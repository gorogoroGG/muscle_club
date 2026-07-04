import { NavLink } from 'react-router-dom'
import { IconChart, IconHome, IconUser } from './Icons'

const TABS = [
  { to: '/', label: 'ホーム', Icon: IconHome },
  { to: '/record', label: '記録', Icon: IconChart },
  { to: '/me', label: 'マイ', Icon: IconUser },
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
          <span className="bottom-nav-icon">
            <tab.Icon size={19} />
          </span>
          <span>{tab.label}</span>
        </NavLink>
      ))}
    </nav>
  )
}
