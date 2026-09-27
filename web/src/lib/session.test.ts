import { describe, expect, it, vi } from 'vitest';
import { createIdentity, encryptProfile } from './crypto';
import { lockAccount } from './session';

describe('immediate local locking', () => {
  it('clears keys/token and removes private UI before a delayed network revoke resolves', async () => {
    const identity = await createIdentity();
    let resolve!: () => void;
    const completion = vi.fn();
    const api = { revoke: vi.fn(() => new Promise<void>(done => { resolve = done; })), clearToken: vi.fn() };
    const detachPrivateUI = vi.fn(() => completion);
    const pending = lockAccount(identity, api, detachPrivateUI);
    expect(detachPrivateUI).toHaveBeenCalledOnce();
    expect(api.clearToken).toHaveBeenCalledOnce();
    expect(identity.master.every(byte => byte === 0)).toBe(true);
    expect(identity.signingSeed.every(byte => byte === 0)).toBe(true);
    expect(identity.profileKey).toBeNull();
    expect(completion).not.toHaveBeenCalled();
    await expect(encryptProfile(identity, { display_name: 'private', email: '' })).rejects.toThrow('dikunci');
    resolve(); await pending;
    expect(completion).toHaveBeenCalledWith(true);
  });
  it('keeps the client locked when the delayed revocation fails offline', async () => {
    const identity = await createIdentity();
    let reject!: (error: Error) => void;
    const completion = vi.fn();
    const api = { revoke: () => new Promise<void>((_, fail) => { reject = fail; }), clearToken: vi.fn() };
    const detachPrivateUI = vi.fn(() => completion);
    const pending = lockAccount(identity, api, detachPrivateUI);
    expect(detachPrivateUI).toHaveBeenCalledOnce();
    expect(identity.profileKey).toBeNull();
    reject(new Error('offline')); await pending;
    expect(completion).toHaveBeenCalledWith(false);
    expect(identity.profileKey).toBeNull();
  });
});
