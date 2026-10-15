-- レシピDB: recipe スキーマ

create schema if not exists recipe;
grant usage on schema recipe to authenticated;
create extension if not exists pg_trgm with schema extensions;

-- レシピ本体
create table recipe.recipes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title text not null,
  description text,
  category text not null default 'main'
    check (category in ('main','side','soup','rice_noodle','salad','dessert','drink','bento','other')),
  cuisine text check (cuisine in ('japanese','western','chinese','korean','ethnic','other')),
  difficulty smallint not null default 2 check (difficulty between 1 and 5),
  servings smallint,
  prep_min smallint,
  cook_min smallint,
  -- 味の傾向（0〜5）
  taste_sweet smallint not null default 0 check (taste_sweet between 0 and 5),
  taste_salty smallint not null default 0 check (taste_salty between 0 and 5),
  taste_sour  smallint not null default 0 check (taste_sour  between 0 and 5),
  taste_spicy smallint not null default 0 check (taste_spicy between 0 and 5),
  taste_umami smallint not null default 0 check (taste_umami between 0 and 5),
  taste_rich  smallint not null default 0 check (taste_rich  between 0 and 5),  -- こってり度
  -- いつ作るか
  seasons    text[] not null default '{}' check (seasons    <@ array['spring','summer','autumn','winter']),
  weathers   text[] not null default '{}' check (weathers   <@ array['sunny','cloudy','rainy','snowy','hot','cold']),
  situations text[] not null default '{}',   -- 'weeknight','party','bento','tired','hangover','date' など自由
  tags       text[] not null default '{}',
  tips text,                    -- 注意点・コツ
  source_url text,
  photo_path text,              -- Storage: recipe-photos/{user_id}/...
  is_favorite boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on recipe.recipes (user_id, updated_at desc);
create index on recipe.recipes using gin (seasons);
create index on recipe.recipes using gin (situations);
create index on recipe.recipes using gin (title extensions.gin_trgm_ops);

-- 材料
create table recipe.ingredients (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references recipe.recipes (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  position smallint not null,
  group_label text,             -- 「A」「タレ」など
  name text not null,
  amount text,                  -- 「大さじ1」「200」「少々」
  unit text,
  note text
);
create index on recipe.ingredients (recipe_id, position);
create index on recipe.ingredients using gin (name extensions.gin_trgm_ops);  -- 冷蔵庫の残り物から探す用

-- 作り方の手順
create table recipe.steps (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references recipe.recipes (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  position smallint not null,
  body text not null,
  timer_sec integer,            -- 手順ごとのタイマー
  caution text                  -- この手順の注意点
);
create index on recipe.steps (recipe_id, position);

-- 作った記録（熟練度・傾向分析の元データ）
create table recipe.cook_logs (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references recipe.recipes (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  cooked_on date not null default current_date,
  rating smallint check (rating between 1 and 5),          -- 出来ばえ
  took_min smallint,                                       -- 実際にかかった時間
  changes text,                                            -- アレンジ・変えたこと
  reflection text,                                         -- 反省・次回やること
  mood text,                                               -- 作ったときの気分
  weather jsonb,                                           -- {"code":"rainy","temp":14}
  photo_path text,
  created_at timestamptz not null default now()
);
create index on recipe.cook_logs (user_id, cooked_on desc);
create index on recipe.cook_logs (recipe_id, cooked_on desc);

-- AIの「今日のおすすめ」履歴（どれを選んだかも学習に使う）
create table recipe.ai_picks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  context jsonb not null,       -- 天気・気分・食べたい種類・冷蔵庫の材料
  picks jsonb not null,         -- [{recipe_id, reason}]
  chosen_recipe_id uuid references recipe.recipes (id) on delete set null,
  model text,
  created_at timestamptz not null default now()
);

-- AIの傾向分析（週次・月次）
create table recipe.ai_insights (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  period_start date not null,
  period_end date not null,
  summary text not null,
  details jsonb not null default '{}',   -- 得意ジャンル、よく使う材料、癖、次の挑戦
  model text,
  created_at timestamptz not null default now()
);

-- 熟練度（作った記録から自動計算）
create view recipe.recipe_stats with (security_invoker = true) as
select
  r.id as recipe_id,
  r.user_id,
  count(l.id)::int as cook_count,
  round(avg(l.rating), 1) as avg_rating,
  max(l.cooked_on) as last_cooked_on,
  case
    when count(l.id) = 0 then 'untried'                                   -- 未挑戦
    when count(l.id) >= 10 and avg(l.rating) >= 4.5 then 'signature'      -- 十八番
    when count(l.id) >= 5  and avg(l.rating) >= 4   then 'confident'      -- 得意
    when count(l.id) >= 2 then 'practicing'                               -- 練習中
    else 'first'                                                          -- 初挑戦
  end as mastery
from recipe.recipes r
left join recipe.cook_logs l on l.recipe_id = r.id
group by r.id, r.user_id;

-- RLS: すべて「自分の行だけ」
do $$
declare t text;
begin
  foreach t in array array['recipes','ingredients','steps','cook_logs','ai_picks','ai_insights'] loop
    execute format('alter table recipe.%I enable row level security', t);
    execute format('grant select, insert, update, delete on recipe.%I to authenticated', t);
  end loop;
  foreach t in array array['recipes','ai_picks','ai_insights'] loop
    execute format('create policy "%1$s_own" on recipe.%1$I for all to authenticated
                    using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
  end loop;
  -- 子テーブルは「自分の行」かつ「自分のレシピにぶら下がる」ときだけ書ける
  foreach t in array array['ingredients','steps','cook_logs'] loop
    execute format('create policy "%1$s_own" on recipe.%1$I for all to authenticated
                    using (user_id = (select auth.uid()))
                    with check (user_id = (select auth.uid()) and exists (
                      select 1 from recipe.recipes r where r.id = recipe_id and r.user_id = (select auth.uid())))', t);
  end loop;
end $$;
grant select on recipe.recipe_stats to authenticated;

create trigger recipes_set_updated_at before update on recipe.recipes
  for each row execute function core.set_updated_at();

-- 写真用バケット（パスの先頭フォルダ = 自分の user_id のときだけ読み書き可）
insert into storage.buckets (id, name, public) values ('recipe-photos', 'recipe-photos', false)
on conflict (id) do nothing;
create policy "recipe_photos_own" on storage.objects for all to authenticated
  using (bucket_id = 'recipe-photos' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'recipe-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
