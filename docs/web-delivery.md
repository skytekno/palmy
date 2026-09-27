# Web delivery and telemetry boundary

MAN-120 supplies an executable production delivery boundary for the existing Next.js **static export and client-rendered application**. The API still owns readable financial data, while the browser encrypts the profile and holds keys and sessions only in memory. This is local, synthetic validation, not a deployed staging or production environment. Public traffic remains gated on the endpoint and operational evidence below.

## Build and serve

Use the pinned Node toolchain in CI (Node 24) and install the committed dependency lock with `npm --prefix web ci`. The current minimum supported Node version is 22.12; the delivery entrypoints explicitly enable Node's TypeScript stripping, and `npm --prefix web run typecheck` independently checks them with all strict flags. No Next server, SSR profile rendering, or framework middleware runs in production.

Set these values through the deployment's configuration/secret mechanism:

| Variable | Requirement |
| --- | --- |
| `PALMY_ENV` | `production`, also the delivery command default. `development` is rejected. |
| `PALMY_WEB_ORIGIN` | Exact canonical HTTPS origin, such as `https://palmy.example.com`. No trailing slash, path, credentials, query, fragment, wildcard, uppercase alias, or explicit default port. |
| `NEXT_PUBLIC_API_URL` | Exact canonical HTTPS API origin; intentionally public and compiled into the browser bundle. It is an origin, not an `/api/v1` URL. |
| `PALMY_TLS_CERT` | PEM leaf certificate followed by its required intermediate chain. The leaf must match the web hostname and be within its validity interval. |
| `PALMY_TLS_KEY` | Matching PEM private key, provisioned outside `out/` and the repository. |
| `PALMY_BIND_HOST` | Defaults to `127.0.0.1`; change only as part of a reviewed network deployment. Port comes from the canonical web origin, defaulting to 443. |

With those variables configured, run:

```sh
npm --prefix web ci
npm --prefix web run typecheck
npm --prefix web test
npm --prefix web run build:delivery
npm --prefix web run serve:delivery
```

`build:delivery` validates both origins before starting Next, disables Next build telemetry, adds SHA-256 SRI to initial script/stylesheet/preload assets, and emits `out/delivery-manifest.json`. The manifest binds the origins, dependency-lock digest, exact served file digests, and CSP. The normal `build`/`start` commands remain local preview commands and do not create a production manifest. A failed delivery build removes the old manifest before rebuilding. Do not mix the `out/` directory from separate exports.

The TLS server verifies the configuration, manifest, CSP and every served byte before listening. It rejects symlinks and holds the verified release in memory, so later file replacements cannot silently change responses. Only `/`, `/index.html` and the manifest's `/_next/static/` assets are served. RSC files, framework error pages, source maps, the manifest, arbitrary files and API paths are not exposed. Only GET/HEAD are accepted. Queries, encoded paths, traversal, unrecognized Host and foreign Origin headers receive generic errors; forwarded headers are not trusted. Default TLS minimum is 1.2. The server does not listen on plaintext HTTP.

This server terminates TLS itself. A load balancer must pass TLS through, or its separate TLS termination, downstream trust, header policy and logging configuration must receive new review and live tests. Do not add a plaintext backend or trust `X-Forwarded-*` by assumption. It does not manage certificate issuance/renewal, application firewall rules, rate limiting, or deployment orchestration.

## Browser policy and caching

The CSP denies resources by default. Scripts load only from this origin or exact SHA-256 hashes of the export's necessary inline bootstrap scripts. There is no script `unsafe-inline` or `unsafe-eval`; inline event handlers, frames, workers, objects, base URLs and form submission are denied. Styles use local stylesheets or exact inline block hashes; style attributes are denied. Fonts and images are local. `connect-src` contains only the configured HTTPS API origin. No CSP reporting endpoint receives page URLs or blocked content.

Hashes are computed from the final HTML's exact UTF-8 script/style content using an HTML parser, rather than a nonce that would require dynamic rendering. Initial resources also have browser SRI; dynamically loaded Next chunks rely on the TLS server's complete release verification and trusted HTTPS. Next's experimental SRI integration is not used. See [Next static exports](https://nextjs.org/docs/app/guides/static-exports), [Next CSP guidance](https://nextjs.org/docs/app/guides/content-security-policy), and [MDN script-src hashes](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/script-src).

