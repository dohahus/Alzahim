-- ════════════════════════════════════════════════════════════════════
--  إيصالات الدفعات — نفّذه مرة واحدة في SQL Editor
--  آمن لإعادة التنفيذ: لا يحذف بيانات ولا يُظهر أخطاء لو نُفّذ مرتين
-- ════════════════════════════════════════════════════════════════════

alter table installments add column if not exists receipt_path text;
alter table installments add column if not exists receipt_name text;
alter table installments add column if not exists receipt_size bigint;
alter table installments add column if not exists paid_at date;

insert into storage.buckets (id, name, public)
values ('receipts','receipts',false)
on conflict (id) do nothing;

-- الإيصالات بيانات مالية: لا يراها إلا من يملك صلاحية الفواتير.
-- الموكل لا يصل إليها ولو عرف المسار، لأن السياسة تُطبَّق على الملف نفسه
drop policy if exists receipts_read on storage.objects;
create policy receipts_read on storage.objects for select using (
  bucket_id = 'receipts' and has_perm('invoices')
);
drop policy if exists receipts_write on storage.objects;
create policy receipts_write on storage.objects for insert with check (
  bucket_id = 'receipts' and has_perm('invoices')
);
drop policy if exists receipts_delete on storage.objects;
create policy receipts_delete on storage.objects for delete using (
  bucket_id = 'receipts' and has_perm('invoices')
);
