// Supabase Edge Function: send-push
//
// Triggered by a Database Webhook on INSERT into public.notifications.
// Looks up the recipient's push subscriptions and sends a Web Push
// notification to each of them. Expired/invalid subscriptions (410/404)
// are removed.
//
// Required secrets (set with `supabase secrets set`):
//   VAPID_PUBLIC_KEY
//   VAPID_PRIVATE_KEY
//   VAPID_SUBJECT (e.g. mailto:you@example.com)
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from 'npm:@supabase/supabase-js@2'
import webpush from 'npm:web-push@3.6.7'

interface NotificationRow {
  id: string
  recipient_member_id: string
  actor_member_id: string | null
  type: string
  title: string
  message: string
}

interface WebhookPayload {
  type: string
  table: string
  record: NotificationRow
}

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const vapidPublicKey = Deno.env.get('VAPID_PUBLIC_KEY')!
const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY')!
const vapidSubject = Deno.env.get('VAPID_SUBJECT') ?? 'mailto:admin@example.com'

webpush.setVapidDetails(vapidSubject, vapidPublicKey, vapidPrivateKey)

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  const payload = (await req.json()) as WebhookPayload
  if (payload.table !== 'notifications' || payload.type !== 'INSERT') {
    return new Response('ignored', { status: 200 })
  }

  const record = payload.record
  const supabase = createClient(supabaseUrl, serviceRoleKey)

  const { data: subscriptions, error } = await supabase
    .from('push_subscriptions')
    .select('*')
    .eq('member_id', record.recipient_member_id)

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }

  const body = JSON.stringify({ title: record.title, body: record.message, url: '/' })

  const results = await Promise.allSettled(
    (subscriptions ?? []).map(async (sub) => {
      try {
        await webpush.sendNotification(
          {
            endpoint: sub.endpoint,
            keys: { p256dh: sub.p256dh, auth: sub.auth },
          },
          body,
        )
      } catch (err) {
        const statusCode = (err as { statusCode?: number }).statusCode
        if (statusCode === 404 || statusCode === 410) {
          await supabase.from('push_subscriptions').delete().eq('endpoint', sub.endpoint)
        } else {
          throw err
        }
      }
    }),
  )

  const failures = results.filter((r) => r.status === 'rejected')
  return new Response(JSON.stringify({ sent: results.length - failures.length, failed: failures.length }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
})
