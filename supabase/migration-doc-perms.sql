-- ════════════════════════════════════════════════════════════════════
--  فصل صلاحيات المستندات المالية — نفّذه مرة واحدة. آمن لإعادة التنفيذ
-- ════════════════════════════════════════════════════════════════════

-- صلاحية «الفواتير» الواحدة صارت أربعاً: عقود أتعاب، عقود استشارات،
-- عروض أسعار، فواتير — ومعها صلاحية مستقلة للمصروفات.
-- من كان يملك invoices يحصل على الأربع، فلا يفقد أحد وصولاً كان له
update staff
set perms = perms
  || jsonb_build_object(
       'fee_contracts',        coalesce((perms->>'invoices')::boolean, false),
       'consulting_contracts', coalesce((perms->>'invoices')::boolean, false),
       'quotes',               coalesce((perms->>'invoices')::boolean, false),
       'expenses',             coalesce((perms->>'invoices')::boolean, false))
where perms is not null
  and not (perms ? 'fee_contracts');

-- من يملك أيّ صلاحية مستند مالي يقرأ جداولها.
-- الكتابة تبقى مقيَّدة بمن يملك صلاحية الفواتير أو العقود
create or replace function has_any_doc_perm() returns boolean
  language sql stable security definer set search_path = public, extensions as $$
  select has_perm('invoices') or has_perm('quotes')
      or has_perm('fee_contracts') or has_perm('consulting_contracts');
$$;
revoke all on function has_any_doc_perm() from public, anon;
grant execute on function has_any_doc_perm() to authenticated;

drop policy if exists invoices_read on invoices;
create policy invoices_read on invoices for select using (
  has_any_doc_perm() or client_id = my_client_id()
);
drop policy if exists invoices_write on invoices;
create policy invoices_write on invoices for insert with check (has_any_doc_perm());
drop policy if exists invoices_update on invoices;
create policy invoices_update on invoices for update using (has_any_doc_perm());
drop policy if exists invoices_delete on invoices;
create policy invoices_delete on invoices for delete using (has_any_doc_perm());

drop policy if exists installments_read on installments;
create policy installments_read on installments for select using (
  exists (select 1 from invoices i where i.id = invoice_id
    and (has_any_doc_perm() or i.client_id = my_client_id()))
);
drop policy if exists installments_write on installments;
create policy installments_write on installments for insert with check (has_any_doc_perm());
drop policy if exists installments_update on installments;
create policy installments_update on installments for update using (has_any_doc_perm());
drop policy if exists installments_delete on installments;
create policy installments_delete on installments for delete using (has_any_doc_perm());

drop policy if exists invoice_cases_write on invoice_cases;
create policy invoice_cases_write on invoice_cases for insert with check (has_any_doc_perm());
drop policy if exists invoice_cases_delete on invoice_cases;
create policy invoice_cases_delete on invoice_cases for delete using (has_any_doc_perm());

-- المصروفات صارت صلاحية مستقلة
drop policy if exists expenses_read on expenses;
create policy expenses_read on expenses for select using (has_perm('expenses'));
drop policy if exists expenses_write on expenses;
create policy expenses_write on expenses for insert with check (has_perm('expenses'));
drop policy if exists expenses_update on expenses;
create policy expenses_update on expenses for update using (has_perm('expenses'));
drop policy if exists expenses_delete on expenses;
create policy expenses_delete on expenses for delete using (has_perm('expenses'));

drop policy if exists expense_docs_read on storage.objects;
create policy expense_docs_read on storage.objects for select using (
  bucket_id = 'expense-docs' and has_perm('expenses'));
drop policy if exists expense_docs_write on storage.objects;
create policy expense_docs_write on storage.objects for insert with check (
  bucket_id = 'expense-docs' and has_perm('expenses'));
drop policy if exists expense_docs_delete on storage.objects;
create policy expense_docs_delete on storage.objects for delete using (
  bucket_id = 'expense-docs' and has_perm('expenses'));

-- إيصالات السداد تتبع صلاحية الفواتير
drop policy if exists receipts_read on storage.objects;
create policy receipts_read on storage.objects for select using (
  bucket_id = 'receipts' and has_any_doc_perm());
drop policy if exists receipts_write on storage.objects;
create policy receipts_write on storage.objects for insert with check (
  bucket_id = 'receipts' and has_any_doc_perm());
drop policy if exists receipts_delete on storage.objects;
create policy receipts_delete on storage.objects for delete using (
  bucket_id = 'receipts' and has_any_doc_perm());
