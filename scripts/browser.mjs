import assert from 'node:assert/strict';
import { mkdir, readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { chromium, expect } from '@playwright/test';
const baseURL=process.env.PALMY_TEST_WEB_URL??'http://localhost:3100';
if(!['localhost','127.0.0.1','[::1]'].includes(new URL(baseURL).hostname)) throw new Error('Browser fixture creation is restricted to a local app.');
await mkdir('artifacts/local',{recursive:true});
const browser=await chromium.launch();
const requests=[], failures=[], responseIds=[], browserLogs=[];
const descriptionCanary=`Private financial note ${randomUUID()}`;
async function assertNoCanariesInArtifacts(canaries) {
 const inspect=async path=>{
  const content=await readFile(path);
  for(const value of canaries) assert.ok(!content.includes(Buffer.from(value)),'Runtime sensitive canary found in build output or telemetry; contents deliberately omitted');
 };
 const visit=async path=>{
  for(const entry of await readdir(path,{withFileTypes:true})) {
   const child=join(path,entry.name);
   if(entry.isDirectory()) await visit(child);
   else if(entry.isFile()) await inspect(child);
  }
 };
 await visit('web/out');
 const logs=process.env.PALMY_TEST_LOGS?.split(',').filter(Boolean)??[];
 if(process.env.CI) assert.ok(logs.length>=2,'CI requires API and web telemetry evidence paths');
 let telemetry='';
 for(const path of logs) { await inspect(path); telemetry+=await readFile(path,'utf8'); }
 if(logs.length) assert.ok(responseIds.filter(id=>telemetry.includes(id)).length>=3,'Telemetry evidence must include correlated real browser API responses');
 console.log(`PASS: generated runtime canaries absent from static build and ${logs.length} configured telemetry logs.`);
}
function observe(page) {
 page.on('request',request=>requests.push({url:request.url(),headers:request.headers(),body:request.postData()??''}));
 page.on('response',response=>{
  if(new URL(response.url()).pathname.startsWith('/api/v1/')) {
   const id=response.headers()['x-request-id'];
   if(id) responseIds.push(id);
  }
 });
 page.on('pageerror',error=>failures.push(error.message));
 page.on('console',message=>browserLogs.push(message.text()));
}
async function assertNoPersistentSecrets(page) {
 assert.deepEqual(await page.evaluate(()=>({local:localStorage.length,session:sessionStorage.length})),{local:0,session:0});
 assert.equal((await page.context().cookies()).length,0);
}
async function recover(page,key) {
 await page.getByRole('button',{name:'Pulihkan akun',exact:true}).click();
 await page.getByLabel('Kunci pemulihan',{exact:false}).fill(key);
 await page.getByRole('button',{name:'Buka akun saya',exact:true}).click();
 await expect(page.getByRole('heading',{name:/Halo,/})).toBeVisible();
}
try {
 const context=await browser.newContext({viewport:{width:1440,height:1000},baseURL});
 const page=await context.newPage(); observe(page);
 await page.goto('/'); await expect(page.getByRole('button',{name:'Mulai perjalananmu'})).toBeVisible();
 await page.screenshot({path:'artifacts/local/web-welcome.png',fullPage:true});
 await page.getByLabel('Nama panggilan',{exact:true}).fill('Browser Private Owner');
 await page.getByLabel('Email',{exact:false}).fill('browser-private@example.invalid');
 await page.getByRole('button',{name:'Mulai perjalananmu'}).click();
 const key=await page.getByLabel('Kunci pemulihan',{exact:true}).inputValue(); assert.match(key,/^palmy1\./);
 await expect(page.getByRole('button',{name:'Buat akun dan masuk'})).toBeDisabled();
 assert.ok(!requests.some(r=>r.url.endsWith('/accounts')),'Account must not be committed before recovery acknowledgment');
 await page.getByRole('checkbox',{name:/Saya sudah menyimpan kunci/}).check();
 await page.getByRole('button',{name:'Buat akun dan masuk'}).click();
 await expect(page.getByRole('heading',{name:'Halo, Browser Private Owner.'})).toBeVisible();
 await page.getByRole('button',{name:'Buat dompet pertama'}).click();
 await page.getByRole('dialog',{name:'Buat dompet baru'}).getByLabel('Nama dompet',{exact:true}).fill('Dompet Uji Browser');
 await page.getByRole('button',{name:'Simpan dompet',exact:true}).click();
 await expect(page.getByRole('status').filter({hasText:'Dompet berhasil dibuat.'})).toBeVisible();
 await page.getByRole('button',{name:'Catat transaksi',exact:true}).click();
 let dialog=page.getByRole('dialog',{name:'Catat transaksi'});
 await dialog.getByRole('button',{name:'Pemasukan',exact:true}).click();
 await dialog.getByLabel('Jumlah (IDR)',{exact:false}).fill('2000');
 await dialog.getByLabel('Kategori',{exact:true}).fill('Pendapatan Uji');
 await dialog.getByRole('button',{name:'Simpan transaksi',exact:true}).click();
 await expect(page.getByRole('status').filter({hasText:'Transaksi berhasil dicatat.'})).toBeVisible();
 await page.getByRole('button',{name:'Catat transaksi',exact:true}).click();
 dialog=page.getByRole('dialog',{name:'Catat transaksi'});
 await dialog.getByLabel('Jumlah (IDR)',{exact:false}).fill('1.001');
 await dialog.getByLabel('Kategori',{exact:true}).fill('Belanja Uji');
 await dialog.getByLabel('Catatan',{exact:false}).fill(descriptionCanary);
 await dialog.getByRole('button',{name:'Simpan transaksi',exact:true}).click();
 await expect(dialog.getByRole('alert')).toBeVisible();
 await dialog.getByLabel('Jumlah (IDR)',{exact:false}).fill('1234.56');
 await dialog.getByRole('button',{name:'Simpan transaksi',exact:true}).click();
 await expect(page.getByRole('region',{name:'Ringkasan keuangan'})).toContainText('Rp 765,44');
 await assertNoPersistentSecrets(page);
 await page.screenshot({path:'artifacts/local/web-dashboard.png',fullPage:true});
 await page.getByRole('navigation',{name:'Navigasi utama'}).getByRole('button',{name:'Profil',exact:true}).click();
 await page.getByLabel('Nama panggilan',{exact:true}).fill('Updated Browser Owner');
 await page.getByRole('button',{name:'Simpan profil',exact:true}).click();
 await expect(page.getByRole('status').filter({hasText:'Profil dienkripsi dan berhasil disimpan.'})).toBeVisible();
 // Delay transport, then send the real revocation: local lock must not await a network response.
 let releaseRevocation;
 const gate=new Promise(resolve=>{releaseRevocation=resolve;});
 await page.route('**/api/v1/auth/session',async route=>{await gate;await route.continue();});
 const revoked=page.waitForResponse(response=>response.url().endsWith('/auth/session')&&response.request().method()==='DELETE');
 await page.getByRole('button',{name:'Kunci akun',exact:true}).click();
 try { await expect(page.getByRole('button',{name:'Pulihkan akun',exact:true})).toBeVisible({timeout:1500}); }
 finally { releaseRevocation(); }
 assert.equal((await revoked).status(),204);
 await page.unrouteAll({behavior:'wait'});
 await assertNoPersistentSecrets(page);
 await context.close();

 const mobile=await browser.newContext({viewport:{width:390,height:844},isMobile:true,deviceScaleFactor:1,baseURL});
 const small=await mobile.newPage(); observe(small); await small.goto('/');
 await recover(small,key);
 await expect(small.getByRole('heading',{name:'Halo, Updated Browser Owner.'})).toBeVisible();
 await expect(small.getByRole('region',{name:'Ringkasan keuangan'})).toContainText('Rp 765,44');
 assert.ok(await small.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Mobile layout overflows viewport');
 await small.screenshot({path:'artifacts/local/web-mobile.png',fullPage:true});
 await small.setViewportSize({width:320,height:780});
 assert.ok(await small.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'320px layout overflows viewport');
 await small.setViewportSize({width:390,height:844});
 await assertNoPersistentSecrets(small);
 await small.reload(); await expect(small.getByRole('button',{name:'Pulihkan akun',exact:true})).toBeVisible();
 await recover(small,key);
 await small.getByRole('button',{name:'Kunci akun',exact:true}).click();
 await expect(small.getByRole('button',{name:'Pulihkan akun',exact:true})).toBeVisible();
 const payloads=JSON.stringify(requests);
 for(const secret of [key,'Browser Private Owner','Updated Browser Owner','browser-private@example.invalid']) assert.ok(!payloads.includes(secret),'Plaintext profile or recovery credential leaked in a request');
 assert.ok(requests.some(r=>r.url.endsWith('/transactions')&&r.body.includes('1234.56')),'Financial amount should remain readable on the wire');
 assert.ok(requests.some(r=>r.url.endsWith('/transactions')&&r.body.includes(descriptionCanary)),'Real API must receive the financial-description canary');
 assert.equal(failures.length,0,'Browser runtime errors observed; contents deliberately omitted');
 const bearerTokens=requests.map(r=>r.headers.authorization?.replace(/^Bearer /,'')).filter(Boolean);
 assert.ok(bearerTokens.length>0,'Expected actual authenticated browser requests');
 const canaries=[key,...bearerTokens,descriptionCanary,'Browser Private Owner','Updated Browser Owner','browser-private@example.invalid','Dompet Uji Browser','Pendapatan Uji','Belanja Uji'];
 for(const value of canaries) assert.ok(!browserLogs.some(line=>line.includes(value)),'Sensitive canary found in browser console');
 for(const request of requests) {
  for(const value of canaries) {
   assert.ok(!decodeURIComponent(request.url).includes(value),'Sensitive canary found in a URL');
   assert.ok(!(request.headers.referer??'').includes(value),'Sensitive canary found in a referrer');
  }
 }
 await assertNoCanariesInArtifacts(canaries);
 await mobile.close();
 console.log('PASS: Chromium desktop/mobile real-account creation, saved-key gate, wallet/income/expense, precision error, encrypted profile update, recovery, lock/reload, no persistent browser credentials, no plaintext identity/recovery network leakage, and no runtime errors.');
} finally { await browser.close(); }
