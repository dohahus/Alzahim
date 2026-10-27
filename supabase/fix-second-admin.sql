-- ════════════════════════════════════════════════════════════════════
--  سدّ ثغرة «الحساب الجديد يستولي على سطر حساب قائم»
--
--  الخلل: finalize_account كانت تُدرج سطر المكتب بـ
--      on conflict (id) do update set username = ..., name = ..., perms = ...
--  فإن انتهى أول دخول للحساب الجديد وصاحبُه مرتبط بحساب مصادقة قائم
--  (لأن بريده موجود مسبقاً في نظام المصادقة، أو لأن الجلسة لم تتغيّر)،
--  فإن سطر صاحب ذلك الحساب يُستبدل باسم الحساب الجديد وصلاحياته.
--  فيفقد صاحبه الأصلي اسم دخوله، فلا يدخل، ويُطلب منه تغيير كلمة المرور بلا فائدة.
--
--  يُنفَّذ مرة واحدة من Supabase ← SQL Editor. آمن على البيانات: لا يحذف ولا يعدّل سطراً.
--  (create or replace بلا drop ← الصلاحيات الممنوحة للدوال تبقى كما هي)
-- ════════════════════════════════════════════════════════════════════

-- ───────── ① الحساب الجديد لا يستولي على سطر قائم ─────────
create or replace function finalize_account(p_identifier text, p_password text)
returns void
  language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id      text := lower(btrim(p_identifier));
  v_pending pending_accounts;
  v_self    staff;
  v_client  clients;
begin
  if auth.uid() is null then
    raise exception 'يجب تسجيل الدخول أولاً';
  end if;
  select * into v_pending from pending_accounts
   where lower(username) = v_id or lower(email) = v_id;

  if v_pending.username is null then
    if exists (select 1 from staff where id = auth.uid())
       or exists (select 1 from clients where auth_user_id = auth.uid()) then
      return;
    end if;
    raise exception 'لا يوجد حساب معلَّق بهذا المعرّف';
  end if;

  if v_pending.password_hash <> crypt(p_password, v_pending.password_hash) then
    raise exception 'بيانات الدخول غير صحيحة';
  end if;

  -- حساب المصادقة الحالي مرتبط مسبقاً بسطر مكتب لشخص آخر:
  -- لا يُستبدل ذلك السطر بحال — يُرفض الاستكمال ويُبلَّغ السبب
  select * into v_self from staff where id = auth.uid();
  if v_self.id is not null and lower(v_self.username) <> lower(v_pending.username) then
    raise exception 'حساب الدخول هذا مرتبط مسبقاً بالمستخدم «%». أعطِ الحساب الجديد بريداً مختلفاً، أو اتركه فارغاً ليُبنى من اسم المستخدم.', v_self.username;
  end if;
  -- أو مرتبط بحساب موكل
  select * into v_client from clients where auth_user_id = auth.uid();
  if v_client.id is not null and (v_pending.kind <> 'client' or v_client.id <> v_pending.client_id) then
    raise exception 'حساب الدخول هذا مرتبط مسبقاً بحساب موكل. أعطِ الحساب الجديد بريداً مختلفاً.';
  end if;
  -- واسم المستخدم محجوز لسطر مكتب آخر
  if exists (select 1 from staff where lower(username) = lower(v_pending.username) and id <> auth.uid()) then
    raise exception 'اسم المستخدم «%» مستخدم لحساب آخر', v_pending.username;
  end if;

  if v_pending.kind = 'staff' then
    insert into staff (id, name, username, email, role, perms)
    values (auth.uid(), v_pending.name, v_pending.username, v_pending.email,
            coalesce(v_pending.role,'محامي'), coalesce(v_pending.perms,'{}'::jsonb))
    on conflict (id) do update set name = excluded.name, username = excluded.username,
            email = excluded.email, role = excluded.role, perms = excluded.perms;
  else
    update clients set auth_user_id = auth.uid(), username = v_pending.username,
           email = coalesce(v_pending.email, email)
    where id = v_pending.client_id;
  end if;

  delete from pending_accounts where username = v_pending.username;
end;
$$;

-- ───────── ② لا يُنشأ حساب ببريد دخول قائم أصلاً ─────────
-- يُفحص البريد في نظام المصادقة نفسه لا في جدول المكتب وحده،
-- فالسطور القديمة قد يكون عمود البريد فيها فارغاً والبريد مسجَّلاً في المصادقة
create or replace function create_pending_account(
  p_username text, p_password text, p_kind text,
  p_name text, p_role text default null,
  p_perms jsonb default '{}'::jsonb, p_client_id uuid default null,
  p_email text default null
) returns void
  language plpgsql security definer set search_path = public, extensions as $$
declare
  v_auth_email text := auth_email_for(p_username, p_email);
  v_uid        uuid;