Every application response includes framing denial (`frame-ancestors 'none'`, `X-Frame-Options: DENY`), `Referrer-Policy: no-referrer`, `X-Content-Type-Options: nosniff`, same-origin opener/resource policies and restrictive device permissions. HSTS is sent only by the TLS server, with a one-year max-age. It does not assume ownership of all subdomains or enroll a hostname in preload. HSTS has a first-visit boundary and does not apply to IP addresses; see [MDN HSTS](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Strict-Transport-Security).

HTML and error responses use `Cache-Control: no-store`. Next's content-addressed static assets use `public, max-age=31536000, immutable`. Deploy complete releases atomically and keep previously published immutable assets available through any CDN rollout window. API auth/profile/finance responses must retain `no-store` and must never enter an edge cache. Do not add a service worker or offline cache without a new privacy design.

## API origin and CORS contract

Set API `PALMY_ENV=production` and explicitly include the exact `PALMY_WEB_ORIGIN` in API `CORS_ORIGINS`. The API origin in the manifest, bundled `NEXT_PUBLIC_API_URL` and CSP must agree. The browser sends bearer tokens only in the Authorization header to that configured API; it uses `credentials: omit`, `cache: no-store` and `referrerPolicy: no-referrer`. CORS permits the explicit web origin, allowed methods and Authorization/Content-Type/Idempotency-Key headers. A denied origin must receive no permissive allow-origin response.

CORS is a browser boundary, not account authorization. Owner checks, challenge proofs, session expiry/revocation and row-level policies remain API requirements. A same-origin API reverse proxy is not implemented by this static server; use a separate canonical API origin for this deployment.

The Rust API listener currently speaks HTTP. A canonical HTTPS `CORS_ORIGINS` value does not enable API TLS. The production API origin requires a separately configured and verified TLS gateway or TLS deployment, including its private downstream network, request limits, cache and logging policies. That gateway is not implemented or deployed by this change. The local delivery test uses a TLS fixture API and does not establish that production API boundary.

## Telemetry and identity-correlation audit

The production server emits only categorical JSON: `event`, `result` (`document`, `asset`, `rejected`), numeric `status`, and `method` (`GET`, `HEAD`, `other`). It never emits URLs, Host, IP, headers, Referer, bodies, exception objects or TLS/parser errors. Startup failures use fixed messages. There are no browser analytics, session replay, crash upload, advertising, external font, push or provider SDKs in the implemented client. This avoids collecting identity-linked telemetry; it does not prevent a hosting operator observing network metadata.

| Surface | Current behavior and boundary |
| --- | --- |
| Name/email | Encrypted profile envelope in API payloads; plaintext only in the owner's client UI/memory. No SSR or HTML personalization. |
| Recovery material | Displayed locally after a user action; explicit copy uses the system clipboard. No key is put in a URL, storage, download filename, server log or analytics. Clipboard history/cloud synchronization is outside Palmy's control. |
| Bearer token | Memory and intended API Authorization header only. No cookies, query tokens or persistent browser session. |
| Financial text | Readable in intended transaction/wallet requests and API storage. Never copied into telemetry. User-entered identifiers can still reveal identity. |
| URLs/referrers | UI selection stays in client state; API query parameters contain only pagination controls. Static queries are rejected without logging/reflection. Document and API requests suppress referrers. |
| Files/push/providers | Uploads, receipts, exports, OAuth providers, payment providers and push subscriptions are unimplemented and disabled by the current resource policy. Their identifiers, EXIF/filenames, callback URLs, tokens and notification payloads need separate correlation review before implementation. |
| Edge/runtime operator | TLS peer addresses, timing, traffic volume and requested public assets remain observable. Cloud access/error/WAF/CDN logs, metrics labels, retention and support tooling require live configuration evidence; local tests cannot certify them. |

