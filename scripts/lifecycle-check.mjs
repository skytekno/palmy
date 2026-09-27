// MAN-115 acceptance reference ONLY. No network, database, runtime API or HPKE implementation.
// All deterministic keys and nonces below are PUBLIC TEST DATA; never use them for an account.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {createHash, hkdfSync, createPrivateKey, createPublicKey, createCipheriv, createDecipheriv, sign, verify} from 'node:crypto';

const root = new URL('../', import.meta.url);
const b64 = value => Buffer.from(value).toString('base64url');
const hash = value => createHash('sha256').update(value).digest();
const counter = value => {
  assert.equal(typeof value, 'string');
  assert.match(value, /^[1-9][0-9]{0,18}$/);
  assert.ok(BigInt(value) <= 9223372036854775807n);
  return value;
};
// Restricted JCS reference: production still needs reviewed strict parsing/canonicalization.
function jcs(value) {
  if (value === null || typeof value === 'boolean') return JSON.stringify(value);
  if (typeof value === 'string') { assert.ok(value.isWellFormed(), 'lone Unicode surrogate'); return JSON.stringify(value); }
  if (Array.isArray(value)) return `[${value.map(jcs).join(',')}]`;
  assert.equal(typeof value, 'object', 'wire numbers/undefined are forbidden');
  assert.equal(Object.getPrototypeOf(value), Object.prototype);
  return `{${Object.keys(value).sort().map(key => {
    assert.match(key, /^[a-z][a-z0-9_]*$/);
    return `${JSON.stringify(key)}:${jcs(value[key])}`;
  }).join(',')}}`;
}
function transcript(purpose, payload) {
  assert.match(purpose, /^[a-z_]+$/);
  return Buffer.concat([Buffer.from(`palmy:lifecycle:v2\0${purpose}\0`), hash(jcs(payload))]);
}
function signingKey(seed) {
  return createPrivateKey({key: Buffer.concat([Buffer.from('302e020100300506032b657004220420','hex'), seed]),format:'der',type:'pkcs8'});
}
const publicKey = key => createPublicKey(key).export({format:'jwk'}).x;
function vectors() {
  const recovery = Buffer.from(Array.from({length:32},(_,i)=>i));
  const seed = Buffer.from(hkdfSync('sha256', recovery, 'palmy:v2', 'palmy:root-signing:v2', 32));
  const recipientIkm = Buffer.from(hkdfSync('sha256', recovery, 'palmy:v2', 'palmy:root-recipient:v2', 32));
  const key = signingKey(seed);
  const account = '11111111-1111-4111-8111-111111111111';
  const payload = {protocol:'2',account_id:account,actor_kind:'root',actor_id:'root',operation_id:'22222222-2222-4222-8222-222222222222',challenge_id:'33333333-3333-4333-8333-333333333333',nonce:b64(Buffer.alloc(32, 0x44)),expires_at:'2030-01-01T00:02:00Z',credential_revision:'7',profile_revision:'9',session_epoch:'3',payload_hash:b64(hash('PUBLIC reference operation payload; not an endpoint request'))};
  const purpose = 'rotation_authorize';
  const aad = {account_id:account,key_generation:'2',profile_revision:'10',purpose:'palmy:profile:v2'};
  const profileKey = Buffer.from(Array.from({length:32},(_,i)=>0xa0+i));
  const nonce = Buffer.from(Array.from({length:12},(_,i)=>0x10+i));
  const profile = {display_name:'Public lifecycle fixture',email:'lifecycle@example.invalid'};
  const plaintext = JSON.stringify(profile);
  const cipher = createCipheriv('aes-256-gcm', profileKey, nonce);
  cipher.setAAD(Buffer.from(jcs(aad)));
  const ciphertext = Buffer.concat([cipher.update(plaintext,'utf8'),cipher.final(),cipher.getAuthTag()]);
  return {
    warning:'PUBLIC TEST MATERIAL ONLY. Not a valid lifecycle endpoint request. No HPKE envelope implementation is supplied.',
    proposal_version:'palmy-lifecycle/2-draft1',
    root_derivation:{recovery_secret:b64(recovery),root_signing_seed:b64(seed),root_signing_public_key:publicKey(key),root_recipient_ikm:b64(recipientIkm),note:'recipient_ikm is input to RFC 9180 DeriveKeyPair; it is not a raw X25519 private scalar'},
    proof:{purpose,payload,canonical_payload:jcs(payload),transcript_hex:transcript(purpose,payload).toString('hex'),signature:b64(sign(null,transcript(purpose,payload),key))},
    profile:{key:b64(profileKey),aad,canonical_aad:jcs(aad),plaintext,envelope:{version:'2',algorithm:'A256GCM',key_generation:'2',profile_revision:'10',nonce:b64(nonce),ciphertext:b64(ciphertext)}}
  };
}

