'use strict';
const assert=require('assert');
const fs=require('fs');
const path=require('path');
const E=require('../web/engine.js');
const A=require('../web/adapters.js');
const sample=name=>fs.readFileSync(path.join(__dirname,'..','samples',name),'utf8');

// ---- formats list ----
assert.deepStrictEqual(A.FORMATS.map(f=>f.id),['jsonl','delimited','xml']);

// ---- JSON Lines ----
const jsonl='{"timestamp":"2026-10-30T08:00:00","equipment":"Pump B","description":"Pump B abnormal vibration"}\n\n{"timestamp":"2026-10-30T08:30:00","equipment":"Pump B","description":"Supervisor notified"}\n';
let r=A.parse(jsonl,'jsonl');
assert.strictEqual(r.format,'jsonl');assert.strictEqual(r.entries.length,2);
assert.deepStrictEqual(r.entries.map(e=>e.line),[1,3],'Source line numbers skip the blank line');
assert.deepStrictEqual(r.entries.map(e=>e.time),['08:00','08:30']);
assert.strictEqual(r.entries[0].issue,true);assert.strictEqual(r.entries[0].equipment,'Pump B');
const asJson=E.parse(JSON.stringify([{timestamp:'2026-10-30T08:00:00',equipment:'Pump B',description:'Pump B abnormal vibration'}]),'json');
assert.strictEqual(r.entries[0].text,asJson.entries[0].text,'Same record gives the same entry as the JSON path');
assert.strictEqual(A.detect(jsonl),'jsonl');
assert.strictEqual(A.parse(jsonl,'auto').format,'jsonl');
assert.throws(()=>A.parse('{"a":1}\nnot json','jsonl'),/line 2 is not valid JSON/);
assert.throws(()=>A.parse('[1]\n[2]','jsonl'),/must be one JSON object/);
assert.strictEqual(A.parse('','jsonl').entries.length,0,'An empty file has no entries');

// ---- delimited tables ----
const tsv='timestamp\tequipment\tdescription\n0800\tPump B\tvibration, abnormal\n0830\tPump B\t"said ""ok"""\n';
r=A.parse(tsv,'delimited');
assert.strictEqual(r.format,'delimited');assert.strictEqual(r.entries.length,2);
assert.deepStrictEqual(r.entries.map(e=>e.line),[2,3]);
assert(r.entries[0].text.includes('vibration, abnormal'),'A comma inside a cell survives');
assert(r.entries[1].text.includes('said "ok"'),'Doubled quotes are read as one quote');
assert.strictEqual(A.detect(tsv),'delimited');
assert.strictEqual(A.parse('time;equipment;text\n0900;Fan 1;fan alarm received','auto').entries[0].time,'09:00','Semicolon tables are detected');
assert.strictEqual(A.parse('time|equipment|text\n0900|Fan 1|fan alarm received','delimited').entries.length,1,'Pipe tables are read');
assert.throws(()=>A.parse('a\tb\nc','delimited'),/same way on every line/);
assert.throws(()=>A.parse('a\tb\n"open\tx','delimited'),/same way on every line/,'A row with an unclosed quote cannot be split consistently');
assert.strictEqual(A.detect('0800 Watch assumed\n0830 Pump B abnormal'),null,'Plain text is left to the engine');
assert.strictEqual(A.detect('timestamp,description\n0800,x'),null,'Comma CSV is left to the engine');

// ---- XML ----
const xml='<?xml version="1.0"?>\n<watchLog>\n <entries>\n  <entry time="0800"><equipment>Fan 2</equipment><text>Fan 2 alarm &amp; fault</text></entry>\n  <entry><timestamp>2026-10-30T08:30:00</timestamp><text><![CDATA[Fan 2 <restored>]]></text></entry>\n  <entry time="0900" text="Pump A secured"/>\n </entries>\n</watchLog>';
r=A.parse(xml,'xml');
assert.strictEqual(r.format,'xml');assert.strictEqual(r.entries.length,3);
assert.deepStrictEqual(r.entries.map(e=>e.line),[4,5,6],'Source lines come from the element positions');
assert.deepStrictEqual(r.entries.map(e=>e.time),['08:00','08:30','09:00']);
assert.strictEqual(r.entries[0].text,'Fan 2: Fan 2 alarm & fault','Entities in text are decoded');
assert.strictEqual(r.entries[0].issue,true);
assert(r.entries[1].text.includes('Fan 2 <restored>')&&r.entries[1].resolution===true,'CDATA is read as text');
assert.strictEqual(r.entries[2].text,'Pump A secured','Attribute-only records work');
assert.strictEqual(A.detect(xml),'xml');
assert.strictEqual(A.parse('<log><LogEntry><text>A&#66;&#x43; &unknown;</text></LogEntry></log>','xml').entries[0].text,'ABC &unknown;','Numeric entities decode; unknown ones stay as written');
assert.throws(()=>A.parse('<!DOCTYPE x [<!ENTITY a "b">]><log><entry>x</entry></log>','xml'),/DTDs and entities are not accepted/);
assert.throws(()=>A.parse('<log><entry>x','xml'),/never closed/);
assert.throws(()=>A.parse('<log><entry>x</log>','xml'),/mismatched closing tag/);
assert.throws(()=>A.parse('<log><meta/></log>','xml'),/no <entry>/);
assert.throws(()=>A.parse('just text','xml'),/no root element/);

// ---- hand-off to the engine ----
assert.strictEqual(A.parse('0800 Watch assumed','text').format,'text');
assert.strictEqual(A.parse('0800 Watch assumed','auto').format,'text');
assert.strictEqual(A.parse(sample('readings.csv'),'auto').format,'csv','Comma CSV still goes to the engine');
assert.strictEqual(A.parse(sample('elog_export.json'),'auto').format,'json');
assert.throws(()=>A.parse('x','nonsense'),/Unsupported format/);

// ---- the synthetic samples ----
const sj=A.parse(sample('elog_export.jsonl'),'auto');
assert.strictEqual(sj.format,'jsonl');assert.deepStrictEqual(sj.entries.map(e=>[e.line,e.time]),[[1,'08:00'],[2,'08:30'],[3,'09:15']]);
const sa=E.analyze(sj.entries);
assert(!sa.findings.some(f=>f.type==='chronology'),'The sample is in order');
assert.strictEqual(sa.open.length,0,'The vibration is cleared at 09:15');
const st=A.parse(sample('readings.tsv'),'auto');
assert.strictEqual(st.format,'delimited');assert.deepStrictEqual(st.entries.map(e=>e.line),[2,3,4]);
assert(st.entries[0].text.includes('42 psi'));
assert(E.analyze(st.entries,{intervalMinutes:30}).findings.some(f=>f.type==='interval-gap'),'Hourly readings against a 30 minute interval raise gaps, as for CSV');
const sx=A.parse(sample('elog_export.xml'),'auto');
assert.strictEqual(sx.format,'xml');assert.deepStrictEqual(sx.entries.map(e=>e.line),[4,5,6]);
assert.strictEqual(sx.entries[0].text,'Fan 2: Fan 2 alarm received & acknowledged');
assert.strictEqual(E.analyze(sx.entries).open.length,0,'The fault is restored at 09:15');
console.log('PASS: e-log adapters (JSON Lines, delimited tables, XML: line numbers, detection, quoting, entities, DTD refusal, errors, engine hand-off, samples)');
