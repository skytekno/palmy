const urls=process.argv.slice(2);
if(!urls.length) throw new Error('Supply URLs to wait for');
for(const url of urls) {
 const deadline=Date.now()+30000;
 for(;;) {
  try { if((await fetch(url,{signal:AbortSignal.timeout(1000)})).ok) break; } catch {}
  if(Date.now()>deadline) throw new Error('Local service did not become ready within 30 seconds');
  await new Promise(resolve=>setTimeout(resolve,250));
 }
}
console.log('Local services ready.');
