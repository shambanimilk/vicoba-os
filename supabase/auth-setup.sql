-- ============================================================
-- VICOBA OS — auth setup (run once in SQL Editor)
-- 1) app_state: only signed-in users can read/write the sync doc
-- 2) membership_applications: public (anon) can APPLY;
--    signed-in members can read + process applications
-- ============================================================

-- 1) lock the demo state document behind authentication
drop policy if exists app_state_demo on app_state;
drop policy if exists app_state_auth on app_state;
create policy app_state_auth on app_state
  for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

-- 2) public join funnel (normalized table)
alter table membership_applications enable row level security;

drop policy if exists memapp_insert on membership_applications;
create policy memapp_insert on membership_applications
  for insert to anon, authenticated with check (true);

drop policy if exists memapp_read on membership_applications;
create policy memapp_read on membership_applications
  for select to authenticated using (true);

drop policy if exists memapp_del on membership_applications;
create policy memapp_del on membership_applications
  for delete to authenticated using (true);
