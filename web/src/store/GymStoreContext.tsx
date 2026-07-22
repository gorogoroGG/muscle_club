import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { isSupabaseConfigured, supabase } from '../lib/supabaseClient'
import {
  addDays,
  isDateInToday,
  isSameDay,
  isSameMonth,
  mondayOfWeek,
  startOfDay,
  weekdayLabel,
} from '../lib/date'
import type {
  AppMode,
  AvatarColor,
  DailyIntent,
  DailyIntentStatus,
  GymVisit,
  Member,
  PeriodStat,
  RankingEntry,
  RankingPeriod,
  TodayGymStatus,
} from '../types'

const AUTH_BOOTSTRAP_TIMEOUT_MS = 12_000
const INITIAL_LOAD_TIMEOUT_MS = 15_000
const DEMO_MODE = import.meta.env.DEV && new URLSearchParams(window.location.search).has('demo')
const DEMO_AUTH_ID = '00000000-0000-4000-8000-000000000001'

function formatErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}

function defaultInitials(name: string, email?: string | null): string {
  const source = name.trim() || email?.split('@')[0] || 'member'
  const normalized = source.toUpperCase().replace(/[^A-Z0-9]/g, '')
  return (normalized || 'ME').slice(0, 2).padEnd(2, 'M')
}

function todayDateKey(date = new Date()): string {
  const year = date.getFullYear()
  const month = `${date.getMonth() + 1}`.padStart(2, '0')
  const day = `${date.getDate()}`.padStart(2, '0')
  return `${year}-${month}-${day}`
}

function authRedirectUrl(): string {
  return new URL(import.meta.env.BASE_URL, window.location.origin).toString()
}

function randomAvatarColor(seed: string): AvatarColor {
  const colors: AvatarColor[] = ['blue', 'teal', 'green', 'orange', 'pink', 'indigo', 'purple', 'red', 'yellow']
  const total = Array.from(seed).reduce((sum, char) => sum + char.charCodeAt(0), 0)
  return colors[total % colors.length]
}

async function withTimeout<T>(promise: PromiseLike<T>, ms: number, label: string): Promise<T> {
  let timeoutId: number | undefined
  const timeout = new Promise<never>((_, reject) => {
    timeoutId = window.setTimeout(() => {
      reject(new Error(`${label}がタイムアウトしました。通信状況を確認して、もう一度お試しください。`))
    }, ms)
  })

  try {
    return await Promise.race([promise, timeout])
  } finally {
    if (timeoutId !== undefined) window.clearTimeout(timeoutId)
  }
}

function periodContains(date: Date, period: RankingPeriod, now = new Date()): boolean {
  if (period === 'all') return true
  if (period === 'month') return isSameMonth(date, now)
  const weekStart = mondayOfWeek(now)
  const weekEnd = addDays(weekStart, 7)
  return date >= weekStart && date < weekEnd
}

function countVisitDays(visits: GymVisit[], memberId: string, period: RankingPeriod): number {
  return new Set(
    visits
      .filter((visit) => visit.member_id === memberId && periodContains(new Date(visit.check_in_at), period))
      .map((visit) => startOfDay(new Date(visit.check_in_at)).getTime()),
  ).size
}

function demoData() {
  const now = new Date()
  const at = (daysAgo: number, hour: number, minute = 0) => {
    const d = new Date(now)
    d.setDate(d.getDate() - daysAgo)
    d.setHours(hour, minute, 0, 0)
    return d.toISOString()
  }
  const dateAt = (daysAgo: number) => {
    const d = new Date(now)
    d.setDate(d.getDate() - daysAgo)
    return todayDateKey(d)
  }
  const members: Member[] = [
    {
      id: DEMO_AUTH_ID,
      user_id: DEMO_AUTH_ID,
      email: 'demo@example.com',
      name: 'ゆーご',
      initials: 'YG',
      avatar_color: 'teal',
      avatar_url: null,
    },
    { id: 'demo-2', user_id: 'other-2', email: null, name: 'まなせ', initials: 'MN', avatar_color: 'pink', avatar_url: null },
    { id: 'demo-3', user_id: 'other-3', email: null, name: 'いっちー', initials: 'IC', avatar_color: 'green', avatar_url: null },
    { id: 'demo-4', user_id: 'other-4', email: null, name: 'うーかす', initials: 'UK', avatar_color: 'orange', avatar_url: null },
  ]
  const dailyIntents: DailyIntent[] = [
    { id: 'di-1', member_id: DEMO_AUTH_ID, date: dateAt(0), status: 'going' },
    { id: 'di-2', member_id: 'demo-3', date: dateAt(0), status: 'going' },
    { id: 'di-3', member_id: 'demo-4', date: dateAt(0), status: 'not_going' },
  ]
  const gymVisits: GymVisit[] = [
    { id: 'v-open', member_id: 'demo-2', check_in_at: at(0, Math.max(0, now.getHours() - 1)), check_out_at: null },
    { id: 'v-done', member_id: 'demo-4', check_in_at: at(0, 7), check_out_at: at(0, 8, 30) },
    ...[1, 2, 4, 6, 9, 12, 16, 20].map((day, index) => ({
      id: `v-me-${index}`,
      member_id: DEMO_AUTH_ID,
      check_in_at: at(day, 19),
      check_out_at: at(day, 20),
    })),
    ...[1, 3, 5, 8].map((day, index) => ({
      id: `v-mn-${index}`,
      member_id: 'demo-2',
      check_in_at: at(day, 18),
      check_out_at: at(day, 19),
    })),
  ]
  return { members, dailyIntents, gymVisits }
}

