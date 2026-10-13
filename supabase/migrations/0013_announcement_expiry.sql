-- Durée d'affichage d'une annonce sur l'accueil (choisie à la création ; vide = sans fin)
alter table public.announcements add column expires_at timestamptz;
