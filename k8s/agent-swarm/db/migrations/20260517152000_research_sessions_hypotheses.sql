-- research_sessions.hypotheses — required by session-store.ts (research lane)

alter table public.research_sessions
  add column if not exists hypotheses jsonb not null default '[]'::jsonb;

comment on column public.research_sessions.hypotheses is
  'Tested ideas with status proposed|testing|verified|falsified|deferred';
