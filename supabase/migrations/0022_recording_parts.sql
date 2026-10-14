-- Suites d'un enregistrement de répétition : fichiers importés (Dictaphone…) ou autre enregistrement
-- ajouté à la suite, lus l'un après l'autre. [{"path": "...", "seconds": 1234}, …]
-- duration_seconds reste la durée totale.
alter table public.recordings add column extra_parts jsonb not null default '[]'::jsonb;

-- Formats acceptés pour les fichiers importés depuis le téléphone ou un ordinateur
update storage.buckets
  set allowed_mime_types = array['audio/webm','audio/mp4','audio/ogg','audio/mpeg','audio/aac','audio/x-m4a',
                                 'audio/wav','audio/x-wav','audio/flac']
  where id = 'enregistrements';
