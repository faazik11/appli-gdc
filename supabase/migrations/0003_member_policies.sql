alter table public.profiles alter column role set default 'en_attente';

create or replace function public.is_member()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role <> 'en_attente'
  );
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    case when exists (select 1 from public.profiles) then 'en_attente'::public.member_role
         else 'admin'::public.member_role end
  );
  return new;
end;
$$;

alter policy "membres lisent les catégories" on public.categories using ((select public.is_member()));
alter policy "membres lisent les chants" on public.songs using ((select public.is_member()));
alter policy "membres lisent les livrets" on public.booklets using ((select public.is_member()));
alter policy "membres lisent les fichiers" on storage.objects
  using (bucket_id in ('lyrics', 'audio', 'booklets') and (select public.is_member()));

-- Les helpers ne servent qu'aux règles d'accès, pas à l'API publique
revoke execute on function public.is_member() from anon, public;
revoke execute on function public.is_editor() from anon, public;
revoke execute on function public.is_admin() from anon, public;
revoke execute on function public.handle_new_user() from anon, authenticated, public;
revoke execute on function public.guard_role_change() from anon, authenticated, public;
