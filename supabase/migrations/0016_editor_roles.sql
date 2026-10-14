-- Responsable et les deux Référents ont les mêmes droits d'édition que l'Admin (hors gestion des membres).
create or replace function public.is_editor()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid())
      and role in ('admin', 'responsable', 'chef', 'referent_arabe')
  );
$$;
