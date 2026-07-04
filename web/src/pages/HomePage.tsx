import { useState, type ReactNode } from 'react'
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
  IconUndo,
} from '../components/Icons'
import { formatMinutes } from '../lib/date'
import type { Member } from '../types'

export function HomePage() {
  const store = useGymStore()
  const [showNotifications, setShowNotifications] = useState(false)
  const [showCancelConfirm, setShowCancelConfirm] = useState(false)

  if (!store.currentUser) return null

  const status = store.todayStatus(store.currentUser.id)

  return (
    <div className="page">
      <header className="home-header">
        <div className="eyebrow">TODAY</div>
        <div className="home-header-row">
          <h1>今日のジム</h1>
          <button className="bell-button" onClick={() => setShowNotifications(true)} aria-label="通知">
            <IconBell size={20} />
            {store.unreadNotificationCount > 0 && (
              <span className="badge-dot">{Math.min(store.unreadNotificationCount, 9)}</span>
            )}
          </button>
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
              <button className="primary-button" onClick={() => store.checkOut()}>
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
            </>
          ) : (
            <>
              <div className="status-circle idle">
                <IconMapPin size={40} />
              </div>
              <p className="status-label">未チェックイン</p>
              <button className="primary-button" onClick={() => store.checkIn()}>
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
