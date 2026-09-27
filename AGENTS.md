# Working on Palmy

This checkout is `skytekno/palmy`. Its runtime folders are `/api` (Rust/Axum), `/web` (strict TypeScript Next.js with client rendering), and `/mobile/android` plus `/mobile/ios` (native Kotlin/Compose and SwiftUI). Historical Flutter or `apps/api` guidance belongs to a different checkout.

## Sources and scope

- Read `docs/delivery.md` and the relevant Linear issue before changing behavior. `docs/linear-plan.json` is a dated publication snapshot; Linear holds current task status.
- `contracts/openapi.json` is generated from the implemented Rust API. `ai-analyze/openapi.json` is a proposed full-product design, not a live contract. Preserve the supplied `ai-analyze` artifacts and checksums.
- Match the Indonesian interface, IDR bookkeeping and shared `design/tokens.json`. Keep native platform behavior and accessibility intact.

## Invariants

- Keep TypeScript `strict` and every additional check in `web/tsconfig.json` enabled. Fix type errors at their source; do not introduce `any`, blanket suppressions or disabled checks to make a build pass.
- Profile details and recovery material remain client-side or encrypted. Finance remains readable but owner-authorized. Never promise guaranteed anonymity from transaction content or metadata.
- Never log tokens, keys, profile plaintext, receipt contents or financial descriptions. Never commit local environment files, credentials, database dumps or real user records.
- Use exact decimal strings at API boundaries and integer minor units for arithmetic. Preserve totals exactly, balanced immutable journals, owner isolation, durable idempotency and version checks.
- Changes to money and its originating domain record must commit together. Corrections use reversal/replacement rather than rewriting posted history.

## Delivery

- Develop a bounded issue on a short-lived branch from the reviewed base. Use Conventional Commits and link the Linear issue in the PR.
- Run `make check` for API/web changes. Run `make integration` against disposable local infrastructure and `npm run test:browser` for affected end-to-end flows. Native commands are in `mobile/README.md`; native state changes need lifecycle/retry regressions.
- Fix relevant failures, inspect the final diff and identify environment-only or external gates. Local passes, hosted CI, independent security review and production readiness are separate evidence.
- New credential protocols stay design-only until their stated review and interoperability gates are satisfied. Do not silently enable deferred providers, automatic posting or excluded product modules.
