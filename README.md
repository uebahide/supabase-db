# supabase-db

uebahide のアプリが共有している Supabase（プロジェクト名: uchinooshi）のデータベース定義です。
どのアプリのテーブルも、ここの `supabase/migrations/` にある SQL で作ります。SQL Editor に直接貼って変更するのはやめて、必ずこのリポジトリを通します。

## 使っているアプリ

| スキーマ | アプリ | リポジトリ |
| --- | --- | --- |
| `core` | 全アプリ共通（プロフィール、アプリ一覧、利用者） | このリポジトリ |
| `oshi` | 推しノート | [uchinooshi-app](https://github.com/uebahide/uchinooshi-app) |
| `recipe` | レシピDB | recipe-app（これから） |

## ルール

- **スキーマ名 = アプリ名。** 英小文字1単語。テーブル、Storage バケット（`<アプリ名>-<用途>`）、マイグレーションのファイル名にも同じ名前を入れます。
- **`public` には何も置きません。** 新しいテーブルは必ずアプリのスキーマか `core` に作ります。
- **ログインは全アプリ共通**（`auth.users`）。アプリ側は初回利用時に `core.app_members` に自分を登録します。
- **全テーブルに `user_id` と RLS。** 「自分の行だけ読み書きできる」が標準です。
- **アプリ同士は直接読みません。** 各アプリは自分のスキーマと `core` だけを使います。
- **`updated_at` は `core.set_updated_at()` のトリガーで更新します。**
- **Storage のパスは `<user_id>/...`。** バケットのポリシーで、先頭フォルダが自分の id のときだけ読み書きできるようにします。

## 新しいアプリを追加する

1. `templates/new_app.sql` をコピーし、`myapp` をアプリ名に置き換えて `supabase/migrations/<YYYYMMDDHHMMSS>_<アプリ名>_init.sql` として保存します。
2. `supabase/config.toml` の `schemas` にアプリ名を足します。
3. PR を出します。Check migrations が通ったらマージすると、本番に適用されます。
4. Supabase の画面で次の2つを設定します。
   - Settings > Data API > Exposed schemas にアプリ名を追加
   - Authentication > URL Configuration > Redirect URLs にアプリの URL を追加
5. アプリ側は uchinooshi-app の `src/lib/supabase/` をコピーし、`env.ts` の `supabaseSchema` をアプリ名にします。Vercel には `NEXT_PUBLIC_SUPABASE_URL` と `NEXT_PUBLIC_SUPABASE_ANON_KEY` を入れます（全アプリ同じ値）。

型が欲しいときは `supabase gen types typescript --project-id <id> --schema <アプリ名> > types.ts` で作れます。

## 本番への適用（初回の設定）

GitHub の Settings > Secrets and variables > Actions に次の3つを登録すると、main へのマージで自動適用されます。

| 名前 | 値 |
| --- | --- |
| `SUPABASE_ACCESS_TOKEN` | Supabase の Account > Access Tokens で作ったトークン |
| `SUPABASE_DB_PASSWORD` | プロジェクトのデータベースパスワード |
| `SUPABASE_PROJECT_ID` | プロジェクトの Reference ID（URL の `https://<ここ>.supabase.co`） |

`20261001000000_oshi_baseline.sql` は、以前 SQL Editor で手動適用していた推しノートのテーブルです。何度流しても同じ結果になるように書いてあるので、本番にそのまま流して問題ありません。

### 2026年10月の移行（推しノートを `oshi` スキーマへ）

`20261020000100_oshi_move_to_schema.sql` が本番に入った瞬間から、古い推しノートはデータを読めなくなります。次の順で続けて行ってください。

1. Exposed schemas に `core`、`oshi`、`recipe` を追加
2. このリポジトリの PR をマージ（Deploy migrations が緑になるのを確認）
3. uchinooshi-app の「共有DBの oshi スキーマを使うようにする」PR をマージ（Vercel が再デプロイ）
