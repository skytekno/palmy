import { ed25519 } from '@noble/curves/ed25519.js';

const utf8 = new TextEncoder();
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
export interface Profile { display_name: string; email: string }
export interface Envelope { version: 1; algorithm: 'A256GCM'; nonce: string; ciphertext: string }
export interface Identity {
  accountId: string;
  master: Uint8Array<ArrayBuffer>;
  signingSeed: Uint8Array<ArrayBuffer>;
  profileKey: CryptoKey | null;
  publicKey: string;
}
export function toBase64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}
export function fromBase64Url(value: string): Uint8Array<ArrayBuffer> {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error('Format kunci tidak valid.');
  const result = Uint8Array.from(atob(value.replaceAll('-', '+').replaceAll('_', '/')), c => c.charCodeAt(0));
  if (toBase64Url(result) !== value) throw new Error('Format kunci tidak valid.');
  return result;
}
export async function deriveKeys(master: Uint8Array<ArrayBuffer>) {
  if (master.length !== 32) throw new Error('Panjang kunci tidak valid.');
  const source = await crypto.subtle.importKey('raw', master, 'HKDF', false, ['deriveBits', 'deriveKey']);
  const params = (info: string) => ({ name: 'HKDF', hash: 'SHA-256', salt: utf8.encode('palmy:v1'), info: utf8.encode(info) });
  const profileKey = await crypto.subtle.deriveKey(params('palmy:profile:v1'), source, { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
  const signingSeed = new Uint8Array(await crypto.subtle.deriveBits(params('palmy:signing:v1'), source, 256));
  return { profileKey, signingSeed };
}
export async function identityFromSecret(accountId: string, master: Uint8Array<ArrayBuffer>): Promise<Identity> {
  if (!uuid.test(accountId)) throw new Error('ID akun tidak valid.');
  const keys = await deriveKeys(master);
  return { accountId, master, ...keys, publicKey: toBase64Url(ed25519.getPublicKey(keys.signingSeed)) };
}
export async function createIdentity(): Promise<Identity> {
  return identityFromSecret(crypto.randomUUID(), crypto.getRandomValues(new Uint8Array(32)));
}
export function recoveryKey(identity: Identity): string {
  return `palmy1.${identity.accountId}.${toBase64Url(identity.master)}`;
}
export async function parseRecoveryKey(value: string): Promise<Identity> {
  const [prefix, accountId, master, ...extra] = value.trim().split('.');
  if (prefix !== 'palmy1' || accountId === undefined || master === undefined || extra.length !== 0 || !uuid.test(accountId)) throw new Error('Kunci pemulihan tidak valid. Gunakan kunci lengkap yang diawali palmy1.');
  return identityFromSecret(accountId, fromBase64Url(master));
}
export async function encryptProfile(identity: Identity, profile: Profile): Promise<Envelope> {
  const profileKey = identity.profileKey;
  if (!profileKey) throw new Error('Akun telah dikunci. Pulihkan akun untuk melanjutkan.');
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce, additionalData: utf8.encode(`palmy:profile:v1:${identity.accountId}`), tagLength: 128 }, profileKey, utf8.encode(JSON.stringify(profile)));
  return { version: 1, algorithm: 'A256GCM', nonce: toBase64Url(nonce), ciphertext: toBase64Url(new Uint8Array(ciphertext)) };
}
export async function decryptProfile(identity: Identity, envelope: Envelope): Promise<Profile> {
  const profileKey = identity.profileKey;
  if (!profileKey) throw new Error('Akun telah dikunci. Pulihkan akun untuk melanjutkan.');
  if (envelope.version !== 1 || envelope.algorithm !== 'A256GCM') throw new Error('Versi profil belum didukung.');
  const nonce = fromBase64Url(envelope.nonce);
  if (nonce.length !== 12) throw new Error('Profil terenkripsi tidak valid.');
  const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce, additionalData: utf8.encode(`palmy:profile:v1:${identity.accountId}`), tagLength: 128 }, profileKey, fromBase64Url(envelope.ciphertext));
  const profile: unknown = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(plain));
  if (typeof profile !== 'object' || profile === null || !('display_name' in profile) || !('email' in profile) || typeof profile.display_name !== 'string' || typeof profile.email !== 'string') throw new Error('Isi profil tidak valid.');
  return { display_name: profile.display_name, email: profile.email };
}
export function registrationProof(identity: Identity, profile: Envelope): string {
  const message = `palmy:register:v1:${identity.accountId}:${identity.publicKey}:${profile.nonce}:${profile.ciphertext}`;
  return toBase64Url(ed25519.sign(utf8.encode(message), identity.signingSeed));
}
export function signChallenge(identity: Identity, challenge: { challenge_id: string; nonce: string }): string {
  return toBase64Url(ed25519.sign(utf8.encode(`palmy:auth:v1:${identity.accountId}:${challenge.challenge_id}:${challenge.nonce}`), identity.signingSeed));
}
export function destroyIdentity(identity: Identity) {
  identity.master.fill(0);
  identity.signingSeed.fill(0);
  identity.profileKey = null;
  // Release the non-extractable key handle even while session revocation remains in flight.
}
