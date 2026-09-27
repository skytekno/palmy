# Palmy — product and technical specification package

Prepared 26 September 2026 from a live authenticated audit of [Seruma](https://seruma.app/). **Palmy** is the name used for the proposed application. No live application branding was changed.

Start with these four deliverables:

1. [Product requirements document](PRD-Palmy.md) — scope, 24 functional requirements, business rules, acceptance criteria and release gates.
2. [API design](API-design.md) — command behavior, authorization, retries, files and reporting; [OpenAPI contract](openapi.json) with 154 operations and 180 schemas; [operation catalog](api-catalog.md).
3. [Database design](Database-design.md) — 62-table proposed PostgreSQL model, exact ledger and isolation; [SQL schema](schema.sql) and [column dictionary](database-dictionary.md).
4. [Entity relationship diagrams](ERD.md) — readable domain views and the [complete Mermaid source](palmy-erd.mmd).

The API/database are **proposed designs**, not Seruma's private implementation. Berdua and descendants, Conversation Cards, and Jurnal Keluarga are excluded throughout.

## Audit result

[QA report](QA-report.md) · [full coverage CSV](coverage.csv) · [coverage summary](coverage-summary.md)

The 163-row inventory records 90 passed checks, 6 findings, 41 inspection-only checks, 16 blocked scenarios, 7 unexecuted scenarios and 3 explicit exclusions. These are scenario rows, not a claim of 163 independent features or exhaustive coverage.

The highest-priority confirmed defect is shared-expense precision: 1234.56 persisted as 618+617=1235. Other findings concern accessibility, help consistency, localization and missing wallet choice for grocery/service postings.

Synthetic `PALMY QA R2` bookkeeping and household records remain in the app. Currency and reporting-cycle settings were restored; default viewport restored. The report includes a retained-fixture manifest and limitations. No real bank transfer or payout occurred.

## Validation and use

[Validation report](validation.md) · [artifact validator](validate_artifacts.py) · [database smoke suite](database-smoke.sql)

Run `python3 validate_artifacts.py` from this directory to repeat dependency-free structural, reference, coverage and financial-specification checks. It does not call the live app.

PostgreSQL runtime validation remains blocked by the local sandbox's shared-memory restriction. Run the SQL schema and smoke suite only in a new disposable PostgreSQL 17+ database with the documented test privileges. Do not apply them to the reference application's database or an existing production schema.

The original request for every possible scenario cannot be certified from one live browser session. File upload/OCR, external permissions, destructive final actions, second-user authorization, concurrency and provider-failure scenarios remain explicit gates. The package preserves those gaps instead of calling inspected or blocked paths passed.
