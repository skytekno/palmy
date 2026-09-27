CREATE SCHEMA palmy;
REVOKE ALL ON SCHEMA palmy FROM PUBLIC;
CREATE TABLE palmy.schema_metadata(version integer PRIMARY KEY);
INSERT INTO palmy.schema_metadata VALUES (1);

CREATE TABLE palmy.accounts (
    id uuid PRIMARY KEY,
    public_key bytea NOT NULL UNIQUE CHECK (octet_length(public_key) = 32),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE palmy.profiles (
    owner_id uuid PRIMARY KEY REFERENCES palmy.accounts(id),
    envelope jsonb NOT NULL CHECK (jsonb_typeof(envelope) = 'object'),
    version bigint NOT NULL DEFAULT 1 CHECK (version > 0)
);
CREATE TABLE palmy.challenges (
    id uuid PRIMARY KEY,
    account_id uuid NOT NULL,
    nonce text NOT NULL,
    expires_at timestamptz NOT NULL
);
CREATE INDEX challenges_expiry ON palmy.challenges(expires_at);
CREATE TABLE palmy.sessions (
    token_hash bytea PRIMARY KEY CHECK (octet_length(token_hash) = 32),
    account_id uuid NOT NULL REFERENCES palmy.accounts(id),
    expires_at timestamptz NOT NULL
);
CREATE INDEX sessions_expiry ON palmy.sessions(expires_at);
CREATE TABLE palmy.ledger_state (
    owner_id uuid PRIMARY KEY REFERENCES palmy.accounts(id),
    revision bigint NOT NULL DEFAULT 0 CHECK (revision >= 0)
);
CREATE TABLE palmy.wallets (
    id uuid PRIMARY KEY,
    owner_id uuid NOT NULL REFERENCES palmy.accounts(id),
    name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80 AND name = btrim(name)),
    currency text NOT NULL DEFAULT 'IDR' CHECK (currency = 'IDR'),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (owner_id, id)
);
CREATE INDEX wallets_owner ON palmy.wallets(owner_id, created_at, id);
CREATE TABLE palmy.journals (
    id uuid PRIMARY KEY,
    owner_id uuid NOT NULL REFERENCES palmy.accounts(id),
    wallet_id uuid NOT NULL,
    kind text NOT NULL CHECK (kind IN ('income', 'expense')),
    amount numeric(18,2) NOT NULL CHECK (amount > 0),
    category text NOT NULL CHECK (char_length(category) BETWEEN 1 AND 60 AND category = btrim(category)),
    description text NOT NULL CHECK (char_length(description) <= 280),
    effective_on date NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (owner_id, id),
    FOREIGN KEY (owner_id, wallet_id) REFERENCES palmy.wallets(owner_id, id)
);
CREATE INDEX journals_owner_page ON palmy.journals(owner_id, created_at DESC, id DESC);
CREATE INDEX journals_wallet ON palmy.journals(owner_id, wallet_id);
CREATE TABLE palmy.entries (
    id uuid PRIMARY KEY,
    owner_id uuid NOT NULL,
    journal_id uuid NOT NULL,
    wallet_id uuid,
    account_kind text NOT NULL CHECK (account_kind IN ('wallet', 'counterparty')),
    amount numeric(18,2) NOT NULL CHECK (amount <> 0),
    FOREIGN KEY (owner_id, journal_id) REFERENCES palmy.journals(owner_id, id),
    FOREIGN KEY (owner_id, wallet_id) REFERENCES palmy.wallets(owner_id, id),
    CHECK ((account_kind = 'wallet') = (wallet_id IS NOT NULL)),
    UNIQUE (owner_id, journal_id, account_kind)
);
CREATE INDEX entries_wallet ON palmy.entries(owner_id, wallet_id);
CREATE TABLE palmy.idempotency (
    owner_id uuid NOT NULL REFERENCES palmy.accounts(id),
    route text NOT NULL CHECK (route IN ('wallets', 'transactions')),
    key uuid NOT NULL,
    body_hash bytea NOT NULL CHECK (octet_length(body_hash) = 32),
    response jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (owner_id, route, key)
);

