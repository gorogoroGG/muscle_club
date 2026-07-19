export type AvatarColor =
  | 'blue'
  | 'indigo'
  | 'pink'
  | 'green'
  | 'orange'
  | 'teal'
  | 'purple'
  | 'red'
  | 'yellow'

export const AVATAR_COLOR_HEX: Record<AvatarColor, string> = {
  blue: '#4AADFF',
  indigo: '#6E7BFF',
  pink: '#FF6FB5',
  green: '#4ADE80',
  orange: '#FFA24A',
  teal: '#64F5C2',
  purple: '#B084F5',
  red: '#FF7575',
  yellow: '#FFD24A',
}

export interface Member {
  id: string
  name: string
  initials: string
  avatar_color: AvatarColor
  avatar_url: string | null
  claimed_by: string | null
}

export type AttendanceType = 'going' | 'notGoing'

export interface AttendanceRecord {
  id: string
  member_id: string
  date: string
  type: AttendanceType
}

export interface GymVisit {
  id: string
  member_id: string
  check_in_at: string
  check_out_at: string | null
}

export type AppNotificationType =
  | 'going'
  | 'notGoing'
  | 'checkedIn'
  | 'checkedOut'
  | 'checkInCancelled'

export interface AppNotification {
  id: string
  recipient_member_id: string
  actor_member_id: string | null
  type: AppNotificationType
  title: string
  message: string
  created_at: string
  read_at: string | null
}

export type TodayGymStatus = 'checkedIn' | 'checkedOut' | 'goingNotArrived' | 'notGoing'

export interface PeriodStat {
  label: string
  start: Date
  count: number
  minutes: number
}

export interface MemberComparisonEntry {
  member: Member
  count: number
  minutes: number
}

export type AppMode = 'loading' | 'auth' | 'claiming' | 'signedIn' | 'failed'
