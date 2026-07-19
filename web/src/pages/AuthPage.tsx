import { useMemo, useState } from 'react'
import { useGymStore } from '../store/GymStoreContext'
import { IconDumbbell } from '../components/Icons'

function authErrorFromHash(): string | null {
  if (typeof window === 'undefined') return null
  const params = new URLSearchParams(window.location.hash.startsWith('#') ? window.location.hash.slice(1) : window.location.hash)
  return params.get('error_description')
}

export function AuthPage() {
  const store = useGymStore()
  const [email, setEmail] = useState('')
  const [busy, setBusy] = useState(false)
  const [sentTo, setSentTo] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const hashError = useMemo(() => authErrorFromHash(), [])

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setBusy(true)
    setError(null)
    const normalized = email.trim()
    const { error } = await store.signInWithEmail(normalized)
    setBusy(false)
    if (error) {
      setError(error)
      return
    }
    setSentTo(normalized)
  }

  return (
    <div className="auth-page">
      <div className="auth-hero">
        <div className="auth-hero-icon">
          <IconDumbbell size={46} />
        </div>
        <h1>筋肉クラブ</h1>
        <p>メールに届くログインリンクから入ってください。</p>
      </div>

      <section className="card">
        <div className="card-title">LOGIN</div>
        <form className="profile-form" onSubmit={handleSubmit}>
          <input
            type="email"
            autoComplete="email"
            inputMode="email"
            placeholder="you@example.com"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
          />
          <button type="submit" className="primary-button" disabled={busy}>
            {busy ? '送信中…' : 'ログインリンクを送る'}
          </button>
        </form>
        <p className="muted small">初回ログイン後に、あなたの名前を1回だけ選びます。</p>
        {sentTo && (
          <div className="message-block accent">
            {sentTo} にログインリンクを送りました。メールアプリからリンクを開いてください。
          </div>
        )}
        {error && <div className="message-block danger">{error}</div>}
        {hashError && <div className="message-block danger">{hashError}</div>}
        {store.lastErrorMessage && <div className="message-block danger">{store.lastErrorMessage}</div>}
      </section>
    </div>
  )
}
