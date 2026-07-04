import { useState } from 'react'
import { useGymStore } from '../store/GymStoreContext'
import { Avatar } from '../components/Avatar'
import { IconDumbbell } from '../components/Icons'
import type { Member } from '../types'

export function ClaimMemberPage() {
  const store = useGymStore()
  const [pendingId, setPendingId] = useState<string | null>(null)
  const [confirmMember, setConfirmMember] = useState<Member | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function handleConfirm() {
    if (!confirmMember) return
    setPendingId(confirmMember.id)
    setError(null)
    const { error } = await store.claimMember(confirmMember.id)
    setPendingId(null)
    if (error) {
      setError(error)
      setConfirmMember(null)
      return
    }
    setConfirmMember(null)
  }

  return (
    <div className="auth-page">
      <div className="auth-hero">
        <div className="auth-hero-icon">
          <IconDumbbell size={46} />
        </div>
        <h1>筋肉クラブ</h1>
        <p>あなたの名前をタップしてください。この端末に紐づきます。</p>
      </div>

      <section className="card">
        <div className="card-title">WHO ARE YOU</div>
        {store.unclaimedMembers.length === 0 ? (
          <p className="auth-card-body">
            使えるアカウントがありません。管理者に連絡してメンバー登録をお願いしてください。
          </p>
        ) : (
          <div className="member-picker-list">
            {store.unclaimedMembers.map((member) => (
              <button
                key={member.id}
                className="member-picker-row"
                disabled={pendingId === member.id}
                onClick={() => setConfirmMember(member)}
              >
                <Avatar member={member} size={44} />
                <span>{member.name}</span>
              </button>
            ))}
          </div>
        )}
        {error && <div className="message-block danger">{error}</div>}
        {store.lastErrorMessage && <div className="message-block danger">{store.lastErrorMessage}</div>}
        <button className="text-link" onClick={() => store.reload()}>
          一覧を更新する
        </button>
      </section>

      {confirmMember && (
        <div className="sheet-backdrop" onClick={() => setConfirmMember(null)}>
          <div className="popup-card" onClick={(e) => e.stopPropagation()}>
            <h3>「{confirmMember.name}」で間違いないですか?</h3>
            <p className="muted">一度選ぶと、この端末はずっとこの名前として使われます。</p>
            <button className="primary-button" onClick={handleConfirm}>
              これは自分です
            </button>
            <button className="ghost-button" onClick={() => setConfirmMember(null)}>
              キャンセル
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
