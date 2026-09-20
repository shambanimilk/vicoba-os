# VICOBA OS

Mfumo kamili wa kifedha kwa VICOBA, Vikoba, SACCOS na MFIs za Tanzania — a complete
community-finance operating system for Tanzanian savings & loan groups.

Single-file web app (`index.html`) — no build step. Open it in any browser.

## Features

- **Any-network contributions (M-Koba differentiator)** — pay via M-Pesa, Mixx by Yas,
  Airtel Money, HaloPesa, bank, or card; every transaction carries the member ID,
  network, and payment reference (simulated gateway — see `docs/payments-integration-spec.md`).
- **Group isolation (multi-tenancy)** — every member belongs to one group; members,
  loans, statistics, notifications, and reports are scoped to the signed-in group only.
  Super Admin can switch between groups.
- **Sign-in required for loans** — a member borrows only from their own group, with
  **3 referees from the same group** and a hard cap:
  `min(3 × shares value, referees' combined contributions)`.
- **Referee consent workflow** — all 3 referees must agree before leaders review;
  one refusal cancels the application.
- **Referee risk alerts** — guarantors are notified with their projected loss
  if the borrower keeps paying at the current pace.
- **Full member registration** — passport photo, valid phone, National ID (NIDA),
  full name, and next of kin, enforced on both admin and invite join forms.
- **Invite-based joining** — groups have invite codes / links; applicants are approved
  by an officer (chair/secretary/treasurer) **or** a vote of 70% of members.
- **Mfuko wa Jamii (welfare fund)** — claims for death and critical illness
  (member, parents, children, in-laws) and member's own wedding only;
  emergency ("dharura") contributions cover fund shortfalls.
- **Expense recording** — meeting allowances, grievance costs, etc., all audited
  and reflected in accounting & reports.
- **Smart reminders** — due-date and contribution reminders with penalty warnings
  (simulated SMS outbox).
- **PDF reports**, **audit log**, **loan estimate & contribution-trend cards** on the
  member dashboard.

## Group constitution (rules)

Every group adopts rules at creation — the general VICOBA OS preset or fully
custom: share price, min/max shares per month, monthly contribution deadline,
loan interest, late-hisa fine, late-repayment fine (with daily/weekly/monthly
accrual on the outstanding balance), meeting-absence penalty, profit split
(e.g. 50% of member-generated profit returns to the member, 50% to the pool
shared pro-rata by shares), exit fee and payout delay, and mobile-money
transaction charges. Adopted rules are permanent: leaders draft changes, and
**more than 70% of members must vote yes** for them to take effect. Meeting
date/location (online or physical) changes monthly without a vote.

## Member estimates, fines & kikoba period

Dashboards show the group's age ("Mwezi wa N — kuanzia <date>"), and every
member sees **Makadirio Yangu**: estimated profit (interest + fines they
generated × their share %, plus their pro-rata pool share) and net
contributions (akiba + hisa + Jamii − transaction charges − allocated group
expenses). Late-repayment fines accrue per the chosen period; missing the
monthly contribution deadline or an unexcused meeting absence triggers the
group's fines automatically. Members submit absence excuses via the in-app
**Fomu ya Samahani** (meeting, party, funeral, wedding, other); leaders accept
or mark unexcused, applying the penalty.

## How membership works

1. **Anyone registers** on the platform ("Jisajili"): 3 full names, phone, PIN (6+),
   passport photo, NIDA, and next of kin.
2. **Groups are invite-only**: an existing member invites by phone (or shares the
   group's invite-code link); the invited person completes the application in their app.
3. **Acceptance**: any of the 3 leaders (Mwenyekiti / Katibu / Mhasibu) approves,
   **or** 70% of members vote yes.
4. **Anyone can create a group** — the creator becomes its first Mwenyekiti.
5. **Member IDs**: 2 letters of the group name + 2 random digits + 3 name initials
   (e.g. `UM74JAM` = Umoja + Juma Ali Mwalimu).

## Leadership & elections (Uchaguzi)

Every group elects a **Mwenyekiti** (chairman), **Katibu** (secretary), and
**Mhasibu** (accountant); **Mkaguzi** (auditor) is an optional elected title.
Leaders can appoint assistants (Naibu) directly. Everyone else is **Mjumbe**.
Leaders start elections; each member casts one vote; most votes wins
(a tie re-opens voting).

## Demo sign-ins (phone + PIN `123456`)

Real Supabase Auth accounts are created lazily on first sign-in. Officers can
change their PIN in Settings.

| Role | Phone | Group |
|---|---|---|
| Super Admin | +255700000001 | all (switcher) |
| Mwenyekiti (chair) | +255713456789 | Umoja wa Wanawake |
| Mweka Hazina (treasurer) | +255715678901 | Umoja wa Wanawake |
| Katibu (secretary) | +255712345678 | Umoja wa Wanawake |
| Mkaguzi (auditor) | +255714567890 | Umoja wa Wanawake |
| Mwanachama (member) | +255716789012 | Vijana Nguvu |

Or use the demo role buttons on the login page. Join a group with invite code
`UMOJA-7K2Q` or open `index.html#invite=UMOJA-7K2Q` (the join form creates the
applicant's account and files a row in the `membership_applications` table).

## Run locally

```bash
python -m http.server 8642
# open http://127.0.0.1:8642/index.html
```

## Supabase

Connected to a live Supabase project: **Supabase Auth** (phone + PIN, mapped to
per-user email accounts) gates the app, the demo state syncs to the
`app_state` table (authenticated-only), and public join requests are filed in
the normalized `membership_applications` table. `supabase/schema.sql` holds the
full normalized schema (loan-cap trigger, 70%-vote auto-approval, RLS group
isolation), `supabase/auth-setup.sql` the auth policies. Production migration
path is described in `docs/payments-integration-spec.md`.

## Project layout

```
index.html                        # the entire app
docs/payments-integration-spec.md # real gateway/backend integration spec
supabase/schema.sql               # database schema + RLS
```
