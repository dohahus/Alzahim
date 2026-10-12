-- ════════════════════════════════════════════════════════════════════
--  منع الموكل من قراءة المستجدات من نوع «مهمة» — نفّذه مرة واحدة
--  آمن لإعادة التنفيذ
-- ════════════════════════════════════════════════════════════════════

drop policy if exists case_updates_read on case_updates;
create policy case_updates_read on case_updates for select using (
  can_see_case(case_id) and (is_staff() or kind is distinct from 'task')
);
