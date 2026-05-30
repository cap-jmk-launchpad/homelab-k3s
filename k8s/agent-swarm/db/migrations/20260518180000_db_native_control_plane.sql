-- Native dashboard + Next.js: lane/settings in DB; latest briefing pointer for indexed reads.

create table if not exists public.lane_state (
  id integer primary key default 1 check (id = 1),
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.lane_state enable row level security;
create policy "service_all_lane_state" on public.lane_state for all using (true) with check (true);

create table if not exists public.runtime_settings (
  id integer primary key default 1 check (id = 1),
  values jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.runtime_settings enable row level security;
create policy "service_all_runtime_settings" on public.runtime_settings for all using (true) with check (true);

alter table public.briefing_snapshots
  add column if not exists is_latest boolean not null default false;

create unique index if not exists briefing_snapshots_latest_idx on public.briefing_snapshots (is_latest)
where
  is_latest;

create index if not exists briefing_snapshots_generated_idx on public.briefing_snapshots (generated_at desc);

create table if not exists public.supervisor_activity (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  level text not null default 'info',
  message text not null,
  meta jsonb
);

create index if not exists supervisor_activity_at_idx on public.supervisor_activity (at desc);

alter table public.supervisor_activity enable row level security;
create policy "service_all_supervisor_activity" on public.supervisor_activity for all using (true) with check (true);
