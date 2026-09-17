-- ============================================================
-- VICOBA OS — Supabase schema (v2)
-- Enforces the same rules as the front-end prototype:
--   * every member belongs to exactly one group
--   * users only see rows belonging to their group
--   * loans require 3 referees + cap = LEAST(3*shares_value, SUM(referee contributions))
--   * Jamii claims: death/illness for member|parent|child|in-law; wedding member only
--   * expenses, audit log, reminders — all group-scoped
-- Idempotent: safe to re-run.
-- ============================================================

create extension if not exists "pgcrypto";

-- ---------- groups ----------
create table if not exists groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  location    text,
  invite_code text not null unique,
  social_balance numeric not null default 0,
  created_at  timestamptz not null default now()
);

-- ---------- settings (per group) ----------
create table if not exists group_settings (
  group_id            uuid primary key references groups(id) on delete cascade,
  weekly_amount       numeric not null default 50000,
  share_value         numeric not null default 75000,
  interest_rate_pct   numeric not null default 10,
  loan_multiplier     int     not null default 3,
  social_monthly      numeric not null default 5000,
  penalty_pct         numeric not null default 2,
  remind_lead_days    int     not null default 3,
  contribution_dow    int     not null default 0,   -- 0=Sunday
  jamii_death_amt     numeric not null default 200000,
  jamii_illness_amt   numeric not null default 150000,
  jamii_wedding_amt   numeric not null default 100000
);

-- ---------- members ----------
create table if not exists members (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references groups(id) on delete cascade,
  member_code  text not null,                       -- e.g. M001
  full_name    text not null,
  phone        text not null unique,
  national_id  text not null,                       -- NIDA
  photo_url    text,
  kin_name     text not null,
  kin_relation text,
  kin_phone    text,
  role         text not null default 'member'
               check (role in ('member','chairperson','secretary','treasurer','auditor','admin')),
  status       text not null default 'active',
  savings      numeric not null default 0,
  shares       int     not null default 0,
  auth_user_id uuid references auth.users(id),      -- set when wiring Supabase Auth
  created_at   timestamptz not null default now(),
  unique (group_id, member_code)
);

-- ---------- contributions / transactions ----------
create table if not exists transactions (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references groups(id) on delete cascade,
  member_id   uuid not null references members(id) on delete cascade,
  txn_code    text not null,                        -- TXN-1001
  kind        text not null check (kind in ('Akiba','Hisa','Mfuko wa Jamii','Dharura ya Jamii')),
  amount      numeric not null check (amount > 0),
  channel     text,                                 -- M-Pesa / Airtel Money / ... (payment integration)
  pay_ref     text,                                 -- PAY-XXXX gateway reference
  tx_date     date not null default current_date,
  created_at  timestamptz not null default now()
);
create index if not exists idx_tx_group_date on transactions (group_id, tx_date desc);

-- ---------- loan applications (3 referees + consent) ----------
create table if not exists loan_applications (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references groups(id) on delete cascade,
  member_id   uuid not null references members(id),
  ref_code    text not null,
  amount      numeric not null check (amount > 0),
  reason      text,
  score       int,
  status      text not null default 'awaiting_referees'
              check (status in ('awaiting_referees','awaiting_approval','approved','rejected')),
  created_at  timestamptz not null default now()
);

create table if not exists loan_referees (
  application_id uuid not null references loan_applications(id) on delete cascade,
  member_id      uuid not null references members(id),
  contribution_snapshot numeric not null default 0,
  consent        text not null default 'pending' check (consent in ('pending','agreed','refused')),
  responded_at   timestamptz,
  primary key (application_id, member_id)
);

-- ---------- loans ----------
-- NOTE: balance defaults to amount via trigger below (Postgres does not allow
-- column references in DEFAULT expressions).
create table if not exists loans (
  id            uuid primary key default gen_random_uuid(),
  group_id      uuid not null references groups(id) on delete cascade,
  member_id     uuid not null references members(id),
  loan_code     text not null,                      -- LN-042
  amount        numeric not null check (amount > 0),
  balance       numeric check (balance >= 0),       -- filled by trg_loans_balance
  interest_pct  numeric not null default 10,
  due_date      date not null,
  penalty_flag  boolean not null default false,
  penalty_amt   numeric not null default 0,
  created_at    timestamptz not null default now()
);
create index if not exists idx_loans_group_due on loans (group_id, due_date);

