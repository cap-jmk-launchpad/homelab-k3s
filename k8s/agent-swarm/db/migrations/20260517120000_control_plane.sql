-- Li cursor-agents control plane (local Supabase)
-- Run: supabase db reset (local) or supabase migration up

create extension if not exists "pgcrypto";

-- Agent runs (Cursor-style history)
create table public.agent_runs (
  run_id text primary key,
  agent_id text not null,
  started_at timestamptz not null,
  finished_at timestamptz,
  status text not null,
  backend text,
  briefing_hash text,
  reason text,
  fingerprint text,
  coordinator text,
  duration_ms integer,
  output_md text,
  output_path text,
  error text,
  completion jsonb,
  pr_urls jsonb not null default '[]'::jsonb,
  deliverables jsonb,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index agent_runs_agent_started_idx on public.agent_runs (agent_id, started_at desc);
create index agent_runs_started_idx on public.agent_runs (started_at desc);

-- Optional streaming / timeline events per run
create table public.agent_run_events (
  id bigint generated always as identity primary key,
  run_id text not null references public.agent_runs (run_id) on delete cascade,
  seq integer not null,
  event_type text not null,
  payload jsonb,
  created_at timestamptz not null default now()
);

create index agent_run_events_run_seq_idx on public.agent_run_events (run_id, seq);

-- Singleton control-plane state (mirrors state.json)
create table public.control_plane_state (
  id integer primary key default 1 check (id = 1),
  version integer not null default 1,
  payload jsonb not null,
  updated_at timestamptz not null default now()
);

-- Latest + historical control-plane reports
create table public.control_plane_reports (
  id uuid primary key default gen_random_uuid (),
  generated_at timestamptz not null,
  briefing_hash text not null,
  payload jsonb not null,
  is_latest boolean not null default false
);

create unique index control_plane_reports_latest_idx on public.control_plane_reports (is_latest)
where
  is_latest;

create index control_plane_reports_generated_idx on public.control_plane_reports (generated_at desc);

-- Intervention snapshots
create table public.interventions_snapshots (
  id uuid primary key default gen_random_uuid (),
  generated_at timestamptz not null,
  briefing_hash text,
  items jsonb not null default '[]'::jsonb
);

create index interventions_snapshots_generated_idx on public.interventions_snapshots (generated_at desc);

-- Briefing payloads (by hash)
create table public.briefing_snapshots (
  briefing_hash text primary key,
  generated_at timestamptz not null,
  source_path text,
  payload jsonb
);

-- Heap plans per briefing
create table public.heap_plan_snapshots (
  briefing_hash text primary key,
  generated_at timestamptz not null,
  payload jsonb not null
);

-- Repo workflow rollout rows (agent-kit, etc.)
create table public.repo_workflow_rollouts (
  id uuid primary key default gen_random_uuid (),
  run_id text references public.agent_runs (run_id) on delete set null,
  rollout_kind text not null default 'agent_kit',
  repo text not null,
  install_ok boolean,
  workflow_ok boolean,
  pr_url text,
  skipped boolean,
  skip_reason text,
  governance boolean,
  error text,
  workspace text,
  created_at timestamptz not null default now()
);

create index repo_workflow_rollouts_run_idx on public.repo_workflow_rollouts (run_id);

-- Queued / heap tasks from last report (denormalized for dashboard)
create table public.queued_agent_tasks (
  id uuid primary key default gen_random_uuid (),
  briefing_hash text not null,
  fingerprint text not null,
  agent_id text not null,
  reason text not null,
  source text,
  coordinator text,
  created_at timestamptz not null default now(),
  unique (briefing_hash, fingerprint)
);

create index queued_agent_tasks_briefing_idx on public.queued_agent_tasks (briefing_hash);

-- Local dev: allow service role full access (no RLS)
alter table public.agent_runs enable row level security;
alter table public.agent_run_events enable row level security;
alter table public.control_plane_state enable row level security;
alter table public.control_plane_reports enable row level security;
alter table public.interventions_snapshots enable row level security;
alter table public.briefing_snapshots enable row level security;
alter table public.heap_plan_snapshots enable row level security;
alter table public.repo_workflow_rollouts enable row level security;
alter table public.queued_agent_tasks enable row level security;

create policy "service_all_agent_runs" on public.agent_runs for all using (true) with check (true);
create policy "service_all_agent_run_events" on public.agent_run_events for all using (true) with check (true);
create policy "service_all_control_plane_state" on public.control_plane_state for all using (true) with check (true);
create policy "service_all_control_plane_reports" on public.control_plane_reports for all using (true) with check (true);
create policy "service_all_interventions" on public.interventions_snapshots for all using (true) with check (true);
create policy "service_all_briefing" on public.briefing_snapshots for all using (true) with check (true);
create policy "service_all_heap" on public.heap_plan_snapshots for all using (true) with check (true);
create policy "service_all_rollouts" on public.repo_workflow_rollouts for all using (true) with check (true);
create policy "service_all_queued" on public.queued_agent_tasks for all using (true) with check (true);