begin
  if not is_owner() then
    raise exception 'غير مصرَّح: إنشاء الحسابات لمدير المكتب فقط';
  end if;
  if exists (select 1 from staff where username = p_username)
     or exists (select 1 from clients where username = p_username and id is distinct from p_client_id) then
    raise exception 'اسم المستخدم مستخدم مسبقاً';
  end if;
  if p_email is not null and btrim(p_email) <> '' then
    if exists (select 1 from staff where lower(email) = lower(btrim(p_email)))
       or exists (select 1 from clients where lower(email) = lower(btrim(p_email)) and id is distinct from p_client_id) then
      raise exception 'البريد الإلكتروني مستخدم لحساب آخر';
    end if;
  end if;

  select id into v_uid from auth.users where lower(email) = v_auth_email;
  if v_uid is not null then
    -- إعادة دعوة الموكل نفسه مسموحة؛ وما عداها بريد دخول مشغول
    if not (p_kind = 'client' and p_client_id is not null
            and exists (select 1 from clients where id = p_client_id and auth_user_id = v_uid)) then
      raise exception 'بريد الدخول «%» له حساب قائم في النظام. اختر بريداً آخر، أو اتركه فارغاً ليُبنى من اسم المستخدم.', v_auth_email;
    end if;
  end if;

  insert into pending_accounts (username, password_hash, kind, name, email, role, perms, client_id)
  values (p_username, crypt(p_password, gen_salt('bf')), p_kind, p_name,
          nullif(btrim(coalesce(p_email,'')),''), p_role, p_perms, p_client_id)
  on conflict (username) do update
    set password_hash = excluded.password_hash, kind = excluded.kind, name = excluded.name,
        email = excluded.email, role = excluded.role, perms = excluded.perms,
        client_id = excluded.client_id;
end;
$$;

-- ───────── ③ تحديد الحساب عند الدخول يصبح قاطعاً لا عشوائياً ─────────
-- select into بلا ترتيب يأخذ سطراً عشوائياً عند تعدّد المطابقات،
-- فيُسلَّم المستخدم بريد دخول حساب آخر ويظهر له أن رمزه خاطئ
create or replace function claim_account(p_identifier text, p_password text)
returns table (auth_email text, kind text, already_registered boolean)
  language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id      text := lower(btrim(p_identifier));
  v_pending pending_accounts;
  v_staff   staff;
  v_client  clients;
  v_n       int;
begin
  select * into v_pending from pending_accounts
   where lower(username) = v_id or lower(email) = v_id
   order by (lower(username) = v_id) desc limit 1;
  if v_pending.username is not null
     and v_pending.password_hash = crypt(p_password, v_pending.password_hash) then
    return query select auth_email_for(v_pending.username, v_pending.email), v_pending.kind, false;
    return;
  end if;

  select count(*) into v_n from staff where lower(username) = v_id or lower(email) = v_id;
  if v_n > 1 then
    raise exception 'المعرّف «%» يطابق أكثر من حساب — راجع مدير المكتب', p_identifier;
  end if;
  select * into v_staff from staff where lower(username) = v_id or lower(email) = v_id;
  if v_staff.id is not null then
    return query select auth_email_for(v_staff.username, v_staff.email), 'staff'::text, true;
    return;
  end if;

  select count(*) into v_n from clients
   where lower(username) = v_id or lower(email) = v_id or lower(id_num) = v_id;
  if v_n > 1 then
    raise exception 'المعرّف «%» يطابق أكثر من حساب — راجع مدير المكتب', p_identifier;
  end if;
  select * into v_client from clients
   where lower(username) = v_id or lower(email) = v_id or lower(id_num) = v_id;
  if v_client.id is not null then
    return query select auth_email_for(v_client.username, v_client.email), 'client'::text, true;
    return;
  end if;

  raise exception 'بيانات الدخول غير صحيحة';
end;
$$;

-- ───────── ④ منع تكرار البريد في جدول المكتب مستقبلاً ─────────
do $$
begin
  if exists (select 1 from staff where email is not null group by lower(email) having count(*) > 1) then
    raise notice 'لم يُضَف قيد التفرّد: يوجد بريد مكرر في جدول المكتب — نفّذ diagnose-accounts.sql أولاً';
  else
    create unique index if not exists staff_email_unique_idx on staff (lower(email)) where email is not null;
  end if;
end $$;

-- ───────── ⑤ تأكيد الصلاحيات (الدوال أُعيد تعريفها لا حذفها، لكن للاحتياط) ─────────
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as f, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('claim_account','finalize_account','create_pending_account')
  loop
    if r.proname = 'create_pending_account' then
      execute format('revoke all on function %s from public, anon', r.f);
      execute format('grant execute on function %s to authenticated', r.f);
    else
      execute format('grant execute on function %s to anon, authenticated', r.f);
    end if;
  end loop;
end $$;

select 'تم — الحساب الجديد لم يعد يستولي على سطر حساب قائم' as النتيجة;
