-- ════════════════════════════════════════════════════════════════════
--  سند استلام الدفعة — نفّذه مرة واحدة في SQL Editor. آمن لإعادة التنفيذ
-- ════════════════════════════════════════════════════════════════════

alter table invoices drop constraint if exists invoices_kind_chk;
alter table invoices add constraint invoices_kind_chk
  check (kind in ('fee','consulting','quote','invoice','receipt'));

-- السند يشير إلى العقد ودفعته، فلا يُحتسب إيراداً جديداً ولا يُصدر مرتين
alter table invoices add column if not exists source_invoice uuid references invoices(id) on delete set null;
alter table invoices add column if not exists source_inst uuid references installments(id) on delete set null;
