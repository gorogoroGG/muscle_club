import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { startAppUpdatePolling } from './lib/appUpdate'
import { registerServiceWorker } from './push/push'

registerServiceWorker().catch(() => undefined)
startAppUpdatePolling()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
