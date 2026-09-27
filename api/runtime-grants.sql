-- The migration applies these grants automatically. This file documents the runtime boundary.
GRANT USAGE ON SCHEMA palmy TO palmy_runtime;
GRANT SELECT ON palmy.schema_metadata TO palmy_runtime;
GRANT SELECT, INSERT ON palmy.accounts TO palmy_runtime;
GRANT SELECT, INSERT, UPDATE ON palmy.profiles, palmy.ledger_state TO palmy_runtime;
GRANT SELECT, INSERT, DELETE ON palmy.challenges, palmy.sessions TO palmy_runtime;
GRANT SELECT, INSERT ON palmy.wallets, palmy.journals, palmy.entries, palmy.idempotency TO palmy_runtime;
GRANT EXECUTE ON FUNCTION palmy.validate_journal(), palmy.reject_posted_mutation() TO palmy_runtime;
