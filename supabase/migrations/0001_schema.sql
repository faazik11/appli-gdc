-- Rôles des membres
create type public.member_role as enum ('admin', 'chef', 'membre');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role public.member_role not null default 'membre',
  created_at timestamptz not null default now()
);

create table public.categories (
  id smallserial primary key,
  name text not null unique,
  position smallint not null default 0
);

insert into public.categories (name, position) values
  ('Chants Français', 1),
  ('Chants Arabe', 2),
  ('Chants Mariage', 3),
  ('Chants International', 4),
  ('Livrets', 5);

create table public.songs (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category_id smallint not null references public.categories(id),
  lyrics_pdf_path text,
  youtube_url text,
  audio_path text,
  tags text[] not null default '{}',
  notes text,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index songs_category_idx on public.songs(category_id);
create index songs_created_by_idx on public.songs(created_by);

-- Livret : structure = [{ "part": "Entrée", "songs": ["<uuid>", ...] }, ...]
create table public.booklets (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  event_date date,
  structure jsonb not null default '[]',
  pdf_path text,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index booklets_created_by_idx on public.booklets(created_by);

-- Helpers
create or replace function public.is_editor()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role in ('admin', 'chef')
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;

create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = ''
as $$ begin new.updated_at = now(); return new; end; $$;

create trigger songs_touch before update on public.songs
  for each row execute function public.touch_updated_at();
create trigger booklets_touch before update on public.booklets
  for each row execute function public.touch_updated_at();

-- Profil créé automatiquement à l'inscription ; le tout premier compte devient admin
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    case when exists (select 1 from public.profiles) then 'membre'::public.member_role
         else 'admin'::public.member_role end
  );
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- RLS
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.songs enable row level security;
alter table public.booklets enable row level security;

create policy "membres lisent les profils" on public.profiles
  for select to authenticated using (true);
create policy "chacun modifie son nom" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()))
  with check (id = (select auth.uid()) or (select public.is_admin()));

create policy "membres lisent les catégories" on public.categories
  for select to authenticated using (true);

create policy "membres lisent les chants" on public.songs
  for select to authenticated using (true);
create policy "éditeurs ajoutent des chants" on public.songs
  for insert to authenticated with check ((select public.is_editor()));
create policy "éditeurs modifient les chants" on public.songs
  for update to authenticated using ((select public.is_editor())) with check ((select public.is_editor()));
create policy "éditeurs suppriment les chants" on public.songs
  for delete to authenticated using ((select public.is_editor()));

create policy "membres lisent les livrets" on public.booklets
  for select to authenticated using (true);
create policy "éditeurs ajoutent des livrets" on public.booklets
  for insert to authenticated with check ((select public.is_editor()));
create policy "éditeurs modifient les livrets" on public.booklets
  for update to authenticated using ((select public.is_editor())) with check ((select public.is_editor()));
create policy "éditeurs suppriment les livrets" on public.booklets
  for delete to authenticated using ((select public.is_editor()));

-- Un membre ne peut pas changer son propre rôle (seul un admin le peut)
create or replace function public.guard_role_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.role is distinct from old.role and not public.is_admin() then
    raise exception 'Seul un admin peut changer un rôle';
  end if;
  return new;
end;
$$;
create trigger profiles_guard_role before update on public.profiles
  for each row execute function public.guard_role_change();

-- Stockage : paroles (PDF), audio, livrets ; privés, lisibles par les membres
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('lyrics', 'lyrics', false, 20971520, array['application/pdf']),
  ('audio', 'audio', false, 52428800, array['audio/mpeg','audio/mp4','audio/x-m4a','audio/aac','audio/wav','audio/x-wav','audio/ogg','audio/flac']),
  ('booklets', 'booklets', false, 52428800, array['application/pdf']);

create policy "membres lisent les fichiers" on storage.objects
  for select to authenticated using (bucket_id in ('lyrics', 'audio', 'booklets'));
create policy "éditeurs déposent des fichiers" on storage.objects
  for insert to authenticated with check (bucket_id in ('lyrics', 'audio', 'booklets') and (select public.is_editor()));
create policy "éditeurs remplacent des fichiers" on storage.objects
  for update to authenticated using (bucket_id in ('lyrics', 'audio', 'booklets') and (select public.is_editor()));
create policy "éditeurs suppriment des fichiers" on storage.objects
  for delete to authenticated using (bucket_id in ('lyrics', 'audio', 'booklets') and (select public.is_editor()));
