import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import type { Session } from '@supabase/supabase-js'
import { isSupabaseConfigured, supabase } from '../lib/supabaseClient'
import {
  addDays,
  addMonths,
  isDateInToday,
  isSameDay,
  isSameMonth,
  minutesBetween,
  mondayOfWeek,
  monthLabel,
  startOfDay,
  weekdayLabel,
} from '../lib/date'
import { isGymClosed } from '../lib/gymHours'
import type {
  AppMode,
  AppNotification,
  AppNotificationType,
  AttendanceRecord,
  GymVisit,
  Member,
  MemberComparisonEntry,
  PeriodStat,
  TodayGymStatus,
} from '../types'

function defaultInitials(name: string): string {
  const normalized = name.toUpperCase().replace(/[^A-Z0-9]/g, '')
  const prefix = normalized.slice(0, 2)
  return prefix.padEnd(2, 'M')
}

// Dev-only demo mode (?demo=1): renders the signed-in screens with local mock
// data and no Supabase traffic, so UI work doesn't require claiming a real
// member. Dead-code-eliminated from production builds via import.meta.env.DEV.
const DEMO_MODE = import.meta.env.DEV && new URLSearchParams(window.location.search).has('demo')
const DEMO_AUTH_ID = 'demo-auth'

function demoData() {
  const now = new Date()
  const at = (daysAgo: number, hour: number, minute = 0) => {
    const d = new Date(now)
    d.setDate(d.getDate() - daysAgo)
    d.setHours(hour, minute, 0, 0)
    return d.toISOString()
  }
  const members: Member[] = [
    { id: 'm-yugo', name: 'ゆーご', initials: 'YG', avatar_color: 'teal', avatar_url: null, claimed_by: DEMO_AUTH_ID },
    { id: 'm-manase', name: 'まなせ', initials: 'MN', avatar_color: 'pink', avatar_url: null, claimed_by: 'other-1' },
    { id: 'm-icchi', name: 'いっちー', initials: 'IC', avatar_color: 'green', avatar_url: null, claimed_by: 'other-2' },
    { id: 'm-ukasu', name: 'うーかす', initials: 'UK', avatar_color: 'orange', avatar_url: null, claimed_by: 'other-3' },
  ]
  const gymVisits: GymVisit[] = [
    { id: 'v-open', member_id: 'm-manase', check_in_at: at(0, Math.max(0, now.getHours() - 1)), check_out_at: null },
    { id: 'v-done', member_id: 'm-ukasu', check_in_at: at(0, 7), check_out_at: at(0, 8, 30) },
    ...[1, 2, 4, 6, 9, 12, 16, 20].map((d, i) => ({
      id: `vh-${i}`,
      member_id: 'm-yugo',
      check_in_at: at(d, 19),
      check_out_at: at(d, 20, 15),
    })),
    ...[1, 3, 5].map((d, i) => ({
      id: `vm-${i}`,
      member_id: 'm-manase',
      check_in_at: at(d, 18),
      check_out_at: at(d, 19),
    })),
  ]
  const attendanceRecords: AttendanceRecord[] = [
    { id: 'a-1', member_id: 'm-yugo', date: now.toISOString(), type: 'going' },
    { id: 'a-2', member_id: 'm-icchi', date: now.toISOString(), type: 'going' },
    { id: 'a-3', member_id: 'm-ukasu', date: now.toISOString(), type: 'notGoing' },
  ]
  const notifications: AppNotification[] = [
    {
      id: 'n-1',
      recipient_member_id: 'm-yugo',
      actor_member_id: 'm-manase',
      type: 'checkedIn',
      title: 'チェックインがありました',
      message: 'まなせ さんがジムに到着しました。',
      created_at: at(0, Math.max(0, now.getHours() - 1)),
      read_at: null,
    },
    {
      id: 'n-2',
      recipient_member_id: 'm-yugo',
      actor_member_id: 'm-icchi',
      type: 'going',
      title: '参加予定が更新されました',
      message: 'いっちー さんが「参加」を選びました。',
      created_at: at(0, 9),
      read_at: null,
    },
  ]
  return { members, gymVisits, attendanceRecords, notifications }
}

