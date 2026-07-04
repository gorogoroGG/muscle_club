import { useEffect, type ReactNode } from 'react'
import { useGymStore } from '../store/GymStoreContext'
import { formatDateTime } from '../lib/date'
import { IconCheck, IconDumbbell, IconLogOut, IconMoon, IconXCircle } from './Icons'
import type { AppNotificationType } from '../types'

const META: Record<AppNotificationType, { icon: ReactNode; tone: string }> = {
  going: { icon: <IconDumbbell size={18} />, tone: 'tone-pink' },
  notGoing: { icon: <IconMoon size={18} />, tone: 'tone-blue' },
  checkedIn: { icon: <IconCheck size={18} />, tone: 'tone-green' },
  checkedOut: { icon: <IconLogOut size={18} />, tone: 'tone-orange' },
  checkInCancelled: { icon: <IconXCircle size={18} />, tone: 'tone-red' },
}

export function NotificationsSheet({ onClose }: { onClose: () => void }) {
  const store = useGymStore()

  useEffect(() => {
    store.markNotificationsRead()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div className="sheet-backdrop" onClick={onClose}>
      <div className="sheet" onClick={(e) => e.stopPropagation()}>
        <div className="sheet-header">
          <h2>通知</h2>
          <button className="ghost-button" onClick={onClose}>
            閉じる
          </button>
        </div>
        <div className="sheet-body">
          {store.notifications.length === 0 ? (
            <div className="empty-state">
              <p>まだ通知はありません</p>
              <p className="empty-state-sub">参加予定やチェックインがあると、ここに通知が届きます。</p>
            </div>
          ) : (
            store.notifications.map((notification) => (
              <div key={notification.id} className="notification-row">
                <div className={`notification-icon ${META[notification.type].tone}`}>
                  {META[notification.type].icon}
                </div>
                <div className="notification-body">
                  <div className="notification-title">{notification.title}</div>
                  <div className="notification-message">{notification.message}</div>
                  <div className="notification-time">{formatDateTime(notification.created_at)}</div>
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  )
}
