import { readFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
const env = {...process.env};
for (const line of readFileSync(new URL('../.env', import.meta.url),'utf8').split('\n')) {
 if (!line || line.startsWith('#')) continue;
 const i=line.indexOf('='); if (i<1) throw new Error('Invalid local env line');
 const key=line.slice(0,i); if (!(key in env)) env[key]=line.slice(i+1);
}
// This wrapper explicitly targets the repository's local development environment.
env.PALMY_ENV ??= 'development';
const [cmd,...args]=process.argv.slice(2);
if(!cmd) throw new Error('Usage: node scripts/with-env.mjs COMMAND ARGS...');
const child=spawn(cmd,args,{env,stdio:'inherit'});
child.on('error',()=>{console.error('Could not start command');process.exit(1);});
child.on('exit',code=>process.exit(code??1));
for(const signal of ['SIGINT','SIGTERM']) process.on(signal,()=>child.kill(signal));
