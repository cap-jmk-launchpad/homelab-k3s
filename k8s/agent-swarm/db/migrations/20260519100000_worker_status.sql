-- Worker heartbeat + materialized work queue for read-only dashboard API.

create table if not exists public.worker_status (
  id integer primary key default 1 check (id = 1),
  supervisor_loop_running boolean not null default false,
  async_swarm_running boolean not null default false,
  research_lane_running boolean not null default false,
  implement_lane_running boolean not null default false,
  maintenance_lane_running boolean not null default false,
  agent_backend text,
  sdk_ready boolean not null default false,
  sdk_max_concurrent integer,
  sdk_sessions_active integer,
  active_runs jsonb not null default '[]'::jsonb,
  handoff_run jsonb,
  last_tick_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.worker_status enable row level security;
create policy "service_all_worker_status" on public.worker_status for all using (true) with check (true);

create table if not exists public.work_queue_snapshots (
  briefing_hash text primary key,
  payload jsonb not null,
  generated_at timestamptz not null default now()
);

create index if not exists work_queue_snapshots_generated_idx on public.work_queue_snapshots (generated_at desc);

alter table public.work_queue_snapshots enable row level security;
create policy "service_all_work_queue_snapshots" on public.work_queue_snapshots for all using (true) with check (true);
