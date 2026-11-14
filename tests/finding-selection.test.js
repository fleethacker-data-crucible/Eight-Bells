'use strict';
// The quality list must show which finding a review note will attach to, and keep keyboard focus
// when that list is redrawn (issue 29). Synthetic logs only. A small DOM stands in for the browser;
// it implements the document calls web/app.js makes on this path, and nothing else.
const assert=require('assert');
const fs=require('fs');
const path=require('path');
const vm=require('vm');
const E=require('../web/engine.js');

function logFrom(id,name,text){
 const parsed=E.parse(text,'text');
 return {id,name,watch:'Engineering',format:'text',imported:'2026-11-14T12:00:00Z',content:text,entries:parsed.entries,analysis:E.analyze(parsed.entries)};
}
const logA=logFrom('log-a','Pump <B> & watch',['0800 Pump B abnormal vibration observed','0830 Pump B abnormal vibration observed','0900 Pump B abnormal vibration observed','0700 Supervisor notified after the earlier entry'].join('\n'));
const logB=logFrom('log-b','Second watch','0800 Gate 2 abnormal alarm observed');
assert(logA.analysis.findings.length>=2,'The fixture log needs two findings so one can be selected and the other not');
let state={logs:[logA,logB],lessons:[],reviews:[],audit:[]};

