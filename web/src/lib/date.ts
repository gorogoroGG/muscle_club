export function startOfDay(date: Date): Date {
  const d = new Date(date)
  d.setHours(0, 0, 0, 0)
  return d
}

export function isSameDay(a: Date, b: Date): boolean {
  return startOfDay(a).getTime() === startOfDay(b).getTime()
}

export function isDateInToday(date: Date): boolean {
  return isSameDay(date, new Date())
}

export function isSameMonth(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth()
}

export function mondayOfWeek(date: Date): Date {
  const day = startOfDay(date)
  const weekday = day.getDay() // 0 = Sunday
  const offset = weekday === 0 ? -6 : 1 - weekday
  const monday = new Date(day)
  monday.setDate(monday.getDate() + offset)
  return monday
}

export function addDays(date: Date, amount: number): Date {
  const d = new Date(date)
  d.setDate(d.getDate() + amount)
  return d
}

export function addMonths(date: Date, amount: number): Date {
  const d = new Date(date)
  d.setMonth(d.getMonth() + amount)
  return d
}

const WEEKDAY_LABELS_JA = ['日', '月', '火', '水', '木', '金', '土']

export function weekdayLabel(date: Date): string {
  return WEEKDAY_LABELS_JA[date.getDay()]
}

export function monthLabel(date: Date): string {
  return `${date.getMonth() + 1}月`
}

export function minutesBetween(start: Date, end: Date): number {
  return Math.max(0, Math.floor((end.getTime() - start.getTime()) / 60000))
}

export function formatMinutes(totalMinutes: number): string {
  const hours = Math.floor(totalMinutes / 60)
  const minutes = totalMinutes % 60
  return hours > 0 ? `${hours}時間${minutes}分` : `${minutes}分`
}

export function formatDateTime(iso: string): string {
  const date = new Date(iso)
  return date.toLocaleString('ja-JP', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}
