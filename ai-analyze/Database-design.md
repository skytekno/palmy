# Palmy — database design

Proposed PostgreSQL 17+ relational model for the in-scope application. The schema is authored from observed product behavior and deliberate Palmy improvements; Seruma's actual schema was not accessed.

Use [schema.sql](schema.sql) for the DDL, [database-dictionary.md](database-dictionary.md) for all columns and constraints, and [ERD.md](ERD.md) for readable relationship views. The complete graph is [palmy-erd.mmd](palmy-erd.mmd). These files share a generated table definition source to limit drift.

## Model and domain ownership

| Domain | Tables | Purpose |
|---|---|---|
| Identity/tenant | users, households, memberships, invitations, household_settings | Identity subject, household boundary, membership, invitations and preferences |
| Ledger/wallets | ledger_accounts, wallets, journal_entries, journal_lines, entry_allocations, merchants | Exact financial source of truth and category/member analysis |
| Budgets | categories, wallet_category_rules, budget_periods, budget_limits | Category tree, wallet restrictions and period limits |
| Debts/goals | debts, debt_payments, goals, goal_movements, goal_asset_links | Principal lifecycle and non-duplicating cash/asset savings allocations |
| Investments | asset_holdings, asset_trades, asset_quotes, allocation_plans, allocation_items | Position/basis history, timestamped prices and target allocations |
| Recurrence/calculators | recurring_templates, recurring_occurrences, calculator_scenarios | Reviewable schedules, deduplicated executions and saved calculations |
| Groceries | shopping_sections, shopping_items, shopping_purchases, shopping_purchase_items, shopping_routines | Current list, immutable checkout snapshots and recurring needs |
| Calendar | calendar_categories, calendar_items, calendar_exceptions, calendar_reminders, calendar_feeds | Events/tasks, recurrence exceptions, reminders and revocable feeds |
| Maintenance/links | maintenance_items, service_records, important_links | Equipment, service history, linked costs and PIN-gated URLs |
| Files/jobs | files, file_links, jobs, import_rows, integrations | Private files, typed resource links, async work, import preview and consent |
| Security/notifications | pin_credentials, step_up_grants, device_subscriptions, notifications | Verifiers, scoped grants, push registration and personal inbox |
| Affiliate | affiliate_accounts, affiliate_commissions, payout_destinations, payout_requests, promotion_submissions | Own referral account, eligibility ledger and payout lifecycle |
| Product content | feedback_posts, feedback_votes, help_articles | Public suggestions, unique votes and versioned help |
| Reliability | idempotency_keys, audit_events, outbox_events, destructive_plans | Retry safety, traceability and atomic async delivery |

There are 62 tables. No entity represents Berdua, Conversation Cards or Jurnal Keluarga.

## Keys, types and normalization

Each table has a UUID primary key, timestamps and a version. Tenant tables additionally have `household_id` and `UNIQUE(household_id,id)`. References between tenant entities use both columns, so knowing a foreign UUID cannot create a cross-household link. Deletions use RESTRICT rather than silently cascading financial history.

Money uses the `palmy.money` domain over unrestricted `numeric` with explicit precision/scale checks, rather than `numeric(p,2)` coercion that can round before validation. It rejects more than two decimal places, non-finite values and values outside the declared range. Quantity permits up to 10 fractional digits; conversion rates have their own domain. PostgreSQL's [numeric type documentation](https://www.postgresql.org/docs/current/datatype-numeric.html) explains the exact numeric behavior underlying this choice.

Normalize category/member allocation, trades, quotes, payments, reservations and purchase lines instead of embedding them into mutable balances. JSONB is confined to versioned calculator payloads, job options/results, import staging and bounded audit/outbox envelopes. The application validates their schemas by version. No financial balance is stored as an unguarded JSON field.

Merchant names are household-local. Categories support one parent and one subcategory level. Active names have scoped unique indexes; archive retains history. A goal can link many holdings; each holding can belong to at most one goal in v1, avoiding duplicated progress. Partial ownership across goals would require a future allocation table and total-percentage invariant.

## Accounting model

`journal_entries` represent business operations. `journal_lines` contain signed debit-positive amounts against asset, liability, income, expense or equity accounts. At commit, each posted entry has at least two lines and sum 0. A posted header, posting line and analysis allocation cannot be modified or deleted. Create a draft, add lines and analysis, then mark posted in one transaction.

