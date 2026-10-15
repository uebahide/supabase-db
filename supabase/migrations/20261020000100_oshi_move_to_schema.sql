-- うちの推し: public.oshis を oshi スキーマへ移動
-- データ・インデックス・RLSポリシー・権限はテーブルと一緒に移動する。
-- 適用直後に「schema: 'oshi'」に対応したアプリをデプロイする（個人利用なので数分の切り替えで済む）。

create schema if not exists oshi;
grant usage on schema oshi to authenticated;

alter table public.oshis set schema oshi;

-- updated_at トリガーを共通関数に付け替え、public の関数を片付ける
drop trigger if exists oshis_set_updated_at on oshi.oshis;
create trigger oshis_set_updated_at before update on oshi.oshis
  for each row execute function core.set_updated_at();
drop function if exists public.set_updated_at();

-- 既存ユーザーを推しノートの利用者として登録
insert into core.app_members (user_id, app_slug)
  select distinct user_id, 'oshi' from oshi.oshis
on conflict do nothing;
