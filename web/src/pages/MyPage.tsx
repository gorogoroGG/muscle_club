import { useEffect, useState } from 'react'
import { useGymStore } from '../store/GymStoreContext'
import { Card } from '../components/Card'
import { Avatar } from '../components/Avatar'
import { getExistingPushSubscription, isPushSupported, subscribeToPush, unsubscribeFromPush } from '../push/push'
import { supabase } from '../lib/supabaseClient'

const VAPID_PUBLIC_KEY = import.meta.env.VITE_VAPID_PUBLIC_KEY as string | undefined

export function MyPage() {
  const store = useGymStore()
  const [name, setName] = useState(store.currentUser?.name ?? '')
  const [pushEnabled, setPushEnabled] = useState(false)
  const [pushBusy, setPushBusy] = useState(false)
  const [pushMessage, setPushMessage] = useState<string | null>(null)

  useEffect(() => {
    setName(store.currentUser?.name ?? '')
  }, [store.currentUser?.name])

  useEffect(() => {
    getExistingPushSubscription()
      .then((sub) => setPushEnabled(Boolean(sub)))
      .catch(() => undefined)
  }, [])

  async function handleEnablePush() {
    if (!VAPID_PUBLIC_KEY || !store.currentUser) return
    setPushBusy(true)
    setPushMessage(null)
    try {
      const subscription = await subscribeToPush(VAPID_PUBLIC_KEY)
      const json = subscription.toJSON()
      const { error } = await supabase.from('push_subscriptions').upsert(
        {
          member_id: store.currentUser.id,
          endpoint: subscription.endpoint,
          p256dh: json.keys?.p256dh,
          auth: json.keys?.auth,
        },
        { onConflict: 'endpoint' },
      )
      if (error) throw error
      setPushEnabled(true)
      setPushMessage('通知をオンにしました。')
    } catch (error) {
      setPushMessage(error instanceof Error ? error.message : String(error))
    } finally {
      setPushBusy(false)
    }
  }

  async function handleDisablePush() {
    setPushBusy(true)
    try {
      const existing = await getExistingPushSubscription()
      if (existing) {
        await supabase.from('push_subscriptions').delete().eq('endpoint', existing.endpoint)
      }
      await unsubscribeFromPush()
      setPushEnabled(false)
      setPushMessage('通知をオフにしました。')
    } catch (error) {
      setPushMessage(error instanceof Error ? error.message : String(error))
    } finally {
      setPushBusy(false)
    }
  }

  if (!store.currentUser) return null

  return (
    <div className="page">
      <header>
        <div className="eyebrow">PROFILE</div>
        <h1>{store.currentUser.name}</h1>
        <p className="muted">Apple ID でログイン中</p>
      </header>

      <Card title="ACCOUNT">
        <div className="profile-hero">
          <Avatar member={store.currentUser} size={74} />
          <form
            className="profile-form"
            onSubmit={(e) => {
              e.preventDefault()
              store.updateProfile(name)
            }}
          >
            <input value={name} onChange={(e) => setName(e.target.value)} placeholder="表示名" />
            <button type="submit" className="secondary-button">
              名前を更新
            </button>
          </form>
        </div>
      </Card>

      <Card title="NOTIFICATIONS">
        <h3 className="section-heading">プッシュ通知</h3>
        <p className="muted">
          誰かがチェックイン・チェックアウト・参加/不参加を宣言したときに、この端末に通知を送ります。
        </p>
        {!isPushSupported ? (
          <div className="message-block warning">
            このブラウザはプッシュ通知に対応していません。ホーム画面に追加してから開いてください。
          </div>
        ) : !VAPID_PUBLIC_KEY ? (
          <div className="message-block warning">VAPID公開鍵が未設定です。</div>
        ) : (
          <button
            className={pushEnabled ? 'secondary-button danger' : 'primary-button'}
            disabled={pushBusy}
            onClick={pushEnabled ? handleDisablePush : handleEnablePush}
          >
            {pushEnabled ? '通知をオフにする' : '通知をオンにする'}
          </button>
        )}
        {pushMessage && <div className="message-block accent">{pushMessage}</div>}
      </Card>

      <Card title="SESSION">
        <h3 className="section-heading">アカウント</h3>
        {store.lastErrorMessage && <div className="message-block danger">{store.lastErrorMessage}</div>}
        <button className="secondary-button danger" onClick={() => store.signOut()}>
          ログアウト
        </button>
      </Card>
    </div>
  )
}
