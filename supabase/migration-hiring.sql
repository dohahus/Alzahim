-- ════════════════════════════════════════════════════════════════════
--  التوظيف: نموذج عام يُعبَّأ من الصفحة التعريفية، وشاشة للمدير
--  آمن لإعادة التنفيذ
-- ════════════════════════════════════════════════════════════════════

create table if not exists job_applications (
  id               uuid primary key default gen_random_uuid(),
  created_at       timestamptz not null default now(),
  name             text not null,
  phone            text not null,
  email            text,
  nationality      text,
  birth_year       text,
  city             text,
  position         text not null,
  qualification    text,
  major            text,
  university       text,
  grad_year        text,
  license_no       text,
  experience       text,
  employer         text,
  languages        text,
  skills           text,
  salary_expect    text,
  availability     text,
  about            text,
  cv_path          text,
  attachments      text[],
  status           text not null default 'جديد',
  staff_note       text
);

-- لمن أنشأ الجدول قبل إضافة المرفقات المتعددة
alter table job_applications add column if not exists attachments text[];

create index if not exists job_applications_created_idx on job_applications (created_at desc);

alter table job_applications enable row level security;

-- يقدّم أي زائر طلبه، ولا يقرأ أحدٌ الطلبات إلا من يملك صلاحية التوظيف.
-- الإدخال بلا قراءة: لا يستطيع المتقدّم رؤية طلبات غيره ولا طلبه بعد إرساله.
drop policy if exists jobs_apply on job_applications;
create policy jobs_apply on job_applications for insert to anon, authenticated with check (true);
drop policy if exists jobs_read on job_applications;
create policy jobs_read on job_applications for select using (has_perm('hiring'));
drop policy if exists jobs_update on job_applications;
create policy jobs_update on job_applications for update using (has_perm('hiring'));
drop policy if exists jobs_delete on job_applications;
create policy jobs_delete on job_applications for delete using (has_perm('hiring'));

-- السير الذاتية في مساحة خاصة غير منشورة: يرفع إليها الزائر ولا يقرأ منها،
-- ولا يفتح الملف إلا من يملك صلاحية التوظيف عبر رابط مؤقّت
insert into storage.buckets (id, name, public) values ('cv-files','cv-files',false)
on conflict (id) do nothing;

drop policy if exists cv_upload on storage.objects;
create policy cv_upload on storage.objects for insert to anon, authenticated with check (
  bucket_id = 'cv-files'
);
drop policy if exists cv_read on storage.objects;
create policy cv_read on storage.objects for select using (
  bucket_id = 'cv-files' and has_perm('hiring')
);
drop policy if exists cv_delete on storage.objects;
create policy cv_delete on storage.objects for delete using (
  bucket_id = 'cv-files' and has_perm('hiring')
);
