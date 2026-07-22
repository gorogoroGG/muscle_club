# Supabase セットアップ

このアプリ(ネイティブ版 / PWA版共通)を Supabase に接続するための手順です。

## まずやること

1. Supabase で新しいプロジェクトを作成する。
2. Supabase の SQL Editor で `schema.sql` を実行する。
3. `2026-07-01_notifications_and_attendance.sql` を実行する。
4. `2026-07-03_pwa_migration.sql` を実行する(チャット廃止 / push_subscriptions テーブル追加)。
5. `2026-07-04_anonymous_member_claim.sql` を実行する(匿名ログイン対応)。
6. `2026-07-16_member_picker_mode.sql` を実行する(PWAを毎回メンバー選択方式に変更)。
7. `2026-07-19_email_login_restore_claims.sql` を実行する(PWAをメールログイン + 初回だけ名前ひも付け方式に変更)。
8. `2026-07-22_full_renewal_email_accounts.sql` を実行する(PWAをメール + パスワード登録方式に変更)。
9. Supabase の Auth 設定で Apple Provider を有効にする(ネイティブアプリのみで使用。
   Bundle ID ベースの設定で問題ありません)。
10. iOS 側で `Sign in with Apple` capability を有効にする(ネイティブアプリのみ)。

## PWA(`web/`)を動かす

PWA版はメールアドレス + パスワードでアカウントを作成し、登録時の表示名でメンバー情報を作成します
(Apple Sign Inは使いません。Web用のApple Services ID設定も不要です)。

1. `web/.env.local` に `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` / `VITE_VAPID_PUBLIC_KEY` を設定する。
2. Supabase Dashboard → Authentication → URL Configuration で以下を設定する。
   - Site URL: `https://gorogorogg.github.io/muscle_club/`
   - Redirect URLs: `https://gorogorogg.github.io/muscle_club/**`
   - 開発用に `http://localhost:5173/**` も追加する
3. Authentication → Sign In / Providers で Email を有効にし、Password sign-in を使える状態にする。
4. Authentication → Sign In / Providers → Email で、運用方針に合わせて以下のどちらかを設定する。
   - クローズドな少人数運用: `Confirm email` をオフにする(登録直後にログイン可能)。
   - メール確認を必須にする運用: Authentication → Emails → SMTP Settings でカスタムSMTPを設定する。
5. もし不要なら Anonymous Sign-Ins を無効にする。
6. `cd web && npm install && npm run dev`
7. iPhone Safari で開いて「ホーム画面に追加」する(Web Push は iOS 16.4+ かつ
   ホーム画面に追加した状態でないと使えません)。

Supabase標準のメール送信サービスは本番用ではありません。チームメンバー以外の宛先に送れない場合や、
低いレート制限に当たる場合があります。メール確認やパスワード再設定メールを確実に使う場合は、
Resend / SendGrid / AWS SES などのSMTPを設定してください。

## Web Push 通知の配信基盤

1. VAPID鍵ペアを発行する(`npx web-push generate-vapid-keys` などで一度だけ生成)。
2. Edge Function をデプロイする: `supabase functions deploy send-push`
3. シークレットを設定する:
   ```
   supabase secrets set VAPID_PUBLIC_KEY=... VAPID_PRIVATE_KEY=... VAPID_SUBJECT=mailto:you@example.com
   ```
4. Supabase Dashboard → Database → Webhooks で以下のWebhookを作成する:
   - Table: `public.notifications`
   - Events: `Insert`
   - Type: Supabase Edge Function
   - Function: `send-push`

これで、`notifications` テーブルに行がinsertされるたびに `send-push` が呼ばれ、
対象メンバーの登録デバイスへプッシュ通知が飛びます。

## テーブル

- `members`
- `daily_intents`(今日行く/行かないの意思表示)
- `gym_visits`(チェックイン〜チェックアウトの記録。PWA版は手動チェックイン/チェックアウト)
- `attendance_records`(旧方式の参加/不参加データ。互換用に残置)
- `notifications`(参加/不参加/チェックイン/チェックアウト/チェックイン取消の通知)
- `push_subscriptions`(Web Push購読情報。PWA版のみ使用)

## 補足

- PWA版では `members.user_id` が `auth.users.id` を指し、ログインユーザー自身のプロフィールとして扱います。
- グループの概念は廃止済みで、登録している全メンバーが常に同じ予定・チェックイン状況を共有します。
- チャット機能と自動チェックイン(位置情報によるジオフェンシング)は廃止されました。
  チェックイン/チェックアウトは手動操作で記録します。
- ランキングはジムに行った回数ベースです。同じ日に複数回チェックインしてもランキング上は1回として数えます。
- `row-level security policy` エラーが出る場合は、SQL Editor で `schema.sql` をもう一度実行して、RLS policy が作成されているか確認してください。
