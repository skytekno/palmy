// An arbitrary failure is NOT success: verify the real post-backup failure and cleanup.
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const expectedError='FAIL: Injected failure after encrypted backup; cleanup must still complete';
const expectedOutput=[
  'Starting isolated synthetic backup drill. No development database is used.',
  'PASS: authenticated encrypted snapshot; wrong-key, tamper and truncation failures rejected before restore.',
  "PASS: only this drill's containers/volumes removed; temporary key/archive directory deleted.",
];
const child=spawn(process.execPath,[fileURLToPath(new URL('./backup-restore.mjs',import.meta.url)),'--inject-failure-after-backup'],{stdio:['ignore','pipe','pipe']});
let stdout='',stderr='',failed=false,interrupted=false;
for(const signal of ['SIGINT','SIGTERM']) process.once(signal,()=>{ interrupted=true; child.kill('SIGTERM'); });
child.stdout.on('data',bytes=>{ stdout+=bytes; if(stdout.length>65536) { failed=true; child.kill('SIGTERM'); } });
child.stderr.on('data',bytes=>{ stderr+=bytes; if(stderr.length>65536) { failed=true; child.kill('SIGTERM'); } });
child.on('error',()=>{ failed=true; });
const timeout=setTimeout(()=>{ failed=true; child.kill('SIGTERM'); },600_000);
const forceTimeout=setTimeout(()=>{ failed=true; child.kill('SIGKILL'); },675_000);
const code=await new Promise(resolve=>child.on('close',resolve));
clearTimeout(timeout); clearTimeout(forceTimeout);
const lines=stdout.trim().split(/\r?\n/);
if(failed || interrupted || code!==1 || stderr.trim()!==expectedError || JSON.stringify(lines)!==JSON.stringify(expectedOutput)) {
  // Do not echo unexpected subprocess output: it is not an approved diagnostic channel.
  console.error('FAIL: negative backup test did not reach the exact injected-failure and successful-cleanup boundaries');
  process.exitCode=1;
} else console.log('PASS: real encrypted backup reached, intentional failure exited 1, and owned-resource cleanup completed; no other error accepted.');
