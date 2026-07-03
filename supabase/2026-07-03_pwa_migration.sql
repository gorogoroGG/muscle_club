-- PWA migration for muscle_club
-- Run this in the Supabase SQL editor after schema.sql / 2026-07-01_notifications_and_attendance.sql.
--
-- Scope: auto check-in (location-based) and chat are dropped from the product.
-- Web Push subscriptions are added so the PWA can notify members about
-- going / notGoing / checkedIn / checkedOut / checkInCancelled events.

-- 1) Drop chat, no longer part of the product.
drop policy if exists "chat_messages_select_visible" on public.chat_messages;
drop policy if exists "chat_messages_insert_own" on public.chat_messages;
drop table if exists public.chat_messages cascade;

-- 2) chatMessage is no longer a valid notification type.
delete from public.notifications
where type = 'chatMessage';

do $$
declare
    target_constraint text;
begin
    select conname
    into target_constraint
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    where t.relname = 'notifications'
      and pg_get_constraintdef(c.oid) ilike '%type%'
    limit 1;

    if target_constraint is not null then
        execute format('alter table public.notifications drop constraint %I', target_constraint);
    end if;
end $$;

alter table public.notifications
add constraint notifications_type_check
check (type in ('going', 'notGoing', 'checkedIn', 'checkedOut', 'checkInCancelled'));

-- 3) Web Push subscriptions, one row per device/browser subscription.
create table if not exists public.push_subscriptions (
    id uuid primary key default gen_random_uuid(),
    member_id uuid not null references public.members(id) on delete cascade,
    endpoint text not null unique,
    p256dh text not null,
    auth text not null,
    created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_push_subscriptions_member_id on public.push_subscriptions(member_id);

alter table public.push_subscriptions enable row level security;

drop policy if exists "push_subscriptions_select_own" on public.push_subscriptions;
create policy "push_subscriptions_select_own"
on public.push_subscriptions
for select
to authenticated
using (member_id = auth.uid());

drop policy if exists "push_subscriptions_insert_own" on public.push_subscriptions;
create policy "push_subscriptions_insert_own"
on public.push_subscriptions
for insert
to authenticated
with check (member_id = auth.uid());

drop policy if exists "push_subscriptions_update_own" on public.push_subscriptions;
create policy "push_subscriptions_update_own"
on public.push_subscriptions
for update
to authenticated
using (member_id = auth.uid())
with check (member_id = auth.uid());

drop policy if exists "push_subscriptions_delete_own" on public.push_subscriptions;
create policy "push_subscriptions_delete_own"
on public.push_subscriptions
for delete
to authenticated
using (member_id = auth.uid());

-- 4) The send-push Edge Function needs to read subscriptions for arbitrary
-- recipients (not just auth.uid()), so it must be called with the service
-- role key. No additional policy is needed for that -- the service role
-- bypasses RLS entirely.
--
-- After running this file:
--   1. Deploy the edge function: supabase functions deploy send-push
--   2. Set secrets: supabase secrets set VAPID_PUBLIC_KEY=... VAPID_PRIVATE_KEY=... VAPID_SUBJECT=mailto:you@example.com
--   3. In the Supabase Dashboard, go to Database -> Webhooks and create a webhook:
--        - Table: public.notifications
--        - Events: Insert
--        - Type: Supabase Edge Function
--        - Function: send-push
--      This triggers the function automatically whenever a notification row is inserted.
