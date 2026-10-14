-- Seuls l'admin et le responsable confient et gèrent les tâches ; les autres voient seulement les leurs.
create or replace function public.is_manager()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid())
      and role in ('admin', 'responsable')
  );
$$;

alter policy "tâches visibles par les éditeurs et les personnes chargées" on public.tasks
  using ((select public.is_manager()) or public.is_task_assignee(id));
alter policy "éditeurs créent les tâches" on public.tasks
  with check ((select public.is_manager()));
alter policy "éditeurs modifient les tâches" on public.tasks
  using ((select public.is_manager()));
alter policy "éditeurs suppriment les tâches" on public.tasks
  using ((select public.is_manager()));
alter policy "personnes chargées visibles" on public.task_assignees
  using ((select public.is_manager()) or public.is_task_assignee(task_id));
alter policy "éditeurs ajoutent des personnes" on public.task_assignees
  with check ((select public.is_manager()));
alter policy "éditeurs changent l'état" on public.task_assignees
  using ((select public.is_manager()));
alter policy "éditeurs retirent des personnes" on public.task_assignees
  using ((select public.is_manager()));
alter policy "messages visibles par ceux de la tâche" on public.task_messages
  using ((select public.is_manager()) or public.is_task_assignee(task_id));
alter policy "ceux de la tâche écrivent" on public.task_messages
  with check (author_id = (select auth.uid()) and ((select public.is_manager()) or public.is_task_assignee(task_id)));
alter policy "on retire ses propres messages" on public.task_messages
  using (author_id = (select auth.uid()) or (select public.is_manager()));
