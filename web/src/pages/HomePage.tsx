import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { useGymStore } from '../store/GymStoreContext'
import { Card } from '../components/Card'
import { Avatar } from '../components/Avatar'
import { NotificationsSheet } from '../components/NotificationsSheet'
import {
  IconBell,
  IconCalendar,
  IconCheck,
  IconDumbbell,
  IconLogOut,
  IconMapPin,
  IconMoon,
  IconRefresh,
  IconUndo,
} from '../components/Icons'
import { formatMinutes } from '../lib/date'
import type { Member } from '../types'

type ConfirmAction = 'checkIn' | 'checkOut'

export function HomePage() {
  const store = useGymStore()
  const [showNotifications, setShowNotifications] = useState(false)
  const [showCancelConfirm, setShowCancelConfirm] = useState(false)
  const [confirmAction, setConfirmAction] = useState<ConfirmAction | null>(null)
  const [now, setNow] = useState(() => new Date())
  const [isReloading, setIsReloading] = useState(false)
  const [pullStartY, setPullStartY] = useState<number | null>(null)
  const [pullDistance, setPullDistance] = useState(0)

  const currentUserId = store.currentUser?.id ?? null
  const status = currentUserId ? store.todayStatus(currentUserId) : null
  const currentVisit = useMemo(
    () => store.gymVisits.find((v) => v.member_id === currentUserId && v.check_out_at === null) ?? null,
    [currentUserId, store.gymVisits],
  )
  const elapsedSeconds = currentVisit
    ? Math.max(0, Math.floor((now.getTime() - new Date(currentVisit.check_in_at).getTime()) / 1000))
    : 0
  const confirmCopy =
    confirmAction === 'checkIn'
      ? {
          title: 'チェックインしますか?',
          message: '今からジム滞在時間の記録を開始します。',
          button: 'チェックインする',
        }
      : {
          title: 'チェックアウトしますか?',
          message: '現在の滞在時間をここで終了して記録します。',
          button: 'チェックアウトする',
        }

  useEffect(() => {
    if (!currentVisit) return
    setNow(new Date())
    const timer = window.setInterval(() => setNow(new Date()), 1000)
    return () => window.clearInterval(timer)
  }, [currentVisit])

  function handleReload() {
    setIsReloading(true)
    store.reload()
    window.setTimeout(() => setIsReloading(false), 700)
  }

  function handlePullStart(clientY: number) {
    if (window.scrollY <= 0) setPullStartY(clientY)
  }

  function handlePullMove(clientY: number) {
    if (pullStartY === null || window.scrollY > 0) return
    const distance = clientY - pullStartY
    if (distance > 0) setPullDistance(Math.min(distance, 120))
  }

  function handlePullEnd() {
    if (pullDistance > 72) handleReload()
    setPullStartY(null)
    setPullDistance(0)
  }

  if (!store.currentUser) return null

  return (
    <div
      className="page"
      onTouchStart={(event) => handlePullStart(event.touches[0]?.clientY ?? 0)}
      onTouchMove={(event) => handlePullMove(event.touches[0]?.clientY ?? 0)}
      onTouchEnd={handlePullEnd}
    >
      <div
        className={`pull-refresh${pullDistance > 72 ? ' is-ready' : ''}${isReloading ? ' is-loading' : ''}`}
        style={{
          opacity: pullDistance > 6 || isReloading ? 1 : 0,
          transform: `translate(-50%, ${Math.min(pullDistance, 96) - 68}px)`,
        }}
      >
        <IconRefresh size={15} />
        <span>{isReloading ? 'ロード中' : pullDistance > 72 ? '離してロード' : '下に引っ張ってロード'}</span>
      </div>
      <header className="home-header">
        <div className="eyebrow">TODAY</div>
        <div className="home-header-row">
          <h1>今日のジム</h1>
          <div className="home-header-actions">
            <button className="bell-button" onClick={handleReload} aria-label="ロード" title="ロード">
              <IconRefresh size={19} />
            </button>
            <button className="bell-button" onClick={() => setShowNotifications(true)} aria-label="通知">
              <IconBell size={20} />
              {store.unreadNotificationCount > 0 && (
                <span className="badge-dot">{Math.min(store.unreadNotificationCount, 9)}</span>
              )}
            </button>
          </div>
        </div>
      </header>

      <Card title="今日の予定">
        <div className="intent-row">
          {!store.isCurrentUserNotGoing && (
            <button
              className={`intent-button danger${store.isCurrentUserGoing ? ' expanded' : ''}`}
              disabled={store.isCurrentUserCheckedIn}
              onClick={() => store.toggleGoing()}
            >
              <span className="intent-icon">
                <IconDumbbell size={28} />
              </span>
              <span>参加</span>
            </button>
          )}
          {!store.isCurrentUserGoing && (
            <button
              className={`intent-button accent${store.isCurrentUserNotGoing ? ' expanded' : ''}`}
              disabled={store.isCurrentUserCheckedIn}
              onClick={() => store.toggleNotGoing()}
            >
              <span className="intent-icon">
                <IconMoon size={28} />
              </span>
              <span>不参加</span>
            </button>
          )}
        </div>
      </Card>

      <Card title="CHECK-IN">
        <div className="checkin-status">
          {status === 'checkedIn' ? (
            <>
              <button className="status-circle checked-in" onClick={() => setShowCancelConfirm(true)}>
                <IconCheck size={52} strokeWidth={2.5} />
              </button>
              <p className="status-label">チェックイン済み</p>
              {currentVisit && (
                <div className="elapsed-panel" aria-live="polite">
                  <span className="elapsed-caption">チェックインから</span>
                  <span className="elapsed-time">{formatElapsedDuration(elapsedSeconds)}</span>
                  <span className="elapsed-caption">経過</span>
                </div>
              )}
              <button className="primary-button" onClick={() => setConfirmAction('checkOut')}>
                チェックアウトする
              </button>
              <button className="text-link" onClick={() => setShowCancelConfirm(true)}>
                チェックインを取り消す
              </button>
            </>
          ) : status === 'checkedOut' ? (
            <>
              <div className="status-circle checked-out">
                <IconUndo size={44} />
              </div>
              <p className="status-label">チェックアウト済み</p>
              <button className="text-link checkout-cancel-link" onClick={() => store.cancelCheckOut()}>
                チェックアウトを取り消す
              </button>
            </>
          ) : (
            <>
              <div className="status-circle idle">
                <IconMapPin size={40} />
              </div>
              <p className="status-label">未チェックイン</p>
              <button className="primary-button" onClick={() => setConfirmAction('checkIn')}>
                チェックインする
              </button>
            </>
          )}
        </div>
      </Card>

      <Card title="TODAY">
        <h3 className="section-heading">今日の様子</h3>
        <div className="status-flow">
          <StatusStage
            tone="going"
            icon={<IconCalendar size={14} />}
            label="予定"
            members={store.todayGoingNotArrivedMembers}
            emptyText="まだ誰も予定していません"
          />
          <div className="status-flow-arrow">↓</div>
          <StatusStage
            tone="checkedin"
            icon={<IconDumbbell size={14} />}
            label="ジムにいる"
            members={store.todayCheckedInMembers}
            emptyText="今チェックイン中の人はいません"
          />
          <div className="status-flow-arrow">↓</div>
          <StatusStage
            tone="checkedout"
            icon={<IconLogOut size={14} />}
            label="チェックアウト済み"
            members={store.todayCheckedOutMembers}
            emptyText="まだ誰も退出していません"
          />
        </div>
      </Card>

      <Card title="SUMMARY">
        <h3 className="section-heading">今月のサマリー</h3>
        <div className="metric-grid">
          <div className="metric-tile">
            <div className="metric-value">{store.currentUserMonthCount}回</div>
            <div className="metric-label">今月</div>
          </div>
          <div className="metric-tile">
            <div className="metric-value">{store.currentStreak}日</div>
            <div className="metric-label">連続</div>
          </div>
          <div className="metric-tile">
            <div className="metric-value">{formatMinutes(store.currentUserMonthMinutes)}</div>
            <div className="metric-label">滞在時間</div>
          </div>
        </div>
      </Card>

      {showNotifications && <NotificationsSheet onClose={() => setShowNotifications(false)} />}

      {confirmAction && (
        <div className="sheet-backdrop" onClick={() => setConfirmAction(null)}>
          <div className="popup-card" onClick={(e) => e.stopPropagation()}>
            <h3>{confirmCopy.title}</h3>
            <p>{confirmCopy.message}</p>
            <button
              className="primary-button"
              onClick={async () => {
                const action = confirmAction
                setConfirmAction(null)
                if (action === 'checkIn') {
                  await store.checkIn()
                } else {
                  await store.checkOut()
                }
              }}
            >
              {confirmCopy.button}
            </button>
            <button className="ghost-button" onClick={() => setConfirmAction(null)}>
              閉じる
            </button>
          </div>
        </div>
      )}

      {showCancelConfirm && (
        <div className="sheet-backdrop" onClick={() => setShowCancelConfirm(false)}>
          <div className="popup-card" onClick={(e) => e.stopPropagation()}>
            <h3>チェックインを取り消しますか?</h3>
            <p>間違ってチェックインした場合に取り消せます。</p>
            <button
              className="secondary-button danger"
              onClick={() => {
                store.cancelCheckIn()
                setShowCancelConfirm(false)
              }}
            >
              チェックインを取り消す
            </button>
            <button className="ghost-button" onClick={() => setShowCancelConfirm(false)}>
              閉じる
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

function formatElapsedDuration(totalSeconds: number): string {
  const hours = Math.floor(totalSeconds / 3600)
  const minutes = Math.floor((totalSeconds % 3600) / 60)
  const seconds = totalSeconds % 60
  const paddedMinutes = String(minutes).padStart(hours > 0 ? 2 : 1, '0')
  const paddedSeconds = String(seconds).padStart(2, '0')
  return hours > 0 ? `${hours}:${paddedMinutes}:${paddedSeconds}` : `${paddedMinutes}:${paddedSeconds}`
}

function StatusStage({
  tone,
  icon,
  label,
  members,
  emptyText,
}: {
  tone: 'going' | 'checkedin' | 'checkedout'
  icon: ReactNode
  label: string
  members: Member[]
  emptyText: string
}) {
  const isActive = members.length > 0
  return (
    <div className={`status-stage tone-${tone}${isActive ? ' is-active' : ''}`}>
      <div className="status-stage-header">
        <span className="status-stage-icon">{icon}</span>
        <span>{label}</span>
      </div>
      {isActive ? (
        <div className="status-stage-chips">
          {members.map((member) => (
            <div key={member.id} className="member-chip">
              <Avatar member={member} size={40} />
              <span>{member.name}</span>
            </div>
          ))}
        </div>
      ) : (
        <p className="status-stage-empty">{emptyText}</p>
      )}
    </div>
  )
}
