-- این migration را فقط اگر جدول network_events روی پروژه Supabase ساخته نشده اجرا کنید.
-- سیستم پیام و گزارش عملکرد از همین جدول و همان مسیر REST شبکه استفاده می‌کند.
create table if not exists public.network_events (
  id text primary key,
  type text not null,
  store_id text not null,
  license text not null default '',
  actor_name text not null default '',
  created_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb
);

alter table public.network_events add column if not exists license text not null default '';
create index if not exists network_events_license_idx on public.network_events(license);
create index if not exists network_events_store_created_idx on public.network_events(store_id, created_at desc);

alter table public.network_events enable row level security;
grant select, insert on public.network_events to anon, authenticated;

drop policy if exists "network events access" on public.network_events;
create policy "network events access" on public.network_events
for select to anon, authenticated using (true);

drop policy if exists "network events insert" on public.network_events;
create policy "network events insert" on public.network_events
for insert to anon, authenticated with check (true);


-- actor_role در نسخه قبلی اپ ارسال می‌شد اما برای جلوگیری از خطای PostgREST
-- در نسخه اصلاحی دیگر به‌عنوان ستون مستقل ارسال نمی‌شود؛ نقش در payload نیز ذخیره می‌شود.
