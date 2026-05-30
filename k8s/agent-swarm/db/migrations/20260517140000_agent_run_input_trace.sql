-- Full agent run input (prompts) and execution trace (thinking, tools, edits)

alter table public.agent_runs
  add column if not exists run_input jsonb,
  add column if not exists run_trace jsonb;

comment on column public.agent_runs.run_input is 'Exact system/user prompts and preflight context';
comment on column public.agent_runs.run_trace is 'Thinking, tool steps, file edits, streamed deltas';
