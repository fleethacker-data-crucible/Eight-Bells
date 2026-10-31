'use strict';
// Builds tiny synthetic PDFs for tests and for tools/make-sample-pdf.js. Classic objects only, no real document is read.
// pages: array of content-stream strings (or arrays of strings for a /Contents array).
// opts: compress (FlateDecode), treeOrder (indexes into pages, the order in the page tree), extraDict (added to the trailer),
//       fontDict (extra text inside the font dictionary), contentFilter (a filter name to write without encoding the data).
const zlib=require('zlib');
function buildPdf(pages,opts){
 opts=opts||{};
 const objs=[];                       // objs[i] is object number i+1, as a latin1 string
 const add=s=>{objs.push(s);return objs.length;};
 const catalog=add('');               // 1, filled in below
 const pagesObj=add('');              // 2, filled in below
 const font=add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding '+(opts.fontDict||'')+'>>');
 const pageNums=[];
 for(const content of pages){
  const parts=Array.isArray(content)?content:[content];
  const streamNums=parts.map(text=>{
   let data=text,filter='';
   if(opts.compress){data=zlib.deflateSync(Buffer.from(text,'latin1')).toString('latin1');filter=' /Filter /FlateDecode';}
   else if(opts.contentFilter)filter=' /Filter /'+opts.contentFilter;
   return add('<< /Length '+data.length+filter+' >>\nstream\n'+data+'\nendstream');
  });
  const contents=streamNums.length===1&&!Array.isArray(content)?streamNums[0]+' 0 R':'['+streamNums.map(n=>n+' 0 R').join(' ')+']';
  pageNums.push(add('<< /Type /Page /Parent '+pagesObj+' 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 '+font+' 0 R >> >> /Contents '+contents+' >>'));
 }
 const order=(opts.treeOrder||pageNums.map((_,i)=>i)).map(i=>pageNums[i]);
 objs[catalog-1]='<< /Type /Catalog /Pages '+pagesObj+' 0 R >>';
 objs[pagesObj-1]='<< /Type /Pages /Kids ['+order.map(n=>n+' 0 R').join(' ')+'] /Count '+order.length+' >>';
 let out='%PDF-1.4\n';const offsets=[];
 objs.forEach((body,i)=>{offsets.push(out.length);out+=(i+1)+' 0 obj\n'+body+'\nendobj\n';});
 const xref=out.length;
 out+='xref\n0 '+(objs.length+1)+'\n0000000000 65535 f \n'+offsets.map(o=>String(o).padStart(10,'0')+' 00000 n \n').join('');
 out+='trailer\n<< /Size '+(objs.length+1)+' /Root '+catalog+' 0 R '+(opts.extraDict||'')+'>>\nstartxref\n'+xref+'\n%%EOF\n';
 return new Uint8Array(Buffer.from(out,'latin1'));
}
const text=lines=>'BT /F1 11 Tf 72 720 Td 14 TL\n'+lines.map((l,i)=>(i?'T* ':'')+'('+l.replace(/[\\()]/g,'\\$&')+') Tj').join('\n')+'\nET';
module.exports={buildPdf,text};
