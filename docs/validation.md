# Validation evidence

Executed locally on 27 September 2026. This record covers the new Palmy implementation, separately from the reference-application audit in `ai-analyze`.

The first table records the baseline implementation and first delivery wave. The subsequent foundation-controls results supersede the affected counts and gates.

| Check | Result | Evidence / command |
|---|---|---|
| Original source integrity | PASS | All 18 SHA256-listed input artifacts unchanged; original structural validator passed on a temporary copy (154 operations, 180 schemas, 62 tables, 163 audit rows). |
| Shared crypto fixture | PASS | `node scripts/crypto-vectors.mjs --check`; independent Node HKDF/AES-GCM/Ed25519 fixture. |
| Rust formatting / lint | PASS | `cargo fmt --all -- --check`; `cargo clippy --locked --workspace --all-targets -- -D warnings`. |
| Rust unit tests | PASS, 8 tests | Money boundaries, signature/context/shape checks, shared signatures, contract security, bounded errors and cache timeout. |
| OpenAPI | PASS | Runtime generator drift check plus `openapi-spec-validator==0.9.0` metaschema validation of OpenAPI 3.1.0; 14 implemented operations including health/schema routes. |
| Web typecheck / tests | PASS, 42 tests | Strict TypeScript and independent crypto/recovery/money/API/immediate-lock checks. Revalidated after enabling checked indexing, exact optional properties, return/fallthrough/override/index-signature/casing checks and including Next configuration. |
| Web production build | PASS | Next.js 16.3.6 static export; authenticated application uses `ssr: false`; no server profile rendering. |
| API integration | PASS, 70 HTTP assertions | `scripts/integration.mjs` against native Rust process, then rebuilt container. Fresh independent Node crypto identities and actual PostgreSQL/Valkey. |
| PostgreSQL invariants | PASS | `scripts/database-check.mjs`: nonprivileged role, no-context RLS, cross-owner reads/writes/FKs, precision, deferred balance enforcement, immutable postings, no plaintext identity columns. Fixtures roll back. |
| Privileged runtime refusal | PASS | API exits before listening when configured with migration-owner credentials; startup output remains bounded. |
| Containers | PASS | `docker compose config --quiet`, image builds, successful one-shot migration, restricted API startup, dependency readiness and repeated live integration suite. |
| Browser end-to-end | PASS | Chromium at desktop 1440px and mobile 390px; extra 320px overflow check. Actual API, no mocked account or finance responses. |
| Swift native tests | PASS, 19 tests, zero skips | `PALMY_TEST_API_URL=http://127.0.0.1:8100 swift test`; 13 actual-model lifecycle/auth/retry regressions plus crypto, validation and live API interoperability. |
| iOS builds / UI lifecycle | PASS, 2 UI tests, zero skips | Debug and unsigned Release simulator builds with Xcode 27; actual SwiftUI onboarding/background and authenticated-background locking on iPhone 17 Pro, iOS 26.5. See [iOS validation](../mobile/ios/README.md). |
| Android native tests | PASS, 21 tests, zero skips | 15 actual-model lifecycle/auth/retry regressions plus shared vectors, validation and actual API interoperability. |
| Android activity lifecycle | PASS, 4 tests, zero skips | Actual MainActivity background/recreation and delayed authentication scenarios on Android 16/API 36 arm64 Pixel 9 emulator; see [Android validation](../mobile/android/TESTING.md). |
| Android build / lint | PASS | Debug APK, unsigned Release APK, instrumentation APK and lint with AGP 9.1.1. **0 errors, 9 warnings**, all newer-version/target-SDK advisories; no blanket lint suppression. |
| Credential lifecycle proposal | PASS, 25 reference cases | `node scripts/lifecycle-check.mjs`; deterministic proposal fixtures and reference state transitions. This is not runtime implementation, HPKE interoperability, PostgreSQL concurrency validation or independent cryptographic review. |
| Final file review | PASS | Original inputs retained, generated secrets ignored, new text whitespace checked, generated API contract current, scoped independent API/web/native reviews completed. |

## Foundation controls: MAN-117, MAN-120 and MAN-121

Executed on 27 September 2026 against the branch based on merged `4132be9`. Runtime money, profile encryption and native application behavior are unchanged; production delivery configuration now fails closed.

