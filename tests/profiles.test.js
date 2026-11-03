'use strict';
const assert=require('assert');
const fs=require('fs');
const path=require('path');
const E=require('../web/engine.js');
const P=require('../web/profiles.js');
const sample=name=>fs.readFileSync(path.join(__dirname,'..','samples',name),'utf8');
const profile=JSON.parse(sample('profile_engineering_synthetic.json'));

// ---- the shipped sample profile is valid, and says it is not a requirement ----
assert.deepStrictEqual(P.validate(profile),[]);
assert(/NOT an approved requirement/.test(profile.label));

// ---- validation messages ----
assert.deepStrictEqual(P.validate(null),['A profile must be a JSON object.']);
assert.deepStrictEqual(P.validate([]),['A profile must be a JSON object.']);
let errs=P.validate({label:'x',rules:[]});assert(errs.some(e=>/at least one rule/.test(e)));
errs=P.validate({rules:[{equipment:'Pump A',reading:'p',min:5,max:2}]});
assert(errs.some(e=>/needs a label/.test(e))&&errs.some(e=>/min is greater than max/.test(e)));
errs=P.validate({label:'x',intervalMinutes:-1,rules:[{reading:'p'},{equipment:'a',reading:'p',min:'3'},{equipment:'a',reading:'p',intervalMinutes:0}]});
assert(errs.some(e=>/intervalMinutes must be a number of minutes/.test(e)));
assert(errs.some(e=>/Rule 1: equipment is required/.test(e)));
assert(errs.some(e=>/Rule 2: min must be a number/.test(e)));
assert(errs.some(e=>/Rule 3: intervalMinutes must be a number above 0/.test(e)));
assert.throws(()=>P.findings([],{label:'x',rules:[]}),/Invalid profile/);

// ---- reading extraction ----
const csv=E.parse(sample('readings_profile_check.csv'),'csv');
assert.deepStrictEqual(P.readingOf(csv.entries[0]),{name:'discharge pressure',value:49,unit:'psi'},'Structured CSV fields');
const text=E.parse('0800 Pump A discharge pressure: 50 psi\n0830 Supervisor notified','text');
assert.deepStrictEqual(P.readingOf(text.entries[0]),{name:'discharge pressure',value:50,unit:'psi'},'Free text with the equipment name leading');
assert.strictEqual(P.readingOf(text.entries[1]),null,'A line with no reading has none');

// ---- findings on the sample readings ----
const f=P.findings(csv.entries,profile);
const by=t=>f.filter(x=>x.type===t);
assert.strictEqual(by('reading-range').length,2);
assert(by('reading-range').some(x=>/above the profile maximum 46/.test(x.detail)&&x.lines[0]===2),'Pump A 49 psi is above 46');
assert(by('reading-range').some(x=>/Fan 2 motor temperature 200/.test(x.detail)&&x.lines[0]===3),'Fan 2 200 F is above 180');
assert.strictEqual(by('reading-unit').length,1);
assert(/recorded in kPa but the profile expects psi/.test(by('reading-unit')[0].detail)&&by('reading-unit')[0].lines[0]===4);
assert.strictEqual(by('reading-interval').length,1);
assert.deepStrictEqual(by('reading-interval')[0].lines,[4,5],'09:00 to 11:00 is 120 minutes against 60');
assert.strictEqual(by('reading-missing').length,0);
assert(f.every(x=>x.priority==='review'&&/^f\d+$/.test(x.id)));

// ---- no findings when readings are in range and on time ----
const good=E.parse('timestamp,equipment,reading_type,value,unit\n0800,Pump A,discharge pressure,42,psi\n0900,Pump A,discharge pressure,44,PSI\n1000,Pump A,discharge pressure,46,psi','csv');
assert.deepStrictEqual(P.findings(good.entries,profile),[],'Range edges, unit case and hourly readings are all fine');

// ---- missing required readings; optional rules stay quiet ----
const other=E.parse('0800 Watch assumed\n0900 Rounds complete','text');
const miss=P.findings(other.entries,profile);
assert.deepStrictEqual(miss.map(x=>x.type),['reading-missing']);
assert(/No Pump A discharge pressure reading/.test(miss[0].detail),'Fan 2 is optional so only Pump A is reported');
assert.deepStrictEqual(miss[0].lines,[]);

// ---- interval precedence and the profile-wide default ----
const slow=E.parse('timestamp,equipment,reading_type,value\n0800,Fan 2,motor temperature,100\n1000,Fan 2,motor temperature,100','csv');
const fan=extra=>Object.assign({equipment:'Fan 2',reading:'motor temperature',required:false},extra);
assert.strictEqual(P.findings(slow.entries,{label:'x',rules:[fan()]}).length,0,'No interval anywhere means no interval findings');
const withDefault=P.findings(slow.entries,{label:'x',intervalMinutes:60,rules:[fan()]});
assert.strictEqual(withDefault.length,1,'The profile-wide 60 minute default applies to a rule without its own interval');
assert.strictEqual(withDefault[0].type,'reading-interval');
assert.strictEqual(P.findings(slow.entries,{label:'x',intervalMinutes:60,rules:[fan({intervalMinutes:120})]}).length,0,'A rule interval of 120 overrides the default of 60');
assert.strictEqual(P.findings(slow.entries,{label:'x',intervalMinutes:0,rules:[fan({intervalMinutes:30})]}).length,1,'A rule interval works with no profile default');

// ---- merged analysis ----
const plain=E.analyze(csv.entries,{intervalMinutes:0});
const merged=P.analyzeWithProfile(csv.entries,profile,{intervalMinutes:0});
assert.strictEqual(merged.findings.length,plain.findings.length+f.length);
assert.deepStrictEqual(merged.findings.map(x=>x.id),merged.findings.map((_,i)=>'f'+(i+1)),'Finding ids continue without gaps');
assert.strictEqual(merged.score,Math.max(0,100-merged.findings.filter(x=>x.type!=='copy-forward').length*10-merged.findings.filter(x=>x.type==='copy-forward').length*8));
assert(merged.score<plain.score,'Profile findings lower the advisory score');
assert.strictEqual(merged.profile,profile.label);
assert.deepStrictEqual(P.analyzeWithProfile(csv.entries,null,{intervalMinutes:0}),plain,'No profile gives the plain analysis');
assert(Array.isArray(merged.open),'The engine fields are kept');
console.log('PASS: watch-profile rules (validation, reading extraction, range, unit, interval, missing, precedence, merged score)');
