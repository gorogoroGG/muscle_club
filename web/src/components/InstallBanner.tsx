import { useEffect, useState } from 'react'
import { IconShare } from './Icons'

function isIos(): boolean {
  return /iphone|ipad|ipod/i.test(window.navigator.userAgent)
}

function isStandalone(): boolean {
  return (
    window.matchMedia('(display-mode: standalone)').matches ||
    (window.navigator as unknown as { standalone?: boolean }).standalone === true
  )
}

const DISMISS_KEY = 'muscle-club-install-banner-dismissed'

export function InstallBanner() {
  const [visible, setVisible] = useState(false)

  useEffect(() => {
    if (isIos() && !isStandalone() && !localStorage.getItem(DISMISS_KEY)) {
      setVisible(true)
    }
  }, [])

  if (!visible) return null

  return (
    <div className="install-banner">
      <span>
        ホーム画面に追加すると通知を受け取れます。共有ボタン
        <IconShare size={14} className="inline-icon" />
        から<strong>「ホーム画面に追加」</strong>を選んでください。
      </span>
      <button
        className="ghost-button"
        onClick={() => {
          localStorage.setItem(DISMISS_KEY, '1')
          setVisible(false)
        }}
      >
        ✕
      </button>
    </div>
  )
}
