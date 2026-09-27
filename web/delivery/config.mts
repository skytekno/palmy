import { rm } from 'node:fs/promises';
import { join } from 'node:path';

export interface DeliveryConfig { webOrigin: string; apiOrigin: string }

export function canonicalHttpsOrigin(value: string | undefined): string {
  if (!value) throw new Error('DELIVERY_ORIGIN_REQUIRED');
  let url: URL;
  try { url = new URL(value); } catch { throw new Error('DELIVERY_ORIGIN_INVALID'); }
  if (url.protocol !== 'https:' || value !== url.origin || url.username || url.password || url.hostname.includes('*') || url.hostname.endsWith('.')) {
    throw new Error('DELIVERY_ORIGIN_INVALID');
  }
  return value;
}

export function deliveryConfig(env: Readonly<Record<string, string | undefined>>): DeliveryConfig {
  if ((env['PALMY_ENV'] ?? 'production') !== 'production') throw new Error('DELIVERY_PRODUCTION_REQUIRED');
  return { webOrigin: canonicalHttpsOrigin(env['PALMY_WEB_ORIGIN']), apiOrigin: canonicalHttpsOrigin(env['NEXT_PUBLIC_API_URL']) };
}

export async function prepareDeliveryBuild(output: string, env: Readonly<Record<string, string | undefined>>): Promise<DeliveryConfig> {
  // Configuration failure must not leave a stale release marker for a later server start.
  await rm(join(output, 'delivery-manifest.json'), { force: true });
  return deliveryConfig(env);
}
