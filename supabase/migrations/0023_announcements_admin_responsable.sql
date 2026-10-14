-- Seuls l'admin et le responsable écrivent et retirent les annonces ; tout le groupe les lit.
create or replace function public.is_announcer()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid())
      and role in ('admin', 'responsable')
  );
$$;

alter policy "éditeurs publient les annonces" on public.announcements
  with check ((select public.is_announcer()));
alter policy "éditeurs suppriment les annonces" on public.announcements
  using ((select public.is_announcer()));
