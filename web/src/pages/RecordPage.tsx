import { useMemo, useState } from 'react'
import { useGymStore } from '../store/GymStoreContext'
import { Card } from '../components/Card'
import { Avatar } from '../components/Avatar'
import { formatMinutes } from '../lib/date'

type Period = 'week' | 'month'

export function RecordPage() {
  const store = useGymStore()
  const [period, setPeriod] = useState<Period>('week')

  const stats = useMemo(
    () => (period === 'week' ? store.dailyStatsForWeek() : store.monthlyStats(6)),
    [period, store],
  )

  const comparison = useMemo(
    () => (period === 'week' ? store.memberComparisonForWeek() : store.memberComparisonForMonth()),
    [period, store],
  )

  const totalMinutes = stats.reduce((sum, s) => sum + s.minutes, 0)
  const totalCount = stats.reduce((sum, s) => sum + s.count, 0)
  const maxMinutes = Math.max(1, ...stats.map((s) => s.minutes))
  const hasComparisonData = comparison.some((c) => c.minutes > 0 || c.count > 0)

  return (
    <div className="page">
      <header>
        <div className="eyebrow">RECORD</div>
        <h1>記録</h1>
        <p className="muted">ジムにいた時間と回数を振り返れます。</p>
      </header>

      <div className="segmented-control">
        <div className={`segmented-thumb${period === 'month' ? ' right' : ''}`} />
        <button className={period === 'week' ? 'active' : ''} onClick={() => setPeriod('week')}>
          週間
        </button>
        <button className={period === 'month' ? 'active' : ''} onClick={() => setPeriod('month')}>
          月間
        </button>
      </div>

      <Card title={period === 'week' ? 'THIS WEEK' : 'LAST 6 MONTHS'}>
        <div className="stat-row">
          <div>
            <div className="muted small">滞在時間</div>
            <div className="stat-value">{formatMinutes(totalMinutes)}</div>
          </div>
          <div>
            <div className="muted small">回数</div>
            <div className="stat-value accent">{totalCount}回</div>
          </div>
        </div>
        <div className="bar-chart" key={period}>
          {stats.map((stat, index) => (
            <div key={stat.label} className="bar-chart-column">
              <div
                className="bar-chart-bar"
                style={{
                  height: `${Math.max(4, (stat.minutes / maxMinutes) * 100)}%`,
                  animationDelay: `${index * 45}ms`,
                }}
              />
              <span className="bar-chart-label">{stat.label}</span>
            </div>
          ))}
        </div>
      </Card>

      <Card title="COMPARISON">
        <h3 className="section-heading">{period === 'week' ? '今週のメンバー比較' : '今月のメンバー比較'}</h3>
        {!hasComparisonData ? (
          <p className="muted">まだ記録がありません。</p>
        ) : (
          <div className="comparison-list" key={period}>
            {comparison.map((item, index) => (
              <div key={item.member.id} className="comparison-row">
                <span className={`rank${index < 3 ? ' top' : ''}`}>{index + 1}</span>
                <Avatar member={item.member} size={40} />
                <div className="comparison-info">
                  <div>{item.member.id === store.currentUser?.id ? `${item.member.name} (あなた)` : item.member.name}</div>
                  <div className="muted small">{item.count}回</div>
                </div>
                <span className="badge">{formatMinutes(item.minutes)}</span>
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  )
}
