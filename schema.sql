-- 釉料配方计算器 — Supabase schema
-- 在 Supabase 项目的 SQL Editor 里整段执行一次即可。

-- ── notebook_entries ──
create table public.notebook_entries (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade default auth.uid(),
  num              text,
  name             text not null,
  note             text default '',
  base_ingredients jsonb not null default '[]'::jsonb,   -- [{name, parts}]
  base_dry         numeric not null default 0,
  base_water       numeric not null default 0,
  glazes           jsonb not null default '[]'::jsonb,   -- [{name, sourceIndex, sourceAmount, amountUnknown, additives:[{name,amount}]}]
  additives        jsonb not null default '{}'::jsonb,   -- {name: pct}
  photos           jsonb not null default '[]'::jsonb,   -- [{path, caption}]
  legacy_id        bigint,                                -- 旧版 Date.now() id，仅用于导入去重
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index notebook_entries_user_id_idx on public.notebook_entries(user_id);
create unique index notebook_entries_legacy_id_uidx on public.notebook_entries(user_id, legacy_id) where legacy_id is not null;

-- ── favourites ──
create table public.favourites (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade default auth.uid(),
  type             text not null check (type in ('base','additive')),
  name             text not null,
  note             text default '',
  glaze_name       text,
  base_ingredients jsonb not null default '[]'::jsonb,
  base_dry         numeric not null default 0,
  base_water       numeric not null default 0,
  additives        jsonb not null default '{}'::jsonb,   -- {name: absolute_grams}
  photos           jsonb not null default '[]'::jsonb,
  legacy_id        bigint,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index favourites_user_id_idx on public.favourites(user_id);
create unique index favourites_legacy_id_uidx on public.favourites(user_id, legacy_id) where legacy_id is not null;

-- ── history_entries ── (无图片，每用户自动只保留最近 50 条)
create table public.history_entries (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade default auth.uid(),
  base_ingredients jsonb not null default '[]'::jsonb,
  base_dry     numeric not null default 0,
  base_water   numeric not null default 0,
  glazes       jsonb not null default '[]'::jsonb,
  glaze_states jsonb not null default '[]'::jsonb,       -- [{baseDry, additiveTotals}]
  created_at   timestamptz not null default now()
);
create index history_entries_user_id_idx on public.history_entries(user_id);

-- ── materials（原料化学成分库，Seger 式分析用；每用户各自维护一份）──
create table public.materials (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade default auth.uid(),
  name       text not null,
  aliases    jsonb not null default '[]'::jsonb,           -- [alias, ...]
  role       text not null default 'base'
             check (role in ('base','colorant','opacifier','surface')),
  oxides     jsonb not null default '{}'::jsonb,           -- {SiO2: 67.5, ...} 原料重量的百分比（不含 LOI）
  loi        numeric not null default 0,                    -- 烧失量百分比；oxides 各项 + loi 应约等于 100
  source     text not null default 'typical'
             check (source in ('typical','supplier','user')),
  verified   boolean not null default false,
  note       text default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index materials_user_id_idx on public.materials(user_id);
create unique index materials_user_name_uidx on public.materials(user_id, name);

-- ── firing_curves（烧成曲线，独立可复用实体；每用户各自维护一份）──
create table public.firing_curves (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade default auth.uid(),
  name         text not null,
  note         text default '',
  segments     jsonb not null default '[]'::jsonb,  -- [{minutes,targetTemp,rate,type?,label?}]
  start_temp   numeric not null default 30,
  total_minutes numeric,
  peak_temp    numeric,
  atmosphere   text default '氧化',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index firing_curves_user_id_idx on public.firing_curves(user_id);
create unique index firing_curves_user_name_uidx on public.firing_curves(user_id, name);

-- ── notebook_entries 追加：关联烧成曲线 + 数据可信度（反向校准用）──
alter table public.notebook_entries add column if not exists firing_curve_id uuid references public.firing_curves(id) on delete set null;
alter table public.notebook_entries add column if not exists peak_temp_override numeric;
alter table public.notebook_entries add column if not exists data_confidence text not null default '可靠'
  check (data_confidence in ('可靠','估算','污染','无法计算'));
alter table public.notebook_entries add column if not exists effect_tags jsonb not null default '[]'::jsonb; -- ['亮光','哑光','结晶','开裂','流动',...]

-- ── RLS：每个人只能读写自己的行 ──
alter table public.notebook_entries enable row level security;
alter table public.favourites        enable row level security;
alter table public.history_entries   enable row level security;
alter table public.materials         enable row level security;
alter table public.firing_curves     enable row level security;

create policy "nb select own"  on public.notebook_entries for select using (auth.uid() = user_id);
create policy "nb insert own"  on public.notebook_entries for insert with check (auth.uid() = user_id);
create policy "nb update own"  on public.notebook_entries for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "nb delete own"  on public.notebook_entries for delete using (auth.uid() = user_id);

create policy "fav select own" on public.favourites for select using (auth.uid() = user_id);
create policy "fav insert own" on public.favourites for insert with check (auth.uid() = user_id);
create policy "fav update own" on public.favourites for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "fav delete own" on public.favourites for delete using (auth.uid() = user_id);

create policy "hist select own" on public.history_entries for select using (auth.uid() = user_id);
create policy "hist insert own" on public.history_entries for insert with check (auth.uid() = user_id);
create policy "hist delete own" on public.history_entries for delete using (auth.uid() = user_id);
-- history 没有 update 策略：记录写入后不再修改

create policy "mat select own" on public.materials for select using (auth.uid() = user_id);
create policy "mat insert own" on public.materials for insert with check (auth.uid() = user_id);
create policy "mat update own" on public.materials for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "mat delete own" on public.materials for delete using (auth.uid() = user_id);

create policy "fc select own" on public.firing_curves for select using (auth.uid() = user_id);
create policy "fc insert own" on public.firing_curves for insert with check (auth.uid() = user_id);
create policy "fc update own" on public.firing_curves for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "fc delete own" on public.firing_curves for delete using (auth.uid() = user_id);

-- ── 每用户历史记录只保留最近 50 条（对应旧版客户端 history.slice(0,50)）──
create or replace function public.trim_history() returns trigger
language plpgsql security definer as $$
begin
  delete from public.history_entries
  where user_id = new.user_id
    and id not in (
      select id from public.history_entries
      where user_id = new.user_id
      order by created_at desc
      limit 50
    );
  return new;
end;
$$;
create trigger history_trim_after_insert
after insert on public.history_entries
for each row execute function public.trim_history();

-- ── updated_at 自动维护 ──
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;
create trigger notebook_set_updated_at before update on public.notebook_entries
  for each row execute function public.set_updated_at();
create trigger favourites_set_updated_at before update on public.favourites
  for each row execute function public.set_updated_at();
create trigger materials_set_updated_at before update on public.materials
  for each row execute function public.set_updated_at();
create trigger firing_curves_set_updated_at before update on public.firing_curves
  for each row execute function public.set_updated_at();

-- ── Storage：私有 bucket + 按 user_id 分文件夹隔离 ──
insert into storage.buckets (id, name, public) values ('glaze-photos', 'glaze-photos', false);

create policy "photos select own" on storage.objects for select
  using (bucket_id = 'glaze-photos' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "photos insert own" on storage.objects for insert
  with check (bucket_id = 'glaze-photos' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "photos update own" on storage.objects for update
  using (bucket_id = 'glaze-photos' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "photos delete own" on storage.objects for delete
  using (bucket_id = 'glaze-photos' and auth.uid()::text = (storage.foldername(name))[1]);

-- 路径约定：{user_id}/notebook/{record_id}/{uuid}.jpg
--        或 {user_id}/favourites/{record_id}/{uuid}.jpg
