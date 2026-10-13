-- ════════════════════════════════════════════════════════════════════
--  بيانات المكتب قابلة للتعديل من الموقع — نفّذه مرة واحدة
--  آمن لإعادة التنفيذ
-- ════════════════════════════════════════════════════════════════════

create table if not exists office_settings (
  id           int primary key default 1,
  name         text, lawyer text, license text, cr text, unique_no text,
  address      text, short_address text, pobox text,
  phone        text, mobile text, email text, city text,
  bank         text, bank_account text, iban text,
  updated_at   timestamptz not null default now(),
  constraint office_settings_single_row check (id = 1)
);

alter table office_settings enable row level security;

-- يقرأها كل منسوبي المكتب لأن المستندات تُبنى منها؛ ويعدّلها من يملك صلاحية الإعدادات
drop policy if exists office_read on office_settings;
create policy office_read on office_settings for select using (is_staff());
drop policy if exists office_write on office_settings;
create policy office_write on office_settings for insert with check (has_perm('settings'));
drop policy if exists office_update on office_settings;
create policy office_update on office_settings for update using (has_perm('settings'));

-- القيم الحالية كما في ورق المراسلة الرسمي
insert into office_settings (id, name, lawyer, license, cr, unique_no,
  address, short_address, pobox, phone, mobile, email, city, bank, bank_account, iban)
values (1,
  'مكتب المحامي / أ.د عبدالله بن إبراهيم الزاحم للمحاماة والاستشارات القانونية',
  'أ.د عبدالله بن إبراهيم الزاحم',
  '38321', '7019939342', '3105777119',
  'طريق الملك عبدالله (الدائري الثاني) مقابل سوق بن داود، المدينة المنورة',
  'DMPA6717', 'DMPA6717',
  '+966506475000', '+966559777374', 'abdullah@alzahimlaw.com', 'المدينة المنورة',
  'بنك الجزيرة', '012695004378001', 'SA84 6010 0012 6950 0437 8001')
on conflict (id) do nothing;
