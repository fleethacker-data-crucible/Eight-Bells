'use strict';
const assert=require('assert');
const lifecycle=require('../web/lifecycle.js');
function fakeEnv(options){
 const o=options||{};
 const listeners={},docListeners={},calls=[],beacons=[];let timer=null,cleared=false;
 const env={
  crypto:{randomUUID:()=>'11111111-2222-3333-4444-555555555555'},
  setInterval:(fn,ms)=>{timer={fn,ms};return 7;},
  clearInterval:id=>{if(id===7)cleared=true;},
  addEventListener:(n,f)=>{listeners[n]=f;},
  removeEventListener:(n,f)=>{if(listeners[n]===f)delete listeners[n];},
  fetch:(path,init)=>{calls.push({path,init,body:JSON.parse(init.body)});return Promise.resolve({ok:true});},
  navigator:o.noBeacon?{}:{sendBeacon:(path,data)=>{beacons.push({path,data});return o.beaconResult!==false;}},
  document:{visibilityState:'visible',addEventListener:(n,f)=>{docListeners[n]=f;},removeEventListener:(n,f)=>{if(docListeners[n]===f)delete docListeners[n];}}
 };
 return {env,listeners,docListeners,calls,beacons,timer:()=>timer,cleared:()=>cleared};
}
const blobText=async data=>typeof data==='string'?data:await data.text();
(async()=>{
 // No token: nothing is sent and nothing is registered.
 let f=fakeEnv();
 lifecycle.startHeartbeat({env:f.env,token:''})();
 assert.strictEqual(f.calls.length,0);assert.strictEqual(f.timer(),null);
 // Heartbeat: immediately, then every 5 s, with the session header and a tab id; no token in the URL or body.
 f=fakeEnv();
 const stop=lifecycle.startHeartbeat({env:f.env,token:'tok-123'});
 assert.strictEqual(f.calls.length,1);
 assert.strictEqual(f.timer().ms,5000);
 const first=f.calls[0];
 assert.strictEqual(first.path,'/api/heartbeat');
 assert.strictEqual(first.init.method,'POST');
 assert.strictEqual(first.init.headers['X-EightBells-Token'],'tok-123');
 assert.strictEqual(first.body.leaving,false);
 assert.strictEqual(first.body.session,undefined,'Normal heartbeats use the header, not the body');
 assert(/^[A-Za-z0-9-]+$/.test(first.body.tab));
 assert(!first.path.includes('tok-123'));
 f.timer().fn();f.timer().fn();
 assert.strictEqual(f.calls.length,3);
 assert(f.calls.every(c=>c.body.tab===first.body.tab));
 // pagehide: sendBeacon with the token in the JSON body (it cannot set headers), never the query string.
 f.listeners.pagehide();
 assert.strictEqual(f.beacons.length,1);
 assert.strictEqual(f.beacons[0].path,'/api/heartbeat');
 const beacon=JSON.parse(await blobText(f.beacons[0].data));
 assert.deepStrictEqual(beacon,{tab:first.body.tab,leaving:true,session:'tok-123'});
 assert.strictEqual(f.calls.length,3,'A delivered beacon is not duplicated by fetch');
 // pageshow (back/forward cache) and becoming visible send a fresh heartbeat so the server cancels the leaving.
 f.listeners.pageshow();f.docListeners.visibilitychange();
 assert.strictEqual(f.calls.length,5);assert.strictEqual(f.calls[4].body.leaving,false);
 // End session stops the heartbeat and removes the listeners.
 stop();
 assert(f.cleared());assert.strictEqual(f.listeners.pagehide,undefined);assert.strictEqual(f.docListeners.visibilitychange,undefined);
 // Without sendBeacon (or if it is refused) a keepalive fetch carries the leaving signal with the header.
 f=fakeEnv({beaconResult:false});
 lifecycle.startHeartbeat({env:f.env,token:'tok-9'});
 f.listeners.pagehide();
 const last=f.calls[f.calls.length-1];
 assert.strictEqual(last.body.leaving,true);assert.strictEqual(last.init.keepalive,true);assert.strictEqual(last.init.headers['X-EightBells-Token'],'tok-9');
 f=fakeEnv({noBeacon:true});
 lifecycle.startHeartbeat({env:f.env,token:'tok-9'});
 f.listeners.pagehide();
 assert.strictEqual(f.calls[f.calls.length-1].body.leaving,true);
 // A failing fetch (server already gone) never throws into the page.
 f=fakeEnv();f.env.fetch=()=>{throw Error('offline');};
 lifecycle.startHeartbeat({env:f.env,token:'tok'});f.timer().fn();
 f=fakeEnv();f.env.fetch=()=>Promise.reject(Error('offline'));
 lifecycle.startHeartbeat({env:f.env,token:'tok'});f.timer().fn();
 // Two tabs get different ids, so the server can tell them apart.
 const a=fakeEnv(),b=fakeEnv();a.env.crypto=b.env.crypto=undefined;
 lifecycle.startHeartbeat({env:a.env,token:'t'});lifecycle.startHeartbeat({env:b.env,token:'t'});
 assert.notStrictEqual(a.calls[0].body.tab,b.calls[0].body.tab);
 console.log('PASS: 8 tab lifecycle tests (heartbeat, beacon, fallback, pageshow, stop, tab ids)');
})().catch(e=>{console.error(e);process.exit(1);});
