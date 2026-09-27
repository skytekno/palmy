// Real HTTP/PG integration, using Node crypto independently of all client libraries.
// Creates only synthetic accounts in the configured local development database.
import assert from 'node:assert/strict';
import { randomBytes, randomUUID, hkdfSync, createPrivateKey, createPublicKey, createCipheriv, createDecipheriv, sign } from 'node:crypto';
const base = process.env.PALMY_TEST_API_URL ?? 'http://127.0.0.1:8100';
if (!['localhost','127.0.0.1','[::1]'].includes(new URL(base).hostname)) throw new Error('Integration fixture creation is restricted to a local API.');
let checks = 0;
const b64 = x => Buffer.from(x).toString('base64url');
async function call(path, {method='GET',body,token,key,status=200}={}) {
 const response = await fetch(`${base}${path}`, {method,headers:{...(body===undefined?{}:{'Content-Type':'application/json'}),...(token?{Authorization:`Bearer ${token}`} : {}),...(key?{'Idempotency-Key':key}:{})},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
 const text=await response.text();
 assert.equal(response.status,status,`${method} ${path}: expected ${status}, got ${response.status}; ${text}`);
 checks++;
 if (path.startsWith('/api/')) assert.equal(response.headers.get('cache-control'),'no-store');
 if(status>=400) {
   assert.match(response.headers.get('content-type')??'',/application\/problem\+json/);
   const problem=JSON.parse(text); assert.equal(problem.status,status); assert.ok(problem.request_id); assert.ok(problem.code);
   assert.doesNotMatch(text,/postgres:\/\/|password|SELECT |INSERT |panic/i);
 }
 return text?JSON.parse(text):undefined;
}
function identity() {
 const account_id=randomUUID(); const master=randomBytes(32);
 const derive=purpose=>Buffer.from(hkdfSync('sha256',master,'palmy:v1',`palmy:${purpose}:v1`,32));
 const key=createPrivateKey({key:Buffer.concat([Buffer.from('302e020100300506032b657004220420','hex'),derive('signing')]),format:'der',type:'pkcs8'});
 return {account_id,public_key:createPublicKey(key).export({format:'jwk'}).x,key,profileKey:derive('profile')};
}
const signature=(who,message)=>b64(sign(null,Buffer.from(message),who.key));
function encrypt(who,profile) {
 const nonce=randomBytes(12), cipher=createCipheriv('aes-256-gcm',who.profileKey,nonce);
 cipher.setAAD(Buffer.from(`palmy:profile:v1:${who.account_id}`));
 const ciphertext=Buffer.concat([cipher.update(JSON.stringify(profile),'utf8'),cipher.final(),cipher.getAuthTag()]);
 return {version:1,algorithm:'A256GCM',nonce:b64(nonce),ciphertext:b64(ciphertext)};
}
function decrypt(who,envelope) {
 const bytes=Buffer.from(envelope.ciphertext,'base64url');
 const decipher=createDecipheriv('aes-256-gcm',who.profileKey,Buffer.from(envelope.nonce,'base64url'));
 decipher.setAAD(Buffer.from(`palmy:profile:v1:${who.account_id}`)); decipher.setAuthTag(bytes.subarray(-16));
 return JSON.parse(Buffer.concat([decipher.update(bytes.subarray(0,-16)),decipher.final()]).toString());
}
async function register(who,profile) {
 const envelope=encrypt(who,profile);
 const body={account_id:who.account_id,public_key:who.public_key,profile:envelope,signature:signature(who,`palmy:register:v1:${who.account_id}:${who.public_key}:${envelope.nonce}:${envelope.ciphertext}`)};
 const result=await call('/api/v1/accounts',{method:'POST',body,status:201}); assert.equal(result.data.account_id,who.account_id); return body;
}
async function proof(who) {
 const {data:c}=await call('/api/v1/auth/challenges',{method:'POST',body:{account_id:who.account_id}});
 return {account_id:who.account_id,challenge_id:c.challenge_id,signature:signature(who,`palmy:auth:v1:${who.account_id}:${c.challenge_id}:${c.nonce}`)};
}
async function login(who) {
 const body=await proof(who); return (await call('/api/v1/auth/sessions',{method:'POST',body})).data.access_token;
}
await call('/health/live'); await call('/health/ready');
// CORS is a browser response allowlist, not authentication or a network firewall.
for (const [origin, allowed] of [['http://localhost:3100',true],['http://localhost:3100.attacker.invalid',false],['https://attacker.invalid',false],['null',false]]) {
 const response=await fetch(`${base}/api/v1/profile`,{method:'OPTIONS',headers:{Origin:origin,'Access-Control-Request-Method':'GET','Access-Control-Request-Headers':'authorization'}});
 assert.equal(response.headers.get('access-control-allow-origin'),allowed?origin:null);
 assert.equal(response.headers.get('access-control-allow-credentials'),null);
 assert.match(response.headers.get('vary')??'',/origin/i);
 checks++;
}
for (const path of ['/health/live','/api/v1/profile','/does-not-exist?private=synthetic-delivery-canary']) {
 const response=await fetch(`${base}${path}`,{headers:{Origin:'http://localhost:3100'}});
 assert.equal(response.headers.get('access-control-allow-origin'),'http://localhost:3100');
 assert.equal(response.headers.get('cache-control'),'no-store');
 assert.equal(response.headers.get('referrer-policy'),'no-referrer');
 assert.equal(response.headers.get('x-frame-options'),'DENY');
 assert.equal(response.headers.get('x-content-type-options'),'nosniff');
 assert.equal(response.headers.get('content-security-policy'),"default-src 'none'; frame-ancestors 'none'");
 checks++;
}
const openapi=await call('/openapi.json'); assert.match(openapi.openapi,/^3\.1\./); assert.ok(openapi.paths['/api/v1/accounts']);
await call('/api/v1/profile',{status:401}); await call('/api/v1/wallets',{status:401}); await call('/api/v1/summary',{token:b64(randomBytes(32)),status:401});
const a=identity(), b=identity(); const personal={display_name:'Synthetic Test Owner',email:'private-test@example.invalid'};
const registration=await register(a,personal); await register(b,{display_name:'Other Test Owner',email:''});
await call('/api/v1/accounts',{method:'POST',body:registration,status:409});
await call('/api/v1/accounts',{method:'POST',body:{...registration,account_id:randomUUID()},status:401});
const challenge=await proof(a);
const session=(await call('/api/v1/auth/sessions',{method:'POST',body:challenge})).data;
await call('/api/v1/auth/sessions',{method:'POST',body:challenge,status:401});
const token=session.access_token, other=await login(b);
const unknown=identity(); const unknownProof=await proof(unknown); await call('/api/v1/auth/sessions',{method:'POST',body:unknownProof,status:401});
const invalidProof=await proof(a); invalidProof.signature=b64(randomBytes(64));
await call('/api/v1/auth/sessions',{method:'POST',body:invalidProof,status:401});
const fetched=(await call('/api/v1/profile',{token})).data; assert.deepEqual(decrypt(a,fetched.profile),personal);
assert.ok(!JSON.stringify(fetched).includes(personal.email)); assert.throws(()=>decrypt(b,fetched.profile));
const edited={display_name:'Edited Synthetic Owner',email:'changed@example.invalid'};
const replacement=encrypt(a,edited);
const updated=(await call('/api/v1/profile',{method:'PUT',token,body:{profile:replacement,version:fetched.version}})).data;
assert.equal(updated.version,fetched.version+1);
await call('/api/v1/profile',{method:'PUT',token,body:{profile:replacement,version:fetched.version},status:409});
assert.deepEqual(decrypt(a,(await call('/api/v1/profile',{token})).data.profile),edited);
await call('/api/v1/profile',{method:'PUT',token,body:{profile:{...replacement,email:'plaintext'},version:updated.version},status:400});
assert.deepEqual((await call('/api/v1/wallets',{token:other})).data,[]);
const walletKey=randomUUID();
const wallet=(await call('/api/v1/wallets',{method:'POST',token,key:walletKey,body:{name:'Synthetic Wallet'},status:201})).data;
assert.equal(wallet.balance,'0.00');
const replay=(await call('/api/v1/wallets',{method:'POST',token,key:walletKey,body:{name:'Synthetic Wallet'},status:201})).data; assert.equal(replay.id,wallet.id);
await call('/api/v1/wallets',{method:'POST',token,key:walletKey,body:{name:'Changed'},status:409});
await call('/api/v1/wallets',{method:'POST',token,key:randomUUID(),body:{name:'Forged owner',owner_id:b.account_id},status:400});
const tx={wallet_id:wallet.id,kind:'income',amount:'2000',category:'Lainnya',description:'Synthetic finance fixture',effective_on:'2026-09-27'};
await call('/api/v1/transactions',{method:'POST',token:other,key:randomUUID(),body:tx,status:404});
await call('/api/v1/transactions',{method:'POST',token,key:randomUUID(),body:{...tx,owner_id:b.account_id},status:400});
for(const amount of ['-1','0','1.001','1e3','NaN','10000000000000000',' 1','01']) await call('/api/v1/transactions',{method:'POST',token,key:randomUUID(),body:{...tx,amount},status:400});
const txKey=randomUUID();
const income=(await call('/api/v1/transactions',{method:'POST',token,key:txKey,body:tx,status:201})).data; assert.equal(income.amount,'2000.00');
const same=(await call('/api/v1/transactions',{method:'POST',token,key:txKey,body:tx,status:201})).data; assert.equal(same.id,income.id);
await call('/api/v1/transactions',{method:'POST',token,key:txKey,body:{...tx,amount:'2001'},status:409});
// Prime cache before write; old cache value must never appear after the write commits.
assert.equal((await call('/api/v1/summary',{token})).data.balance,'2000.00');
const expense={...tx,kind:'expense',amount:'1234.56'};
const concurrentKey=randomUUID();
const repeated=await Promise.all(Array.from({length:6},()=>call('/api/v1/transactions',{method:'POST',token,key:concurrentKey,body:expense,status:201})));
assert.equal(new Set(repeated.map(r=>r.data.id)).size,1);
for(let i=0;i<3;i++) assert.deepEqual((await call('/api/v1/summary',{token})).data,{balance:'765.44',income:'2000.00',expense:'1234.56',currency:'IDR'});
assert.equal((await call('/api/v1/wallets',{token})).data[0].balance,'765.44');
assert.equal((await call('/api/v1/transactions',{token})).data.length,2);
assert.deepEqual((await call('/api/v1/transactions',{token:other})).data,[]);
assert.equal((await call('/api/v1/summary',{token:other})).data.balance,'0.00');
const page=await call('/api/v1/transactions?limit=1',{token}); assert.equal(page.data.length,1); assert.ok(page.next_cursor);
const next=await call(`/api/v1/transactions?limit=1&before=${page.next_cursor}`,{token}); assert.equal(next.data.length,1); assert.notEqual(next.data[0].id,page.data[0].id);
await call(`/api/v1/transactions?before=${income.id}`,{token:other,status:400});
await call('/api/v1/transactions?limit=101',{token,status:400});
const raceProof=await proof(a);
const race=await Promise.all(Array.from({length:2},()=>fetch(`${base}/api/v1/auth/sessions`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(raceProof)})));
assert.deepEqual(race.map(r=>r.status).sort(),[200,401]); checks++;
await call('/api/v1/auth/session',{method:'DELETE',token,status:204});
await call('/api/v1/profile',{token,status:401}); await call('/api/v1/summary',{token,status:401});
const recovered=await login(a); assert.deepEqual(decrypt(a,(await call('/api/v1/profile',{token:recovered})).data.profile),edited);
await call('/api/v1/auth/session',{method:'DELETE',token:recovered,status:204}); await call('/api/v1/auth/session',{method:'DELETE',token:other,status:204});
console.log(`PASS: ${checks} real HTTP assertions, encrypted profile recovery, cross-owner isolation, replay/concurrent challenge rejection, exact money, idempotent concurrent posting, cache revision, pagination, and revocation.`);
