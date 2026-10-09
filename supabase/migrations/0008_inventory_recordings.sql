-- Inventaire du matériel du local (catégories créées par le chef de chœur)
create table public.equipment_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (length(trim(name)) > 0),
  created_at timestamptz not null default now()
);
create table public.equipment (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  category_id uuid references public.equipment_categories(id) on delete set null,
  quantity integer not null default 1 check (quantity >= 0),
  notes text,
  photo_path text,
  created_at timestamptz not null default now()
);
create index equipment_category_idx on public.equipment(category_id);

-- Enregistrements des répétitions, datés automatiquement, avec les points abordés
create table public.recordings (
  id uuid primary key default gen_random_uuid(),
  recorded_at timestamptz not null default now(),
  event_id uuid references public.events(id) on delete set null,
  title text,
  notes text,
  audio_path text not null,
  duration_seconds integer,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index recordings_event_idx on public.recordings(event_id);
create index recordings_created_by_idx on public.recordings(created_by);

alter table public.equipment_categories enable row level security;
alter table public.equipment enable row level security;
alter table public.recordings enable row level security;

create policy "membres lisent les catégories de matériel" on public.equipment_categories
  for select to authenticated using ((select public.is_member()));
create policy "éditeurs gèrent les catégories de matériel" on public.equipment_categories
  for all to authenticated using ((select public.is_editor())) with check ((select public.is_editor()));
create policy "membres lisent le matériel" on public.equipment
  for select to authenticated using ((select public.is_member()));
create policy "éditeurs gèrent le matériel" on public.equipment
  for all to authenticated using ((select public.is_editor())) with check ((select public.is_editor()));
create policy "membres lisent les enregistrements" on public.recordings
  for select to authenticated using ((select public.is_member()));
create policy "éditeurs gèrent les enregistrements" on public.recordings
  for all to authenticated using ((select public.is_editor())) with check ((select public.is_editor()));

-- Fichiers : photos du matériel, enregistrements (≈ 22 Mo pour 2 h)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('materiel', 'materiel', false, 10485760, array['image/jpeg','image/png','image/webp','image/heic']),
  ('enregistrements', 'enregistrements', false, 52428800, array['audio/webm','audio/mp4','audio/ogg','audio/mpeg','audio/aac','audio/x-m4a']);

alter policy "membres lisent les fichiers" on storage.objects
  using (bucket_id in ('lyrics', 'audio', 'booklets', 'materiel', 'enregistrements'));
alter policy "éditeurs déposent des fichiers" on storage.objects
  with check (bucket_id in ('lyrics', 'audio', 'booklets', 'materiel', 'enregistrements') and (select public.is_editor()));
alter policy "éditeurs remplacent des fichiers" on storage.objects
  using (bucket_id in ('lyrics', 'audio', 'booklets', 'materiel', 'enregistrements') and (select public.is_editor()));
alter policy "éditeurs suppriment des fichiers" on storage.objects
  using (bucket_id in ('lyrics', 'audio', 'booklets', 'materiel', 'enregistrements') and (select public.is_editor()));
