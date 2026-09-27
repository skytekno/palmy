import {execFileSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
const a=randomUUID(), b=randomUUID(), wa=randomUUID(), wb=randomUUID(), journal=randomUUID();
const sql=`
BEGIN;
INSERT INTO palmy.accounts(id,public_key) VALUES ('${a}',decode(repeat('11',32),'hex')),('${b}',decode(repeat('22',32),'hex'));
INSERT INTO palmy.ledger_state(owner_id) VALUES ('${a}'),('${b}');
INSERT INTO palmy.wallets(id,owner_id,name) VALUES ('${wa}','${a}','Synthetic A'),('${wb}','${b}','Synthetic B');
INSERT INTO palmy.journals(id,owner_id,wallet_id,kind,amount,category,description,effective_on)
VALUES ('${journal}','${a}','${wa}','income',1234.56,'Test','Synthetic only','2026-09-27');
INSERT INTO palmy.entries(id,owner_id,journal_id,wallet_id,account_kind,amount) VALUES
(gen_random_uuid(),'${a}','${journal}','${wa}','wallet',1234.56),
(gen_random_uuid(),'${a}','${journal}',NULL,'counterparty',-1234.56);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SET LOCAL ROLE palmy_runtime;
DO $$ BEGIN
 IF EXISTS(SELECT FROM pg_roles WHERE rolname=current_user AND (rolsuper OR rolbypassrls)) THEN RAISE EXCEPTION 'unsafe runtime'; END IF;
 IF EXISTS(SELECT FROM palmy.wallets) THEN RAISE EXCEPTION 'missing-context RLS failed'; END IF;
END $$;
SELECT set_config('palmy.account_id','${a}',true);
DO $$ BEGIN
 IF (SELECT count(*) FROM palmy.wallets) <> 1 THEN RAISE EXCEPTION 'owner select failed'; END IF;
 IF EXISTS(SELECT FROM palmy.wallets WHERE id='${wb}') THEN RAISE EXCEPTION 'cross-owner read'; END IF;
 IF (SELECT sum(amount) FROM palmy.entries WHERE wallet_id='${wa}') <> 1234.56 THEN RAISE EXCEPTION 'precision failed'; END IF;
 BEGIN
  INSERT INTO palmy.wallets(id,owner_id,name) VALUES(gen_random_uuid(),'${b}','Forbidden');
  RAISE EXCEPTION 'cross-owner insert accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  INSERT INTO palmy.journals(id,owner_id,wallet_id,kind,amount,category,description,effective_on)
  VALUES(gen_random_uuid(),'${a}','${wb}','expense',1,'Test','','2026-09-27');
  RAISE EXCEPTION 'cross-owner wallet foreign key accepted';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN
  UPDATE palmy.entries SET amount=7 WHERE journal_id='${journal}';
  RAISE EXCEPTION 'runtime ledger update permitted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  INSERT INTO palmy.journals(id,owner_id,wallet_id,kind,amount,category,description,effective_on)
  VALUES(gen_random_uuid(),'${a}','${wa}','expense',1,'Test','','2026-09-27');
  SET CONSTRAINTS ALL IMMEDIATE;
  RAISE EXCEPTION 'unbalanced journal accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
SELECT set_config('palmy.account_id','${b}',true);
DO $$ BEGIN
 IF EXISTS(SELECT FROM palmy.journals) OR EXISTS(SELECT FROM palmy.entries) THEN RAISE EXCEPTION 'second owner leaked ledger'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
 BEGIN
  UPDATE palmy.entries SET amount=7 WHERE journal_id='${journal}';
  RAISE EXCEPTION 'immutable trigger failed';
 EXCEPTION WHEN check_violation THEN NULL; END;
 IF EXISTS(SELECT FROM information_schema.columns WHERE table_schema='palmy' AND column_name IN ('email','display_name','password','master_secret','private_key','auth_subject')) THEN RAISE EXCEPTION 'plaintext identity column'; END IF;
END $$;
ROLLBACK;
`;
try {
 execFileSync('docker',['compose','exec','-T','postgres','psql','-X','-q','-v','ON_ERROR_STOP=1','-U','palmy_owner','-d','palmy'],{input:sql,encoding:'utf8',stdio:['pipe','pipe','pipe']});
 console.log('PASS: PostgreSQL runtime role, missing-context RLS, cross-owner read/write/foreign-key denial, exact decimals, balanced-journal enforcement, immutable postings and identity column boundary. All fixtures rolled back.');
} catch(error) { console.error(error.stderr?.toString()??'Database assertions failed'); process.exit(1); }
