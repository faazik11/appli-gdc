// Fichiers des enregistrements de répète, rangés chez Cloudflare R2 (10 Go gratuits).
// L'appli ne voit jamais les clés R2 : cette fonction vérifie le compte puis donne un lien signé
// valable 1 h pour lire ou déposer un fichier directement chez R2.
// Les clés sont dans la table app_secrets (r2_endpoint, r2_access_key_id, r2_secret_access_key, r2_bucket).
import { createClient } from "npm:@supabase/supabase-js@2";
import { AwsClient } from "npm:aws4fetch@1.0.20";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const SUPABASE_BUCKET = "enregistrements";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-gdc-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

async function secrets(): Promise<Record<string, string>> {
  const { data } = await db.from("app_secrets").select("name, value");
  return Object.fromEntries((data ?? []).map((r) => [r.name, r.value]));
}

/** Droits du compte qui appelle, d'après les mêmes règles que la base (null si pas membre validé). */
async function rightsOf(req: Request): Promise<{ editor: boolean; admin: boolean } | null> {
  const auth = req.headers.get("Authorization");
  if (!auth) return null;
  const as = createClient(Deno.env.get("SUPABASE_URL")!, req.headers.get("apikey") ?? Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
  });
  const [member, editor, admin] = await Promise.all([as.rpc("is_member"), as.rpc("is_editor"), as.rpc("is_admin")]);
  if (member.data !== true) return null;
  return { editor: editor.data === true, admin: admin.data === true };
}

const cleanPath = (p: unknown) => {
  const s = String(p ?? "");
  if (!s || s.includes("..") || s.startsWith("/") || s.length > 300) throw new Error("chemin invalide");
  return s;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const s = await secrets();
    const body = await req.json().catch(() => ({}));
    const action = String(body.action ?? "");
    const fromDb = s.notify_token && req.headers.get("x-gdc-token") === s.notify_token;
    const rights = fromDb ? { editor: true, admin: true } : await rightsOf(req);
    if (!rights) return json({ error: "Connexion requise" }, 401);
    if (!s.r2_endpoint || !s.r2_access_key_id || !s.r2_secret_access_key) return json({ error: "R2 pas encore configuré" }, 503);

    const r2 = new AwsClient({ accessKeyId: s.r2_access_key_id, secretAccessKey: s.r2_secret_access_key, service: "s3", region: "auto" });
    const base = `${s.r2_endpoint.replace(/\/$/, "")}/${s.r2_bucket || "gdc-enregistrements"}`;
    const objectUrl = (path: string) => `${base}/${path.split("/").map(encodeURIComponent).join("/")}`;
    const signed = async (path: string, method: string, type?: string) => {
      const url = new URL(objectUrl(path));
      url.searchParams.set("X-Amz-Expires", "3600");
      const r = await r2.sign(url.toString(), {
        method,
        headers: type ? { "Content-Type": type } : undefined,
        aws: { signQuery: true },
      });
      return r.url;
    };
    const { editor, admin } = rights;

    switch (action) {
      // Lien de lecture (tous les membres).
      case "lire":
        return json({ url: await signed(cleanPath(body.path), "GET") });

      // Lien de dépôt (éditeurs).
      case "deposer": {
        if (!editor) return json({ error: "Ton rôle ne permet pas de faire ça." }, 403);
        const type = String(body.type || "application/octet-stream");
        return json({ url: await signed(cleanPath(body.path), "PUT", type) });
      }

      // Le fichier existe-t-il déjà ? (restauration d'une sauvegarde)
      case "existe": {
        if (!editor) return json({ error: "Ton rôle ne permet pas de faire ça." }, 403);
        const r = await r2.fetch(objectUrl(cleanPath(body.path)), { method: "HEAD" });
        return json({ existe: r.ok });
      }

      case "supprimer": {
        if (!editor) return json({ error: "Ton rôle ne permet pas de faire ça." }, 403);
        for (const p of (body.paths ?? []) as unknown[]) {
          await r2.fetch(objectUrl(cleanPath(p)), { method: "DELETE" });
        }
        return json({ ok: true });
      }

      // Liste des fichiers avec leur taille (admins : jauge et sauvegarde).
      case "liste": {
        if (!admin) return json({ error: "Réservé aux admins" }, 403);
        const files: { path: string; size: number }[] = [];
        let token: string | null = null;
        do {
          const url = new URL(base);
          url.searchParams.set("list-type", "2");
          if (token) url.searchParams.set("continuation-token", token);
          const xml = await (await r2.fetch(url.toString())).text();
          for (const m of xml.matchAll(/<Contents>([\s\S]*?)<\/Contents>/g)) {
            const key = m[1].match(/<Key>([\s\S]*?)<\/Key>/)?.[1] ?? "";
            const size = Number(m[1].match(/<Size>(\d+)<\/Size>/)?.[1] ?? 0);
            files.push({ path: key.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'"), size });
          }
          token = /<IsTruncated>true<\/IsTruncated>/.test(xml)
            ? xml.match(/<NextContinuationToken>([\s\S]*?)<\/NextContinuationToken>/)?.[1] ?? null
            : null;
        } while (token);
        return json({ files });
      }

      // Copie chez R2 d'un fichier encore chez Supabase (déménagement, un fichier par appel).
      case "copier": {
        if (!admin) return json({ error: "Réservé aux admins" }, 403);
        const path = cleanPath(body.path);
        const { data, error } = await db.storage.from(SUPABASE_BUCKET).download(path);
        if (error || !data) return json({ error: `introuvable chez Supabase : ${path}` }, 404);
        const put = await r2.fetch(objectUrl(path), {
          method: "PUT",
          body: await data.arrayBuffer(),
          headers: { "Content-Type": data.type || "application/octet-stream" },
        });
        if (!put.ok) return json({ error: `R2 a refusé (${put.status}) : ${await put.text()}` }, 502);
        const head = await r2.fetch(objectUrl(path), { method: "HEAD" });
        return json({ path, size: data.size, r2Size: Number(head.headers.get("content-length") ?? -1) });
      }

      default:
        return json({ error: "action inconnue" }, 400);
    }
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
