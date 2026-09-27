// Test real drill startup with a fake Docker CLI: only local metadata reads are allowed.
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, readFile, rm} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {join, delimiter} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
const fixture=await mkdtemp(join(tmpdir(),'palmy-drill-preflight-test-'));
const log=join(fixture,'calls');
try {
  await writeFile(join(fixture,'docker'),`#!${process.execPath}
import {appendFileSync} from 'node:fs';
const args=process.argv.slice(2);
appendFileSync(${JSON.stringify(log)},JSON.stringify(args)+'\\n');
if(args[0]==='context'&&args[1]==='show') process.stdout.write('fixture-current\\n');
else if(args[0]==='context'&&args[1]==='inspect') process.stdout.write('ssh://example.invalid\\n');
else process.exit(91);
`,{mode:0o700});
  // The fake CLI has no extension; mark its private directory as ESM explicitly.
  await writeFile(join(fixture,'package.json'),' {"type":"module"} ');
  const common={...process.env,PATH:fixture+delimiter+process.env.PATH};
  delete common.DOCKER_HOST; delete common.DOCKER_CONTEXT;
  const cases=[
    {name:'explicit remote host',variables:{DOCKER_HOST:'ssh://example.invalid'},commands:[]},
    {name:'explicit remote context',variables:{DOCKER_CONTEXT:'fixture-remote'},commands:['inspect']},
    {name:'configured remote context',variables:{},commands:['show','inspect']},
    {name:'remote host with overriding context',variables:{DOCKER_HOST:'tcp://example.invalid:2376',DOCKER_CONTEXT:'fixture-local'},commands:[]},
  ];
  for(const test of cases) {
    await writeFile(log,'');
    const result=spawnSync(process.execPath,[fileURLToPath(new URL('./backup-restore.mjs',import.meta.url))],{env:{...common,...test.variables},encoding:'utf8',timeout:15000});
    assert.equal(result.status,1,`${test.name}: rejection exit`);
    assert.match(result.stderr,/Remote Docker (endpoints|contexts) are forbidden/);
    assert.ok(!result.stderr.includes('example.invalid'),'Endpoint must not leak in diagnostics');
    const calls=(await readFile(log,'utf8')).trim().split('\n').filter(Boolean).map(line=>JSON.parse(line));
    assert.deepEqual(calls.map(args=>args[1]),test.commands,`${test.name}: no daemon/resource/cleanup calls`);
    assert.ok(calls.every(args=>args[0]==='context'));
    console.log(`PASS: ${test.name} rejected before daemon contact or resource creation`);
  }
} finally { await rm(fixture,{recursive:true,force:true}); }
