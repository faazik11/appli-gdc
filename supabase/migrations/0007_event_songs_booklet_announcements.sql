-- Chants à travailler pour une répétition, livret d'une prestation
alter table public.events add column song_ids uuid[] not null default '{}';
alter table public.events add column booklet_id uuid references public.booklets(id) on delete set null;
create index events_booklet_idx on public.events(booklet_id);

-- Annonces du chef de chœur, affichées en haut de l'accueil
create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  body text not null check (length(trim(body)) > 0),
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index announcements_created_by_idx on public.announcements(created_by);
alter table public.announcements enable row level security;
create policy "membres lisent les annonces" on public.announcements
  for select to authenticated using ((select public.is_member()));
create policy "éditeurs publient les annonces" on public.announcements
  for insert to authenticated with check ((select public.is_editor()));
create policy "éditeurs suppriment les annonces" on public.announcements
  for delete to authenticated using ((select public.is_editor()));
