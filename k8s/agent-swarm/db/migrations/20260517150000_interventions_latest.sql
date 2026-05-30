-- Single-row live interventions (recomputed from fresh briefing, not supervisor snapshot only).
create table if not exists public.interventions_latest (
  id int primary key default 1 check (id = 1),
  generated_at timestamptz not null,
  briefing_hash text,
  briefing_generated_at timestamptz,
  items jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.interventions_latest enable row level security;

create policy "service_all_interventions_latest" on public.interventions_latest for all using (true) with check (true);
