/* Eight Bells -> Halyard hand-off: reviewed lessons become STORY work items in Halyard's work-item model
   (Halyard docs/WORK_ITEM_MODEL.md): "STORY :: name" title, a halyard-meta fence, Need / Acceptance criteria / Tasks / Parent
   sections and the minimum labels. Halyard has no import file format, so the export is the issue payloads (title, body, labels)
   as JSON for the sandbox review board. No network and no dependencies. */
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.EightBellsHalyard=api;})(typeof globalThis!=='undefined'?globalThis:this,function(){
"use strict";
const SCHEMA='eightbells.halyard-backlog/1';
// Defaults are chosen here, not by Halyard: a lane and a Feature to hold lesson follow-ups. Override per export.
const DEFAULTS={theme:'THEME-watch-lessons',parent:'FEATURE-lessons-follow-up',area:'watchstanding',state:'open',points:'TBD',sprint:'TBD',includeDrafts:false};
const clean=s=>String(s==null?'':s).replace(/\s+/g,' ').trim();
function slug(s){return clean(s).toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'').slice(0,40).replace(/-+$/,'')||'lesson';}
function storyId(lesson){const tail=String(lesson.id==null?'':lesson.id).toLowerCase().replace(/[^a-z0-9]/g,'').slice(0,6);return 'STORY-'+slug(lesson.title)+(tail?'-'+tail:'');}
function metaBlock(m){return '~~~halyard-meta\n'+['type','id','theme','parent','state','area','points','sprint'].map(k=>k+': '+m[k]).join('\n')+'\n~~~';}
function buildItem(lesson,o){
 const id=storyId(lesson),title=clean(lesson.title),short=title.length>90?title.slice(0,89)+'…':title;
 const meta={type:'STORY',id,theme:o.theme,parent:o.parent,state:o.state,area:o.area,points:o.points,sprint:o.sprint};
 const body=[metaBlock(meta),'',
  '## User need','As a relieving watchstander, I need this lesson learned acted on, so the condition it describes is not repeated: '+short+'.','',
  '## Lesson (as reviewed in Eight Bells)',String(lesson.body==null?'':lesson.body).trim()||'(no text)','',
  '## Acceptance criteria','- [ ] The lesson is checked against its source evidence'+(lesson.source?' (Eight Bells source '+lesson.source+')':''),'- [ ] A decision is recorded: act, defer or reject','- [ ] If acted on, the change and where it landed are linked','',
  '## Tasks','- [ ] Confirm the evidence lines','- [ ] Decide the follow-up and owner','- [ ] Close or split this Story','',
  '## Parent',o.parent,''].join('\n');
 return {id,title:'STORY :: '+short,labels:['halyard','type::story','area::'+o.area,'refine::sandbox-review'],body,source:{lessonId:lesson.id==null?null:lesson.id,logId:lesson.source||null}};
}
// lessons: Eight Bells lesson records {id,title,body,source,status}. Only reviewed lessons are exported unless includeDrafts is set.
function exportLessons(lessons,opts){
 const o=Object.assign({},DEFAULTS,opts||{}),items=[],skipped=[],seen=new Set();
 for(const lesson of Array.isArray(lessons)?lessons:[]){
  if(!lesson||!clean(lesson.title)){skipped.push({id:lesson&&lesson.id||null,reason:'no title'});continue;}
  if(lesson.status!=='reviewed'&&!o.includeDrafts){skipped.push({id:lesson.id,reason:'not reviewed'});continue;}
  const item=buildItem(lesson,o);
  if(seen.has(item.id)){skipped.push({id:lesson.id,reason:'duplicate story id'});continue;}
  seen.add(item.id);items.push(item);
 }
 return {schema:SCHEMA,generated:o.now||new Date().toISOString(),target:{theme:o.theme,parent:o.parent,area:o.area},items,skipped};
}
// Reads the key: value lines of the first halyard-meta fence. Returns null when there is none.
function parseMeta(body){
 const m=String(body||'').match(/~~~halyard-meta\r?\n([\s\S]*?)\r?\n~~~/);if(!m)return null;
 const out={};for(const line of m[1].split(/\r?\n/)){const i=line.indexOf(':');if(i>0)out[line.slice(0,i).trim()]=line.slice(i+1).trim();}
 return out;
}
// The file Halyard's Intake reads (Halyard docs/HANDOFF.md, "fleet-handoff" version 1): one item per reviewed lesson, with the
// lesson's id as the stable ref so importing the same export twice is recognised as already copied. Intake classifies the
// item, drafts its halyard-meta body, links back to the ref and leaves it for human review; nothing goes straight to a backlog.
const HANDOFF={format:'fleet-handoff',version:1,app:'eight-bells',maxItems:500,maxTitle:200,maxBody:20000};
function toHandoff(lessons,opts){
 const o=Object.assign({includeDrafts:false},opts||{}),items=[],skipped=[],seen=new Set();
 for(const lesson of Array.isArray(lessons)?lessons:[]){
  const ref=clean(lesson&&lesson.id),title=clean(lesson&&lesson.title).slice(0,HANDOFF.maxTitle);
  if(!lesson||!title){skipped.push({id:lesson&&lesson.id||null,reason:'no title'});continue;}
  if(!ref){skipped.push({id:null,reason:'no id'});continue;}
  if(lesson.status!=='reviewed'&&!o.includeDrafts){skipped.push({id:lesson.id,reason:'not reviewed'});continue;}
  if(seen.has(ref)){skipped.push({id:lesson.id,reason:'duplicate id'});continue;}
  if(items.length>=HANDOFF.maxItems){skipped.push({id:lesson.id,reason:'over the 500-item limit'});continue;}
  seen.add(ref);
  const text=String(lesson.body==null?'':lesson.body).trim()||'(no text)';
  const NL=String.fromCharCode(10),note=NL+NL+'Handed over from Eight Bells as a reviewed lesson learned'+(lesson.source?' (source log '+lesson.source+')':'')+'. Check it against the source evidence before acting.';
  items.push({ref,title,body:(text+note).slice(0,HANDOFF.maxBody),kind:'story',labels:['area::watchstanding']});
 }
 return {format:HANDOFF.format,version:HANDOFF.version,source:{app:HANDOFF.app,exportedAt:o.now||new Date().toISOString()},items,skipped};
}
return {SCHEMA,DEFAULTS,HANDOFF,exportLessons,toHandoff,parseMeta,storyId};
});
