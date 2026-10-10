-- Notifications sur les téléphones (Web Push) : abonnements, envois automatiques.
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

-- Un abonnement par téléphone (navigateur ou icône GDC installée)
create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now()
);
create index push_subscriptions_profile_idx on public.push_subscriptions(profile_id);
alter table public.push_subscriptions enable row level security;
create policy "chacun voit ses abonnements" on public.push_subscriptions
  for select to authenticated using (profile_id = (select auth.uid()));
create policy "chacun retire ses abonnements" on public.push_subscriptions
  for delete to authenticated using (profile_id = (select auth.uid()));

-- Enregistre l'abonnement du téléphone pour la personne connectée (remplace celui d'un autre compte sur le même téléphone)
create function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text)
returns void language sql security definer set search_path = '' as $$
  insert into public.push_subscriptions (profile_id, endpoint, p256dh, auth)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth)
  on conflict (endpoint) do update
    set profile_id = auth.uid(), p256dh = excluded.p256dh, auth = excluded.auth;
$$;
revoke execute on function public.save_push_subscription(text, text, text) from public, anon;

-- Valeurs privées (clés d'envoi) : aucune règle d'accès, seul le serveur les lit.
-- Les valeurs sont saisies directement dans la base, jamais dans ce dépôt public.
create table public.app_secrets (name text primary key, value text not null);
alter table public.app_secrets enable row level security;
revoke all on public.app_secrets from anon, authenticated;

-- Rappels déjà envoyés (pour ne jamais envoyer deux fois le même)
create table public.notification_log (
  event_id uuid not null references public.events(id) on delete cascade,
  kind text not null,
  sent_at timestamptz not null default now(),
  primary key (event_id, kind)
);
alter table public.notification_log enable row level security;
revoke all on public.notification_log from anon, authenticated;

-- Appelle le service d'envoi
create function public.send_notifications(payload jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_url text := (select value from public.app_secrets where name = 'functions_url');
  v_token text := (select value from public.app_secrets where name = 'notify_token');
begin
  if v_url is null or v_token is null then return; end if;
  perform net.http_post(
    url := v_url || '/notifications',
    body := payload,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-gdc-token', v_token)
  );
end;
$$;
revoke execute on function public.send_notifications(jsonb) from public, anon, authenticated;

create function public.notify_new_event() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.send_notifications(jsonb_build_object('type', 'event', 'id', new.id));
  return new;
end;
$$;
create trigger events_notify after insert on public.events
  for each row execute function public.notify_new_event();

create function public.notify_new_announcement() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.send_notifications(jsonb_build_object('type', 'announcement', 'id', new.id));
  return new;
end;
$$;
create trigger announcements_notify after insert on public.announcements
  for each row execute function public.notify_new_announcement();

-- Toutes les heures : le service n'envoie les rappels qu'à 18 h (heure de Paris)
select cron.schedule('gdc-rappels', '0 * * * *', $$select public.send_notifications('{"type":"reminders"}'::jsonb)$$);

-- Notification de bienvenue juste après l'activation, pour vérifier que ça marche
create function public.test_push() returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.send_notifications(jsonb_build_object('type', 'test', 'profile_id', auth.uid()));
end;
$$;
revoke execute on function public.test_push() from public, anon;
