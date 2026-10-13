-- ════════════════════════════════════════════════════════════════════
--  توسعة بيانات المكتب لتُعدَّل من الموقع — نفّذه مرة واحدة
--  الجدول موجود أصلاً بستة حقول قديمة، فنُضيف الباقي ونصحّح القيم
--  آمن لإعادة التنفيذ
-- ════════════════════════════════════════════════════════════════════

create table if not exists office_settings (
  id int primary key default 1 check (id = 1)
);

alter table office_settings add column if not exists name          text;
alter table office_settings add column if not exists lawyer        text;
alter table office_settings add column if not exists license       text;
alter table office_settings add column if not exists cr            text;
alter table office_settings add column if not exists unique_no     text;
alter table office_settings add column if not exists address       text;
alter table office_settings add column if not exists short_address text;
alter table office_settings add column if not exists pobox         text;
alter table office_settings add column if not exists phone         text;
alter table office_settings add column if not exists mobile        text;
alter table office_settings add column if not exists email         text;
alter table office_settings add column if not exists city          text;
alter table office_settings add column if not exists bank          text;
alter table office_settings add column if not exists bank_account  text;
alter table office_settings add column if not exists iban          text;
alter table office_settings add column if not exists updated_at    timestamptz not null default now();

alter table office_settings enable row level security;

-- تُقرأ من الجميع لأن المستندات تُبنى منها ويفتحها الموكل أيضاً، وهي بيانات
-- منشورة على ورق المراسلة؛ ولا يعدّلها إلا من يملك صلاحية الإعدادات
drop policy if exists office_read on office_settings;
create policy office_read on office_settings for select using (true);
drop policy if exists office_write on office_settings;
create policy office_write on office_settings for insert with check (has_perm('settings'));
drop policy if exists office_update on office_settings;
create policy office_update on office_settings for update using (has_perm('settings'));

-- القيم الصحيحة كما في ورق المراسلة الرسمي، بدل القيم المتقادمة في الصف القديم
insert into office_settings (id) values (1) on conflict (id) do nothing;

update office_settings set
  name          = 'مكتب المحامي / أ.د عبدالله بن إبراهيم الزاحم للمحاماة والاستشارات القانونية',
  lawyer        = 'أ.د عبدالله بن إبراهيم الزاحم',
  license       = '38321',
  cr            = '7019939342',
  unique_no     = '3105777119',
  address       = 'طريق الملك عبدالله (الدائري الثاني) مقابل سوق بن داود، المدينة المنورة',
  short_address = 'DMPA6717',
  pobox         = 'DMPA6717',
  phone         = '+966506475000',
  mobile        = '+966559777374',
  email         = 'abdullah@alzahimlaw.com',
  city          = 'المدينة المنورة',
  bank          = 'بنك الجزيرة',
  bank_account  = '012695004378001',
  iban          = 'SA84 6010 0012 6950 0437 8001',
  updated_at    = now()
where id = 1 and lawyer is null;
