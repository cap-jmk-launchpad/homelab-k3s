-- Dashboard hot-path indexes + queue row shape for indexed reads (no full-table scans).

alter table public.queued_agent_tasks
  add column if not exists priority integer not null default 50,
  add column if not exists status text not null default 'pending',
  add column if not exists meta jsonb;

create index if not exists queued_agent_tasks_briefing_priority_idx
  on public.queued_agent_tasks (briefing_hash, priority desc, agent_id);

-- Active research sessions (batch load for full queue build; avoids N+1 per goal).
create index if not exists research_sessions_in_progress_updated_idx
  on public.research_sessions (updated_at desc)
  where
    status = 'in_progress';

-- Activity / recent runs (exclude mock backend without scanning output_md).
create index if not exists agent_runs_started_prod_idx
  on public.agent_runs (started_at desc)
  where
    backend is distinct from 'mock';
