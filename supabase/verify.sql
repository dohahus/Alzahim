-- ════════════════════════════════════════════════════════════════════
--  تحقّق أن المخطط اكتمل — نفّذه في SQL Editor
--  النتيجة المتوقعة: كل السطور "✅ سليم"
-- ════════════════════════════════════════════════════════════════════

select 'الجداول' as البند,
       count(*)::text || ' / 16' as النتيجة,
       case when count(*) = 16 then '✅ سليم' else '❌ ناقص — أعد تنفيذ schema.sql' end as الحالة
from pg_tables where schemaname = 'public'

union all
select 'سياسات الحماية',
       count(*)::text || ' / 58',
       case when count(*) >= 58 then '✅ سليم' else '❌ ناقص — أعد تنفيذ schema.sql' end
from pg_policies where schemaname in ('public','storage')

union all
select 'الحماية مُشغَّلة على كل الجداول',
       count(*) filter (where rowsecurity)::text || ' / ' || count(*)::text,
       case when count(*) = count(*) filter (where rowsecurity)
            then '✅ سليم' else '❌ جدول بلا حماية' end
from pg_tables where schemaname = 'public'

union all
select 'الدوال',
       count(*)::text || ' / 9',
       case when count(*) >= 9 then '✅ سليم' else '❌ ناقص — أعد تنفيذ schema.sql' end
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('is_staff','is_owner','has_perm','my_client_id','can_see_case',
                    'create_pending_account','bootstrap_owner','claim_account','finalize_account')

union all
select 'مساحات تخزين الملفات',
       count(*)::text || ' / 3',
       case when count(*) = 3 then '✅ سليم' else '❌ ناقص — أعد تنفيذ schema.sql' end
from storage.buckets where id in ('case-docs','task-files','avatars')

union all
select 'جدول الحسابات المعلَّقة محجوب عن المتصفح',
       coalesce((select count(*)::text from pg_policies
                 where schemaname='public' and tablename='pending_accounts'), '0') || ' سياسات',
       case when not exists (select 1 from pg_policies
                             where schemaname='public' and tablename='pending_accounts')
            then '✅ سليم' else '❌ يجب ألّا يملك أي سياسة' end

union all
select 'حساب المدير',
       case when exists (select 1 from staff) then 'مُسجَّل ومكتمل'
            when exists (select 1 from pending_accounts where kind='staff') then 'جاهز — سجّل الدخول من الموقع'
            else 'غير موجود' end,
       case when exists (select 1 from staff) or exists (select 1 from pending_accounts where kind='staff')
            then '✅ سليم' else '⚠️ نفّذ bootstrap_owner' end;
