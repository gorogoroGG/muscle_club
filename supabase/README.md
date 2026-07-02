# Supabase セットアップ

このアプリを Supabase に接続するための手順です。

## まずやること

1. Supabase で新しいプロジェクトを作成する。
2. Supabase の SQL Editor で `schema.sql` を実行する。
3. `2026-07-01_notifications_and_attendance.sql` も実行する。
4. アプリのビルド設定か Scheme の環境変数に次の2つを入れる。
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
5. Supabase の Auth 設定で Apple Provider を有効にする。
6. iOS 側で `Sign in with Apple` capability を有効にする。

## 次にやること

1. アプリを起動して Apple でログインする。
2. 登録した全員が同じ空間を共有するので、そのまま参加予定の登録を試す。
3. 設定したジムの位置に3分ほど滞在して、自動チェックインされるか確認する。

## テーブル

- `members`
- `attendance_records`(今日の参加/不参加の意思表示のみ)
- `gym_visits`(チェックイン〜チェックアウトの滞在記録)
- `chat_messages`(全体チャット)

## 補足

- `members.id` は Supabase Auth の `auth.users.id` と同じ UUID になります。
- グループの概念は廃止済みで、登録している全メンバーが常に同じ予定・チェックイン状況を共有します。
- チェックイン/チェックアウトは自己申告ではなく、位置情報による自動判定(ジムに3分連続滞在/3分連続離脱)で `gym_visits` に記録されます。
- チャットは全体向けで、`@名前` 形式のメンションを保存します。
- ローカルのサンプル表示は、Supabase 設定がまだ入っていない場合のみ使われます。
- `row-level security policy` エラーが出る場合は、SQL Editor で `schema.sql` をもう一度実行して、RLS policy が作成されているか確認してください。