| Check | Result | Evidence / boundary |
|---|---|---|
| Complete API/web checks | PASS | `make check`: four remote-Docker preflight cases, existing crypto/25 lifecycle reference cases, generated OpenAPI parity, Rust fmt/Clippy, **12 Rust tests**, strict TypeScript, **63 web tests**, static export. |
| OpenAPI metaschema | PASS | OpenAPI 3.1 validation; still 14 implemented operations. Erasure proposals are excluded from runtime OpenAPI. |
| PostgreSQL and HTTP | PASS | `make integration` against rebuilt API container: database invariants plus **77 real HTTP assertions**, including exact-origin CORS and private-response headers. |
| Real-API browser privacy | PASS | Chromium desktop/mobile flow with actual Rust/PostgreSQL and correlated API request IDs across two captured log files. Profile/recovery/token and financial-description canaries absent from logs, browser console, URLs, referrers and export files. |
| Trusted HTTPS delivery | PASS | Actual production export in Firefox with a disposable trusted CA and synthetic API; untrusted CA rejected, CSP positive flow and negative execution/exfiltration/framing checks, release integrity, cache/header/Host/path boundaries and privacy scans. See [delivery evidence and limits](web-delivery.md). |
| Encrypted backup and restore | PASS, 137 checks | Two isolated fresh PostgreSQL clusters; encryption tamper/wrong-key/truncation refusal, role/RLS/ledger/profile/auth reset and concurrent idempotency checks. Normal and deliberately failed runs clean up only owned resources. See [measured drill](backup-restore.md); production recovery objectives remain unproven. |
| Erasure refinement | Reviewed proposal | 38 unique future cases, all mapped to 13 unestimated Backlog tasks MAN-124–136 with acyclic blocking links. These are not implemented or passing runtime erasure tests. Policy/specialist acceptance remains open. |
| Source integrity | PASS | All 18 original `ai-analyze` checksums unchanged. |

CI now runs the trusted HTTPS browser check and both backup success/failure exercises, in addition to the existing native jobs. Native implementation is unchanged in this wave; hosted results must be checked against the final candidate commit. Local TLS evidence does not substitute for a real staging hostname, API TLS gateway, edge telemetry configuration or independent security review.

## Scenarios exercised

The API checks register two separate encrypted identities, require proof of possession, consume challenges once (including a concurrent race), reject invalid/unknown proofs, decrypt profiles only with the client key, enforce profile versions, reject unknown plaintext fields, isolate wallets and transactions, reject foreign wallet access, reject invalid/excess-precision amounts, replay identical idempotency keys, reject changed bodies, prevent six concurrent retries from duplicating an expense, preserve `2000.00 - 1234.56 = 765.44`, reject foreign cursors, update cached summaries after posting and reject revoked sessions.

The browser checks recovery acknowledgement **before** registration, creates a wallet and both transaction directions, rejects excess precision, edits the encrypted profile, recovers the same account in a separate mobile context, checks that reload loses unlocked access, and verifies local locking within 1.5 seconds while the real revocation request is deliberately delayed. It asserts no profile plaintext or recovery text in outgoing URLs, headers or bodies, no cookies/localStorage/sessionStorage credentials, and no uncaught browser errors. Synthetic financial amounts remain readable on the wire as intended.

Desktop welcome/dashboard and mobile dashboard screenshots were inspected; no horizontal overflow was observed at 320 or 390 pixels. Local screenshots are under ignored `artifacts/local/`. Native automation covers the lifecycle scenarios above; the complete native interaction and accessibility matrices remain open. Android disables screenshot capture; no Android visual interaction audit is claimed.

## Defects found and fixed during validation

- Real PostgreSQL execution found a PL/pgSQL CASE-expression syntax error in the balance trigger. Fixed before the first successful migration; both valid and unbalanced journals subsequently exercised.
- Browser testing found recovery textarea contents included in the implicit accessible label. Controls now use explicit label associations and separate help descriptions.
- Independent review found web locking awaited a slow network response. Keys/UI now clear immediately, and delayed revocation cannot alter a newer login. Unit and delayed-transport browser tests pass.
- Native review found unstable Swift request equality, stale asynchronous login/logout feedback, background sign-in cancellation gaps, and retries after committed writes whose refresh failed. Both clients now use stable retry identity, cancellation/generation guards and separate committed-write feedback. Controlled model regressions exercise delayed responses and retry outcomes; native simulator/emulator tests exercise actual lifecycle callbacks.
- Android lint crashed inside AGP 9.1.0 Kotlin FIR. Updating to 9.1.1 restored lint execution; it then found and verified fixes for explicit local-network subdomain policy, backup exclusions and the application icon.

## Repeat the checks

```sh
make setup
make infra migrate
make check
uv run --with openapi-spec-validator==0.9.0 python scripts/check-openapi.py
```

Run the API (`make api`) and static web (`npm --prefix web start`) in separate terminals, or use the API container. Then:

```sh
make integration
npx playwright install chromium
npm run test:browser
```

Native commands and environment details are in [mobile/README.md](../mobile/README.md). Synthetic HTTP/native/browser test accounts remain in the **local development database**; they are separate accounts from any user-created data. The direct SQL test rolls back its fixtures. No reference app or production database was modified.

## Unrun and future gates

The tables record local evidence; hosted results must be checked against the candidate commit in GitHub PR checks. Hosted native tests explicitly skip live API cases when their API environment is absent; the baseline local runs above supplied it. Firefox delivery is now exercised with a synthetic API; Safari and the broader cross-browser matrix remain open. Physical devices, complete native UI automation, screen-reader/large-text testing, release/store signing, staging/production TLS and edge configuration, load benchmarking, representative production recovery, independent cryptographic review, key rotation/device persistence and full account lifecycle remain gates. There is no claim of measured production performance, guaranteed anonymity, complete accessibility conformance or production readiness.

The remaining product operations are designed in [delivery.md](delivery.md) and `ai-analyze`; their presence in those documents is not runtime implementation or passing-test evidence.