interface GymStoreValue {
  appMode: AppMode
  session: Session | null
  members: Member[]
  dailyIntents: DailyIntent[]
  gymVisits: GymVisit[]
  lastErrorMessage: string | null
  currentUser: Member | null
  isCurrentUserGoing: boolean
  isCurrentUserNotGoing: boolean
  isCurrentUserCheckedIn: boolean
  todayStatus: (memberId: string) => TodayGymStatus | null
  todayCheckedInMembers: Member[]
  todayCheckedOutMembers: Member[]
  todayGoingNotArrivedMembers: Member[]
  todayNotGoingMembers: Member[]
  todayUnknownMembers: Member[]
  currentUserMonthCount: number
  currentUserTotalCount: number
  currentUserMonthRank: number | null
  visitStatsForWeek: (date?: Date, memberId?: string) => PeriodStat[]
  rankingForPeriod: (period: RankingPeriod) => RankingEntry[]
  signUpWithEmail: (params: { email: string; password: string; name: string }) => Promise<{ error: string | null; needsEmailConfirmation: boolean }>
  signInWithEmail: (email: string, password: string) => Promise<{ error: string | null }>
  resendSignupEmail: (email: string) => Promise<{ error: string | null }>
  resetPassword: (email: string) => Promise<{ error: string | null }>
  signOut: () => Promise<void>
  setTodayIntent: (status: DailyIntentStatus | null) => Promise<void>
  checkIn: () => Promise<void>
  checkOut: () => Promise<void>
  cancelCheckIn: () => Promise<void>
  cancelCheckOut: () => Promise<void>
  updateProfile: (name: string) => Promise<{ error: string | null }>
  updateAvatar: (image: Blob) => Promise<{ error: string | null }>
  reload: () => void
}

const GymStoreContext = createContext<GymStoreValue | null>(null)

