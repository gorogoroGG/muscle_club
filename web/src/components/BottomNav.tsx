import { NavLink } from 'react-router-dom'

const TABS = [
  { to: '/', label: 'ホーム', icon: '🏠' },
  { to: '/record', label: '記録', icon: '📊' },
  { to: '/me', label: 'マイ', icon: '👤' },
]

export function BottomNav() {
  return (
    <nav className="bottom-nav">
      {TABS.map((tab) => (
        <NavLink
          key={tab.to}
          to={tab.to}
          end={tab.to === '/'}
          className={({ isActive }) => `bottom-nav-item${isActive ? ' active' : ''}`}
        >
          <span className="bottom-nav-icon">{tab.icon}</span>
          <span>{tab.label}</span>
        </NavLink>
      ))}
    </nav>
  )
}
