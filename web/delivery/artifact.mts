import { createHash } from 'node:crypto';
import { lstat, readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { parse, type DefaultTreeAdapterMap } from 'parse5';
import { canonicalHttpsOrigin, type DeliveryConfig } from './config.mts';

export interface Asset { path: string; sha256: string; mime: string; immutable: boolean }
export interface Manifest extends DeliveryConfig { version: 1; files: Asset[]; csp: string; lockSha256: string }
export const digest = (value: string | Buffer): string => createHash('sha256').update(value).digest('base64');
export const mimeTypes: Readonly<Record<string, string>> = { '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.woff2': 'font/woff2', '.woff': 'font/woff', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.html': 'text/html; charset=utf-8' };

export async function addSubresourceIntegrity(root: string, html: string): Promise<string> {
  const edits: { offset: number; text: string }[] = [];
  async function visit(node: DefaultTreeAdapterMap['node']): Promise<void> {
    if ('tagName' in node && (node.tagName === 'script' || node.tagName === 'link')) {
      const source = node.attrs.find(attr => attr.name === (node.tagName === 'script' ? 'src' : 'href'))?.value;
      if (source) {
        if (!/^\/_next\/static\/[a-zA-Z0-9_./-]+$/.test(source) || source.includes('..') || node.attrs.some(attr => attr.name === 'integrity')) throw new Error('DELIVERY_EXTERNAL_ASSET');
        const offset = node.sourceCodeLocation?.startTag?.endOffset;
        if (!offset) throw new Error('DELIVERY_ASSET_LOCATION');
        const hash = digest(await readFile(join(root, source)));
        const position = html[offset - 2] === '/' ? offset - 2 : offset - 1;
        edits.push({ offset: position, text: ` integrity="sha256-${hash}"${node.attrs.some(attr => attr.name === 'crossorigin') ? '' : ' crossorigin="anonymous"'}` });
      }
    }
    if ('childNodes' in node) for (const child of node.childNodes) await visit(child);
  }
  await visit(parse(html, { sourceCodeLocationInfo: true }));
  for (const edit of edits.sort((a, b) => b.offset - a.offset)) html = html.slice(0, edit.offset) + edit.text + html.slice(edit.offset);
  return html;
}

export function contentPolicy(html: string, apiOrigin: string): string {
  canonicalHttpsOrigin(apiOrigin);
  const scripts = new Set<string>(), styles = new Set<string>();
  function visit(node: DefaultTreeAdapterMap['node']): void {
    if ('tagName' in node) {
      if (node.attrs.some(attr => /^on/i.test(attr.name))) throw new Error('DELIVERY_INLINE_HANDLER');
      if (node.tagName === 'script' && !node.attrs.some(attr => attr.name === 'src') || node.tagName === 'style') {
        const location = node.sourceCodeLocation;
        if (!location?.startTag || !location.endTag) throw new Error('DELIVERY_INLINE_LOCATION');
        const content = html.slice(location.startTag.endOffset, location.endTag.startOffset);
        (node.tagName === 'script' ? scripts : styles).add(`'sha256-${digest(content)}'`);
      }
      for (const attr of node.attrs) {
        if ((node.tagName === 'script' && attr.name === 'src') || (node.tagName === 'link' && attr.name === 'href')) {
          if (!/^\/_next\/static\/[a-zA-Z0-9_./-]+$/.test(attr.value) || attr.value.includes('..')) throw new Error('DELIVERY_EXTERNAL_ASSET');
        }
      }
    }
    if ('childNodes' in node) node.childNodes.forEach(visit);
  }
  visit(parse(html, { sourceCodeLocationInfo: true }));
  return [
    "default-src 'none'", `script-src 'self' ${[...scripts].sort().join(' ')}`.trim(), "script-src-attr 'none'",
    `style-src 'self' ${[...styles].sort().join(' ')}`.trim(), "style-src-attr 'none'", "img-src 'self'", "font-src 'self'",
    `connect-src ${apiOrigin}`, "object-src 'none'", "base-uri 'none'", "frame-ancestors 'none'", "frame-src 'none'",
    "form-action 'none'", "worker-src 'none'", "manifest-src 'none'", 'upgrade-insecure-requests',
  ].join('; ');
}

export async function filesBelow(root: string, relative = ''): Promise<string[]> {
  const entries = await readdir(join(root, relative), { withFileTypes: true });
  const files: string[] = [];
  for (const entry of entries) {
    if (entry.isSymbolicLink()) throw new Error('DELIVERY_SYMLINK');
    const path = relative ? `${relative}/${entry.name}` : entry.name;
    if (entry.isDirectory()) files.push(...await filesBelow(root, path));
    else if (entry.isFile()) files.push(path);
    else throw new Error('DELIVERY_SPECIAL_FILE');
  }
  return files.sort();
}

export async function createManifest(root: string, config: DeliveryConfig, lock: Buffer): Promise<Manifest> {
  canonicalHttpsOrigin(config.webOrigin); canonicalHttpsOrigin(config.apiOrigin);
  const files: Asset[] = [];
  for (const file of await filesBelow(root)) {
    // This CSR app has one document. RSC payloads, diagnostics, source maps and framework error pages are not routes.
    if (file !== 'index.html' && !file.startsWith('_next/static/')) continue;
    const extension = file.slice(file.lastIndexOf('.'));
    const mime = mimeTypes[extension];
    if (!mime || !/^[a-zA-Z0-9_./-]+$/.test(file) || file.includes('..')) throw new Error('DELIVERY_UNEXPECTED_ASSET');
    files.push({ path: `/${file}`, sha256: digest(await readFile(join(root, file))), mime, immutable: file.startsWith('_next/static/') });
  }
  const html = await readFile(join(root, 'index.html'), 'utf8');
  return { version: 1, ...config, files, csp: contentPolicy(html, config.apiOrigin), lockSha256: digest(lock) };
}

function record(value: unknown): value is Record<string, unknown> { return typeof value === 'object' && value !== null && !Array.isArray(value); }
export function parseManifest(value: unknown, config: DeliveryConfig): Manifest {
  if (!record(value) || value['version'] !== 1 || value['webOrigin'] !== config.webOrigin || value['apiOrigin'] !== config.apiOrigin || typeof value['csp'] !== 'string' || typeof value['lockSha256'] !== 'string' || !/^[A-Za-z0-9+/]{43}=$/.test(value['lockSha256']) || !Array.isArray(value['files']) || value['files'].length > 10000) throw new Error('DELIVERY_MANIFEST_INVALID');
  const files: Asset[] = [];
  const paths = new Set<string>();
  for (const file of value['files']) {
    if (!record(file) || typeof file['path'] !== 'string' || !/^\/(?:index\.html|_next\/static\/[a-zA-Z0-9_./-]+)$/.test(file['path']) || file['path'].includes('..') || paths.has(file['path']) || typeof file['sha256'] !== 'string' || !/^[A-Za-z0-9+/]{43}=$/.test(file['sha256']) || typeof file['mime'] !== 'string' || file['mime'] !== mimeTypes[file['path'].slice(file['path'].lastIndexOf('.'))] || file['immutable'] !== file['path'].startsWith('/_next/static/')) throw new Error('DELIVERY_MANIFEST_INVALID');
    files.push({ path: file['path'], sha256: file['sha256'], mime: file['mime'], immutable: file['immutable'] });
    paths.add(file['path']);
  }
  if (!paths.has('/index.html')) throw new Error('DELIVERY_MANIFEST_INVALID');
  return { version: 1, ...config, files, csp: value['csp'], lockSha256: value['lockSha256'] };
}

export async function loadArtifact(root: string, config: DeliveryConfig): Promise<{ manifest: Manifest; assets: Map<string, Buffer> }> {
  const manifestFile = join(root, 'delivery-manifest.json');
  if ((await lstat(manifestFile)).isSymbolicLink()) throw new Error('DELIVERY_SYMLINK');
  const manifest = parseManifest(JSON.parse(await readFile(manifestFile, 'utf8')) as unknown, config);
  // Reject symlinks anywhere; hold verified bytes in memory so replacement after startup cannot change a response.
  await filesBelow(root);
  const assets = new Map<string, Buffer>();
  let bytes = 0;
  for (const file of manifest.files) {
    const body = await readFile(join(root, file.path));
    bytes += body.length;
    if (bytes > 128 * 1024 * 1024 || digest(body) !== file.sha256) throw new Error('DELIVERY_INTEGRITY_FAILED');
    assets.set(file.path, body);
  }
  const html = assets.get('/index.html');
  if (!html || contentPolicy(html.toString('utf8'), config.apiOrigin) !== manifest.csp) throw new Error('DELIVERY_CSP_MISMATCH');
  return { manifest, assets };
}
