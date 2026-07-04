import { useEffect, useRef, useState } from 'react'
import { useGymStore } from '../store/GymStoreContext'
import { Card } from '../components/Card'
import { Avatar } from '../components/Avatar'
import { getExistingPushSubscription, isPushSupported, subscribeToPush, unsubscribeFromPush } from '../push/push'
import { supabase } from '../lib/supabaseClient'
import { resizeToSquareJpeg } from '../lib/image'

const VAPID_PUBLIC_KEY = import.meta.env.VITE_VAPID_PUBLIC_KEY as string | undefined

export function MyPage() {
  const store = useGymStore()
  const [name, setName] = useState(store.currentUser?.name ?? '')
  const [pushEnabled, setPushEnabled] = useState(false)
  const [pushBusy, setPushBusy] = useState(false)
  const [pushMessage, setPushMessage] = useState<string | null>(null)
  const [avatarBusy, setAvatarBusy] = useState(false)
  const [avatarMessage, setAvatarMessage] = useState<string | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)

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

  async function handleAvatarSelected(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file) return
    setAvatarBusy(true)
    setAvatarMessage(null)
    try {
      const image = await resizeToSquareJpeg(file, 256)
      const { error } = await store.updateAvatar(image)
      setAvatarMessage(error ?? 'アイコンを変更しました。')
    } catch {
      setAvatarMessage('画像を読み込めませんでした。別の写真で試してください。')
    } finally {
      setAvatarBusy(false)
    }
  }

  if (!store.currentUser) return null

  return (
    <div className="page">
      <header>
        <div className="eyebrow">PROFILE</div>
        <h1>{store.currentUser.name}</h1>
        <p className="muted">この端末に紐づいています</p>
      </header>

      <Card title="ACCOUNT">
        <div className="profile-hero">
          <button
            type="button"
            className="avatar-edit-button"
            disabled={avatarBusy}
            onClick={() => fileInputRef.current?.click()}
            aria-label="アイコンを変更"
          >
            <Avatar member={store.currentUser} size={84} />
            <span className="avatar-edit-badge">{avatarBusy ? '…' : '📷'}</span>
          </button>
          <input
            ref={fileInputRef}
            type="file"
            accept="image/*"
            hidden
            onChange={handleAvatarSelected}
          />
          <p className="muted small">アイコンをタップして写真を変更</p>
          {avatarMessage && <div className="message-block accent">{avatarMessage}</div>}
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

      {store.lastErrorMessage && (
        <Card title="ERROR">
          <div className="message-block danger">{store.lastErrorMessage}</div>
        </Card>
      )}
    </div>
  )
}