create or replace function set_loan_balance() returns trigger as $$
begin
  if NEW.balance is null then NEW.balance := NEW.amount; end if;
  return NEW;
end $$ language plpgsql;

drop trigger if exists trg_loans_balance on loans;
create trigger trg_loans_balance before insert on loans
  for each row execute function set_loan_balance();

-- Loan cap rule: amount must not exceed LEAST(3 x shares, referee contributions).
-- Checked when an application moves to 'awaiting_approval' (after all referees
-- have been added — they FK the application, so they cannot exist before it).
create or replace function check_loan_cap() returns trigger as $$
declare
  borrower_shares int;
  share_value numeric;
  multiplier int;
  shares_cap numeric;
  refs_cap numeric;
  n_refs int;
begin
  if NEW.status = 'awaiting_approval' and OLD.status is distinct from 'awaiting_approval' then
    select m.shares into borrower_shares from members m where m.id = NEW.member_id;
    select s.share_value, s.loan_multiplier into share_value, multiplier
      from group_settings s where s.group_id = NEW.group_id;
    shares_cap := coalesce(borrower_shares,0) * coalesce(share_value,75000) * coalesce(multiplier,3);

    select coalesce(sum(r.contribution_snapshot), 0), count(*)
      into refs_cap, n_refs
      from loan_referees r where r.application_id = NEW.id;

    if n_refs < 3 then
      raise exception 'Loan % needs at least 3 referees (has %)', NEW.ref_code, n_refs;
    end if;
    if NEW.amount > least(shares_cap, refs_cap) then
      raise exception 'Loan % exceeds cap: amount > LEAST(%, %)', NEW.ref_code, shares_cap, refs_cap;
    end if;
  end if;
  return NEW;
end $$ language plpgsql;

drop trigger if exists trg_loan_cap on loan_applications;
create trigger trg_loan_cap before update on loan_applications
  for each row execute function check_loan_cap();

-- ---------- repayments ----------
create table if not exists repayments (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references groups(id) on delete cascade,
  member_id   uuid not null references members(id),
  loan_id     uuid not null references loans(id),
  txn_code    text not null,
  amount      numeric not null check (amount > 0),
  interest_part numeric not null default 0,
  channel     text,
  pay_ref     text,
  repaid_on   date not null default current_date
);

-- ---------- Jamii (welfare) claims ----------
create table if not exists jamii_claims (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references groups(id) on delete cascade,
  member_id   uuid not null references members(id),
  ref_code    text not null,
  event_type  text not null check (event_type in ('msiba','ugonjwa','harusi')),
  beneficiary text not null check (beneficiary in ('Mwanachama','Mzazi','Mwana','Mkwe')),
  amount      numeric not null check (amount > 0),
  shortfall   numeric not null default 0,
  note        text,
  status      text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at  timestamptz not null default now(),
  -- wedding is for the member ONLY
  constraint wedding_member_only check (event_type <> 'harusi' or beneficiary = 'Mwanachama')
);

-- ---------- expenses ----------
create table if not exists expenses (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references groups(id) on delete cascade,
  exp_code   text not null,
  category   text not null,          -- Posho ya Mkutano / Utasuluhishi (Grievances) / ...
  description text,
  amount     numeric not null check (amount > 0),
  spent_on   date not null default current_date,
  recorded_by uuid references members(id),
  created_at timestamptz not null default now()
);

-- ---------- membership applications (officer OR 70% vote) ----------
create table if not exists membership_applications (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references groups(id) on delete cascade,
  ref_code     text not null,
  full_name    text not null,
  phone        text not null,
  national_id  text not null,
  photo_url    text,
  kin_name     text not null,
  kin_relation text,
  kin_phone    text,
  invite_code  text not null,
  status       text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at   timestamptz not null default now()
);

create table if not exists membership_votes (
  application_id uuid not null references membership_applications(id) on delete cascade,
  member_id      uuid not null references members(id),
  voted_at       timestamptz not null default now(),
  primary key (application_id, member_id)
);

-- Auto-approve when votes >= 70% of group size (officer approval is a direct update).
create or replace function maybe_auto_approve() returns trigger as $$
declare
  gid uuid; total int; needed int; votes int;
