(function(){
'use strict';
const E=window.EightBellsEngine;
const L=window.EightBellsLifecycle;
const el=id=>document.getElementById(id);
const escapeHTML=s=>String(s==null?'':s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const array=x=>Array.isArray(x)?x:x?[x]:[];
let token=(location.hash.match(/(?:^#|&)token=([^&]+)/)||[])[1]||'';
let state={logs:[],lessons:[],reviews:[],audit:[]},chosenFinding=null,chosenLog=null,previewUrl=null;
const shell=window.EightBellsShell||{setEngine(){},setSession(){}};
function notify(message,error){el('notice').textContent=message;el('notice').classList.toggle('is-error',!!error);}
async function api(path,data){
 if(!token)throw Error('No launch session token. Start Eight Bells with Launch-EightBells.bat.');
 const res=await fetch(path,{method:data===undefined?'GET':'POST',headers:{'X-EightBells-Token':token,'Content-Type':'application/json'},body:data===undefined?undefined:JSON.stringify(data),cache:'no-store'});
 const payload=await res.json();
 if(!res.ok)throw Error(payload.error||'Request failed ('+res.status+')');
 return payload;
}
function bind(id,event,handler){el(id).addEventListener(event,handler);}
function visit(name){
 document.querySelectorAll('.view').forEach(x=>x.classList.toggle('active',x.id===name));
 document.querySelectorAll('.nav-btn').forEach(x=>{const on=x.dataset.view===name;x.classList.toggle('active',on);if(on)x.setAttribute('aria-current','page');else x.removeAttribute('aria-current');});
 const labels={overview:'Command Center',ingest:'Ingestion Studio',quality:'Quality Assurance',turnover:'Watch Turnover',memory:'Operational Memory',settings:'AI & Diagnostics'};
 el('pageTitle').textContent=labels[name]||name;el('breadcrumb').textContent=(labels[name]||name).toUpperCase();
 if(name==='settings')refreshDiagnostics();
}
document.addEventListener('click',ev=>{
 let button=ev.target.closest('[data-view],[data-nav]');
 if(button){visit(button.dataset.view||button.dataset.nav);}
 const finding=ev.target.closest('[data-finding]');
 if(finding){chosenFinding={logId:finding.dataset.log,findId:finding.dataset.finding};renderFinding();}
 const source=ev.target.closest('[data-source]');
 if(source){chosenLog=source.dataset.source;el('qualityLog').value=chosenLog;el('turnLog').value=chosenLog;renderQuality();visit('quality');}
 const sig=ev.target.closest('[data-signal]');
 if(sig){chosenLog=sig.dataset.signal;el('qualityLog').value=chosenLog;renderQuality();visit('quality');}
 const candidate=ev.target.closest('[data-candidate]');
 if(candidate){let c=E.candidates(state.logs)[Number(candidate.dataset.candidate)];if(c){el('lessonTitle').value=c.title;el('lessonBody').value=c.description+' Evidence: '+c.evidence.map(x=>x.logId+' lines '+x.lines.join(',')).join('; ');el('lessonSource').value=c.evidence[0].logId;notify('Draft prepared; review evidence and save.');}}
 const lesson=ev.target.closest('[data-review-lesson]');
 if(lesson){markLesson(lesson.dataset.reviewLesson);}
});
function opts(){const options=state.logs.map(l=>'<option value="'+escapeHTML(l.id)+'">'+escapeHTML(l.name)+' · '+escapeHTML(l.watch)+'</option>').join('');
 for(const id of ['qualityLog','turnLog']){const old=el(id).value;el(id).innerHTML=options;el(id).value=(state.logs.find(x=>x.id===old)?old:(chosenLog||state.logs[0]?.id||''));}
 const prev=el('lessonSource').value;el('lessonSource').innerHTML='<option value="">General knowledge</option>'+options;el('lessonSource').value=prev;
}
function render(){
 state.logs=array(state.logs);state.lessons=array(state.lessons);state.reviews=array(state.reviews);state.audit=array(state.audit);
 el('metricLogs').textContent=state.logs.length;
 // An empty workspace opens on the welcome panel (emblem and one action) in place of two empty panels.
 el('welcome').hidden=state.logs.length>0;
 document.querySelector('#overview .twocol').hidden=state.logs.length===0;
 el('metricFlags').textContent=state.logs.reduce((n,l)=>n+array(l.analysis?.findings).length,0);
 el('metricOpen').textContent=state.logs.reduce((n,l)=>n+array(l.analysis?.open).length,0);
 el('metricLessons').textContent=state.lessons.length;
 const recent=state.logs.slice().reverse().slice(0,8);
 el('recentLogs').innerHTML=recent.map(l=>'<button class="row-item" data-source="'+escapeHTML(l.id)+'"><b>'+escapeHTML(l.name)+'</b><small>'+escapeHTML(l.watch)+' · '+new Date(l.imported).toLocaleString()+' · '+array(l.entries).length+' events</small></button>').join('')||'<p class="hint">No sources yet. Import a synthetic training log to start.</p>';
 const signal=state.logs.slice().reverse().filter(l=>array(l.analysis?.findings).length).slice(0,6);
 el('signals').innerHTML=signal.map(l=>'<button class="row-item flag" data-signal="'+escapeHTML(l.id)+'"><b>'+escapeHTML(l.name)+'</b><small>'+array(l.analysis.findings).length+' review observations · advisory only</small></button>').join('')||'<p class="hint">No heuristic findings have been recorded.</p>';
 opts();renderSources();renderQuality();renderMemory();
}
async function refresh(){state=await api('/api/state');render();notify('Workspace synchronized');}
function renderSources(){
 const q=el('sourceSearch').value.toLowerCase();
 el('sourceList').innerHTML=state.logs.slice().reverse().filter(l=>(l.name+' '+l.watch).toLowerCase().includes(q)).map(l=>'<button data-source="'+escapeHTML(l.id)+'" class="row-item"><b>'+escapeHTML(l.name)+'</b><small>'+escapeHTML(l.format)+' · '+array(l.entries).length+' parsed entries · '+array(l.analysis?.findings).length+' findings</small></button>').join('')||'<p class="hint">No matching sources.</p>';
}
function getLog(id){return state.logs.find(l=>l.id===id);}
function renderQuality(){
 const l=getLog(el('qualityLog').value);if(!l){el('qualitySummary').textContent='Import a log to review its quality.';el('qualityFindings').innerHTML='';renderFinding();return;}
 const f=array(l.analysis?.findings),open=array(l.analysis?.open);
 el('qualitySummary').textContent=f.length+' advisory findings · '+open.length+' potential open conditions · Quality heuristic '+(l.analysis?.score??'—')+'/100';
 el('qualityFindings').innerHTML=f.map(x=>{
 const reviews=state.reviews.filter(r=>r.logId===l.id&&r.findingId===x.id);
 return '<button class="row-item flag" data-finding="'+escapeHTML(x.id)+'" data-log="'+escapeHTML(l.id)+'"><b>'+escapeHTML(x.type)+' <span class="pill warn fl-badge">'+escapeHTML(x.priority)+'</span></b><p>'+escapeHTML(x.detail)+'</p><small>Source lines '+escapeHTML(array(x.lines).join(', '))+' · '+reviews.length+' reviews</small></button>';
 }).join('')||'<p class="hint">No heuristic findings. This is not proof of completeness.</p>';
 renderFinding();
}
function renderFinding(){
 const l=getLog(chosenFinding?.logId),f=array(l?.analysis?.findings).find(x=>x.id===chosenFinding?.findId);
 if(!f){el('selectedFinding').textContent='Select a quality finding to inspect evidence.';el('reviewHistory').innerHTML='';return;}
 const evidence=array(l.entries).filter(e=>array(f.lines).includes(e.line));
 el('selectedFinding').innerHTML='<b>'+escapeHTML(f.type)+'</b><p>'+escapeHTML(f.detail)+'</p><div class="stack">'+evidence.map(e=>'<div class="row-item"><small>Line '+e.line+' · '+escapeHTML(e.time||'Unknown time')+'</small><p>'+escapeHTML(e.text)+'</p></div>').join('')+'</div>';
 el('reviewHistory').innerHTML=state.reviews.filter(r=>r.logId===l.id&&r.findingId===f.id).slice().reverse().map(r=>'<div class="row-item"><b>'+escapeHTML(r.disposition)+'</b><p>'+escapeHTML(r.note)+'</p><small>'+escapeHTML(r.at)+'</small></div>').join('')||'<p class="hint">No reviewer notes yet.</p>';
}
async function reviewFinding(){
 if(!chosenFinding)throw Error('Select a finding');
 const note=el('reviewNote').value.trim();if(!note)throw Error('A reviewer explanation is required.');
 await api('/api/review',{logId:chosenFinding.logId,findingId:chosenFinding.findId,disposition:el('disposition').value,note});
 el('reviewNote').value='';await refresh();notify('Review recorded without modifying source.');
}
function renderMemory(){
 let q=el('memorySearch').value.toLowerCase();
 const docs=[...state.lessons.map(l=>({title:l.title,content:l.body,source:'Lesson '+l.status})),...state.logs.map(l=>({title:l.name,content:l.content,source:'Log source'}))];
 el('memoryResults').innerHTML=docs.filter(d=>!q||(d.title+' '+d.content).toLowerCase().includes(q)).slice(0,12).map(d=>'<div class="row-item"><b>'+escapeHTML(d.title)+'</b><small>'+escapeHTML(d.source)+'</small><p>'+escapeHTML(d.content.slice(0,160))+'</p></div>').join('')||'<p class="hint">No matches in encrypted local records.</p>';
 const candidates=E.candidates(state.logs);
 el('memoryCandidates').innerHTML=candidates.map((c,i)=>'<button class="row-item" data-candidate="'+i+'"><b>'+escapeHTML(c.title)+'</b><p>'+escapeHTML(c.description)+'</p><small>'+c.evidence.length+' source records · Click to draft lesson</small></button>').join('')||'<p class="hint">No recurring candidates across at least two imported logs.</p>';
 el('lessonList').innerHTML=state.lessons.slice().reverse().map(l=>'<div class="row-item"><b>'+escapeHTML(l.title)+' <span class="pill fl-badge">'+escapeHTML(l.status)+'</span></b><p>'+escapeHTML(l.body)+'</p><small>Source: '+escapeHTML(l.source||'General')+'</small> '+(l.status==='draft'?'<button class="outline small fl-btn fl-btn--secondary" data-review-lesson="'+escapeHTML(l.id)+'">Mark reviewed</button>':'')+'</div>').join('')||'<p class="hint">Create a human-reviewed lesson from source evidence.</p>';
}
async function markLesson(id){if(!confirm('Mark lesson locally reviewed? This is not an authenticated command approval.'))return;try{await api('/api/lesson/review',{id});await refresh();notify('Lesson marked reviewed.')}catch(e){notify(e.message,true);}}
function viewPreview(){
 const text=el('logText').value,fmt=el('format').value;
 try{
  let p=E.parse(text,fmt),a=E.analyze(p.entries,{intervalMinutes:Number(el('interval').value)});
  el('previewStatus').textContent=p.entries.length+' entries · '+a.findings.length+' advisory findings · format: '+p.format;
  el('previewEntries').innerHTML=p.entries.slice(0,10).map(e=>'<div class="row-item"><small>Line '+e.line+' · '+escapeHTML(e.time||'Unspecified time')+' · '+escapeHTML(e.equipment||'No entity')+'</small><p>'+escapeHTML(e.text)+'</p></div>').join('');
  return {parsed:p,analysis:a};
 }catch(e){el('previewStatus').textContent=e.message;el('previewEntries').innerHTML='';return null;}
}
async function importLog(){
 const content=el('logText').value.trim(),name=el('logName').value.trim();
 if(!name||!content)throw Error('Provide a title and verified text.');
 const r=viewPreview();if(!r)throw Error('Correct source parsing errors before importing.');
 const file=el('importFile').files[0];
 await api('/api/import',{name,watch:el('watchType').value,content,sourceType:file&&/image|pdf/.test(file.type)?'manual-transcription':'digital-text',format:r.parsed.format,entries:r.parsed.entries,analysis:r.analysis});
 await refresh();visit('overview');notify('Encrypted log import completed.');
}
async function chooseFile(){
 const file=el('importFile').files[0];if(!file)return;
 el('logName').value=file.name;
 if(previewUrl){URL.revokeObjectURL(previewUrl);previewUrl=null;}
 el('previewWrap').classList.add('hidden');el('visionActions').classList.add('hidden');el('visionConsent').checked=false;
 const image=/^image\//.test(file.type)||/\.(png|jpg|jpeg|webp|tif|tiff)$/i.test(file.name);
 const pdf=/\.pdf$/i.test(file.name);
 if(image){previewUrl=URL.createObjectURL(file);el('imagePreview').src=previewUrl;el('previewWrap').classList.remove('hidden');el('visionActions').classList.remove('hidden');el('logText').value='';notify('Image preview ready. Enter a verified transcript; no OCR is claimed.');}
 else if(pdf){el('logText').value='';notify('PDF requires manual text transcription in this build.',true);}
 else{if(file.size>1500000)throw Error('File exceeds the 1.5MB text limit.');el('logText').value=await file.text();notify('Text file loaded for verification.');}
 viewPreview();
}
async function transcribeVision(){
 const file=el('importFile').files[0];
 if(!file||!file.type.startsWith('image/'))throw Error('Choose an image file first.');
 if(!['image/png','image/jpeg','image/webp'].includes(file.type))throw Error('For AI vision, choose PNG, JPEG, or WebP.');
 if(file.size>2000000)throw Error('Vision image must be less than 2MB.');
 if(!el('visionConsent').checked)throw Error('Consent is required for each image sent to a model.');
 const dataUrl=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=()=>reject(Error('Cannot read image'));reader.readAsDataURL(file);});
 try{
  notify('Transcribing with approved vision model. Review every line before importing.');
  const result=await api('/api/vision',{mime:file.type,base64:dataUrl.split(',')[1],consent:true});
  el('logText').value=result.text;
  el('format').value='text';viewPreview();
  notify('Unverified AI transcription received; inspect and correct before import.');
 }finally{el('visionConsent').checked=false;}
}
async function saveLesson(){
 let title=el('lessonTitle').value.trim(),body=el('lessonBody').value.trim();
 if(!title||!body)throw Error('Lesson title and evidence explanation required.');
 await api('/api/lesson',{title,body,source:el('lessonSource').value});
 el('lessonTitle').value='';el('lessonBody').value='';await refresh();notify('Memory draft encrypted locally.');
}
function selectedTurn(){return getLog(el('turnLog').value);}
function generateTurn(){const l=selectedTurn();if(!l)throw Error('Select a source log');el('turnText').textContent=E.turnover(l);notify('Turnover draft generated; requires source verification.');}
function download(name,data,mime){
 const url=URL.createObjectURL(new Blob([data],{type:mime||'text/plain'}));
 const a=document.createElement('a');a.href=url;a.download=name;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
async function configureAI(clear){
 let data=clear?{endpoint:'',model:'',key:''}:{endpoint:el('endpoint').value.trim(),model:el('model').value.trim(),key:el('aiKey').value,useVault:el('aiVault').checked};
 await api('/api/ai/config',data);el('aiKey').value='';notify(clear?'AI configuration cleared.':'AI session provider configured.');
}
async function runAI(){
 const l=selectedTurn();if(!l)throw Error('Select a source log');
 if(!el('aiConsent').checked)throw Error('Per-request AI transmission authorization required.');
 el('aiText').textContent='Contacting configured AI endpoint…';
 try{const r=await api('/api/ai/run',{logId:l.id,consent:true});el('aiText').textContent='UNVERIFIED AI DRAFT · '+r.model+'\n\n'+r.text;notify('AI draft received and marked unverified.');}
 finally{el('aiConsent').checked=false;}
}
async function refreshDiagnostics(){
 try{const d=await api('/api/diagnostics');el('diagOutput').textContent='STORAGE: '+d.storage+'\nAI CONFIGURED: '+d.aiConfigured+'\n\n'+array(d.lines).join('\n');}
 catch(e){el('diagOutput').textContent='Diagnostics unavailable: '+e.message;}
}
function safe(fn){return async()=>{try{await fn();}catch(e){notify(e.message,true);}};}
bind('reloadBtn','click',safe(refresh));bind('importFile','change',safe(chooseFile));bind('visionTranscribe','click',safe(transcribeVision));bind('analyzeBtn','click',safe(importLog));
bind('logText','input',viewPreview);bind('format','change',viewPreview);bind('interval','change',viewPreview);
bind('sourceSearch','input',renderSources);bind('qualityLog','change',()=>{chosenFinding=null;renderQuality();});
bind('reviewBtn','click',safe(reviewFinding));bind('memorySearch','input',renderMemory);
bind('lessonSave','click',safe(saveLesson));
bind('generateTurn','click',safe(generateTurn));
bind('copyTurn','click',safe(async()=>{await navigator.clipboard.writeText(el('turnText').textContent);notify('Turnover copied to clipboard.');}));
bind('saveTurn','click',safe(async()=>{download('EightBells-turnover.txt',el('turnText').textContent,'text/plain');}));
bind('exportBtn','click',safe(async()=>{if(!confirm('Export all local training records to UNENCRYPTED JSON?'))return;download('EightBells-export.json',JSON.stringify(state,null,2),'application/json');}));
bind('aiConfig','click',safe(()=>configureAI(false)));bind('aiClear','click',safe(()=>configureAI(true)));
bind('runAi','click',safe(runAI));bind('diagRefresh','click',safe(refreshDiagnostics));
// The open tab owns the server: it stops itself shortly after the last tab closes (see lifecycle.js).
let stopHeartbeat=function(){};
async function endSession(){
 if(!confirm('End this Eight Bells session? The local server stops; reopen it with Launch-EightBells.bat.'))return;
 stopHeartbeat();
 try{await api('/api/shutdown',{});}
 catch(e){stopHeartbeat=beat();throw e;}
 document.querySelectorAll('#endSession,#shutdown').forEach(b=>{b.disabled=true;});
 shell.setEngine('stopped');shell.setSession('Session ended');
 notify('Session ended; the server has stopped. You can close this tab.');
}
bind('shutdown','click',safe(endSession));bind('endSession','click',safe(endSession));
// Status bar: the heartbeat reports whether the engine answers; without a token only /health can be asked.
function beat(){return L.startHeartbeat({token,onStatus:ok=>shell.setEngine(ok?'running':'disconnected')});}
if(!token){
 notify('Session token missing. Launch via Launch-EightBells.bat rather than manually typing localhost.',true);
 shell.setSession('No session token');
 fetch('/health',{cache:'no-store'}).then(r=>shell.setEngine(r.ok?'running':'disconnected'),()=>shell.setEngine('disconnected'));
}
else{stopHeartbeat=beat();shell.setSession('Session active');refresh().catch(e=>notify('Cannot load state: '+e.message,true));}
})();