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
  user_id: string | null
  email: string | null
  name: string
  initials: string
  avatar_color: AvatarColor
  avatar_url: string | null
  created_at?: string
  updated_at?: string
}

export type DailyIntentStatus = 'going' | 'not_going'

export interface DailyIntent {
  id: string
  member_id: string
  date: string
  status: DailyIntentStatus
  created_at?: string
  updated_at?: string
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

export type RankingPeriod = 'week' | 'month' | 'all'

export interface RankingEntry {
  member: Member
  count: number
  rank: number
  isCurrentUser: boolean
}

export interface PeriodStat {
  label: string
  start: Date
  count: number
}

export type AppMode = 'loading' | 'auth' | 'signedIn' | 'failed'
