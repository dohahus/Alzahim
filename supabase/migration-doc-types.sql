-- ════════════════════════════════════════════════════════════════════
--  أنواع المستندات: عقد أتعاب / عقد استشارات سنوي / عرض سعر / فاتورة
--  نفّذه مرة واحدة في SQL Editor — آمن لإعادة التنفيذ
-- ════════════════════════════════════════════════════════════════════

-- نوع المستند؛ العقود القائمة كلها عقود أتعاب
alter table invoices add column if not exists kind text not null default 'fee';
alter table invoices drop constraint if exists invoices_kind_chk;
alter table invoices add constraint invoices_kind_chk
  check (kind in ('fee','consulting','quote','invoice'));

-- موضوع المستند / نطاق الخدمات — لما لا يرتبط بقضية بعينها
alter table invoices add column if not exists subject text;

-- ضريبة القيمة المضافة: النسبة صفر ما لم تُفعَّل، والرقم الضريبي شرط
-- لتسمية المستند «فاتورة ضريبية» نظاماً
alter table invoices add column if not exists vat_rate numeric not null default 0;
alter table invoices add column if not exists vat_number text;

alter table invoices add column if not exists valid_days int;   -- مدة سريان عرض السعر
alter table invoices add column if not exists due_date date;    -- تاريخ استحقاق الفاتورة
alter table invoices add column if not exists bank_info text;   -- بيانات التحويل

-- بنود عرض السعر والفاتورة تُحرَّر بوصفها، بخلاف دفعات العقد المرقَّمة تلقائياً
alter table installments add column if not exists qty numeric;
