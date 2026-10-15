-- Place occupée par les fichiers, par espace (en octets), pour la jauge de stockage des admins.
create or replace function public.storage_usage()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Réservé aux admins';
  end if;
  return coalesce((
    select jsonb_object_agg(bucket_id, bytes)
    from (
      select bucket_id, sum(coalesce((metadata->>'size')::bigint, 0)) as bytes
      from storage.objects
      group by bucket_id
    ) t
  ), '{}'::jsonb);
end;
$$;

revoke execute on function public.storage_usage() from public, anon;
grant execute on function public.storage_usage() to authenticated;
