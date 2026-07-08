const CHECK_INTERVAL_MS = 5 * 60 * 1000

function entryScriptPathFrom(html: string): string | null {
  const match = html.match(/<script[^>]+type=["']module["'][^>]+src=["']([^"']+)["']/i)
  if (!match) return null
  return new URL(match[1], window.location.href).pathname
}

function currentEntryScriptPath(): string | null {
  const scripts = Array.from(document.scripts)
  const entry = scripts.find((script) => script.type === 'module' && script.src.includes('/assets/'))
  return entry ? new URL(entry.src).pathname : null
}

async function checkForAppUpdate(): Promise<void> {
  if (document.visibilityState === 'hidden') return

  const base = import.meta.env.BASE_URL
  const response = await fetch(`${base}index.html?update=${Date.now()}`, { cache: 'no-store' })
  if (!response.ok) return

  const latestEntryPath = entryScriptPathFrom(await response.text())
  const currentEntryPath = currentEntryScriptPath()
  if (!latestEntryPath || !currentEntryPath || latestEntryPath === currentEntryPath) return

  const registration = await navigator.serviceWorker?.getRegistration(base)
  await registration?.update().catch(() => undefined)
  window.location.reload()
}

export function startAppUpdatePolling(): () => void {
  if (import.meta.env.DEV) return () => undefined

  let timer: number | undefined
  const check = () => {
    checkForAppUpdate().catch(() => undefined)
  }
  const handleVisibilityChange = () => {
    if (document.visibilityState === 'visible') check()
  }

  window.addEventListener('focus', check)
  document.addEventListener('visibilitychange', handleVisibilityChange)
  timer = window.setInterval(check, CHECK_INTERVAL_MS)
  window.setTimeout(check, 3_000)

  return () => {
    window.removeEventListener('focus', check)
    document.removeEventListener('visibilitychange', handleVisibilityChange)
    if (timer !== undefined) window.clearInterval(timer)
  }
}
