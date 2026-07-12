const holidayCache = new Map<number, Set<string>>()

export interface GymHoursInfo {
  isClosed: boolean
  hoursText: string
  noticeText: string | null
  closeAt: Date | null
}

function startOfDay(date: Date): Date {
  const value = new Date(date)
  value.setHours(0, 0, 0, 0)
  return value
}

function dayKey(date: Date): string {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

function dateFromKey(key: string): Date {
  const [year, month, day] = key.split('-').map(Number)
  return new Date(year, month - 1, day, 12, 0, 0, 0)
}

function buildDate(year: number, monthIndex: number, day: number): Date {
  return new Date(year, monthIndex, day, 12, 0, 0, 0)
}

function isLastDayOfMonth(date: Date): boolean {
  const nextDay = new Date(date)
  nextDay.setDate(nextDay.getDate() + 1)
  return nextDay.getMonth() !== date.getMonth()
}

function nthWeekdayOfMonth(year: number, monthIndex: number, weekday: number, nth: number): number {
  const lastDay = new Date(year, monthIndex + 1, 0).getDate()
  let count = 0
  for (let day = 1; day <= lastDay; day += 1) {
    if (buildDate(year, monthIndex, day).getDay() === weekday) {
      count += 1
      if (count === nth) return day
    }
  }
  return 1
}

function springEquinoxDay(year: number): number {
  return Math.floor(20.8431 + 0.242194 * (year - 1980) - Math.floor((year - 1980) / 4))
}

function autumnEquinoxDay(year: number): number {
  return Math.floor(23.2488 + 0.242194 * (year - 1980) - Math.floor((year - 1980) / 4))
}

function buildBaseHolidaySet(year: number): Set<string> {
  const dates = new Set<string>()
  const add = (monthIndex: number, day: number) => {
    dates.add(dayKey(buildDate(year, monthIndex, day)))
  }

  add(0, 1)
  add(0, nthWeekdayOfMonth(year, 0, 1, 2))
  add(1, 11)
  add(1, 23)
  add(2, springEquinoxDay(year))
  add(3, 29)
  add(4, 3)
  add(4, 4)
  add(4, 5)
  add(6, nthWeekdayOfMonth(year, 6, 1, 3))
  add(7, 11)
  add(8, nthWeekdayOfMonth(year, 8, 1, 3))
  add(8, autumnEquinoxDay(year))
  add(9, nthWeekdayOfMonth(year, 9, 1, 2))
  add(10, 3)
  add(10, 23)

  return dates
}

function buildJapaneseHolidaySet(year: number): Set<string> {
  if (holidayCache.has(year)) {
    return holidayCache.get(year)!
  }

  const holidays = buildBaseHolidaySet(year)
  let changed = true

  while (changed) {
    changed = false
    const snapshot = [...holidays]

    for (const key of snapshot) {
      const date = dateFromKey(key)
      if (date.getDay() !== 0) continue

      const substitute = new Date(date)
      substitute.setDate(substitute.getDate() + 1)
      while (holidays.has(dayKey(substitute))) {
        substitute.setDate(substitute.getDate() + 1)
      }

      const substituteKey = dayKey(substitute)
      if (!holidays.has(substituteKey)) {
        holidays.add(substituteKey)
        changed = true
      }
    }

    const cursor = new Date(year, 0, 1, 12, 0, 0, 0)
    while (cursor.getFullYear() === year) {
      const currentKey = dayKey(cursor)
      if (!holidays.has(currentKey)) {
        const previous = new Date(cursor)
        previous.setDate(previous.getDate() - 1)
        const next = new Date(cursor)
        next.setDate(next.getDate() + 1)

        if (holidays.has(dayKey(previous)) && holidays.has(dayKey(next))) {
          holidays.add(currentKey)
          changed = true
        }
      }

      cursor.setDate(cursor.getDate() + 1)
    }
  }

  holidayCache.set(year, holidays)
  return holidays
}

export function isJapaneseHoliday(date: Date): boolean {
  return buildJapaneseHolidaySet(date.getFullYear()).has(dayKey(startOfDay(date)))
}

export function getGymHours(date: Date = new Date()): GymHoursInfo {
  const day = startOfDay(date)
  const weekday = day.getDay()

  if (weekday === 1 || isLastDayOfMonth(day)) {
    return {
      isClosed: true,
      hoursText: '休館日',
      noticeText: null,
      closeAt: null,
    }
  }

  const isSundayOrHoliday = weekday === 0 || isJapaneseHoliday(day)
  const closeHour = isSundayOrHoliday ? 18 : weekday === 6 ? 22 : 23
  const closeAt = new Date(day)
  closeAt.setHours(closeHour, 0, 0, 0)

  return {
    isClosed: false,
    hoursText: `10:00〜${String(closeHour).padStart(2, '0')}:00`,
    noticeText: closeAt.getTime() - date.getTime() <= 60 * 60 * 1000 && closeAt.getTime() > date.getTime()
      ? '残り1時間で閉店です。'
      : null,
    closeAt,
  }
}

export function isGymClosed(date: Date = new Date()): boolean {
  return getGymHours(date).isClosed
}
