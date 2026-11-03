/* Eight Bells PDF text-layer reader. Reads the text that a digital PDF already carries; it is NOT OCR, so a scanned page
   (an image) gives no text and says so. Pure script, no install: FlateDecode streams are inflated with the platform
   (zlib in Node, DecompressionStream in the browser). Supported: classic objects, page tree order, content stream arrays,
   Tj, TJ, ', ", Td, TD, T*, Tm text operators, WinAnsi-style single-byte fonts. Not supported (warned, never guessed):
   encryption, object streams, Type0 / ToUnicode fonts, LZW, ASCII85 and image filters. The result is unverified text the
   user must check against the document. No network. */
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.EightBellsPdf=api;})(typeof globalThis!=='undefined'?globalThis:this,function(){
"use strict";
const MAX_BYTES=5*1024*1024,MAX_INFLATED=8*1024*1024,MAX_PAGES=200;
// Bytes 0x80-0x9F in Windows-1252; everything else is Latin-1.
const CP1252={0x80:'€',0x82:'‚',0x83:'ƒ',0x84:'„',0x85:'…',0x86:'†',0x87:'‡',0x88:'ˆ',0x89:'‰',0x8A:'Š',0x8B:'‹',0x8C:'Œ',0x8E:'Ž',0x91:'‘',0x92:'’',0x93:'“',0x94:'”',0x95:'•',0x96:'–',0x97:'—',0x98:'˜',0x99:'™',0x9A:'š',0x9B:'›',0x9C:'œ',0x9E:'ž',0x9F:'Ÿ'};
const decodeByte=b=>CP1252[b]||String.fromCharCode(b);
const toLatin1=bytes=>{let s='';for(let i=0;i<bytes.length;i+=8192)s+=String.fromCharCode.apply(null,bytes.subarray(i,i+8192));return s;};
const fromLatin1=s=>{const u=new Uint8Array(s.length);for(let i=0;i<s.length;i++)u[i]=s.charCodeAt(i)&255;return u;};

// Default inflate: zlib in Node, DecompressionStream in the browser. Output is capped so a small file cannot expand without limit.
async function defaultInflate(bytes){
 if(typeof process!=='undefined'&&process.versions&&process.versions.node){
  const zlib=require('zlib');
  try{return new Uint8Array(zlib.inflateSync(bytes,{maxOutputLength:MAX_INFLATED}));}
  catch(e){throw Error(e.code==='ERR_BUFFER_TOO_LARGE'||/limit|exceed|larger than/i.test(e.message)?'A compressed stream expands past the safety limit.':'A compressed stream is damaged.');}
 }
 const ds=new DecompressionStream('deflate'),w=ds.writable.getWriter();
 w.write(bytes).catch(()=>{});w.close().catch(()=>{});
 const reader=ds.readable.getReader(),chunks=[];let total=0;
 try{for(;;){const {done,value}=await reader.read();if(done)break;total+=value.length;if(total>MAX_INFLATED){reader.cancel();throw Error('A compressed stream expands past the safety limit.');}chunks.push(value);}}
 catch(e){if(/safety limit/.test(e.message))throw e;throw Error('A compressed stream is damaged.');}
 const out=new Uint8Array(total);let o=0;for(const c of chunks){out.set(c,o);o+=c.length;}return out;
}

// ---- objects ----
function readObjects(src){
 const objs=new Map(),re=/(\d+)\s+(\d+)\s+obj\b/g;let m;
 while((m=re.exec(src))){
  const start=re.lastIndex,end=src.indexOf('endobj',start);if(end<0)break;
  const body=src.slice(start,end),si=body.search(/\bstream\r?\n|\bstream\r(?!\n)/);
  let dict=body,data=null;
  if(si>=0){
   dict=body.slice(0,si);
   const after=body.slice(si).replace(/^stream\r?\n|^stream\r/,'');
   const ei=after.lastIndexOf('endstream');data=ei>=0?after.slice(0,ei).replace(/\r?\n$/,''):after;
  }
  objs.set(Number(m[1]),{dict,data});
  re.lastIndex=end+6;
 }
 return objs;
}
const refOf=(text,key)=>{const m=new RegExp('/'+key+'\\s+(\\d+)\\s+\\d+\\s+R').exec(text);return m?Number(m[1]):null;};
const refsIn=text=>{const out=[],re=/(\d+)\s+\d+\s+R/g;let m;while((m=re.exec(text)))out.push(Number(m[1]));return out;};
function arrayAfter(text,key){const i=text.search(new RegExp('/'+key+'\\s*\\['));if(i<0)return null;const s=text.indexOf('[',i),e=text.indexOf(']',s);return e<0?null:text.slice(s+1,e);}

function pageOrder(objs,warnings){
 const catalogRef=(()=>{for(const [n,o] of objs)if(/\/Type\s*\/Catalog\b/.test(o.dict))return n;return null;})();
 const pages=[];
 const walk=(n,depth)=>{
  const o=objs.get(n);if(!o||depth>20)return;
  if(/\/Type\s*\/Pages\b/.test(o.dict)){const kids=arrayAfter(o.dict,'Kids');if(kids)for(const k of refsIn(kids))walk(k,depth+1);}
  else if(/\/Type\s*\/Page\b/.test(o.dict))pages.push(n);
 };
 if(catalogRef!=null){const root=refOf(objs.get(catalogRef).dict,'Pages');if(root!=null)walk(root,0);}
 if(!pages.length){for(const [n,o] of objs)if(/\/Type\s*\/Page\b/.test(o.dict)&&!/\/Type\s*\/Pages\b/.test(o.dict))pages.push(n);if(pages.length)warnings.push('The page tree was not found; pages are in file order.');}
 return pages.slice(0,MAX_PAGES);
}

async function streamBytes(obj,inflate,warnings,label){
 if(!obj||obj.data==null)return null;
 const filters=(obj.dict.match(/\/Filter\s*(\[[^\]]*\]|\/\w+)/)||[])[1]||'';
 const names=(filters.match(/\/\w+/g)||[]).map(s=>s.slice(1));
 let bytes=fromLatin1(obj.data);
 for(const f of names){
  if(f==='FlateDecode'||f==='Fl')bytes=await inflate(bytes);
  else{warnings.push(label+' uses the unsupported filter '+f+'; its text was skipped.');return null;}
 }
 return bytes;
}

// ---- content streams ----
function tokenize(s){
 const out=[];let i=0;const n=s.length;
 while(i<n){
  const c=s[i];
  if(/\s/.test(c)){i++;continue;}
  if(c==='%'){while(i<n&&s[i]!=='\n'&&s[i]!=='\r')i++;continue;}
  if(c==='('){
   let depth=1,j=i+1,str='';
   while(j<n&&depth>0){
    const d=s[j];
    if(d==='\\'){
     const e=s[j+1];j+=2;
     if(e==='n')str+='\n';else if(e==='r')str+='\r';else if(e==='t')str+='\t';else if(e==='b')str+='\b';else if(e==='f')str+='\f';
     else if(e==='\r'){if(s[j]==='\n')j++;}else if(e==='\n'){}
     else if(e>='0'&&e<='7'){let oct=e;while(oct.length<3&&s[j]>='0'&&s[j]<='7'){oct+=s[j++];}str+=String.fromCharCode(parseInt(oct,8)&255);}
     else str+=e;
    }else if(d==='('){depth++;str+=d;j++;}
    else if(d===')'){depth--;if(depth>0)str+=d;j++;}
    else{str+=d;j++;}
   }
   out.push({t:'s',v:str});i=j;continue;
  }
  if(c==='<'&&s[i+1]!=='<'){const e=s.indexOf('>',i);const hex=s.slice(i+1,e<0?n:e).replace(/\s+/g,'');let str='';for(let k=0;k<hex.length;k+=2)str+=String.fromCharCode(parseInt((hex.slice(k,k+2)+'0').slice(0,2),16));out.push({t:'s',v:str});i=e<0?n:e+1;continue;}
  if(c==='['||c===']'){out.push({t:c});i++;continue;}
  if(c==='<'||c==='>'){i+=s[i+1]===c?2:1;continue;}
  let j=i;while(j<n&&!/[\s()<>\[\]/%]/.test(s[j]))j++;
  if(c==='/'){j=i+1;while(j<n&&!/[\s()<>\[\]/%]/.test(s[j]))j++;out.push({t:'n',v:s.slice(i+1,j)});i=j;continue;}
  if(j===i){i++;continue;}
  const w=s.slice(i,j);out.push(/^[+-]?(\d+\.?\d*|\.\d+)$/.test(w)?{t:'#',v:parseFloat(w)}:{t:'o',v:w});i=j;
 }
 return out;
}
function textOf(content){
 const toks=tokenize(content),lines=[];let cur='',stack=[],arr=null,lastY=null;
 const flush=()=>{if(cur.trim())lines.push(cur);cur='';};
 const show=str=>{for(let k=0;k<str.length;k++)cur+=decodeByte(str.charCodeAt(k)&255);};
 for(const tk of toks){
  if(tk.t==='['){arr=[];continue;}
  if(tk.t===']'){stack.push({t:'a',v:arr||[]});arr=null;continue;}
  if(arr){arr.push(tk);continue;}
  if(tk.t!=='o'){stack.push(tk);continue;}
  const op=tk.v;
  if(op==='BT'){flush();lastY=null;}
  else if(op==='ET'){flush();}
  else if(op==='Tj'){const a=stack[stack.length-1];if(a&&a.t==='s')show(a.v);}
  else if(op==='TJ'){const a=stack[stack.length-1];if(a&&a.t==='a')for(const x of a.v){if(x.t==='s')show(x.v);else if(x.t==='#'&&x.v<-200&&cur&&!/\s$/.test(cur))cur+=' ';}}
  else if(op==="'"||op==='"'){flush();const a=stack[stack.length-1];if(a&&a.t==='s')show(a.v);}
  else if(op==='T*'){flush();}
  else if(op==='Td'||op==='TD'){const y=stack[stack.length-1];if(y&&y.t==='#'&&y.v!==0)flush();else if(cur&&!/\s$/.test(cur))cur+=' ';}
  else if(op==='Tm'){const y=stack[stack.length-1];if(y&&y.t==='#'){if(lastY!==null&&y.v!==lastY)flush();else if(cur&&!/\s$/.test(cur))cur+=' ';lastY=y.v;}}
  stack=[];
 }
 flush();return lines;
}

async function extractText(input,opts){
 opts=opts||{};const inflate=opts.inflate||defaultInflate,warnings=[];
 const bytes=input instanceof Uint8Array?input:new Uint8Array(input);
 if(bytes.length>MAX_BYTES)throw Error('The PDF is larger than '+(MAX_BYTES/1048576)+' MB.');
 const src=toLatin1(bytes);
 if(!/^%PDF-\d/.test(src.slice(0,16)))throw Error('This is not a PDF file.');
 if(/\/Encrypt\b/.test(src))throw Error('The PDF is encrypted; Eight Bells does not open encrypted PDFs.');
 const objs=readObjects(src);
 if(/\/Type\s*\/ObjStm\b/.test(src))warnings.push('The PDF uses object streams, which are not read; some pages may be missing.');
 if(/\/Subtype\s*\/Type0\b|\/Encoding\s*\/Identity-H|\/ToUnicode\b/.test(src))warnings.push('Some fonts use custom encodings (Type0 or ToUnicode); their text may be wrong or missing.');
 const order=pageOrder(objs,warnings);
 const pages=[];
 for(let p=0;p<order.length;p++){
  const page=objs.get(order[p]),cont=page.dict.match(/\/Contents\s*(\[[^\]]*\]|\d+\s+\d+\s+R)/);
  const refs=cont?refsIn(cont[1]):[];
  let text='';
  for(const r of refs){
   const bytesOut=await streamBytes(objs.get(r),inflate,warnings,'Page '+(p+1));
   if(bytesOut)text+=textOf(toLatin1(bytesOut)).join('\n')+'\n';
  }
  pages.push({page:p+1,text:text.replace(/\n+$/,'')});
 }
 if(!pages.length)warnings.push('No pages were found in this PDF.');
 else if(!pages.some(pg=>pg.text.trim()))warnings.push('No text layer was found. This looks like a scanned or image-only PDF. Eight Bells has no OCR; type or paste the text instead.');
 return {pageCount:pages.length,pages,text:pages.map(pg=>pg.text).filter(Boolean).join('\n\n'),warnings,verified:false};
}
return {extractText,textOf,tokenize,MAX_BYTES};
});