interface GymStoreValue {
  appMode: AppMode
  session: Session | null
  members: Member[]
  unclaimedMembers: Member[]
  attendanceRecords: AttendanceRecord[]
  gymVisits: GymVisit[]
  notifications: AppNotification[]
  lastErrorMessage: string | null
  currentUser: Member | null
  isCurrentUserGoing: boolean
  isCurrentUserNotGoing: boolean
  isCurrentUserCheckedIn: boolean
  unreadNotificationCount: number
  todayStatus: (memberId: string) => TodayGymStatus | null
  todayCheckedInMembers: Member[]
  todayCheckedOutMembers: Member[]
  todayGoingNotArrivedMembers: Member[]
  todayNotGoingMembers: Member[]
  currentStreak: number
  currentUserMonthCount: number
  currentUserMonthMinutes: number
  dailyStatsForWeek: (date?: Date, memberId?: string) => PeriodStat[]
  monthlyStats: (monthsBack?: number, memberId?: string) => PeriodStat[]
  memberComparisonForWeek: (date?: Date) => MemberComparisonEntry[]
  memberComparisonForMonth: (date?: Date) => MemberComparisonEntry[]
  claimMember: (memberId: string) => Promise<{ error: string | null }>
  resetIdentity: () => Promise<void>
  toggleGoing: () => Promise<void>
  toggleNotGoing: () => Promise<void>
  checkIn: () => Promise<void>
  checkOut: () => Promise<void>
  cancelCheckIn: () => Promise<void>
  cancelCheckOut: () => Promise<void>
  markNotificationsRead: () => Promise<void>
  updateProfile: (name: string) => Promise<void>
  updateAvatar: (image: Blob) => Promise<{ error: string | null }>
  reload: () => void
}

const GymStoreContext = createContext<GymStoreValue | null>(null)

