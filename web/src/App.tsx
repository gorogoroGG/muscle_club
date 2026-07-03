import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { GymStoreProvider, useGymStore } from './store/GymStoreContext'
import { AuthPage } from './pages/AuthPage'
import { HomePage } from './pages/HomePage'
import { RecordPage } from './pages/RecordPage'
import { MyPage } from './pages/MyPage'
import { BottomNav } from './components/BottomNav'
import { InstallBanner } from './components/InstallBanner'

function Screen() {
  const store = useGymStore()

  if (store.appMode === 'loading') {
    return (
      <div className="centered-state">
        <div className="spinner" />
        <h2>同期しています</h2>
        <p className="muted">アカウントとトレーニング記録を読み込んでいます。</p>
      </div>
    )
  }

  if (store.appMode === 'signedOut') {
    return <AuthPage />
  }

  if (store.appMode === 'failed') {
    return (
      <div className="centered-state">
        <h2>データを開けませんでした</h2>
        <p className="muted">{store.lastErrorMessage}</p>
        <button className="primary-button" onClick={store.reload}>
          もう一度読み込む
        </button>
        <button className="secondary-button danger" onClick={store.signOut}>
          ログアウトする
        </button>
      </div>
    )
  }

  return (
    <BrowserRouter basename={import.meta.env.BASE_URL}>
      <InstallBanner />
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route path="/record" element={<RecordPage />} />
        <Route path="/me" element={<MyPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
      <BottomNav />
    </BrowserRouter>
  )
}

export default function App() {
  return (
    <GymStoreProvider>
      <div className="app-background">
        <Screen />
      </div>
    </GymStoreProvider>
  )
}
