import { afterEach, describe, expect, it, vi } from 'vitest';
import vectors from '../../../contracts/crypto-vectors.json';
import { ApiClient, ApiError } from './api';
import { parseRecoveryKey } from './crypto';

function recordedRequest(calls: Parameters<typeof fetch>[], index = 0) {
  const call = calls[index];
  if (!call) throw new Error(`Expected request ${index} to have been recorded.`);
  const [url, init] = call;
  if (!init) throw new Error(`Expected options for request ${index}.`);
  return { url: String(url), init, headers: new Headers(init.headers) };
}

function requestBody(init: RequestInit): string {
  if (typeof init.body !== 'string') throw new Error('Expected a serialized JSON request body.');
  return init.body;
}

function jsonBody(init: RequestInit): unknown {
  return JSON.parse(requestBody(init));
}

afterEach(() => vi.unstubAllGlobals());
describe('private client transport', () => {
  it('sends only the public key, owner proof, and encrypted profile on registration', async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(new Response(JSON.stringify({ data: { account_id: vectors.account_id } }), { status: 201 }));
    vi.stubGlobal('fetch', fetcher);
    const identity = await parseRecoveryKey(vectors.recovery_key);
    await new ApiClient(undefined, 'http://localhost:8100').register(identity, vectors.profile);
    const { url, init } = recordedRequest(fetcher.mock.calls);
    expect(url).toBe('http://localhost:8100/api/v1/accounts');
    const body = jsonBody(init);
    if (typeof body !== 'object' || body === null) throw new Error('Expected an account registration object.');
    expect(Object.keys(body).sort()).toEqual(['account_id', 'profile', 'public_key', 'signature']);
    for (const secret of [vectors.recovery_key, vectors.master_secret, vectors.signing_seed, vectors.profile.display_name, vectors.profile.email]) expect(requestBody(init)).not.toContain(secret);
    expect(init.credentials).toBe('omit');
    expect(init.referrerPolicy).toBe('no-referrer');
    expect(init.cache).toBe('no-store');
  });
  it('uses a challenge proof and keeps the session token in the Authorization header only', async () => {
    const fetcher = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(Response.json({ data: { ...vectors.challenge, expires_at: '2099-01-01T00:00:00Z' } }))
      .mockResolvedValueOnce(Response.json({ data: { access_token: 'opaque-token', expires_at: '2099-01-01T00:00:00Z' } }))
      .mockResolvedValueOnce(new Response(null, { status: 204 }));
    vi.stubGlobal('fetch', fetcher);
    const session = await new ApiClient(undefined, 'http://localhost:8100').login(await parseRecoveryKey(vectors.recovery_key));
    expect(jsonBody(recordedRequest(fetcher.mock.calls, 1).init)).toEqual({ account_id: vectors.account_id, challenge_id: vectors.challenge.challenge_id, signature: vectors.authentication_signature });
    const api = new ApiClient(session.access_token, 'http://localhost:8100'); await api.revoke();
    const revocation = recordedRequest(fetcher.mock.calls, 2);
    expect(revocation.headers.get('Authorization')).toBe('Bearer opaque-token');
    expect(revocation.url).not.toContain('opaque-token');
    expect(revocation.init).not.toHaveProperty('body');
  });
  it('rejects mismatched owner context before decryption', async () => {
    vi.stubGlobal('fetch', vi.fn<typeof fetch>().mockResolvedValue(Response.json({ data: { account_id: 'other', profile: vectors.envelope, version: 1 } })));
    await expect(new ApiClient('token', 'http://localhost:8100').profile(await parseRecoveryKey(vectors.recovery_key))).rejects.toThrow('Konteks pemilik');
  });
  it('surfaces version conflict status without displaying untrusted server detail', async () => {
    vi.stubGlobal('fetch', vi.fn<typeof fetch>().mockResolvedValue(Response.json({ title: 'untrusted private detail', code: 'version_conflict', request_id: 'safe-request-id' }, { status: 409 })));
    try { await new ApiClient('token', 'http://localhost:8100').request('/profile', 'PUT', { version: 1 }); throw new Error('Expected conflict'); }
    catch (error) {
      if (!(error instanceof ApiError)) throw error;
      expect(error).toMatchObject({ status: 409, code: 'version_conflict', requestId: 'safe-request-id' });
      expect(error.message).not.toContain('untrusted private detail');
    }
  });
  it('reuses the caller idempotency key and canonical decimal string unchanged', async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(Response.json({ data: {} })); vi.stubGlobal('fetch', fetcher);
    await new ApiClient('token', 'http://localhost:8100').request('/transactions', 'POST', { amount: '9999999999999999.99' }, 'fixed-key');
    const request = recordedRequest(fetcher.mock.calls);
    expect(request.headers.get('Idempotency-Key')).toBe('fixed-key');
    expect(jsonBody(request.init)).toEqual({ amount: '9999999999999999.99' });
  });
});
