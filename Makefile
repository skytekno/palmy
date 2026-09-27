.PHONY: setup infra migrate api web check integration stop
setup:
	node scripts/setup-local.mjs
	npm ci
	npm ci --prefix web
infra:
	docker compose up -d --wait postgres cache
migrate:
	node scripts/with-env.mjs cargo run --locked -p palmy-api -- migrate
api:
	node scripts/with-env.mjs cargo run --locked -p palmy-api -- serve
web:
	npm --prefix web run dev
check:
	node scripts/crypto-vectors.mjs --check
	node scripts/lifecycle-check.mjs
	node scripts/check-contract.mjs
	cargo fmt --all -- --check
	cargo clippy --locked --workspace --all-targets -- -D warnings
	cargo test --locked --workspace
	npm --prefix web run typecheck
	npm --prefix web test
	npm --prefix web run build
integration:
	node scripts/database-check.mjs
	node scripts/with-env.mjs node scripts/integration.mjs
stop:
	docker compose stop
