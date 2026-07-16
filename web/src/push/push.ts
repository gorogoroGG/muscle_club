function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/')
  const rawData = atob(base64)
  const outputArray = new Uint8Array(rawData.length)
  for (let i = 0; i < rawData.length; i++) {
    outputArray[i] = rawData.charCodeAt(i)
  }
  return outputArray
}

export const isPushSupported =
  typeof window !== 'undefined' && 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window

const isServiceWorkerSupported = typeof window !== 'undefined' && 'serviceWorker' in navigator

function reloadWithCacheBust(paramName: string): void {
  const url = new URL(window.location.href)
  url.searchParams.set(paramName, Date.now().toString())
  window.location.replace(url.toString())
}

export async function registerServiceWorker(): Promise<ServiceWorkerRegistration | null> {
  if (!isServiceWorkerSupported) return null
  const base = import.meta.env.BASE_URL
  let reloadedByControllerChange = false
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (reloadedByControllerChange) return
    reloadedByControllerChange = true
    reloadWithCacheBust('sw-updated')
  })
  const registration = await navigator.serviceWorker.register(`${base}sw.js`, { scope: base, updateViaCache: 'none' })
  await registration.update().catch(() => undefined)
  return registration
}

export async function getExistingPushSubscription(): Promise<PushSubscription | null> {
  if (!isPushSupported) return null
  const registration = await navigator.serviceWorker.ready
  return registration.pushManager.getSubscription()
}

export async function subscribeToPush(vapidPublicKey: string): Promise<PushSubscription> {
  const permission = await Notification.requestPermission()
  if (permission !== 'granted') {
    throw new Error('通知が許可されませんでした。')
  }
  const registration = await navigator.serviceWorker.ready
  const existing = await registration.pushManager.getSubscription()
  if (existing) return existing
  return registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(vapidPublicKey) as BufferSource,
  })
}

export async function unsubscribeFromPush(): Promise<void> {
  const subscription = await getExistingPushSubscription()
  if (subscription) {
    await subscription.unsubscribe()
  }
}