export function GymStoreProvider({ children }: { children: ReactNode }) {
  const [appMode, setAppMode] = useState<AppMode>('loading')
  const [session, setSession] = useState<Session | null>(null)
  const [members, setMembers] = useState<Member[]>([])
  const [attendanceRecords, setAttendanceRecords] = useState<AttendanceRecord[]>([])
  const [gymVisits, setGymVisits] = useState<GymVisit[]>([])
  const [notifications, setNotifications] = useState<AppNotification[]>([])
  const [lastErrorMessage, setLastErrorMessage] = useState<string | null>(null)
  const [reloadToken, setReloadToken] = useState(0)

  const authUserId = DEMO_MODE ? DEMO_AUTH_ID : (session?.user.id ?? null)

  const currentUser = useMemo<Member | null>(() => {
    if (!authUserId) return null
    return members.find((m) => m.claimed_by === authUserId) ?? null
  }, [members, authUserId])

  const currentUserId = currentUser?.id ?? null

  const unclaimedMembers = useMemo(() => members.filter((m) => m.claimed_by === null), [members])

  // Bootstrap: reuse an existing session, or silently create an anonymous one.
  // No email is ever sent for this, so there's no OTP rate limit to hit.
  useEffect(() => {
    if (DEMO_MODE) {
      const seed = demoData()
      setMembers(seed.members)
      setGymVisits(seed.gymVisits)
      setAttendanceRecords(seed.attendanceRecords)
      setNotifications(seed.notifications)
      setAppMode('signedIn')
      return
    }

    if (!isSupabaseConfigured) {
      setLastErrorMessage('Supabase の設定がまだ入っていません。')
      setAppMode('failed')
      return
    }

    let cancelled = false

    async function bootstrap() {
      const { data } = await supabase.auth.getSession()
      if (cancelled) return
      if (data.session) {
        setSession(data.session)
        return
      }
      const { data: anon, error } = await supabase.auth.signInAnonymously()
      if (cancelled) return
      if (error) {
        setLastErrorMessage(error.message)
        setAppMode('failed')
        return
      }
      setSession(anon.session)
    }

    bootstrap()

    const { data: subscription } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession)
    })

    return () => {
      cancelled = true
      subscription.subscription.unsubscribe()
    }
  }, [])

  useEffect(() => {
    if (!session) return
    const activeSession = session
    let cancelled = false

    async function run() {
      setAppMode('loading')
      try {
        const { data: memberRows, error: membersError } = await supabase.from('members').select('*')
        if (membersError) throw membersError
        if (cancelled) return
        setMembers(memberRows as Member[])

        const claimed = (memberRows as Member[]).find((m) => m.claimed_by === activeSession.user.id)
        if (!claimed) {
          setAttendanceRecords([])
          setGymVisits([])
          setNotifications([])
          setLastErrorMessage(null)
          setAppMode('claiming')
          return
        }

        const [attendanceRes, visitsRes, notificationsRes] = await Promise.all([
          supabase.from('attendance_records').select('*'),
          supabase.from('gym_visits').select('*'),
          supabase
            .from('notifications')
            .select('*')
            .eq('recipient_member_id', claimed.id)
            .order('created_at', { ascending: false })
            .limit(100),
        ])
        if (attendanceRes.error) throw attendanceRes.error
        if (visitsRes.error) throw visitsRes.error
        if (notificationsRes.error) throw notificationsRes.error
        if (cancelled) return

        setAttendanceRecords(attendanceRes.data as AttendanceRecord[])
        setGymVisits(visitsRes.data as GymVisit[])
        setNotifications(notificationsRes.data as AppNotification[])
        setLastErrorMessage(null)
        setAppMode('signedIn')
      } catch (error) {
        if (!cancelled) {
          setLastErrorMessage(error instanceof Error ? error.message : String(error))
          setAppMode('failed')
        }
      }
    }

    run()
    return () => {
      cancelled = true
    }
  }, [session, reloadToken])

  const reload = useCallback(() => setReloadToken((t) => t + 1), [])

  // refresh when the installed PWA comes back to the foreground (e.g. after a push notification)
  useEffect(() => {
    function handleVisibility() {
      if (document.visibilityState === 'visible' && session) reload()
    }
    document.addEventListener('visibilitychange', handleVisibility)
    return () => document.removeEventListener('visibilitychange', handleVisibility)
  }, [session, reload])

  const openVisitFor = useCallback(
    (memberId: string) => gymVisits.find((v) => v.member_id === memberId && v.check_out_at === null),
    [gymVisits],
  )

  const todayAttendanceRecordFor = useCallback(
    (memberId: string) =>
      attendanceRecords
        .filter((r) => r.member_id === memberId && isDateInToday(new Date(r.date)))
        .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())[0] ?? null,
    [attendanceRecords],
  )

  const todayClosedVisitFor = useCallback(
    (memberId: string) =>
      gymVisits
        .filter((v) => v.member_id === memberId && v.check_out_at !== null && isDateInToday(new Date(v.check_in_at)))
        .sort((a, b) => new Date(b.check_in_at).getTime() - new Date(a.check_in_at).getTime())[0] ?? null,
    [gymVisits],
  )

  const isCurrentUserGoing = useMemo(
    () =>
      Boolean(currentUserId && todayAttendanceRecordFor(currentUserId)?.type === 'going'),
    [currentUserId, todayAttendanceRecordFor],
  )

  const isCurrentUserNotGoing = useMemo(
    () =>
      Boolean(currentUserId && todayAttendanceRecordFor(currentUserId)?.type === 'notGoing'),
    [currentUserId, todayAttendanceRecordFor],
  )

  const isCurrentUserCheckedIn = useMemo(
    () => Boolean(currentUserId && openVisitFor(currentUserId)),
    [currentUserId, openVisitFor],
  )

  const todayStatus = useCallback(
    (memberId: string): TodayGymStatus | null => {
      if (openVisitFor(memberId)) return 'checkedIn'
      const hasVisitToday = gymVisits.some((v) => v.member_id === memberId && isDateInToday(new Date(v.check_in_at)))
      if (hasVisitToday) return 'checkedOut'
      const attendance = todayAttendanceRecordFor(memberId)
      if (attendance?.type === 'notGoing') return 'notGoing'
      const isGoingToday = attendance?.type === 'going'
      if (isGoingToday) return 'goingNotArrived'
      return null
    },
    [gymVisits, openVisitFor, todayAttendanceRecordFor],
  )

  const todayCheckedInMembers = useMemo(
    () => members.filter((m) => todayStatus(m.id) === 'checkedIn'),
    [members, todayStatus],
  )
  const todayCheckedOutMembers = useMemo(
    () => members.filter((m) => todayStatus(m.id) === 'checkedOut'),
    [members, todayStatus],
  )
  const todayGoingNotArrivedMembers = useMemo(
    () => members.filter((m) => todayStatus(m.id) === 'goingNotArrived'),
    [members, todayStatus],
  )
  const todayNotGoingMembers = useMemo(
    () => members.filter((m) => todayStatus(m.id) === 'notGoing'),
    [members, todayStatus],
  )

  const currentStreak = useMemo(() => {
    if (!currentUserId) return 0
    const days = Array.from(
      new Set(
        gymVisits
          .filter((v) => v.member_id === currentUserId)
          .map((v) => startOfDay(new Date(v.check_in_at)).getTime()),
      ),
    ).sort((a, b) => b - a)

    let streak = 0
    let cursor = startOfDay(new Date()).getTime()
    const dayMs = 24 * 60 * 60 * 1000
    for (const day of days) {
      if (day === cursor) {
        streak += 1
        cursor -= dayMs
      } else {
        break
      }
    }
    return streak
  }, [gymVisits, currentUserId])

  const currentUserMonthCount = useMemo(() => {
    if (!currentUserId) return 0
    const now = new Date()
    const days = new Set(
      gymVisits
        .filter((v) => v.member_id === currentUserId && isSameMonth(new Date(v.check_in_at), now))
        .map((v) => startOfDay(new Date(v.check_in_at)).getTime()),
    )
    return days.size
  }, [gymVisits, currentUserId])

  const currentUserMonthMinutes = useMemo(() => {
    if (!currentUserId) return 0
    const now = new Date()
    return gymVisits
      .filter((v) => v.member_id === currentUserId && isSameMonth(new Date(v.check_in_at), now))
      .reduce((sum, v) => sum + minutesBetween(new Date(v.check_in_at), v.check_out_at ? new Date(v.check_out_at) : now), 0)
  }, [gymVisits, currentUserId])

  const unreadNotificationCount = useMemo(
    () => notifications.filter((n) => n.read_at === null).length,
    [notifications],
  )

  const dailyStatsForWeek = useCallback(
    (date: Date = new Date(), memberId?: string): PeriodStat[] => {
      const targetId = memberId ?? currentUserId
      const monday = mondayOfWeek(date)
      return Array.from({ length: 7 }, (_, offset) => {
        const day = addDays(monday, offset)
        const visits = gymVisits.filter((v) => v.member_id === targetId && isSameDay(new Date(v.check_in_at), day))
        const minutes = visits.reduce(
          (sum, v) => sum + minutesBetween(new Date(v.check_in_at), v.check_out_at ? new Date(v.check_out_at) : new Date()),
          0,
        )
        return { label: weekdayLabel(day), start: day, count: visits.length > 0 ? 1 : 0, minutes }
      })
    },
    [gymVisits, currentUserId],
  )

  const monthlyStats = useCallback(
    (monthsBack = 6, memberId?: string): PeriodStat[] => {
      const targetId = memberId ?? currentUserId
      const results: PeriodStat[] = []
      for (let offset = monthsBack - 1; offset >= 0; offset--) {
        const monthDate = addMonths(new Date(), -offset)
        const monthStart = new Date(monthDate.getFullYear(), monthDate.getMonth(), 1)
        const visits = gymVisits.filter((v) => v.member_id === targetId && isSameMonth(new Date(v.check_in_at), monthDate))
        const days = new Set(visits.map((v) => startOfDay(new Date(v.check_in_at)).getTime())).size
        const minutes = visits.reduce(
          (sum, v) => sum + minutesBetween(new Date(v.check_in_at), v.check_out_at ? new Date(v.check_out_at) : new Date()),
          0,
        )
        results.push({ label: monthLabel(monthStart), start: monthStart, count: days, minutes })
      }
      return results
    },
    [gymVisits, currentUserId],
  )

  const memberComparisonForWeek = useCallback(
    (date: Date = new Date()): MemberComparisonEntry[] => {
      const monday = mondayOfWeek(date)
      const weekEnd = addDays(monday, 7)
      return members
        .map((member) => {
          const visits = gymVisits.filter(
            (v) => v.member_id === member.id && new Date(v.check_in_at) >= monday && new Date(v.check_in_at) < weekEnd,
          )
          const days = new Set(visits.map((v) => startOfDay(new Date(v.check_in_at)).getTime())).size
          const minutes = visits.reduce(
            (sum, v) => sum + minutesBetween(new Date(v.check_in_at), v.check_out_at ? new Date(v.check_out_at) : new Date()),
            0,
          )
          return { member, count: days, minutes }
        })
        .sort((a, b) => b.minutes - a.minutes)
    },
    [members, gymVisits],
  )

  const memberComparisonForMonth = useCallback(
    (date: Date = new Date()): MemberComparisonEntry[] => {
      return members
        .map((member) => {
          const visits = gymVisits.filter((v) => v.member_id === member.id && isSameMonth(new Date(v.check_in_at), date))
          const days = new Set(visits.map((v) => startOfDay(new Date(v.check_in_at)).getTime())).size
          const minutes = visits.reduce(
            (sum, v) => sum + minutesBetween(new Date(v.check_in_at), v.check_out_at ? new Date(v.check_out_at) : new Date()),
            0,
          )
          return { member, count: days, minutes }
        })
        .sort((a, b) => b.minutes - a.minutes)
    },
    [members, gymVisits],
  )

  const notificationRecipientIds = useCallback(
    () => members.map((m) => m.id).filter((id) => id !== currentUserId),
    [members, currentUserId],
  )

  const createNotifications = useCallback(
    async (type: AppNotificationType, title: string, message: string) => {
      if (isGymClosed(new Date())) return
      if (DEMO_MODE) return
      const recipients = notificationRecipientIds()
      if (recipients.length === 0 || !currentUserId) return
      const payload: AppNotification[] = recipients.map((recipientId) => ({
        id: crypto.randomUUID(),
        recipient_member_id: recipientId,
        actor_member_id: currentUserId,
        type,
        title,
        message,
        created_at: new Date().toISOString(),
        read_at: null,
      }))
      const { error } = await supabase.from('notifications').insert(payload)
      if (error) setLastErrorMessage(error.message)
    },
    [notificationRecipientIds, currentUserId],
  )

  const claimMember = useCallback(
    async (memberId: string) => {
      if (!session) return { error: 'セッションがありません。少し待ってからもう一度試してください。' }
      const { data, error } = await supabase
        .from('members')
        .update({ claimed_by: session.user.id })
        .eq('id', memberId)
        .is('claimed_by', null)
        .select()
        .maybeSingle()
      if (error) return { error: error.message }
      if (!data) return { error: 'その名前はすでに使われています。一覧を更新してみてください。' }
      reload()
      return { error: null }
    },
    [session, reload],
  )

  // Discards the current (anonymous) identity and starts a fresh one. This is
  // only useful as a recovery path from the failed screen -- it does not
  // "log out" of a claimed member, since claiming is meant to be permanent
  // per device.
  const resetIdentity = useCallback(async () => {
    await supabase.auth.signOut()
    setMembers([])
    setAttendanceRecords([])
    setGymVisits([])
    setNotifications([])
    setAppMode('loading')
    const { data, error } = await supabase.auth.signInAnonymously()
    if (error) {
      setLastErrorMessage(error.message)
      setAppMode('failed')
      return
    }
    setSession(data.session)
  }, [])

  // All write actions below update local state first so taps feel instant,
  // then sync to Supabase in the background and roll back on failure.
  const toggleGoing = useCallback(async () => {
    if (!currentUserId || isCurrentUserCheckedIn) return
    const existing = attendanceRecords.filter(
      (r) => r.member_id === currentUserId && isDateInToday(new Date(r.date)),
    )
    const removedIds = new Set(existing.map((r) => r.id))

    if (isCurrentUserGoing) {
      setAttendanceRecords((prev) => prev.filter((r) => !removedIds.has(r.id)))
      if (!DEMO_MODE && existing.length > 0) {
        const { error } = await supabase.from('attendance_records').delete().in('id', [...removedIds])
        if (error) {
          setAttendanceRecords((prev) => [...prev, ...existing])
          setLastErrorMessage(error.message)
        }
      }
      return
    }

    const record: AttendanceRecord = {
      id: crypto.randomUUID(),
      member_id: currentUserId,
      date: new Date().toISOString(),
      type: 'going',
    }
    setAttendanceRecords((prev) => [...prev.filter((r) => !removedIds.has(r.id)), record])
    if (DEMO_MODE) return
    if (existing.length > 0) {
      await supabase.from('attendance_records').delete().in('id', [...removedIds])
    }
    const { error } = await supabase.from('attendance_records').insert(record)
    if (error) {
      setAttendanceRecords((prev) => [...prev.filter((r) => r.id !== record.id), ...existing])
      setLastErrorMessage(error.message)
      return
    }
    const name = currentUser?.name ?? '誰か'
    await createNotifications('going', '参加予定が更新されました', `${name} さんが「参加」を選びました。`)
  }, [currentUserId, isCurrentUserCheckedIn, isCurrentUserGoing, attendanceRecords, currentUser, createNotifications])

  const toggleNotGoing = useCallback(async () => {
    if (!currentUserId) return
    if (isCurrentUserCheckedIn) {
      setLastErrorMessage('チェックインを取り消してから不参加に変更してください。')
      return
    }
    const existing = attendanceRecords.filter(
      (r) => r.member_id === currentUserId && isDateInToday(new Date(r.date)),
    )
    const removedIds = new Set(existing.map((r) => r.id))

    if (isCurrentUserNotGoing) {
      setAttendanceRecords((prev) => prev.filter((r) => !removedIds.has(r.id)))
      if (!DEMO_MODE && existing.length > 0) {
        const { error } = await supabase.from('attendance_records').delete().in('id', [...removedIds])
        if (error) {
          setAttendanceRecords((prev) => [...prev, ...existing])
          setLastErrorMessage(error.message)
        }
      }
      return
    }

    const record: AttendanceRecord = {
      id: crypto.randomUUID(),
      member_id: currentUserId,
      date: new Date().toISOString(),
      type: 'notGoing',
    }
    setAttendanceRecords((prev) => [...prev.filter((r) => !removedIds.has(r.id)), record])
    if (DEMO_MODE) return
    if (existing.length > 0) {
      await supabase.from('attendance_records').delete().in('id', [...removedIds])
    }
    const { error } = await supabase.from('attendance_records').insert(record)
    if (error) {
      setAttendanceRecords((prev) => [...prev.filter((r) => r.id !== record.id), ...existing])
      setLastErrorMessage(error.message)
      return
    }
    const name = currentUser?.name ?? '誰か'
    await createNotifications('notGoing', '参加予定が更新されました', `${name} さんが「不参加」を選びました。`)
  }, [currentUserId, isCurrentUserCheckedIn, isCurrentUserNotGoing, attendanceRecords, currentUser, createNotifications])

  const checkIn = useCallback(async () => {
    if (!currentUserId || isCurrentUserCheckedIn) return
    const visit: GymVisit = {
      id: crypto.randomUUID(),
      member_id: currentUserId,
      check_in_at: new Date().toISOString(),
      check_out_at: null,
    }
    setGymVisits((prev) => [...prev, visit])
    if (DEMO_MODE) return
    const { error } = await supabase.from('gym_visits').insert(visit)
    if (error) {
      setGymVisits((prev) => prev.filter((v) => v.id !== visit.id))
      setLastErrorMessage(error.message)
      return
    }
    const name = currentUser?.name ?? '誰か'
    await createNotifications('checkedIn', 'チェックインがありました', `${name} さんがジムに到着しました。`)
  }, [currentUserId, isCurrentUserCheckedIn, currentUser, createNotifications])

  const checkOut = useCallback(async () => {
    if (!currentUserId) return
    const visit = openVisitFor(currentUserId)
    if (!visit) return
    const checkOutAt = new Date().toISOString()
    setGymVisits((prev) => prev.map((v) => (v.id === visit.id ? { ...v, check_out_at: checkOutAt } : v)))
    if (DEMO_MODE) return
    const { error } = await supabase.from('gym_visits').update({ check_out_at: checkOutAt }).eq('id', visit.id)
    if (error) {
      setGymVisits((prev) => prev.map((v) => (v.id === visit.id ? { ...v, check_out_at: null } : v)))
      setLastErrorMessage(error.message)
      return
    }
    const name = currentUser?.name ?? '誰か'
    await createNotifications('checkedOut', 'チェックアウトがありました', `${name} さんがジムを退出しました。`)
  }, [currentUserId, openVisitFor, currentUser, createNotifications])

  const cancelCheckIn = useCallback(async () => {
    if (!currentUserId) return
    const visit = openVisitFor(currentUserId)
    if (!visit) return
    setGymVisits((prev) => prev.filter((v) => v.id !== visit.id))
    if (DEMO_MODE) return
    const { error } = await supabase.from('gym_visits').delete().eq('id', visit.id)
    if (error) {
      setGymVisits((prev) => [...prev, visit])
      setLastErrorMessage(error.message)
      return
    }
    const name = currentUser?.name ?? '誰か'
    await createNotifications('checkInCancelled', 'チェックインが取り消されました', `${name} さんがチェックインを取り消しました。`)
  }, [currentUserId, openVisitFor, currentUser, createNotifications])

  const cancelCheckOut = useCallback(async () => {
    if (!currentUserId) return
    const visit = todayClosedVisitFor(currentUserId)
    if (!visit) return
    setGymVisits((prev) => prev.map((v) => (v.id === visit.id ? { ...v, check_out_at: null } : v)))
    if (DEMO_MODE) return
    const { error } = await supabase.from('gym_visits').update({ check_out_at: null }).eq('id', visit.id)
    if (error) {
      setGymVisits((prev) => prev.map((v) => (v.id === visit.id ? { ...v, check_out_at: visit.check_out_at } : v)))
      setLastErrorMessage(error.message)
    }
  }, [currentUserId, todayClosedVisitFor])

  const markNotificationsRead = useCallback(async () => {
    const unread = notifications.filter((n) => n.read_at === null)
    if (unread.length === 0) return
    const unreadIds = new Set(unread.map((n) => n.id))
    const readAt = new Date().toISOString()
    setNotifications((prev) => prev.map((n) => (unreadIds.has(n.id) ? { ...n, read_at: readAt } : n)))
    if (DEMO_MODE) return
    const { error } = await supabase.from('notifications').update({ read_at: readAt }).in('id', [...unreadIds])
    if (error) {
      setNotifications((prev) => prev.map((n) => (unreadIds.has(n.id) ? { ...n, read_at: null } : n)))
      setLastErrorMessage(error.message)
    }
  }, [notifications])

  const updateProfile = useCallback(
    async (name: string) => {
      if (!currentUserId) return
      const trimmed = name.trim()
      if (!trimmed) return
      if (!DEMO_MODE) {
        const { error } = await supabase
          .from('members')
          .update({ name: trimmed, initials: defaultInitials(trimmed) })
          .eq('id', currentUserId)
        if (error) {
          setLastErrorMessage(error.message)
          return
        }
      }
      setMembers((prev) =>
        prev.map((m) => (m.id === currentUserId ? { ...m, name: trimmed, initials: defaultInitials(trimmed) } : m)),
      )
    },
    [currentUserId],
  )

  const updateAvatar = useCallback(
    async (image: Blob): Promise<{ error: string | null }> => {
      if (!currentUserId) return { error: 'メンバー情報が見つかりません。' }

      if (DEMO_MODE) {
        const url = URL.createObjectURL(image)
        setMembers((prev) => prev.map((m) => (m.id === currentUserId ? { ...m, avatar_url: url } : m)))
        return { error: null }
      }

      const path = `${currentUserId}.jpg`
      const { error: uploadError } = await supabase.storage.from('avatars').upload(path, image, {
        upsert: true,
        contentType: 'image/jpeg',
        cacheControl: '3600',
      })
      if (uploadError) return { error: uploadError.message }

      const { data } = supabase.storage.from('avatars').getPublicUrl(path)
      // cache-busting query so everyone's browser picks up the new image
      const url = `${data.publicUrl}?v=${Date.now()}`
      const { error } = await supabase.from('members').update({ avatar_url: url }).eq('id', currentUserId)
      if (error) return { error: error.message }

      setMembers((prev) => prev.map((m) => (m.id === currentUserId ? { ...m, avatar_url: url } : m)))
      return { error: null }
    },
    [currentUserId],
  )

  const value: GymStoreValue = {
    appMode,
    session,
    members,
    unclaimedMembers,
    attendanceRecords,
    gymVisits,
    notifications,
    lastErrorMessage,
    currentUser,
    isCurrentUserGoing,
    isCurrentUserNotGoing,
    isCurrentUserCheckedIn,
    unreadNotificationCount,
    todayStatus,
    todayCheckedInMembers,
    todayCheckedOutMembers,
    todayGoingNotArrivedMembers,
    todayNotGoingMembers,
    currentStreak,
    currentUserMonthCount,
    currentUserMonthMinutes,
    dailyStatsForWeek,
    monthlyStats,
    memberComparisonForWeek,
    memberComparisonForMonth,
    claimMember,
    resetIdentity,
    toggleGoing,
    toggleNotGoing,
    checkIn,
    checkOut,
    cancelCheckIn,
    cancelCheckOut,
    markNotificationsRead,
    updateProfile,
    updateAvatar,
    reload,
  }

  return <GymStoreContext.Provider value={value}>{children}</GymStoreContext.Provider>
}

export function useGymStore(): GymStoreValue {
  const ctx = useContext(GymStoreContext)
  if (!ctx) throw new Error('useGymStore must be used within GymStoreProvider')
  return ctx
}
