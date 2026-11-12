-- Vidéos des prestations. Les fichiers sont chez Cloudflare R2 (dossier videos/ du bucket des
-- enregistrements), seule la fiche est ici.
create table public.videos (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  event_id uuid references public.events(id) on delete set null,
  filmed_on date,
  path text not null,
  content_type text,
  size_bytes bigint,
  duration_seconds integer,
  notes text,
  created_at timestamptz not null default now()
);
create index videos_event_id_idx on public.videos(event_id);
alter table public.videos enable row level security;
create policy "membres regardent les vidéos" on public.videos
  for select to authenticated using ((select public.is_member()));
create policy "éditeurs gèrent les vidéos" on public.videos
  for all to authenticated using ((select public.is_editor())) with check ((select public.is_editor()));

-- Les fiches des vidéos font partie de la sauvegarde (pas les fichiers, trop lourds pour un .zip)
create or replace function public.backup_tables() returns text[]
language sql immutable set search_path = '' as $$
  select array[
    'categories', 'profiles', 'songs', 'booklets', 'outfits', 'garments', 'outfit_items', 'events',
    'event_participants', 'notification_log', 'announcements', 'equipment_categories',
    'equipment', 'event_equipment', 'recordings', 'videos', 'tasks', 'task_assignees', 'task_messages', 'backups'
  ];
$$;
