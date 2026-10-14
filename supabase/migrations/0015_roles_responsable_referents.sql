-- Rôles : Admin, Responsable, Référent Chant Français (valeur 'chef'), Référent Chant Arabe, Membre.
alter type public.member_role add value if not exists 'responsable';
alter type public.member_role add value if not exists 'referent_arabe';
