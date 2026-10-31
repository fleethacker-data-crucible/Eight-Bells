'use strict';
const assert=require('assert');
const engine=require('../web/engine.js');
const logs=[
 {id:'a',watch:'Engineering',analysis:{open:[{equipment:'Pump A',lines:[1]}],findings:[{id:'f1'},{id:'f2'}]}},
 {id:'b',watch:'Engineering',analysis:{open:[],findings:[{id:'f3'}]}},
 {id:'c',watch:'Security',analysis:{open:[],findings:[]}},
 {id:'d',watch:'',analysis:{open:[{equipment:'Gate 3',lines:[4]}],findings:[]}}
];
const lessons=[
 {id:'l1',source:'a',status:'draft'},
 {id:'l2',source:'a',status:'reviewed'},
 {id:'l3',source:'c',status:'reviewed'},
 {id:'l4',source:'',status:'draft'},
 {id:'l5',source:'gone',status:'draft'}
];
const rows=engine.semaphoreRows(logs,lessons);
assert.deepStrictEqual(rows.map(r=>r.watch),['Engineering','General','Security','Unassigned']);
const eng=rows[0];
assert.deepStrictEqual([eng.logs,eng.openConditions,eng.findings,eng.lessonsDraft,eng.lessonsReviewed],[2,1,3,1,1]);
assert.deepStrictEqual([rows[1].lessonsDraft,rows[1].lessonsReviewed],[2,0],'Lessons with no source or an unknown source count under General');
assert.deepStrictEqual([rows[2].logs,rows[2].lessonsReviewed],[1,1]);
assert.deepStrictEqual([rows[3].logs,rows[3].openConditions],[1,1],'A log with no watch is counted as Unassigned');
assert.deepStrictEqual(engine.semaphoreRows([],[]),[],'No logs and no lessons gives no rows');
assert.deepStrictEqual(engine.semaphoreRows(undefined,null),[],'Missing inputs are treated as empty');
assert.strictEqual(engine.semaphoreRows([{id:'x',watch:'  Night  ',analysis:{}}],[])[0].watch,'Night','Watch names are trimmed');
assert.strictEqual(engine.semaphoreRows([{id:'x',watch:'Night'}],[])[0].openConditions,0,'A log without analysis counts zero');

const csv=engine.semaphoreCsv(engine.semaphoreRows([{id:'q',watch:'Bridge, "night"',analysis:{}}],[]));
assert.strictEqual(csv,'watch,logs,open_conditions,findings,lessons_draft,lessons_reviewed\r\n"Bridge, ""night""",1,0,0,0,0\r\n','Commas and quotes are quoted and doubled');
assert.strictEqual(engine.semaphoreCsv([]),'watch,logs,open_conditions,findings,lessons_draft,lessons_reviewed\r\n','An empty export still has a header');
// Round trip through the engine's own CSV reader.
const parsed=engine.csv(csv);
assert.strictEqual(parsed[1][0],'Bridge, "night"');
assert.strictEqual(parsed.length,2);
console.log('PASS: Semaphore data-source export (per-watch counts, lesson status, CSV quoting, empty input)');
