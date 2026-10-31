/* Eight Bells schema: stable IDs and provenance for the records in docs/ARCHITECTURE.md ("Future schema"), and the lesson
   lifecycle. IDs are derived from content with SHA-256, so the same source always gives the same IDs and an edited source
   gives new ones; originals are never rewritten. The lesson lifecycle is a checked state machine with a two-person rule
   (the author cannot approve their own lesson). Records are plain objects and every transition returns a NEW lesson.
   This is a library: the server does not store these records yet, and "reviewer" is a name someone typed, not a verified
   identity. No network, no dependencies. */
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.EightBellsSchema=api;})(typeof globalThis!=='undefined'?globalThis:this,function(){
"use strict";
// ---- SHA-256 (synchronous, so IDs can be made anywhere) ----
const K=[0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
function utf8(str){
 const s=unescape(encodeURIComponent(String(str==null?'':str))),out=new Uint8Array(s.length);
 for(let i=0;i<s.length;i++)out[i]=s.charCodeAt(i);return out;
}
function sha256Hex(input){
 const data=typeof input==='string'?utf8(input):input,len=data.length;
 const padded=new Uint8Array(((len+9+63)>>6)<<6);padded.set(data);padded[len]=0x80;
 const bits=len*8,view=new DataView(padded.buffer);
 view.setUint32(padded.length-8,Math.floor(bits/0x100000000));view.setUint32(padded.length-4,bits>>>0);
 const h=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19],w=new Uint32Array(64);
 const rotr=(x,n)=>(x>>>n)|(x<<(32-n));
 for(let off=0;off<padded.length;off+=64){
  for(let i=0;i<16;i++)w[i]=view.getUint32(off+i*4);
  for(let i=16;i<64;i++){const s0=rotr(w[i-15],7)^rotr(w[i-15],18)^(w[i-15]>>>3),s1=rotr(w[i-2],17)^rotr(w[i-2],19)^(w[i-2]>>>10);w[i]=(w[i-16]+s0+w[i-7]+s1)>>>0;}
  let [a,b,c,d,e,f,g,hh]=h;
  for(let i=0;i<64;i++){
   const S1=rotr(e,6)^rotr(e,11)^rotr(e,25),ch=(e&f)^(~e&g),t1=(hh+S1+ch+K[i]+w[i])>>>0;
   const S0=rotr(a,2)^rotr(a,13)^rotr(a,22),maj=(a&b)^(a&c)^(b&c),t2=(S0+maj)>>>0;
   hh=g;g=f;f=e;e=(d+t1)>>>0;d=c;c=b;b=a;a=(t1+t2)>>>0;
  }
  h[0]=(h[0]+a)>>>0;h[1]=(h[1]+b)>>>0;h[2]=(h[2]+c)>>>0;h[3]=(h[3]+d)>>>0;h[4]=(h[4]+e)>>>0;h[5]=(h[5]+f)>>>0;h[6]=(h[6]+g)>>>0;h[7]=(h[7]+hh)>>>0;
 }
 return h.map(x=>x.toString(16).padStart(8,'0')).join('');
}
// A stable ID: a short prefix plus 16 hex characters of the hash of its parts. Parts are joined with a separator that cannot occur in the text.
const stableId=(prefix,...parts)=>prefix+'_'+sha256Hex(parts.map(p=>String(p==null?'':p)).join('\u001f')).slice(0,16);
const clean=s=>String(s==null?'':s).replace(/\s+/g,' ').trim();

// ---- records ----
// SourceDocument(id, sha256, mime, classification, origin, retention). Retention is a policy label, never an automatic deletion.
function sourceDocument(o){
 const sha=sha256Hex(o.content);
 return {id:'src_'+sha.slice(0,16),sha256:sha,name:clean(o.name),mime:o.mime||'text/plain',classification:o.classification||'synthetic-training',origin:o.origin||'manual-import',retention:{policy:(o.retention&&o.retention.policy)||'unspecified',reviewAfterDays:(o.retention&&o.retention.reviewAfterDays)||null},bytes:utf8(o.content).length};
}
// WatchEntry(id, source_id, watch_profile, time, asset_id, narrative). The asset ID depends only on the equipment name, so it matches across logs.
function watchEntry(source,entry,watchProfile){
 const equipment=clean(entry.equipment).toLowerCase();
 return {id:stableId('ent',source.sha256,entry.line),sourceId:source.id,watchProfile:watchProfile||null,line:entry.line,time:entry.time||null,assetId:equipment?stableId('ast',equipment):null,narrative:entry.text};
}
// Finding(id, event_ids, rule, confidence, review_status). Confidence is "heuristic": these are prompts to check, not conclusions.
function finding(source,f){
 return {id:stableId('fnd',source.sha256,f.type,(f.lines||[]).join(',')),sourceId:source.id,rule:f.type,lines:(f.lines||[]).slice(),detail:f.detail,confidence:'heuristic',reviewStatus:'unreviewed'};
}
// Everything for one imported log: {source, entries, findings}. log is {content,name,watch,entries,analysis}.
function fromLog(log,opts){
 const source=sourceDocument(Object.assign({content:log.content,name:log.name},opts||{}));
 return {source,entries:(log.entries||[]).map(e=>watchEntry(source,e,log.watch)),findings:((log.analysis&&log.analysis.findings)||[]).map(f=>finding(source,f))};
}

// ---- lesson lifecycle ----
// draft -> in-review -> approved -> superseded | expired ; in-review -> rejected -> draft ; in-review -> draft (returned)
const TRANSITIONS={
 submit:{from:['draft'],to:'in-review'},
 return:{from:['in-review'],to:'draft'},
 approve:{from:['in-review'],to:'approved'},
 reject:{from:['in-review'],to:'rejected'},
 reopen:{from:['rejected'],to:'draft'},
 supersede:{from:['approved'],to:'superseded'},
 expire:{from:['approved'],to:'expired'}
};
function newLesson(o){
 const at=o.at||new Date().toISOString();
 return {id:o.id||stableId('les',o.title,o.author,at),title:clean(o.title),body:String(o.body||''),eventIds:(o.eventIds||[]).slice(),status:'draft',author:clean(o.author),reviewers:[],supersedes:o.supersedes||null,supersededBy:null,expiry:o.expiry||null,history:[{at,from:null,to:'draft',by:clean(o.author),note:''}]};
}
// actor: the name of the person acting (typed, not verified). opts: {at, note, supersededBy}. Returns a new lesson or throws a plain message.
function transition(lesson,action,actor,opts){
 opts=opts||{};const t=TRANSITIONS[action],who=clean(actor),at=opts.at||new Date().toISOString();
 if(!t)throw Error('Unknown lesson action "'+action+'".');
 if(t.from.indexOf(lesson.status)<0)throw Error('The lesson is '+lesson.status+', so "'+action+'" is not allowed (it works on a lesson that is '+t.from.join(' or ')+').');
 if(!who)throw Error('The person acting must be named.');
 if((action==='approve'||action==='reject')&&who.toLowerCase()===lesson.author.toLowerCase())throw Error('The author cannot '+action+' their own lesson; a second person must.');
 if(action==='reject'&&!clean(opts.note))throw Error('A rejection needs a reason.');
 if(action==='supersede'&&!opts.supersededBy)throw Error('Name the lesson that supersedes this one.');
 if(action==='expire'&&lesson.expiry&&new Date(at)<new Date(lesson.expiry))throw Error('This lesson has not reached its expiry date yet.');
 const next=Object.assign({},lesson,{status:t.to,eventIds:lesson.eventIds.slice(),reviewers:lesson.reviewers.slice(),history:lesson.history.slice()});
 if(action==='approve'||action==='reject')next.reviewers.push({name:who,at,decision:action==='approve'?'approved':'rejected',note:clean(opts.note)});
 if(action==='supersede')next.supersededBy=opts.supersededBy;
 next.history.push({at,from:lesson.status,to:t.to,by:who,note:clean(opts.note)});
 return next;
}
const isExpired=(lesson,now)=>!!lesson.expiry&&lesson.status==='approved'&&new Date(now||Date.now())>=new Date(lesson.expiry);
return {sha256Hex,stableId,sourceDocument,watchEntry,finding,fromLog,TRANSITIONS,newLesson,transition,isExpired};
});
