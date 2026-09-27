# Disposable PostgreSQL backup and restore drill — MAN-121

This exercises the implemented v1 API and database with synthetic records. It is evidence for [MAN-121](https://linear.app/skyholding/issue/MAN-121/execute-a-disposable-postgresql-backup-and-restore-drill) and NFR-05; it does not configure production backups, approve retention, or demonstrate production RPO/RTO. Development drill operator: **Codex**, under project lead **Rohman M**. A named production responder, storage owner and key-access approvers remain release gates.

## Run the complete drill

Prerequisites: Docker with Compose v2 on macOS/Linux, the repository's pinned Rust toolchain, Node.js 22 or later, and OpenSSL 3 with CMS AES-GCM support. Docker must be reachable through a local Unix socket and have capacity for two PostgreSQL 18.6 containers and two Valkey 9.1.2 containers. The script builds the local API; initial image pulls and compilation can take longer than a warm run.

```sh
node scripts/backup-restore.mjs
```

The command returns zero only when the exercise and cleanup pass. It prints bounded assertion counts, archive size and timings, never SQL/dumps, tokens, account IDs, profile plaintext, encryption keys or connection URLs. It does not load `.env`, accept a database URL/archive path, contact the normal development API, or reuse development volumes. Child processes receive a minimal environment with fixture-specific configuration. It uses a unique `palmy-drill-<random>` Docker project, explicit empty Compose environment file, isolated named volumes and ephemeral ports bound to `127.0.0.1`. API processes also bind ephemeral loopback ports. Database passwords are independently random for each cluster and runtime role.

The infrastructure definition is [ops/backup-drill.compose.yml](../ops/backup-drill.compose.yml); orchestration and assertions are in [scripts/backup-restore.mjs](../scripts/backup-restore.mjs). Run the script, rather than bringing up that Compose file with manually supplied credentials.

Preflight rejects SSH/TCP Docker endpoints before daemon contact, including explicit remote `DOCKER_HOST` even when a context would override it. Context inspection reads only local metadata. The selected local endpoint follows Docker's `DOCKER_CONTEXT` → `DOCKER_HOST` → configured-context precedence, must resolve to a Unix socket, and is pinned with `--host` for every subsequent command and cleanup. Remote current contexts are conservatively rejected even when a local host override is present. [Docker CLI environment precedence](https://docs.docker.com/reference/cli/docker/), [Docker contexts](https://docs.docker.com/engine/manage-resources/contexts/).

Run the no-daemon preflight regressions separately:

```sh
node scripts/backup-restore-preflight.mjs
```

These invoke the real drill with a fake Docker CLI, proving remote host, explicit/current remote context and conflicting override settings exit before any daemon/resource/cleanup command. They do not create or change Docker contexts.

To exercise cleanup after a failed run:

```sh
node scripts/backup-restore.mjs --inject-failure-after-backup
```

This deliberately exits **1** after creating and validating the encrypted archive, then removes its own resources. It is a negative test, not a successful backup. Wrong-key, modified-tag and truncated-archive checks also run on every normal invocation. No failed decryption is passed into PostgreSQL.

For CI, use `node scripts/backup-restore-negative.mjs`. The wrapper succeeds only when the real drill reaches that exact injected failure, exits 1, reports successful encrypted-archive validation and completes cleanup. It rejects early failures, additional error output and missing cleanup evidence; checking an arbitrary nonzero exit would produce false positives.

## Snapshot, restore and assertions

1. Provision only the source cluster/cache, create a non-superuser `palmy_runtime` with no BYPASSRLS, role memberships, database creation or role creation, then run the real SQLx migrations as the owner. Seed two synthetic encrypted-profile owners through the real API, two wallets, one income of `2000.00` and one expense of `1234.56`. Edit a profile to version 2 and retain one active session and one unused challenge for rollback tests.
2. Run PostgreSQL 18.6 `pg_dump --format=custom --compress=gzip:6` as the fixture database owner. Include all schemas, tables, SQLx history, ownership, grants, RLS, functions, triggers and idempotency responses. The compressed plaintext archive stays in process memory. PostgreSQL makes a consistent database snapshot; a logical dump does not include cluster-wide roles. [PostgreSQL SQL dump documentation](https://www.postgresql.org/docs/18/backup-dump.html), [pg_dump reference](https://www.postgresql.org/docs/18/app-pgdump.html).
3. Encrypt using the installed OpenSSL CMS implementation: AES-256-GCM content encryption and RSA-3072 OAEP/SHA-256 recipient key transport. Use a fresh disposable recipient key/certificate per drill. The DER CMS archive and private key are mode `0600` inside a mode `0700` OS temporary directory outside the repository. Encryption is a standard CMS format; no custom archive cipher or password-derived construction is added. [OpenSSL CMS documentation](https://docs.openssl.org/3.5/man1/openssl-cms/).
4. Demonstrate the snapshot boundary by committing another expense of `0.37`, editing the profile again, revoking the saved session and consuming the saved challenge **after** backup. These later changes must not appear in the restored snapshot. This also makes clear why restoring old authentication rows is unsafe.
5. Create a **new** destination PostgreSQL cluster and fresh cache. Check the destination has no application tables and a different PostgreSQL system identifier. Recreate known role definitions with a new destination password and runtime **NOLOGIN**. Never import global role passwords, apply `--no-owner`/`--no-acl`, use `--clean`, or restore over an existing database. Ownership/grants must refer to these preprovisioned roles. [Role attributes](https://www.postgresql.org/docs/18/role-attributes.html).
6. Decrypt the complete archive successfully before sending any plaintext to `pg_restore --single-transaction --exit-on-error`. AES-GCM can emit provisional plaintext before final authentication; piping it directly to SQL would be unsafe. The whole custom archive is bounded to 64 MiB by this fixture. Failure rolls back the restore rather than leaving a partially accepted destination. [pg_restore transaction behavior](https://www.postgresql.org/docs/18/app-pgrestore.html).
7. While the destination has no API and the runtime role is NOLOGIN, verify the old authentication rows were restored, then atomically clear **all** sessions and challenges and enable runtime login. Start with an empty destination Valkey; caches, old authorization state and abuse-limit counters are never copied from the source. Start the real API only after this quarantine step.
8. Compare migration versions, checksums and successful history exactly. Check restricted role ownership/membership, six forced-RLS tables, no rows without owner context, cross-owner read/write/FK denial, immutable journals/postings and rejection of a new unbalanced journal. Verify both existing journals have exactly two balanced postings and the restored balance is exactly `765.44`.
9. Verify old tokens and the saved challenge return 401, fresh owner proof succeeds, the restored ciphertext/version exactly match the snapshot, only the correct owner key decrypts the profile, and the other owner cannot access its wallet/ledger. Replay wallet idempotency and four concurrent requests with the original expense key; all return the original IDs without another journal. A changed body with the old key returns 409. A new `0.01` expense changes the restored balance/cache to `765.43`; profile versioning still rejects stale writes.

The exercise uses independent Node standard-library crypto for synthetic API clients, not a bypass of API authentication. API and PostgreSQL assertions both run. Its RSA private key protects the **whole backup**, including readable finance; it is unrelated to client profile/recovery keys, which never enter a server request or dump. CMS encryption authenticates ciphertext integrity, not source provenance: this tool accepts only its own just-created archive. A future production restore also needs authenticated inventory/object-version provenance from the approved backup system.

## Timing and recovery-point evidence

NFR-05 proposes RPO **24 hours** and RTO **4 hours**. The emitted metrics distinguish:

- `backup_seconds`: dump plus authenticated encryption/write of the archive.
- `snapshot_age_at_incident_seconds`: wall-clock interval from immediately before `pg_dump` starts until the deliberately later mutations/revocation complete. This conservatively bounds this fixture's recovery-point age; it is not the interval between scheduled production backups.
- `restore_and_verification_seconds`: from provisioning the fresh destination through decryption, restore, quarantine, API readiness and snapshot/invariant/idempotency checks. New-write smoke tests follow.
- `total_exercise_seconds`: source preparation, API build, fixture seeding, backup and all recovery checks; final resource cleanup is separate.

On 2026-09-27, a local warm-build/image run by Codex passed 137 checks and cleanup on PostgreSQL 18.6 / OpenSSL 3.6.4:

| Measured fixture result | Value |
|---|---|
| Snapshot content | 2 synthetic owners, 2 wallets, 2 journals, 4 postings; SQLx migration history and idempotency records |
| Custom dump / encrypted CMS archive | 32,678 / 33,301 bytes |
| Backup | 0.151 seconds |
| Snapshot age at simulated incident | 0.191 seconds, conservatively measured before dump starts |
| Fresh destination provision, restore and verification | 3.637 seconds |
| Total exercise before cleanup | 9.348 seconds |
| Expected post-snapshot loss | One `0.37` expense and one profile edit |

All committed pre-snapshot fixture data was retained. Wrong-key/tag-tamper/truncation negatives passed, and the injected-failure wrapper verified the real after-backup exit 1 and successful cleanup. The wrapper also rejected a deliberately early preflight failure. Separate OpenSSL 3.0.20 Linux compatibility testing passed the same AES-GCM/RSA-OAEP parameters, a byte-identical decrypt, and wrong-key/truncation rejection. Four no-daemon preflight regressions passed.

These measured local intervals are below the proposed 24h/4h numbers, but small fixture timings cannot establish a production recovery SLA or scheduled RPO. Real acceptance must include representative size/write load, backup transfer/download, secret retrieval approvals, operator response, restore validation, erasure reconciliation and safe traffic cutover.

## Backup storage, key access and production gates

The current drill keeps its encrypted archive and disposable recipient private key only for the run and removes them afterward. It deliberately retains no usable backup. This is a local exercise policy, not offsite disaster protection. Managed runtimes and SSD deletion cannot guarantee erasure of all prior memory/media copies; only synthetic records belong here.

Before real records, Rohman M must record named responsible people and approve the following deployment-specific policy. None is configured by this script:

| Boundary | Required production decision/control |
|---|---|
| Scheduling and RPO | Choose logical/physical backup and WAL/PITR topology; monitor successful recoverable-point age, alert early enough to stay within the proposed 24h maximum, and demonstrate missed/failed-backup escalation. A once-per-day start alone does not establish a 24h RPO. |
| Backup storage | Dedicated private offsite storage, encrypted transport, private access policy, verified object versions/inventory and protection against accidental or malicious deletion. Approve exact maximum retention for every base backup, WAL segment, replica and restore copy; no retention duration is accepted here. |
| Writer access | Separate backup service identity, limited to the selected source and necessary archive writes. Runtime application credentials cannot read backup archives or decryption keys. |
| Decryption key custody | Store the private recipient/decryption key separately from archives in an approved secrets/KMS boundary, with audited, time-limited restore access, independent recovery of key custody and named approval/rotation owners. Losing every key copy makes encrypted backups unrecoverable. Do not store private keys in Git, build artifacts or the archive bucket. |
| Restore authority | Named production incident responder and database operator; approved quarantine destination, trusted source/version/checksum inventory, least-privilege role provisioning and deliberate traffic cutover. Restoring SQL trusts its source's administrative code; encryption alone does not establish that trust. |
| Privacy reconciliation | An independent durable erasure/suspension registry must survive application-backup rollback and be reconciled before traffic, jobs, exports or new backups resume. Missing/stale/unverifiable registry keeps the restore quarantined. See the [account-erasure design](account-erasure.md). That registry and erasure are **not implemented** by this drill. |
| Credential recovery | Clear sessions/challenges and cache before any v1 restored API is exposed. Future credential-lifecycle revisions require an independently durable rollback-prevention policy; this v1 purge is not proof that older backups cannot resurrect a rotated root/device credential. |
| RTO acceptance | Measure a representative restore including all approvals/reconciliation/cutover, then accept or revise the proposed 4h target. Document incident communications without financial/profile payloads. |

Logical `pg_dump` backups cannot be replayed with WAL for PITR. A production WAL strategy needs compatible physical/base backups and an uninterrupted archived WAL sequence, with its own operational tests. [PostgreSQL continuous archiving](https://www.postgresql.org/docs/18/continuous-archiving.html). This drill does not add scheduling, offsite upload, production credentials, hosted KMS or a legal retention policy.

## Failure handling and cleanup

Stop on a failed encryption/decryption, restore, role/invariant check or authorization check; do not open the destination to users. The tool suppresses raw command diagnostics because they may contain SQL or connection information. Diagnose the named stage by repeating the synthetic drill; do not enable payload logging against real data.

The `finally` path stops only its child API processes, then runs Compose `down --volumes` for its generated project and verifies no project containers or volumes remain. It deletes its own temporary directory on success or failure. SIGINT/SIGTERM abort active work and enter cleanup. A hard kill, daemon outage or host crash can prevent cleanup; the tool prints the exact owned project if cleanup fails. Inspect resources with that exact `com.docker.compose.project` label and remove only those verified resources after the daemon recovers. Do not use global Docker prune, delete normal `palmy` volumes, or attempt to repair a failed destination by overwriting the source.

Encrypted-archive wrong-key, tag-tamper and truncation rejection are tested before destination creation. The optional injected failure proves the failure cleanup path. If a production restore ever fails, retain its original encrypted source and approved evidence, discard/quarantine the failed destination, and retry into another clean environment after resolving the cause. This disposable fixture instead removes both synthetic clusters and its temporary archive/key, by design.
