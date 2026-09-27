-- Palmy database smoke suite. RUN ONLY in a fresh disposable database after schema.sql.
-- Example: psql -X -v ON_ERROR_STOP=1 -d palmy_test -f schema.sql -f database-smoke.sql
-- Requires a disposable-database test identity with BYPASSRLS and CREATEROLE (or superuser).
-- The tested runtime role itself has neither superuser nor BYPASSRLS.
-- Everything below rolls back. No existing database is a valid test target.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.assert_ok(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAILED: %',label; END IF; RAISE NOTICE 'PASS: %',label; END $$;
CREATE FUNCTION pg_temp.expect_error(statement text,expected text,label text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE caught text;
BEGIN
 BEGIN EXECUTE statement; EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS caught=RETURNED_SQLSTATE; END;
 IF caught IS DISTINCT FROM expected THEN RAISE EXCEPTION 'FAILED: % expected %, got %',label,expected,caught; END IF;
 RAISE NOTICE 'PASS: %',label;
END $$;

INSERT INTO palmy.users(id,auth_subject,display_name) VALUES
('00000000-0000-4000-8000-000000000001','palmy-smoke-owner-a','Synthetic owner A'),
('00000000-0000-4000-8000-000000000002','palmy-smoke-owner-b','Synthetic owner B');
INSERT INTO palmy.households(id,name) VALUES
('10000000-0000-4000-8000-000000000001','Synthetic household A'),
('10000000-0000-4000-8000-000000000002','Synthetic household B');
INSERT INTO palmy.memberships(household_id,user_id,role,display_name) VALUES
('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','owner','Owner A'),
('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002','owner','Owner B');
INSERT INTO palmy.ledger_accounts(id,household_id,name,kind) VALUES
('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Cash','asset'),
('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','Opening equity','equity'),
('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001','Expenses','expense'),
('20000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000001','Receivable','asset'),
('20000000-0000-4000-8000-000000000005','10000000-0000-4000-8000-000000000001','Investment cost','asset'),
('20000000-0000-4000-8000-000000000006','10000000-0000-4000-8000-000000000002','Foreign cash','asset');
INSERT INTO palmy.wallets(id,household_id,account_id,name,kind,is_primary) VALUES
('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','QA Cash','cash',true),
('30000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000006','Other tenant cash','cash',true);

SELECT pg_temp.assert_ok('617.28'::palmy.money+'617.28'::palmy.money='1234.56'::numeric,'exact decimal sum');
SELECT pg_temp.expect_error($q$SELECT '1.001'::palmy.money$q$,'23514','reject excess precision');
SELECT pg_temp.expect_error($q$SELECT 'NaN'::palmy.money$q$,'23514','reject NaN');
SELECT pg_temp.expect_error($q$SELECT 'Infinity'::palmy.money$q$,'23514','reject infinity');

INSERT INTO palmy.journal_entries(id,household_id,kind,effective_on,amount,created_by)
VALUES('40000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','opening','2026-09-26',100000,'00000000-0000-4000-8000-000000000001');
INSERT INTO palmy.journal_lines(household_id,entry_id,account_id,amount) VALUES
('10000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',100000),
('10000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002',-100000);
UPDATE palmy.journal_entries SET state='posted',posted_at=now() WHERE id='40000000-0000-4000-8000-000000000001';
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.assert_ok((SELECT balance=100000 FROM palmy.account_balances WHERE account_id='20000000-0000-4000-8000-000000000001'),'opening journal and derived cash balance');
SELECT pg_temp.expect_error($q$UPDATE palmy.journal_entries SET description='tamper' WHERE id='40000000-0000-4000-8000-000000000001'$q$,'23514','posted header immutable');
SELECT pg_temp.expect_error($q$DELETE FROM palmy.journal_lines WHERE entry_id='40000000-0000-4000-8000-000000000001'$q$,'23514','posted lines immutable');
SELECT pg_temp.expect_error($q$
INSERT INTO palmy.journal_entries(id,household_id,kind,state,posted_at,effective_on,amount,created_by)
VALUES('40000000-0000-4000-8000-000000000099','10000000-0000-4000-8000-000000000001','expense','posted',now(),'2026-09-26',1,'00000000-0000-4000-8000-000000000001');
SET CONSTRAINTS ALL IMMEDIATE$q$,'23514','posted empty journal rejected at constraint boundary');
SELECT pg_temp.expect_error($q$
INSERT INTO palmy.wallets(household_id,account_id,name,kind)
VALUES('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000006','Cross tenant','cash')$q$,'23503','composite FK rejects cross-tenant account');

INSERT INTO palmy.categories(id,household_id,name,direction,account_id) VALUES
('50000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Root','expense','20000000-0000-4000-8000-000000000003');
INSERT INTO palmy.categories(id,household_id,name,direction,account_id,parent_id) VALUES
('50000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','Child','expense','20000000-0000-4000-8000-000000000003','50000000-0000-4000-8000-000000000001');
SELECT pg_temp.expect_error($q$
INSERT INTO palmy.categories(household_id,name,direction,account_id,parent_id) VALUES
('10000000-0000-4000-8000-000000000001','Grandchild','expense','20000000-0000-4000-8000-000000000003','50000000-0000-4000-8000-000000000002')$q$,'23514','category depth limited');

INSERT INTO palmy.goals(id,household_id,name,type,target_amount) VALUES
('60000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Synthetic goal','emergency',10000);
INSERT INTO palmy.goal_movements(household_id,goal_id,wallet_id,amount,kind,effective_on) VALUES
('10000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1500,'reserve','2026-09-26'),
('10000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',-500,'release','2026-09-26');
SELECT pg_temp.assert_ok((SELECT reserved=1000 FROM palmy.goal_cash_balances WHERE goal_id='60000000-0000-4000-8000-000000000001'),'reservation release leaves1000');
SELECT pg_temp.assert_ok((SELECT balance=100000 FROM palmy.account_balances WHERE account_id='20000000-0000-4000-8000-000000000001'),'reservation does not debit wallet');
SELECT pg_temp.expect_error($q$INSERT INTO palmy.goal_movements(household_id,goal_id,wallet_id,amount,kind,effective_on) VALUES
('10000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',-1001,'release','2026-09-26')$q$,'23514','over-release rejected');
SELECT pg_temp.expect_error($q$INSERT INTO palmy.goal_movements(household_id,goal_id,wallet_id,amount,kind,effective_on) VALUES
('10000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',99001,'reserve','2026-09-26')$q$,'23514','over-reserve rejected');

INSERT INTO palmy.asset_holdings(id,household_id,name,asset_class,unit,account_id) VALUES
('70000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Synthetic asset','other','unit','20000000-0000-4000-8000-000000000005');
INSERT INTO palmy.asset_trades(household_id,holding_id,kind,quantity_delta,gross_amount,cost_basis_delta,effective_on) VALUES
('10000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000001','buy',2,2000,2000,'2026-09-26'),
('10000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000001','sell',-1,1500,-1000,'2026-09-26');
SELECT pg_temp.assert_ok((SELECT quantity=1 AND cost_basis=1000 FROM palmy.asset_positions WHERE holding_id='70000000-0000-4000-8000-000000000001'),'partial sale leaves correct quantity and basis');
SELECT pg_temp.expect_error($q$INSERT INTO palmy.asset_trades(household_id,holding_id,kind,quantity_delta,gross_amount,cost_basis_delta,effective_on) VALUES
('10000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000001','sell',-2,3000,-2000,'2026-09-26')$q$,'23514','oversell rejected');

INSERT INTO palmy.allocation_plans(id,household_id,name,kind) VALUES
('80000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Synthetic allocation','income');
INSERT INTO palmy.allocation_items(household_id,plan_id,name,basis_points) VALUES
('10000000-0000-4000-8000-000000000001','80000000-0000-4000-8000-000000000001','A',6000),
('10000000-0000-4000-8000-000000000001','80000000-0000-4000-8000-000000000001','B',5000);
SELECT pg_temp.expect_error($q$UPDATE palmy.allocation_plans SET state='active' WHERE id='80000000-0000-4000-8000-000000000001'; SET CONSTRAINTS ALL IMMEDIATE$q$,'23514','110 percent active plan rejected');

-- Runtime role is a test-only name. Creation fails rather than altering a pre-existing role.
CREATE ROLE palmy_smoke_runtime NOLOGIN NOSUPERUSER NOBYPASSRLS;
GRANT USAGE ON SCHEMA palmy TO palmy_smoke_runtime;
GRANT SELECT ON ALL TABLES IN SCHEMA palmy TO palmy_smoke_runtime;
GRANT EXECUTE ON FUNCTION palmy.can_access(uuid),palmy.is_owner(uuid) TO palmy_smoke_runtime;
SET LOCAL ROLE palmy_smoke_runtime;
SELECT set_config('app.user_id','00000000-0000-4000-8000-000000000001',true);
SELECT set_config('app.household_id','10000000-0000-4000-8000-000000000001',true);
SELECT pg_temp.assert_ok((SELECT count(*)=1 FROM palmy.wallets),'RLS reveals only active household wallet');
SELECT set_config('app.household_id','10000000-0000-4000-8000-000000000002',true);
SELECT pg_temp.assert_ok((SELECT count(*)=0 FROM palmy.wallets),'RLS rejects household without membership');
SELECT set_config('app.user_id','',true);
SELECT pg_temp.assert_ok((SELECT count(*)=0 FROM palmy.wallets),'RLS rejects missing identity context');
RESET ROLE;

-- Ensure successful posted entries still satisfy all deferred constraints.
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
\echo Palmy smoke suite completed; all synthetic rows and test role rolled back.
