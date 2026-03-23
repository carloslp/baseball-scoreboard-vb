-- Enable UUID extension
create extension if not exists "pgcrypto";

-- Matches table
create table public.matches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) not null,
  user_obs_token text not null,
  home_team_name text not null default 'HOME',
  home_team_color text not null default '#1a73e8',
  away_team_name text not null default 'AWAY',
  away_team_color text not null default '#e53935',
  home_score integer not null default 0,
  away_score integer not null default 0,
  inning integer not null default 1,
  inning_half text not null default 'top',
  balls integer not null default 0,
  strikes integer not null default 0,
  outs integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Enable RLS
alter table public.matches enable row level security;

-- RLS Policies
create policy "Users can view own matches"
  on public.matches for select
  using (auth.uid() = user_id);

create policy "Users can insert own matches"
  on public.matches for insert
  with check (auth.uid() = user_id);

create policy "Users can update own matches"
  on public.matches for update
  using (auth.uid() = user_id);

-- Public read access is intentional: the OBS overlay needs unauthenticated access
-- to match data by token. Tokens are random 32-character hex strings, making them
-- effectively unguessable. Realtime subscriptions also require this policy.
create policy "Public can view match by obs token"
  on public.matches for select
  using (true);

create or replace function get_active_match_by_token(p_token text)
returns setof public.matches
language sql
security definer
as $$
  select * from public.matches
  where user_obs_token = p_token
    and is_active = true
  limit 1;
$$;
