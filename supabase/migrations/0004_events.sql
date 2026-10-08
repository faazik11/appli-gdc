-- Agenda : répétitions et prestations, réponses des membres et présences réelles
create type public.event_kind as enum ('repetition', 'prestation');
create type public.event_response as enum ('present', 'peut_etre', 'absent');

create table public.events (
  id uuid primary key default gen_random_uuid(),
  kind public.event_kind not null default 'repetition',
  title text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  location text,
  notes text,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index events_starts_at_idx on public.events(starts_at);
create index events_created_by_idx on public.events(created_by);

-- response : ce que le membre a annoncé ; attended : présence notée par le chef (null = pas encore fait)
create table public.event_participants (
  event_id uuid not null references public.events(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  response public.event_response,
  attended boolean,
  updated_at timestamptz not null default now(),
  primary key (event_id, profile_id)
);
create index event_participants_profile_idx on public.event_participants(profile_id);

alter table public.events enable row level security;
alter table public.event_participants enable row level security;

create policy "membres lisent les événements" on public.events
  for select to authenticated using ((select public.is_member()));
create policy "éditeurs créent les événements" on public.events
  for insert to authenticated with check ((select public.is_editor()));
create policy "éditeurs modifient les événements" on public.events
  for update to authenticated using ((select public.is_editor())) with check ((select public.is_editor()));
create policy "éditeurs suppriment les événements" on public.events
  for delete to authenticated using ((select public.is_editor()));

create policy "membres lisent les participations" on public.event_participants
  for select to authenticated using ((select public.is_member()));
create policy "chacun répond pour soi, les éditeurs pour tous" on public.event_participants
  for insert to authenticated
  with check ((select public.is_member()) and (profile_id = (select auth.uid()) or (select public.is_editor())));
create policy "chacun modifie sa réponse, les éditeurs tout" on public.event_participants
  for update to authenticated
  using ((select public.is_member()) and (profile_id = (select auth.uid()) or (select public.is_editor())))
  with check ((select public.is_member()) and (profile_id = (select auth.uid()) or (select public.is_editor())));

-- Seuls les chefs et admins notent les présences réelles
create or replace function public.guard_attendance()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_editor() then
    if tg_op = 'INSERT' and new.attended is not null then
      raise exception 'Seul le chef de chœur note les présences';
    end if;
    if tg_op = 'UPDATE' and new.attended is distinct from old.attended then
      raise exception 'Seul le chef de chœur note les présences';
    end if;
  end if;
  new.updated_at = now();
  return new;
end;
$$;
revoke execute on function public.guard_attendance() from anon, authenticated, public;

create trigger event_participants_guard before insert or update on public.event_participants
  for each row execute function public.guard_attendance();
