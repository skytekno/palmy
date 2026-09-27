import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
const generated=execFileSync('cargo',['run','--quiet','--locked','-p','palmy-api','--bin','export-openapi'],{encoding:'utf8',stdio:['ignore','pipe','inherit']});
assert.deepEqual(JSON.parse(readFileSync('contracts/openapi.json','utf8')),JSON.parse(generated),'Regenerate contracts/openapi.json from the implemented API.');
console.log('PASS: committed OpenAPI matches runtime generator.');
