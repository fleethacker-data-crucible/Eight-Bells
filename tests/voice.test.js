'use strict';
const assert=require('assert');
const V=require('../web/voice.js');

// ---- chunking ----
assert.deepStrictEqual(V.chunk('Line one\n\n  Line   two  \r\nLine three'),['Line one','Line two','Line three'],'Blank lines drop, spaces collapse, order is kept');
assert.deepStrictEqual(V.chunk(''),[]);
assert.deepStrictEqual(V.chunk(null),[]);
const longText=('word '.repeat(120)).trim();
const parts=V.chunk(longText,50);
assert(parts.every(p=>p.length<=50)&&parts.length>5,'Long lines are cut to the limit');
assert.strictEqual(parts.join(' '),longText,'Nothing is lost when cutting');
assert(V.chunk('x'.repeat(130),50).every(p=>p.length<=50),'A word longer than the limit is still cut');

// ---- fakes ----
function fakeEnv(o){
 o=o||{};const spoken=[];let cancels=0;
 const voices=o.voices||[{name:'Online Voice',lang:'en-US',localService:false},{name:'Local US',lang:'en-US',localService:true,default:true},{name:'Local GB',lang:'en-GB',localService:true}];
 const env={
  voiceWaitMs:0,
  speechSynthesis:o.noSynth?undefined:{getVoices:()=>voices,cancel:()=>{cancels++;},speak:u=>{spoken.push(u);if(o.failAt!=null&&spoken.length===o.failAt+1)setTimeout(()=>u.onerror({error:'synthesis-failed'}),0);else setTimeout(()=>u.onend(),0);}},
  SpeechSynthesisUtterance:o.noSynth?undefined:function(text){this.text=text;}
 };
 return {env,spoken,cancels:()=>cancels};
}
(async()=>{
 // ---- support ----
 let f=fakeEnv({noSynth:true});
 assert.deepStrictEqual(V.create(f.env).support(),{speak:false,dictate:false});
 // ---- speak: refuses without speech output ----
 let r=await V.create(f.env).speak('Hello');
 assert.strictEqual(r.ok,false);assert.strictEqual(r.message,V.MESSAGES.noSpeech);
 // ---- speak: nothing to read ----
 f=fakeEnv();r=await V.create(f.env).speak('  \n ');
 assert.strictEqual(r.ok,false);assert.strictEqual(r.message,V.MESSAGES.nothing);assert.strictEqual(f.spoken.length,0);
 // ---- speak: only online voices are refused, nothing is spoken ----
 f=fakeEnv({voices:[{name:'Online Voice',lang:'en-US',localService:false}]});
 r=await V.create(f.env).speak('WATCH TURNOVER');
 assert.strictEqual(r.ok,false);assert.strictEqual(r.message,V.MESSAGES.noLocalVoice);assert.strictEqual(f.spoken.length,0,'No text may reach an online voice');
 // ---- speak: local voice, chunks in order, default voice preferred ----
 f=fakeEnv();r=await V.create(f.env).speak('Line 1 | Pump B\nLine 2 | Supervisor notified');
 assert.strictEqual(r.ok,true);assert.strictEqual(r.chunks,2);assert.strictEqual(r.voice,'Local US');
 assert.deepStrictEqual(f.spoken.map(u=>u.text),['Line 1 | Pump B','Line 2 | Supervisor notified']);
 assert(f.spoken.every(u=>u.voice.localService===true),'Only on-device voices are used');
 assert.strictEqual(f.cancels(),1,'Earlier speech is cancelled before a new read');
 // ---- speak: language choice among local voices ----
 f=fakeEnv();r=await V.create(f.env).speak('Hello',{lang:'en-GB'});
 assert.strictEqual(r.voice,'Local GB');
 // ---- speak: an error ends the read with a message ----
 f=fakeEnv({failAt:0});r=await V.create(f.env).speak('One\nTwo');
 assert.strictEqual(r.ok,false);assert(/synthesis-failed/.test(r.message));assert.strictEqual(f.spoken.length,1,'Reading stops after an error');
 // ---- stop ----
 f=fakeEnv();V.create(f.env).stop();assert.strictEqual(f.cancels(),1);

 // ---- dictation ----
 function recEnv(o){
  o=o||{};const made=[];
  function Rec(){this.started=false;this.stopped=false;if(!o.noLocal)this.processLocally=false;made.push(this);}
  Rec.prototype.start=function(){if(o.startThrows)throw Error('already started');this.started=true;};
  Rec.prototype.stop=function(){this.stopped=true;if(this.onend)this.onend();};
  return {env:{SpeechRecognition:Rec},made};
 }
 let d=V.create({}).dictate({consent:true});
 assert.strictEqual(d.ok,false);assert.strictEqual(d.message,V.MESSAGES.noDictation,'No recognition at all');
 let e=recEnv();d=V.create(e.env).dictate({});
 assert.strictEqual(d.ok,false);assert.strictEqual(d.message,V.MESSAGES.needConsent,'Consent is required each time');
 assert.strictEqual(e.made.length,0,'No microphone object is created without consent');
 e=recEnv({noLocal:true});d=V.create(e.env).dictate({consent:true});
 assert.strictEqual(d.ok,false);assert.strictEqual(d.message,V.MESSAGES.noDictation,'Online-only recognition is refused');
 assert.strictEqual(e.made[0].started,false,'Online-only recognition is never started');
 assert.deepStrictEqual(V.create(e.env).support(),{speak:false,dictate:false});
 e=recEnv();assert.deepStrictEqual(V.create(e.env).support(),{speak:false,dictate:true});

 e=recEnv();const got=[],errs=[];let ended=0;
 d=V.create(e.env).dictate({consent:true,lang:'en-GB',onText:t=>got.push(t),onError:m=>errs.push(m),onEnd:()=>ended++});
 const rec=e.made[0];
 assert.strictEqual(d.ok,true);assert.strictEqual(rec.started,true);
 assert.strictEqual(rec.processLocally,true,'Recognition is set to run on the device');
 assert.strictEqual(rec.continuous,true);assert.strictEqual(rec.interimResults,false);assert.strictEqual(rec.lang,'en-GB');
 rec.onresult({resultIndex:0,results:[Object.assign([{transcript:'  0800  watch assumed '}],{isFinal:true}),Object.assign([{transcript:'partial'}],{isFinal:false})]});
 assert.deepStrictEqual(got,['0800 watch assumed'],'Only final results are used, with spaces tidied');
 rec.onerror({error:'not-allowed'});rec.onerror({error:'language-not-supported'});rec.onerror({error:'weird'});
 assert(/Microphone access was refused/.test(errs[0])&&/speech pack/.test(errs[1])&&/weird/.test(errs[2]));
 d.stop();assert.strictEqual(rec.stopped,true);assert.strictEqual(ended,1);

 e=recEnv({startThrows:true});d=V.create(e.env).dictate({consent:true});
 assert.strictEqual(d.ok,false);assert(/could not start/.test(d.message));
 console.log('PASS: voice (chunking, on-device voices only, refusal messages, consent, local-only dictation, errors, stop)');
})().catch(err=>{console.error(err);process.exit(1);});
