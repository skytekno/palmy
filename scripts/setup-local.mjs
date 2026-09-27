import { randomBytes } from 'node:crypto';
import { writeFileSync, existsSync } from 'node:fs';
const path = new URL('../.env', import.meta.url);
if (existsSync(path)) { console.log('.env already exists; preserved.'); process.exit(0); }
const owner = randomBytes(24).toString('hex');
const runtime = randomBytes(24).toString('hex');
writeFileSync(path, `PALMY_DB_OWNER_PASSWORD=${owner}\nPALMY_DB_RUNTIME_PASSWORD=${runtime}\nDATABASE_URL=postgres://palmy_runtime:${runtime}@127.0.0.1:55432/palmy\nMIGRATION_DATABASE_URL=postgres://palmy_owner:${owner}@127.0.0.1:55432/palmy\nREDIS_URL=redis://127.0.0.1:56379\nBIND_ADDR=0.0.0.0:8100\nCORS_ORIGINS=http://localhost:3100,http://127.0.0.1:3100\n`, {mode:0o600,flag:'wx'});
console.log('Created local .env with independent random database passwords (mode 0600).');
