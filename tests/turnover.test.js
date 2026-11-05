'use strict';
// Exercise the real controller's DOM event handlers with synthetic logs and no service/provider.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const engine=require('../web/engine.js');
const html=fs.readFileSync(path.join(__dirname,'../web/index.html'),'utf8');
const script=fs.readFileSync(path.join(__dirname,'../web/app.js'),'utf8');
const settle=()=>new Promise(resolve=>setImmediate(resolve));
function log(id,name){const parsed=engine.parse('0800 Pump '+id+' abnormal vibration','text');return {id,name,watch:'Engineering',format:'text',imported:'2026-10-31T08:00:00Z',content:name,entries:parsed.entries,analysis:engine.analyze(parsed.entries)};}
async function app(){
 const elements=new Map(),events={},copied=[],downloads=[],aiRequests=[];
 let state={logs:[log('a','Synthetic log A'),log('b','Synthetic log B')],lessons:[],reviews:[],audit:[]};
 const blobs=new Map();let blobId=0;
 function element(id){
  if(!elements.has(id)){
   const tag=html.match(new RegExp('<[^>]*\\bid="'+id+'"[^>]*>'))?.[0]||'';
   const listeners={};
   elements.set(id,{id,value:'',textContent:'',innerHTML:'',checked:false,disabled:/\bdisabled\b/.test(tag),hidden:false,
    classList:{toggle(){},add(){},remove(){}},addEventListener:(name,handler)=>{listeners[name]=handler;},
    dispatch:(name)=>listeners[name]?.(),remove(){},click(){if(this.href)downloads.push(blobs.get(this.href));}});
  }
  return elements.get(id);
 }
 const document={getElementById:element,querySelectorAll:()=>[],querySelector:element,addEventListener:(name,fn)=>{events[name]=fn;},
  createElement:()=>element('download-'+blobId),body:{appendChild(){}}};
 const fetch=async route=>{
  if(route==='/api/state')return {ok:true,json:async()=>JSON.parse(JSON.stringify(state))};
  if(route==='/api/ai/run')return new Promise(resolve=>aiRequests.push(text=>resolve({ok:true,json:async()=>({model:'synthetic-model',text})})));
  throw Error('Unexpected route '+route);
 };
 vm.runInNewContext(script,{window:{EightBellsEngine:engine,EightBellsSourceLinks:require('../web/sourcelinks.js'),EightBellsLifecycle:{startHeartbeat:()=>()=>{}}},document,location:{hash:'#token=synthetic-ui-test'},
  navigator:{clipboard:{writeText:async text=>copied.push(text)}},fetch,Blob,URL:{createObjectURL:blob=>{const id='blob:'+ ++blobId;blobs.set(id,blob);return id;},revokeObjectURL(){}},setTimeout:()=>0,console});
 await settle();
 return {element,copied,downloads,aiRequests,state:()=>state,
  select:async id=>{element('turnLog').value=id;await element('turnLog').dispatch('change');},
  source:async id=>{events.click({target:{closest:selector=>selector==='[data-source]'?{dataset:{source:id}}:null}});await settle();},
  refresh:async()=>{await element('reloadBtn').dispatch('click');await settle();}};
}
(async()=>{
 const ui=await app(),el=ui.element;
 assert.equal(el('copyTurn').disabled,true,'Copy must start disabled before any draft exists');
 assert.equal(el('saveTurn').disabled,true,'Save must start disabled before any draft exists');
 // Direct invocation still has to guard against exporting placeholder/stale text.
 await el('copyTurn').dispatch('click');await el('saveTurn').dispatch('click');
 assert.equal(ui.copied.length,0);assert.equal(ui.downloads.length,0);
 await el('generateTurn').dispatch('click');
 assert.equal(el('copyTurn').disabled,false);
 assert.match(el('turnStatus').textContent,/Synthetic log A/);
 await el('copyTurn').dispatch('click');assert.match(ui.copied[0],/Synthetic log A/);
 await ui.select('b');
 assert.equal(el('copyTurn').disabled,true);assert.equal(el('saveTurn').disabled,true);
 assert.doesNotMatch(el('turnText').textContent,/Synthetic log A/);
 await el('copyTurn').dispatch('click');await el('saveTurn').dispatch('click');
 assert.equal(ui.copied.length,1);assert.equal(ui.downloads.length,0);
 await el('generateTurn').dispatch('click');await el('saveTurn').dispatch('click');
 assert.match(await ui.downloads[0].text(),/Synthetic log B/);
 assert.match(await ui.downloads[0].text(),/Generated:/);
 // Programmatic selection from source-library navigation must invalidate output too.
 await ui.source('a');assert.equal(el('copyTurn').disabled,true);
 await el('generateTurn').dispatch('click');
 await ui.refresh();assert.equal(el('copyTurn').disabled,false,'An unchanged state refresh preserves the matching draft');
 ui.state().logs[0].content='Updated synthetic source';await ui.refresh();
 assert.equal(el('copyTurn').disabled,true,'Changing source content under the same id invalidates the draft');
 // Late AI output for A must not overwrite B (or a newer B request).
 el('aiConsent').checked=true;const first=el('runAi').dispatch('click');
 await ui.select('b');assert.equal(el('aiConsent').checked,false);
 el('aiConsent').checked=true;const second=el('runAi').dispatch('click');
 ui.aiRequests[1]('Draft B');await second;
 assert.match(el('aiText').textContent,/Draft B/);assert.match(el('aiText').textContent,/Synthetic log B/);
 ui.aiRequests[0]('Late draft A');await first;
 assert.match(el('aiText').textContent,/Draft B/);assert.doesNotMatch(el('aiText').textContent,/Late draft A/);
 await ui.select('a');assert.doesNotMatch(el('aiText').textContent,/Draft B/);
 console.log('PASS: turnover source binding, guarded exports, refresh invalidation and late AI response regression checks');
})().catch(error=>{console.error(error);process.exitCode=1;});
