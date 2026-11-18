-- Corrections des paroles faites dans l'appli (bouton « Modifier » sur la page du chant).
-- Le PDF d'origine est gardé tel quel ; songs.lyrics_pdf_path pointe vers la version corrigée.
create table public.lyrics_corrections (
  song_id uuid primary key references public.songs(id) on delete cascade,
  original_path text not null,
  -- { "page:ligne:morceau": { "t": "nouveau texte", "c": "rrggbb" } }
  edits jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);

alter table public.lyrics_corrections enable row level security;

create policy "membres lisent les corrections" on public.lyrics_corrections
  for select to authenticated using ((select public.is_member()));
create policy "éditeurs ajoutent des corrections" on public.lyrics_corrections
  for insert to authenticated with check ((select public.is_editor()));
create policy "éditeurs modifient les corrections" on public.lyrics_corrections
  for update to authenticated using ((select public.is_editor()));
create policy "éditeurs retirent les corrections" on public.lyrics_corrections
  for delete to authenticated using ((select public.is_editor()));

-- Comprises dans la sauvegarde (Membres › Sauvegarde)
create or replace function public.backup_tables() returns text[]
language sql immutable set search_path = '' as $$
  select array[
    'categories', 'profiles', 'songs', 'lyrics_corrections', 'booklets', 'outfits', 'garments', 'outfit_items', 'events',
    'event_participants', 'notification_log', 'announcements', 'equipment_categories',
    'equipment', 'event_equipment', 'recordings', 'videos', 'tasks', 'task_assignees', 'task_messages', 'backups'
  ];
$$;
