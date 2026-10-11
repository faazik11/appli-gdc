-- Matériel à emporter pour une prestation (pris dans l'inventaire), coché au chargement
create table public.event_equipment (
  event_id uuid not null references public.events(id) on delete cascade,
  equipment_id uuid not null references public.equipment(id) on delete cascade,
  quantity integer not null default 1 check (quantity > 0),
  packed boolean not null default false,
  primary key (event_id, equipment_id)
);
create index event_equipment_equipment_idx on public.event_equipment(equipment_id);

-- Tenues réutilisables : une photo d'ensemble et les éléments, chacun avec sa petite photo
create table public.outfits (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  notes text,
  photo_path text,
  created_at timestamptz not null default now()
);
create table public.outfit_items (
  id uuid primary key default gen_random_uuid(),
  outfit_id uuid not null references public.outfits(id) on delete cascade,
  label text not null check (length(trim(label)) > 0),
  photo_path text,
  position integer not null default 0
);
create index outfit_items_outfit_idx on public.outfit_items(outfit_id);

-- Tenue du jour d'un événement
alter table public.events add column outfit_id uuid references public.outfits(id) on delete set null;
create index events_outfit_idx on public.events(outfit_id);

alter table public.event_equipment enable row level security;
alter table public.outfits enable row level security;
alter table public.outfit_items enable row level security;

create policy "membres lisent le matériel des événements" on public.event_equipment
  for select to authenticated using ((select public.is_member()));
create policy "éditeurs gèrent le matériel des événements" on public.event_equipment
  for all to authenticated using ((select public.is_editor())) with check ((select public.is_editor()));
create policy "membres lisent les tenues" on public.outfits
  for select to authenticated using ((select public.is_member()));
create policy "éditeurs gèrent les tenues" on public.outfits
  for all to authenticated using ((select public.is_editor())) with check ((select public.is_editor()));
create policy "membres lisent les éléments de tenue" on public.outfit_items
  for select to authenticated using ((select public.is_member()));
create policy "éditeurs gèrent les éléments de tenue" on public.outfit_items
  for all to authenticated using ((select public.is_editor())) with check ((select public.is_editor()));
-- Les photos des tenues vont dans le dossier « tenues/ » du stockage « materiel ».
