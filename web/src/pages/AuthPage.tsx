import { useState } from 'react'
import { useGymStore } from '../store/GymStoreContext'
import { IconDumbbell } from '../components/Icons'

type AuthMode = 'signIn' | 'signUp'

export function AuthPage() {
  const store = useGymStore()
  const [mode, setMode] = useState<AuthMode>('signIn')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [name, setName] = useState('')
  const [busy, setBusy] = useState(false)
  const [sentSignupEmail, setSentSignupEmail] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setBusy(true)
    setSentSignupEmail(null)
    setMessage(null)
    setError(null)

    const result =
      mode === 'signUp'
        ? await store.signUpWithEmail({ email, password, name })
        : await store.signInWithEmail(email, password)

    setBusy(false)
    if (result.error) {
      setError(result.error)
      return
    }

    if (mode === 'signUp' && 'needsEmailConfirmation' in result && result.needsEmailConfirmation) {
      const normalizedEmail = email.trim()
      setSentSignupEmail(normalizedEmail)
      setMessage('確認メールを送りました。メール内のリンクを開いてからログインしてください。')
      setMode('signIn')
      return
    }

    setMessage(mode === 'signUp' ? 'アカウントを作成しました。' : 'ログインしました。')
  }

  async function handleResetPassword() {
    setBusy(true)
    setMessage(null)
    setError(null)
    const result = await store.resetPassword(email)
    setBusy(false)
    if (result.error) {
      setError(result.error)
      return
    }
    setMessage('登録済みのメールアドレス宛に、パスワード再設定メールを送りました。')
  }

  async function handleResendSignupEmail() {
    if (!sentSignupEmail) return
    setBusy(true)
    setMessage(null)
    setError(null)
    const result = await store.resendSignupEmail(sentSignupEmail)
    setBusy(false)
    if (result.error) {
      setError(result.error)
      return
    }
    setMessage('確認メールを再送しました。')
  }

  return (
    <div className="auth-page">
      <div className="auth-hero">
        <div className="auth-hero-icon">
          <IconDumbbell size={46} />
        </div>
        <h1>筋肉クラブ</h1>
        <p>メールアドレスでアカウントを作成して、今日のジム状況を共有できます。</p>
      </div>

      <section className="card">
        <div className="auth-mode-tabs" aria-label="認証モード">
          <button className={mode === 'signIn' ? 'active' : ''} onClick={() => setMode('signIn')} type="button">
            ログイン
          </button>
          <button className={mode === 'signUp' ? 'active' : ''} onClick={() => setMode('signUp')} type="button">
            新規登録
          </button>
        </div>

        <form className="profile-form" onSubmit={handleSubmit}>
          {mode === 'signUp' && (
            <input
              autoComplete="name"
              placeholder="表示名"
              value={name}
              onChange={(event) => setName(event.target.value)}
            />
          )}
          <input
            type="email"
            autoComplete="email"
            inputMode="email"
            placeholder="you@example.com"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
          />
          <input
            type="password"
            autoComplete={mode === 'signUp' ? 'new-password' : 'current-password'}
            placeholder="パスワード"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
          />
          <button type="submit" className="primary-button" disabled={busy}>
            {busy ? '処理中...' : mode === 'signUp' ? 'アカウントを作成' : 'ログイン'}
          </button>
        </form>

        {mode === 'signIn' && (
          <button type="button" className="text-link" onClick={handleResetPassword} disabled={busy}>
            パスワードを忘れた場合
          </button>
        )}
        {sentSignupEmail && (
          <button type="button" className="secondary-button" onClick={handleResendSignupEmail} disabled={busy}>
            確認メールを再送する
          </button>
        )}
        {message && <div className="message-block accent">{message}</div>}
        {error && <div className="message-block danger">{error}</div>}
        {store.lastErrorMessage && <div className="message-block danger">{store.lastErrorMessage}</div>}
      </section>
    </div>
  )
}
