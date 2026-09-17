-- ============================================================
-- VICOBA OS — demo cloud-sync table
-- Stores the whole app state as one JSON document so the demo
-- syncs across devices (local app + GitHub Pages deployment).
-- Production moves to the normalized schema + Supabase Auth
-- (see schema.sql and docs/payments-integration-spec.md).
-- ============================================================

create table if not exists app_state (
  id         text primary key,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);

alter table app_state enable row level security;

drop policy if exists app_state_demo on app_state;
-- DEMO ONLY: open access via the anon key. Replace with authenticated
-- policies (like those in schema.sql) before real production use.
create policy app_state_demo on app_state for all using (true) with check (true);
