-- レシピDB: 献立カレンダー
-- 1行 = ある日のある食事（朝・昼・夜・間食）の1品。1食に主菜・副菜・汁物など何品でも並べられる。

create table recipe.meal_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  planned_on date not null,
  meal text not null check (meal in ('breakfast','lunch','dinner','snack')),
  position smallint not null default 0,          -- 同じ食事の中での並び順
  recipe_id uuid references recipe.recipes (id) on delete set null,
  title text not null,                           -- 料理名。レシピから選んだときはその名前を写す（外食・残り物などは自由入力）
  note text,
  status text not null default 'planned' check (status in ('planned','cooked','skipped')),  -- 予定・作った・やめた
  cook_log_id uuid references recipe.cook_logs (id) on delete set null,                      -- 「作った」で作られた調理記録
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on recipe.meal_plans (user_id, planned_on);
create index on recipe.meal_plans (recipe_id);

alter table recipe.meal_plans enable row level security;
grant select, insert, update, delete on recipe.meal_plans to authenticated;
-- 自分の行だけ。つなぐレシピと調理記録も自分のものに限る
create policy "meal_plans_own" on recipe.meal_plans for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and (recipe_id is null or exists (select 1 from recipe.recipes r where r.id = recipe_id and r.user_id = (select auth.uid())))
    and (cook_log_id is null or exists (select 1 from recipe.cook_logs l where l.id = cook_log_id and l.user_id = (select auth.uid())))
  );

create trigger meal_plans_set_updated_at before update on recipe.meal_plans
  for each row execute function core.set_updated_at();
