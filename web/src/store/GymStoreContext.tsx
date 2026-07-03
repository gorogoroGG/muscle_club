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
  markNotificationsRead: () => Promise<void>
  updateProfile: (name: string) => Promise<void>
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

  const authUserId = session?.user.id ?? null

  const currentUser = useMemo<Member | null>(() => {
    if (!authUserId) return null
    return members.find((m) => m.claimed_by === authUserId) ?? null
  }, [members, authUserId])

  const currentUserId = currentUser?.id ?? null

  const unclaimedMembers = useMemo(() => members.filter((m) => m.claimed_by === null), [members])

  // Bootstrap: reuse an existing session, or silently create an anonymous one.
  // No email is ever sent for this, so there's no OTP rate limit to hit.
  useEffect(() => {
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

  const isCurrentUserGoing = useMemo(
    () =>
      Boolean(
        currentUserId &&
          attendanceRecords.some(
            (r) => r.member_id === currentUserId && r.type === 'going' && isDateInToday(new Date(r.date)),
          ),
      ),
    [attendanceRecords, currentUserId],
  )

  const isCurrentUserNotGoing = useMemo(
    () =>
      Boolean(
        currentUserId &&
          attendanceRecords.some(
            (r) => r.member_id === currentUserId && r.type === 'notGoing' && isDateInToday(new Date(r.date)),
          ),
      ),
    [attendanceRecords, currentUserId],
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
      const isGoingToday = attendanceRecords.some(
        (r) => r.member_id === memberId && r.type === 'going' && isDateInToday(new Date(r.date)),
      )
      if (isGoingToday) return 'goingNotArrived'
      return null
    },
    [attendanceRecords, gymVisits, openVisitFor],
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

  const toggleGoing = useCallback(async () => {
    if (!currentUserId || isCurrentUserCheckedIn) return
    const existing = attendanceRecords.filter(
      (r) => r.member_id === currentUserId && isDateInToday(new Date(r.date)),
    )
    if (existing.length > 0) {
      await supabase.from('attendance_records').delete().in('id', existing.map((r) => r.id))
    }
    if (isCurrentUserGoing) {
      setAttendanceRecords((prev) => prev.filter((r) => !existing.some((e) => e.id === r.id)))
      return
    }
    const record: AttendanceRecord = {
      id: crypto.randomUUID(),
      member_id: currentUserId,
      date: new Date().toISOString(),
      type: 'going',
    }
    const { error } = await supabase.from('attendance_records').insert(record)
    if (error) {
      setLastErrorMessage(error.message)
      return
    }
    setAttendanceRecords((prev) => [...prev.filter((r) => !existing.some((e) => e.id === r.id)), record])
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
    if (existing.length > 0) {
      await supabase.from('attendance_records').delete().in('id', existing.map((r) => r.id))
    }
    if (isCurrentUserNotGoing) {
      setAttendanceRecords((prev) => prev.filter((r) => !existing.some((e) => e.id === r.id)))
      return
    }
    const record: AttendanceRecord = {
      id: crypto.randomUUID(),
      member_id: currentUserId,
      date: new Date().toISOString(),
      type: 'notGoing',
    }
    const { error } = await supabase.from('attendance_records').insert(record)
    if (error) {
      setLastErrorMessage(error.message)
      return
    }
    setAttendanceRecords((prev) => [...prev.filter((r) => !existing.some((e) => e.id === r.id)), record])
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
    const { error } = await supabase.from('gym_visits').insert(visit)
    if (error) {
      setLastErrorMessage(error.message)
      return
    }
    setGymVisits((prev) => [...prev, visit])
    const name = currentUser?.name ?? '誰か'
    await createNotifications('checkedIn', 'チェックインがありました', `${name} さんがジムに到着しました。`)
  }, [currentUserId, isCurrentUserCheckedIn, currentUser, createNotifications])

  const checkOut = useCallback(async () => {
    if (!currentUserId) return
    const visit = openVisitFor(currentUserId)
    if (!visit) return
    const checkOutAt = new Date().toISOString()
    const { error } = await supabase.from('gym_visits').update({ check_out_at: checkOutAt }).eq('id', visit.id)
    if (error) {
      setLastErrorMessage(error.message)
      return
    }
    setGymVisits((prev) => prev.map((v) => (v.id === visit.id ? { ...v, check_out_at: checkOutAt } : v)))
    const name = currentUser?.name ?? '誰か'
    await createNotifications('checkedOut', 'チェックアウトがありました', `${name} さんがジムを退出しました。`)
  }, [currentUserId, openVisitFor, currentUser, createNotifications])

  const cancelCheckIn = useCallback(async () => {
    if (!currentUserId) return
    const visit = openVisitFor(currentUserId)
    if (!visit) return
    const { error } = await supabase.from('gym_visits').delete().eq('id', visit.id)
    if (error) {
      setLastErrorMessage(error.message)
      return
    }
    setGymVisits((prev) => prev.filter((v) => v.id !== visit.id))
    const name = currentUser?.name ?? '誰か'
    await createNotifications('checkInCancelled', 'チェックインが取り消されました', `${name} さんがチェックインを取り消しました。`)
  }, [currentUserId, openVisitFor, currentUser, createNotifications])

  const markNotificationsRead = useCallback(async () => {
    const unreadIds = notifications.filter((n) => n.read_at === null).map((n) => n.id)
    if (unreadIds.length === 0) return
    const readAt = new Date().toISOString()
    const { error } = await supabase.from('notifications').update({ read_at: readAt }).in('id', unreadIds)
    if (error) {
      setLastErrorMessage(error.message)
      return
    }
    setNotifications((prev) => prev.map((n) => (unreadIds.includes(n.id) ? { ...n, read_at: readAt } : n)))
  }, [notifications])

  const updateProfile = useCallback(
    async (name: string) => {
      if (!currentUserId) return
      const trimmed = name.trim()
      if (!trimmed) return
      const { error } = await supabase
        .from('members')
        .update({ name: trimmed, initials: defaultInitials(trimmed) })
        .eq('id', currentUserId)
      if (error) {
        setLastErrorMessage(error.message)
        return
      }
      setMembers((prev) =>
        prev.map((m) => (m.id === currentUserId ? { ...m, name: trimmed, initials: defaultInitials(trimmed) } : m)),
      )
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
    markNotificationsRead,
    updateProfile,
    reload,
  }

  return <GymStoreContext.Provider value={value}>{children}</GymStoreContext.Provider>
}

export function useGymStore(): GymStoreValue {
  const ctx = useContext(GymStoreContext)
  if (!ctx) throw new Error('useGymStore must be used within GymStoreProvider')
  return ctx
}
