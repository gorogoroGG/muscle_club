import { useState } from 'react'
import { useGymStore } from '../store/GymStoreContext'
import { isSupabaseConfigured } from '../lib/supabaseClient'

export function AuthPage() {
  const store = useGymStore()
  const [email, setEmail] = useState('')
  const [isSending, setIsSending] = useState(false)
  const [magicLinkMessage, setMagicLinkMessage] = useState<string | null>(null)
  const [magicLinkError, setMagicLinkError] = useState<string | null>(null)

  async function handleSendMagicLink(e: React.FormEvent) {
    e.preventDefault()
    setIsSending(true)
    setMagicLinkMessage(null)
    setMagicLinkError(null)
    const { error } = await store.sendMagicLink(email)
    setIsSending(false)
    if (error) {
      setMagicLinkError(error)
      return
    }
    setMagicLinkMessage('ログイン用のリンクを送信しました。メールを確認してください。')
  }

  return (
    <div className="auth-page">
      <div className="auth-hero">
        <div className="auth-hero-icon">💪</div>
        <h1>筋肉クラブ</h1>
        <p>仲間と予定を共有して、ジムの継続を続けやすくするアプリです。</p>
      </div>

      <section className="card">
        <div className="card-title">APPLE SIGN IN</div>
        <h2 className="auth-card-title">Apple ID でログイン</h2>
        <p className="auth-card-body">
          ログインすると、自分の記録を安全に管理しつつ、登録メンバー全員と予定とチェックインを共有できます。
        </p>

        <button
          className="apple-signin-button"
          disabled={!isSupabaseConfigured}
          onClick={() => store.signInWithApple()}
        >
           Apple でサインイン
        </button>

        {store.lastErrorMessage && <div className="message-block danger">{store.lastErrorMessage}</div>}
        {!isSupabaseConfigured && (
          <div className="message-block warning">
            Supabase の URL / ANON KEY を設定すると Apple ID ログインを開始できます。
          </div>
        )}
      </section>

      <div className="auth-divider">または</div>

      <section className="card">
        <div className="card-title">EMAIL SIGN IN</div>
        <h2 className="auth-card-title">メールアドレスでログイン</h2>
        <p className="auth-card-body">
          ログイン用のリンクをメールで送ります。パスワードは不要です。
        </p>

        <form className="magic-link-form" onSubmit={handleSendMagicLink}>
          <input
            type="email"
            required
            placeholder="you@example.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            disabled={!isSupabaseConfigured || isSending}
          />
          <button type="submit" className="secondary-button" disabled={!isSupabaseConfigured || isSending}>
            {isSending ? '送信中...' : 'ログインリンクを送る'}
          </button>
        </form>

        {magicLinkMessage && <div className="message-block accent">{magicLinkMessage}</div>}
        {magicLinkError && <div className="message-block danger">{magicLinkError}</div>}
      </section>

      <ul className="benefit-list">
        <li>登録メンバー全員の情報を見られます</li>
        <li>予定とチェックインをすばやく共有できます</li>
        <li>Supabase Auth と RLS でデータを制限します</li>
      </ul>
    </div>
  )
}