| Operation | Debit-positive line | Credit-negative line |
|---|---|---|
| Opening cash 100000 | Cash asset+100000 | Opening equity−100000 |
| Income 3000 | Cash asset+3000 | Income−3000 |
| Expense 1234.56 | Expense+1234.56 | Cash asset−1234.56 |
| Transfer 1000 with 50 fee | Destination cash+1000; fee expense+50 | Source cash−1050 |
| Credit spending 2000 | Expense+2000 | Credit liability−2000 |
| Credit repayment 500 | Credit liability+500 | Cash−500 |
| Lend 2000 | Receivable asset+2000 | Cash−2000 |
| Receive principal 500 | Cash+500 | Receivable−500 |
| Buy 2 asset units at 1000 | Investment cost asset+2000 | Cash−2000 |
| Sell 1 unit at 1500 with basis 1000 | Cash+1500 | Investment cost−1000; realized gain income−500 |

Initial credit debt is an opening-liability/equity operation, not new spending. Paying principal is not a second expense. A prior receivable with no wallet effect uses an opening-equity counter-account. Record-only services/groceries create domain history with no journal. Record-only debt settlement still changes the receivable/payable and requires an explicit clearing/equity counterpart, which reports separately from cash.

An expense can have multiple category/member analysis rows without creating duplicate wallet debits. Require allocation sum equal to accepted principal, and map fee to its own expense line. Header amounts and fee are convenience business fields; the posting service validates their consistency with lines and domain entities. The DDL's balanced-sum trigger alone cannot determine the correct economic classification.

## Derived balances and corrections

- Wallet balance derives from posted lines against its account. Credit outstanding is the negative of a liability balance, with positive liability-account balance displayed as CR.
- Free cash is eligible wallet asset balance minus active goal reservations. A reserve/release changes `goal_movements`, not journal money. External savings use explicit external wallets. Later spending can reveal underfunding; do not invent cash to keep the goal funded.
- Debt remaining is original principal less payments, treating reversal rows as negative payments. Debt-payment trigger locks the debt and rejects an overpayment. A payment reversal must exactly match its original breakdown and can occur only once.
- Holdings derive quantity and cost from trade deltas. Quote history determines market value. The sale service computes weighted-average cost allocation and final-unit residual adjustment; the database rejects negative total quantity or basis. Unit correction changes quantity while preserving cost.
- Goal progress combines reserved cash with linked holding market value. Wealth aggregates each physical/account asset once. Goal exclusion is an allocation exclusion in the reporting layer and must not subtract a holding twice.
- Posted entry correction is a compensating journal plus replacement with explicit linkage. Debt, trade, checkout and service corrections run through the owning domain service; a generic ledger reversal alone must not leave domain state unchanged.

The trade schema includes explicit reversal linkage and checks opposite quantity/basis deltas against the original. Debt payments have matching breakdown reversals; service and purchase replacements link to the original snapshot. The owning command service must reverse the associated journal and append replacement domain data in the same transaction. The generic transaction reversal endpoint rejects these domain-owned operations. These are proposed implementation rules, not tested Seruma behavior.

## Transactions and concurrency

Use READ COMMITTED with explicit row locks for ordinary commands; use SERIALIZABLE or an equivalent retrying transaction for aggregate-sensitive workflows where a single root lock does not cover every writer. Always lock resource roots in deterministic order. Include every writer, including imports, workers and corrections, in the same locking protocol.

| Invariant | Database enforcement | Additional service enforcement |
|---|---|---|
| Exact finite money | Domain precision/range checks | Normalize locale; reject negative/zero where prohibited |
| Tenant integrity | Composite FKs and RLS | Validate identity and role before DB context |
| Balanced/immutable posted journal | Deferred sum trigger and mutation triggers | Correct account/type mapping; linked-domain consistency |
| Debt overpayment | Locked debt sum trigger | Interest policy, settlement mode and journal mapping |
| Asset oversell/basis below zero | Locked holding sum trigger | Cost-basis algorithm and provider/currency validation |
| Goal over-release/over-reserve | Wallet lock and reservation checks | New-money/transfer mode creates matching journal first |
| Active allocation total 100% | Deferred 10000-basis-point check | Preview hash, period mapping and plan-type rules |
| Duplicate recurrence/import | Unique template/date and committed fingerprint | Stable source fingerprint; retried operation semantics |
| Checkout/payout races | Scoped keys and idempotency record | Lock selected items/affiliate root; recompute totals/availability |
| Version conflicts | Incrementing version column | Conditional UPDATE and If-Match/412 contract |

