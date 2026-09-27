# Privacy boundary and threat model

## What the design protects

Only user details are encrypted: initially display name and email. Clients encrypt before sending; the API has no profile decryption key. A database dump contains ciphertext and pseudonymous finance. A random recovery secret supplies independent encryption and authentication keys. The profile envelope uses AES-256-GCM, a fresh 96-bit nonce, a 128-bit tag and account-bound associated data. HKDF-SHA256 separates key purposes. Authentication uses Ed25519, never the encryption key. See [protocol.md](protocol.md), [RFC 5869](https://www.rfc-editor.org/rfc/rfc5869) and [RFC 8032](https://www.rfc-editor.org/rfc/rfc8032).

Financial data remains readable to the server as requested. The normal API serves it only to the account whose active session owns the rows. Authorization and encryption solve separate problems: keeping financial rows plaintext does not make them publicly accessible; encrypting profiles does not replace ownership checks.

| Threat | Control | Remaining boundary |
|---|---|---|
| Database-only profile disclosure | Client-only profile key; authenticated envelope | Key theft on a device or decrypted identity copied elsewhere bypasses this. |
| Another customer guessing a wallet/account | Database-verified session, owner predicates, composite foreign keys, RLS | Administrative database credentials can read plaintext finance. |
| Replayed sign-in | Random short-lived challenge, account binding, atomic consumption | A stolen live bearer token grants access until revoked/expired. |
| Duplicate expense from retry | Transactional idempotency, immutable balanced postings | User intentionally submitting a new command with a new key is a separate expense. |
| Cache leaks or stale balance | Authentication before lookup, owner/revision key, no profiles/auth cache | Cache administrators see cached readable financial totals. |
| Identity ciphertext moved between accounts | Account UUID in AES-GCM associated data | Server can delete/withhold data; encryption does not guarantee availability. |
| Sensitive details in telemetry | No payload/token/identity logging; bounded status/request IDs | Reverse proxies/hosting may independently retain IP, timing or user agent. Configure these separately. |

## What cannot be promised

“Nobody at Palmy can know who owns financial data” cannot be guaranteed while finance remains readable. Merchant names, transaction descriptions, precise times, rare amounts, payees, receipts and bank references may identify a person directly or through outside knowledge. Stable pseudonymous IDs reveal that records belong together. Network metadata, payment providers, push tokens, analytics and support conversations can connect those IDs to real people.

A malicious operator who controls the delivered web JavaScript can ship code that steals a recovery secret when it is entered. Client encryption does not defend against a compromised distribution channel or device. Native signed releases improve distribution separation but are also vulnerable to malicious updates and compromised devices. Independent security review, reproducible release processes, strong CSP, restricted third-party scripts and audits reduce these risks; they do not convert readable finance into anonymous data.

The UI therefore explains that profile details are private and finance is readable. Do not put names, phone numbers, account numbers, addresses or emails into finance descriptions or wallet names when identity privacy matters. The API cannot reliably detect all personal data in arbitrary readable strings. There is no plaintext email login, search, identity-provider link, support recovery, avatar URL or hidden identity hash in this implementation.

## Key lifecycle and recovery

Create a recovery secret with the platform cryptographic random source, never a human password or PIN. Recovery text is a **full account credential**, not merely a profile backup. Save it outside Palmy and keep it private. Knowing it allows both profile decryption and authentication from another client. Losing it and every unlocked device means Palmy cannot restore access or decrypt the profile. The server cannot reset it using email.

Web retains keys/session in memory and clears application state on lock or reload. Do not store them in localStorage, sessionStorage, URLs, analytics, service worker caches or logs. Native initial clients also keep access material in memory; retaining access between launches requires reviewed Android Keystore/iOS Keychain wrapping and backup policy. Managed runtimes cannot promise perfect erasure of prior memory copies. Copying/exporting a key exposes it to the chosen destination and should always be an explicit user action.

Profile edits encrypt afresh with a new random nonce. Nonce reuse with one AES key is forbidden. Authentication challenges and bearer tokens are random, bounded and expire; only token digests are stored. Lock attempts session revocation and clears local secrets even if disconnected; an unreachable server may retain that session until its one-hour expiry.

Device enrollment, credential rotation, account erasure, household recipient verification, recovery-key replacement and remote revocation of every device are **future capabilities**. Do not offer ordinary password reset as a substitute: that would break the stated privacy model. Cryptographic version changes must keep old envelopes readable until clients complete an explicit migration.

## Production review gates

Before handling real customer records, review the authentication protocol and implementations independently; verify cross-platform vectors and negative authorization tests; deploy HTTPS and restrictive web script policy; configure gateway abuse limits and retention; test backups and restoration; and implement reviewed lifecycle operations. Reference schema provider integrations and affiliate payouts require a separate disclosure model because they may reveal identity. No production anonymity, legal compliance or security certification is claimed by this repository.
