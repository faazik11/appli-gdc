-- Tâches confiées par le Responsable ou un Référent à certaines personnes, avec un fil de messages par tâche.
-- Chacun ne voit que les tâches qui le concernent ; les éditeurs voient tout.

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(trim(title)) > 0),
  details text,
  due_date date,
  event_id uuid references public.events(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index tasks_event_idx on public.tasks(event_id);
create index tasks_created_by_idx on public.tasks(created_by);

-- Personnes chargées d'une tâche et où elles en sont
create table public.task_assignees (
  task_id uuid not null references public.tasks(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'a_faire' check (status in ('a_faire', 'fait', 'impossible')),
  updated_at timestamptz not null default now(),
  primary key (task_id, profile_id)
);
create index task_assignees_profile_idx on public.task_assignees(profile_id);

create table public.task_messages (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  author_id uuid references public.profiles(id) on delete set null default auth.uid(),
  body text not null check (length(trim(body)) > 0),
  created_at timestamptz not null default now()
);
create index task_messages_task_idx on public.task_messages(task_id, created_at);
create index task_messages_author_idx on public.task_messages(author_id);

-- La personne connectée est chargée de cette tâche
create function public.is_task_assignee(p_task uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.task_assignees where task_id = p_task and profile_id = (select auth.uid()));
$$;
revoke execute on function public.is_task_assignee(uuid) from public, anon;

alter table public.tasks enable row level security;
create policy "tâches visibles par les éditeurs et les personnes chargées" on public.tasks
  for select to authenticated using ((select public.is_editor()) or public.is_task_assignee(id));
create policy "éditeurs créent les tâches" on public.tasks
  for insert to authenticated with check ((select public.is_editor()));
create policy "éditeurs modifient les tâches" on public.tasks
  for update to authenticated using ((select public.is_editor()));
create policy "éditeurs suppriment les tâches" on public.tasks
  for delete to authenticated using ((select public.is_editor()));

alter table public.task_assignees enable row level security;
create policy "personnes chargées visibles" on public.task_assignees
  for select to authenticated using ((select public.is_editor()) or public.is_task_assignee(task_id));
create policy "éditeurs ajoutent des personnes" on public.task_assignees
  for insert to authenticated with check ((select public.is_editor()));
create policy "éditeurs changent l'état" on public.task_assignees
  for update to authenticated using ((select public.is_editor()));
create policy "éditeurs retirent des personnes" on public.task_assignees
  for delete to authenticated using ((select public.is_editor()));

alter table public.task_messages enable row level security;
create policy "messages visibles par ceux de la tâche" on public.task_messages
  for select to authenticated using ((select public.is_editor()) or public.is_task_assignee(task_id));
create policy "ceux de la tâche écrivent" on public.task_messages
  for insert to authenticated
  with check (author_id = (select auth.uid()) and ((select public.is_editor()) or public.is_task_assignee(task_id)));
create policy "on retire ses propres messages" on public.task_messages
  for delete to authenticated using (author_id = (select auth.uid()) or (select public.is_editor()));

-- La personne chargée indique où elle en est (seulement sa propre ligne, seulement l'état)
create function public.set_task_status(p_task uuid, p_status text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_status not in ('a_faire', 'fait', 'impossible') then
    raise exception 'État inconnu';
  end if;
  update public.task_assignees set status = p_status, updated_at = now()
    where task_id = p_task and profile_id = auth.uid();
  if not found then
    raise exception 'Cette tâche ne t''est pas confiée';
  end if;
end;
$$;
revoke execute on function public.set_task_status(uuid, text) from public, anon;

-- Notifications : tâche confiée, réponse « Fait » / « Je ne peux pas », nouveau message
create function public.notify_task_assignee() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    perform public.send_notifications(jsonb_build_object('type', 'task', 'task_id', new.task_id, 'profile_id', new.profile_id));
  elsif new.status is distinct from old.status and new.status <> 'a_faire' then
    perform public.send_notifications(jsonb_build_object('type', 'task_status', 'task_id', new.task_id, 'profile_id', new.profile_id));
  end if;
  return new;
end;
$$;
create trigger task_assignees_notify after insert or update of status on public.task_assignees
  for each row execute function public.notify_task_assignee();

create function public.notify_task_message() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.send_notifications(jsonb_build_object('type', 'task_message', 'id', new.id));
  return new;
end;
$$;
create trigger task_messages_notify after insert on public.task_messages
  for each row execute function public.notify_task_message();

-- Rappels de tâches déjà envoyés
create table public.task_notification_log (
  task_id uuid not null references public.tasks(id) on delete cascade,
  kind text not null,
  sent_at timestamptz not null default now(),
  primary key (task_id, kind)
);
alter table public.task_notification_log enable row level security;
revoke all on public.task_notification_log from anon, authenticated;

-- Sauvegarde : les tâches et leurs messages en font partie
create or replace function public.backup_tables() returns text[]
language sql immutable set search_path = '' as $$
  select array[
    'categories', 'profiles', 'songs', 'booklets', 'outfits', 'garments', 'outfit_items', 'events',
    'event_participants', 'notification_log', 'announcements', 'equipment_categories',
    'equipment', 'event_equipment', 'recordings', 'tasks', 'task_assignees', 'task_messages', 'backups'
  ];
$$;

create or replace function public.backup_restore(data jsonb) returns jsonb
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
  -- Pas de notification pour les événements, annonces et tâches remis
  perform set_config('gdc.restauration', 'on', true);
  foreach t in array public.backup_tables() loop
    if not (data->'tables' ? t) then continue; end if;
    v_rows := data->'tables'->t;
    -- Comptes qui n'existent plus : la ligne est gardée sans auteur, ou ignorée si elle n'a de sens qu'avec lui
    if t = 'profiles' then
      select coalesce(jsonb_agg(e), '[]') into v_rows from jsonb_array_elements(v_rows) e
        where exists (select 1 from auth.users u where u.id = (e->>'id')::uuid);
    elsif t in ('event_participants', 'task_assignees') then
      select coalesce(jsonb_agg(e), '[]') into v_rows from jsonb_array_elements(v_rows) e
        where exists (select 1 from public.profiles p where p.id = (e->>'profile_id')::uuid);
    elsif t in ('songs', 'booklets', 'events', 'announcements', 'recordings', 'tasks', 'backups') then
      select coalesce(jsonb_agg(case
          when exists (select 1 from public.profiles p where p.id = (e->>'created_by')::uuid) then e
          else e || '{"created_by": null}' end), '[]')
        into v_rows from jsonb_array_elements(v_rows) e;
    elsif t = 'task_messages' then
      select coalesce(jsonb_agg(case
          when exists (select 1 from public.profiles p where p.id = (e->>'author_id')::uuid) then e
          else e || '{"author_id": null}' end), '[]')
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
