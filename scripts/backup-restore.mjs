// MAN-121: synthetic, disposable backup/restore exercise. Never opens root .env.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {randomBytes, randomUUID, hkdfSync, createPrivateKey, createPublicKey, createCipheriv, createDecipheriv, sign} from 'node:crypto';
import {mkdtemp, writeFile, readFile, chmod, rm, stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {createServer} from 'node:net';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
if (process.argv.slice(2).some(arg => arg !== '--inject-failure-after-backup')) {
  console.error('Usage: node scripts/backup-restore.mjs [--inject-failure-after-backup]');
  process.exit(2);
}
const project = `palmy-drill-${randomUUID().replaceAll('-', '')}`;
const work = await mkdtemp(join(tmpdir(), 'palmy-backup-drill-'));
await chmod(work, 0o700);
const cleanEnv = Object.fromEntries(['PATH','HOME','USER','TMPDIR','DOCKER_CONFIG','DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH','CARGO_HOME','RUSTUP_HOME'].filter(k => process.env[k]).map(k => [k, process.env[k]]));
const env = {...cleanEnv, PALMY_DRILL_SECRET_DIR: work};
const composeArgs = ['compose', '--project-directory', work, '--env-file', join(work, 'empty.env'), '-p', project, '-f', join(root, 'ops/backup-drill.compose.yml')];
const abort = new AbortController();
for (const signal of ['SIGINT','SIGTERM']) process.once(signal, () => abort.abort());
let phase = 'preflight', checks = 0, created = false, dockerSafe = false, dockerHost;
const apis = [];
const begun = performance.now();
const timings = {};
class SafeFailure extends Error {}
const check = (condition, label) => { if (!condition) throw new SafeFailure(label); checks++; };
function run(command, args, {input, environment=env, allowFailure=false, timeout=180_000, cleanup=false}={}) {
  return new Promise((resolve, reject) => {
    if (command === 'docker' && dockerHost) args = ['--host', dockerHost, ...args];
    const child = spawn(command, args, {cwd: root, env: environment, stdio: ['pipe','pipe','pipe'], signal: cleanup ? undefined : abort.signal});
    let size = 0, out = [], stderrSize = 0, spawnFailed = false;
    const timer = setTimeout(() => child.kill('SIGKILL'), timeout);
    child.stdout.on('data', chunk => { size += chunk.length; if (size > 64 * 1024 * 1024) child.kill('SIGKILL'); else out.push(chunk); });
    // Command errors may include connection strings, SQL or decrypted bytes: never log them.
    child.stderr.on('data', chunk => { stderrSize += chunk.length; if (stderrSize > 1024 * 1024) child.kill('SIGKILL'); });
    child.stdin.on('error', () => {});
    child.on('error', () => { spawnFailed = true; });
    child.on('close', code => {
      clearTimeout(timer);
      const output = Buffer.concat(out); out = [];
      if (spawnFailed || size > 64 * 1024 * 1024 || (code !== 0 && !allowFailure)) {
        output.fill(0); reject(new SafeFailure(`${phase}: ${command} failed (diagnostic output withheld)`));
      } else resolve({code, output});
    });
    child.stdin.end(input);
  });
}
const localSocket = endpoint => {
  try {
    const value = new URL(endpoint);
    return value.protocol==='unix:' && value.hostname==='' && value.pathname.startsWith('/') && !value.search && !value.hash;
  } catch { return false; }
};
async function verifyLocalDocker() {
  // Reject explicit remote hints even when DOCKER_CONTEXT would override DOCKER_HOST.
  // Docker context commands read local metadata; they do not contact the daemon.
  if (cleanEnv.DOCKER_HOST && !localSocket(cleanEnv.DOCKER_HOST)) throw new SafeFailure('Remote Docker endpoints are forbidden; select a local Unix socket');
  const metadataEnv = {...cleanEnv}; delete metadataEnv.DOCKER_HOST; delete metadataEnv.DOCKER_CONTEXT;
  const context = cleanEnv.DOCKER_CONTEXT || (await run('docker',['context','show'],{environment:metadataEnv})).output.toString().trim();
  const inspected = (await run('docker',['context','inspect','--format','{{.Endpoints.docker.Host}}','--',context],{environment:metadataEnv})).output.toString().trim();
  if (!localSocket(inspected)) throw new SafeFailure('Remote Docker contexts are forbidden; select a local Unix socket');
  // DOCKER_CONTEXT > DOCKER_HOST > configured context. Pin the resolved local endpoint
  // for every subsequent command so a concurrent `docker context use` cannot redirect it.
  const endpoint = cleanEnv.DOCKER_CONTEXT ? inspected : cleanEnv.DOCKER_HOST || inspected;
  if (!(await stat(fileURLToPath(new URL(endpoint).href.replace(/^unix:/,'file:')))).isSocket()) throw new SafeFailure('Docker endpoint must be a local Unix socket');
  delete env.DOCKER_CONTEXT; delete env.DOCKER_HOST;
  dockerHost = endpoint; dockerSafe = true; checks++;
}
const compose = (args, options) => run('docker', [...composeArgs, ...args], options);
const sql = async (service, statement) => (await compose(['exec','-T',service,'psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','palmy_owner','-d','palmy'], {input: statement})).output.toString().trim();
const port = async (service, internal) => {
  const address = (await compose(['port', service, String(internal)])).output.toString().trim();
  check(/^127\.0\.0\.1:[0-9]+$/.test(address), 'Fixture port must bind loopback');
  return Number(address.split(':')[1]);
};
async function freePort() {
  const server = createServer();
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const number = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return number;
}
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
async function startApi(side, password) {
  const p = await freePort(), pg = await port(side, 5432), cache = await port(`${side}-cache`, 6379);
  const child = spawn(join(root, 'target/debug/palmy-api'), ['serve'], {cwd: root, env: {...env,
    PALMY_ENV: 'development', CORS_ORIGINS: 'http://127.0.0.1:3100', BIND_ADDR: `127.0.0.1:${p}`,
    DATABASE_URL: `postgres://palmy_runtime:${password}@127.0.0.1:${pg}/palmy`, REDIS_URL: `redis://127.0.0.1:${cache}`}, stdio: 'ignore'});
  apis.push(child); child.on('error', () => {});
  const base = `http://127.0.0.1:${p}`;
  for (let i=0; i<100; i++) {
    if (abort.signal.aborted || child.exitCode !== null || child.signalCode !== null) throw new SafeFailure(`${side} API startup failed`);
    try { if ((await fetch(`${base}/health/ready`, {signal: AbortSignal.timeout(500)})).ok) return base; } catch {}
    await pause(100);
  }
  throw new SafeFailure(`${side} API readiness timed out`);
}
async function call(base, path, {method='GET',body,token,key,status=200}={}) {
  const response = await fetch(`${base}/api/v1${path}`, {method, headers: {...(body===undefined?{}:{'Content-Type':'application/json'}), ...(token?{Authorization:`Bearer ${token}`} : {}), ...(key?{'Idempotency-Key':key}:{})}, body:body===undefined?undefined:JSON.stringify(body), signal:AbortSignal.any([abort.signal, AbortSignal.timeout(15000)])});
  check(response.status===status, `HTTP ${method} fixture request returned unexpected status`);
  check(response.headers.get('cache-control')==='no-store', 'Private API response must not be cached');
  const text = await response.text();
  return text ? JSON.parse(text) : undefined;
}
const b64 = x => Buffer.from(x).toString('base64url');
function identity() {
  const account_id=randomUUID(), master=randomBytes(32);
  const derive=purpose=>Buffer.from(hkdfSync('sha256',master,'palmy:v1',`palmy:${purpose}:v1`,32));
  const key=createPrivateKey({key:Buffer.concat([Buffer.from('302e020100300506032b657004220420','hex'),derive('signing')]),format:'der',type:'pkcs8'});
  const who={account_id,key,public_key:createPublicKey(key).export({format:'jwk'}).x,profileKey:derive('profile')}; master.fill(0); return who;
}
const signature = (who, text) => b64(sign(null, Buffer.from(text), who.key));
function encrypt(who, profile) {
  const nonce=randomBytes(12), cipher=createCipheriv('aes-256-gcm',who.profileKey,nonce);
  cipher.setAAD(Buffer.from(`palmy:profile:v1:${who.account_id}`));
  return {version:1,algorithm:'A256GCM',nonce:b64(nonce),ciphertext:b64(Buffer.concat([cipher.update(JSON.stringify(profile)),cipher.final(),cipher.getAuthTag()]))};
}
function decrypt(who, envelope) {
  const bytes=Buffer.from(envelope.ciphertext,'base64url'), decipher=createDecipheriv('aes-256-gcm',who.profileKey,Buffer.from(envelope.nonce,'base64url'));
  decipher.setAAD(Buffer.from(`palmy:profile:v1:${who.account_id}`)); decipher.setAuthTag(bytes.subarray(-16));
  return JSON.parse(Buffer.concat([decipher.update(bytes.subarray(0,-16)),decipher.final()]).toString());
}
async function register(base, who, profile) {
  const envelope=encrypt(who, profile);
  await call(base,'/accounts',{method:'POST',status:201,body:{account_id:who.account_id,public_key:who.public_key,profile:envelope,signature:signature(who,`palmy:register:v1:${who.account_id}:${who.public_key}:${envelope.nonce}:${envelope.ciphertext}`)}});
}
async function proof(base, who) {
  const {data:c}=await call(base,'/auth/challenges',{method:'POST',body:{account_id:who.account_id}});
  return {account_id:who.account_id,challenge_id:c.challenge_id,signature:signature(who,`palmy:auth:v1:${who.account_id}:${c.challenge_id}:${c.nonce}`)};
}
async function login(base, who) { return (await call(base,'/auth/sessions',{method:'POST',body:await proof(base,who)})).data.access_token; }
async function keyPair(label) {
  await run('openssl',['req','-x509','-newkey','rsa:3072','-nodes','-sha256','-days','1','-subj','/CN=Palmy disposable restore fixture','-keyout',join(work,`${label}.key`),'-out',join(work,`${label}.crt`)]);
  await chmod(join(work,`${label}.key`),0o600);
}
const cmsDecrypt = (bytes, key='archive', options={}) => run('openssl',['cms','-decrypt','-binary','-inform','DER','-recip',join(work,'archive.crt'),'-inkey',join(work,`${key}.key`)], {input:bytes, ...options});

async function exercise() {
  console.log('Starting isolated synthetic backup drill. No development database is used.');
  await verifyLocalDocker();
  await writeFile(join(work,'empty.env'),'');
  const passwords = Object.fromEntries(['source','destination'].map(side => [side, {owner:randomBytes(24).toString('hex'),runtime:randomBytes(24).toString('hex')} ]));
  for (const side of ['source','destination']) await writeFile(join(work,`${side}-password`),passwords[side].owner,{mode:0o600});
  check((await run('docker',['ps','-aq','--filter',`label=com.docker.compose.project=${project}`])).output.length===0,'Unique container namespace');
  check((await run('docker',['volume','ls','-q','--filter',`label=com.docker.compose.project=${project}`])).output.length===0,'Unique volume namespace');
  const opensslVersion=(await run('openssl',['version'])).output.toString().split(' ').slice(0,2).join(' ');
  check(opensslVersion.startsWith('OpenSSL 3.'),'OpenSSL 3 with CMS GCM support is required');
  phase='compile fixture API';
  await run('cargo',['build','--locked','-p','palmy-api'],{timeout:600_000});
  phase='provision source'; created=true;
  await compose(['up','-d','--wait','--wait-timeout','90','source','source-cache']);
  check(await sql('source','SHOW server_version_num;')==='180006','Source PostgreSQL must be 18.6');
  await sql('source',`CREATE ROLE palmy_runtime LOGIN PASSWORD '${passwords.source.runtime}' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS; REVOKE CREATE ON SCHEMA public FROM PUBLIC; REVOKE ALL ON DATABASE palmy FROM PUBLIC; GRANT CONNECT ON DATABASE palmy TO palmy_runtime;`);
  const sourcePg=await port('source',5432);
  await run(join(root,'target/debug/palmy-api'),['migrate'],{environment:{...env,MIGRATION_DATABASE_URL:`postgres://palmy_owner:${passwords.source.owner}@127.0.0.1:${sourcePg}/palmy`}});
  const source=await startApi('source',passwords.source.runtime);
  phase='seed synthetic owners and ledger';
  const a=identity(), b=identity(), personal={display_name:'Disposable restore owner',email:'restore@example.invalid'};
  await register(source,a,{display_name:'Initial synthetic owner',email:''}); await register(source,b,{display_name:'Other synthetic owner',email:''});
  const oldToken=await login(source,a), bToken=await login(source,b);
  const profile=(await call(source,'/profile',{method:'PUT',token:oldToken,body:{version:1,profile:encrypt(a,personal)}})).data;
  const walletKey=randomUUID(), expenseKey=randomUUID();
  const walletBody={name:'Disposable wallet'};
  const wallet=(await call(source,'/wallets',{method:'POST',token:oldToken,key:walletKey,body:walletBody,status:201})).data;
  const otherWallet=(await call(source,'/wallets',{method:'POST',token:bToken,key:randomUUID(),body:{name:'Separate owner'},status:201})).data;
  const transaction={wallet_id:wallet.id,kind:'income',amount:'2000.00',category:'Fixture',description:'Synthetic only',effective_on:'2026-09-27'};
  await call(source,'/transactions',{method:'POST',token:oldToken,key:randomUUID(),body:transaction,status:201});
  const expense={...transaction,kind:'expense',amount:'1234.56'};
  const posted=(await call(source,'/transactions',{method:'POST',token:oldToken,key:expenseKey,body:expense,status:201})).data;
  const summary=(await call(source,'/summary',{token:oldToken})).data;
  assert.deepEqual(summary,{balance:'765.44',income:'2000.00',expense:'1234.56',currency:'IDR'}); checks++;
  const pendingProof=await proof(source,a);
  const migrations=await sql('source',"SELECT json_agg(row_to_json(m) ORDER BY version) FROM (SELECT version,description,success,encode(checksum,'hex') checksum FROM public._sqlx_migrations) m;");
  check(migrations!=='' && migrations!=='null','Source migration history exists');
  await keyPair('archive'); await keyPair('wrong');
  phase='encrypted snapshot'; const snapshotStarted=Date.now(), snapshotClock=performance.now();
  const dump=(await compose(['exec','-T','source','pg_dump','-U','palmy_owner','-d','palmy','--format=custom','--compress=gzip:6'])).output;
  const dumpBytes=dump.length;
  const encrypted=(await run('openssl',['cms','-encrypt','-binary','-aes-256-gcm','-outform','DER','-recip',join(work,'archive.crt'),'-keyopt','rsa_padding_mode:oaep','-keyopt','rsa_oaep_md:sha256'],{input:dump})).output;
  dump.fill(0);
  await writeFile(join(work,'snapshot.cms'),encrypted,{mode:0o600});
  timings.backup_seconds=(performance.now()-snapshotClock)/1000;
  const wrong=await cmsDecrypt(encrypted,'wrong',{allowFailure:true});
  check(wrong.code>0,'Wrong archive key must fail authentication'); wrong.output.fill(0);
  const tampered=Buffer.from(encrypted); tampered[tampered.length-1]^=1;
  const damaged=await cmsDecrypt(tampered,'archive',{allowFailure:true});
  check(damaged.code>0,'Tampered archive must fail authentication'); damaged.output.fill(0); tampered.fill(0);
  const truncated=await cmsDecrypt(encrypted.subarray(0,-32),'archive',{allowFailure:true});
  check(truncated.code>0,'Truncated archive must fail'); truncated.output.fill(0);
  console.log('PASS: authenticated encrypted snapshot; wrong-key, tamper and truncation failures rejected before restore.');
  if (process.argv.includes('--inject-failure-after-backup')) throw new SafeFailure('Injected failure after encrypted backup; cleanup must still complete');
  // Deliberate post-snapshot events demonstrate recovery-point loss and credential rollback risk.
  const lost=(await call(source,'/transactions',{method:'POST',token:oldToken,key:randomUUID(),body:{...expense,amount:'0.37'},status:201})).data;
  await call(source,'/profile',{method:'PUT',token:oldToken,body:{version:2,profile:encrypt(a,{display_name:'Post-snapshot change',email:''})}});
  await call(source,'/auth/session',{method:'DELETE',token:oldToken,status:204});
  await call(source,'/auth/sessions',{method:'POST',body:pendingProof});
  await call(source,'/summary',{token:oldToken,status:401});
  const incident=Date.now(); timings.snapshot_age_at_incident_seconds=(incident-snapshotStarted)/1000;
  phase='restore into new destination'; const restoreClock=performance.now();
  await compose(['up','-d','--wait','--wait-timeout','90','destination','destination-cache']);
  check(await sql('destination','SHOW server_version_num;')==='180006','Destination PostgreSQL must be 18.6');
  await sql('destination',`CREATE ROLE palmy_runtime NOLOGIN PASSWORD '${passwords.destination.runtime}' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS; REVOKE CREATE ON SCHEMA public FROM PUBLIC; REVOKE ALL ON DATABASE palmy FROM PUBLIC; GRANT CONNECT ON DATABASE palmy TO palmy_runtime;`);
  check(await sql('destination',"SELECT count(*) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema');")==='0','Restore destination must contain no application tables');
  check(await sql('source',"SELECT system_identifier FROM pg_control_system();")!==await sql('destination',"SELECT system_identifier FROM pg_control_system();"),'Destination must be a distinct PostgreSQL cluster');
  const decrypted=(await cmsDecrypt(await readFile(join(work,'snapshot.cms')))).output;
  // Do not pipe partial unauthenticated plaintext to pg_restore: decrypt must exit successfully first.
  await compose(['exec','-T','destination','pg_restore','-U','palmy_owner','-d','palmy','--single-transaction','--exit-on-error'],{input:decrypted}); decrypted.fill(0);
  check(await sql('destination',"SELECT count(*) FROM palmy.sessions;")==='2','Snapshot includes old sessions for the restore-boundary test');
  check(await sql('destination',"SELECT count(*) FROM palmy.challenges;")==='1','Snapshot includes a previously unconsumed challenge');
  // No destination API exists yet and runtime is NOLOGIN. Purge rollback-prone auth before reopening.
  await sql('destination','BEGIN; TRUNCATE palmy.sessions, palmy.challenges; ALTER ROLE palmy_runtime LOGIN; COMMIT;');
  check(await sql('destination',"SELECT (SELECT count(*) FROM palmy.sessions)+(SELECT count(*) FROM palmy.challenges);")==='0','Authentication state must be empty before restored API starts');
  check((await compose(['exec','-T','destination-cache','valkey-cli','DBSIZE'])).output.toString().trim()==='0','Destination cache must start empty');
  check(await sql('destination',"SELECT json_agg(row_to_json(m) ORDER BY version) FROM (SELECT version,description,success,encode(checksum,'hex') checksum FROM public._sqlx_migrations) m;")===migrations,'SQLx versions/checksums/success preserved');
  phase='verify restored database invariants';
  await sql('destination',`BEGIN;
DO $$ BEGIN
 IF EXISTS(SELECT FROM pg_roles WHERE rolname='palmy_runtime' AND (rolsuper OR rolbypassrls OR rolcreatedb OR rolcreaterole)) THEN RAISE EXCEPTION 'unsafe role'; END IF;
 IF EXISTS(SELECT FROM pg_class c JOIN pg_roles r ON r.oid=c.relowner WHERE r.rolname='palmy_runtime') THEN RAISE EXCEPTION 'runtime owns table'; END IF;
 IF EXISTS(SELECT FROM pg_auth_members WHERE member=(SELECT oid FROM pg_roles WHERE rolname='palmy_runtime')) THEN RAISE EXCEPTION 'runtime role membership'; END IF;
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='palmy' AND c.relrowsecurity AND c.relforcerowsecurity)<>6 THEN RAISE EXCEPTION 'RLS lost'; END IF;
 IF EXISTS(SELECT FROM palmy.journals j LEFT JOIN palmy.entries e ON e.journal_id=j.id GROUP BY j.id HAVING count(e.id)<>2 OR sum(e.amount) IS DISTINCT FROM 0 OR max(e.amount) FILTER(WHERE e.account_kind='wallet') IS DISTINCT FROM (CASE WHEN j.kind='income' THEN j.amount ELSE -j.amount END) OR bool_and(e.wallet_id=j.wallet_id) FILTER(WHERE e.account_kind='wallet') IS DISTINCT FROM true) THEN RAISE EXCEPTION 'unbalanced restored journal'; END IF;
 IF (SELECT count(*) FROM palmy.journals)<>2 OR (SELECT count(*) FROM palmy.entries)<>4 THEN RAISE EXCEPTION 'snapshot row counts'; END IF;
 BEGIN UPDATE palmy.journals SET amount=7 WHERE id='${posted.id}'; RAISE EXCEPTION 'journal rewrite accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN DELETE FROM palmy.entries WHERE journal_id='${posted.id}'; RAISE EXCEPTION 'posting delete accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
SET LOCAL ROLE palmy_runtime;
DO $$ BEGIN IF EXISTS(SELECT FROM palmy.wallets) OR EXISTS(SELECT FROM palmy.profiles) THEN RAISE EXCEPTION 'missing-context disclosure'; END IF; END $$;
SELECT set_config('palmy.account_id','${a.account_id}',true);
DO $$ BEGIN
 IF (SELECT count(*) FROM palmy.wallets)<>1 OR (SELECT count(*) FROM palmy.profiles)<>1 THEN RAISE EXCEPTION 'owner row visibility'; END IF;
 IF EXISTS(SELECT FROM palmy.wallets WHERE id='${otherWallet.id}') THEN RAISE EXCEPTION 'cross-owner read'; END IF;
 IF (SELECT sum(amount) FROM palmy.entries WHERE wallet_id='${wallet.id}')<>765.44 THEN RAISE EXCEPTION 'decimal corruption'; END IF;
 BEGIN INSERT INTO palmy.wallets(id,owner_id,name) VALUES(gen_random_uuid(),'${b.account_id}','Forbidden'); RAISE EXCEPTION 'cross-owner insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN UPDATE palmy.entries SET amount=7; RAISE EXCEPTION 'runtime mutation privilege'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO palmy.journals(id,owner_id,wallet_id,kind,amount,category,description,effective_on) VALUES(gen_random_uuid(),'${a.account_id}','${otherWallet.id}','expense',1,'Fixture','','2026-09-27'); RAISE EXCEPTION 'foreign-owner reference'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO palmy.journals(id,owner_id,wallet_id,kind,amount,category,description,effective_on) VALUES(gen_random_uuid(),'${a.account_id}','${wallet.id}','expense',1,'Fixture','','2026-09-27'); SET CONSTRAINTS ALL IMMEDIATE; RAISE EXCEPTION 'unbalanced insert accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
SELECT set_config('palmy.account_id','${b.account_id}',true);
DO $$ BEGIN IF EXISTS(SELECT FROM palmy.journals) OR EXISTS(SELECT FROM palmy.entries) OR EXISTS(SELECT FROM palmy.idempotency WHERE owner_id='${a.account_id}') THEN RAISE EXCEPTION 'owner isolation'; END IF; END $$;
ROLLBACK;`); checks+=14;
  const destination=await startApi('destination',passwords.destination.runtime);
  phase='verify restored API and recovery';
  await call(destination,'/summary',{token:oldToken,status:401});
  await call(destination,'/profile',{token:bToken,status:401});
  await call(destination,'/auth/sessions',{method:'POST',body:pendingProof,status:401});
  const token=await login(destination,a), other=await login(destination,b);
  const restoredProfile=(await call(destination,'/profile',{token})).data;
  assert.deepEqual(restoredProfile,profile); assert.deepEqual(decrypt(a,restoredProfile.profile),personal);
  assert.throws(()=>decrypt(b,restoredProfile.profile)); checks+=3;
  assert.deepEqual((await call(destination,'/summary',{token})).data,summary);
  assert.deepEqual((await call(destination,'/transactions',{token:other})).data,[]);
  check((await call(destination,'/summary',{token:other})).data.balance==='0.00','Separate owner balance');
  check((await call(destination,'/wallets',{token:other})).data.every(w=>w.id!==wallet.id),'Owner wallet isolation');
  await call(destination,'/transactions',{method:'POST',token:other,key:randomUUID(),body:expense,status:404});
  const entries=(await call(destination,'/transactions',{token})).data;
  check(entries.length===2 && !entries.some(e=>e.id===lost.id),'Post-snapshot transaction is deliberately absent');
  const walletReplay=(await call(destination,'/wallets',{method:'POST',token,key:walletKey,body:walletBody,status:201})).data;
  check(walletReplay.id===wallet.id,'Wallet idempotency record survives restore');
  const replays=await Promise.all(Array.from({length:4},()=>call(destination,'/transactions',{method:'POST',token,key:expenseKey,body:expense,status:201})));
  check(replays.every(r=>r.data.id===posted.id),'Concurrent idempotency replay returns original journal');
  await call(destination,'/transactions',{method:'POST',token,key:expenseKey,body:{...expense,amount:'1234.57'},status:409});
  check((await call(destination,'/transactions',{token})).data.length===2,'Restore retry cannot duplicate the journal');
  assert.deepEqual((await call(destination,'/summary',{token})).data,summary); checks++;
  timings.restore_and_verification_seconds=(performance.now()-restoreClock)/1000;
  phase='verify fresh post-restore writes';
  await call(destination,'/transactions',{method:'POST',token,key:randomUUID(),body:{...expense,amount:'0.01'},status:201});
  check((await call(destination,'/summary',{token})).data.balance==='765.43','New write advances restored revision/cache exactly');
  const next=(await call(destination,'/profile',{method:'PUT',token,body:{version:restoredProfile.version,profile:encrypt(a,personal)}})).data;
  check(next.version===3,'Restored profile optimistic version progresses');
  await call(destination,'/profile',{method:'PUT',token,body:{version:2,profile:encrypt(a,personal)},status:409});
  timings.total_exercise_seconds=(performance.now()-begun)/1000;
  console.log(`PASS: ${checks} checks; two synthetic owners, two snapshot journals/four postings, RLS/roles, profile decryption, auth reset, and durable concurrent idempotency.`);
  console.log(JSON.stringify({operator:'Codex (development drill)',project_lead:'Rohman M',postgres:'18.6',openssl:opensslVersion,custom_dump_bytes:dumpBytes,encrypted_archive_bytes:encrypted.length,...Object.fromEntries(Object.entries(timings).map(([k,v])=>[k,Number(v.toFixed(3))])),snapshot_loss:'one later expense and one later profile edit excluded as expected',proposed_rpo_hours:24,proposed_rto_hours:4,production_sla_proven:false}));
}

let failed = false;
try { await exercise(); }
catch (error) { failed=true; console.error(error instanceof SafeFailure ? `FAIL: ${error.message}` : `FAIL: ${phase}; assertion/transport details withheld to protect fixture credentials and data`); }
finally {
  for (const child of apis) {
    if (child.exitCode===null && child.signalCode===null) {
      child.kill('SIGTERM');
      await Promise.race([new Promise(resolve=>child.once('exit',resolve)),pause(3000)]);
      if (child.exitCode===null && child.signalCode===null) child.kill('SIGKILL');
    }
  }
  phase='cleanup';
  try {
    if (dockerSafe) {
      if (created) await compose(['down','--volumes','--remove-orphans','--timeout','5'],{cleanup:true,timeout:60_000});
      check((await run('docker',['ps','-aq','--filter',`label=com.docker.compose.project=${project}`],{cleanup:true})).output.length===0,'Owned containers remain');
      check((await run('docker',['volume','ls','-q','--filter',`label=com.docker.compose.project=${project}`],{cleanup:true})).output.length===0,'Owned volumes remain');
    }
    await rm(work,{recursive:true,force:true});
    console.log('PASS: only this drill\'s containers/volumes removed; temporary key/archive directory deleted.');
  } catch { failed=true; console.error(`Cleanup incomplete. Inspect only Docker project ${project}; do not prune unrelated resources.`); }
  await rm(work,{recursive:true,force:true});
}
if (failed || abort.signal.aborted) process.exitCode=1;
