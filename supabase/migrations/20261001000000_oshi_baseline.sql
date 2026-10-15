-- 推しノートの最初のテーブル（もともと uchinooshi-app の 0001_oshis.sql を SQL Editor で手動適用していたもの）。
-- 本番にはすでにあるので、何度流しても同じ結果になるように書いてある。次のマイグレーションで oshi スキーマへ移動する。
create table if not exists public.oshis (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists oshis_user_id_idx on public.oshis (user_id);

alter table public.oshis enable row level security;

drop policy if exists "oshis_select_own" on public.oshis;
drop policy if exists "oshis_insert_own" on public.oshis;
drop policy if exists "oshis_update_own" on public.oshis;
drop policy if exists "oshis_delete_own" on public.oshis;
create policy "oshis_select_own" on public.oshis
  for select to authenticated using (user_id = (select auth.uid()));
create policy "oshis_insert_own" on public.oshis
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "oshis_update_own" on public.oshis
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "oshis_delete_own" on public.oshis
  for delete to authenticated using (user_id = (select auth.uid()));

create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists oshis_set_updated_at on public.oshis;
create trigger oshis_set_updated_at before update on public.oshis
  for each row execute function public.set_updated_at();
