'use client';

import { cloneElement, useEffect, useId, useRef, useState, type FormEvent, type ReactElement, type ReactNode } from 'react';
import { ApiClient, ApiError, type Page, type Session, type Summary, type Transaction, type TransactionInput, type Wallet } from '@/lib/api';
import { createIdentity, decryptProfile, destroyIdentity, encryptProfile, parseRecoveryKey, recoveryKey, type Identity, type Profile } from '@/lib/crypto';
import { canonicalMoney, formatMoney, todayJakarta } from '@/lib/money';
import { lockAccount } from '@/lib/session';

type Destination = 'home' | 'finance' | 'profile';
type IconName = 'leaf' | 'home' | 'wallet' | 'profile' | 'lock' | 'plus' | 'arrow-up' | 'arrow-down' | 'check' | 'arrow-right' | 'close';
function Icon({ name, size = 22 }: { name: IconName; size?: number }) {
  const paths: Record<IconName, ReactNode> = {
    leaf: <><path d="M20 4c1 10-4 15-13 13C5 9 10 3 20 4Z" /><path d="M4 21 15 10" /></>,
    home: <><path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1Z" /><path d="M9 21v-8h6v8" /></>,
    wallet: <><rect x="3" y="5" width="18" height="15" rx="3" /><path d="M16 10h5v5h-5a2.5 2.5 0 0 1 0-5ZM4 5l13-3v3" /></>,
    profile: <><circle cx="12" cy="8" r="4" /><path d="M4 21v-2a8 8 0 0 1 16 0v2" /></>,
    lock: <><rect x="5" y="10" width="14" height="11" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3" /></>,
    plus: <path d="M12 5v14M5 12h14" />,
    'arrow-up': <path d="M12 20V4m-6 6 6-6 6 6" />,
    'arrow-down': <path d="M12 4v16m-6-6 6 6 6-6" />,
    check: <path d="m5 12 4 4L19 6" />,
    'arrow-right': <path d="M4 12h16m-6-6 6 6-6 6" />,
    close: <path d="m6 6 12 12M6 18 18 6" />,
  };
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>;
}
function Brand() { return <span className="brand"><span className="brand-mark"><Icon name="leaf" size={26} /></span>palmy<span className="brand-dot">.</span></span>; }
function ErrorNotice({ message }: { message: string }) { return message ? <div className="notice error" role="alert">{message}</div> : null; }
function errorMessage(error: unknown) { return error instanceof Error ? error.message : 'Terjadi kesalahan. Silakan coba kembali.'; }
function Field({ label, children, help }: { label: string; children: ReactElement<{ id?: string; 'aria-describedby'?: string }>; help?: string }) {
  const id = useId();
  const helpId = `${id}-help`;
  return <div className="field"><label htmlFor={id}>{label}</label>{cloneElement(children, { id, ...(help ? { 'aria-describedby': helpId } : {}) })}{help && <small id={helpId}>{help}</small>}</div>;
}
const privacyNotice = 'Data keuangan, nama dompet, kategori, dan catatan dapat dibaca Palmy. Hindari nama, nomor rekening, atau informasi pribadi di sini.';

export default function PalmyApp() {
  const [auth, setAuth] = useState<{ identity: Identity; session: Session } | null>(null);
  const [notice, setNotice] = useState('');
  const authGeneration = useRef(0);
  function onLocked(message: string) {
    const generation = ++authGeneration.current;
    setAuth(null); setNotice(message);
    return (completion: string) => { if (authGeneration.current === generation) setNotice(completion); };
  }
  return auth
    ? <Dashboard identity={auth.identity} session={auth.session} onLocked={onLocked} />
    : <Welcome notice={notice} onAuthenticated={(identity, session) => { ++authGeneration.current; setNotice(''); setAuth({ identity, session }); }} />;
}

