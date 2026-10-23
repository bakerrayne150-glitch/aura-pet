-- Aura Pet — Supabase schema
-- Run with: supabase db push   (or paste into the Supabase SQL editor)
--
-- Mirrors the Firebase layout:
--   users/{uid}  →  profiles + entitlements + usage tables
-- The client may READ its own rows; it can NEVER write billing/usage
-- fields — only the Edge Functions (service role) may.

-- 1) One profile row per auth user. trial_start is the server timestamp
--    of first sighting — this starts the 7-day trial.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  trial_start timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- 2) Subscription entitlement, written ONLY by verify-subscription.
create table public.entitlements (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  status text not null default 'inactive',      -- 'active' | 'inactive'
  product_id text,
  expiry_time_millis bigint not null default 0,
  auto_renewing boolean not null default false,
  verified_at timestamptz
);

-- 3) Per-day message counter for the daily cap (abuse protection).
create table public.usage (
  user_id uuid not null references public.profiles (id) on delete cascade,
  day date not null,
  count int not null default 0,
  primary key (user_id, day)
);

-- Auto-create a profile row the moment a user signs up (anonymous or not).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Atomically increments today's counter and reports whether the user
-- is still under the cap. One statement = no race between check and bump.
create or replace function public.check_and_increment_usage(
  p_user_id uuid,
  p_cap int
)
returns boolean
language plpgsql
security definer set search_path = public
as $$
declare
  v_count int;
begin
  insert into public.usage (user_id, day, count)
  values (p_user_id, current_date, 1)
  on conflict (user_id, day)
  do update set count = public.usage.count + 1
  returning count into v_count;

  return v_count <= p_cap;
end;
$$;

-- Row Level Security: the app reads its own rows, writes nothing.
alter table public.profiles enable row level security;
alter table public.entitlements enable row level security;
alter table public.usage enable row level security;

create policy "Users read their own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users read their own entitlement"
  on public.entitlements for select
  using (auth.uid() = user_id);

create policy "Users read their own usage"
  on public.usage for select
  using (auth.uid() = user_id);

-- No insert/update/delete policies for authenticated users on purpose:
-- only the service role (Edge Functions) can write these tables.
