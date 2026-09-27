// Synthetic local evidence only. No OS trust changes, certificate bypasses, remote accounts or telemetry providers.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createPublicKey, randomBytes, randomUUID, verify } from 'node:crypto';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer, request as httpsRequest } from 'node:https';
import { createServer as createTcpServer } from 'node:net';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { firefox, expect } from '@playwright/test';
import { createDeliveryServer } from '../web/delivery/server.mts';
import { filesBelow, digest } from '../web/delivery/artifact.mts';

const root = fileURLToPath(new URL('..', import.meta.url));
const web = join(root, 'web');
const artifacts = join(root, 'artifacts/local');
await mkdir(artifacts, { recursive: true });
// A killed CI job may upload artifacts/local: private CA keys and browser profiles must never live there.
const temporary = await mkdtemp(join(tmpdir(), 'palmy-delivery-'));
const canaries = { name: `DeliveryOwner${randomBytes(8).toString('hex')}`, email: `private-${randomBytes(8).toString('hex')}@example.invalid`, description: `FinanceOnly${randomBytes(8).toString('hex')}` };
const secretValues = Object.values(canaries);
const bearerTokens = [];
const logs = [], network = [], browserLogs = [], violations = [], pageErrors = [], fixtureErrors = [];
let checkpoint = 'setup', context, untrustedContext, api, delivery, attacker;
let productionBuilt = false;
const progress = setInterval(() => process.stdout.write(`Delivery check: ${checkpoint}.\n`), 15000);
progress.unref();