const NORMAL = ['finance:read','finance:write','profile:read','profile:write'];
const MANAGEMENT = ['device:enroll','device:revoke','session:revoke_all'];
const controller = [...NORMAL,...MANAGEMENT].sort();
const fail = code => { throw Object.assign(new Error(code),{code}); };
const expectCode = (code, action) => assert.throws(action, error => error.code === code);
const device = (id,scopes=controller) => ({id,scopes:[...scopes].sort(),status:'active',revision:1});

// Actor strings represent ALREADY verified signatures. This model is not an authentication service.
class Model {
  constructor() {
    this.state={root:'root-1',rootGeneration:1,epoch:1,revision:1,profileGeneration:1,profileRevision:1,profile:'old-cipher',mode:'active',devices:{a:device('a'),b:device('b',NORMAL)},recipients:['root','a','b'],writes:0};
    this.sessions = new Map(); this.operations = new Map(); this.challenges = new Map(); this.n=0;
  }
  actor(who,scope) {
    if (who===this.state.root) return;
    const d=this.state.devices[who];
    if (!d || d.status!=='active') fail('INVALID_PROOF');
    if (scope && !d.scopes.includes(scope)) fail('INSUFFICIENT_SCOPE');
  }
  challenge(who) {
    const id=++this.n;
    this.challenges.set(id,{who,epoch:this.state.epoch,revision:this.state.revision,used:false}); return id;
  }
  login(id) {
    const c=this.challenges.get(id);
    if (!c || c.used) fail('INVALID_PROOF'); c.used=true;
    if (!this.state.devices[c.who]) fail('INVALID_PROOF');
    this.actor(c.who);
    if (c.epoch!==this.state.epoch || c.revision!==this.state.revision) fail('INVALID_PROOF');
    const token=`reference-session-${++this.n}`;
    this.sessions.set(token,{who:c.who,epoch:c.epoch}); return token;
  }
  token(who='a') { return this.login(this.challenge(who)); }
  authorize(token,scope) {
    const session=this.sessions.get(token);
    if (!session || session.epoch!==this.state.epoch) fail('INVALID_PROOF');
    this.actor(session.who,scope); return session.who;
  }
  write(token) { this.authorize(token,'finance:write'); this.state.writes++; }
  profileEdit(token) {
    this.authorize(token,'profile:write');
    if (this.state.mode!=='active') fail('PROFILE_REKEY_REQUIRED');
    this.state.profileRevision++; this.state.profile=`edited-${this.state.profileRevision}`;
  }
  revokeAll(who) {
    this.actor(who,'session:revoke_all'); this.state.epoch++; this.state.revision++;
  }
  revokeDevice(who,target,withRekey=false) {
    this.actor(who,'device:revoke');
    if(withRekey) { this.actor(who,'profile:read'); this.actor(who,'profile:write'); }
    const d=this.state.devices[target];
    if (!d || d.status!=='active') fail('INVALID_PROOF');
    const next=structuredClone(this.state);
    next.devices[target].status='revoked'; next.epoch++; next.revision++;
    next.recipients=next.recipients.filter(x=>x!==target);
    if (d.scopes.includes('profile:read')) {
      next.mode=withRekey?'active':'rekey_required';
      if(withRekey) { next.profileGeneration++; next.profileRevision++; next.profile='rekey-cipher'; }
    }
    this.state=next;
  }
  expected() { return {epoch:this.state.epoch,revision:this.state.revision,profileRevision:this.state.profileRevision}; }
  checkExpected(expected) {
    if (JSON.stringify(expected)!==JSON.stringify(this.expected())) fail('REVISION_CONFLICT');
  }
  prepareRotation(who,id,{saved=true,newRoot='root-2',newDevice='c',recipients=['root','c']}={}) {
    if (who!==this.state.root) fail('INSUFFICIENT_SCOPE');
    if (!saved) fail('SAVE_NEW_RECOVERY_REQUIRED');
    const proposal={newRoot,newDevice,recipients};
    if (newRoot===this.state.root || this.state.devices[newDevice]) fail('FRESH_CREDENTIALS_REQUIRED');
    const existing=this.operations.get(id);
    if(existing) {
      if(JSON.stringify(existing.proposal)!==JSON.stringify(proposal)) fail('IDEMPOTENCY_CONFLICT');
      return existing;
    }
    if([...this.operations.values()].some(op=>op.kind==='rotation'&&op.status==='prepared')) fail('OPERATION_IN_PROGRESS');
    const op={kind:'rotation',status:'prepared',oldRoot:who,expected:this.expected(),proposal,expires:600};
    this.operations.set(id,op); return op;
  }
  commitRotation(id,{now=0,fault=false}={}) {
    const op=this.operations.get(id);
    if (!op || op.status!=='prepared') fail('OPERATION_FINAL');
    if(now>=op.expires) fail('OPERATION_EXPIRED');
    this.checkExpected(op.expected);
    const {newRoot,newDevice,recipients}=op.proposal;
    if(JSON.stringify([...recipients].sort())!==JSON.stringify(['root',newDevice].sort())) fail('RECIPIENT_SET_MISMATCH');
    const next=structuredClone(this.state);
    next.root=newRoot; next.rootGeneration++; next.profileGeneration++; next.profileRevision++;
    next.epoch++; next.revision++; next.profile='new-cipher'; next.mode='active';
    for(const d of Object.values(next.devices)) d.status='revoked';
    next.devices[newDevice]=device(newDevice); next.recipients=[...recipients];
    if(fault) fail('INJECTED_TRANSACTION_FAILURE');
    this.state=next; op.status='committed'; op.receipt=this.expected();
  }
  status(id,who) {
    const op=this.operations.get(id);
    if(!op || ![op.oldRoot,op.proposal?.newRoot].includes(who)) fail('INVALID_PROOF');
    return {status:op.status,receipt:op.receipt??null};
  }
  abort(id,who) {
    const op=this.operations.get(id);
    if (!op || who!==op.oldRoot) fail('INVALID_PROOF');
    if(op.status!=='prepared') fail('OPERATION_FINAL'); op.status='aborted';
  }
  prepareEnrollment(who,id,scopes=NORMAL,{verified=true}={}) {
    this.actor(who,'device:enroll');
    if(!verified) fail('UNVERIFIED_KEY');
    if(new Set(scopes).size!==scopes.length || scopes.some(s=>!controller.includes(s)) || (scopes.includes('finance:write')&&!scopes.includes('finance:read')) || (scopes.includes('profile:write')&&!scopes.includes('profile:read'))) fail('INVALID_REQUEST');
    if(who!==this.state.root && scopes.some(s=>MANAGEMENT.includes(s))) fail('INSUFFICIENT_SCOPE');
    if(who!==this.state.root && scopes.some(s=>!this.state.devices[who].scopes.includes(s))) fail('INSUFFICIENT_SCOPE');
    if(this.state.mode==='rekey_required' && scopes.includes('profile:read')) fail('PROFILE_REKEY_REQUIRED');
    if(this.state.devices[id]) fail('FRESH_CREDENTIALS_REQUIRED');
    this.operations.set(id,{kind:'enroll',status:'prepared',who,scopes,expected:this.expected()});
  }
  activate(id,{ack=true,confirmation=true}={}) {
    const op=this.operations.get(id);
    if(!op || op.status!=='prepared') fail('OPERATION_FINAL');
    this.actor(op.who,'device:enroll'); this.checkExpected(op.expected);
    if(!ack || (op.scopes.includes('profile:read')&&!confirmation)) fail('INVALID_ACK');
    if(Object.values(this.state.devices).filter(d=>d.status==='active').length>=20) fail('DEVICE_LIMIT');
    this.state.devices[id]=device(id,op.scopes);
    if(op.scopes.includes('profile:read')) this.state.recipients.push(id);
    this.state.revision++; op.status='committed';
  }
}

