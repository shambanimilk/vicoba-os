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

## Demo sign-ins (phone + any PIN)

| Role | Phone | Group |
|---|---|---|
| Mwenyekiti (chair) | +255713456789 | Umoja wa Wanawake |
| Mweka Hazina (treasurer) | +255715678901 | Umoja wa Wanawake |
| Katibu (secretary) | +255712345678 | Umoja wa Wanawake |
| Mkaguzi (auditor) | +255714567890 | Umoja wa Wanawake |
| Mwanachama (member) | +255716789012 | Vijana Nguvu |

Or use the demo role buttons on the login page. Join a group with invite code
`UMOJA-7K2Q` or open `index.html#invite=UMOJA-7K2Q`.

## Run locally

```bash
python -m http.server 8642
# open http://127.0.0.1:8642/index.html
```

## Supabase (planned backend)

`supabase/schema.sql` contains the full database schema (tables, indexes, and
row-level-security policies enforcing group isolation). See `docs/payments-integration-spec.md`
for the backend architecture and roadmap.

## Project layout

```
index.html                        # the entire app
docs/payments-integration-spec.md # real gateway/backend integration spec
supabase/schema.sql               # database schema + RLS
```
