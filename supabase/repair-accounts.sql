-- ════════════════════════════════════════════════════════════════════
--  ترميم الحسابات على الحالة المطلوبة
--    عبدالله بن إبراهيم الزاحم — مدير مكتب، كل الصلاحيات — aez79@hotmail.com
--    زياد بن عبدالله الزاحم    — مدير مكتب، كل الصلاحيات — ziyad@alzahimlaw.com
--    مازن بن عبدالله الزاحم    — محامٍ متدرب            — abdullah@alzahimlaw.com
--  يُنفَّذ بعد fix-second-admin.sql
-- ════════════════════════════════════════════════════════════════════
begin;

-- ① بريد كل سطر مكتب = بريد حساب دخوله
--    اختلافهما هو ما يقفل الدخول: الموقع يحسب البريد من العمود، فإن كان
--    فارغاً بنى بريداً اصطناعياً لا وجود له في نظام المصادقة
update staff s set email = u.email
from auth.users u
where u.id = s.id
  and (s.email is null or lower(s.email) is distinct from lower(u.email));

-- ② عبدالله: اسم دخول بلا مسافة، وكل الصلاحيات
update staff set
  username = 'abdullah',
  name     = 'عبدالله بن إبراهيم الزاحم',
  role     = 'مدير المكتب',
  perms    = '{"cases":true,"cases_add":true,"hearings":true,"tasks":true,
               "clients":true,"clients_add":true,"fee_contracts":true,
               "consulting_contracts":true,"quotes":true,"invoices":true,
               "expenses":true,"letters":true,"hiring":true,"reports":true,
               "settings":true,"users":true}'::jsonb
where id = '140719c6-02a1-4fff-9f40-50053ec8a19b';

-- ③ زياد: كل الصلاحيات
update staff set
  name  = 'زياد بن عبدالله الزاحم',
  role  = 'مدير المكتب',
  perms = '{"cases":true,"cases_add":true,"hearings":true,"tasks":true,
            "clients":true,"clients_add":true,"fee_contracts":true,
            "consulting_contracts":true,"quotes":true,"invoices":true,
            "expenses":true,"letters":true,"hiring":true,"reports":true,
            "settings":true,"users":true}'::jsonb
where id = 'a1b3b899-720e-499a-8b18-60c842acdbe3';

-- ④ مازن: الاسم والدور — وصلاحياته تُضبط من «إدارة المستخدمين»
update staff set
  name = 'مازن بن عبدالله الزاحم',
  role = 'محامي متدرب'
where id = '54abdbaa-6c8e-4517-ae18-518b29f78018';

commit;

-- ⑤ التحقق: يجب أن تكون الحالة «سليم» في كل سطر
select s.username as اسم_الدخول, s.name as الاسم, s.role as الدور,
       s.email as بريد_الدخول,
       (s.perms->>'users')::boolean as مدير,
       case when lower(u.email) = auth_email_for(s.username, s.email)
            then 'سليم' else 'معطّل' end as الحالة
from staff s join auth.users u on u.id = s.id
order by s.username;
