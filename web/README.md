# Palmy web

Next.js 16.3.6 and React 19.3.0, pinned from the official npm registry. The App Router exports static files; account and financial screens render entirely in the browser. There are no Next.js API routes or account sessions on the web server.

```sh
npm ci
cp .env.example .env.local
npm run dev
```

Web: `http://localhost:3100`. API: `http://localhost:8100`. Set `NEXT_PUBLIC_API_URL` before building; it is a public API origin, never a secret. Production API URLs must use HTTPS. The API must allow the web origin explicitly in CORS.

```sh
npm run typecheck
npm test
npm run build
npm start
```

TypeScript uses `strict` together with unchecked-index checking, exact optional properties, explicit return-path checking, switch fallthrough protection, explicit overrides, index-signature access checking, and consistent filename casing. `npm run typecheck` generates Next's route types and checks application code, tests, environment declarations, and `next.config.ts`. Missing optional fields are omitted rather than written as `undefined`; parsed recovery fields and recorded test requests are checked before use.

`npm start` is a local static preview at port 3100. Deploy `out/` to an HTTPS static host. Configure no-referrer, nosniff, frame-ancestors 'none', a Content Security Policy restricted to your own scripts and configured API origin, and no third-party analytics/scripts. Next's inline bootstrap requires build-specific script hashes in a strict CSP; the local preview is not a production server.

The implemented product slice includes create/recover account, encrypted profile, wallet creation, exact income/expense posting, lifetime totals, paginated transactions, profile version conflicts, and session revocation. Broader product features in `../ai-analyze` remain roadmap scope.

The recovery key gives full account access. The browser keeps secrets and access tokens in memory and does not use localStorage, sessionStorage, IndexedDB, cookies, or service workers. Reloading requires recovery. Explicit locking revokes the session and releases local keys; network failures show that revocation did not complete. Browser garbage collection cannot guarantee immediate erasure of all memory copies. Only profile fields are encrypted; financial text and metadata remain readable and can identify someone. Do not put identifying information in wallet names, categories, or descriptions.

Cryptography is defined in `../docs/protocol.md` and tested against independently generated `../contracts/crypto-vectors.json`. Helpers in `src/lib/crypto.ts` use Web Crypto HKDF/AES-GCM and noble Ed25519. Tests also exercise tamper rejection, account context binding, recovery input validation, exact money, and API owner context checks.
