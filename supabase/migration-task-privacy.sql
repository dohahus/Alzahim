-- ════════════════════════════════════════════════════════════════════
--  المهام خاصة بأصحابها حتى عن مدير المكتب
--  لا تُرى المهمة إلا لمن كتبها أو أُشير إليه فيها
--  آمن لإعادة التنفيذ
-- ════════════════════════════════════════════════════════════════════

drop policy if exists tasks_read on tasks;
create policy tasks_read on tasks for select using (
  is_staff() and (
    creator_id = auth.uid()
    or assignee_id = auth.uid()
    or exists (select 1 from task_assignees ta where ta.task_id = tasks.id and ta.staff_id = auth.uid())
  )
);

drop policy if exists tasks_update on tasks;
create policy tasks_update on tasks for update using (
  is_staff() and (
    creator_id = auth.uid()
    or assignee_id = auth.uid()
    or exists (select 1 from task_assignees ta where ta.task_id = tasks.id and ta.staff_id = auth.uid())
  )
);

drop policy if exists tasks_delete on tasks;
create policy tasks_delete on tasks for delete using (
  is_staff() and creator_id = auth.uid()
);

-- دالة رؤية المهمة تتبع القاعدة نفسها (تعليقاتها ومرفقاتها تُقاس بها)
create or replace function can_see_task(t_id uuid) returns boolean
  language sql stable security definer set search_path = public, extensions as $$
  select exists (
    select 1 from tasks t
    where t.id = t_id
      and is_staff()
      and (
        t.assignee_id = auth.uid() or t.creator_id = auth.uid()
        or exists (select 1 from task_assignees ta where ta.task_id = t.id and ta.staff_id = auth.uid())
      )
  );
$$;
