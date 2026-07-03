import type { ReactNode } from 'react'

export function Card({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="card">
      <div className="card-title">{title}</div>
      {children}
    </section>
  )
}
