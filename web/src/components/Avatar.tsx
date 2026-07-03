import { AVATAR_COLOR_HEX, type Member } from '../types'

export function Avatar({ member, size = 40 }: { member: Member; size?: number }) {
  const color = AVATAR_COLOR_HEX[member.avatar_color] ?? '#4AADFF'
  return (
    <div
      className="avatar"
      style={{
        width: size,
        height: size,
        fontSize: size * 0.36,
        backgroundColor: `${color}29`,
        color,
        border: `1.5px solid ${color}66`,
      }}
    >
      {member.initials}
    </div>
  )
}
