'use strict';
const assert=require('assert');
const fs=require('fs');
const path=require('path');
const zlib=require('zlib');
const E=require('../web/engine.js');
const P=require('../web/pdf.js');
const {buildPdf,text}=require('./helpers/pdf-builder.js');
const BT=body=>'BT /F1 11 Tf '+body+' ET';

(async()=>{
 const ex=(pages,opts)=>P.extractText(buildPdf(pages,opts));
 const rejects=async(promise,re,msg)=>{try{await promise;}catch(e){assert(re.test(e.message),msg+' (got: '+e.message+')');return;}assert.fail(msg+' (nothing was thrown)');};

 // ---- plain text lines ----
 let r=await ex([text(['0800 Watch assumed','0830 Pump B abnormal vibration'])]);
 assert.strictEqual(r.pageCount,1);assert.strictEqual(r.text,'0800 Watch assumed\n0830 Pump B abnormal vibration');
 assert.strictEqual(r.verified,false,'Extracted text is always unverified');assert.deepStrictEqual(r.warnings,[]);
 // ---- operators ----
 r=await ex([BT('72 720 Td [(Pu) -20 (mp) -300 (B)] TJ')]);
 assert.strictEqual(r.text,'Pump B','Kerning joins letters and a wide gap becomes a space');
 r=await ex([BT('72 720 Td (Line \\(one\\) \\\\ \\101) Tj')]);
 assert.strictEqual(r.text,'Line (one) \\ A','Escapes and octal codes');
 r=await ex([BT('72 720 Td <48656C6C6F> Tj')]);assert.strictEqual(r.text,'Hello','Hex strings');
 r=await ex([BT('72 720 Td 14 TL (first) Tj T* (second) Tj (third) \'')]);
 assert.strictEqual(r.text,'first\nsecond\nthird','T* and the quote operator start new lines');
 r=await ex([BT('1 0 0 1 72 700 Tm (a) Tj 1 0 0 1 72 680 Tm (b) Tj 1 0 0 1 120 680 Tm (c) Tj')]);
 assert.strictEqual(r.text,'a\nb c','Tm on a new y starts a line; on the same y it continues');
 r=await ex([BT('72 720 Td (\\223quoted\\224 \\226 ok) Tj')]);
 assert.strictEqual(r.text,'“quoted” – ok','Windows-1252 punctuation');
 r=await ex([BT('72 720 Td (ignored % not a comment) Tj')]);assert.strictEqual(r.text,'ignored % not a comment');
 // ---- compression, pages, contents arrays ----
 r=await ex([text(['Compressed line'])],{compress:true});assert.strictEqual(r.text,'Compressed line');
 r=await ex([text(['PAGE ONE']),text(['PAGE TWO'])],{treeOrder:[1,0]});
 assert.deepStrictEqual(r.pages.map(p=>p.text),['PAGE TWO','PAGE ONE'],'Page order follows the page tree, not the file');
 assert.strictEqual(r.text,'PAGE TWO\n\nPAGE ONE');
 r=await ex([[text(['part one']),text(['part two'])]]);assert.strictEqual(r.text,'part one\npart two','A Contents array is read in order');
 let calls=0;
 r=await P.extractText(buildPdf([text(['Custom inflate'])],{compress:true}),{inflate:async b=>{calls++;return new Uint8Array(zlib.inflateSync(b));}});
 assert.strictEqual(calls,1);assert.strictEqual(r.text,'Custom inflate','The browser path can pass its own inflate');
 // ---- no text, unsupported, refused ----
 r=await ex(['q 100 0 0 100 0 0 cm /Im1 Do Q']);
 assert.strictEqual(r.text,'');assert(r.warnings.some(w=>/No text layer.*no OCR/s.test(w)||/No text layer/.test(w)&&/OCR/.test(w)),'A scanned page says there is no OCR');
 r=await ex([text(['hidden'])],{contentFilter:'ASCII85Decode'});
 assert.strictEqual(r.text,'');assert(r.warnings.some(w=>/unsupported filter ASCII85Decode/.test(w)),'An unsupported filter is reported, not guessed');
 r=await ex([text(['x'])],{fontDict:'/Subtype /Type0 '});assert(r.warnings.some(w=>/custom encodings/.test(w)));
 await rejects(P.extractText(buildPdf([text(['x'])],{extraDict:'/Encrypt 9 0 R '})),/encrypted/,'Encrypted PDFs are refused');
 await rejects(P.extractText(new TextEncoder().encode('Just some text, not a PDF')),/not a PDF/,'Other files are refused');
 await rejects(P.extractText(new Uint8Array(P.MAX_BYTES+1).fill(37)),/larger than/,'Oversized files are refused');
 await rejects(ex([text(['x'])].map(()=> 'garbage'),{contentFilter:'FlateDecode'}),/damaged/,'A damaged stream is reported');
 const bomb=zlib.deflateSync(Buffer.alloc(9*1024*1024));
 assert(bomb.length<64*1024,'The test bomb is small on disk');
 await rejects(P.extractText(new Uint8Array(Buffer.concat([Buffer.from('%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>\nendobj\n4 0 obj\n<< /Length '+bomb.length+' /Filter /FlateDecode >>\nstream\n','latin1'),bomb,Buffer.from('\nendstream\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF','latin1')]))),/safety limit/,'A stream that expands too far is stopped');
 r=await P.extractText(new Uint8Array(Buffer.from('%PDF-1.4\n%%EOF','latin1')));
 assert(r.warnings.some(w=>/No pages/.test(w)),'A PDF with no pages says so');

 // ---- the synthetic sample goes through the normal import path ----
 const sample=new Uint8Array(fs.readFileSync(path.join(__dirname,'..','samples','synthetic_watch.pdf')));
 r=await P.extractText(sample);
 assert.strictEqual(r.pageCount,1);assert.deepStrictEqual(r.warnings,[]);
 assert(r.text.includes('0830 Pump B abnormal vibration observed')&&r.text.startsWith('SYNTHETIC TRAINING LOG'));
 const parsed=E.parse(r.text,'text');
 assert.strictEqual(parsed.entries.filter(e=>e.time).length,4,'Four timed entries are recognised');
 const analysis=E.analyze(parsed.entries);
 assert.strictEqual(analysis.open.length,0,'The vibration is cleared at 09:15');
 console.log('PASS: PDF text layer (operators, escapes, kerning, compression, page order, Contents arrays, warnings, refusals, size and expansion limits, sample)');
})().catch(err=>{console.error(err);process.exit(1);});
