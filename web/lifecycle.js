/* Eight Bells tab lifecycle: the open tab keeps the local server alive. No network beyond the local server. */
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.EightBellsLifecycle=api;})(typeof globalThis!=='undefined'?globalThis:this,function(){
"use strict";
function newTabId(env){
 const c=env.crypto;
 if(c&&typeof c.randomUUID==='function')return c.randomUUID().replace(/[^A-Za-z0-9-]/g,'');
 return 'tab-'+Date.now().toString(36)+'-'+Math.random().toString(36).slice(2,10);
}
// Heartbeat every intervalMs with the session header; on pagehide a sendBeacon "leaving" signal.
// sendBeacon cannot set headers, so that one request carries the token in its JSON body (never in the URL).
// The server stops 20 s after the last heartbeat, or 5 s after a leaving signal; a reload sends a new
// heartbeat inside that grace. Returns a function that stops the heartbeat (used by End session).
// options.onStatus(ok), when given, hears whether each heartbeat reached the server (the status bar's engine state).
function startHeartbeat(options){
 const o=options||{};
 const env=o.env||(typeof window!=='undefined'?window:{});
 const token=o.token;
 if(!token)return function(){};
 const doFetch=o.fetch||(env.fetch?env.fetch.bind(env):null);
 const nav=o.navigator||env.navigator;
 const doc=o.document||env.document;
 const path=o.path||'/api/heartbeat';
 const tab=o.tabId||newTabId(env);
 let stopped=false;
 const report=ok=>{if(stopped||typeof o.onStatus!=='function')return;try{o.onStatus(ok);}catch(e){/* status display only */}};
 const send=leaving=>{
  if(stopped||!doFetch)return;
  try{
   const p=doFetch(path,{method:'POST',headers:{'X-EightBells-Token':token,'Content-Type':'application/json'},body:JSON.stringify({tab,leaving:!!leaving}),cache:'no-store',keepalive:true});
   if(p&&typeof p.then==='function')p.then(r=>report(!!r&&r.ok!==false),()=>report(false));
  }catch(e){report(false);/* server already gone */}
 };
 const onHide=()=>{
  if(stopped)return;
  let sent=false;
  try{
   if(nav&&typeof nav.sendBeacon==='function'){
    const body=JSON.stringify({tab,leaving:true,session:token});
    const payload=typeof Blob!=='undefined'?new Blob([body],{type:'application/json'}):body;
    sent=nav.sendBeacon(path,payload);
   }
  }catch(e){sent=false;}
  if(!sent)send(true);
 };
 const onShow=()=>send(false);
 const onVisible=()=>{if(doc&&doc.visibilityState==='visible')send(false);};
 send(false);
 const timer=env.setInterval?env.setInterval(()=>send(false),o.intervalMs||5000):null;
 if(env.addEventListener){env.addEventListener('pagehide',onHide);env.addEventListener('pageshow',onShow);}
 if(doc&&doc.addEventListener)doc.addEventListener('visibilitychange',onVisible);
 return function stop(){
  stopped=true;
  if(timer!==null&&env.clearInterval)env.clearInterval(timer);
  if(env.removeEventListener){env.removeEventListener('pagehide',onHide);env.removeEventListener('pageshow',onShow);}
  if(doc&&doc.removeEventListener)doc.removeEventListener('visibilitychange',onVisible);
 };
}
return {startHeartbeat};
});
