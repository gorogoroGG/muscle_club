import { useMemo, useState } from 'react'
import { useGymStore } from '../store/GymStoreContext'
import { Card } from '../components/Card'
import { Avatar } from '../components/Avatar'
import type { RankingPeriod } from '../types'

const PERIOD_LABEL: Record<RankingPeriod, string> = {
  week: '今週',
  month: '今月',
  all: '通算',
}

export function RecordPage() {
  const store = useGymStore()
  const [period, setPeriod] = useState<RankingPeriod>('month')

  const weekStats = useMemo(() => store.visitStatsForWeek(), [store])
  const ranking = useMemo(() => store.rankingForPeriod(period), [period, store])
  const totalCount = weekStats.reduce((sum, stat) => sum + stat.count, 0)
  const maxCount = Math.max(1, ...weekStats.map((stat) => stat.count))
  const hasRankingData = ranking.some((entry) => entry.count > 0)

  return (
    <div className="page">
      <header>
        <div className="eyebrow">RANKING</div>
        <h1>ランキング</h1>
        <p className="muted">ジムに行った回数だけで比べます。滞在時間は集計していません。</p>
      </header>

      <Card title="THIS WEEK">
        <div className="stat-row">
          <div>
            <div className="muted small">あなたの今週</div>
            <div className="stat-value accent">{totalCount}回</div>
          </div>
          <div>
            <div className="muted small">今月</div>
            <div className="stat-value">{store.currentUserMonthCount}回</div>
          </div>
        </div>
        <div className="bar-chart" key={totalCount}>
          {weekStats.map((stat, index) => (
            <div key={stat.label} className="bar-chart-column">
              <div
                className="bar-chart-bar"
                style={{
                  height: `${Math.max(4, (stat.count / maxCount) * 100)}%`,
                  animationDelay: `${index * 45}ms`,
                }}
              />
              <span className="bar-chart-label">{stat.label}</span>
            </div>
          ))}
        </div>
      </Card>

      <div className="period-tabs">
        {(['week', 'month', 'all'] as RankingPeriod[]).map((item) => (
          <button key={item} className={period === item ? 'active' : ''} onClick={() => setPeriod(item)}>
            {PERIOD_LABEL[item]}
          </button>
        ))}
      </div>

      <Card title="COUNT RANKING">
        <h3 className="section-heading">{PERIOD_LABEL[period]}の回数ランキング</h3>
        {!hasRankingData ? (
          <p className="muted">まだ記録がありません。</p>
        ) : (
          <div className="comparison-list" key={period}>
            {ranking.map((entry) => (
              <div key={entry.member.id} className={`comparison-row${entry.isCurrentUser ? ' is-me' : ''}`}>
                <span className={`rank${entry.rank <= 3 ? ' top' : ''}`}>{entry.rank}</span>
                <Avatar member={entry.member} size={40} />
                <div className="comparison-info">
                  <div>{entry.isCurrentUser ? `${entry.member.name} (あなた)` : entry.member.name}</div>
                  <div className="muted small">{PERIOD_LABEL[period]}</div>
                </div>
                <span className="badge">{entry.count}回</span>
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  )
}
