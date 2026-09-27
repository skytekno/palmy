# Palmy

Household finance designed from [`ai-analyze`](ai-analyze/README.md), with a working personal finance foundation and client-encrypted identity.

- [`api/`](api): Rust 1.98.1 + Axum, PostgreSQL, Valkey caching, generated OpenAPI.
- [`web/`](web): Next.js client-rendered application with a static export.
- [`mobile/android/`](mobile/android): native Kotlin / Jetpack Compose.
- [`mobile/ios/`](mobile/ios): native Swift / SwiftUI.

Profiles are encrypted on the device. Financial amounts and descriptions remain readable; the API restricts access by pseudonymous owner. This does **not** guarantee anonymity against transaction contents or metadata. The recovery key is the full account credential; Palmy cannot replace a lost key. Read the [privacy boundary](docs/security.md).

## Run locally

Prerequisites: Docker Compose, Rust 1.98.1 (rustup reads the pin), Node 22.12+ and npm. Commands run from repository root. Existing `.env` files are preserved; generated database credentials are random and local.

```sh
make setup
make infra
make migrate
make api
```

In another terminal:

```sh
make web
```

Open [localhost:3100](http://localhost:3100). The API runs at `http://localhost:8100`; OpenAPI is at `/openapi.json`. PostgreSQL and Valkey publish only on loopback ports 55432 and 56379. `docker compose up -d --build api` runs the API and migrations in containers instead of `make migrate` / `make api`; do not run both APIs on the same port.

Create an account, save its recovery key, create a wallet, then record income or an expense. Recovery on another client uses that same key. Lock revokes the active session when reachable and clears local state. The initial clients do not persist unlocked credentials between launches.

Native setup and build commands live in [`mobile/README.md`](mobile/README.md). Android emulator connects through `10.0.2.2:8100`; iOS simulator uses `127.0.0.1:8100`. HTTPS and production deployment are separate gates.

The API defaults to production configuration: `CORS_ORIGINS` must list exact canonical HTTPS origins. The local Compose stack and `scripts/with-env.mjs` explicitly select development mode, which permits loopback origins only. See [web delivery controls](docs/web-delivery.md) for the production static server, TLS, CSP, origin configuration and remaining staging evidence.

## Verify

```sh
make check
make integration  # requires local infrastructure and the API running
npx playwright install chromium
npm run test:browser  # also requires the web running at localhost:3100
npx playwright install firefox
make delivery-check  # isolated trusted HTTPS, CSP and privacy browser checks
make backup-drill    # synthetic encrypted restore and failure cleanup
```

See [validation evidence](docs/validation.md) for browser/native commands and actual outcomes. The [architecture](docs/architecture.md), [wire/crypto protocol](docs/protocol.md), [visual tokens](design/tokens.json), and [delivery map](docs/delivery.md) distinguish implemented behavior from the full product roadmap. The [initial Linear delivery plan](docs/linear-plan.md) links 44 issues and eight milestones; the [erasure refinements](docs/erasure-followups.json) add MAN-124–136. Linear holds current task status. The 154 operations in the original specification are not all implemented by this initial slice.

`docker compose stop` stops only this project's containers and retains data. Do not delete the PostgreSQL volume when it contains records you want to keep.