Dependency versions are locked, `npm ci` checks registry integrity, and the release manifest records the lock digest. These controls detect mismatched bytes, not a malicious dependency version that was intentionally locked. Dependency review, vulnerability checks and trusted CI/release provenance remain necessary.

## Executable local evidence

From the repository root, after `npm ci` and `npm --prefix web ci`:

```sh
npx playwright install --with-deps firefox
npm --prefix web run typecheck
npm --prefix web test
npm --prefix web run test:delivery
```

The delivery check builds the actual production export against dynamically allocated loopback HTTPS origins. OpenSSL creates a one-day CA and leaf certificate. Node validates that CA and rejects the same endpoint without it. Firefox first rejects the untrusted certificate, then imports only that CA into a disposable browser profile through a process-specific enterprise policy; there is no `ignoreHTTPSErrors`, certificate bypass, browser-install edit, global trust-store change, or `HOME` override. [Mozilla documents CA installation](https://firefox-admin-docs.mozilla.org/reference/policies/certificates/); [Playwright's Firefox policy hook](https://github.com/microsoft/playwright/blob/main/browser_patches/firefox/preferences/playwright.cfg) supplies the isolated policy path.

Checks cover the delivered headers, every served asset digest/cache rule, rejected Host/origin/method/path/query requests, unserved internal artifacts, registration acknowledgement, crypto proofs, exact finance, encrypted profile update, lock/recovery, and no unexpected CSP violation during the real UI flow. Deliberate probes exercise denied inline script, event handler, eval, connection to a separate trusted HTTPS origin and cross-origin framing. A synthetic API fixture verifies Ed25519 proofs and supplies finance responses; this is delivery evidence, not a replacement for real Rust/PostgreSQL integration tests.

Random canaries check profile plaintext, recovery strings, bearer tokens and financial descriptions across build/SSR output, browser console, delivery/fixture logs, URLs and referrers. The request allowlist permits only the configured web and API origins, with readable financial descriptions restricted to their intended POST. Local/session storage, cookies, Cache Storage and service-worker registrations are empty. The test retains no traces, screenshots or fixture payloads. CA keys and browser profiles use a private OS temporary directory, outside CI's uploaded artifact directory even if the job is killed. It writes a sanitized summary at `artifacts/local/delivery-evidence.json`, then deletes the CA, keys and browser profiles. Failure text redacts generated canaries.

Run this after the ordinary local browser suite, not concurrently with another web build. It restores the standard development export (`http://localhost:8100`) on completion. Disposable CI may set `PALMY_DELIVERY_RESTORE_DEV=0` to skip that final restore. Browser binaries may be cached using `PLAYWRIGHT_BROWSERS_PATH`; they are never copied into a release. Hosted CI and remote endpoint results must be recorded separately from local evidence.

## Release, rollback and remaining public-traffic gate

Build in trusted CI from a reviewed commit using locked dependencies. Preserve the commit, lock digest, manifest, export and validation evidence as one release. Provision TLS secrets separately. Start a new server against that complete immutable release, probe it with normal certificate verification, and switch traffic only after verification. Roll back by starting the prior complete release with its matching origin configuration and switching traffic back; never edit a live manifest, weaken CSP, or roll back only one chunk. Coordinate API compatibility and cached immutable asset retention across the switch.

Before public traffic, attach evidence from the actual staging hostname and edge: certificate chain/renewal, HTTPS redirects at any HTTP listener, full header and cache behavior including errors, origin/CORS and invalid-Host probes, build-to-release digest/provenance, privacy-safe logging/retention at every hop, and the same browser flow against that environment. Independent cryptographic/security review, backup/restore and deployment ownership remain open gates described in [security.md](security.md). The local delivery result does not satisfy that remote-evidence checkbox or make MAN-120 production-complete.

A malicious operator that controls delivered HTML/JavaScript, CI, the server or headers can replace both code and hashes and steal a key when the user unlocks. CSP, SRI, release digests and TLS protect specific delivery boundaries; they cannot guarantee secrecy from an actively malicious software distributor. Signed native distribution, reproducible releases and independent review can reduce that risk, but do not turn this web client into a trustless system. Encrypted profile data also does not make readable finance or connection metadata anonymous.