begin
  select group_id into gid from membership_applications where id = NEW.application_id;
  select count(*) into total from members where group_id = gid and status = 'active';
  needed := ceil(total * 0.7);
  select count(*) into votes from membership_votes where application_id = NEW.application_id;
  if votes >= needed then
    update membership_applications set status = 'approved' where id = NEW.application_id;
  end if;
  return NEW;
end $$ language plpgsql;

drop trigger if exists trg_auto_approve on membership_votes;
create trigger trg_auto_approve after insert on membership_votes
  for each row execute function maybe_auto_approve();

-- ---------- reminders / notifications / audit ----------
create table if not exists reminders (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references groups(id) on delete cascade,
  member_id  uuid not null references members(id),
  kind       text not null,   -- loan-due / overdue / contribution / referee-risk
  message    text not null,
  dedupe_key text not null unique,
  sent_at    timestamptz not null default now()
);

create table if not exists notifications (
  id         uuid primary key default gen_random_uuid(),
  group_id   uuid not null references groups(id) on delete cascade,
  member_id  uuid references members(id),
  title      text not null,
  body       text,
  read_at    timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists audit_log (
  id         bigserial primary key,
  group_id   uuid not null references groups(id) on delete cascade,
  actor_id   uuid references members(id),
  actor_role text,
  action     text not null,
  ip         text,
  created_at timestamptz not null default now()
);
-- append-only audit log
drop rule if exists audit_no_update on audit_log;
create rule audit_no_update as on update to audit_log do instead nothing;
drop rule if exists audit_no_delete on audit_log;
create rule audit_no_delete as on delete to audit_log do instead nothing;

-- ============================================================
-- Row Level Security: a signed-in member sees only their group.
-- Assumes auth.uid() maps to members.auth_user_id (Supabase Auth).
-- ============================================================
alter table groups                  enable row level security;
alter table group_settings          enable row level security;
alter table members                 enable row level security;
alter table transactions            enable row level security;
alter table loan_applications       enable row level security;
alter table loan_referees           enable row level security;
alter table loans                   enable row level security;
alter table repayments              enable row level security;
alter table jamii_claims            enable row level security;
alter table expenses                enable row level security;
alter table membership_applications enable row level security;
alter table membership_votes        enable row level security;
alter table reminders               enable row level security;
alter table notifications           enable row level security;
alter table audit_log               enable row level security;

-- helper: the caller's group (NULL = not a member)
create or replace function my_group_id() returns uuid as $$
  select group_id from members where auth_user_id = auth.uid() limit 1;
$$ language sql security definer stable;

-- helper: is the caller a platform admin?
create or replace function is_admin() returns boolean as $$
  select exists (select 1 from members m where m.auth_user_id = auth.uid() and m.role = 'admin');
$$ language sql security definer stable;

-- Example policy set (apply the same pattern to every group-scoped table).
-- All are drop-if-exists first so the script can be re-run safely.
drop policy if exists grp_read_own on groups;
create policy grp_read_own on groups for select
  using (id = my_group_id() or is_admin());

drop policy if exists mem_read_own on members;
create policy mem_read_own on members for select
  using (group_id = my_group_id() or is_admin());

drop policy if exists mem_write_own on members;
create policy mem_write_own on members for all
  using (group_id = my_group_id()) with check (group_id = my_group_id());

drop policy if exists tx_group on transactions;
create policy tx_group on transactions for all
  using (group_id = my_group_id()) with check (group_id = my_group_id());

drop policy if exists loans_group on loans;
create policy loans_group on loans for all
  using (group_id = my_group_id()) with check (group_id = my_group_id());

drop policy if exists jamii_group on jamii_claims;
create policy jamii_group on jamii_claims for all
  using (group_id = my_group_id()) with check (group_id = my_group_id());

drop policy if exists exp_group on expenses;
create policy exp_group on expenses for all
  using (group_id = my_group_id()) with check (group_id = my_group_id());

drop policy if exists audit_read on audit_log;
create policy audit_read on audit_log for select
  using (group_id = my_group_id() or is_admin());

drop policy if exists notif_group on notifications;
create policy notif_group on notifications for all
  using (group_id = my_group_id()) with check (group_id = my_group_id());
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
