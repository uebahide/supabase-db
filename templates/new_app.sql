-- 新しいアプリを追加するときのテンプレート
-- 使い方: myapp を新しいアプリのスキーマ名（英小文字）に置き換えて、
--   supabase/migrations/<YYYYMMDDHHMMSS>_myapp_init.sql として保存 → PR → マージで本番に適用

insert into core.apps (slug, name) values ('myapp', 'アプリの表示名') on conflict do nothing;

create schema if not exists myapp;
grant usage on schema myapp to authenticated;

create table myapp.items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  -- ここにアプリ固有の列
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on myapp.items (user_id);
alter table myapp.items enable row level security;
create policy "items_own" on myapp.items for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
grant select, insert, update, delete on myapp.items to authenticated;
create trigger items_set_updated_at before update on myapp.items
  for each row execute function core.set_updated_at();

-- 忘れずに: Supabase の Settings > Data API > Exposed schemas に myapp を追加
--          Authentication > URL Configuration > Redirect URLs にアプリのURLを追加
