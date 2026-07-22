import { useState, type ReactNode } from 'react'
import { useGymStore } from '../store/GymStoreContext'
import { Card } from '../components/Card'
import { Avatar } from '../components/Avatar'
import {
  IconCalendar,
  IconCheck,
  IconDumbbell,
  IconLogOut,
  IconMoon,
  IconRefresh,
  IconUndo,
  IconUser,
} from '../components/Icons'
import type { Member, TodayGymStatus } from '../types'

export function HomePage() {
  const store = useGymStore()
  const [isReloading, setIsReloading] = useState(false)

  const currentUserId = store.currentUser?.id ?? null
  const status = currentUserId ? store.todayStatus(currentUserId) : null

  function handleReload() {
    setIsReloading(true)
    store.reload()
    window.setTimeout(() => setIsReloading(false), 700)
  }

  if (!store.currentUser) return null

  return (
    <div className="page">
      <header className="home-header">
        <div className="eyebrow">TODAY</div>
        <div className="home-header-row">
          <div>
            <h1>今日のジム</h1>
            <p className="muted">行く人、今いる人、終わった人をひと目で確認できます。</p>
          </div>
          <button className={`bell-button${isReloading ? ' is-spinning' : ''}`} onClick={handleReload} aria-label="ロード" title="ロード">
            <IconRefresh size={19} />
          </button>
        </div>
      </header>

      <Card title="MY STATUS">
        <div className="current-user-strip">
          <Avatar member={store.currentUser} size={48} />
          <div>
            <div className="current-user-name">{store.currentUser.name}</div>
            <div className="muted small">{statusLabel(status)}</div>
          </div>
        </div>
        <div className="intent-row">
          <button
            className={`intent-button danger${store.isCurrentUserGoing ? ' expanded' : ''}`}
            disabled={store.isCurrentUserCheckedIn}
            onClick={() => store.setTodayIntent(store.isCurrentUserGoing ? null : 'going')}
          >
            <span className="intent-icon">
              <IconDumbbell size={28} />
            </span>
            <span>行く</span>
          </button>
          <button
            className={`intent-button accent${store.isCurrentUserNotGoing ? ' expanded' : ''}`}
            disabled={store.isCurrentUserCheckedIn}
            onClick={() => store.setTodayIntent(store.isCurrentUserNotGoing ? null : 'not_going')}
          >
            <span className="intent-icon">
              <IconMoon size={28} />
            </span>
            <span>行かない</span>
          </button>
        </div>
      </Card>

      <Card title="CHECK-IN">
        <div className="checkin-status">
          {status === 'checkedIn' ? (
            <>
              <button className="status-circle checked-in" onClick={() => store.checkOut()} aria-label="チェックアウト">
                <IconCheck size={52} strokeWidth={2.5} />
              </button>
              <p className="status-label">今ジムにいます</p>
              <button className="primary-button" onClick={() => store.checkOut()}>
                チェックアウトする
              </button>
              <button className="text-link" onClick={() => store.cancelCheckIn()}>
                チェックインを取り消す
              </button>
            </>
          ) : status === 'checkedOut' ? (
            <>
              <div className="status-circle checked-out">
                <IconUndo size={44} />
              </div>
              <p className="status-label">今日のトレーニングは完了</p>
              <button className="secondary-button" onClick={() => store.cancelCheckOut()}>
                完了を取り消して在館中に戻す
              </button>
            </>
          ) : status === 'notGoing' ? (
            <>
              <div className="status-circle not-going">
                <IconMoon size={38} />
              </div>
              <p className="status-label">今日は行かない予定</p>
              <button className="secondary-button" onClick={() => store.setTodayIntent(null)}>
                予定を未定に戻す
              </button>
            </>
          ) : (
            <>
              <div className="status-circle idle">
                <IconDumbbell size={40} />
              </div>
              <p className="status-label">{status === 'goingNotArrived' ? '行く予定です' : 'まだ未チェックイン'}</p>
              <button className="primary-button" onClick={() => store.checkIn()}>
                チェックインする
              </button>
            </>
          )}
        </div>
      </Card>

      <Card title="CLUB">
        <h3 className="section-heading">メンバーの状況</h3>
        <div className="status-flow">
          <StatusStage
            tone="going"
            icon={<IconCalendar size={14} />}
            label="今日行く"
            members={store.todayGoingNotArrivedMembers}
            emptyText="まだ予定している人はいません"
          />
          <StatusStage
            tone="checkedin"
            icon={<IconDumbbell size={14} />}
            label="今ジムにいる"
            members={store.todayCheckedInMembers}
            emptyText="今ジムにいる人はいません"
          />
          <StatusStage
            tone="checkedout"
            icon={<IconLogOut size={14} />}
            label="終わった"
            members={store.todayCheckedOutMembers}
            emptyText="まだ完了した人はいません"
          />
          <StatusStage
            tone="notgoing"
            icon={<IconMoon size={14} />}
            label="行かない"
            members={store.todayNotGoingMembers}
            emptyText="行かない予定の人はいません"
          />
          <StatusStage
            tone="unknown"
            icon={<IconUser size={14} />}
            label="未定"
            members={store.todayUnknownMembers}
            emptyText="全員の状況が出ています"
          />
        </div>
      </Card>

      <Card title="SUMMARY">
        <h3 className="section-heading">あなたの回数</h3>
        <div className="metric-grid">
          <div className="metric-tile">
            <div className="metric-value">{store.currentUserMonthCount}回</div>
            <div className="metric-label">今月</div>
          </div>
          <div className="metric-tile">
            <div className="metric-value">{store.currentUserMonthRank ? `${store.currentUserMonthRank}位` : '-'}</div>
            <div className="metric-label">今月順位</div>
          </div>
          <div className="metric-tile">
            <div className="metric-value">{store.currentUserTotalCount}回</div>
            <div className="metric-label">通算</div>
          </div>
        </div>
      </Card>

      {store.lastErrorMessage && (
        <Card title="ERROR">
          <div className="message-block danger">{store.lastErrorMessage}</div>
        </Card>
      )}
    </div>
  )
}

function statusLabel(status: TodayGymStatus | null): string {
  switch (status) {
    case 'checkedIn':
      return '今ジムにいます'
    case 'checkedOut':
      return '今日のトレーニングは完了'
    case 'goingNotArrived':
      return '今日は行く予定'
    case 'notGoing':
      return '今日は行かない予定'
    default:
      return '今日はまだ未定'
  }
}

function StatusStage({
  tone,
  icon,
  label,
  members,
  emptyText,
}: {
  tone: 'going' | 'checkedin' | 'checkedout' | 'notgoing' | 'unknown'
  icon: ReactNode
  label: string
  members: Member[]
  emptyText: string
}) {
  const active = members.length > 0
  return (
    <div className={`status-stage tone-${tone}${active ? ' is-active' : ''}`}>
      <div className="status-stage-header">
        <span className="status-stage-icon">{icon}</span>
        <span>{label}</span>
        <span className="status-count">{members.length}</span>
      </div>
      {active ? (
        <div className="status-stage-chips">
          {members.map((member) => (
            <div key={member.id} className="member-chip">
              <Avatar member={member} size={38} />
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