const ids=Object.create(null);
const document={listeners:{},activeElement:null,createElement:tag=>make(tag,{}),addEventListener(type,fn){(this.listeners[type]||(this.listeners[type]=[])).push(fn);}};
function decode(s){return String(s).replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&amp;/g,'&');}
function parseAttrs(s){
 const attrs={};const re=/([^\s=\/]+)(?:\s*=\s*"([^"]*)")?/g;let m;
 while((m=re.exec(s)))attrs[m[1].toLowerCase()]=m[2]===undefined?'':decode(m[2]);
 return attrs;
}
function unregister(el){
 if(el.id&&ids[el.id]===el)delete ids[el.id];
 for(const c of el.children)unregister(c);
}
function parseInto(parent,html){
 const re=/<!--[\s\S]*?-->|<\/([a-zA-Z0-9]+)>|<([a-zA-Z0-9]+)([^>]*)>|([^<]+)/g;
 const stack=[parent];let m;
 while((m=re.exec(html))){
  if(m[0].startsWith('<!--'))continue;
  if(m[1]){if(stack.length>1)stack.pop();continue;}
  if(m[2]){
   const el=make(m[2],parseAttrs(m[3]||''));
   const cur=stack[stack.length-1];
   cur.children.push(el);el.parentElement=cur;
   const selfClose=/\/\s*$/.test(m[3]||'')||['img','br','input','meta','link'].includes(m[2].toLowerCase());
   if(!selfClose)stack.push(el);
   continue;
  }
  if(m[4]){const cur=stack[stack.length-1];cur._text=(cur._text||'')+decode(m[4]);}
 }
}
function matchCompound(el,compound){
 const parts=compound.match(/(#[\w-]+|\.[\w-]+|\[[^\]]+\]|[a-zA-Z][\w-]*)/g)||[];
 if(!parts.length)return false;
 return parts.every(part=>{
  if(part[0]==='#')return el.id===part.slice(1);
  if(part[0]==='.')return el.classList.contains(part.slice(1));
  if(part[0]==='['){
   const m=part.match(/^\[([^\]=~|^$*]+)(?:([~|^$*]?=)"([^"]*)")?\]$/);
   if(!m)return false;
   if(m[2]===undefined)return el.hasAttribute(m[1]);
   return m[2]==='='&&el.getAttribute(m[1])===m[3];
  }
  return el.tagName===part.toUpperCase();
 });
}
function collect(el,compound,out){
 for(const c of el.children){if(matchCompound(c,compound))out.push(c);collect(c,compound,out);}
}
function queryAll(root,selector){
 const out=[];
 for(const sel of selector.split(',').map(s=>s.trim()).filter(Boolean)){
  let nodes=root===document?[body]:[root];
  for(const compound of sel.split(/\s+/)){
   const next=[];
   for(const n of nodes)collect(n,compound,next);
   nodes=next;
  }
  for(const n of nodes)if(!out.includes(n))out.push(n);
 }
 return out;
}
function make(tag,attrs){
 const el={tagName:String(tag).toUpperCase(),id:'',children:[],parentElement:null,attrs:new Map(),classSet:new Set(),_text:'',_html:null,value:'',hidden:false,disabled:false,checked:false,files:[],src:'',listeners:{}};
 el.classList={
  contains:t=>el.classSet.has(t),
  add:t=>{el.classSet.add(t);},
  remove:t=>{el.classSet.delete(t);},
  toggle:(t,force)=>{const on=force===undefined?!el.classSet.has(t):!!force;if(on)el.classSet.add(t);else el.classSet.delete(t);return on;}
 };
 el.setAttribute=(name,value)=>{name=String(name).toLowerCase();el.attrs.set(name,String(value));if(name==='class')el.classSet=new Set(String(value).split(/\s+/).filter(Boolean));if(name==='id'){if(el.id&&ids[el.id]===el)delete ids[el.id];el.id=String(value);ids[el.id]=el;}};
 el.getAttribute=name=>el.attrs.has(String(name).toLowerCase())?el.attrs.get(String(name).toLowerCase()):null;
 el.hasAttribute=name=>el.attrs.has(String(name).toLowerCase());
 el.removeAttribute=name=>{name=String(name).toLowerCase();el.attrs.delete(name);if(name==='class')el.classSet.clear();if(name==='id'&&ids[el.id]===el){delete ids[el.id];el.id='';}};
 el.addEventListener=(type,fn)=>{(el.listeners[type]||(el.listeners[type]=[])).push(fn);};
 el.focus=()=>{document.activeElement=el;};
 el.closest=sel=>{let n=el;while(n){if(queryAll(document,sel).includes(n))return n;n=n.parentElement;}return null;};
 el.querySelector=sel=>queryAll(el,sel)[0]||null;
 el.querySelectorAll=sel=>queryAll(el,sel);
 Object.defineProperty(el,'dataset',{get(){const o={};for(const [k,v] of el.attrs)if(k.startsWith('data-'))o[k.slice(5).replace(/-([a-z])/g,(_,c)=>c.toUpperCase())]=v;return o;}});
 Object.defineProperty(el,'textContent',{
  get(){return (el._text||'')+el.children.map(c=>c.textContent).join('');},
  set(v){for(const c of el.children)unregister(c);el.children=[];el._text=String(v);el._html=null;}
 });
 Object.defineProperty(el,'innerHTML',{
  get(){return el._html==null?'':el._html;},
  set(v){for(const c of el.children)unregister(c);el.children=[];el._text='';el._html=String(v);parseInto(el,el._html);}
 });
 for(const [k,v] of Object.entries(attrs||{}))el.setAttribute(k,v);
 return el;
}
const body=make('body',{});
document.body=body;document.activeElement=body;
document.getElementById=id=>{
 if(!ids[id]){const el=make('div',{id});body.children.push(el);el.parentElement=body;}
 return ids[id];
};
document.querySelector=sel=>queryAll(document,sel)[0]||null;
document.querySelectorAll=sel=>queryAll(document,sel);
const overview=make('section',{id:'overview',class:'view'});
const twocol=make('div',{class:'twocol'});
overview.children.push(twocol);twocol.parentElement=overview;
body.children.push(overview);overview.parentElement=body;

global.window=global;
global.document=document;
global.location={hash:'#token=synthetic-token'};
global.confirm=()=>false;
global.fetch=async(url,opts)=>{
 if(url==='/api/review'&&opts&&opts.method==='POST'){
  const body=JSON.parse(opts.body);
  state={...state,reviews:state.reviews.concat([{logId:body.logId,findingId:body.findingId,disposition:body.disposition,note:body.note,at:'2026-11-14T12:30:00Z'}])};
  return {ok:true,json:async()=>({ok:true})};
 }
 if(url==='/api/state')return {ok:true,json:async()=>state};
 return {ok:true,json:async()=>({})};
};
global.EightBellsEngine=E;
global.EightBellsSourceLinks=require('../web/sourcelinks.js');
global.EightBellsLifecycle={startHeartbeat(){return function(){};}};
vm.runInThisContext(fs.readFileSync(path.join(__dirname,'..','web','app.js'),'utf8'),{filename:'web/app.js'});

async function flush(){for(let i=0;i<8;i++)await new Promise(r=>setImmediate(r));}
async function click(el){
 el.focus();
 const ev={target:el};
 for(const fn of el.listeners.click||[])await fn(ev);
 for(const fn of document.listeners.click||[])await fn(ev);
}
function buttons(){return [...document.getElementById('qualityFindings').querySelectorAll('[data-finding]')];}
function pressed(){return buttons().filter(b=>b.getAttribute('aria-pressed')==='true');}

(async()=>{
 await flush();
 const findings=document.getElementById('qualityFindings');
 if(!buttons().length){
  console.error('notice:',document.getElementById('notice').textContent);
  console.error('qualityLog:',JSON.stringify(document.getElementById('qualityLog').value));
  console.error('findings:',findings.innerHTML.slice(0,500));
 }
 assert.strictEqual(buttons().length,logA.analysis.findings.length,'Every finding on the selected log is a button');
 assert.strictEqual(pressed().length,0,'Before a choice, no finding is pressed');
 assert.ok(buttons().every(b=>b.getAttribute('aria-pressed')==='false'&&!b.classList.contains('is-selected')),'Unselected rows expose aria-pressed false and no selected class');

 const target=buttons().find(b=>b.dataset.finding==='f2');
 assert.ok(target,'The chronology finding is in the list');
 target.focus();
 await click(target);
 const now=document.activeElement;
 assert.strictEqual(now.dataset.finding,'f2','Keyboard focus stays on the finding that was activated');
 assert.notStrictEqual(now,target,'Focus is on the redrawn button, not the detached one');
 assert.strictEqual(now.getAttribute('aria-pressed'),'true');
 assert.ok(now.classList.contains('is-selected'));
 assert.strictEqual(pressed().length,1,'Only the finding under review is pressed');
 assert.ok(buttons().filter(b=>b.dataset.finding!=='f2').every(b=>b.getAttribute('aria-pressed')==='false'&&!b.classList.contains('is-selected')));
 const panel=document.getElementById('selectedFinding');
 assert.ok(panel.innerHTML.includes('Pump &lt;B&gt; &amp; watch'),'The review panel names the source log, escaped');
 assert.ok(panel.textContent.includes('Review note attaches to Pump <B> & watch'),'The reviewer can read which log the note attaches to');
 assert.ok(panel.textContent.includes('source lines 3, 4'),'The review panel repeats the finding line numbers');
 assert.ok(!panel.innerHTML.includes('<B>'),'A log name cannot inject markup');

 const kept=document.activeElement;
 await document.getElementById('reloadBtn').listeners.click[0]();
 await flush();
 assert.strictEqual(document.activeElement.dataset.finding,'f2','Redrawing the list puts focus back on the finding that had it');
 assert.notStrictEqual(document.activeElement,kept);
 assert.strictEqual(document.activeElement.getAttribute('aria-pressed'),'true','The same finding is still pressed after a redraw');

 document.getElementById('reviewNote').value='Checked source lines 3 and 4 against the synthetic log.';
 document.getElementById('disposition').value='acknowledged';
 const reviewBtn=document.getElementById('reviewBtn');
 await click(reviewBtn);
 await flush();
 assert.strictEqual(document.activeElement,reviewBtn,'Saving a review does not move focus off the review control');
 assert.strictEqual(pressed().length,1);
 assert.strictEqual(pressed()[0].dataset.finding,'f2','The saved note stays attached to the finding that was selected');
 assert.ok(document.getElementById('selectedFinding').textContent.includes('Pump <B> & watch'));
 assert.ok(document.getElementById('reviewHistory').textContent.includes('Checked source lines 3 and 4'),'The saved note shows on that finding');
 assert.ok(pressed()[0].textContent.includes('1 reviews'));

 document.getElementById('qualityLog').value='log-b';
 document.getElementById('qualityLog').listeners.change[0]();
 assert.strictEqual(pressed().length,0,'Changing logs clears the pressed finding');
 assert.strictEqual(document.getElementById('selectedFinding').textContent,'Select a quality finding to inspect evidence.');

 const css=fs.readFileSync(path.join(__dirname,'..','web','styles.css'),'utf8');
 assert(/button\.row-item\.flag\.is-selected,\s*button\.row-item\.flag\[aria-pressed='true'\]\s*\{\s*border-color:\s*var\(--fl-accent\);\s*background:\s*var\(--fl-muted\);/.test(css),'The selected row reuses the accent and muted tokens');
 const html=fs.readFileSync(path.join(__dirname,'..','web','index.html'),'utf8');
 assert(/id="selectedFinding"[^>]*aria-live="polite"/.test(html),'The review panel announces the finding a note will attach to');
 console.log('PASS: selected finding stays marked (aria-pressed, accent row) and keeps focus; the panel repeats the log and source lines');
})().catch(e=>{console.error(e);process.exit(1);});
