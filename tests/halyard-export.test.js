'use strict';
const assert=require('assert');
const H=require('../web/halyard-export.js');
// Rules below are taken from Halyard docs/WORK_ITEM_MODEL.md: title pattern, id pattern, required meta for a STORY,
// TBD allowed for sizing, minimum labels, and the Story body sections.
const REQUIRED_STORY_META=['type','id','parent','theme','state','area','points','sprint'];
const lessons=[
 {id:'a1b2c3d4e5f6',title:'Pump B vibration repeats across watches',body:'Recurring condition: Pump B. Evidence: log 1 lines 2,3.',source:'log-1',status:'reviewed'},
 {id:'ffeeddccbbaa',title:'Draft only lesson',body:'Not reviewed yet.',source:'',status:'draft'},
 {id:'0011223344',title:'  ',body:'No title',status:'reviewed'},
 {id:'9988776655',title:'Pump B vibration repeats across watches',body:'Same title, different lesson.',source:'log-2',status:'reviewed'}
];
const out=H.exportLessons(lessons,{now:'2026-10-31T12:00:00.000Z'});
assert.strictEqual(out.schema,'eightbells.halyard-backlog/1');
assert.strictEqual(out.generated,'2026-10-31T12:00:00.000Z');
assert.strictEqual(out.items.length,2,'Only reviewed lessons with a title are exported by default');
assert.deepStrictEqual(out.skipped.map(s=>s.reason).sort(),['no title','not reviewed']);
const first=out.items[0];
assert(/^STORY :: .+/.test(first.title),'Title pattern is "STORY :: name"');
assert(/^STORY-[a-z0-9-]+$/.test(first.id),'Id pattern is STORY-slug');
assert.notStrictEqual(out.items[0].id,out.items[1].id,'Two lessons with the same title get different ids');
for(const item of out.items){
 const meta=H.parseMeta(item.body);
 assert(meta,'Every body starts with a halyard-meta fence');
 for(const key of REQUIRED_STORY_META)assert(key in meta&&meta[key]!=='' ,'Missing required STORY meta: '+key);
 assert.strictEqual(meta.type,'STORY');assert.strictEqual(meta.id,item.id);
 assert.strictEqual(meta.state,'open');
 assert.strictEqual(meta.points,'TBD','Sizing stays TBD until a human approves a value');
 assert.strictEqual(meta.sprint,'TBD');
 assert(item.body.startsWith('~~~halyard-meta'),'The meta fence comes first');
 for(const section of ['## User need','## Acceptance criteria','## Tasks','## Parent'])assert(item.body.includes(section),'Missing section '+section);
 assert(/## Acceptance criteria\n- \[ \]/.test(item.body),'Acceptance criteria are a checklist');
 assert(/## Tasks\n- \[ \]/.test(item.body),'Tasks are a checklist inside the Story');
 for(const label of ['halyard','type::story','area::watchstanding','refine::sandbox-review'])assert(item.labels.includes(label),'Missing label '+label);
 assert(!item.labels.includes('halyard-synthetic'),'Proposals must not carry the teardown label');
}
assert(first.body.includes('Recurring condition: Pump B.'),'The reviewed lesson text is carried into the body');
assert.strictEqual(first.source.logId,'log-1');
assert(first.body.includes('Eight Bells source log-1'));

const withDrafts=H.exportLessons(lessons,{includeDrafts:true});
assert.strictEqual(withDrafts.items.length,3);
const custom=H.exportLessons([lessons[0]],{theme:'THEME-x',parent:'FEATURE-y',area:'ops',points:'3',sprint:'2026-S12'});
const cm=H.parseMeta(custom.items[0].body);
assert.deepStrictEqual([cm.theme,cm.parent,cm.area,cm.points,cm.sprint],['THEME-x','FEATURE-y','ops','3','2026-S12']);
assert(custom.items[0].labels.includes('area::ops'));
assert.deepStrictEqual(H.exportLessons([]).items,[]);
assert.deepStrictEqual(H.exportLessons(null).items,[]);
assert.strictEqual(H.parseMeta('no fence here'),null);
const long=H.exportLessons([{id:'z',title:'x'.repeat(300),body:'b',status:'reviewed'}]).items[0];
assert(long.title.length<=100&&long.id.length<=60,'Long titles are shortened');
JSON.parse(JSON.stringify(out));
console.log('PASS: Halyard lesson export (work-item model rules, meta fence, sections, labels, TBD sizing, duplicates, drafts)');
