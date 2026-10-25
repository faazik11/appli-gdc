-- Notification « Nouveau chant » : envoyée seulement si celui qui ajoute le chant le choisit,
-- une seule fois par chant, et jamais lors d'une modification.
create table public.song_notification_log (
  song_id uuid primary key references public.songs(id) on delete cascade,
  sent_at timestamptz not null default now()
);
alter table public.song_notification_log enable row level security;
revoke all on public.song_notification_log from anon, authenticated;

create function public.notify_new_song(p_song_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_editor() then
    raise exception 'Seuls les responsables et référents peuvent prévenir les membres';
  end if;
  -- Chant tout juste ajouté uniquement
  if not exists (select 1 from public.songs where id = p_song_id and created_at > now() - interval '1 hour') then
    return;
  end if;
  insert into public.song_notification_log (song_id) values (p_song_id) on conflict do nothing;
  if not found then return; end if;
  perform public.send_notifications(jsonb_build_object('type', 'song', 'id', p_song_id));
end;
$$;
revoke execute on function public.notify_new_song(uuid) from public, anon;
grant execute on function public.notify_new_song(uuid) to authenticated;
