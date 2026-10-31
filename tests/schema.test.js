'use strict';
const assert=require('assert');
const crypto=require('crypto');
const fs=require('fs');
const path=require('path');
const E=require('../web/engine.js');
const S=require('../web/schema.js');
const sample=name=>fs.readFileSync(path.join(__dirname,'..','samples',name),'utf8');

// ---- SHA-256 against known vectors and against Node's own ----
assert.strictEqual(S.sha256Hex(''),'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
assert.strictEqual(S.sha256Hex('abc'),'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
assert.strictEqual(S.sha256Hex('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),'248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1','Two-block message');
const samples=['a','The quick brown fox','x'.repeat(55),'x'.repeat(56),'x'.repeat(63),'x'.repeat(64),'x'.repeat(65),'x'.repeat(1000),'Pump B · vibration — "quoted" é ü 日本語 😀','line1\r\nline2\n'];
for(const s of samples)assert.strictEqual(S.sha256Hex(s),crypto.createHash('sha256').update(s,'utf8').digest('hex'),'sha256 of '+JSON.stringify(s.slice(0,20)));
for(const f of ['engineering_discrepancy.txt','readings.csv','elog_export.json'])assert.strictEqual(S.sha256Hex(sample(f)),crypto.createHash('sha256').update(sample(f),'utf8').digest('hex'),f);
assert.strictEqual(S.sha256Hex(new Uint8Array([97,98,99])),'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad','Bytes work too');

// ---- stable IDs ----
assert.strictEqual(S.stableId('ent','a',1),S.stableId('ent','a',1),'Same parts, same ID');
assert.notStrictEqual(S.stableId('ent','a',1),S.stableId('ent','a',2));
assert.notStrictEqual(S.stableId('ent','ab','c'),S.stableId('ent','a','bc'),'Parts are separated, so they cannot run together');
assert(/^ent_[0-9a-f]{16}$/.test(S.stableId('ent','x')));

// ---- records from a real sample log ----
const text=sample('engineering_discrepancy.txt'),parsed=E.parse(text,'auto'),analysis=E.analyze(parsed.entries);
const log={content:text,name:'  Engineering   1200-1600 ',watch:'Engineering',entries:parsed.entries,analysis};
const rec=S.fromLog(log,{retention:{policy:'review-after',reviewAfterDays:365}});
assert.strictEqual(rec.source.sha256,crypto.createHash('sha256').update(text,'utf8').digest('hex'));
assert.strictEqual(rec.source.id,'src_'+rec.source.sha256.slice(0,16));
assert.strictEqual(rec.source.name,'Engineering 1200-1600');
assert.strictEqual(rec.source.classification,'synthetic-training');
assert.deepStrictEqual(rec.source.retention,{policy:'review-after',reviewAfterDays:365});
assert.strictEqual(rec.source.bytes,Buffer.byteLength(text,'utf8'));
assert.strictEqual(rec.entries.length,parsed.entries.length);
assert(rec.entries.every(e=>e.sourceId===rec.source.id&&/^ent_/.test(e.id)&&e.watchProfile==='Engineering'));
assert.strictEqual(new Set(rec.entries.map(e=>e.id)).size,rec.entries.length,'Entry IDs are unique');
const pumpEntries=rec.entries.filter(e=>/pump b/i.test(e.narrative)&&e.assetId);
assert(pumpEntries.length>=2&&new Set(pumpEntries.map(e=>e.assetId)).size===1,'The same equipment gets the same asset ID');
assert.strictEqual(rec.findings.length,analysis.findings.length);
assert(rec.findings.every(f=>f.confidence==='heuristic'&&f.reviewStatus==='unreviewed'&&/^fnd_/.test(f.id)));
const again=S.fromLog(log,{retention:{policy:'review-after',reviewAfterDays:365}});
assert.deepStrictEqual(again,rec,'Building twice gives identical records');
const edited=S.fromLog(Object.assign({},log,{content:text+'\n1700 One more line'}));
assert.notStrictEqual(edited.source.id,rec.source.id,'An edited source gets a new ID; the original is never rewritten');
assert.notStrictEqual(edited.entries[0].id,rec.entries[0].id);
const other=S.fromLog({content:'0800 Pump B check',name:'other',entries:[{line:1,time:'08:00',text:'0800 Pump B check',equipment:'Pump B'}],analysis:{findings:[]}});
assert.strictEqual(other.entries[0].assetId,pumpEntries[0].assetId,'Asset IDs match across different logs');
assert.strictEqual(S.fromLog({content:'',name:'',entries:[]}).entries.length,0);

// ---- lesson lifecycle ----
const T='2026-10-31T10:00:00.000Z';
let les=S.newLesson({title:'  Pump B  repeats ',body:'Evidence: logs 1 and 2',author:'Author One',eventIds:['fnd_1'],at:T,expiry:'2027-10-31T00:00:00.000Z'});
assert.strictEqual(les.status,'draft');assert.strictEqual(les.title,'Pump B repeats');assert(/^les_/.test(les.id));
assert.deepStrictEqual(les.history,[{at:T,from:null,to:'draft',by:'Author One',note:''}]);
const draft=les;
les=S.transition(les,'submit','Author One',{at:T});
assert.strictEqual(les.status,'in-review');assert.strictEqual(draft.status,'draft','The earlier record is not changed');
assert.throws(()=>S.transition(les,'approve','Author One',{at:T}),/author cannot approve/);
assert.throws(()=>S.transition(les,'approve','  author one ',{at:T}),/author cannot approve/,'The author check ignores case and spaces');
assert.throws(()=>S.transition(les,'reject','Reviewer Two',{at:T}),/needs a reason/);
assert.throws(()=>S.transition(les,'approve','',{at:T}),/must be named/);
assert.throws(()=>S.transition(les,'submit','Author One',{at:T}),/The lesson is in-review, so "submit" is not allowed \(it works on a lesson that is draft\)/);
assert.throws(()=>S.transition(les,'fly','x'),/Unknown lesson action/);
const rejected=S.transition(les,'reject','Reviewer Two',{at:T,note:'Evidence is thin'});
assert.strictEqual(rejected.status,'rejected');assert.deepStrictEqual(rejected.reviewers.map(r=>[r.name,r.decision,r.note]),[['Reviewer Two','rejected','Evidence is thin']]);
const reopened=S.transition(rejected,'reopen','Author One',{at:T});assert.strictEqual(reopened.status,'draft');
const returned=S.transition(les,'return','Reviewer Two',{at:T,note:'Add dates'});assert.strictEqual(returned.status,'draft');
les=S.transition(les,'approve','Reviewer Two',{at:T,note:'Checked against the logs'});
assert.strictEqual(les.status,'approved');assert.deepStrictEqual(les.reviewers.map(r=>[r.name,r.decision]),[['Reviewer Two','approved']]);
assert.deepStrictEqual(les.history.map(h=>h.to),['draft','in-review','approved']);
assert.throws(()=>S.transition(les,'supersede','Reviewer Two',{at:T}),/Name the lesson/);
assert.throws(()=>S.transition(les,'expire','Reviewer Two',{at:T}),/not reached its expiry/);
assert.strictEqual(S.isExpired(les,'2026-11-01T00:00:00Z'),false);
assert.strictEqual(S.isExpired(les,'2027-11-01T00:00:00Z'),true);
const expired=S.transition(les,'expire','Reviewer Two',{at:'2027-11-01T00:00:00.000Z'});assert.strictEqual(expired.status,'expired');
const superseded=S.transition(les,'supersede','Reviewer Two',{at:T,supersededBy:'les_next'});
assert.strictEqual(superseded.status,'superseded');assert.strictEqual(superseded.supersededBy,'les_next');
assert.throws(()=>S.transition(superseded,'approve','Someone Else',{at:T}),/The lesson is superseded, so "approve" is not allowed/);
assert.throws(()=>S.transition(expired,'submit','Author One',{at:T}),/The lesson is expired, so "submit" is not allowed/);
assert.strictEqual(les.status,'approved','Transitions never change the lesson they start from');
const nextLesson=S.newLesson({title:'Pump B follow-up',body:'x',author:'Author One',supersedes:les.id,at:T});
assert.strictEqual(nextLesson.supersedes,les.id);
console.log('PASS: schema (sha256 vs Node crypto, stable IDs, provenance records, lesson lifecycle with two-person rule, expiry, immutability)');
