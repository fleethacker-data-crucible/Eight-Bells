/* Eight Bells electronic-log adapters: JSON Lines, delimited tables (TSV, semicolon, pipe) and XML exports.
   Each adapter turns the file into the records the engine already understands and lets the engine build the entries, so
   timestamps, entities, issue and resolution flags behave exactly as for CSV and JSON. Source line numbers are kept so
   evidence links still point at the right line. XML is read by a small built-in reader: DTDs and entities are refused, so
   there is no entity expansion or external fetch. No network, no dependencies beyond engine.js. */
(function(root,factory){
 if(typeof module==='object'&&module.exports)module.exports=factory(require('./engine.js'));
 else root.EightBellsAdapters=factory(root.EightBellsEngine);
})(typeof globalThis!=='undefined'?globalThis:this,function(engine){
"use strict";
const FORMATS=[
 {id:'jsonl',label:'JSON Lines (one event per line)'},
 {id:'delimited',label:'Delimited table (tab, semicolon or pipe)'},
 {id:'xml',label:'XML e-log export'}
];
const DELIMS=['\t',';','|'];
const nonBlank=text=>String(text||'').split(/\r?\n/).map((s,i)=>({s,line:i+1})).filter(x=>x.s.trim());
function fixLines(entries,lines){entries.forEach((e,i)=>{if(lines[i]!=null)e.line=lines[i];});return entries;}

function parseJsonl(content){
 const rows=nonBlank(content),records=[],lines=[];
 for(const r of rows){
  let v;try{v=JSON.parse(r.s);}catch(e){throw Error('JSON Lines: line '+r.line+' is not valid JSON ('+e.message+')');}
  if(v===null||typeof v!=='object'||Array.isArray(v))throw Error('JSON Lines: line '+r.line+' must be one JSON object');
  records.push(v);lines.push(r.line);
 }
 const parsed=engine.parse(JSON.stringify(records),'json');
 return {format:'jsonl',entries:fixLines(parsed.entries,lines),warnings:parsed.warnings};
}

function splitDelimited(line,d){
 const out=[];let cell='',quote=false;
 for(let i=0;i<line.length;i++){
  const c=line[i];
  if(c==='"'){if(quote&&line[i+1]==='"'){cell+='"';i++;}else quote=!quote;}
  else if(c===d&&!quote){out.push(cell);cell='';}
  else cell+=c;
 }
 if(quote)throw Error('Delimited table: an unclosed quote');
 out.push(cell);return out;
}
function pickDelimiter(content){
 const rows=nonBlank(content).slice(0,20).map(r=>r.s);
 if(rows.length<2)return null;
 let best=null;
 for(const d of DELIMS){
  const counts=rows.map(r=>{try{return splitDelimited(r,d).length;}catch(e){return 0;}});
  if(counts[0]>1&&counts.every(c=>c===counts[0])&&(!best||counts[0]>best.cols))best={d,cols:counts[0]};
 }
 return best?best.d:null;
}
function parseDelimited(content){
 const d=pickDelimiter(content);
 if(!d)throw Error('Delimited table: no tab, semicolon or pipe separates the columns the same way on every line');
 const rows=nonBlank(content);
 const head=splitDelimited(rows[0].s,d).map(x=>x.trim());
 const records=[],lines=[];
 for(const r of rows.slice(1)){
  const cells=splitDelimited(r.s,d),obj={};
  head.forEach((h,i)=>{obj[h]=cells[i]==null?'':cells[i];});
  records.push(obj);lines.push(r.line);
 }
 // The engine's CSV reader gives the same field mapping as the .csv files already supported.
 const q=v=>/[",\r\n]/.test(v)?'"'+v.replace(/"/g,'""')+'"':v;
 const csv=[head.map(q).join(',')].concat(records.map(o=>head.map(h=>q(String(o[h]))).join(','))).join('\n');
 const parsed=engine.parse(csv,'csv');
 return {format:'delimited',entries:fixLines(parsed.entries,lines),warnings:parsed.warnings};
}

const XML_ENTITIES={amp:'&',lt:'<',gt:'>',quot:'"',apos:"'"};
function decode(s){
 return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi,(m,e)=>{
  if(e[0]==='#'){const n=e[1].toLowerCase()==='x'?parseInt(e.slice(2),16):parseInt(e.slice(1),10);return Number.isFinite(n)&&n>0&&n<0x110000?String.fromCodePoint(n):m;}
  return Object.prototype.hasOwnProperty.call(XML_ENTITIES,e)?XML_ENTITIES[e]:m;
 });
}
// Returns [{name,attrs,text,children,line}] for the elements under the root, using a tag scanner.
function readXml(content){
 const src=String(content||'').replace(/^﻿/,'');
 if(/<!DOCTYPE|<!ENTITY/i.test(src))throw Error('XML: DTDs and entities are not accepted');
 const lineAt=pos=>src.slice(0,pos).split('\n').length;
 const re=/<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<!\[CDATA\[([\s\S]*?)\]\]>|<(\/?)([A-Za-z_][\w:.-]*)((?:\s+[\w:.-]+\s*=\s*(?:"[^"]*"|'[^']*'))*)\s*(\/?)>|([^<]+)/g;
 const root={name:'#root',attrs:{},text:'',children:[],line:1},stack=[root];let m;
 while((m=re.exec(src))){
  if(m[1]!==undefined){stack[stack.length-1].text+=m[1];continue;}
  if(m[3]!==undefined){
   if(m[2]==='/'){if(stack.length<2||stack[stack.length-1].name!==m[3])throw Error('XML: mismatched closing tag </'+m[3]+'> on line '+lineAt(m.index));stack.pop();continue;}
   const attrs={};String(m[4]||'').replace(/([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g,(_,k,a,b)=>{attrs[k]=decode(a!==undefined?a:b);return '';});
   const el={name:m[3],attrs,text:'',children:[],line:lineAt(m.index)};
   stack[stack.length-1].children.push(el);
   if(m[5]!=='/')stack.push(el);
  }else if(m[6]!==undefined){stack[stack.length-1].text+=decode(m[6]);}
 }
 if(stack.length!==1)throw Error('XML: <'+stack[stack.length-1].name+'> was never closed');
 if(!root.children.length)throw Error('XML: no root element');
 return root.children[0];
}
const RECORD_NAMES=/^(entry|event|record|log|logentry|item|observation)$/i;
function findRecords(el){
 const hits=[];
 (function walk(n){for(const c of n.children){if(RECORD_NAMES.test(c.name))hits.push(c);else walk(c);}})(el);
 return hits;
}
function parseXml(content){
 const rootEl=readXml(content),recs=findRecords(rootEl);
 if(!recs.length)throw Error('XML: no <entry>, <event>, <record>, <log> or <item> elements were found');
 const records=[],lines=[];
 for(const r of recs){
  const o=Object.assign({},r.attrs);
  for(const c of r.children)o[c.name]=(c.text||'').trim();
  if(!r.children.length&&r.text.trim())o.text=r.text.trim();
  records.push(o);lines.push(r.line);
 }
 const parsed=engine.parse(JSON.stringify(records),'json');
 return {format:'xml',entries:fixLines(parsed.entries,lines),warnings:parsed.warnings};
}

// Which adapter fits this content, or null when the engine's own formats should handle it.
function detect(content){
 const text=String(content||'').replace(/^﻿/,'').trim();
 if(!text)return null;
 if(text[0]==='<')return 'xml';
 const rows=nonBlank(text);
 if(rows.length>=2&&rows.every(r=>/^\{.*\}\s*$/.test(r.s.trim())))return 'jsonl';
 if(pickDelimiter(text)&&/(time|date|equipment|asset|watch|entry|description|text)/i.test(rows[0].s))return 'delimited';
 return null;
}
function parse(content,format){
 const f=(format==='auto'||!format)?detect(content):format;
 if(f==='jsonl')return parseJsonl(content);
 if(f==='delimited')return parseDelimited(content);
 if(f==='xml')return parseXml(content);
 return engine.parse(content,format||'auto');
}
return {FORMATS,detect,parse};
});
