-- ════════════════════════════════════════════════════════════════════
--  المصروفات + تاريخ استحقاق الدفعات — نفّذه مرة واحدة في SQL Editor
--  آمن لإعادة التنفيذ
-- ════════════════════════════════════════════════════════════════════

-- ١) مصروفات المكتب
create table if not exists expenses (
  id          uuid primary key default gen_random_uuid(),
  date        date not null default current_date,
  title       text not null,
  category    text not null,
  amount      numeric not null default 0,
  -- المصروف المباشر يُحمَّل على قضية، وغير المباشر مصروف تشغيلي عام
  case_id     uuid references cases(id) on delete set null,
  billable    boolean not null default false,  -- قابل لإعادة تحميله على الموكل
  reimbursed  boolean not null default false,  -- حُصِّل من الموكل فعلاً
  method      text,                            -- نقد / تحويل / بطاقة
  vendor      text,
  notes       text,
  receipt_path text,
  receipt_name text,
  created_by  uuid references staff(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists idx_expenses_date on expenses(date);
create index if not exists idx_expenses_case on expenses(case_id);

alter table expenses enable row level security;

-- المصروفات بيانات مالية: لمن يملك صلاحية الفواتير وحده، ولا يراها الموكل
drop policy if exists expenses_read on expenses;
create policy expenses_read on expenses for select using (has_perm('invoices'));
drop policy if exists expenses_write on expenses;
create policy expenses_write on expenses for insert with check (has_perm('invoices'));
drop policy if exists expenses_update on expenses;
create policy expenses_update on expenses for update using (has_perm('invoices'));
drop policy if exists expenses_delete on expenses;
create policy expenses_delete on expenses for delete using (has_perm('invoices'));

-- مرفقات فواتير المصروفات
insert into storage.buckets (id, name, public)
values ('expense-docs','expense-docs',false)
on conflict (id) do nothing;

drop policy if exists expense_docs_read on storage.objects;
create policy expense_docs_read on storage.objects for select using (
  bucket_id = 'expense-docs' and has_perm('invoices')
);
drop policy if exists expense_docs_write on storage.objects;
create policy expense_docs_write on storage.objects for insert with check (
  bucket_id = 'expense-docs' and has_perm('invoices')
);
drop policy if exists expense_docs_delete on storage.objects;
create policy expense_docs_delete on storage.objects for delete using (
  bucket_id = 'expense-docs' and has_perm('invoices')
);

-- ٢) تاريخ استحقاق لكل دفعة — بدونه لا يمكن حساب أعمار الديون
alter table installments add column if not exists due_date date;
