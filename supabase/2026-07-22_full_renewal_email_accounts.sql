-- Full renewal: email/password accounts, explicit daily intent, and count-based ranking.
-- Run this after 2026-07-19_email_login_restore_claims.sql.
--
-- This keeps legacy member/visit data in place, but all new app behavior uses
-- members.user_id = auth.uid() as the reliable account ownership link.

create extension if not exists pgcrypto;

alter table public.members
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists email text,
  add column if not exists avatar_url text,
  add column if not exists created_at timestamptz not null default timezone('utc', now()),
  add column if not exists updated_at timestamptz not null default timezone('utc', now());

update public.members m
set user_id = coalesce(m.claimed_by, m.user_id)
where m.user_id is null
  and m.claimed_by is not null;

update public.members m
set email = u.email
from auth.users u
where m.user_id = u.id
  and m.email is null;

create unique index if not exists idx_members_user_id
  on public.members(user_id)
  where user_id is not null;

create table if not exists public.daily_intents (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete cascade,
  date date not null,
  status text not null check (status in ('going', 'not_going')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique(member_id, date)
);

create index if not exists idx_daily_intents_date on public.daily_intents(date desc);
create index if not exists idx_daily_intents_member_date on public.daily_intents(member_id, date desc);
create index if not exists idx_gym_visits_member_checkin on public.gym_visits(member_id, check_in_at desc);

create or replace function public.member_initials(display_name text, fallback_email text)
returns text
language plpgsql
immutable
as $$
declare
  source_text text;
  normalized text;
begin
  source_text := coalesce(nullif(trim(display_name), ''), split_part(coalesce(fallback_email, 'member'), '@', 1), 'member');
  normalized := upper(regexp_replace(source_text, '[^[:alnum:]]', '', 'g'));
  return left(rpad(coalesce(nullif(normalized, ''), 'ME'), 2, 'M'), 2);
end;
$$;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists members_touch_updated_at on public.members;
create trigger members_touch_updated_at
before update on public.members
for each row execute function public.touch_updated_at();

drop trigger if exists daily_intents_touch_updated_at on public.daily_intents;
create trigger daily_intents_touch_updated_at
before update on public.daily_intents
for each row execute function public.touch_updated_at();

create or replace function public.current_member_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.members where user_id = auth.uid()
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  display_name text;
begin
  display_name := coalesce(
    nullif(trim(new.raw_user_meta_data->>'name'), ''),
    nullif(trim(new.raw_user_meta_data->>'display_name'), ''),
    split_part(new.email, '@', 1),
    'member'
  );

  insert into public.members (id, user_id, email, name, initials, avatar_color)
  values (
    new.id,
    new.id,
    new.email,
    display_name,
    public.member_initials(display_name, new.email),
    coalesce(nullif(new.raw_user_meta_data->>'avatar_color', ''), 'blue')
  )
  on conflict (id) do update
  set
    user_id = excluded.user_id,
    email = excluded.email,
    name = coalesce(public.members.name, excluded.name),
    initials = coalesce(public.members.initials, excluded.initials);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.members enable row level security;
alter table public.daily_intents enable row level security;
alter table public.gym_visits enable row level security;

drop policy if exists "members_select_visible" on public.members;
create policy "members_select_visible"
  on public.members
  for select
  to authenticated
  using (true);

drop policy if exists "members_insert_own" on public.members;
create policy "members_insert_own"
  on public.members
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "members_update_own" on public.members;
create policy "members_update_own"
  on public.members
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "daily_intents_select_visible" on public.daily_intents;
create policy "daily_intents_select_visible"
  on public.daily_intents
  for select
  to authenticated
  using (true);

drop policy if exists "daily_intents_insert_own" on public.daily_intents;
create policy "daily_intents_insert_own"
  on public.daily_intents
  for insert
  to authenticated
  with check (member_id = public.current_member_id());

drop policy if exists "daily_intents_update_own" on public.daily_intents;
create policy "daily_intents_update_own"
  on public.daily_intents
  for update
  to authenticated
  using (member_id = public.current_member_id())
  with check (member_id = public.current_member_id());

drop policy if exists "daily_intents_delete_own" on public.daily_intents;
create policy "daily_intents_delete_own"
  on public.daily_intents
  for delete
  to authenticated
  using (member_id = public.current_member_id());

drop policy if exists "gym_visits_select_visible" on public.gym_visits;
create policy "gym_visits_select_visible"
  on public.gym_visits
  for select
  to authenticated
  using (true);

drop policy if exists "gym_visits_insert_own" on public.gym_visits;
create policy "gym_visits_insert_own"
  on public.gym_visits
  for insert
  to authenticated
  with check (member_id = public.current_member_id());

drop policy if exists "gym_visits_update_own" on public.gym_visits;
create policy "gym_visits_update_own"
  on public.gym_visits
  for update
  to authenticated
  using (member_id = public.current_member_id())
  with check (member_id = public.current_member_id());

drop policy if exists "gym_visits_delete_own" on public.gym_visits;
create policy "gym_visits_delete_own"
  on public.gym_visits
  for delete
  to authenticated
  using (member_id = public.current_member_id());

drop policy if exists "attendance_records_insert_own" on public.attendance_records;
create policy "attendance_records_insert_own"
  on public.attendance_records
  for insert
  to authenticated
  with check (member_id = public.current_member_id());

drop policy if exists "attendance_records_update_own" on public.attendance_records;
create policy "attendance_records_update_own"
  on public.attendance_records
  for update
  to authenticated
  using (member_id = public.current_member_id())
  with check (member_id = public.current_member_id());

drop policy if exists "attendance_records_delete_own" on public.attendance_records;
create policy "attendance_records_delete_own"
  on public.attendance_records
  for delete
  to authenticated
  using (member_id = public.current_member_id());

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
  on public.notifications
  for select
  to authenticated
  using (recipient_member_id = public.current_member_id());

drop policy if exists "notifications_insert_actor" on public.notifications;
create policy "notifications_insert_actor"
  on public.notifications
  for insert
  to authenticated
  with check (actor_member_id = public.current_member_id());

drop policy if exists "notifications_update_own_read_state" on public.notifications;
create policy "notifications_update_own_read_state"
  on public.notifications
  for update
  to authenticated
  using (recipient_member_id = public.current_member_id())
  with check (recipient_member_id = public.current_member_id());

drop policy if exists "push_subscriptions_select_own" on public.push_subscriptions;
create policy "push_subscriptions_select_own"
  on public.push_subscriptions
  for select
  to authenticated
  using (member_id = public.current_member_id());

drop policy if exists "push_subscriptions_insert_own" on public.push_subscriptions;
create policy "push_subscriptions_insert_own"
  on public.push_subscriptions
  for insert
  to authenticated
  with check (member_id = public.current_member_id());

drop policy if exists "push_subscriptions_update_own" on public.push_subscriptions;
create policy "push_subscriptions_update_own"
  on public.push_subscriptions
  for update
  to authenticated
  using (member_id = public.current_member_id())
  with check (member_id = public.current_member_id());

drop policy if exists "push_subscriptions_delete_own" on public.push_subscriptions;
create policy "push_subscriptions_delete_own"
  on public.push_subscriptions
  for delete
  to authenticated
  using (member_id = public.current_member_id());

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read"
on storage.objects
for select
using (bucket_id = 'avatars');

drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and split_part(name, '.', 1) = public.current_member_id()::text
);

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars'
  and split_part(name, '.', 1) = public.current_member_id()::text
)
with check (
  bucket_id = 'avatars'
  and split_part(name, '.', 1) = public.current_member_id()::text
);

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'avatars'
  and split_part(name, '.', 1) = public.current_member_id()::text
);
