import { spawn } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { prepareDeliveryBuild } from './config.mts';
import { addSubresourceIntegrity, createManifest } from './artifact.mts';

const root = fileURLToPath(new URL('..', import.meta.url));
try {
  const config = await prepareDeliveryBuild(join(root, 'out'), process.env);
  const code = await new Promise<number | null>((resolve, reject) => {
    const child = spawn(process.execPath, [join(root, 'node_modules/next/dist/bin/next'), 'build'], {
      cwd: root, stdio: 'inherit', env: { ...process.env, NEXT_PUBLIC_API_URL: config.apiOrigin, NEXT_TELEMETRY_DISABLED: '1' },
    });
    child.once('error', reject); child.once('exit', resolve);
  });
  if (code !== 0) throw new Error('DELIVERY_BUILD_FAILED');
  const output = join(root, 'out');
  const htmlPath = join(output, 'index.html');
  await writeFile(htmlPath, await addSubresourceIntegrity(output, await readFile(htmlPath, 'utf8')));
  const manifest = await createManifest(output, config, await readFile(join(root, 'package-lock.json')));
  await writeFile(join(root, 'out', 'delivery-manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`, { mode: 0o600 });
  process.stdout.write('DELIVERY_BUILD_READY\n');
} catch {
  process.stderr.write('DELIVERY_BUILD_FAILED: require canonical HTTPS origins and a successful static export.\n');
  process.exitCode = 1;
}
