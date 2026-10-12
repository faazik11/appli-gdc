-- Sauvegarde complète sur l'ordinateur d'un admin, et restauration depuis ce fichier.
-- Les clés privées (app_secrets) et les abonnements des téléphones ne sont jamais exportés.

-- Date de chaque sauvegarde (pour rappeler aux admins d'en refaire une)
create table public.backups (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null default auth.uid()
);
alter table public.backups enable row level security;
create policy "admins voient les sauvegardes" on public.backups
  for select to authenticated using ((select public.is_admin()));

-- Tables sauvegardées, dans l'ordre où on peut les remettre (une table après celles dont elle dépend)
create function public.backup_tables() returns text[]
language sql immutable set search_path = '' as $$
  select array[
    'categories', 'profiles', 'songs', 'booklets', 'outfits', 'outfit_items', 'events',
    'event_participants', 'notification_log', 'announcements', 'equipment_categories',
    'equipment', 'event_equipment', 'recordings', 'backups'
  ];
$$;

-- Tout le contenu de l'appli en un seul objet (admin uniquement)
create function public.backup_export() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  t text;
  v_rows jsonb;
  tables jsonb := '{}';
begin
  if not public.is_admin() then
    raise exception 'Seul un admin peut faire une sauvegarde';
  end if;
  insert into public.backups default values;
  foreach t in array public.backup_tables() loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from public.%I x', t) into v_rows;
    tables := tables || jsonb_build_object(t, v_rows);
  end loop;
  return jsonb_build_object(
    'format', 1,
    'created_at', now(),
    'tables', tables,
    'accounts', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'email', email, 'created_at', created_at)), '[]')
                 from auth.users),
    'files', (select coalesce(jsonb_agg(jsonb_build_object('bucket', bucket_id, 'path', name,
                                                           'type', metadata->>'mimetype', 'size', metadata->>'size')), '[]')
              from storage.objects
              where bucket_id in ('lyrics', 'audio', 'booklets', 'materiel', 'enregistrements'))
  );
end;
$$;
revoke execute on function public.backup_export() from public, anon;

-- Remet ce qui manque depuis une sauvegarde : n'efface et ne remplace jamais rien d'existant.
-- Renvoie le nombre de lignes remises par table.
create function public.backup_restore(data jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  t text;
  v_rows jsonb;
  n integer;
  added jsonb := '{}';
begin
  if not public.is_admin() then
    raise exception 'Seul un admin peut restaurer une sauvegarde';
  end if;
  if (data->>'format')::int is distinct from 1 then
    raise exception 'Ce fichier n''est pas une sauvegarde de l''appli GDC';
  end if;
  -- Pas de notification pour les événements et annonces remis
  perform set_config('gdc.restauration', 'on', true);
  foreach t in array public.backup_tables() loop
    if not (data->'tables' ? t) then continue; end if;
    v_rows := data->'tables'->t;
    -- Comptes qui n'existent plus : la ligne est gardée sans auteur, ou ignorée si elle n'a de sens qu'avec lui
    if t = 'profiles' then
      select coalesce(jsonb_agg(e), '[]') into v_rows from jsonb_array_elements(v_rows) e
        where exists (select 1 from auth.users u where u.id = (e->>'id')::uuid);
    elsif t = 'event_participants' then
      select coalesce(jsonb_agg(e), '[]') into v_rows from jsonb_array_elements(v_rows) e
        where exists (select 1 from public.profiles p where p.id = (e->>'profile_id')::uuid);
    elsif t in ('songs', 'booklets', 'events', 'announcements', 'recordings', 'backups') then
      select coalesce(jsonb_agg(case
          when exists (select 1 from public.profiles p where p.id = (e->>'created_by')::uuid) then e
          else e || '{"created_by": null}' end), '[]')
        into v_rows from jsonb_array_elements(v_rows) e;
    end if;
    execute format('insert into public.%I select * from jsonb_populate_recordset(null::public.%I, $1) on conflict do nothing', t, t)
      using v_rows;
    get diagnostics n = row_count;
    added := added || jsonb_build_object(t, n);
  end loop;
  perform setval(pg_get_serial_sequence('public.categories', 'id'), greatest((select max(id) from public.categories), 1));
  perform set_config('gdc.restauration', 'off', true);
  return added;
end;
$$;
revoke execute on function public.backup_restore(jsonb) from public, anon;

-- Le service d'envoi se tait pendant une restauration
create or replace function public.send_notifications(payload jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_url text := (select value from public.app_secrets where name = 'functions_url');
  v_token text := (select value from public.app_secrets where name = 'notify_token');
begin
  if current_setting('gdc.restauration', true) = 'on' then return; end if;
  if v_url is null or v_token is null then return; end if;
  perform net.http_post(
    url := v_url || '/notifications',
    body := payload,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-gdc-token', v_token)
  );
end;
$$;
revoke execute on function public.send_notifications(jsonb) from public, anon, authenticated;
