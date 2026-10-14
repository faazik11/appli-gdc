-- Note de départ enregistrée pour chaque chant (fichier dans le bucket « enregistrements », dossier notes/)
alter table public.songs add column note_audio_path text;
