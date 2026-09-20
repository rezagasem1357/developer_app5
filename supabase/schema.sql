-- زیرساخت اولیه ارتباط شبکه برای اپ فروشگاه
-- این SQL را در SQL Editor پروژه Supabase اجرا کنید.

-- توجه: store_id واقعی که از اپ ارسال می‌شود از نوع «لایسنس__شناسه‌فروشگاه» است
-- (مثلاً STORE.2026.0001__store-1)، بنابراین همین ستون به‌تنهایی داده هر لایسنس را
-- از لایسنس‌های دیگر جدا نگه می‌دارد. ستون license هم برای فیلتر و گزارش‌گیری جداگانه نگه داشته می‌شود.
create table if not exists public.store_snapshots (
  store_id text primary key,
  license text not null default '',
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by text not null default ''
);

create table if not exists public.network_events (
  id text primary key,
  type text not null,
  store_id text not null,
  license text not null default '',
  actor_name text not null default '',
  created_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb
);

create index if not exists store_snapshots_license_idx on public.store_snapshots(license);
create index if not exists network_events_license_idx on public.network_events(license);

create index if not exists network_events_store_created_idx
  on public.network_events(store_id, created_at desc);

-- اگر این اسکریپت قبلاً (بدون ستون license) اجرا شده، این دو خط ستون را اضافه می‌کنند
-- و اجرای دوباره اسکریپت روی دیتابیس قبلی خطا نمی‌دهد.
alter table public.store_snapshots add column if not exists license text not null default '';
alter table public.network_events add column if not exists license text not null default '';

alter table public.store_snapshots enable row level security;
alter table public.network_events enable row level security;

-- در نسخه عملیاتی بهتر است احراز هویت Supabase و RLS مبتنی بر auth.uid() فعال شود.
-- این policy ها برای راه‌اندازی اولیه محیط خصوصی فروشگاه هستند.
-- قبل از انتشار عمومی، آن‌ها را با کاربران authenticated و نقش‌ها محدود کنید.

grant select, insert, update on public.store_snapshots to anon, authenticated;
grant insert, select on public.network_events to anon, authenticated;

create policy "network store snapshot access"
on public.store_snapshots
for all
to anon, authenticated
using (true)
with check (true);

create policy "network events access"
on public.network_events
for select
 to anon, authenticated
using (true);

create policy "network events insert"
on public.network_events
for insert
 to anon, authenticated
with check (true);
