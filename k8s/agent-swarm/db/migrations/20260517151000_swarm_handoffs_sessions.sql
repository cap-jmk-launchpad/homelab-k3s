-- Swarm handoffs + research sessions (database-first control plane)
-- Renamed from 20260517150000 — that version was taken by interventions_latest.

create table public.research_sessions (
  session_id text primary key,
  agent_id text not null,
  goal_id text,
  cycle integer not null default 1,
  status text not null default 'in_progress',
  current_focus jsonb,
  queue jsonb not null default '[]'::jsonb,
  completed_steps jsonb not null default '[]'::jsonb,
  artifacts jsonb,
  connections jsonb not null default '[]'::jsonb,
  deferred_findings jsonb not null default '[]'::jsonb,
  last_run_id text references public.agent_runs (run_id) on delete set null,
  last_run_status text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index research_sessions_agent_status_idx on public.research_sessions (agent_id, status);

create table public.research_session_steps (
  id bigint generated always as identity primary key,
  session_id text not null references public.research_sessions (session_id) on delete cascade,
  step_id text not null,
  kind text,
  target text,
  summary text,
  artifact_path text,
  created_at timestamptz not null default now()
);

create index research_session_steps_session_idx on public.research_session_steps (session_id, created_at);

create table public.agent_handoffs (
  handoff_id uuid primary key default gen_random_uuid (),
  research_goal_id text,
  from_agent text not null,
  to_agents jsonb not null default '[]'::jsonb,
  status text not null default 'pending_placement',
  domains jsonb,
  north_star_fit text,
  package_placement jsonb,
  work jsonb not null default '{}'::jsonb,
  research_session_id text references public.research_sessions (session_id) on delete set null,
  briefing_hash text,
  source_run_id text references public.agent_runs (run_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  claimed_at timestamptz,
  completed_at timestamptz
);

create index agent_handoffs_status_created_idx on public.agent_handoffs (status, created_at);
create index agent_handoffs_to_agents_gin on public.agent_handoffs using gin (to_agents);

alter table public.research_sessions enable row level security;
alter table public.research_session_steps enable row level security;
alter table public.agent_handoffs enable row level security;
