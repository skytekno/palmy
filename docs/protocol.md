# Palmy identity and finance protocol v1

This is the implementation contract for the first slice. The `ai-analyze` package is the broader product design, not a list of implemented endpoints. Authentication and finance paths are relative to `/api/v1`; operational paths are absolute. JSON uses snake_case. Success responses wrap the payload in `{ "data": ... }`; lists put arrays in `data`. Failures are RFC 9457 problem JSON with `status`, `title`, `code`, and a server-generated `request_id`. All account responses are `Cache-Control: no-store`.

## Client identity

Clients generate a random UUID v4 `account_id` and a cryptographically random 32-byte master secret. Recovery format is `palmy1.<lowercase UUID>.<unpadded base64url master secret>`. This is a full-access secret. Never send it, its derived secret keys, or unencrypted profile fields to the API. Never put it in a URL, log, analytics event, or browser persistent storage. Web keeps it and the session in memory until locked. Native apps may wrap it using platform secure storage with backups disabled.

Derive independent 32-byte keys using HKDF-SHA256, salt UTF-8 `palmy:v1`, info UTF-8 `palmy:profile:v1` (AES key) and `palmy:signing:v1` (Ed25519 seed). Ed25519 public keys are raw 32-byte unpadded base64url. Use standard libraries: Web Crypto HKDF/AES-GCM plus noble Ed25519; CryptoKit on iOS; JCA AES-GCM/HMAC with Bouncy Castle Ed25519 on Android. Protocol test vectors are shared in `contracts/crypto-vectors.json`.

Profile plaintext is UTF-8 JSON `{ "display_name": string, "email": string }`. Future personally identifying fields must join this envelope; do not introduce plaintext identity columns. AES-256-GCM uses a fresh cryptographically random 12-byte nonce per encryption, a 128-bit tag, and UTF-8 AAD `palmy:profile:v1:<account_id>`. `ciphertext` contains ciphertext followed by the tag. Envelope: `{ "version": 1, "algorithm": "A256GCM", "nonce": base64url, "ciphertext": base64url }`. API validates shape and size, never decrypts it. This authenticates profile ownership/context, not anonymity of readable transaction content.

## Authentication API

* `POST /accounts`: `{account_id, public_key, profile, signature}`. Signature is Ed25519 over UTF-8 `palmy:register:v1:<account_id>:<public_key>:<nonce>:<ciphertext>` using profile envelope fields. Return 201 `{data:{account_id}}`. Account ID and public key are unique. Registration does not create a session. No email lookup or password reset service.
* `POST /auth/challenges`: `{account_id}`. Return `{data:{challenge_id, nonce, expires_at}}` even for an unknown UUID, with equivalent shape. Challenge UUID, random 32-byte nonce, 120-second lifetime. Store authoritative challenge in PostgreSQL; limit global issuance and per-account issuance using Valkey/Redis. Do not log account ID, token, nonce, public key, or bodies.
* `POST /auth/sessions`: `{account_id, challenge_id, signature}`. Sign UTF-8 `palmy:auth:v1:<account_id>:<challenge_id>:<nonce>`. Atomically consume the challenge once, verify account binding/expiry/signature with Ed25519, then return `{data:{access_token, expires_at}}`. Opaque 32-byte token, 1-hour TTL; only SHA-256 digest stored in PostgreSQL. A replay or incorrect/expired proof returns 401. Use `Authorization: Bearer <token>` on subsequent requests. Sessions rechecked against database, never positive-auth cached.
* `DELETE /auth/session`: revoke this session, return 204.
* `GET /profile`: authenticated caller's `{data:{account_id, profile, version}}`.
* `PUT /profile`: `{profile, version}`; use conditional version update; return incremented version; stale version 409. Owner derived exclusively from session.

## Finance API

API accepts at most 16 integer digits and exactly zero, one or two fraction digits in positive money strings; returns canonical two-decimal strings. PostgreSQL uses NUMERIC(18,2), Rust uses checked integer minor units. IDR v1 follows the source design's two-decimal accepted input (1234.56 must stay 1234.56). No binary float money. User-provided `owner_id` or unknown fields are rejected.

* `GET /wallets`: return all own wallets, at most 100, `{id, name, balance, currency}`. Currency is `IDR`.
* `POST /wallets`: `{name}` with `Idempotency-Key` UUID. Return 201 wallet with balance `0.00`. Name 1–80 trimmed characters. Wallet creation limit 100/account. No direct balance writes.
* `GET /transactions?limit=25&before=<optional UUID>`: own recent transactions in descending created_at/id order, default 25/max 100, `{data:[...], next_cursor: UUID|null}`. Transaction: `{id,wallet_id,kind,amount,category,description,effective_on,created_at}`. `kind` income/expense. Filter cursor to owner; unknown/inaccessible cursor 400.
* `POST /transactions`: `{wallet_id,kind,amount,category,description,effective_on}` with `Idempotency-Key` UUID. Category 1–60 characters, description up to 280, date `YYYY-MM-DD`. Create immutable journal with balanced wallet/counterparty postings; balance is sum of wallet entries. Same key/body returns original transaction, changed body 409. Enforce owner check in the write transaction, composite owner foreign keys, and database RLS with non-owner runtime role. Inaccessible wallet 404. Posted edits/transfers/household sharing are future slices, not partial implementations.
* `GET /summary`: `{data:{balance,income,expense,currency:"IDR"}}` with lifetime totals. Optional short-lived cache uses owner ID AND authoritative per-owner ledger revision read from PostgreSQL, so old cache values cannot become current after a commit. Always authenticate before cache lookup. Financial read cache contains no profile or authentication data. No cache needed on mutable lists.

`GET /health/live`, `GET /health/ready`, and `GET /openapi.json` are public. Readiness checks PostgreSQL migrations and Redis/Valkey. Request body limit 16 KiB. Private responses are bounded by the 100-row limit and field/envelope size limits; the OpenAPI document is separately public. Development CORS uses an explicit origin allowlist. Production HTTPS is required; web uses a configured public API URL, native uses platform network policy.

## Shared client design

Indonesian UI, IDR display and Asia/Jakarta date defaults. Palette: canvas `#F5F7F2`, surface `#FFFFFF`, primary `#214E3B`, primary-soft `#E5EDE5`, accent `#D6F078`, ink `#15291F`, muted `#68776E`, border `#DFE6DF`, danger `#A63434`. Soft rounded cards, clear native typography, visible labels and touch targets. Main implemented destinations: Beranda, Keuangan, Profil. Product roadmap retains Home/Finance/Calendar/More; do not present unimplemented modules as functional.

Start at create/recover account. Creation encrypts display name/email locally, submits only envelope/public key, shows recovery key with explicit keep-safe acknowledgement, and authenticates. Recovery imports that same key on any client, signs a fresh challenge, fetches and decrypts profile. Signed-in clients show live summary/wallets/transactions, create a wallet, add income/expense, edit encrypted profile, and lock/revoke the session. Distinguish loading, empty, error and saved states. Never display synthetic finance as live account data. Explain at data entry that finance/category/description remain readable and should omit personal details.
