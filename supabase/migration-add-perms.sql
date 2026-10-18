-- ════════════════════════════════════════════════════════════════════
--  صلاحيتان جديدتان: إضافة موكلين، وإضافة قضايا
--  آمن لإعادة التنفيذ
-- ════════════════════════════════════════════════════════════════════

-- من أضاف الموكل يراه ولو لم تُقيَّد له قضية بعد
alter table clients add column if not exists created_by uuid references staff(id) on delete set null;

drop policy if exists clients_read on clients;
create policy clients_read on clients for select using (
  is_owner()
  or has_perm('clients_add')
  or has_perm('cases_add')
  or id = my_client_id()
  or created_by = auth.uid()
  or (is_staff() and exists (select 1 from cases c where c.client_id = clients.id and c.lawyer_id = auth.uid()))
);

-- الإضافة صارت صلاحية مستقلة، والمدير يملكها دائماً
drop policy if exists clients_staff_write on clients;
create policy clients_staff_write on clients for insert with check (
  is_staff() and (is_owner() or has_perm('clients_add'))
);

drop policy if exists cases_staff_write on cases;
create policy cases_staff_write on cases for insert with check (
  is_staff() and (is_owner() or has_perm('cases_add'))
);

-- الموكّلون القائمون يُنسبون للمدير حتى لا يفقدهم أحد
update clients set created_by = (
  select id from staff where coalesce((perms->>'users')::boolean,false) order by created_at limit 1
) where created_by is null;
