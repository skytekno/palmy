import { describe, expect, it } from 'vitest';
import { ed25519 } from '@noble/curves/ed25519.js';
import vectors from '../../../contracts/crypto-vectors.json';
import { createIdentity, decryptProfile, destroyIdentity, encryptProfile, fromBase64Url, identityFromSecret, parseRecoveryKey, recoveryKey, registrationProof, signChallenge, toBase64Url, type Envelope } from './crypto';

const fixture = () => parseRecoveryKey(vectors.recovery_key);
describe('protocol interoperability', () => {
  it('recovers the exact key, seed and public identity from independently generated vectors', async () => {
    const identity = await fixture();
    expect(identity.accountId).toBe(vectors.account_id);
    expect(identity.publicKey).toBe(vectors.public_key);
    expect(toBase64Url(identity.signingSeed)).toBe(vectors.signing_seed);
    expect(recoveryKey(identity)).toBe(vectors.recovery_key);
    expect(identity.profileKey?.extractable).toBe(false);
    expect(await decryptProfile(identity, vectors.envelope as Envelope)).toEqual(vectors.profile);
  });
  it('signs registration and fresh challenge with the exact cross-client messages', async () => {
    const identity = await fixture();
    expect(registrationProof(identity, vectors.envelope as Envelope)).toBe(vectors.registration_signature);
    expect(signChallenge(identity, vectors.challenge)).toBe(vectors.authentication_signature);
    expect(ed25519.verify(fromBase64Url(signChallenge(identity, vectors.challenge)), new TextEncoder().encode(vectors.authentication_message), fromBase64Url(vectors.public_key))).toBe(true);
  });
  it('randomizes nonces and never exposes plaintext in the envelope', async () => {
    const identity = await createIdentity();
    const profile = { display_name: 'Nama Rahasia 🌴', email: '' };
    const a = await encryptProfile(identity, profile);
    const b = await encryptProfile(identity, profile);
    expect(a.nonce).not.toBe(b.nonce);
    expect(a.ciphertext).not.toBe(b.ciphertext);
    expect(JSON.stringify(a)).not.toContain(profile.display_name);
    expect(fromBase64Url(a.nonce)).toHaveLength(12);
    expect(await decryptProfile(await parseRecoveryKey(recoveryKey(identity)), a)).toEqual(profile);
  });
  it('rejects modified ciphertext and tag', async () => {
    const identity = await fixture();
    for (const index of [0, fromBase64Url(vectors.envelope.ciphertext).length - 1]) {
      const bytes = fromBase64Url(vectors.envelope.ciphertext);
      const byte = bytes[index];
      if (byte === undefined) throw new Error('Tamper index is outside the fixture.');
      bytes[index] = byte ^ 1;
      await expect(decryptProfile(identity, { ...vectors.envelope, ciphertext: toBase64Url(bytes) } as Envelope)).rejects.toThrow();
    }
  });
  it('binds profile to the account even when both accounts have the same master key', async () => {
    const other = await identityFromSecret('33333333-3333-4333-8333-333333333333', fromBase64Url(vectors.master_secret));
    await expect(decryptProfile(other, vectors.envelope as Envelope)).rejects.toThrow();
    const unrelated = await createIdentity();
    await expect(decryptProfile(unrelated, vectors.envelope as Envelope)).rejects.toThrow();
  });
  it('rejects unsupported envelope versions and invalid nonce lengths', async () => {
    const identity = await fixture();
    await expect(decryptProfile(identity, { ...vectors.envelope, version: 2 } as unknown as Envelope)).rejects.toThrow('Versi');
    await expect(decryptProfile(identity, { ...vectors.envelope, nonce: 'AQ' } as Envelope)).rejects.toThrow('valid');
  });
  it.each(['', 'palmy1.bad.AQ', `palmy2.${vectors.account_id}.${vectors.master_secret}`, `${vectors.recovery_key}=`, `${vectors.recovery_key}.extra`, `palmy1.${vectors.account_id}.AQ`, vectors.recovery_key.replace('4111', '1111')])('rejects malformed recovery key %s', async value => {
    await expect(parseRecoveryKey(value)).rejects.toThrow();
  });
  it('clears accessible secret arrays when locking', async () => {
    const identity = await fixture(); destroyIdentity(identity);
    expect(identity.profileKey).toBeNull();
    expect(identity.master.every(byte => byte === 0)).toBe(true);
    expect(identity.signingSeed.every(byte => byte === 0)).toBe(true);
  });
});
