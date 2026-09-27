// Public deterministic fixtures ONLY. Never use these keys or nonce for an account.
import { hkdfSync, createCipheriv, createPrivateKey, createPublicKey, sign } from 'node:crypto';
import { writeFileSync, readFileSync } from 'node:fs';
const b64 = value => Buffer.from(value).toString('base64url');
const account_id = '11111111-1111-4111-8111-111111111111';
const master = Buffer.from(Array.from({length: 32}, (_, i) => i));
const derive = purpose => Buffer.from(hkdfSync('sha256', master, 'palmy:v1', `palmy:${purpose}:v1`, 32));
const profile_key = derive('profile');
const signing_seed = derive('signing');
const signingKey = createPrivateKey({ key: Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), signing_seed]), format: 'der', type: 'pkcs8' });
const public_key = createPublicKey(signingKey).export({format:'jwk'}).x;
const nonce = Buffer.from(Array.from({length:12},(_,i)=>i+32));
const profile = {display_name:'Pengguna Uji',email:'uji@example.invalid'};
const plaintext = JSON.stringify(profile);
const aad = `palmy:profile:v1:${account_id}`;
const cipher = createCipheriv('aes-256-gcm', profile_key, nonce);
cipher.setAAD(Buffer.from(aad));
const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final(), cipher.getAuthTag()]);
const envelope = {version:1,algorithm:'A256GCM',nonce:b64(nonce),ciphertext:b64(ciphertext)};
const registration_message = `palmy:register:v1:${account_id}:${public_key}:${envelope.nonce}:${envelope.ciphertext}`;
const challenge = {challenge_id:'22222222-2222-4222-8222-222222222222',nonce:b64(Buffer.alloc(32,42))};
const authentication_message = `palmy:auth:v1:${account_id}:${challenge.challenge_id}:${challenge.nonce}`;
const vector = {warning:'PUBLIC TEST FIXTURE. NEVER USE THESE KEYS OR NONCE FOR REAL ACCOUNTS.',account_id,master_secret:b64(master),recovery_key:`palmy1.${account_id}.${b64(master)}`,profile_key:b64(profile_key),signing_seed:b64(signing_seed),public_key,profile,plaintext,aad,envelope,registration_message,registration_signature:b64(sign(null,Buffer.from(registration_message),signingKey)),challenge,authentication_message,authentication_signature:b64(sign(null,Buffer.from(authentication_message),signingKey))};
const path = new URL('../contracts/crypto-vectors.json', import.meta.url);
const content = JSON.stringify(vector,null,2)+'\n';
if (process.argv.includes('--check')) {
 if (readFileSync(path,'utf8') !== content) throw new Error('Crypto fixture drift');
 console.log('Independent Node crypto fixture matches committed protocol vector.');
} else writeFileSync(path, content);