-- Context is set transaction-locally only after the API verifies a database session.
DO $$
DECLARE relation text;
BEGIN
    FOREACH relation IN ARRAY ARRAY['profiles','ledger_state','wallets','journals','entries','idempotency'] LOOP
        EXECUTE format('ALTER TABLE palmy.%I ENABLE ROW LEVEL SECURITY', relation);
        EXECUTE format('ALTER TABLE palmy.%I FORCE ROW LEVEL SECURITY', relation);
        EXECUTE format('CREATE POLICY owner_only ON palmy.%I USING (owner_id = nullif(current_setting(''palmy.account_id'', true), '''')::uuid) WITH CHECK (owner_id = nullif(current_setting(''palmy.account_id'', true), '''')::uuid)', relation);
    END LOOP;
END $$;

CREATE FUNCTION palmy.reject_posted_mutation() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, palmy AS $$
BEGIN RAISE EXCEPTION 'posted journal is immutable' USING ERRCODE = '23514'; END $$;
REVOKE ALL ON FUNCTION palmy.reject_posted_mutation() FROM PUBLIC;
CREATE TRIGGER journal_immutable BEFORE UPDATE OR DELETE ON palmy.journals
FOR EACH ROW EXECUTE FUNCTION palmy.reject_posted_mutation();
CREATE TRIGGER entry_immutable BEFORE UPDATE OR DELETE ON palmy.entries
FOR EACH ROW EXECUTE FUNCTION palmy.reject_posted_mutation();

CREATE FUNCTION palmy.validate_journal() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, palmy AS $$
DECLARE journal palmy.journals%ROWTYPE; target_id uuid; total numeric; entry_count integer; wallet_amount numeric; wallet_match boolean;
BEGIN
    IF TG_TABLE_NAME = 'journals' THEN target_id := NEW.id; ELSE target_id := NEW.journal_id; END IF;
    SELECT * INTO STRICT journal FROM palmy.journals WHERE id = target_id;
    SELECT sum(amount), count(*), max(amount) FILTER (WHERE account_kind = 'wallet'),
           bool_and(wallet_id = journal.wallet_id) FILTER (WHERE account_kind = 'wallet')
    INTO total, entry_count, wallet_amount, wallet_match FROM palmy.entries WHERE journal_id = target_id;
    IF entry_count <> 2 OR total <> 0 OR wallet_match IS DISTINCT FROM true OR
       wallet_amount IS DISTINCT FROM (CASE WHEN journal.kind = 'income' THEN journal.amount ELSE -journal.amount END) THEN
       RAISE EXCEPTION 'journal must have two matching balanced entries' USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION palmy.validate_journal() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER journal_balanced AFTER INSERT ON palmy.journals
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION palmy.validate_journal();
CREATE CONSTRAINT TRIGGER entries_balanced AFTER INSERT ON palmy.entries
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION palmy.validate_journal();

-- Provision palmy_runtime as LOGIN NOSUPERUSER NOBYPASSRLS before migrating.
GRANT USAGE ON SCHEMA palmy TO palmy_runtime;
GRANT SELECT ON palmy.schema_metadata TO palmy_runtime;
GRANT SELECT, INSERT ON palmy.accounts TO palmy_runtime;
GRANT SELECT, INSERT, UPDATE ON palmy.profiles, palmy.ledger_state TO palmy_runtime;
GRANT SELECT, INSERT, DELETE ON palmy.challenges, palmy.sessions TO palmy_runtime;
GRANT SELECT, INSERT ON palmy.wallets, palmy.journals, palmy.entries, palmy.idempotency TO palmy_runtime;
GRANT EXECUTE ON FUNCTION palmy.validate_journal(), palmy.reject_posted_mutation() TO palmy_runtime;
