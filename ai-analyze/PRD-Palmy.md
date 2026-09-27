# Palmy — product requirements document

Version 1.0 · 26 September 2026 · Proposed product specification derived from an authenticated black-box audit of [Seruma](https://seruma.app/).

## 1. Summary

Palmy is a household workspace for managing money, plans, schedules, shopping and maintenance. A household can record income and expenses, understand cash and credit balances, plan budgets, track debts and savings goals, manage investments, coordinate tasks, and preserve useful links.

This specification names the proposed application **Palmy**. The source application remains Seruma; no live brand or family name was changed. Requirements below describe the intended Palmy product. The [coverage inventory](coverage.csv) distinguishes observed behavior from inspection-only and unexecuted scenarios. The proposed API and database are new designs, not claims about Seruma's private implementation.

**Scope exclusion:** Berdua and all of its descendants, Conversation Cards, and Jurnal Keluarga are excluded from testing, requirements, API resources and database entities. References to financial journals mean bookkeeping entries, not Jurnal Keluarga.

## 2. Ownership and contacts

The requesting stakeholder is the product sponsor for this specification. Product owner, engineering lead, design lead, QA owner and data/privacy owner must be assigned before delivery begins. No names or approval claims are inferred from the authenticated account. Ownership of each implementation milestone belongs to the relevant role, not to the reference application's operators.

## 3. Background and evidence

The reference product combines household finance and daily coordination in a compact mobile-oriented interface. The observed navigation is Home, Finance, Calendar and More, with Finance hosting budgets, debts, goals, assets, allocation, wallets, recurring transactions, reports, calculators and groceries. Maintenance, links, profile, settings, affiliate, feedback and help appear under More.

The audit used clearly labeled synthetic records (`PALMY QA R2`) in the signed-in household. It verified persisted results for cash and credit wallets, transfers, expenses, AI-assisted income, category splits, budgets, a receivable lifecycle, savings contributions/releases, investment purchase/valuation/sale, recurring posting, groceries checkout, calendar events/checklists and maintenance. Exports were checked as downloaded XLSX workbooks.

Evidence does not establish market demand, user retention, real provider reliability, server authorization, multi-user concurrency, or production capacity. No source code, database catalog, private API specification, or staging environment was available. File upload was blocked by the browser extension's file-access setting. Observed weaknesses inform explicit Palmy improvements:

- A shared expense of 1234.56 became two rows totaling 1235. Palmy must preserve the entered total exactly.
- Grocery checkout and maintenance costs used the primary wallet without a picker. Palmy must make the posting destination explicit.
- Several icon controls and checklists were unnamed, while sortable cards appeared disabled to accessibility tools. Palmy requires semantic, operable controls.
- Help content conflicts with settings about PIN behavior and display currency. Palmy requires help content tied to implemented behavior.

## 4. Objectives and success criteria

The primary outcome is that a household can make daily decisions using an understandable, internally consistent record of money and commitments.

| Objective | Proposed release measure | Measurement |
|---|---|---|
| Trustworthy balances | Every posted journal balances exactly; no duplicate posting for repeated idempotency keys | Database invariant tests and reconciliation jobs |
| Fast daily capture | At least 90% of recruited usability participants complete a basic expense without help; median completion under 45 seconds | Moderated pilot task, timing starts at Home |
| Connected planning | Goal reservations, debt principal, transfers and asset trades never inflate ordinary income/expense totals | Golden ledger scenarios and report reconciliation |
| Reliable coordination | At least 99% of eligible reminder jobs enter a terminal delivered/failed state within five minutes of due time | Worker telemetry; push delivery is separately reported |
| Accessible everyday use | All core flows pass keyboard checks and targeted WCAG 2.2 AA review | Manual accessibility test plus automated checks |
| Recoverable data | Tested restore to a new environment; no silent import partial success | Restore drill and import rollback tests |

These are proposed acceptance targets, not measured results or promises about the reference app. Define the activation event as: household configured, first wallet created, first income/expense posted, and one budget or goal created. Track activation rate, weekly active households, successfully posted entries, reconciliations, rejected duplicate requests, import failures and reminder failures. Establish a real baseline during the pilot before setting growth targets.

## 5. Users and jobs to be done

| Segment | Job | Required access |
|---|---|---|
| Household owner | Set up shared records, manage members and protect household data | Owner settings and all household workflows |
| Household member | Record spending and coordinate tasks with a partner | Authorized shared records and attributed actions |
| Household financial planner | Understand budgets, obligations, savings and investments | Reporting, calculators and portfolio tools |
| Affiliate participant | View eligible referrals, commissions and payout status | Own affiliate account only |

Palmy's initial role model is owner/member. Restricted child accounts are a future design question; they were not demonstrated as an available role in the audit and must not be advertised as shipped. Affiliate administration and support moderation require separate internal operator permissions, never household roles.

## 6. Value proposition and experience

Palmy brings related household activities into one place: grocery checkout can become an expense; service history can create a cost and next maintenance date; a goal can combine reserved cash with linked investments; calendar views can surface bills and service reminders. Users must be able to see which linked records were created and correct them without breaking balances.

Use Indonesian for the initial interface, ISO dates and exact decimal amounts at the API boundary, and localized display formatting in the client. The household's reporting timezone is explicit. Base bookkeeping currency is IDR in v1; an optional display currency uses a timestamped conversion rate. Show base amounts and rate provenance in detail/export. Do not silently reinterpret existing amounts when changing display currency.

Every form supports required-field errors, loading, retry, empty state, saved state and prevention of accidental double submission. AI/OCR produces a draft that the user reviews before committing. Monetary actions explicitly show the selected wallet, direction, amount and any fee. Cross-module actions show their consequences before confirmation.

## 7. Solution and functional requirements

Priority **P0** is necessary for a trustworthy core release. **P1** completes the observed household feature set. **P2** is a separately gated enhancement. Each row is traceable to IDs in [coverage.csv](coverage.csv), API operation tags and the database entity catalog.

| ID | Priority | Capability | Acceptance criteria |
|---|---|---|---|
| FR-01 | P0 | Navigation and search | Home/Finance/Calendar/More reach every in-scope module; search clearly says whether it searches menus or records; back navigation preserves valid draft state; loading is distinguishable from empty. |
| FR-02 | P1 | Home, notifications and insight | Show today's agenda, period finances, wallet filters and recent entries; mask amounts accessibly; notification read state persists; generated insights cite their reporting period and underlying totals. Weather is optional with manual location fallback. |
| FR-03 | P0 | Wallets | Create cash/bank/e-wallet/credit/external wallets with name, icon, owner, opening state and wealth-inclusion flag; credit limit and outstanding/CR are distinct; archive preserves history; balance adjustment is an audited journal, not an overwrite. |
| FR-04 | P0 | Transfers and credit repayment | Transfer 1000 with fee 50 reduces source 1050 and increases destination 1000 atomically; fee is expense and principal is internal transfer; reject identical source/destination and inaccessible wallets; credit repayment reduces cash and liability together. |
| FR-05 | P0 | Transactions | Record income/expense with date, optional time, merchant, description, need/want, member, wallet, category and fee; edit metadata with version conflict protection; changes to money reverse and replace the journal; support duplicate-to-draft and reviewed category/person splits. |
| FR-06 | P0 | Transaction history | Search description/merchant; filter date/category/member/wallet/type; stable date and amount sorting; cursor pagination has no duplicates/missing rows; reset restores defaults; grouped transfer display counts one business operation. |
| FR-07 | P1 | AI and receipt capture | Support manual input, natural-language parsing, receipt OCR, transfer-proof OCR and up to 10 receipts per batch; show uncertainty and editable draft fields; distinguish transfer from expense; commit only reviewed valid drafts; failed files do not silently disappear. |
| FR-08 | P0 | Budgets/categories | Parent categories and one subcategory level; names/icons/colors/default need/want and optional wallet restrictions; period budget amounts and due dates; list/card/reorder; cycle starts day 1–28 in v1; trend labels explain included cashflow; archived categories preserve history. |
| FR-09 | P0 | Debts and receivables | Support borrowing, lending and credit-goods origin, prior balances, rate/tenor/due date, person and notes; explicit optional wallet effect; payment cannot exceed remaining amount; principal/interest/fee separated; archive/restore preserves balances; reminder is a prepared message until user sends it. |
| FR-10 | P0 | Goals and savings | Require name/type/target; optional deadline and default wallet; reserve existing funds without another cash debit; support contribution, release and cross-wallet movement; link assets without duplicating wealth; progress = allocated cash + allocated asset market value; insufficient free cash is rejected. |
| FR-11 | P1 | Assets and investments | Support gold, silver, dinar, FX, stock, ETF, crypto, bond, deposit, mutual fund, property and other; class-specific units/pricing; purchase, valuation, sale, fee, dividend/income, unit correction, ownership and goal link; preserve cost basis; distinguish approximate performance from exact cashflow returns. |
| FR-12 | P1 | Allocation planning | Model income allocation into named percentages linked to budgets/goals/asset classes; require total 100% before applying; preview exact amounts and changes; save/apply atomically; asset allocation targets and income allocation are separate plans. |
| FR-13 | P1 | Recurring templates | Monthly/yearly schedule, amount/category/wallet/person/fee and optional linked debt/goal/asset; manual record opens a review; at most one committed occurrence per due date unless an explicit correction is made; automatic posting is deferred P2 and must be opt-in. |
| FR-14 | P0 | Reports and exports | Day/week/month/year and custom periods; cashflow, wealth, category/member/wallet, need/want and budgets; transfers excluded from external cashflow; principal separated from spending; Excel and print use identical filters/totals; display-currency rate is visible. |
| FR-15 | P1 | Calculators | Loan with fixed/tiered rates, extra payments and takeover comparison; saved scenarios; education inflation and funding estimate; create-goal draft from result; zero-rate calculation 1200000/12=100000; disclose assumptions and rounding. |
| FR-16 | P1 | Groceries | Sections, items, quantities/unit prices, selected checkout, merchant, purchase/price history and recurring needs; receipt item extraction; explicit wallet or record-only choice; checkout creates one atomic transaction with immutable purchase lines; retry cannot charge bookkeeping twice. |
| FR-17 | P1 | Calendar and tasks | Month/week/day, categories of event/checklist, item order/color, date or undated task, optional time, assignee, time window, recurrence/reminders, complete/undo, import and read-only calendar feed; occurrence completion must not complete an entire recurring series. |
| FR-18 | P1 | Maintenance | Vehicle/home/electronic resources; interval and next due date; service/repair history and attachments; explicit wallet or record-only service cost; create/update linked calendar reminder; history corrections update cost through journal replacement. |
| FR-19 | P1 | Important links | Name, safe http/https URL, category/order; create/edit/archive; sensitive view requires configured step-up PIN; PIN never travels in URL; opened external links cannot access the opener context. |
| FR-20 | P0 | Profile and membership | Household name, members, profile photo and optional location; owner can invite/revoke members; invitation accepts only intended account and expires; household access ends promptly on revocation; role checks enforced server-side. |
| FR-21 | P0 | Settings and security | Reporting cycle, display currency and split defaults; explicit PIN scope; account/password change uses identity provider; browser permissions optional; destructive reset/delete uses step-up and explicit scope preview; never expose secrets in exports/logs. |
| FR-22 | P1 | Import, backup and integrations | Versioned templates; upload/validate/preview/commit; row-specific localized errors, duplicate detection and atomic batches; selective export of in-scope domains; background jobs downloadable by authorized member only; optional Google Sheets OAuth with least privileges and disconnect. |
| FR-23 | P1 | Affiliate | Own referral link, attributed referrals, eligible commission ledger, payout destination and request history; available balance excludes pending/paid/reversed commissions; minimum withdrawal 50000 IDR is configurable; payout provider effects idempotent. |
| FR-24 | P1 | Help and feedback | FAQ, about, privacy/terms links; feedback topic/status/search/my requests and one vote per account; separate public content from household data; validation and help agree with product behavior. |

### Business rules and exact acceptance scenarios

1. **Exact amounts.** Store and compute money as decimal, never binary floating point. At a two-decimal allocation scale, 1234.56 split evenly is 617.28 +617.28. If a product currency permits only whole units, reject or explicitly round the input once before posting; never change it silently during splitting. Largest-remainder allocation preserves the exact accepted total for uneven shares.
2. **One business operation, one atomic outcome.** A transfer, debt payment, credit repayment, grocery checkout, service expense or asset trade commits its domain record and balanced journal together. A retry with the same idempotency key returns the first result. Rollback leaves neither side visible.
3. **Reports represent economic meaning.** Opening balance, internal transfer, debt principal, goal reservation, asset purchase and ordinary spending are separate purposes. Paying 500 principal is a cash outflow and liability reduction; it is not another 500 of ordinary consumption.
4. **Goals do not mint assets.** Reserving 1500 from a100000 wallet leaves wallet balance 100000 and free cash 98500. Releasing 500 makes reservation 1000. Linking a1500 investment gives 2500 goal progress; household net worth counts that investment once.
5. **Asset basis.** Buy 2 units at 1000, revalue to 1500/unit, sell 1 at 1500: one unit remains, cost 1000, market value 1500, realized gain 500 before fees. Unit correction to 1.5 preserves remaining cost 1000 and records its reason.
6. **Debt lifecycle.** Lend 2000; receive 500; remaining 1500. A further 1501 is rejected in the same transaction that checks the current balance. Archive/restore does not erase principal or payments. Keep archive visibility independent from inclusion in wealth.
7. **Credit.** Credit limit 10000 and outstanding 2000 yield available 8000. Paying 500 yields outstanding 1500 and available 8500. Overpayment is an explicit credit balance, not a negative debt bug.
8. **Calendar.** Store date-only tasks separately from timed events. Household timezone defines reporting-day boundaries. Monthly day 31 recurrence uses a documented clamp-to-last-day policy; changing a series distinguishes this occurrence/future occurrences/all.
9. **Import.** Parse 321.09 as 321.09. Reject negative expense input rather than interpreting it as positive. Preview all errors and proposed category/wallet mappings before commit. An imported row's source fingerprint prevents duplicate posting on repeated imports unless user explicitly resolves it.
10. **Cross-module correction.** Archiving a wallet/category must not orphan history. Changes to posted money create an audited reversal/replacement; all dependent views recalculate. Deletion workflows must state what remains for audit and what is erased.

### Nonfunctional requirements

| ID | Requirement | Release evidence |
|---|---|---|
| NFR-01 | Responsive at 320–1920 px; keyboard operability; meaningful accessible names, focus management and error associations; WCAG 2.2 AA target | Every core page and modal tested, not only Home; screen reader and contrast review |
| NFR-02 | Tenant isolation, least privilege, step-up for sensitive actions, exact arithmetic, audit trail, idempotency and optimistic concurrency | Two-tenant negative tests, version conflicts, duplicate request tests, balanced journals and concurrent overpayment/sale tests |
| NFR-03 | Proposed p95 read response under 500 ms and posted write under 1s excluding AI/file providers; availability target 99.9% monthly | Staging workload with declared dataset/concurrency; production SLO monitoring |
| NFR-04 | Encrypted transport and managed encryption at rest; secret references only; signed short-lived downloads; file malware/type/size checks | Security review, access-control tests and operational evidence |
| NFR-05 | Backup RPO 24h/RTO 4h proposed for v1; localized errors; traceable async jobs; no silent partial imports | Restore drill, failed-job recovery and localized error snapshots |

Do not collect financial descriptions in analytics. Use event IDs, timing and result codes. Logs omit PIN/password/token/bank identifiers and receipt contents. Define retention and deletion policy with the responsible privacy owner before launch; this document is not a jurisdictional legal assessment.

## 8. Release and validation plan

| Stage | Deliverables | Exit gate |
|---|---|---|
| Foundation | Identity, household authorization, database migration, exact ledger, API contract | Tenant and invariant test suite passes; backup restore exercised |
| Finance core | Wallets, transfers, categories, transactions, budgets, debts, goals and reports | Golden business scenarios reconcile at all views; no P0/P1 data-integrity defect |
| Household operations | Recurring, groceries, calendar, maintenance, links, imports and exports | Cross-module atomicity, reminder scheduling and file pipeline tested |
| Planning and ecosystem | Assets, allocation, calculators, insights, affiliate and optional integrations | Provider failure/retry, pricing provenance and operator permissions tested |
| Pilot and general availability | Usability, accessibility, multi-browser, privacy and operations review | Named owners approve measured evidence and remaining low-severity risks |

Release blockers include the demonstrated amount-preservation defect if reproduced in Palmy, unverified tenant isolation, unbalanced postings, double commits, unsafe file processing, and incorrect linked goal/asset totals. Imported historical data must be reconciled before a household starts posting live records.

The live reference audit is not a release certification. Complete the remaining scenarios in the [QA report](QA-report.md) using a disposable staging tenant, enabled file upload, test identities and provider sandboxes. Product decisions still to confirm are invitation licensing, permitted member restrictions, supported display currencies, quotation providers, regulatory treatment of affiliate payouts, and data-retention periods. The specification gives implementable defaults while identifying these decisions explicitly.
