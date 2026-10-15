-- Repères dans les enregistrements de répète : [{"s": secondes, "label": "Nom du chant"}].
alter table public.recordings add column if not exists markers jsonb not null default '[]'::jsonb;
