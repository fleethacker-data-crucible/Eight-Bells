'use strict';
const assert=require('assert');
const H=require('../web/halyard-export.js');
// Rules below are taken from Halyard docs/HANDOFF.md and src/Halyard.Core/Intelligence/HandoffImport.cs:
// format "fleet-handoff", version 1, source.app lower case, items with ref and title, title up to 200 characters,
// body up to 20 000, at most 500 items, labels as strings.
const lessons=[
 {id:'a1b2c3d4e5f6',title:'Pump B vibration repeats across watches',body:'Recurring condition: Pump B. Evidence: log 1 lines 2,3.',source:'log-1',status:'reviewed'},
 {id:'ffeeddccbbaa',title:'Draft only lesson',body:'Not reviewed yet.',source:'',status:'draft'},
 {id:'0011223344',title:'  ',body:'No title',status:'reviewed'},
 {id:'a1b2c3d4e5f6',title:'Same id twice',body:'Duplicate.',status:'reviewed'},
 {id:'',title:'No id',body:'x',status:'reviewed'},
 {id:'bbccddeeff00',title:'y'.repeat(300),body:'z'.repeat(30000),source:'log-9',status:'reviewed'}
];
const out=H.toHandoff(lessons,{now:'2026-11-04T12:00:00.000Z'});
assert.strictEqual(out.format,'fleet-handoff');assert.strictEqual(out.version,1);
assert.strictEqual(out.source.app,'eight-bells');assert(/^[a-z][a-z0-9-]*$/.test(out.source.app),'source.app is lower case');
assert.strictEqual(out.source.exportedAt,'2026-11-04T12:00:00.000Z');
assert.strictEqual(out.items.length,2,'Only reviewed lessons with a title, an id and a new ref are exported');
assert.deepStrictEqual(out.skipped.map(s=>s.reason).sort(),['duplicate id','no id','no title','not reviewed']);
const a=out.items[0];
assert.strictEqual(a.ref,'a1b2c3d4e5f6','The lesson id is the stable ref');
assert.strictEqual(a.kind,'story');assert(Array.isArray(a.labels)&&a.labels.every(l=>typeof l==='string'));
assert(a.body.includes('Recurring condition: Pump B.')&&a.body.includes('source log log-1'),'The reviewed text and its source log travel with the item');
assert(!('url' in a),'No url: it must be http(s) and a log id is not');
const b=out.items[1];
assert.strictEqual(b.title.length,200,'Title is cut to 200 characters');
assert.strictEqual(b.body.length,20000,'Body is cut to 20 000 characters');
assert.strictEqual(H.toHandoff(lessons,{includeDrafts:true}).items.length,3,'includeDrafts adds the draft');
assert.deepStrictEqual(H.toHandoff([]).items,[]);assert.deepStrictEqual(H.toHandoff(null).items,[]);
const many=[];for(let i=0;i<510;i++)many.push({id:'id'+i,title:'t'+i,body:'b',status:'reviewed'});
const big=H.toHandoff(many);assert.strictEqual(big.items.length,500);assert.strictEqual(big.skipped.length,10,'Items past 500 are skipped and listed');
// Importing the same export twice must give the same refs (Halyard recognises refs it already copied).
assert.deepStrictEqual(H.toHandoff(lessons).items.map(i=>i.ref),H.toHandoff(lessons).items.map(i=>i.ref));
console.log('PASS: fleet-handoff v1 export (format, ref, limits, skips, drafts, stable refs)');
