import { destroyIdentity, type Identity } from './crypto';

interface RevocableSession { revoke(): Promise<void>; clearToken(): void }

/** Detach private UI and keys synchronously, independent of server availability. */
export function lockAccount(identity: Identity, api: RevocableSession, onLocalLock: () => (revoked: boolean) => void): Promise<void> {
  // request() copies Authorization into its own pending fetch before yielding.
  const revocation = api.revoke();
  api.clearToken();
  destroyIdentity(identity);
  const completed = onLocalLock();
  return revocation.then(() => completed(true), () => completed(false));
}
