const SW_VERSION = '2026-07-16-3'
const RELOAD_PARAM = 'swv'

self.addEventListener('install', () => {
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      await self.clients.claim()
      const clientList = await self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      await Promise.all(
        clientList.map(async (client) => {
          if (!client.url.startsWith(self.registration.scope) || !('navigate' in client)) return
          const targetUrl = new URL(client.url)
          targetUrl.searchParams.set(RELOAD_PARAM, SW_VERSION)
          try {
            await client.navigate(targetUrl.toString())
          } catch {
            // ignore navigation failures; the next launch will still use the new worker
          }
        }),
      )
    })(),
  )
})

function scopedUrl(path) {
  return new URL(path, self.registration.scope).href
}

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return
  if (event.request.mode !== 'navigate') return

  const requestUrl = new URL(event.request.url)
  if (!requestUrl.href.startsWith(self.registration.scope)) return

  event.respondWith(
    fetch(event.request, { cache: 'reload' }).catch(() => fetch(event.request)),
  )
})

self.addEventListener('push', (event) => {
  let payload = { title: '筋肉クラブ', body: '' }
  try {
    if (event.data) payload = { ...payload, ...event.data.json() }
  } catch {
    payload.body = event.data ? event.data.text() : ''
  }

  event.waitUntil(
    self.registration.showNotification(payload.title, {
      body: payload.body,
      icon: scopedUrl('icons/icon-192.png'),
      badge: scopedUrl('icons/icon-192.png'),
      data: { url: payload.url ? scopedUrl(payload.url.replace(/^\//, '')) : self.registration.scope },
    }),
  )
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const targetUrl = event.notification.data?.url || self.registration.scope
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          return client.focus()
        }
      }
      if (self.clients.openWindow) return self.clients.openWindow(targetUrl)
    }),
  )
})
