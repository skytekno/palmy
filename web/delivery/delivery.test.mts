import { afterEach, describe, expect, it } from 'vitest';
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { canonicalHttpsOrigin, deliveryConfig, prepareDeliveryBuild } from './config.mts';
import { addSubresourceIntegrity, contentPolicy, createManifest, digest, loadArtifact, parseManifest } from './artifact.mts';

const config = { webOrigin: 'https://web.example.invalid', apiOrigin: 'https://api.example.invalid' };
const html = '<!doctype html><html><head><script src="/_next/static/test.js" async></script><style>body { color: black; }</style></head><body><script>self.loaded = "✅";</script></body></html>';
const temporary: string[] = [];
afterEach(async () => { for (const root of temporary.splice(0)) await rm(root, { recursive: true, force: true }); });
async function fixture(): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), 'palmy-delivery-'));
  temporary.push(root);
  await mkdir(join(root, '_next/static'), { recursive: true });
  await writeFile(join(root, 'index.html'), html);
  await writeFile(join(root, '_next/static/test.js'), 'self.asset = true;');
  const manifest = await createManifest(root, config, Buffer.from('lock'));
  await writeFile(join(root, 'delivery-manifest.json'), JSON.stringify(manifest));
  return root;
}

describe('fail-closed delivery configuration', () => {
  it.each([undefined, '', 'http://localhost:3100', 'https://web.example.invalid/', 'https://WEB.example.invalid', ' https://web.example.invalid', 'https://u:p@web.example.invalid', 'https://web.example.invalid/path', 'https://web.example.invalid?secret=1', 'https://web.example.invalid#secret', 'https://web.example.invalid:443', 'https://*.example.invalid', 'https://web.example.invalid.'])('rejects noncanonical origin %s', value => {
    expect(() => canonicalHttpsOrigin(value)).toThrow();
  });
  it('accepts explicit HTTPS origins and refuses development mode or missing API config', () => {
    expect(deliveryConfig({ PALMY_WEB_ORIGIN: config.webOrigin, NEXT_PUBLIC_API_URL: config.apiOrigin })).toEqual(config);
    expect(canonicalHttpsOrigin('https://localhost:8443')).toBe('https://localhost:8443');
    expect(() => deliveryConfig({ PALMY_ENV: 'development', PALMY_WEB_ORIGIN: config.webOrigin, NEXT_PUBLIC_API_URL: config.apiOrigin })).toThrow();
    expect(() => deliveryConfig({ PALMY_WEB_ORIGIN: config.webOrigin })).toThrow();
  });
  it('invalidates an existing production manifest even when new configuration is rejected', async () => {
    const root = await fixture();
    await expect(prepareDeliveryBuild(root, { PALMY_ENV: 'development' })).rejects.toThrow('DELIVERY_PRODUCTION_REQUIRED');
    await expect(readFile(join(root, 'delivery-manifest.json'))).rejects.toMatchObject({ code: 'ENOENT' });
  });
});

describe('static build CSP and integrity', () => {
  it('hashes exact Unicode script/style bytes and excludes unsafe execution and third-party connections', () => {
    const csp = contentPolicy(html, config.apiOrigin);
    expect(csp).toContain(`'sha256-${digest('self.loaded = "✅";')}'`);
    expect(csp).toContain(`'sha256-${digest('body { color: black; }')}'`);
    expect(csp).toContain(`connect-src ${config.apiOrigin};`);
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).not.toMatch(/unsafe-inline|unsafe-eval|report-uri|report-to/);
    expect(contentPolicy(html.replace('✅', 'changed'), config.apiOrigin)).not.toBe(csp);
  });
  it('rejects remote script/stylesheet injection and event handlers at build time', () => {
    expect(() => contentPolicy(html.replace('/_next/static/test.js', 'https://untrusted.example/x.js'), config.apiOrigin)).toThrow();
    expect(() => contentPolicy('<button onclick="steal()">go</button>', config.apiOrigin)).toThrow();
  });
  it('adds browser SRI to initial local assets without changing inline bytes', async () => {
    const root = await fixture();
    const output = await addSubresourceIntegrity(root, html);
    expect(output).toContain(`integrity="sha256-${digest('self.asset = true;')}" crossorigin="anonymous"`);
    expect(contentPolicy(output, config.apiOrigin)).toBe(contentPolicy(html, config.apiOrigin));
  });
  it('verifies all served bytes and holds a stable in-memory release', async () => {
    const root = await fixture();
    const release = await loadArtifact(root, config);
    await writeFile(join(root, '_next/static/test.js'), 'changed');
    expect(release.assets.get('/_next/static/test.js')?.toString()).toBe('self.asset = true;');
    await expect(loadArtifact(root, config)).rejects.toThrow('DELIVERY_INTEGRITY_FAILED');
  });
  it('rejects mismatched origins, manifest traversal, CSP weakening, duplicate files and symlinks', async () => {
    const root = await fixture();
    const raw = JSON.parse(await readFile(join(root, 'delivery-manifest.json'), 'utf8')) as Record<string, unknown>;
    expect(() => parseManifest({ ...raw, apiOrigin: 'https://evil.example' }, config)).toThrow();
    expect(() => parseManifest({ ...raw, files: [{ path: '/../key' }] }, config)).toThrow();
    const manifest = parseManifest(raw, config);
    expect(() => parseManifest({ ...raw, files: [...manifest.files, ...manifest.files] }, config)).toThrow();
    await writeFile(join(root, 'delivery-manifest.json'), JSON.stringify({ ...raw, csp: "default-src * 'unsafe-inline'" }));
    await expect(loadArtifact(root, config)).rejects.toThrow('DELIVERY_CSP_MISMATCH');
    await symlink(join(root, 'index.html'), join(root, 'alias'));
    await expect(loadArtifact(root, config)).rejects.toThrow('DELIVERY_SYMLINK');
  });
  it('does not expose RSC payloads or framework diagnostics', async () => {
    const root = await fixture();
    await writeFile(join(root, 'index.txt'), 'internal flight');
    await writeFile(join(root, '404.html'), 'internal page');
    const manifest = await createManifest(root, config, Buffer.from('lock'));
    expect(manifest.files.map(file => file.path).sort()).toEqual(['/_next/static/test.js', '/index.html']);
  });
});
