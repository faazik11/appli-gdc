-- Qui vient : réponses de tous, visibles des membres (sans les présences notées à l'appel).
create or replace function public.event_responses()
returns table (event_id uuid, profile_id uuid, response public.event_response)
language sql stable security definer set search_path = ''
as $$
  select p.event_id, p.profile_id, p.response
  from public.event_participants p
  where public.is_member() and p.response is not null;
$$;
revoke execute on function public.event_responses() from anon, public;
grant execute on function public.event_responses() to authenticated;
