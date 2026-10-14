-- Rôles : ajout de Référent Sono et Référent Artistique.
alter type public.member_role add value if not exists 'referent_sono';
alter type public.member_role add value if not exists 'referent_artistique';
