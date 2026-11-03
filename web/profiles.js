/* Eight Bells watch-profile rules: expected readings per piece of equipment, beyond the single manual interval.
   A profile is data the user loads (JSON). It says which readings a watch must record, the unit and the allowed range,
   and how often. Nothing here is an approved requirement: Eight Bells ships no limits, and a profile is only as good
   as the person who wrote it. Findings are advisory prompts to check the record, like every other finding. No network. */
(function(root,factory){
 if(typeof module==='object'&&module.exports)module.exports=factory(require('./engine.js'));
 else root.EightBellsProfiles=factory(root.EightBellsEngine);
})(typeof globalThis!=='undefined'?globalThis:this,function(engine){
"use strict";
const clean=s=>String(s==null?'':s).replace(/\s+/g,' ').trim();
const lower=s=>clean(s).toLowerCase();
const isNum=v=>typeof v==='number'&&Number.isFinite(v);

// Returns a list of plain-language problems; an empty list means the profile can be used.
function validate(profile){
 const errors=[];
 if(!profile||typeof profile!=='object'||Array.isArray(profile))return ['A profile must be a JSON object.'];
 if(!clean(profile.label))errors.push('The profile needs a label.');
 if(profile.intervalMinutes!=null&&!(isNum(profile.intervalMinutes)&&profile.intervalMinutes>=0))errors.push('intervalMinutes must be a number of minutes, 0 or more.');
 if(!Array.isArray(profile.rules)||!profile.rules.length)errors.push('The profile needs at least one rule.');
 (Array.isArray(profile.rules)?profile.rules:[]).forEach((r,i)=>{
  const n='Rule '+(i+1)+': ';
  if(!r||typeof r!=='object'){errors.push(n+'must be an object.');return;}
  if(!clean(r.equipment))errors.push(n+'equipment is required.');
  if(!clean(r.reading))errors.push(n+'reading is required.');
  if(r.min!=null&&!isNum(r.min))errors.push(n+'min must be a number.');
  if(r.max!=null&&!isNum(r.max))errors.push(n+'max must be a number.');
  if(isNum(r.min)&&isNum(r.max)&&r.min>r.max)errors.push(n+'min is greater than max.');
  if(r.intervalMinutes!=null&&!(isNum(r.intervalMinutes)&&r.intervalMinutes>0))errors.push(n+'intervalMinutes must be a number above 0.');
  if(r.unit!=null&&typeof r.unit!=='string')errors.push(n+'unit must be text.');
 });
 return errors;
}

// The reading carried by one entry: structured fields first (CSV, TSV, JSON, XML), then "name: 42 psi" in the text.
function readingOf(entry){
 const raw=entry.raw&&typeof entry.raw==='object'?entry.raw:null;
 if(raw){
  const get=(...keys)=>{for(const k of keys){const a=Object.keys(raw).find(x=>x.toLowerCase()===k);if(a&&raw[a]!=null&&clean(raw[a])!=='')return clean(raw[a]);}return '';};
  const name=get('reading_type','metric','parameter','reading'),value=get('value'),unit=get('unit');
  if(name&&value!==''&&Number.isFinite(Number(value)))return {name,value:Number(value),unit};
 }
 const m=String(entry.text||'').match(/([A-Za-z][A-Za-z0-9 ./-]*?):\s*(-?\d+(?:\.\d+)?)\s*([A-Za-z%°/]+)?/);
 if(!m)return null;
 let name=clean(m[1].split('|').pop());
 // "Pump A discharge pressure: 50 psi": the equipment name leads the reading name in free text.
 if(entry.equipment&&lower(name).startsWith(lower(entry.equipment)+' '))name=clean(name.slice(String(entry.equipment).length));
 return {name,value:Number(m[2]),unit:m[3]||''};
}
const matches=(rule,entry,reading)=>reading&&lower(reading.name)===lower(rule.reading)&&lower(entry.equipment||'')===lower(rule.equipment);
const minutesOf=e=>{if(!e.time)return null;const [h,m]=e.time.split(':').map(Number);return h*60+m;};

// Findings for one profile. Same shape as engine findings; ids continue from firstId.
function findings(entries,profile,firstId){
 const out=[];let n=firstId||1;
 const add=(type,detail,lines)=>out.push({id:'f'+(n++),type,detail,lines,priority:'review'});
 const errs=validate(profile);if(errs.length)throw Error('Invalid profile: '+errs[0]);
 for(const rule of profile.rules){
  const label=rule.equipment+' '+rule.reading;
  const hits=[];
  for(const e of entries){const r=readingOf(e);if(matches(rule,e,r))hits.push({e,r});}
  if(rule.required!==false&&!hits.length){add('reading-missing','No '+label+' reading was found; the profile expects one.',[]);continue;}
  for(const {e,r} of hits){
   if(rule.unit&&r.unit&&lower(r.unit)!==lower(rule.unit))add('reading-unit',label+' is recorded in '+r.unit+' but the profile expects '+rule.unit+'.',[e.line]);
   else if(isNum(rule.min)&&r.value<rule.min)add('reading-range',label+' '+r.value+' '+(r.unit||rule.unit||'')+' is below the profile minimum '+rule.min+'.',[e.line]);
   else if(isNum(rule.max)&&r.value>rule.max)add('reading-range',label+' '+r.value+' '+(r.unit||rule.unit||'')+' is above the profile maximum '+rule.max+'.',[e.line]);
  }
  const every=isNum(rule.intervalMinutes)?rule.intervalMinutes:(isNum(profile.intervalMinutes)?profile.intervalMinutes:0);
  if(every>0){
   let prev=null;
   for(const {e} of hits){
    const t=minutesOf(e);if(t==null)continue;
    if(prev){const d=t-prev.t;if(d>every*1.75&&d<600)add('reading-interval',label+' readings are '+d+' minutes apart against the profile interval of '+every+' minutes.',[prev.line,e.line]);}
    prev={t,line:e.line};
   }
  }
 }
 return out;
}

// engine.analyze plus the profile findings, with the advisory score worked out the same way.
function analyzeWithProfile(entries,profile,opts){
 const base=engine.analyze(entries,opts);
 if(!profile)return base;
 const extra=findings(entries,profile,base.findings.length+1);
 const all=base.findings.concat(extra);
 const score=Math.max(0,100-all.filter(f=>f.type!=='copy-forward').length*10-all.filter(f=>f.type==='copy-forward').length*8);
 return Object.assign({},base,{findings:all,score,profile:profile.label});
}
return {validate,readingOf,findings,analyzeWithProfile};
});