const tests = {
  'LC-01':()=>{const v=vectors(),pub=createPublicKey(signingKey(Buffer.from(v.root_derivation.root_signing_seed,'base64url'))); assert.ok(verify(null,transcript(v.proof.purpose,v.proof.payload),pub,Buffer.from(v.proof.signature,'base64url')));},
  'LC-02':()=>{const v=vectors(),pub=createPublicKey(signingKey(Buffer.from(v.root_derivation.root_signing_seed,'base64url'))),sig=Buffer.from(v.proof.signature,'base64url'); for(const p of [{...v.proof.payload,account_id:'44444444-4444-4444-8444-444444444444'},{...v.proof.payload,session_epoch:'4'},{...v.proof.payload,payload_hash:b64(hash('substitution'))}]) assert.equal(verify(null,transcript(v.proof.purpose,p),pub,sig),false); assert.equal(verify(null,transcript('rotation_accept',v.proof.payload),pub,sig),false);},
  'LC-03':()=>{assert.equal(jcs({z:'last',a:'first'}),jcs({a:'first',z:'last'})); assert.throws(()=>jcs({counter:1})); assert.throws(()=>jcs({text:'\ud800'})); assert.equal(counter('9223372036854775807'),'9223372036854775807'); for(const v of ['01','0','-1','9223372036854775808']) assert.throws(()=>counter(v));},
  'LC-04':()=>{const v=vectors().profile,bytes=Buffer.from(v.envelope.ciphertext,'base64url'); const open=aad=>{const d=createDecipheriv('aes-256-gcm',Buffer.from(v.key,'base64url'),Buffer.from(v.envelope.nonce,'base64url')); d.setAAD(Buffer.from(jcs(aad))); d.setAuthTag(bytes.subarray(-16)); return Buffer.concat([d.update(bytes.subarray(0,-16)),d.final()]).toString();}; assert.equal(open(v.aad),v.plaintext); assert.throws(()=>open({...v.aad,key_generation:'3'})); assert.throws(()=>open({...v.aad,profile_revision:'11'}));},
  'LC-05':()=>{const m=new Model(),t=m.token();m.write(t);m.revokeAll('a');assert.equal(m.state.writes,1);expectCode('INVALID_PROOF',()=>m.write(t));},
  'LC-06':()=>{const m=new Model(),t=m.token();m.revokeAll('a');expectCode('INVALID_PROOF',()=>m.write(t));assert.equal(m.state.writes,0);},
  'LC-07':()=>{const m=new Model(),c=m.challenge('a');m.revokeAll('a');expectCode('INVALID_PROOF',()=>m.login(c));expectCode('INVALID_PROOF',()=>m.login(c));},
  'LC-08':()=>{const m=new Model();m.revokeAll('a');m.write(m.token('a'));assert.equal(m.state.writes,1);},
  'LC-09':()=>{const m=new Model(),t=m.token('b');m.revokeDevice('a','b');expectCode('INVALID_PROOF',()=>m.write(t));expectCode('INVALID_PROOF',()=>m.token('b'));},
  'LC-10':()=>{const m=new Model();m.revokeDevice('a','b');const t=m.token();m.write(t);expectCode('PROFILE_REKEY_REQUIRED',()=>m.profileEdit(t));expectCode('PROFILE_REKEY_REQUIRED',()=>m.prepareEnrollment('a','c'));},
  'LC-11':()=>{const m=new Model();m.revokeDevice('a','b',true);assert.equal(m.state.profileGeneration,2);assert.deepEqual(m.state.recipients,['root','a']);m.profileEdit(m.token());},
  'LC-12':()=>{const m=new Model();expectCode('INSUFFICIENT_SCOPE',()=>m.prepareRotation('a','r'));expectCode('INSUFFICIENT_SCOPE',()=>m.prepareEnrollment('a','c',controller));expectCode('INVALID_PROOF',()=>m.token('root-1'));},
  'LC-13':()=>{const m=new Model();expectCode('UNVERIFIED_KEY',()=>m.prepareEnrollment('a','c',NORMAL,{verified:false}));m.prepareEnrollment('a','c');expectCode('INVALID_PROOF',()=>m.token('c'));expectCode('INVALID_ACK',()=>m.activate('c',{confirmation:false}));assert.equal(m.state.devices.c,undefined);},
  'LC-14':()=>{const m=new Model();m.prepareEnrollment('a','c');m.revokeDevice('root-1','a',true);expectCode('INVALID_PROOF',()=>m.activate('c'));assert.equal(m.state.devices.c,undefined);},
  'LC-15':()=>{const m=new Model();m.prepareEnrollment('a','c',['finance:read']);m.activate('c',{confirmation:false});assert.ok(!m.state.recipients.includes('c'));expectCode('INSUFFICIENT_SCOPE',()=>m.write(m.token('c')));},
  'LC-16':()=>{const m=new Model();m.prepareEnrollment('a','c');for(let n=2;n<20;n++)m.state.devices[`d${n}`]=device(`d${n}`);expectCode('DEVICE_LIMIT',()=>m.activate('c'));assert.equal(m.state.devices.c,undefined);},
  'LC-17':()=>{const m=new Model(),before=structuredClone(m.state);expectCode('SAVE_NEW_RECOVERY_REQUIRED',()=>m.prepareRotation('root-1','r',{saved:false}));assert.deepEqual(m.state,before);m.prepareRotation('root-1','r');assert.deepEqual(m.state,before);},
  'LC-18':()=>{const m=new Model();m.prepareRotation('root-1','r');m.profileEdit(m.token());const before=structuredClone(m.state);expectCode('REVISION_CONFLICT',()=>m.commitRotation('r'));assert.deepEqual(m.state,before);},
  'LC-19':()=>{const m=new Model();m.prepareRotation('root-1','r',{recipients:['root','c','b']});expectCode('RECIPIENT_SET_MISMATCH',()=>m.commitRotation('r'));assert.equal(m.state.root,'root-1');},
  'LC-20':()=>{const m=new Model();m.prepareRotation('root-1','r');const before=structuredClone(m.state);expectCode('INJECTED_TRANSACTION_FAILURE',()=>m.commitRotation('r',{fault:true}));assert.deepEqual(m.state,before);assert.equal(m.operations.get('r').status,'prepared');},
  'LC-21':()=>{const m=new Model(),t=m.token();m.prepareRotation('root-1','r');m.commitRotation('r');assert.equal(m.state.root,'root-2');assert.equal(m.state.profile,'new-cipher');assert.equal(m.state.rootGeneration,2);assert.equal(m.state.profileGeneration,2);assert.deepEqual(m.state.recipients,['root','c']);expectCode('INVALID_PROOF',()=>m.write(t));expectCode('INVALID_PROOF',()=>m.actor('root-1'));m.write(m.token('c'));},
  'LC-22':()=>{const m=new Model();m.prepareRotation('root-1','r');m.commitRotation('r');const before=structuredClone(m.state);assert.equal(m.status('r','root-1').status,'committed');assert.equal(m.status('r','root-2').status,'committed');assert.deepEqual(Object.keys(m.status('r','root-1')).sort(),['receipt','status']);expectCode('OPERATION_FINAL',()=>m.commitRotation('r'));assert.deepEqual(m.state,before);},
  'LC-23':()=>{const m=new Model();m.prepareRotation('root-1','r');expectCode('IDEMPOTENCY_CONFLICT',()=>m.prepareRotation('root-1','r',{newRoot:'root-other'}));expectCode('OPERATION_EXPIRED',()=>m.commitRotation('r',{now:600}));m.abort('r','root-1');expectCode('OPERATION_FINAL',()=>m.commitRotation('r'));assert.equal(m.state.root,'root-1');},
  'LC-24':()=>{const m=new Model();m.prepareRotation('root-1','r1');expectCode('OPERATION_IN_PROGRESS',()=>m.prepareRotation('root-1','r2',{newRoot:'root-3',newDevice:'d',recipients:['root','d']}));m.commitRotation('r1');expectCode('INSUFFICIENT_SCOPE',()=>m.prepareRotation('root-1','r2',{newRoot:'root-3',newDevice:'d',recipients:['root','d']}));assert.equal(m.state.rootGeneration,2);},
  'LC-25':()=>{const m=new Model();m.prepareEnrollment('root-1','c',controller);m.activate('c');assert.deepEqual(m.state.devices.c.scopes,controller);m.revokeAll('c');expectCode('INVALID_PROOF',()=>m.token('root-1'));expectCode('INVALID_REQUEST',()=>m.prepareEnrollment('root-1','d',['root:replace']));expectCode('INVALID_REQUEST',()=>m.prepareEnrollment('root-1','d',['profile:write']));},
};

const generated=vectors(), path=new URL('contracts/lifecycle-vectors.json',root);
if(process.argv.includes('--write-vectors')) writeFileSync(path,JSON.stringify(generated,null,2)+'\n');
assert.deepEqual(JSON.parse(readFileSync(path,'utf8')),generated,'Lifecycle vector drift; review before --write-vectors.');
const cases=JSON.parse(readFileSync(new URL('contracts/lifecycle-cases.json',root),'utf8'));
assert.deepEqual(cases.cases.map(c=>c.id).sort(),Object.keys(tests).sort(),'Every declared acceptance case needs a model assertion.');
for(const test of cases.cases) { tests[test.id](); console.log(`PASS ${test.id}: ${test.name}`); }
console.log(`PASS: ${cases.cases.length} lifecycle reference cases and deterministic vectors. Not runtime, PostgreSQL, HPKE or professional cryptographic validation.`);
