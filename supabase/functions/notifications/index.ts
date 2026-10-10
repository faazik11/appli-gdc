// Envoi des notifications sur les téléphones (Web Push).
// Appelé par la base : nouvel événement, nouvelle annonce, et toutes les heures pour les rappels.
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const APP_URL = "https://faazik11.github.io/appli-gdc/";
const TZ = "Europe/Paris";

type Msg = { title: string; body: string; url?: string; tag?: string };

async function secrets(): Promise<Record<string, string>> {
  const { data } = await db.from("app_secrets").select("name, value");
  return Object.fromEntries((data ?? []).map((r) => [r.name, r.value]));
}

/** Jour (AAAA-MM-JJ) et heure à Paris. */
function paris(d: Date) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", hourCycle: "h23",
    }).formatToParts(d).map((p) => [p.type, p.value]),
  );
  return { day: `${parts.year}-${parts.month}-${parts.day}`, hour: Number(parts.hour) };
}

const dayLabel = (d: Date) =>
  new Intl.DateTimeFormat("fr-FR", { timeZone: TZ, weekday: "long", day: "numeric", month: "long" }).format(d);
const timeLabel = (d: Date) =>
  new Intl.DateTimeFormat("fr-FR", { timeZone: TZ, hour: "2-digit", minute: "2-digit" }).format(d).replace(":", "h");

function eventName(e: { kind: string; title: string | null }) {
  if (e.title?.trim()) return e.title.trim();
  return e.kind === "prestation" ? "Prestation" : "Répétition";
}

/** Membres validés (pas en attente), éventuellement filtrés. */
async function members(): Promise<string[]> {
  const { data } = await db.from("profiles").select("id, role");
  return (data ?? []).filter((p) => p.role !== "en_attente").map((p) => p.id);
}

async function send(profileIds: string[], msg: Msg) {
  if (profileIds.length === 0) return 0;
  const { data: subs } = await db.from("push_subscriptions").select("id, endpoint, p256dh, auth").in("profile_id", profileIds);
  let sent = 0;
  await Promise.all((subs ?? []).map(async (s) => {
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
        JSON.stringify({ ...msg, url: msg.url ?? APP_URL }),
        { TTL: 60 * 60 * 12, urgency: "normal" },
      );
      sent++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      // Abonnement expiré (appli supprimée, notifications coupées) : on l'oublie.
      if (code === 404 || code === 410) await db.from("push_subscriptions").delete().eq("id", s.id);
      else console.error("envoi impossible", code, String(e));
    }
  }));
  return sent;
}

/** Note l'envoi ; renvoie false s'il a déjà été fait. */
async function once(eventId: string, kind: string) {
  const { error } = await db.from("notification_log").insert({ event_id: eventId, kind });
  return !error;
}

async function onEvent(id: string) {
  const { data: e } = await db.from("events").select("*").eq("id", id).single();
  if (!e || new Date(e.starts_at) < new Date()) return 0;
  if (!(await once(e.id, "nouveau"))) return 0;
  const start = new Date(e.starts_at);
  const who = (await members()).filter((m) => m !== e.created_by);
  return send(who, {
    title: e.kind === "prestation" ? `Nouvelle prestation : ${eventName(e)}` : "Nouvelle répétition",
    body: `${dayLabel(start)} à ${timeLabel(start)}${e.location ? ` · ${e.location}` : ""}. Dis si tu viens dans l'agenda.`,
    tag: `event-${e.id}`,
  });
}

async function onAnnouncement(id: string) {
  const { data: a } = await db.from("announcements").select("*").eq("id", id).single();
  if (!a) return 0;
  const who = (await members()).filter((m) => m !== a.created_by);
  const body = a.body.length > 180 ? a.body.slice(0, 177) + "…" : a.body;
  return send(who, { title: "Nouvelle annonce", body, tag: `annonce-${a.id}` });
}

async function reminders(force: boolean) {
  const now = new Date();
  const today = paris(now);
  if (!force && today.hour !== 18) return 0;
  const { data: events } = await db.from("events").select("*, event_participants(profile_id, response)")
    .gte("starts_at", now.toISOString())
    .lte("starts_at", new Date(now.getTime() + 4 * 86400000).toISOString());
  const all = await members();
  let sent = 0;
  const dayIn = (n: number) => paris(new Date(now.getTime() + n * 86400000)).day;
  for (const e of events ?? []) {
    const start = new Date(e.starts_at);
    const day = paris(start).day;
    const parts = (e.event_participants ?? []) as { profile_id: string; response: string | null }[];
    // Veille : tout le monde sauf ceux qui ont dit qu'ils seraient absents
    if (day === dayIn(1) && (await once(e.id, "veille"))) {
      const absent = new Set(parts.filter((p) => p.response === "absent").map((p) => p.profile_id));
      sent += await send(all.filter((m) => !absent.has(m)), {
        title: e.kind === "prestation" ? `Demain : ${eventName(e)}` : "Répétition demain",
        body: `${timeLabel(start)}${e.location ? ` · ${e.location}` : ""}${e.notes ? ` · ${e.notes}` : ""}`.slice(0, 180),
        tag: `veille-${e.id}`,
      });
    }
    // 3 jours avant une prestation : relance de ceux qui n'ont pas répondu
    if (e.kind === "prestation" && day === dayIn(3) && (await once(e.id, "relance"))) {
      const answered = new Set(parts.filter((p) => p.response).map((p) => p.profile_id));
      sent += await send(all.filter((m) => !answered.has(m)), {
        title: `${eventName(e)} : tu viens ?`,
        body: `${dayLabel(start)} à ${timeLabel(start)}. Réponds dans l'agenda pour que le chef de chœur puisse s'organiser.`,
        tag: `relance-${e.id}`,
      });
    }
  }
  return sent;
}

Deno.serve(async (req) => {
  const keys = await secrets();
  if (req.headers.get("x-gdc-token") !== keys.notify_token) return new Response("interdit", { status: 403 });
  webpush.setVapidDetails(APP_URL, keys.vapid_public, keys.vapid_private);
  const p = await req.json().catch(() => ({}));
  let sent = 0;
  if (p.type === "event") sent = await onEvent(p.id);
  else if (p.type === "announcement") sent = await onAnnouncement(p.id);
  else if (p.type === "reminders") sent = await reminders(p.force === true);
  else if (p.type === "test" && p.profile_id) {
    sent = await send([p.profile_id], { title: "Notifications activées", body: "Tu recevras les rappels du Groupe de Chant Narbonne." });
  }
  return Response.json({ sent });
});