export function GymStoreProvider({ children }: { children: ReactNode }) {
  const [appMode, setAppMode] = useState<AppMode>('loading')
  const [session, setSession] = useState<Session | null>(null)
  const [members, setMembers] = useState<Member[]>([])
  const [dailyIntents, setDailyIntents] = useState<DailyIntent[]>([])
  const [gymVisits, setGymVisits] = useState<GymVisit[]>([])
  const [lastErrorMessage, setLastErrorMessage] = useState<string | null>(null)
  const [reloadToken, setReloadToken] = useState(0)

  const authUserId = DEMO_MODE ? DEMO_AUTH_ID : (session?.user.id ?? null)

  const currentUser = useMemo<Member | null>(() => {
    if (!authUserId) return null
    return members.find((member) => member.user_id === authUserId || member.id === authUserId) ?? null
  }, [members, authUserId])

  const currentUserId = currentUser?.id ?? null

  const ensureCurrentMember = useCallback(async (user: User): Promise<Member> => {
    const displayName = String(user.user_metadata.name ?? user.user_metadata.display_name ?? user.email?.split('@')[0] ?? 'member')
    const fallback: Member = {
      id: user.id,
      user_id: user.id,
      email: user.email ?? null,
      name: displayName,
      initials: defaultInitials(displayName, user.email),
      avatar_color: randomAvatarColor(user.email ?? user.id),
      avatar_url: null,
    }

    const { data: existing, error: existingError } = await supabase
      .from('members')
      .select('*')
      .eq('user_id', user.id)
      .maybeSingle()
    if (existingError) throw existingError
    if (existing) return existing as Member

    const { data, error } = await supabase
      .from('members')
      .insert(fallback)
      .select()
      .single()
    if (error) throw error
    return data as Member
  }, [])

  useEffect(() => {
    if (DEMO_MODE) {
      const seed = demoData()
      setSession(null)
      setMembers(seed.members)
      setDailyIntents(seed.dailyIntents)
      setGymVisits(seed.gymVisits)
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
      try {
        const { data, error } = await withTimeout(
          supabase.auth.getSession(),
          AUTH_BOOTSTRAP_TIMEOUT_MS,
          'セッション確認',
        )
        if (cancelled) return
        if (error) throw error
        setSession(data.session)
        setAppMode(data.session ? 'loading' : 'auth')
      } catch (error) {
        if (cancelled) return
        setLastErrorMessage(`保存済みセッションの復元に失敗しました。(${formatErrorMessage(error)})`)
        setAppMode('failed')
      }
    }

    bootstrap()

    const { data: subscription } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      if (cancelled) return
      setSession(nextSession)
      if (!nextSession) {
        setMembers([])
        setDailyIntents([])
        setGymVisits([])
        setLastErrorMessage(null)
        setAppMode('auth')
      }
    })

    return () => {
      cancelled = true
      subscription.subscription.unsubscribe()
    }
  }, [])

  useEffect(() => {
    if (DEMO_MODE || !session) return
    const activeSession = session
    let cancelled = false

    async function loadData() {
      setAppMode('loading')
      try {
        await ensureCurrentMember(activeSession.user)
        const [membersRes, intentsRes, visitsRes] = await withTimeout(
          Promise.all([
            supabase.from('members').select('*').order('name', { ascending: true }),
            supabase.from('daily_intents').select('*').order('date', { ascending: false }),
            supabase.from('gym_visits').select('*').order('check_in_at', { ascending: false }),
          ]),
          INITIAL_LOAD_TIMEOUT_MS,
          '初期データの読み込み',
        )
        if (membersRes.error) throw membersRes.error
        if (intentsRes.error) throw intentsRes.error
        if (visitsRes.error) throw visitsRes.error
        if (cancelled) return
        setMembers(membersRes.data as Member[])
        setDailyIntents(intentsRes.data as DailyIntent[])
        setGymVisits(visitsRes.data as GymVisit[])
        setLastErrorMessage(null)
        setAppMode('signedIn')
      } catch (error) {
        if (cancelled) return
        setLastErrorMessage(formatErrorMessage(error))
        setAppMode('failed')
      }
    }

    loadData()
    return () => {
      cancelled = true
    }
  }, [ensureCurrentMember, reloadToken, session])

  const reload = useCallback(() => setReloadToken((token) => token + 1), [])

  useEffect(() => {
    function handleVisibility() {
      if (document.visibilityState === 'visible' && session) reload()
    }
    document.addEventListener('visibilitychange', handleVisibility)
    return () => document.removeEventListener('visibilitychange', handleVisibility)
  }, [reload, session])

  const openVisitFor = useCallback(
    (memberId: string) => gymVisits.find((visit) => visit.member_id === memberId && visit.check_out_at === null) ?? null,
    [gymVisits],
  )

  const todayIntentFor = useCallback(
    (memberId: string) =>
      dailyIntents
        .filter((intent) => intent.member_id === memberId && intent.date === todayDateKey())
        .sort((a, b) => (b.updated_at ?? '').localeCompare(a.updated_at ?? ''))[0] ?? null,
    [dailyIntents],
  )

  const todayClosedVisitFor = useCallback(
    (memberId: string) =>
      gymVisits
        .filter((visit) => visit.member_id === memberId && visit.check_out_at !== null && isDateInToday(new Date(visit.check_in_at)))
        .sort((a, b) => new Date(b.check_in_at).getTime() - new Date(a.check_in_at).getTime())[0] ?? null,
    [gymVisits],
  )

  const isCurrentUserGoing = Boolean(currentUserId && todayIntentFor(currentUserId)?.status === 'going')
  const isCurrentUserNotGoing = Boolean(currentUserId && todayIntentFor(currentUserId)?.status === 'not_going')
  const isCurrentUserCheckedIn = Boolean(currentUserId && openVisitFor(currentUserId))

  const todayStatus = useCallback(
    (memberId: string): TodayGymStatus | null => {
      if (openVisitFor(memberId)) return 'checkedIn'
      if (todayClosedVisitFor(memberId)) return 'checkedOut'
      const intent = todayIntentFor(memberId)
      if (intent?.status === 'not_going') return 'notGoing'
      if (intent?.status === 'going') return 'goingNotArrived'
      return null
    },
    [openVisitFor, todayClosedVisitFor, todayIntentFor],
  )

  const todayCheckedInMembers = useMemo(
    () => members.filter((member) => todayStatus(member.id) === 'checkedIn'),
    [members, todayStatus],
  )
  const todayCheckedOutMembers = useMemo(
    () => members.filter((member) => todayStatus(member.id) === 'checkedOut'),
    [members, todayStatus],
  )
  const todayGoingNotArrivedMembers = useMemo(
    () => members.filter((member) => todayStatus(member.id) === 'goingNotArrived'),
    [members, todayStatus],
  )
  const todayNotGoingMembers = useMemo(
    () => members.filter((member) => todayStatus(member.id) === 'notGoing'),
    [members, todayStatus],
  )
  const todayUnknownMembers = useMemo(
    () => members.filter((member) => todayStatus(member.id) === null),
    [members, todayStatus],
  )

  const rankingForPeriod = useCallback(
    (period: RankingPeriod): RankingEntry[] => {
      const ranked = members
        .map((member) => ({
          member,
          count: countVisitDays(gymVisits, member.id, period),
          rank: 0,
          isCurrentUser: member.id === currentUserId,
        }))
        .sort((a, b) => b.count - a.count || a.member.name.localeCompare(b.member.name, 'ja'))

      let lastCount: number | null = null
      let lastRank = 0
      return ranked.map((entry, index) => {
        if (entry.count !== lastCount) {
          lastRank = index + 1
          lastCount = entry.count
        }
        return { ...entry, rank: lastRank }
      })
    },
    [currentUserId, gymVisits, members],
  )

  const currentUserMonthCount = currentUserId ? countVisitDays(gymVisits, currentUserId, 'month') : 0
  const currentUserTotalCount = currentUserId ? countVisitDays(gymVisits, currentUserId, 'all') : 0
  const currentUserMonthRank = rankingForPeriod('month').find((entry) => entry.isCurrentUser)?.rank ?? null

  const visitStatsForWeek = useCallback(
    (date: Date = new Date(), memberId?: string): PeriodStat[] => {
      const targetId = memberId ?? currentUserId
      const monday = mondayOfWeek(date)
      return Array.from({ length: 7 }, (_unused, offset) => {
        const day = addDays(monday, offset)
        const count = targetId
          ? Number(gymVisits.some((visit) => visit.member_id === targetId && isSameDay(new Date(visit.check_in_at), day)))
          : 0
        return { label: weekdayLabel(day), start: day, count }
      })
    },
    [currentUserId, gymVisits],
  )

  const signUpWithEmail = useCallback(async ({ email, password, name }: { email: string; password: string; name: string }) => {
    const normalizedEmail = email.trim()
    const normalizedName = name.trim()
    if (!normalizedName) return { error: '表示名を入力してください。', needsEmailConfirmation: false }
    if (!normalizedEmail) return { error: 'メールアドレスを入力してください。', needsEmailConfirmation: false }
    if (password.length < 6) return { error: 'パスワードは6文字以上で入力してください。', needsEmailConfirmation: false }

    const { data, error } = await supabase.auth.signUp({
      email: normalizedEmail,
      password,
      options: {
        emailRedirectTo: authRedirectUrl(),
        data: {
          name: normalizedName,
          avatar_color: randomAvatarColor(normalizedEmail),
        },
      },
    })
    if (error) return { error: error.message, needsEmailConfirmation: false }
    if (data.session) {
      setSession(data.session)
      reload()
    }
    return { error: null, needsEmailConfirmation: !data.session }
  }, [reload])

  const resendSignupEmail = useCallback(async (email: string) => {
    const normalizedEmail = email.trim()
    if (!normalizedEmail) return { error: 'メールアドレスを入力してください。' }
    const { error } = await supabase.auth.resend({
      type: 'signup',
      email: normalizedEmail,
      options: {
        emailRedirectTo: authRedirectUrl(),
      },
    })
    if (error) return { error: error.message }
    return { error: null }
  }, [])

  const signInWithEmail = useCallback(async (email: string, password: string) => {
    const normalizedEmail = email.trim()
    if (!normalizedEmail || !password) return { error: 'メールアドレスとパスワードを入力してください。' }
    const { data, error } = await supabase.auth.signInWithPassword({
      email: normalizedEmail,
      password,
    })
    if (error) return { error: error.message }
    setSession(data.session)
    reload()
    return { error: null }
  }, [reload])

  const resetPassword = useCallback(async (email: string) => {
    const normalizedEmail = email.trim()
    if (!normalizedEmail) return { error: 'メールアドレスを入力してください。' }
    const { error } = await supabase.auth.resetPasswordForEmail(normalizedEmail, {
      redirectTo: authRedirectUrl(),
    })
    if (error) return { error: error.message }
    return { error: null }
  }, [])

  const signOut = useCallback(async () => {
    if (!DEMO_MODE) await supabase.auth.signOut({ scope: 'local' })
    setSession(null)
    setMembers([])
    setDailyIntents([])
    setGymVisits([])
    setLastErrorMessage(null)
    setAppMode('auth')
  }, [])

  const setTodayIntent = useCallback(
    async (status: DailyIntentStatus | null) => {
      if (!currentUserId) return
      const existing = todayIntentFor(currentUserId)
      const date = todayDateKey()

      if (status === null) {
        if (!existing) return
        setDailyIntents((prev) => prev.filter((intent) => intent.id !== existing.id))
        if (DEMO_MODE) return
        const { error } = await supabase.from('daily_intents').delete().eq('id', existing.id)
        if (error) {
          setDailyIntents((prev) => [...prev, existing])
          setLastErrorMessage(error.message)
        }
        return
      }

      const intent: DailyIntent = {
        id: existing?.id ?? crypto.randomUUID(),
        member_id: currentUserId,
        date,
        status,
        updated_at: new Date().toISOString(),
      }
      setDailyIntents((prev) => [...prev.filter((item) => !(item.member_id === currentUserId && item.date === date)), intent])
      if (DEMO_MODE) return
      const { error } = await supabase
        .from('daily_intents')
        .upsert(intent, { onConflict: 'member_id,date' })
      if (error) {
        setDailyIntents((prev) => {
          const withoutNew = prev.filter((item) => item.id !== intent.id)
          return existing ? [...withoutNew, existing] : withoutNew
        })
        setLastErrorMessage(error.message)
      }
    },
    [currentUserId, todayIntentFor],
  )

  const checkIn = useCallback(async () => {
    if (!currentUserId || openVisitFor(currentUserId)) return
    const visit: GymVisit = {
      id: crypto.randomUUID(),
      member_id: currentUserId,
      check_in_at: new Date().toISOString(),
      check_out_at: null,
    }
    setGymVisits((prev) => [visit, ...prev])
    if (DEMO_MODE) return
    const { error } = await supabase.from('gym_visits').insert(visit)
    if (error) {
      setGymVisits((prev) => prev.filter((item) => item.id !== visit.id))
      setLastErrorMessage(error.message)
    }
  }, [currentUserId, openVisitFor])

  const checkOut = useCallback(async () => {
    if (!currentUserId) return
    const visit = openVisitFor(currentUserId)
    if (!visit) return
    const checkOutAt = new Date().toISOString()
    setGymVisits((prev) => prev.map((item) => (item.id === visit.id ? { ...item, check_out_at: checkOutAt } : item)))
    if (DEMO_MODE) return
    const { error } = await supabase.from('gym_visits').update({ check_out_at: checkOutAt }).eq('id', visit.id)
    if (error) {
      setGymVisits((prev) => prev.map((item) => (item.id === visit.id ? { ...item, check_out_at: null } : item)))
      setLastErrorMessage(error.message)
    }
  }, [currentUserId, openVisitFor])

  const cancelCheckIn = useCallback(async () => {
    if (!currentUserId) return
    const visit = openVisitFor(currentUserId)
    if (!visit) return
    setGymVisits((prev) => prev.filter((item) => item.id !== visit.id))
    if (DEMO_MODE) return
    const { error } = await supabase.from('gym_visits').delete().eq('id', visit.id)
    if (error) {
      setGymVisits((prev) => [visit, ...prev])
      setLastErrorMessage(error.message)
    }
  }, [currentUserId, openVisitFor])

  const cancelCheckOut = useCallback(async () => {
    if (!currentUserId) return
    const visit = todayClosedVisitFor(currentUserId)
    if (!visit) return
    setGymVisits((prev) => prev.map((item) => (item.id === visit.id ? { ...item, check_out_at: null } : item)))
    if (DEMO_MODE) return
    const { error } = await supabase.from('gym_visits').update({ check_out_at: null }).eq('id', visit.id)
    if (error) {
      setGymVisits((prev) => prev.map((item) => (item.id === visit.id ? { ...item, check_out_at: visit.check_out_at } : item)))
      setLastErrorMessage(error.message)
    }
  }, [currentUserId, todayClosedVisitFor])

  const updateProfile = useCallback(
    async (name: string) => {
      if (!currentUser) return { error: 'プロフィールを確認できません。' }
      const normalizedName = name.trim()
      if (!normalizedName) return { error: '表示名を入力してください。' }
      const nextMember = {
        ...currentUser,
        name: normalizedName,
        initials: defaultInitials(normalizedName, currentUser.email),
      }
      setMembers((prev) => prev.map((member) => (member.id === currentUser.id ? nextMember : member)))
      if (DEMO_MODE) return { error: null }
      const { error } = await supabase
        .from('members')
        .update({ name: nextMember.name, initials: nextMember.initials })
        .eq('id', currentUser.id)
      if (error) {
        setMembers((prev) => prev.map((member) => (member.id === currentUser.id ? currentUser : member)))
        setLastErrorMessage(error.message)
        return { error: error.message }
      }
      return { error: null }
    },
    [currentUser],
  )

  const updateAvatar = useCallback(
    async (image: Blob) => {
      if (!currentUser) return { error: 'プロフィールを確認できません。' }
      if (DEMO_MODE) return { error: null }
      const path = `${currentUser.id}.jpg`
      const { error: uploadError } = await supabase.storage
        .from('avatars')
        .upload(path, image, { cacheControl: '3600', contentType: 'image/jpeg', upsert: true })
      if (uploadError) return { error: uploadError.message }
      const publicUrl = supabase.storage.from('avatars').getPublicUrl(path).data.publicUrl
      const avatarUrl = `${publicUrl}?v=${Date.now()}`
      const { error } = await supabase.from('members').update({ avatar_url: avatarUrl }).eq('id', currentUser.id)
      if (error) return { error: error.message }
      setMembers((prev) => prev.map((member) => (member.id === currentUser.id ? { ...member, avatar_url: avatarUrl } : member)))
      return { error: null }
    },
    [currentUser],
  )

  const value = useMemo<GymStoreValue>(
    () => ({
      appMode,
      session,
      members,
      dailyIntents,
      gymVisits,
      lastErrorMessage,
      currentUser,
      isCurrentUserGoing,
      isCurrentUserNotGoing,
      isCurrentUserCheckedIn,
      todayStatus,
      todayCheckedInMembers,
      todayCheckedOutMembers,
      todayGoingNotArrivedMembers,
      todayNotGoingMembers,
      todayUnknownMembers,
      currentUserMonthCount,
      currentUserTotalCount,
      currentUserMonthRank,
      visitStatsForWeek,
      rankingForPeriod,
      signUpWithEmail,
      signInWithEmail,
      resendSignupEmail,
      resetPassword,
      signOut,
      setTodayIntent,
      checkIn,
      checkOut,
      cancelCheckIn,
      cancelCheckOut,
      updateProfile,
      updateAvatar,
      reload,
    }),
    [
      appMode,
      session,
      members,
      dailyIntents,
      gymVisits,
      lastErrorMessage,
      currentUser,
      isCurrentUserGoing,
      isCurrentUserNotGoing,
      isCurrentUserCheckedIn,
      todayStatus,
      todayCheckedInMembers,
      todayCheckedOutMembers,
      todayGoingNotArrivedMembers,
      todayNotGoingMembers,
      todayUnknownMembers,
      currentUserMonthCount,
      currentUserTotalCount,
      currentUserMonthRank,
      visitStatsForWeek,
      rankingForPeriod,
      signUpWithEmail,
      signInWithEmail,
      resendSignupEmail,
      resetPassword,
      signOut,
      setTodayIntent,
      checkIn,
      checkOut,
      cancelCheckIn,
      cancelCheckOut,
      updateProfile,
      updateAvatar,
      reload,
    ],
  )

  return <GymStoreContext.Provider value={value}>{children}</GymStoreContext.Provider>
}

export function useGymStore() {
  const value = useContext(GymStoreContext)
  if (!value) throw new Error('useGymStore must be used within GymStoreProvider')
  return value
}
