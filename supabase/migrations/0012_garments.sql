-- Liste des vêtements (chemise blanche, chaussettes noires…) avec leur photo,
-- dans laquelle on choisit les éléments de chaque tenue.
create table public.garments (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  photo_path text,
  created_at timestamptz not null default now()
);
alter table public.garments enable row level security;
create policy "membres lisent les vêtements" on public.garments
  for select to authenticated using ((select public.is_member()));
create policy "éditeurs gèrent les vêtements" on public.garments
  for all to authenticated using ((select public.is_editor())) with check ((select public.is_editor()));

-- Un élément de tenue renvoie au vêtement (son nom et sa photo viennent de la liste).
alter table public.outfit_items add column garment_id uuid references public.garments(id) on delete cascade;
create index outfit_items_garment_idx on public.outfit_items(garment_id);

-- Les éléments déjà saisis deviennent des vêtements de la liste (un seul par nom).
insert into public.garments (name, photo_path)
select distinct on (lower(trim(label))) trim(label), photo_path
from public.outfit_items
order by lower(trim(label)), photo_path nulls last;
update public.outfit_items i set garment_id = g.id
from public.garments g where lower(trim(i.label)) = lower(g.name);

-- Quelques vêtements de départ
insert into public.garments (name)
select n from (values ('Chemise blanche'), ('Chemise noire'), ('Chaussettes blanches')) v(n)
where not exists (select 1 from public.garments g where lower(g.name) = lower(n));

-- La sauvegarde inclut les vêtements (avant les éléments de tenue qui en dépendent)
create or replace function public.backup_tables() returns text[]
language sql immutable set search_path = '' as $$
  select array[
    'categories', 'profiles', 'songs', 'booklets', 'outfits', 'garments', 'outfit_items', 'events',
    'event_participants', 'notification_log', 'announcements', 'equipment_categories',
    'equipment', 'event_equipment', 'recordings', 'backups'
  ];
$$;