function Welcome({ notice, onAuthenticated }: { notice: string; onAuthenticated: (identity: Identity, session: Session) => void }) {
  const [mode, setMode] = useState<'create' | 'recover'>('create');
  const [pending, setPending] = useState<{ identity: Identity; profile: Profile } | null>(null);
  const [acknowledged, setAcknowledged] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [copyStatus, setCopyStatus] = useState('');
  const recoveryInput = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (!pending) return;
    const preventExit = (event: BeforeUnloadEvent) => { event.preventDefault(); };
    window.addEventListener('beforeunload', preventExit);
    return () => window.removeEventListener('beforeunload', preventExit);
  }, [pending]);

  async function prepare(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setError(''); setBusy(true);
    const values = new FormData(event.currentTarget);
    try {
      const display_name = String(values.get('display_name')).trim();
      const email = String(values.get('email')).trim();
      if (!display_name) throw new Error('Nama panggilan harus diisi.');
      setPending({ identity: await createIdentity(), profile: { display_name, email } });
    } catch (caught) { setError(errorMessage(caught)); }
    finally { setBusy(false); }
  }
  async function register() {
    if (!pending || !acknowledged) return;
    setBusy(true); setError('');
    const api = new ApiClient();
    try {
      try { await api.register(pending.identity, pending.profile); }
      catch (caught) {
        // A previous response may have been lost after commit. A fresh proof can recover that same account.
        if (!(caught instanceof ApiError) || caught.status !== 409) throw caught;
      }
      const session = await api.login(pending.identity);
      await new ApiClient(session.access_token).profile(pending.identity);
      onAuthenticated(pending.identity, session);
    } catch (caught) { setError(errorMessage(caught)); }
    finally { setBusy(false); }
  }
  async function recover(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError('');
    let identity: Identity | undefined;
    try {
      identity = await parseRecoveryKey(recoveryInput.current?.value ?? '');
      const session = await new ApiClient().login(identity);
      await new ApiClient(session.access_token).profile(identity);
      if (recoveryInput.current) recoveryInput.current.value = '';
      onAuthenticated(identity, session);
    } catch (caught) {
      if (identity) destroyIdentity(identity);
      setError(errorMessage(caught));
    } finally { setBusy(false); }
  }
  async function copyRecovery() {
    if (!pending) return;
    try { await navigator.clipboard.writeText(recoveryKey(pending.identity)); setCopyStatus('Kunci disalin. Simpan di pengelola kata sandi yang aman.'); }
    catch { setCopyStatus('Salin kunci secara manual dari kotak di atas.'); }
  }

  return <main className="welcome" id="main-content">
    <section className="welcome-story" aria-label="Tentang Palmy">
      <Brand />
      <div className="story-copy"><span className="eyebrow light">RUANG UNTUK HIDUP LEBIH TENANG</span><h1>Keuangan tertata.<br />Pikiran lebih <em>lega.</em></h1><p>Mulai langkah kecil untuk memahami uangmu. Semua catatan di satu tempat, dengan identitas yang tetap dalam kendalimu.</p></div>
      <div className="botanical" aria-hidden="true"><span /><span /><span /><span /><span /></div>
      <div className="story-footer"><Icon name="lock" size={18} /><span>Profil dienkripsi di perangkatmu</span><span className="story-number">01 / PALMY</span></div>
    </section>
    <section className="welcome-content">
      <div className="welcome-top"><span>Keuangan personal, dibuat sederhana.</span><span className="small-badge">IDR · Indonesia</span></div>
      <div className="auth-card">
        {pending ? <>
          <span className="round-icon"><Icon name="lock" size={26} /></span><p className="eyebrow">LANGKAH TERAKHIR</p><h2>Simpan kunci. Pegang kendali.</h2><p className="muted">Kunci ini adalah satu-satunya cara membuka akun di perangkat lain. Palmy tidak memiliki kunci dan tidak dapat mengatur ulang aksesmu.</p>
          <Field label="Kunci pemulihan"><textarea className="recovery-key" readOnly spellCheck={false} autoComplete="off" value={recoveryKey(pending.identity)} rows={4} /></Field>
          <button className="button secondary full" onClick={copyRecovery} type="button">Salin kunci pemulihan</button>
          <p className="helper" aria-live="polite">{copyStatus || 'Siapa pun yang memiliki kunci ini dapat mengakses seluruh akunmu. Jangan membagikannya.'}</p>
          <label className="checkbox"><input type="checkbox" checked={acknowledged} onChange={event => setAcknowledged(event.target.checked)} disabled={busy} /><span>Saya sudah menyimpan kunci di tempat aman dan memahami bahwa Palmy tidak dapat memulihkan kunci yang hilang.</span></label>
          <ErrorNotice message={error} />
          <button className="button primary full" disabled={!acknowledged || busy} onClick={register}>{busy ? 'Membuka ruangmu…' : 'Buat akun dan masuk'}<Icon name="arrow-right" size={18} /></button>
          <p className="helper">Akun baru dibuat setelah kamu menyetujui penyimpanan kunci.</p>
        </> : <>
          <span className="eyebrow">SELAMAT DATANG DI PALMY</span><h2>Ruang tenang<br />untuk keuanganmu.</h2><p className="muted">Catat hari ini. Rencanakan esok dengan lebih yakin.</p>
          {notice && <div className="notice" role="status">{notice}</div>}
          <div className="segmented" aria-label="Akses akun"><button aria-pressed={mode === 'create'} onClick={() => { setMode('create'); setError(''); }} disabled={busy}>Buat akun</button><button aria-pressed={mode === 'recover'} onClick={() => { setMode('recover'); setError(''); }} disabled={busy}>Pulihkan akun</button></div>
          {mode === 'create' ? <form onSubmit={prepare}>
            <Field label="Nama panggilan"><input name="display_name" required maxLength={80} autoComplete="off" placeholder="Kamu ingin dipanggil apa?" disabled={busy} /></Field>
            <Field label="Email (opsional)" help="Dienkripsi bersama namamu. Tidak digunakan untuk masuk atau pemulihan."><input name="email" type="email" maxLength={254} autoComplete="off" placeholder="nama@contoh.com" disabled={busy} /></Field>
            <ErrorNotice message={error} /><button className="button primary full" disabled={busy}>{busy ? 'Menyiapkan kunci…' : 'Mulai perjalananmu'}<Icon name="arrow-right" size={18} /></button>
          </form> : <form onSubmit={recover}>
            <Field label="Kunci pemulihan" help="Gunakan kunci lengkap dari perangkatmu sebelumnya."><textarea ref={recoveryInput} name="recovery_key" required rows={4} placeholder="palmy1.…" autoComplete="off" autoCorrect="off" autoCapitalize="none" spellCheck={false} disabled={busy} /></Field>
            <ErrorNotice message={error} /><button className="button primary full" disabled={busy}>{busy ? 'Memverifikasi akses…' : 'Buka akun saya'}<Icon name="arrow-right" size={18} /></button>
          </form>}
          <div className="privacy-note"><Icon name="lock" size={19} /><p>Nama dan email hanya dibuka di perangkatmu. Catatan keuangan tetap dapat dibaca layanan. Kunci dan sesi web tidak disimpan setelah halaman ditutup.</p></div>
        </>}
      </div>
      <footer className="welcome-bottom">Sedikit lebih teratur. Setiap hari.<span>© {new Date().getFullYear()} Palmy</span></footer>
    </section>
  </main>;
}