All writes for an operation, its audit event, outbox event and idempotent response commit together. A key claim is unique on household/user/route/key; hash mismatch returns 409. Keep keys at least 24h; immutable domain uniqueness still prevents repeated occurrences after key expiry. Queue delivery is at least once; consumers deduplicate event/provider IDs.

## Row security and secrets

Runtime roles must be NOSUPERUSER, NOBYPASSRLS and not own tables. Most tenant tables use FORCE ROW LEVEL SECURITY. The membership lookup intentionally uses a fixed-search-path SECURITY DEFINER function owned by the migration role so policies can verify active membership without recursion; the membership table itself is not FORCE'd. Public execution of these helper functions is revoked and explicitly granted only to the application group.

The API sets `app.user_id` and `app.household_id` with SET LOCAL inside a transaction after verifying the token. Never accept these values directly from a request header or reuse them across pooled connections. No arbitrary SQL interface is exposed to clients. RLS limits data access; it is not a replacement for per-action authorization. PostgreSQL's [row-security documentation](https://www.postgresql.org/docs/current/ddl-rowsecurity.html) describes the owner/bypass behavior relevant to this setup.

The commented role grants in schema.sql describe the normal API role and revoke direct access to PIN, step-up, integration, bank-destination and calendar-feed tables. Identity bootstrap and secret operations need separately scoped trusted services. Do not grant every service broad migration credentials. Full owner/member operation authorization and operator-only commission/moderation writes must be implemented and tested before production.

PINs use an Argon 2 id verifier in an application-managed identity/security service, never plaintext or reversible encryption. Calendar/invitation/step-up bearer tokens are stored as digests. OAuth credentials are external secret-manager references. Phone/bank/push key data uses managed envelope encryption with key rotation. Export code uses an allowlist and excludes these tables.

## Indexes, queries and scale

Indexes cover tenant/date/ID journal pagination, every composite foreign key, latest asset quotes, calendar dates, unread personal notifications, queued jobs and undelivered outbox records. Partial unique indexes constrain primary wallets, active wallet/category names and committed import fingerprints. The initial model avoids partitioning; measure tenant size and query plans before introducing it.

For search, use escaped ILIKE initially on tenant-filtered descriptions/merchant names; add a tenant-aware text/trigram index only after measuring query shape. Reports should use journal-purpose and allocation indexes rather than repeatedly scanning JSON. A materialized monthly summary is an optional read model, rebuilt from authoritative entries and invalidated by corrections. Currency conversion remains presentation unless a future multi-base-currency version is designed explicitly.

## Lifecycle, migration and operations

The SQL creates a new `palmy` schema in a fresh database, inside a transaction. It does not connect to Seruma or migrate any private export automatically. Provision roles first through infrastructure, apply migration as owner, then apply narrowly reviewed runtime grants. Run the supplied validation procedures in a disposable database. Keep migration numbering/checksums in the implementation repository.

For future migrations, use expand/backfill/validate/contract: introduce nullable/new structures, deploy compatible readers/writers, backfill in bounded batches, validate constraints, then remove obsolete structures after the supported client window. Rollback of posted finance is compensating records, not dropping history. Back up before data transformations and test restore into a separate environment.

Proposed baseline: encrypted daily backups with RPO 24h/RTO 4h and a documented restore drill. File/job staging expires according to approved retention; financial records and audit retention need product/privacy approval. Archive is recoverable. Account erasure/reset requires a planned dependency order, step-up and explicit consequence preview; RESTRICT prevents accidental cascades. Operational deletion workers must reconcile ledger/domain requirements with the approved retention policy.

See [validation.md](validation.md) for the actual validation result. The schema and service rules are a design deliverable; they are not a running backend or a claim that every invariant has been executed in PostgreSQL in this environment.
