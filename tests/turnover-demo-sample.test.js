'use strict';
const assert=require('assert'),fs=require('fs'),path=require('path');
const E=require('../web/engine.js');
// The turnover walkthrough log must show an unresolved condition and a chronology problem in the same log, and be marked synthetic.
const text=fs.readFileSync(path.join(__dirname,'..','samples','engineering_turnover_demo.txt'),'utf8');
assert(/^SIMULATED \/ TRAINING ONLY/.test(text),'The log says it is simulated');
const parsed=E.parse(text,'auto'),res=E.analyze(parsed.entries);
assert(res.findings.some(f=>f.type==='chronology'),'The log raises a chronology finding');
assert(res.open.some(o=>o.equipment==='Pump B'),'The log has Pump B as a potential open condition');
const turn=E.turnover({name:'demo',watch:'Engineering',content:text,entries:parsed.entries,analysis:res});
assert(/Pump B/.test(turn)&&/source line/.test(turn),'The offline turnover names Pump B with a source line');
console.log('PASS: turnover demonstration log (chronology finding, Pump B open condition, offline turnover with source lines)');
