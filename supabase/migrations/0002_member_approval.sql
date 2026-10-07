-- Les nouveaux comptes attendent la validation d'un admin avant de voir la bibliothèque
alter type public.member_role add value if not exists 'en_attente';
