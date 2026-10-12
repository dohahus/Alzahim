-- ════════════════════════════════════════════════════════════════════
--  عرض السعر لمن ليس موكلاً بعد + تحويل العرض إلى فاتورة
--  نفّذه مرة واحدة في SQL Editor — آمن لإعادة التنفيذ
-- ════════════════════════════════════════════════════════════════════

-- عرض السعر قد يُوجَّه لعميل محتمل لم يُسجَّل موكلاً بعد
alter table invoices alter column client_id drop not null;
alter table invoices add column if not exists client_name text;

-- العرض المعتمَد يشير إلى الفاتورة الصادرة عنه، فلا يُحوَّل مرتين
alter table invoices add column if not exists converted_to uuid references invoices(id) on delete set null;
