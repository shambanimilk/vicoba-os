# VICOBA OS — Payments & Messaging Integration Spec

Status: **specification** (the in-app payment experience is a simulation; this document describes how to make it real)
Audience: backend developer / technical co-founder
Related: `index.html` (front-end prototype)

---

## 1. Goal

Turn the simulated "Changia kutoka mtandao wowote" flow into real money movement, so VICOBA OS can accept contributions and loan repayments from **any Tanzanian mobile-money network** (M-Pesa, Mixx by Yas, Airtel Money, HaloPesa), bank transfers, and cards — plus send real SMS/WhatsApp reminders.

This is the core differentiator vs. M-Koba, which is locked to one network (Vodacom M-Pesa).

## 2. Architecture

```
┌──────────────┐   HTTPS    ┌──────────────┐   REST API   ┌──────────────┐
│  VICOBA OS   │ ─────────> │   Backend    │ ───────────> │   Payment    │
│  (frontend)  │  JWT/OTP   │  (Node/Go)   │  + webhook   │   Gateway    │
│  PWA / web   │ <───────── │  + Postgres  │ <─────────── │ (aggregator) │
└──────────────┘  updates   └──────┬───────┘  callbacks   └──────────────┘
                                 │
                          ┌──────┴───────┐
                          │ SMS/WhatsApp │  (reminders, consents, receipts)
                          │   Gateway    │
                          └──────────────┘
```

The frontend never holds gateway credentials. All secrets live on the backend.

## 3. Gateway options (Tanzania)

| Option | Networks covered | Notes |
|---|---|---|
| **Selcom** (TZ) | M-Pesa, Mixx, Airtel, HaloPesa, bank, card | Strong local coverage, USSD push + QR, TSh settlement. Recommended primary. |
| **Flutterwave** | M-Pesa, Mixx, Airtel + pan-African | Good if expanding beyond TZ later; higher fees. |
| **DPO Group** | M-Pesa, cards, bank | Solid card processing; mobile-money coverage varies. |

Recommendation: **Selcom primary** (deepest TZ mobile-money coverage), Flutterwave as fallback. Both support webhook callbacks.

## 4. Backend API (sketch)

| Endpoint | Purpose |
|---|---|
| `POST /api/payments/initiate` | Body: `{memberId, type, amount, channel, idempotencyKey}` → returns `{paymentRef, instructions (USSD/push), expiresAt}`. Ref format matches the prototype's `PAY-XXXX`. |
| `POST /webhooks/gateway` | Gateway callback on payment success/failure. Must validate signature header (HMAC or IP allowlist). |
| `GET /api/payments/:ref` | Frontend polls (or WebSocket) for status until `confirmed` or `expired`. |
| `POST /api/reminders/dispatch` | Cron job (daily) that evaluates due loans/contribution days and queues SMS — mirrors `runReminders()` in the prototype. |
| `POST /api/consents/:applicationRef` | Referee accept/refuse from SMS deep link — mirrors `respondConsent()`. |

### Idempotency & reconciliation
- Every initiation carries a client-generated `idempotencyKey` (e.g., `memberId-type-yyyymmdd`) so retries never double-charge.
- A nightly reconciliation job compares gateway settlement reports against local transactions; mismatches raise alerts (never auto-edit — append corrections, matching the audit-log philosophy).

## 5. Security checklist

- Gateway API keys/secrets only on the server (env vars / secret manager).
- HTTPS everywhere; HSTS on the API.
- Webhook signature validation + reject unexpected source IPs.
- Member auth: phone + PIN (hashed with bcrypt/argon2) + OTP on new devices — the current demo skips real auth.
- Role-based authorization server-side (never trust the client's role).
- Audit log is append-only; database triggers deny UPDATE/DELETE on `audit_log`.

## 6. SMS / WhatsApp for reminders

Options: Africa's Talking, Infobip, or gateway-bundled SMS (Selcom offers SMS).
Message templates mirror the prototype's reminder engine:
- Loan due: "Mkopo {loanId} unalipwa {date}. Lipa sasa kuepuka adhabu {penaltyAmount} ({rate}%)."
- Overdue: "Mkopo {loanId} umechelewa! Adhabu ya {penaltyAmount} imeongezwa."
- Contribution: "Kumbusho: mchango wa wiki hii {amount} unalipwa kesho {date}."
- Referee consent: deep link `https://app.vicoba-os.co.tz/c/{applicationRef}?ref={refereeToken}` — one-tap Kubali/Kataa.

## 7. Data model additions (beyond the prototype's localStorage shape)

```
payments(id, ref, member_id, type, amount, channel, status, gateway_txn_id, created_at, confirmed_at)
reminders(id, member_id, kind, message, dedupe_key, sent_at)
consent_tokens(application_ref, referee_id, token, used_at)
members(id, group_id, full_name, phone, national_id, photo_url, kin_name, kin_relation, kin_phone, role)
jamii_claims(id, ref, member_id, event_type, beneficiary, amount, shortfall, status, decided_by, created_at)
expenses(id, group_id, category, description, amount, date, recorded_by)
```

The prototype already stores the JSON equivalents (`transactions[].network/ref/memberId`, `remindersLog[]`, `loanApplications[].referees[]`, `members[].photo/nationalId/kin*`, `jamiiClaims[]` incl. `shortfall`, `expenses[]` with category `Posho ya Mkutano`/`Utasuluhishi (Grievances)`/…), so migration is a straight mapping. Member photos should move from localStorage data-URLs to object storage (S3-style) with the DB holding `photo_url`. Emergency ("dharura") contributions are ordinary payments with `type='Dharura ya Jamii'` — the gateway attributes them to `member_id` exactly like regular contributions.

## 8. Build order

1. **Auth + backend skeleton** — phone/PIN login, JWT, Postgres, migrate the localStorage model.
2. **Selcom integration** — initiate + webhook + reconcile; swap the simulated confirm button for status polling.
3. **SMS reminders** — cron dispatch + templates; keep the in-app "SMS Outbox" as the sent-messages view.
4. **Referee consent deep links** — SMS one-tap consent.
5. **USSD (*150# style) short code** — for members without smartphones (gateway-provided).
6. **Compliance** — BOT (Bank of Tanzania) payment-systems guidelines, data protection (PDPA 2022), KYC on members.

## 9. What stays in the front end

The current prototype's flow (channel selection → instructions → reference → confirmation) maps 1:1 onto the real API, so when the backend is ready the UI needs only the `confirmPayment()` call replaced by `initiate → poll` — no redesign required.
