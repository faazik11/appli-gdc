-- Un membre ne lit que ses propres réponses et présences ; chefs et admins lisent tout.
alter policy "membres lisent les participations" on public.event_participants
  using ((select public.is_member()) and (profile_id = (select auth.uid()) or (select public.is_editor())));

-- Totaux par événement, visibles de tous les membres (combien on sera), sans les noms.
create or replace function public.event_counts()
returns table (event_id uuid, present int, peut_etre int, absent int, attended int, roll_call_done boolean)
language sql stable security definer set search_path = ''
as $$
  select p.event_id,
         count(*) filter (where p.response = 'present')::int,
         count(*) filter (where p.response = 'peut_etre')::int,
         count(*) filter (where p.response = 'absent')::int,
         count(*) filter (where p.attended)::int,
         bool_or(p.attended is not null)
  from public.event_participants p
  where public.is_member()
  group by p.event_id;
$$;
revoke execute on function public.event_counts() from anon, public;
grant execute on function public.event_counts() to authenticated;
