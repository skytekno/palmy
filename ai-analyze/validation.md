# Palmy — validation record

Validation date:26 September 2026. This record distinguishes testing of the reference UI from checking newly authored specification files.

## Completed artifact checks

- The OpenAPI JSON parses, uses version 3.0.3, resolves all local references and defines unique operation IDs. Structural validation checks request path parameters, duplicate parameters, success responses, required-field references, regular expressions and authenticated household routing.
- The API design skill linter ran on a copy with shared parameters expanded because that linter does not resolve parameter `$ref` objects. Final result:154 operations,0 errors,942 warnings,138 informational findings, score 80.75/100. This is a style score, not a production-readiness score.
- Of the warnings,939 concern the deliberately consistent snake_case naming convention and 3 concern nested domain correction routes. The latter retain explicit parent context for ownership checks. Informational findings include accepted 202/412/422/428 status semantics and bodyless resource-creation/desired-state operations. These were reviewed rather than silently suppressed.
- Dependency-free financial specification fixtures check exact shared allocation including a one-cent remainder, transfer-plus-fee arithmetic, debt remaining balance, linked goal progress and education compounding. These fixtures validate the proposed formulas, not the live backend.
- SQL structure checks ensure all referenced tables exist, tenant graph tables match the complete ERD/dictionary, the migration transaction is bounded, and required invariant/security clauses are present. These checks are not a PostgreSQL parser or execution engine.
- Markdown internal links and fenced-block balance are checked. The coverage CSV has unique scenario IDs and exactly the three requested exclusions.

The repeatable results are in [artifact-validation.json](artifact-validation.json), produced by [validate_artifacts.py](validate_artifacts.py).

## PostgreSQL execution: blocked

PostgreSQL 17.11 tools are installed. A disposable `initdb` attempt in the workspace was denied directory creation. Retrying in the permitted temporary directory created configuration files, but bootstrap failed:

```text
FATAL: could not create shared memory segment: Operation not permitted
Failed system call was shmget(... size=56 ...).
```

A memory-mapped configuration attempt reached the same shared-memory restriction. No server was started, no user database was accessed, and no schema was deployed. `initdb` removed its failed temporary cluster. The delivered [database-smoke.sql](database-smoke.sql) is therefore **provided but not executed**. It must not be described as passing.

The smoke suite covers exact numeric rejection, balanced/immutable journals, tenant foreign keys, category depth, goal reserve/release guards, position arithmetic, oversell protection, allocation totals and non-owner RLS reads. It runs in a transaction and rolls back fixtures and the test role. It requires a disposable database under a privileged test/migration identity and creates a separate NOSUPERUSER/NOBYPASSRLS role for the isolation assertions.

## Other validation boundaries

No complete OpenAPI metaschema validator, generated client/server integration, Mermaid renderer, SQL migration engine, load suite or full application source test suite ran. The complete ERD's entity inventory was checked, but rendered layout is not claimed as visually verified. The package is a specification and audit deliverable, not an implemented or deployed Palmy application.

Live UI results, browser diagnostics, fixture retention, file-upload blocker and remaining scenario matrix are in the [QA report](QA-report.md). Passing a structural check on the proposed design does not resolve any live Seruma defect.
