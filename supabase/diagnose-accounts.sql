-- ════════════════════════════════════════════════════════════════════
--  تشخيص الحسابات — قراءة فقط، لا يغيّر شيئاً في قاعدة البيانات
--  يُنفَّذ من Supabase ← SQL Editor، ثم تُنسخ النتيجة كاملة
-- ════════════════════════════════════════════════════════════════════
select line from (

  -- حسابات الدخول في نظام المصادقة
  select 1 as ord, u.email as k, format(
    'AUTH    | %s | id=%s | أُنشئ=%s | آخر دخول=%s | مؤكَّد=%s',
    u.email, u.id,
    to_char(u.created_at, 'MM-DD HH24:MI'),
    coalesce(to_char(u.last_sign_in_at, 'MM-DD HH24:MI'), 'لم يدخل'),
    case when u.email_confirmed_at is null then 'لا' else 'نعم' end) as line
  from auth.users u

  union all
  -- سطور المكتب
  select 2, s.username, format(
    'STAFF   | %s | %s | بريد=%s | دخول=%s | دور=%s | مدير=%s | id=%s',
    s.username, s.name, coalesce(s.email, '—'),
    auth_email_for(s.username, s.email), s.role,
    case when (s.perms->>'users')::boolean is true then 'نعم' else 'لا' end, s.id)
  from staff s

  union all
  -- حسابات أُنشئت ولم يدخل أصحابها بعد
  select 3, p.username, format(
    'PENDING | %s | %s | بريد=%s | دخول=%s | نوع=%s | دور=%s | أُنشئ=%s',
    p.username, p.name, coalesce(p.email, '—'),
    auth_email_for(p.username, p.email), p.kind, coalesce(p.role, '—'),
    to_char(p.created_at, 'MM-DD HH24:MI'))
  from pending_accounts p

  union all
  -- سطر مكتب بلا حساب مصادقة أصلاً
  select 4, s.username, format('خلل ① | سطر المكتب «%s» لا يقابله حساب مصادقة (id مفقود)', s.username)
  from staff s where not exists (select 1 from auth.users u where u.id = s.id)

  union all
  -- بريد الدخول المحسوب غير موجود في المصادقة ← صاحبه لا يستطيع الدخول
  select 5, s.username, format('خلل ② | «%s» بريد دخوله المحسوب %s غير موجود في المصادقة ← لا يستطيع الدخول',
    s.username, auth_email_for(s.username, s.email))
  from staff s
  where not exists (select 1 from auth.users u where lower(u.email) = auth_email_for(s.username, s.email))

  union all
  -- بريد الدخول موجود لكنه يخصّ حساب مصادقة آخر ← السطر مُستولى عليه
  select 6, s.username, format('خلل ③ | «%s» بريد دخوله %s يخصّ حساب مصادقة آخر (%s) لا سطره (%s)',
    s.username, auth_email_for(s.username, s.email), u.id, s.id)
  from staff s
  join auth.users u on lower(u.email) = auth_email_for(s.username, s.email)
  where u.id <> s.id

  union all
  -- حساب مصادقة واحد يحمل أكثر من سطر مكتب
  select 7, s.id::text, format('خلل ④ | حساب مصادقة واحد (%s) له %s سطر مكتب: %s',
    s.id, count(*), string_agg(s.username, ' ، '))
  from staff s group by s.id having count(*) > 1

  union all
  -- بريد مكرر بين سطور المكتب ← يجعل تحديد الحساب عشوائياً
  select 8, lower(s.email), format('خلل ⑤ | البريد %s مكرر في %s سطر مكتب: %s',
    lower(s.email), count(*), string_agg(s.username, ' ، '))
  from staff s where s.email is not null group by lower(s.email) having count(*) > 1

  union all
  -- حساب معلَّق بريد دخوله موجود مسبقاً في المصادقة ← أول دخول له سيصطدم
  select 9, p.username, format('خلل ⑥ | الحساب المعلَّق «%s» بريد دخوله %s موجود مسبقاً في المصادقة',
    p.username, auth_email_for(p.username, p.email))
  from pending_accounts p
  where exists (select 1 from auth.users u where lower(u.email) = auth_email_for(p.username, p.email))

) t order by ord, k;
