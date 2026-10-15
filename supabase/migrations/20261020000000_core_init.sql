-- 共有DBの土台: core スキーマ（全アプリ共通）
-- ログイン(auth.users)は全アプリで共通。アプリ固有のデータは各アプリのスキーマへ。

create schema if not exists core;
grant usage on schema core to authenticated;

-- updated_at を自動更新する共通関数（各アプリのトリガーから使う）
create or replace function core.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- このDBに載っているアプリの一覧（アプリ追加時に1行足す）
create table if not exists core.apps (
  slug text primary key check (slug ~ '^[a-z][a-z0-9_]*$'),   -- = スキーマ名
  name text not null,
  created_at timestamptz not null default now()
);
alter table core.apps enable row level security;
create policy "apps_read" on core.apps for select to authenticated using (true);
grant select on core.apps to authenticated;

insert into core.apps (slug, name) values
  ('oshi', '推しノート'),
  ('recipe', 'レシピDB')
on conflict (slug) do nothing;

-- 全アプリ共通のプロフィール（表示名など）。ユーザー登録時に自動作成
create table if not exists core.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  avatar_path text,               -- Storage の core-avatars バケット内のパス
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table core.profiles enable row level security;
create policy "profiles_select_own" on core.profiles for select to authenticated using (id = (select auth.uid()));
create policy "profiles_update_own" on core.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
grant select, update on core.profiles to authenticated;
create trigger profiles_set_updated_at before update on core.profiles
  for each row execute function core.set_updated_at();

-- どのユーザーがどのアプリを使っているか（初回利用時にアプリ側から登録）
create table if not exists core.app_members (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  app_slug text not null references core.apps (slug),
  joined_at timestamptz not null default now(),
  primary key (user_id, app_slug)
);
alter table core.app_members enable row level security;
create policy "members_select_own" on core.app_members for select to authenticated using (user_id = (select auth.uid()));
create policy "members_insert_own" on core.app_members for insert to authenticated with check (user_id = (select auth.uid()));
grant select, insert on core.app_members to authenticated;

-- 新規登録時にプロフィールを作る
create or replace function core.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into core.profiles (id) values (new.id) on conflict do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created_core on auth.users;
create trigger on_auth_user_created_core after insert on auth.users
  for each row execute function core.handle_new_user();

-- 既存ユーザーのプロフィールも作っておく
insert into core.profiles (id) select id from auth.users on conflict do nothing;