function Dashboard({ identity, session, onLocked }: { identity: Identity; session: Session; onLocked: (message: string) => (completion: string) => void }) {
  const [api] = useState(() => new ApiClient(session.access_token));
  const [destination, setDestination] = useState<Destination>('home');
  const [profile, setProfile] = useState<Profile | null>(null);
  const [version, setVersion] = useState(0);
  const [summary, setSummary] = useState<Summary | null>(null);
  const [wallets, setWallets] = useState<Wallet[]>([]);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [modal, setModal] = useState<'wallet' | 'transaction' | null>(null);
  const [locking, setLocking] = useState(false);
  const mounted = useRef(true);
  const heading = useRef<HTMLHeadingElement>(null);

  useEffect(() => {
    mounted.current = true;
    const expires = Math.max(0, new Date(session.expires_at).getTime() - Date.now());
    const timeout = window.setTimeout(() => {
      mounted.current = false; api.clearToken(); destroyIdentity(identity); onLocked('Sesi berakhir. Pulihkan akun untuk melanjutkan.');
    }, expires);
    void load();
    return () => { mounted.current = false; window.clearTimeout(timeout); };
    // API and identity are immutable for this dashboard instance.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function load() {
    setLoading(true); setError('');
    try {
      const [person, totals, accounts, journal] = await Promise.all([
        api.profile(identity), api.request<{ data: Summary }>('/summary'), api.request<{ data: Wallet[] }>('/wallets'), api.request<Page<Transaction>>('/transactions?limit=25'),
      ]);
      if (!mounted.current) return;
      setProfile(person.profile); setVersion(person.version); setSummary(totals.data); setWallets(accounts.data); setTransactions(journal.data); setCursor(journal.next_cursor);
    } catch (caught) { if (mounted.current) setError(errorMessage(caught)); }
    finally { if (mounted.current) setLoading(false); }
  }
  async function lock() {
    setLocking(true);
    await lockAccount(identity, api, () => {
      mounted.current = false;
      const report = onLocked('Perangkat dikunci. Kunci telah dilepas; sesi server sedang dicabut.');
      return revoked => report(revoked
        ? 'Akun dikunci. Kunci telah dilepas dan sesi server berhasil dicabut.'
        : 'Perangkat dikunci. Pencabutan sesi di server gagal karena koneksi; sesi server akan kedaluwarsa dalam paling lama satu jam.');
    });
  }
  async function more() {
    if (!cursor) return;
    setLoading(true); setError('');
    try {
      const page = await api.request<Page<Transaction>>(`/transactions?limit=25&before=${encodeURIComponent(cursor)}`);
      if (mounted.current) { setTransactions(current => [...current, ...page.data.filter(item => !current.some(old => old.id === item.id))]); setCursor(page.next_cursor); }
    } catch (caught) { if (mounted.current) setError(errorMessage(caught)); }
    finally { if (mounted.current) setLoading(false); }
  }
  function navigate(next: Destination) { setDestination(next); setSuccess(''); setError(''); window.setTimeout(() => heading.current?.focus(), 0); }
  async function saved(message: string) { setModal(null); await load(); if (mounted.current) setSuccess(message); }
  const nav: { id: Destination; title: string; icon: IconName }[] = [{ id: 'home', title: 'Beranda', icon: 'home' }, { id: 'finance', title: 'Keuangan', icon: 'wallet' }, { id: 'profile', title: 'Profil', icon: 'profile' }];
  const date = new Intl.DateTimeFormat('id-ID', { timeZone: 'Asia/Jakarta', day: 'numeric', month: 'long', year: 'numeric' }).format(new Date());

  return <div className="app-shell">
    <a className="skip-link" href="#main-content">Lewati ke konten</a>
    <aside className="sidebar"><Brand /><span className="sidebar-caption">RUANG PRIBADIMU</span><nav aria-label="Navigasi utama">{nav.map(item => <button key={item.id} aria-current={destination === item.id ? 'page' : undefined} onClick={() => navigate(item.id)}><Icon name={item.icon} /><span>{item.title}</span>{destination === item.id && <span className="nav-dot" />}</button>)}</nav><div className="sidebar-bottom"><div className="sidebar-privacy"><Icon name="lock" /><strong>Identitas dalam kendalimu</strong><p>Profil dibuka di perangkat ini dengan kunci milikmu.</p></div><button className="lock-button" onClick={lock} disabled={locking}><Icon name="lock" size={19} />{locking ? 'Mengunci…' : 'Kunci akun'}</button></div></aside>
    <div className="main-shell"><header className="topbar"><span className="breadcrumb">Ruang pribadi <span>/</span> {nav.find(item => item.id === destination)?.title}</span><span className="topbar-right"><button className="mobile-lock icon-button" aria-label="Kunci akun" onClick={lock} disabled={locking}><Icon name="lock" size={17} /></button><span className="secure-badge"><span />Profil terenkripsi</span><span className="avatar" aria-hidden="true">{profile?.display_name.slice(0, 1).toLocaleUpperCase('id') || 'P'}</span></span></header>
      <main className="workspace" id="main-content" aria-busy={loading}>
        <div className="page-heading"><div><p className="eyebrow">{destination === 'home' ? date : 'RUANG PRIBADIMU'}</p><h1 ref={heading} tabIndex={-1}>{destination === 'home' ? `Halo${profile ? `, ${profile.display_name}` : ''}.` : destination === 'finance' ? 'Keuanganmu, lebih jelas.' : 'Profil & privasi.'}</h1><p className="muted">{destination === 'home' ? 'Lihat perjalanan keuanganmu, satu langkah setiap hari.' : destination === 'finance' ? 'Setiap catatan kecil memberi gambaran yang lebih utuh.' : 'Informasi personal hanya dibuka dengan kuncimu.'}</p></div>{destination !== 'profile' && <button className="button primary" onClick={() => setModal('transaction')} disabled={loading || wallets.length === 0}><Icon name="plus" size={19} />Catat transaksi</button>}</div>
        <ErrorNotice message={error} />{error && <button className="button secondary retry" onClick={load}>Coba muat ulang</button>}
        {success && <div className="notice success" role="status"><Icon name="check" size={18} />{success}</div>}
        {loading && !summary && <div className="loading-card" role="status">Mengambil catatan keuanganmu…</div>}
        {destination === 'profile' ? profile && <ProfilePanel identity={identity} api={api} profile={profile} version={version} onUpdated={load} onLock={lock} locking={locking} /> : <>
          {summary && <section className="summary-grid" aria-label="Ringkasan keuangan"><article className="balance-card"><div className="balance-label"><span>Total saldo</span><span className="currency-badge">IDR</span></div><p className="balance-value">{formatMoney(summary.balance)}</p><p className="balance-caption">Seluruh dompet · saldo terkini</p><div className="balance-decoration" aria-hidden="true"><Icon name="leaf" size={110} /></div></article><article className="metric-card"><span className="metric-icon incoming"><Icon name="arrow-down" /></span><span>Total pemasukan</span><strong>{formatMoney(summary.income)}</strong><small>Seluruh catatan</small></article><article className="metric-card"><span className="metric-icon outgoing"><Icon name="arrow-up" /></span><span>Total pengeluaran</span><strong>{formatMoney(summary.expense)}</strong><small>Seluruh catatan</small></article></section>}
          {summary && <div className="content-grid"><section className="panel transactions-panel"><div className="section-heading"><div><h2>{destination === 'home' ? 'Aktivitas terbaru' : 'Riwayat transaksi'}</h2><p>Catatan uang masuk dan keluar</p></div><span className="small-badge">{transactions.length} catatan</span></div>{transactions.length === 0 ? <Empty icon="leaf" title="Perjalananmu dimulai di sini" description={wallets.length ? 'Catat pemasukan atau pengeluaran pertamamu.' : 'Buat dompet, lalu mulai catat keuanganmu.'} /> : <><ul className="transaction-list">{transactions.map(transaction => <li key={transaction.id}><span className={`transaction-icon ${transaction.kind === 'income' ? 'incoming' : 'outgoing'}`}><Icon name={transaction.kind === 'income' ? 'arrow-down' : 'arrow-up'} size={19} /></span><div className="transaction-content"><strong>{transaction.category}</strong><span>{wallets.find(wallet => wallet.id === transaction.wallet_id)?.name ?? 'Dompet'} · {new Intl.DateTimeFormat('id-ID', { day: 'numeric', month: 'short', timeZone: 'Asia/Jakarta' }).format(new Date(`${transaction.effective_on}T00:00:00+07:00`))}</span>{transaction.description && <p>{transaction.description}</p>}</div><span className={`transaction-amount ${transaction.kind === 'income' ? 'positive' : ''}`}><span className="sr-only">{transaction.kind === 'income' ? 'Pemasukan' : 'Pengeluaran'}</span>{transaction.kind === 'income' ? '+' : '−'}{formatMoney(transaction.amount)}</span></li>)}</ul>{cursor && <button className="button text-button full" onClick={more} disabled={loading}>{loading ? 'Memuat…' : 'Muat lebih banyak'}</button>}</>}</section><div className="aside-panels"><section className="panel wallet-panel"><div className="section-heading"><div><h2>Dompetku</h2><p>Uangmu punya tempat</p></div><button className="icon-button" aria-label="Tambah dompet" onClick={() => setModal('wallet')} disabled={loading || wallets.length >= 100}><Icon name="plus" /></button></div>{wallets.length === 0 ? <div className="wallet-empty"><span className="round-icon"><Icon name="wallet" /></span><p>Belum ada dompet.</p><button className="button secondary full" onClick={() => setModal('wallet')}>Buat dompet pertama</button></div> : <ul className="wallet-list">{wallets.map(wallet => <li key={wallet.id}><span className="wallet-icon"><Icon name="wallet" size={19} /></span><div><strong>{wallet.name}</strong><span>{formatMoney(wallet.balance)}</span></div><small>IDR</small></li>)}</ul>}</section><section className="quiet-note"><span className="eyebrow">SELANGKAH LEBIH SADAR</span><p>Ruang untuk uangmu.<br />Kendali untuk dirimu.</p><div><Icon name="lock" size={17} /><span>Profil pribadi terenkripsi. Catatan keuangan dapat dibaca layanan.</span></div></section></div></div>}
        </>}
        <footer className="workspace-footer"><span>Pelan-pelan, tetap melangkah.</span><span>Palmy · Ruang pribadi</span></footer>
      </main>
    </div>
    {modal && <Modal title={modal === 'wallet' ? 'Buat dompet baru' : 'Catat transaksi'} onClose={() => setModal(null)}>{modal === 'wallet' ? <WalletForm api={api} onSaved={() => saved('Dompet berhasil dibuat.')} /> : <TransactionForm api={api} wallets={wallets} onSaved={() => saved('Transaksi berhasil dicatat.')} />}</Modal>}
  </div>;
}

function Empty({ icon, title, description }: { icon: IconName; title: string; description: string }) { return <div className="empty-state"><span className="empty-icon"><Icon name={icon} size={34} /></span><h3>{title}</h3><p>{description}</p></div>; }
function Modal({ title, children, onClose }: { title: string; children: ReactNode; onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => { dialog.current?.showModal(); }, []);
  function close() { if (!dialog.current?.querySelector('[aria-busy="true"]')) onClose(); }
  return <dialog ref={dialog} className="modal" aria-labelledby="modal-title" onCancel={event => { event.preventDefault(); close(); }} onClose={onClose}><div className="modal-header"><h2 id="modal-title">{title}</h2><button className="icon-button" aria-label="Tutup formulir" onClick={close}><Icon name="close" /></button></div>{children}</dialog>;
}
function useSubmission() {
  const previous = useRef<{ body: string; key: string } | null>(null);
  return (body: unknown) => {
    const serialized = JSON.stringify(body);
    if (!previous.current || previous.current.body !== serialized) previous.current = { body: serialized, key: crypto.randomUUID() };
    return previous.current.key;
  };
}
function WalletForm({ api, onSaved }: { api: ApiClient; onSaved: () => Promise<void> }) {
  const [busy, setBusy] = useState(false); const [error, setError] = useState(''); const keyFor = useSubmission();
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError('');
    const name = String(new FormData(event.currentTarget).get('name')).trim();
    try { if (!name) throw new Error('Nama dompet harus diisi.'); await api.request('/wallets', 'POST', { name }, keyFor({ name })); await onSaved(); }
    catch (caught) { setError(errorMessage(caught)); } finally { setBusy(false); }
  }
  return <form onSubmit={submit} aria-busy={busy}><p className="muted">Pisahkan tempat menyimpan uang agar lebih mudah dipahami.</p><Field label="Nama dompet"><input name="name" placeholder="Contoh: Dompet harian" maxLength={80} required autoFocus disabled={busy} /></Field><p className="input-privacy">{privacyNotice}</p><ErrorNotice message={error} /><button className="button primary full" disabled={busy}>{busy ? 'Menyimpan…' : 'Simpan dompet'}</button><p className="helper">Saldo awal Rp 0,00. Tambahkan pemasukan untuk mencatat saldo.</p></form>;
}
function TransactionForm({ api, wallets, onSaved }: { api: ApiClient; wallets: Wallet[]; onSaved: () => Promise<void> }) {
  const [kind, setKind] = useState<'income' | 'expense'>('expense'); const [busy, setBusy] = useState(false); const [error, setError] = useState(''); const keyFor = useSubmission();
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError('');
    const values = new FormData(event.currentTarget);
    try {
      const body: TransactionInput = { wallet_id: String(values.get('wallet_id')), kind, amount: canonicalMoney(String(values.get('amount'))), category: String(values.get('category')).trim(), description: String(values.get('description')).trim(), effective_on: String(values.get('effective_on')) };
      if (!body.category) throw new Error('Kategori harus diisi.');
      await api.request('/transactions', 'POST', body, keyFor(body)); await onSaved();
    } catch (caught) { setError(errorMessage(caught)); } finally { setBusy(false); }
  }
  return <form onSubmit={submit} aria-busy={busy}><div className="segmented"><button type="button" aria-pressed={kind === 'expense'} onClick={() => setKind('expense')} disabled={busy}>Pengeluaran</button><button type="button" aria-pressed={kind === 'income'} onClick={() => setKind('income')} disabled={busy}>Pemasukan</button></div><Field label="Jumlah (IDR)" help="Gunakan titik untuk desimal, misalnya 1234.56."><input name="amount" inputMode="decimal" placeholder="0.00" maxLength={19} required autoFocus disabled={busy} /></Field><div className="form-row"><Field label="Dompet"><select name="wallet_id" required disabled={busy}>{wallets.map(wallet => <option key={wallet.id} value={wallet.id}>{wallet.name}</option>)}</select></Field><Field label="Tanggal"><input name="effective_on" type="date" defaultValue={todayJakarta()} required disabled={busy} /></Field></div><Field label="Kategori"><input name="category" maxLength={60} placeholder={kind === 'expense' ? 'Contoh: Makanan' : 'Contoh: Gaji'} required disabled={busy} /></Field><Field label="Catatan (opsional)"><textarea name="description" maxLength={280} placeholder="Tambahkan konteks tanpa informasi pribadi" rows={2} disabled={busy} /></Field><p className="input-privacy">{privacyNotice}</p><ErrorNotice message={error} /><button className="button primary full" disabled={busy}>{busy ? 'Mencatat…' : 'Simpan transaksi'}</button><p className="helper">Transaksi yang tersimpan belum dapat diubah atau dihapus di versi ini.</p></form>;
}
function ProfilePanel({ identity, api, profile, version, onUpdated, onLock, locking }: { identity: Identity; api: ApiClient; profile: Profile; version: number; onUpdated: () => Promise<void>; onLock: () => Promise<void>; locking: boolean }) {
  const [name, setName] = useState(profile.display_name); const [email, setEmail] = useState(profile.email); const [busy, setBusy] = useState(false); const [error, setError] = useState(''); const [success, setSuccess] = useState('');
  useEffect(() => { setName(profile.display_name); setEmail(profile.email); }, [profile]);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError(''); setSuccess('');
    try {
      if (!name.trim()) throw new Error('Nama panggilan harus diisi.');
      const envelope = await encryptProfile(identity, { display_name: name.trim(), email: email.trim() });
      // Self-verification keeps malformed or incompatible local envelopes from replacing a valid profile.
      await decryptProfile(identity, envelope);
      await api.request('/profile', 'PUT', { profile: envelope, version }); await onUpdated(); setSuccess('Profil dienkripsi dan berhasil disimpan.');
    } catch (caught) {
      if (caught instanceof ApiError && caught.status === 409) { await onUpdated(); setError('Profil berubah di perangkat lain. Versi terbaru ditampilkan; periksa kembali sebelum menyimpan.'); }
      else setError(errorMessage(caught));
    } finally { setBusy(false); }
  }
  return <div className="profile-grid"><section className="panel profile-form"><div className="section-heading"><div><h2>Detail pribadi</h2><p>Nama dan email disimpan sebagai satu profil terenkripsi.</p></div><Icon name="lock" /></div><form onSubmit={submit}><Field label="Nama panggilan"><input value={name} onChange={event => setName(event.target.value)} maxLength={80} required autoComplete="off" disabled={busy} /></Field><Field label="Email (opsional)"><input value={email} onChange={event => setEmail(event.target.value)} type="email" maxLength={254} autoComplete="off" disabled={busy} /></Field><ErrorNotice message={error} />{success && <p className="notice success" role="status">{success}</p>}<button className="button primary" disabled={busy}>{busy ? 'Mengenkripsi…' : 'Simpan profil'}</button></form></section><section className="panel privacy-panel"><span className="round-icon"><Icon name="lock" size={27} /></span><h2>Kuncimu, aksesmu.</h2><p>Nama dan email dienkripsi sebelum dikirim. Palmy menyimpan data terenkripsi, bukan kunci untuk membukanya.</p><p>Catatan keuangan tetap terbaca. Informasi pribadi yang ditulis pada nama dompet atau catatan transaksi tidak terlindungi oleh enkripsi profil.</p><p>Profil terenkripsi bukan jaminan anonimitas. Metadata koneksi dan isi catatan dapat mengungkap identitas.</p><div className="privacy-divider" /><p>Menutup atau memuat ulang halaman melepaskan kunci web. Gunakan kunci pemulihan untuk masuk kembali.</p><button className="button secondary full" onClick={onLock} disabled={locking || busy}><Icon name="lock" size={18} />{locking ? 'Mengunci…' : 'Kunci dan keluar'}</button></section></div>;
}
