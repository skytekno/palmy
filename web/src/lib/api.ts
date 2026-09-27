import { type Identity, type Envelope, type Profile, decryptProfile, signChallenge, registrationProof, encryptProfile } from './crypto';

export interface Wallet { id: string; name: string; balance: string; currency: 'IDR' }
export interface Transaction { id: string; wallet_id: string; kind: 'income' | 'expense'; amount: string; category: string; description: string; effective_on: string; created_at: string }
export type TransactionInput = Omit<Transaction, 'id' | 'created_at'>;
export interface Summary { balance: string; income: string; expense: string; currency: 'IDR' }
export interface Session { access_token: string; expires_at: string }
export interface ProfileResponse { account_id: string; profile: Envelope; version: number }
export interface Page<T> { data: T[]; next_cursor: string | null }
export class ApiError extends Error {
  constructor(public status: number, public code: string, public requestId?: string) {
    const messages: Record<number, string> = { 400: 'Periksa data yang dimasukkan.', 401: 'Sesi atau bukti akses tidak valid. Pulihkan akun untuk masuk kembali.', 404: 'Data tidak ditemukan atau tidak dapat diakses.', 409: 'Data telah berubah atau permintaan bertentangan. Muat ulang lalu coba kembali.', 429: 'Terlalu banyak permintaan. Tunggu sebentar lalu coba lagi.' };
    super(messages[status] ?? 'Layanan belum tersedia. Coba kembali sebentar lagi.');
  }
}
function configuredBase(): string {
  const value = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:8100';
  const url = new URL(value);
  if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new Error('Konfigurasi API tidak valid.');
  if (url.protocol !== 'https:' && !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)) throw new Error('API harus menggunakan HTTPS.');
  return value.replace(/\/$/, '');
}
export class ApiClient {
  constructor(private token?: string, private base = configuredBase()) {}
  async request<T>(path: string, method = 'GET', body?: unknown, idempotencyKey?: string): Promise<T> {
    const headers = new Headers({ Accept: 'application/json' });
    if (body !== undefined) headers.set('Content-Type', 'application/json');
    if (this.token) headers.set('Authorization', `Bearer ${this.token}`);
    if (idempotencyKey) headers.set('Idempotency-Key', idempotencyKey);
    let response: Response;
    try {
      response = await fetch(`${this.base}/api/v1${path}`, { method, headers, ...(body === undefined ? {} : { body: JSON.stringify(body) }), cache: 'no-store', credentials: 'omit', referrerPolicy: 'no-referrer', signal: AbortSignal.timeout(15000) });
    } catch {
      throw new Error('Tidak dapat terhubung ke Palmy. Periksa koneksi lalu coba lagi.');
    }
    if (!response.ok) {
      const problem = await response.json().catch(() => ({})) as { code?: string; request_id?: string };
      throw new ApiError(response.status, problem.code ?? 'request_failed', problem.request_id);
    }
    if (response.status === 204) return undefined as T;
    return response.json() as Promise<T>;
  }
  async register(identity: Identity, profile: Profile) {
    const envelope = await encryptProfile(identity, profile);
    return this.request('/accounts', 'POST', { account_id: identity.accountId, public_key: identity.publicKey, profile: envelope, signature: registrationProof(identity, envelope) });
  }
  async login(identity: Identity): Promise<Session> {
    const { data: challenge } = await this.request<{ data: { challenge_id: string; nonce: string; expires_at: string } }>('/auth/challenges', 'POST', { account_id: identity.accountId });
    return (await this.request<{ data: Session }>('/auth/sessions', 'POST', { account_id: identity.accountId, challenge_id: challenge.challenge_id, signature: signChallenge(identity, challenge) })).data;
  }
  async profile(identity: Identity): Promise<{ profile: Profile; version: number }> {
    const { data } = await this.request<{ data: ProfileResponse }>('/profile');
    if (data.account_id !== identity.accountId) throw new Error('Konteks pemilik profil tidak cocok.');
    return { profile: await decryptProfile(identity, data.profile), version: data.version };
  }
  revoke() { return this.request<void>('/auth/session', 'DELETE'); }
  clearToken() { this.token = undefined; }
}
