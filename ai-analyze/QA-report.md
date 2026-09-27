# Palmy — reference application audit

Audit date: 26 September 2026, Asia/Jakarta. Application: [Seruma](https://seruma.app/), authenticated Chrome session. Proposed application name: **Palmy**.

## Result and scope

The audit exercised the principal household finance and coordination workflows with synthetic `PALMY QA R2` records and inspected all discovered in-scope top-level modules. It found a confirmed monetary precision defect, localization and accessibility defects, documentation conflicts, and two posting-destination product gaps. This was a black-box audit, not a source-code, backend-security or exhaustive state-space certification.

The [163-row inventory](coverage.csv) records each scenario's result. [Status counts](coverage-summary.md) distinguish executed checks, inspected controls, blockers, explicit execution gaps and exclusions. A module being opened does not mean all its paths passed. It is not accurate to claim that every possible scenario was checked or that the app is bug-free.

Excluded exactly as requested: Berdua and descendants, Conversation Cards, Jurnal Keluarga. One transaction-filter interaction unintentionally navigated to Berdua; it was immediately abandoned and no excluded workflow was exercised or changed.

## Findings

| ID | Severity | Finding | Evidence and reproduction | Expected Palmy behavior |
|---|---|---|---|---|
| BUG-01 | P1 | Shared expense changes accepted amount | Manual expense 1234.56; All/shared members at 50/50; saved rows 618 and 617. Sum 1235 differs by+0.44. Edit retained the split amounts. | Preserve 1234.56 exactly;617.28 each at two-decimal scale. Round only through an explicit currency policy. |
| BUG-02 | P3 | Overpayment validation is not localized | Create receivable 2000; submit payment 2001; error is `amount exceeds remaining balance`. Validation itself works. | Localized field message with current remaining amount. |
| BUG-03 | P2 | Controls lack usable accessibility semantics | Grocery/checklist checkbox and several edit/header icons unnamed; sortable cards announced disabled although pointer activation works. | Labeled checkbox/buttons; disabled means actually disabled; keyboard operation and focus verified. |
| BUG-04 | P2 | Help contradicts settings | FAQ describes 6-digit PIN at app open, while settings describe 4–6 digits for sensitive links/reset. Currency and child-access descriptions also disagree with observed settings/backlog. | Help versioned with implemented PIN scope, display-currency behavior and supported roles. |
| GAP-01 | P2 | Grocery checkout has no wallet selection | R2 Milk 2×1000 checked out for 2000; no wallet selector; posted to primary wallet. | Wallet or record-only choice is explicit in checkout review. |
| GAP-02 | P2 | Maintenance cost has no wallet selection | R2 Bicycle chain service 1000 saved; expense posted to primary wallet without choice. | Explicit wallet or record-only service entry. |

P1 denotes material data-integrity impact; P2 denotes significant usability/accessibility or functional gap; P3 denotes minor presentation. The wallet-selection gaps are product recommendations grounded in the observed flow, not a claim that a supplied written requirement was violated. The app's public feature board also contains a request for wallet selection in these flows.

## Selected successful scenarios

- Transfer 1000 plus fee 50: source−1050, destination+1000, separate fee 50.
- Credit limit 10000/opening used 2000; repayment 500 leaves 1500 outstanding.
- Multi-category expense 100+200: two linked rows total 300; missing category rejected; shared-member split disabled in this mode.
- AI salary prompt 3000: parsed draft reviewed, QA wallet selected, saved income found in history.
- Receivable 2000, partial payment 500, archive and restore: remaining 1500 and preserved history.
- Goal target 10000; reserve 1500, release 500, link asset 1500: final progress 2500/10000=25%.
- Asset buy 2×1000, quote 1500, sell 1×1500: remaining 1 unit with value 1500 and cost 1000. Unit-correction preview preserved basis and was cancelled.
- Recurring 250 monthly template: reviewed posting increased record count to 1.
- Grocery checkout 2000 and vehicle service 1000 appeared in finance history.
- Calendar event saved; checklist category/item created; completion 0/1→1/1→0/1 verified.
- Person and date/category filters returned expected records; filter reset and pagination 1→2→1 passed. Portfolio targets clamped 110 to 100 and prevented save at 50; card/compact views passed.
- Education 1000000×1.1²=1210000; zero-interest loan 1200000/12=100000/month.
- Reporting tabs and periods, amount masking, valid report workbook and selective backup workbook checked.

These examples use synthetic amounts. Existing private household balances and transactions are deliberately not reproduced in the deliverables.

## Environmental and consequential-action boundaries

| Boundary | What was done | Remaining gate |
|---|---|---|
| File upload | Downloaded transaction template; generated valid 321.09 and invalid−1 XLSX files; upload chooser rejected access | Enable Chrome extension Allow access to file URLs, then run import/OCR/attachment matrix |
| Credentials | Required fields and disabled submission states inspected | User-controlled credential lifecycle on a disposable identity |
| Permanent deletion/reset | Wallet scope, PIN guard, password and HAPUS account guard inspected; cancelled | Disposable tenant and explicit action-time authorization before final destruction |
| Membership | Profile and invitation surface inspected | Two test identities and authorized invitations/revocations |
| OAuth/permissions | Google Sheets disconnected state, notification/location/install controls inspected | Test provider accounts and authorized scope/permission grants |
| Affiliate/payment | Dashboard, minimum, bank and payout forms inspected | Provider sandbox, synthetic bank data and approved payout scenario |
| Public feedback/contact | Validation and status views inspected | Explicit request to publish a synthetic post, vote, promotion or message if needed |
| Backend correctness | Visible arithmetic and retained diagnostics checked | Source/staging access for isolation, concurrency, rollback, rate limiting and fault injection |

No bank transfer, real investment trade, external payment, public post, invitation or message was sent. Financial actions performed in Seruma were bookkeeping records.

## Remaining execution matrix

The inventory explicitly preserves incomplete branches. They must not be relabeled passed to achieve a numerical coverage target. In staging, finish:

1. Remaining transaction filter combinations and multi-row sorting; manual-only income; copy-to-draft; fees and person splits; zero/negative/precision/overflow; duplicate click/retry; concurrent edit and correction.
2. Wallet ownership/visibility, category restrictions, reorder, credit overpayment/limit adjustments, archive and recovery; invalid due days and nested category constraints.
3. Debt borrowing/credit-goods variants, full settlement, interest/fees, non-wallet records; every goal contribution mode and oversubscription protection.
4. Each asset class with provider data, stale/outage quotes, full disposal/oversell, dividends/maturity, saved allocation targets, bulk quote changes and rebalance application.
5. Save/apply allocation plans, yearly recurrence, due-day edge cases, recurring retry and duplicate occurrence guards.
6. All calculator rate models with independent amortization fixtures, saved scenarios and extreme inputs; report totals for opening balances, transfers, principal, fees and gains.
7. Grocery history/reorder/price comparison, home/electronic service histories, calendar recurrence exceptions/time windows/edit scopes and actual reminder dispatch.
8. File type/size/malware/permission errors, OCR uncertainty, batch maximum 10/11, import mapping/duplicates/partial failures/rollback and export round-trip restore.
9. PIN expiry/lockout, membership isolation, OAuth disconnect, notification opt-out, links protocol safety, public-feedback permissions and affiliate payout races/reversals.
10. Full keyboard/screen reader review, contrast, mobile modals, Safari/Firefox, offline recovery, slow networks, service restart, backups and recovery under a declared load.

## Diagnostics and evidence limits

Home was tested at viewport widths 320,768,1024,1440,1920; root scroll width equaled viewport width. Bottom navigation target sizes were 57×48 at 320 and 78×48 at wider layouts. Other screens were inspected in the default centered layout; this is not a full responsive or accessibility certification.

The retained console warning/error buffer was empty. A retained network window contained no HTTP status≥400 or loading failures, but the event buffer was truncated. This cannot establish that the entire session was error-free. Observed async refreshes required waiting for persisted state; transient empty data immediately after navigation was not classified as a defect.

The automation snapshot includes some clipped/collapsed forms and several sortable cards marked disabled. The filter footer could be clipped beneath fixed navigation at 810 px and 1100 px heights. Native date-picker selection and keyboard Reset/Apply ultimately verified those paths. Some locator clicks scrolled controls beneath the fixed navigation; results were treated as inconclusive until a visible state confirmed the outcome. Failed automation alone was not reported as an application bug.

Zero expense was rejected. Typing−1 visibly normalized to 1; it was not submitted. This sign-removal behavior is a usability observation, not evidence of a negative posted record.

Report export succeeded despite a download-event timeout: the new XLSX file existed with matching creation time and a valid `Laporan` sheet. The selective backup contained exactly `Transaksi`, `RiwayatServis`, `PortofolioAset`, `RiwayatPembelianAset`, `UtangPiutang`, `Goal`, `Agenda`. Neither private export is copied into this package. The downloaded transaction template columns are date, category, wallet, subcategory, need/want, description, amount and optional time.

## Retained fixtures and restoration

New data remains clearly labeled with `PALMY QA R2`: Cash and Credit wallets; transfer/fee; shared expense rows; AI income; multi-category expense rows; Budget/Sub; Borrower receivable/payment (restored active); Goal/contribution/release/note; Asset/purchase/quote/sale/goal link; Recurring template/posting; grocery section/Milk purchase/Rice routine; Event; Tasks category/Checklist (unchecked); Bicycle/service; Air Filter; Device; Documentation link pointing to example.com.

The grocery and service scenarios recorded 3000 total against the primary wallet because those forms lacked a selector. They are synthetic bookkeeping entries, not real spending. Existing pre-R2 QA fixtures were not removed. Permanent cleanup was not performed. If cleanup is later authorized, reverse linked financial operations before removing synthetic containers, verify balances against the opening snapshot, and preserve real records.

Display currency was restored toIDR, budget cycle to day 1, and viewport override cleared. Backup selection remains the seven in-scope groups; category display remains list view. Goal-link and receivable restore changes intentionally remain as test results.

## Package validation

See [validation.md](validation.md) for checks actually run on the proposed OpenAPI, SQL and documentation artifacts. Those checks validate the design files; they do not validate Seruma's implementation.
