import { createServer, type Server } from 'node:https';
import { readFile } from 'node:fs/promises';
import { X509Certificate } from 'node:crypto';
import { isIP } from 'node:net';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { canonicalHttpsOrigin, deliveryConfig, type DeliveryConfig } from './config.mts';
import { loadArtifact } from './artifact.mts';

export interface DeliveryEvent { event: 'delivery_request'; result: 'document' | 'asset' | 'rejected'; status: number; method: 'GET' | 'HEAD' | 'other' }
export interface ServerOptions { root: string; config: DeliveryConfig; key: Buffer; cert: Buffer; log: (event: DeliveryEvent) => void }

export async function createDeliveryServer(options: ServerOptions): Promise<Server> {
  canonicalHttpsOrigin(options.config.webOrigin); canonicalHttpsOrigin(options.config.apiOrigin);
  const hostname = new URL(options.config.webOrigin).hostname.replace(/^\[|\]$/g, '');
  const leaf = new X509Certificate(options.cert);
  if (!(isIP(hostname) ? leaf.checkIP(hostname) : leaf.checkHost(hostname)) || Date.now() < Date.parse(leaf.validFrom) || Date.now() >= Date.parse(leaf.validTo)) throw new Error('DELIVERY_CERTIFICATE_INVALID');
  const { manifest, assets } = await loadArtifact(options.root, options.config);
  const index = new Map(manifest.files.map(file => [file.path, file]));
  const host = new URL(options.config.webOrigin).host;
  function handle(request: IncomingMessage, response: ServerResponse): void {
    const method = request.method === 'GET' || request.method === 'HEAD' ? request.method : 'other';
    const headers: Record<string, string> = {
      'Content-Security-Policy': manifest.csp,
      'Strict-Transport-Security': 'max-age=31536000',
      'X-Content-Type-Options': 'nosniff', 'X-Frame-Options': 'DENY', 'Referrer-Policy': 'no-referrer',
      'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Resource-Policy': 'same-origin',
      'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), payment=(), usb=(), browsing-topics=()',
      'Cache-Control': 'no-store', 'Content-Type': 'text/plain; charset=utf-8',
    };
    function send(status: number, result: DeliveryEvent['result'], body: Buffer | string): void {
      response.writeHead(status, { ...headers, 'Content-Length': Buffer.byteLength(body) });
      response.end(method === 'HEAD' ? undefined : body);
      options.log({ event: 'delivery_request', result, status, method });
    }
    // Never trust forwarded headers. TLS terminates here; the canonical Host is exact, not a suffix allowlist.
    if (request.headers.host !== host || (request.headers.origin !== undefined && request.headers.origin !== options.config.webOrigin)) return send(421, 'rejected', 'Misdirected request');
    if (method === 'other') { headers['Allow'] = 'GET, HEAD'; return send(405, 'rejected', 'Method not allowed'); }
    const path = request.url ?? '';
    // Query strings are not app state; reject rather than record or reflect possibly sensitive input.
    if (!/^\/[a-zA-Z0-9_./-]*$/.test(path) || path.includes('..') || path.includes('//')) return send(400, 'rejected', 'Invalid request');
    const route = path === '/' ? '/index.html' : path;
    const asset = index.get(route), body = assets.get(route);
    if (!asset || !body) return send(404, 'rejected', 'Not found');
    headers['Content-Type'] = asset.mime;
    headers['Cache-Control'] = asset.immutable ? 'public, max-age=31536000, immutable' : 'no-store';
    // Release assets are verified at startup. A cache validator is unnecessary for immutable hashed URLs.
    return send(200, route === '/index.html' ? 'document' : 'asset', body);
  }
  const server = createServer({ key: options.key, cert: options.cert, minVersion: 'TLSv1.2', maxHeaderSize: 8192, requestTimeout: 15000, headersTimeout: 10000, keepAliveTimeout: 5000 }, handle);
  server.maxRequestsPerSocket = 100;
  // Parser and TLS errors contain caller-controlled bytes: never send them to the logger.
  server.on('clientError', (_error, socket) => { socket.destroy(); });
  server.on('tlsClientError', () => { /* TLS rejects invalid clients before any application request. */ });
  return server;
}

async function main(): Promise<void> {
  try {
    const config = deliveryConfig(process.env);
    const keyPath = process.env['PALMY_TLS_KEY'], certPath = process.env['PALMY_TLS_CERT'];
    if (!keyPath || !certPath) throw new Error('DELIVERY_TLS_REQUIRED');
    const server = await createDeliveryServer({ root: fileURLToPath(new URL('../out', import.meta.url)), config,
      key: await readFile(keyPath), cert: await readFile(certPath), log: event => process.stdout.write(`${JSON.stringify(event)}\n`) });
    server.once('error', () => { process.stderr.write('DELIVERY_START_FAILED\n'); process.exitCode = 1; });
    server.listen(Number(new URL(config.webOrigin).port || '443'), process.env['PALMY_BIND_HOST'] ?? '127.0.0.1', () => process.stdout.write('DELIVERY_READY\n'));
    for (const signal of ['SIGTERM', 'SIGINT'] as const) process.once(signal, () => { server.close(); server.closeIdleConnections(); });
  } catch { process.stderr.write('DELIVERY_START_FAILED: verify configuration, certificate, and release integrity.\n'); process.exitCode = 1; }
}
const entry = process.argv[1];
if (entry && import.meta.url === pathToFileURL(entry).href) await main();