function run(command, args, options = {}) {
  return new Promise((resolveCommand, reject) => {
    const child = spawn(command, args, { cwd: root, ...options, stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '';
    child.stdout.on('data', chunk => { output += chunk; }); child.stderr.on('data', chunk => { output += chunk; });
    child.once('error', reject);
    child.once('exit', code => code === 0 ? resolveCommand(output) : reject(new Error(`child command failed: ${command} (${code})`)));
  });
}
async function listen(server, port = 0) {
  await new Promise((resolveListen, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', resolveListen); });
  const address = server.address(); assert.ok(address && typeof address !== 'string'); return address.port;
}
async function close(server) {
  if (!server?.listening) return;
  server.closeAllConnections?.();
  await new Promise(resolveClose => server.close(resolveClose));
}
function probe(origin, ca, path = '/', options = {}) {
  return new Promise((resolveProbe, reject) => {
    const url = new URL(origin);
    const request = httpsRequest({ hostname: '127.0.0.1', port: url.port, servername: url.hostname, path, ca, rejectUnauthorized: true, headers: { Host: url.host, ...options.headers }, method: options.method ?? 'GET' }, response => {
      const authorized = response.socket.authorized, protocol = response.socket.getProtocol();
      const chunks = []; response.on('data', chunk => chunks.push(chunk));
      response.on('end', () => resolveProbe({ status: response.statusCode, headers: response.headers, body: Buffer.concat(chunks), authorized, protocol }));
    });
    request.on('error', reject); request.end();
  });
}
function noCanaries(value, message) { for (const secret of secretValues) assert.ok(!value.includes(secret), message); }
function nodePublicKey(encoded) { return createPublicKey({ format: 'der', type: 'spki', key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), Buffer.from(encoded, 'base64url')]) }); }

try {
  checkpoint = 'ephemeral TLS certificates';
  const caKey = join(temporary, 'ca-key.pem'), caFile = join(temporary, 'ca.pem'), keyFile = join(temporary, 'server-key.pem'), certFile = join(temporary, 'server.pem'), csr = join(temporary, 'server.csr');
  await run('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-days', '1', '-subj', '/CN=Palmy isolated delivery test CA', '-keyout', caKey, '-out', caFile, '-addext', 'basicConstraints=critical,CA:TRUE', '-addext', 'keyUsage=critical,keyCertSign,cRLSign']);
  await run('openssl', ['req', '-newkey', 'rsa:2048', '-nodes', '-sha256', '-subj', '/CN=localhost', '-keyout', keyFile, '-out', csr]);
  const extensions = join(temporary, 'extensions.cnf');
  await writeFile(extensions, 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n');
  await run('openssl', ['x509', '-req', '-in', csr, '-CA', caFile, '-CAkey', caKey, '-CAcreateserial', '-out', certFile, '-days', '1', '-sha256', '-extfile', extensions]);
  const ca = await readFile(caFile), key = await readFile(keyFile), cert = await readFile(certFile);
  // Reserve an available web port long enough to choose the build's canonical origin, then bind it after export.
  const reservation = createTcpServer(); const webPort = await listen(reservation); await close(reservation);
  const webOrigin = `https://localhost:${webPort}`;
  let account, challenge, profileVersion = 1;
  const sessions = new Set(), wallets = [], transactions = [];
  const total = () => transactions.reduce((sum, item) => sum + (item.kind === 'income' ? 1n : -1n) * BigInt(item.amount.replace('.', '')), 0n);
  const money = value => `${value < 0n ? '-' : ''}${(value < 0n ? -value : value) / 100n}.${String((value < 0n ? -value : value) % 100n).padStart(2, '0')}`;
  api = createServer({ key, cert, minVersion: 'TLSv1.2' }, async (request, response) => {
    try {
      const origin = request.headers.origin;
      const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Vary': 'Origin' };
      if (origin === webOrigin) Object.assign(headers, { 'Access-Control-Allow-Origin': webOrigin, 'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE', 'Access-Control-Allow-Headers': 'authorization, content-type, idempotency-key', 'Access-Control-Expose-Headers': 'x-request-id' });
      function send(status, data) { response.writeHead(status, headers); response.end(status === 204 ? undefined : JSON.stringify(data)); }
      if (origin && origin !== webOrigin) return send(403, { code: 'origin_denied' });
      if (request.method === 'OPTIONS') return send(204);
      const chunks = []; for await (const chunk of request) chunks.push(chunk);
      const body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString()) : null;
      const path = new URL(request.url, webOrigin).pathname;
      logs.push(JSON.stringify({ event: 'fixture_api', method: request.method }));
      if (path === '/api/v1/accounts' && request.method === 'POST') {
        assert.ok(!account, 'fixture duplicate account');
        const text = `palmy:register:v1:${body.account_id}:${body.public_key}:${body.profile.nonce}:${body.profile.ciphertext}`;
        assert.ok(verify(null, Buffer.from(text), nodePublicKey(body.public_key), Buffer.from(body.signature, 'base64url')), 'fixture registration signature');
        noCanaries(JSON.stringify(body), 'profile plaintext in registration');
        account = body; return send(201, { data: { account_id: body.account_id } });
      }
      if (path === '/api/v1/auth/challenges') {
        assert.ok(account && body.account_id === account.account_id, 'fixture unknown account');
        challenge = { challenge_id: randomUUID(), nonce: randomBytes(32).toString('base64url'), expires_at: new Date(Date.now() + 60000).toISOString() };
        return send(200, { data: challenge });
      }
      if (path === '/api/v1/auth/sessions') {
        assert.ok(account && challenge && body.challenge_id === challenge.challenge_id, 'fixture unknown challenge');
        const text = `palmy:auth:v1:${account.account_id}:${challenge.challenge_id}:${challenge.nonce}`;
        assert.ok(verify(null, Buffer.from(text), nodePublicKey(account.public_key), Buffer.from(body.signature, 'base64url')), 'fixture auth signature');
        challenge = undefined;
        const token = randomBytes(32).toString('base64url'); sessions.add(token); secretValues.push(token); bearerTokens.push(token);
        return send(201, { data: { access_token: token, expires_at: new Date(Date.now() + 3600000).toISOString() } });
      }
      const token = request.headers.authorization?.replace(/^Bearer /, '');
      if (!token || !sessions.has(token)) return send(401, { code: 'unauthorized' });
      if (path === '/api/v1/auth/session' && request.method === 'DELETE') { sessions.delete(token); return send(204); }
      if (path === '/api/v1/profile') {
        if (request.method === 'PUT') { assert.ok(body.version === profileVersion, 'fixture profile version'); account.profile = body.profile; profileVersion++; }
        return send(200, { data: { account_id: account.account_id, profile: account.profile, version: profileVersion } });
      }
      if (path === '/api/v1/wallets') {
        if (request.method === 'POST') { assert.ok(request.headers['idempotency-key'], 'fixture wallet idempotency'); const wallet = { id: randomUUID(), name: body.name, balance: '0.00', currency: 'IDR' }; wallets.push(wallet); return send(201, { data: wallet }); }
        return send(200, { data: wallets.map(wallet => ({ ...wallet, balance: money(total()) })) });
      }
      if (path === '/api/v1/transactions') {
        if (request.method === 'POST') { assert.ok(request.headers['idempotency-key'], 'fixture transaction idempotency'); const transaction = { id: randomUUID(), ...body, created_at: new Date().toISOString() }; transactions.push(transaction); return send(201, { data: transaction }); }
        return send(200, { data: transactions, next_cursor: null });
      }
      if (path === '/api/v1/summary') return send(200, { data: { balance: money(total()), income: money(total()), expense: '0.00', currency: 'IDR' } });
      return send(404, { code: 'not_found' });
    } catch { fixtureErrors.push('fixture assertion failed'); response.writeHead(500); response.end(); }
  });
  const apiPort = await listen(api); const apiOrigin = `https://localhost:${apiPort}`;
  let exfiltrationRequests = 0;
  attacker = createServer({ key, cert }, (request, response) => {
    if (request.url === '/frame') { response.writeHead(200, { 'Content-Type': 'text/html' }); response.end(`<iframe src="${webOrigin}"></iframe>`); }
    else { exfiltrationRequests++; response.writeHead(204); response.end(); }
  });
  const attackerOrigin = `https://localhost:${await listen(attacker)}`;

  checkpoint = 'production export';
  process.stdout.write('Delivery check: building the production export.\n');
  logs.push(await run('npm', ['run', 'build:delivery'], { cwd: web, env: { ...process.env, PALMY_ENV: 'production', PALMY_WEB_ORIGIN: webOrigin, NEXT_PUBLIC_API_URL: apiOrigin, PALMY_PRIVATE_BUILD_CANARY: canaries.name, NEXT_TELEMETRY_DISABLED: '1' } }));
  productionBuilt = true;
  const config = { webOrigin, apiOrigin };
  delivery = await createDeliveryServer({ root: join(web, 'out'), config, key, cert, log: event => logs.push(JSON.stringify(event)) });
  await listen(delivery, webPort);

  checkpoint = 'TLS, headers and request boundary';
  const response = await probe(webOrigin, ca);
  assert.equal(response.status, 200); assert.ok(response.authorized, 'TLS CA must be trusted');
  assert.ok(['TLSv1.2', 'TLSv1.3'].includes(response.protocol));
  assert.equal(response.headers['cache-control'], 'no-store');
  assert.equal(response.headers['x-frame-options'], 'DENY'); assert.equal(response.headers['x-content-type-options'], 'nosniff');
  assert.equal(response.headers['referrer-policy'], 'no-referrer'); assert.equal(response.headers['strict-transport-security'], 'max-age=31536000');
  assert.equal(response.headers['cross-origin-resource-policy'], 'same-origin');
  assert.equal(response.headers['cross-origin-opener-policy'], 'same-origin');
  assert.ok(!response.headers['set-cookie']); assert.ok(!response.headers['x-powered-by']);
  assert.ok(!/unsafe-eval|unsafe-inline|report-uri|report-to/.test(response.headers['content-security-policy']));
  assert.ok(response.headers['content-security-policy'].includes(`connect-src ${apiOrigin};`));
  await assert.rejects(probe(webOrigin, undefined)); // This CA is not globally trusted.
  const denied = [
    ['/?recovery=' + secretValues[0], {}, 400], ['/../secret', {}, 400], ['/%2e%2e/secret', {}, 400], ['//evil.example', {}, 400],
    ['/delivery-manifest.json', {}, 404], ['/index.txt', {}, 404], ['/missing', {}, 404], ['/', { method: 'POST' }, 405],
    ['/', { headers: { Host: 'attacker.example', Referer: secretValues[0] } }, 421], ['/', { headers: { Origin: 'https://attacker.example' } }, 421],
  ];
  for (const [path, options, status] of denied) { const result = await probe(webOrigin, ca, path, options); assert.equal(result.status, status); assert.equal(result.headers['cache-control'], 'no-store'); noCanaries(result.body.toString(), 'request reflected into response'); }
  const head = await probe(webOrigin, ca, '/', { method: 'HEAD' }); assert.equal(head.status, 200); assert.equal(head.body.length, 0);
  const manifest = JSON.parse(await readFile(join(web, 'out/delivery-manifest.json'), 'utf8'));
  for (const file of manifest.files) {
    const asset = await probe(webOrigin, ca, file.path);
    assert.equal(asset.status, 200); assert.equal(digest(asset.body), file.sha256);
    assert.equal(asset.headers['cache-control'], file.immutable ? 'public, max-age=31536000, immutable' : 'no-store');
  }

  checkpoint = 'isolated browser trust';
  // Playwright supports a process-specific enterprise policy path. The browser install and OS/user trust stores stay untouched.
  const policyFile = join(temporary, 'policies.json');
  // First prove Firefox rejects this certificate before installing our explicit trust anchor.
  untrustedContext = await firefox.launchPersistentContext(join(temporary, 'untrusted-profile'), { headless: true, env: { ...process.env, PLAYWRIGHT_FIREFOX_POLICIES_JSON: '' } });
  await assert.rejects(untrustedContext.pages()[0].goto(webOrigin), /SEC_ERROR_UNKNOWN_ISSUER|SEC_ERROR_UNTRUSTED_ISSUER|certificate|SSL/i);
  await untrustedContext.close(); untrustedContext = undefined;
  await writeFile(policyFile, JSON.stringify({ policies: { Certificates: { ImportEnterpriseRoots: false, Install: [caFile] }, DisableTelemetry: true, DisableFirefoxStudies: true, DisableFirefoxAccounts: true, PasswordManagerEnabled: false, DisableFormHistory: true } }));
  context = await firefox.launchPersistentContext(join(temporary, 'trusted-profile'), { headless: true, env: { ...process.env, PLAYWRIGHT_FIREFOX_POLICIES_JSON: policyFile }, viewport: { width: 1440, height: 1000 } });
  context.setDefaultTimeout(10000); context.setDefaultNavigationTimeout(10000);
  const page = context.pages()[0];
  await context.exposeBinding('recordViolation', (_source, event) => violations.push(event));
  await context.addInitScript(() => document.addEventListener('securitypolicyviolation', event => {
    void window.recordViolation({ directive: event.effectiveDirective, blocked: event.blockedURI });
  }));
  context.on('request', request => network.push({ url: request.url(), method: request.method(), headers: request.headers(), body: request.postData() ?? '' }));
  function observePage(opened) { opened.on('console', message => browserLogs.push(message.text())); opened.on('pageerror', error => pageErrors.push(error.message)); }
  for (const opened of context.pages()) observePage(opened);
  context.on('page', observePage);
  checkpoint = 'CSR account, encryption and finance under CSP';
  await page.goto(webOrigin);
  await expect(page.getByRole('button', { name: 'Mulai perjalananmu' })).toBeVisible();
  assert.ok(await page.evaluate(() => window.isSecureContext));
  await page.getByLabel('Nama panggilan', { exact: true }).fill(canaries.name);
  await page.getByLabel('Email', { exact: false }).fill(canaries.email);
  await page.getByRole('button', { name: 'Mulai perjalananmu' }).click();
  const recovery = await page.getByLabel('Kunci pemulihan', { exact: true }).inputValue(); secretValues.push(recovery);
  assert.ok(recovery.startsWith('palmy1.')); assert.ok(!account, 'saved-key acknowledgement must precede registration');
  await page.getByRole('checkbox', { name: /Saya sudah menyimpan kunci/ }).check();
  await page.getByRole('button', { name: 'Buat akun dan masuk' }).click();
  await expect(page.getByRole('heading', { name: `Halo, ${canaries.name}.` })).toBeVisible();
  await page.getByRole('button', { name: 'Buat dompet pertama' }).click();
  await page.getByLabel('Nama dompet', { exact: true }).fill('Dompet delivery');
  await page.getByRole('button', { name: 'Simpan dompet', exact: true }).click();
  await expect(page.getByRole('status').filter({ hasText: 'Dompet berhasil dibuat.' })).toBeVisible();
  await page.getByRole('button', { name: 'Catat transaksi', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: 'Catat transaksi' });
  await dialog.getByRole('button', { name: 'Pemasukan', exact: true }).click();
  await dialog.getByLabel('Jumlah (IDR)', { exact: false }).fill('1234.56');
  await dialog.getByLabel('Kategori', { exact: true }).fill('Uji delivery');
  await dialog.getByLabel('Catatan', { exact: false }).fill(canaries.description);
  await dialog.getByRole('button', { name: 'Simpan transaksi', exact: true }).click();
  await expect(page.getByRole('region', { name: 'Ringkasan keuangan' })).toContainText('Rp 1.234,56');
  await expect(page.getByText(canaries.description, { exact: true })).toBeVisible();
  await page.getByRole('navigation', { name: 'Navigasi utama' }).getByRole('button', { name: 'Profil', exact: true }).click();
  const changedName = `${canaries.name}Updated`; secretValues.push(changedName);
  await page.getByLabel('Nama panggilan', { exact: true }).fill(changedName);
  await page.getByRole('button', { name: 'Simpan profil', exact: true }).click();
  await expect(page.getByRole('status').filter({ hasText: 'Profil dienkripsi dan berhasil disimpan.' })).toBeVisible();
  await page.getByRole('button', { name: 'Kunci akun', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Pulihkan akun', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Pulihkan akun', exact: true }).click();
  await page.getByLabel('Kunci pemulihan', { exact: true }).fill(recovery);
  await page.getByRole('button', { name: 'Buka akun saya', exact: true }).click();
  await expect(page.getByRole('heading', { name: `Halo, ${changedName}.` })).toBeVisible();
  await expect(page.getByRole('region', { name: 'Ringkasan keuangan' })).toContainText('Rp 1.234,56');
  assert.deepEqual(await page.evaluate(async () => ({ local: localStorage.length, session: sessionStorage.length, caches: await caches.keys(), workers: (await navigator.serviceWorker.getRegistrations()).length })), { local: 0, session: 0, caches: [], workers: 0 });
  assert.deepEqual(await context.cookies(), []); assert.deepEqual(violations, []); assert.deepEqual(pageErrors, []); assert.deepEqual(fixtureErrors, []);
  assert.equal(context.pages().length, 1, 'the application must not create a popup or secondary page');

  checkpoint = 'privacy and network allowlist';
  for (const request of network) {
    const url = new URL(request.url); assert.ok([webOrigin, apiOrigin].includes(url.origin), 'third-party application request');
    noCanaries(request.url, 'sensitive URL'); assert.ok(!request.headers.referer, 'unexpected Referer'); assert.ok(!request.headers.cookie, 'unexpected cookie');
    const { authorization, ...otherHeaders } = request.headers;
    noCanaries(JSON.stringify(otherHeaders), 'sensitive non-Authorization header');
    if (url.origin === webOrigin) noCanaries(JSON.stringify(request), 'secret sent to static delivery');
    for (const value of [canaries.name, canaries.email, changedName, recovery]) assert.ok(!request.body.includes(value), 'plaintext identity or recovery on wire');
    for (const token of bearerTokens) assert.ok(!request.body.includes(token), 'bearer outside Authorization');
    if (authorization) assert.ok(url.origin === apiOrigin && bearerTokens.some(token => authorization === `Bearer ${token}`), 'bearer destination or unexpected Authorization content');
    if (request.body.includes(canaries.description)) assert.ok(url.origin === apiOrigin && url.pathname === '/api/v1/transactions' && request.method === 'POST', 'finance sent outside intended write');
  }
  assert.ok(network.some(item => item.body.includes(canaries.description)), 'fixture must exercise readable financial data');
  noCanaries(JSON.stringify(logs), 'delivery or fixture log leak'); noCanaries(JSON.stringify(browserLogs), 'browser console leak');
  for (const directory of ['out', '.next/server']) for (const file of await filesBelow(join(web, directory))) noCanaries((await readFile(join(web, directory, file))).toString(), 'build or SSR output leak');
  // npm ci verifies these registry integrity hashes; local links / unpinned remote sources must not enter the release lock.
  const lock = JSON.parse(await readFile(join(web, 'package-lock.json'), 'utf8'));
  for (const [name, entry] of Object.entries(lock.packages)) if (name) assert.ok(/^sha512-[A-Za-z0-9+/=]+$/.test(entry.integrity) && entry.resolved.startsWith('https://registry.npmjs.org/'), 'dependency integrity metadata');

  checkpoint = 'CSP negative execution and exfiltration probes';
  const requestsBefore = network.length;
  await page.evaluate(async exfiltrationUrl => {
    const script = document.createElement('script'); script.textContent = 'window.deliveryInlineExecuted = true'; document.body.append(script);
    const button = document.createElement('button'); button.setAttribute('onclick', 'window.deliveryHandlerExecuted = true'); document.body.append(button); button.click();
    // Run after the debugger evaluation stack unwinds; devtools evaluation itself is privileged by the browser.
    await new Promise(resolveProbe => setTimeout(() => {
      let evaluated = false; try { window.eval('window.deliveryEvalExecuted = true'); evaluated = true; } catch { /* CSP must reject eval. */ }
      window.deliveryEvalSucceeded = evaluated; resolveProbe();
    }, 0));
    await fetch(exfiltrationUrl).catch(() => undefined);
  }, `${attackerOrigin}/exfiltration`);
  assert.deepEqual(await page.evaluate(() => [window.deliveryInlineExecuted === true, window.deliveryHandlerExecuted === true, window.deliveryEvalExecuted === true, window.deliveryEvalSucceeded]), [false, false, false, false]);
  await expect.poll(() => violations.length).toBeGreaterThanOrEqual(4);
  assert.ok(violations.some(item => item.directive === 'connect-src'));
  assert.ok(violations.some(item => item.directive === 'script-src-elem'));
  assert.ok(violations.some(item => item.directive === 'script-src-attr'));
  // Browser tooling may emit a request event for CSP-blocked URLs; it must never reach an external network.
  assert.ok(network.slice(requestsBefore).every(item => item.url === `${attackerOrigin}/exfiltration`), 'unexpected negative-probe request');
  assert.equal(exfiltrationRequests, 0, 'CSP must prevent an actual connection to the other trusted HTTPS origin');
  checkpoint = 'CSP cross-origin framing denial';
  const framePage = await context.newPage();
  const frameErrors = [];
  framePage.on('console', message => frameErrors.push(message.text()));
  await framePage.goto(`${attackerOrigin}/frame`);
  await expect.poll(() => frameErrors.some(message => /frame-ancestors|X-Frame-Options|refused|denied/i.test(message))).toBe(true);
  // A denied frame has no application execution context; waiting for its DOM would wait indefinitely.
  await framePage.close();
  const evidence = { scope: 'isolated loopback TLS; synthetic API; no remote deployment', browser: 'Firefox', tls: response.protocol, caTrustedByBrowser: true, untrustedCaRejected: true, headers: response.headers, staticFilesVerified: manifest.files.length, dependencyLockSha256: manifest.lockSha256, applicationRequestOrigins: ['configured HTTPS web origin', 'configured HTTPS API origin'], cspPositiveViolations: 0, cspNegativeProbeCount: violations.length, secretsInLogsBuildUrlsReferrers: false, publicTraffic: 'gated: remote endpoint, edge logs, retention and independent review not evidenced' };
  // Ports and CSP hashes are public delivery configuration. Never persist browser traces, fixture payloads or screenshots of secrets.
  await writeFile(join(artifacts, 'delivery-evidence.json'), `${JSON.stringify(evidence, null, 2)}\n`);
  process.stdout.write('PASS: trusted TLS and rejected untrusted CA; delivery headers/cache/Host/path boundaries; intact assets and lock metadata; Firefox CSR create/finance/profile/recovery; no secret logs/storage/build/URLs/referrers or third-party application traffic; CSP blocks inline/event/eval/exfiltration probes. Local evidence only.\n');
} catch (error) {
  // Even failure diagnostics must not dump locators or payloads containing the synthetic secrets.
  let message = error instanceof Error ? error.message : 'unknown failure';
  for (const secret of secretValues) message = message.replaceAll(secret, '[redacted]');
  process.stderr.write(`FAIL delivery check (${checkpoint}): ${message}\n`);
  process.exitCode = 1;
} finally {
  clearInterval(progress);
  await context?.close(); await untrustedContext?.close(); await close(delivery); await close(api); await close(attacker);
  await rm(temporary, { recursive: true, force: true });
  // The default local preview uses web/out; do not leave it pointing at a disposable HTTPS fixture.
  if (productionBuilt && process.env['PALMY_DELIVERY_RESTORE_DEV'] !== '0') {
    try { await run('npm', ['run', 'build'], { cwd: web, env: { ...process.env, PALMY_ENV: 'development', NEXT_PUBLIC_API_URL: 'http://localhost:8100', NEXT_TELEMETRY_DISABLED: '1' } }); }
    catch { process.stderr.write('FAIL restoring the local development export.\n'); process.exitCode = 1; }
  }
}
