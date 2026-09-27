# Palmy delivery plan

[Read the published roadmap document](https://linear.app/skyholding/document/palmy-implementation-roadmap-and-release-gates-a418cf1888e8).

[Open the Linear project](https://linear.app/skyholding/project/palmy-e44a689b012b). Published 27 September 2026: **44 issues (30 capability epics, 14 implementation tasks), 8 milestones and 70 blocking relationships**. All FR-01–24 and NFR-01–05 are mapped. Linear is the live execution tracker; [linear-plan.json](linear-plan.json) is this publication snapshot with stable issue IDs, requirements and dependencies.

## Planning boundaries

- Owners and issue dates remain unset until capacity is confirmed; existing project lead/start/target dates preserved.
- Capability epics are Backlog and require child-task refinement before sprint commitment. No speculative effort estimates.
- The current first slice is local and uncommitted. Strict TypeScript is locally verified and In Review, not Done or shipped.
- Berdua and descendants, Conversation Cards and Jurnal Keluarga are excluded. Restricted child roles are undecided. Automatic recurring posting is P2.
- Identity is client-encrypted; readable finance and metadata can reidentify people. No promise of guaranteed anonymity.

The user requested strict TypeScript and an implementation plan in the existing Palmy project. The existing SkyTek team, project lead, start date and January 31, 2027 target were preserved. Team capacity is unknown; that target is not a delivery forecast. The initial app has 14 runtime operations; the 154-operation source design remains future scope. No source-input files were edited.

## Milestones and issues

### 01 · Secure foundation

Integrate and review the locally validated personal-account slice; enforce strict TypeScript, contract parity, key lifecycle, native lifecycle tests and operational controls.

| Issue | Scope | Requirements | State at publication |
|---|---|---|---|
| [MAN-80](https://linear.app/skyholding/issue/MAN-80/epic-review-and-operationalize-the-monorepo-foundation) | [Epic] Review and operationalize the monorepo foundation | NFR-02, NFR-03, NFR-04, NFR-05 | Backlog |
| [MAN-81](https://linear.app/skyholding/issue/MAN-81/epic-complete-encrypted-identity-and-account-lifecycle) | [Epic] Complete encrypted identity and account lifecycle | FR-21, NFR-02, NFR-04 | Backlog |
| [MAN-110](https://linear.app/skyholding/issue/MAN-110/review-and-integrate-the-locally-validated-monorepo-baseline) | Review and integrate the locally validated monorepo baseline | NFR-02, NFR-05 | Todo |
| [MAN-111](https://linear.app/skyholding/issue/MAN-111/enforce-strict-typescript-and-resolve-checked-boundary-errors) | Enforce strict TypeScript and resolve checked-boundary errors | NFR-02 | In Review |
| [MAN-112](https://linear.app/skyholding/issue/MAN-112/enforce-runtime-contract-and-cross-client-crypto-fixtures-in-ci) | Enforce runtime contract and cross-client crypto fixtures in CI | NFR-02 | Backlog |
| [MAN-113](https://linear.app/skyholding/issue/MAN-113/test-ios-authentication-and-background-lifecycle-races) | Test iOS authentication and background lifecycle races | FR-21, NFR-02 | Todo |
| [MAN-114](https://linear.app/skyholding/issue/MAN-114/test-android-authentication-and-background-lifecycle-races) | Test Android authentication and background lifecycle races | FR-21, NFR-02 | Todo |
| [MAN-115](https://linear.app/skyholding/issue/MAN-115/specify-credential-rotation-device-enrollment-and-revocation) | Specify credential rotation, device enrollment and revocation | FR-21, NFR-04 | Todo |
| [MAN-116](https://linear.app/skyholding/issue/MAN-116/implement-owner-wide-session-revocation) | Implement owner-wide session revocation | FR-21, NFR-02 | Backlog |
| [MAN-117](https://linear.app/skyholding/issue/MAN-117/specify-account-erasure-and-retention-boundaries) | Specify account erasure and retention boundaries | FR-21, FR-22, NFR-04 | Todo |
| [MAN-118](https://linear.app/skyholding/issue/MAN-118/implement-reviewed-android-credential-storage) | Implement reviewed Android credential storage | FR-21, NFR-04 | Backlog |
| [MAN-119](https://linear.app/skyholding/issue/MAN-119/implement-reviewed-ios-credential-storage) | Implement reviewed iOS credential storage | FR-21, NFR-04 | Backlog |
| [MAN-120](https://linear.app/skyholding/issue/MAN-120/verify-web-delivery-integrity-and-telemetry-privacy) | Verify web delivery integrity and telemetry privacy | FR-21, NFR-04 | Backlog |
| [MAN-121](https://linear.app/skyholding/issue/MAN-121/execute-a-disposable-postgresql-backup-and-restore-drill) | Execute a disposable PostgreSQL backup and restore drill | NFR-05 | Backlog |
| [MAN-122](https://linear.app/skyholding/issue/MAN-122/specify-and-test-authentication-abuse-and-step-up-controls) | Specify and test authentication abuse and step-up controls | FR-21, NFR-02 | Backlog |
| [MAN-123](https://linear.app/skyholding/issue/MAN-123/resolve-release-scope-ownership-and-provider-decisions) | Resolve release scope, ownership and provider decisions | FR-20, FR-21, FR-22, FR-23 | Todo |

### 02 · Household access

Add pseudonymous household roles, intended-recipient invitations and verified client-encrypted sharing. Revocation must stop future server access.

| Issue | Scope | Requirements | State at publication |
|---|---|---|---|
| [MAN-82](https://linear.app/skyholding/issue/MAN-82/epic-add-household-membership-and-verified-sharing) | [Epic] Add household membership and verified sharing | FR-20, NFR-02 | Backlog |

### 03 · Ledger and capture

Complete exact-money wallets, transfers, corrections, splits and searchable history with immutable balanced journals.

| Issue | Scope | Requirements | State at publication |
|---|---|---|---|
| [MAN-83](https://linear.app/skyholding/issue/MAN-83/epic-complete-navigation-drafts-and-accessible-forms) | [Epic] Complete navigation, drafts and accessible forms | FR-01, NFR-01 | Backlog |
| [MAN-84](https://linear.app/skyholding/issue/MAN-84/epic-complete-wallet-types-and-audited-balances) | [Epic] Complete wallet types and audited balances | FR-03 | Backlog |
| [MAN-85](https://linear.app/skyholding/issue/MAN-85/epic-post-atomic-transfers-and-credit-repayments) | [Epic] Post atomic transfers and credit repayments | FR-04 | Backlog |
| [MAN-86](https://linear.app/skyholding/issue/MAN-86/epic-add-transaction-metadata-corrections-and-exact-splits) | [Epic] Add transaction metadata, corrections and exact splits | FR-05 | Backlog |
| [MAN-87](https://linear.app/skyholding/issue/MAN-87/epic-deliver-stable-searchable-transaction-history) | [Epic] Deliver stable searchable transaction history | FR-06 | Backlog |

### 04 · Budgets, debts, goals and reports

Deliver trustworthy planning and economic-purpose reports reconciled against the ledger.

| Issue | Scope | Requirements | State at publication |
|---|---|---|---|
| [MAN-88](https://linear.app/skyholding/issue/MAN-88/epic-build-category-hierarchy-and-budget-cycles) | [Epic] Build category hierarchy and budget cycles | FR-08 | Backlog |
| [MAN-89](https://linear.app/skyholding/issue/MAN-89/epic-implement-debt-and-receivable-lifecycles) | [Epic] Implement debt and receivable lifecycles | FR-09 | Backlog |
| [MAN-90](https://linear.app/skyholding/issue/MAN-90/epic-implement-savings-reservations-and-goal-progress) | [Epic] Implement savings reservations and goal progress | FR-10 | Backlog |
| [MAN-91](https://linear.app/skyholding/issue/MAN-91/epic-reconcile-period-reports-excel-and-print) | [Epic] Reconcile period reports, Excel and print | FR-14 | Backlog |

### 05 · Household workflows and files

Deliver private file/job infrastructure, reviewed recurring entries, groceries, calendar, maintenance, links and import/export.

| Issue | Scope | Requirements | State at publication |
|---|---|---|---|
| [MAN-92](https://linear.app/skyholding/issue/MAN-92/epic-build-private-files-jobs-and-transactional-outbox) | [Epic] Build private files, jobs and transactional outbox | NFR-04, NFR-05 | Backlog |
| [MAN-93](https://linear.app/skyholding/issue/MAN-93/epic-add-reviewed-text-and-receipt-capture) | [Epic] Add reviewed text and receipt capture | FR-07 | Backlog |
| [MAN-94](https://linear.app/skyholding/issue/MAN-94/epic-add-reviewed-recurring-transaction-templates) | [Epic] Add reviewed recurring transaction templates | FR-13 | Backlog |
| [MAN-95](https://linear.app/skyholding/issue/MAN-95/epic-deliver-groceries-and-atomic-selected-checkout) | [Epic] Deliver groceries and atomic selected checkout | FR-16 | Backlog |
| [MAN-96](https://linear.app/skyholding/issue/MAN-96/epic-build-calendar-tasks-and-occurrence-safe-reminders) | [Epic] Build calendar, tasks and occurrence-safe reminders | FR-17 | Backlog |
| [MAN-97](https://linear.app/skyholding/issue/MAN-97/epic-link-maintenance-history-costs-and-calendar) | [Epic] Link maintenance history, costs and calendar | FR-18 | Backlog |
| [MAN-98](https://linear.app/skyholding/issue/MAN-98/epic-protect-important-links-with-scoped-step-up) | [Epic] Protect important links with scoped step-up | FR-19 | Backlog |
| [MAN-99](https://linear.app/skyholding/issue/MAN-99/epic-implement-previewed-imports-selective-export-and-backup-jobs) | [Epic] Implement previewed imports, selective export and backup jobs | FR-22 | Backlog |

### 06 · Investments and ecosystem

Add investment accounting, allocation, calculators, insights, optional providers, affiliate and help/feedback.

| Issue | Scope | Requirements | State at publication |
|---|---|---|---|
| [MAN-100](https://linear.app/skyholding/issue/MAN-100/epic-implement-investment-lots-valuation-and-trades) | [Epic] Implement investment lots, valuation and trades | FR-11 | Backlog |
| [MAN-101](https://linear.app/skyholding/issue/MAN-101/epic-apply-exact-income-and-asset-allocation-plans) | [Epic] Apply exact income and asset allocation plans | FR-12 | Backlog |
| [MAN-102](https://linear.app/skyholding/issue/MAN-102/epic-add-versioned-loan-and-education-scenarios) | [Epic] Add versioned loan and education scenarios | FR-15 | Backlog |
| [MAN-103](https://linear.app/skyholding/issue/MAN-103/epic-add-period-dashboard-notifications-and-explainable-insights) | [Epic] Add period dashboard, notifications and explainable insights | FR-02 | Backlog |
| [MAN-104](https://linear.app/skyholding/issue/MAN-104/epic-add-optional-consented-sheets-and-provider-integrations) | [Epic] Add optional consented Sheets and provider integrations | FR-22 | Backlog |
| [MAN-105](https://linear.app/skyholding/issue/MAN-105/epic-isolate-affiliate-commissions-and-payouts) | [Epic] Isolate affiliate commissions and payouts | FR-23 | Backlog |
| [MAN-106](https://linear.app/skyholding/issue/MAN-106/epic-publish-accurate-help-and-privacy-separated-feedback) | [Epic] Publish accurate help and privacy-separated feedback | FR-24 | Backlog |

### 07 · Pilot and release

Measure security, privacy, accessibility, performance, reliability and signed-distribution evidence before selecting a release.

| Issue | Scope | Requirements | State at publication |
|---|---|---|---|
| [MAN-107](https://linear.app/skyholding/issue/MAN-107/epic-complete-measured-pilot-and-production-release-gates) | [Epic] Complete measured pilot and production release gates | NFR-01, NFR-02, NFR-03, NFR-04, NFR-05 | Backlog |

### 08 · Deferred enhancements

Separately gated P2 or optional features; excluded from the core release commitment.

| Issue | Scope | Requirements | State at publication |
|---|---|---|---|
| [MAN-108](https://linear.app/skyholding/issue/MAN-108/epic-opt-in-automatic-recurring-posting-p2) | [Epic] Opt-in automatic recurring posting (P2) | FR-13 | Backlog |
| [MAN-109](https://linear.app/skyholding/issue/MAN-109/epic-optional-weather-and-display-currency-providers) | [Epic] Optional weather and display-currency providers | FR-02, FR-21 | Backlog |

## Execution and review

Start with baseline integration, native lifecycle regressions, key-lifecycle protocol review, retention decisions and scope/ownership refinement. The strict TypeScript task is locally implemented and **In Review**; compilation, 42 web tests and a static production build passed. The baseline still requires repository review and actual hosted CI.

A capability epic is not a sprint-sized task. Before pulling one into implementation, create independently reviewable schema/API, strict TypeScript web, native Android, native iOS and integration/rollout children as applicable. Prefer a single small user flow or contract operation per change. Size after refinement and capacity confirmation; do not guess three-client feature estimates.

Use the issue's Linear branch suggestion or a short `feat/man-<id>-<scope>` branch from the reviewed base. Sequence backward-compatible schema/contract changes before consumers; keep optional providers behind disabled rollout controls until validated. Link every PR to its issue, requirement and evidence. A build passing alone does not make a feature complete.

For each task, require reviewed/integrated code, relevant negative/concurrency tests, updated runtime OpenAPI and cross-client behavior, accessible Indonesian UI where affected, privacy-safe telemetry and current docs. Record rollout/rollback and unrun gates. Never collect profile details, recovery material or financial descriptions in analytics.

Refine category master data before category-based transaction splits; budget-period behavior follows transaction accounting. This avoids a circular budget/transaction dependency. Allocation apply changes budget limits atomically; goal reservations and asset trades remain separate reviewed operations.

## Release scope

The pilot issue blocks on the P0 finance/household foundations. P1 capabilities are tracked without claiming they all fit the existing target. Selecting a release must explicitly include or defer each capability and carry its own tests; milestones express delivery order, not promised dates. P2 automatic posting and optional provider enhancements stay separate.

Source authority: [delivery map](delivery.md), [PRD](../ai-analyze/PRD-Palmy.md), [protocol](protocol.md), [privacy boundary](security.md), [validation evidence](validation.md), and [runtime OpenAPI](../contracts/openapi.json). The source reference audit is not Palmy release certification.
