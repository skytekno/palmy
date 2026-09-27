# Product scope and implementation map

The execution plan is published in [Linear project Palmy](https://linear.app/skyholding/project/palmy-e44a689b012b). See the [issue and milestone map](linear-plan.md) for priorities, dependencies, acceptance criteria and refinement boundaries.

The full design comes from the 24 requirements and 154 proposed operations in `ai-analyze`. The first implementation makes encrypted profile ownership and a minimal personal ledger executable across three clients. A feature listed below as planned is neither served nor simulated by a production endpoint. The native/web designs share tokens and flows; the source contains no pixel-level mockups to reproduce.

| Source requirement | Current implementation | Remaining work |
|---|---|---|
| FR-01 Navigation | Beranda, Keuangan, Profil; shared responsive/native visual language | Full Calendar/More tree, menu/record search, draft restoration |
| FR-02 Home/insights | Live lifetime summary and recent transactions | Period/filter views, notifications, insight provenance, optional weather |
| FR-03 Wallets | Create personal IDR wallet; balance from postings | Types, opening journals, credit, archive, adjustments |
| FR-04 Transfers | Design retained | Atomic transfers, fees and credit repayments |
| FR-05 Transactions | Immutable income/expense, exact strings, idempotency | Splits, fees, metadata edits, reversal/replacement, duplicate-to-draft |
| FR-06 History | Owner-scoped recent entries, bounded API pagination | Full search/filter/sort and transfer grouping |
| FR-07 AI/OCR | Design retained | Upload scan, draft extraction, review, batch failures |
| FR-08 Budgets | Free-text category on simple transaction | Category hierarchy, budgets, cycles and reorder |
| FR-09 Debts | Design retained | Locked principal/interest/payment lifecycle |
| FR-10 Goals | Design retained | Reservations, release, linked assets, free-cash checks |
| FR-11 Investments | Design retained | Holdings, lots, valuations, trades and cost basis |
| FR-12 Allocation | Exactness policy retained | Plans, largest-remainder shares, atomic preview/apply |
| FR-13 Recurring | Design retained | Templates and one reviewed occurrence per due date |
| FR-14 Reports | Basic lifetime totals | Period economic-purpose reports, print and exports |
| FR-15 Calculators | Design retained | Versioned loan/education calculations and scenarios |
| FR-16 Groceries | Design retained | Selected checkout and explicit wallet choice |
| FR-17 Calendar/tasks | Design retained | Recurrence exceptions, reminders, feeds and imports |
| FR-18 Maintenance | Design retained | Service history and atomic linked expenses/calendar |
| FR-19 Links | Design retained | Safe URL policy and scoped step-up |
| FR-20 Profile/membership | Client-encrypted personal profile, create/recover/sign-in | Household membership and verified sharing protocol |
| FR-21 Security/settings | Owner authorization, session revoke, client lock, profile version | Rotation, all-device revocation, settings, step-up, deletion |
| FR-22 Imports/integrations | Design retained | File/job infrastructure, backups, exports, Sheets consent |
| FR-23 Affiliate | Design retained | Identity disclosure policy, separate operator/payout ledger |
| FR-24 Help/feedback | Privacy/recovery explanations | Complete localized help, public feedback and moderation |

Berdua and descendants, Conversation Cards, and Jurnal Keluarga remain excluded. Automatic recurring posting is P2 and restricted child roles are undecided in the source.

## Order of next slices

1. Finish key lifecycle, account deletion and independent protocol review; test secure native device storage and release distribution.
2. Add household authorization and verified profile-sharing envelopes with two-user/revocation tests.
3. Complete ledger transfers, fees, splits, reversals and adjustments, then wallet types/categories.
4. Add budgets, debts and goals with concurrent invariant tests; reconcile reports against journals.
5. Add jobs/outbox/private files, then groceries, calendar, maintenance, OCR and import/export.
6. Add investments, allocation and calculators; gate providers, affiliate and optional integrations independently.

Each slice updates the running OpenAPI, cross-client behavior and validation evidence together. The original source API paths use households and assume an identity provider; the implemented personal-account contract intentionally differs. Do not generate clients against `ai-analyze/openapi.json` expecting those endpoints to exist. Use `contracts/openapi.json` and [protocol.md](protocol.md).
