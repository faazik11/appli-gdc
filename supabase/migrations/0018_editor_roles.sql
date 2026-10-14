-- Responsable et tous les Référents ont les droits d'édition (hors gestion des membres, réservée à l'Admin).
create or replace function public.is_editor()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid())
      and role in ('admin', 'responsable', 'chef', 'referent_arabe', 'referent_sono', 'referent_artistique')
  );
$$;
