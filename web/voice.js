/* Eight Bells voice: read the turnover aloud and dictate log text with the browser's own speech features.
   Local only: speech out uses on-device voices (localService), and dictation requires the browser to recognise speech
   on the device (SpeechRecognition.processLocally). Online voices and online recognition would send the text or the
   audio to a cloud service, so they are refused with a message that says what to do instead. No dependencies. */
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.EightBellsVoice=api;})(typeof globalThis!=='undefined'?globalThis:this,function(){
"use strict";
const MESSAGES={
 noSpeech:'Read aloud is not available: this browser has no speech output. Use Copy or Save TXT, or Windows Narrator.',
 noLocalVoice:'Read aloud needs an on-device voice, and this browser lists only online voices, which would send the text to a cloud service. Install a Windows voice (Settings, Time and language, Speech) or use Narrator.',
 noDictation:'Dictation is not available: this browser cannot recognise speech on the device, and online recognition would send audio to a cloud service, which Eight Bells does not use. Type or paste the log, or use Windows voice typing (Win+H) after checking its privacy setting.',
 needConsent:'Dictation needs your approval each time. Tick the box first.',
 nothing:'Nothing to read yet. Generate the draft first.'
};
const clean=s=>String(s==null?'':s).replace(/\s+/g,' ').trim();
// Lines stay in order; a line longer than max is cut at spaces so each utterance is short enough to start quickly and stop cleanly.
function chunk(text,max){
 max=max||200;const out=[];
 for(const line of String(text==null?'':text).split(/\r?\n/)){
  let rest=clean(line);
  while(rest.length>max){let cut=rest.lastIndexOf(' ',max);if(cut<max/2)cut=max;out.push(rest.slice(0,cut).trim());rest=rest.slice(cut).trim();}
  if(rest)out.push(rest);
 }
 return out;
}
const ERRORS={'not-allowed':'Microphone access was refused. Allow the microphone for this page and try again.','service-not-allowed':'This browser blocked on-device speech recognition.','language-not-supported':'The on-device speech pack for this language is not installed.','no-speech':'No speech was heard.','audio-capture':'No microphone was found.'};
function create(env){
 env=env||(typeof globalThis!=='undefined'?globalThis:{});
 let recognition=null;
 const wait=ms=>new Promise(r=>setTimeout(r,ms));
 async function localVoices(synth){
  let voices=synth.getVoices?synth.getVoices():[];
  if(!voices.length)await wait(env.voiceWaitMs==null?800:env.voiceWaitMs),voices=synth.getVoices();
  return voices.filter(v=>v.localService===true);
 }
 function support(){
  const synth=env.speechSynthesis,Rec=env.SpeechRecognition||env.webkitSpeechRecognition;
  let local=false;try{local=!!Rec&&'processLocally' in new Rec();}catch(e){}
  return {speak:!!(synth&&env.SpeechSynthesisUtterance),dictate:local};
 }
 async function speak(text,opts){
  opts=opts||{};const synth=env.speechSynthesis,Utt=env.SpeechSynthesisUtterance;
  if(!synth||!Utt)return {ok:false,message:MESSAGES.noSpeech};
  const parts=chunk(text,opts.maxChunk);if(!parts.length)return {ok:false,message:MESSAGES.nothing};
  const local=await localVoices(synth);if(!local.length)return {ok:false,message:MESSAGES.noLocalVoice};
  const voice=(opts.lang&&local.find(v=>String(v.lang).toLowerCase().startsWith(String(opts.lang).toLowerCase())))||local.find(v=>v.default)||local[0];
  synth.cancel();
  return new Promise(resolve=>{
   let i=0;
   const next=()=>{
    if(i>=parts.length)return resolve({ok:true,chunks:parts.length,voice:voice.name});
    const u=new Utt(parts[i++]);u.voice=voice;u.lang=voice.lang;u.rate=opts.rate||1;
    u.onend=next;u.onerror=ev=>resolve({ok:false,message:ev&&ev.error==='canceled'?'Stopped.':'Speech stopped: '+((ev&&ev.error)||'error')});
    synth.speak(u);
   };
   next();
  });
 }
 function stop(){
  if(env.speechSynthesis)env.speechSynthesis.cancel();
  if(recognition){try{recognition.stop();}catch(e){}recognition=null;}
 }
 // opts: consent (must be true), lang, onText(finalText), onError(message), onEnd().
 function dictate(opts){
  opts=opts||{};
  if(opts.consent!==true)return {ok:false,message:MESSAGES.needConsent};
  const Rec=env.SpeechRecognition||env.webkitSpeechRecognition;
  if(!Rec)return {ok:false,message:MESSAGES.noDictation};
  let r;try{r=new Rec();}catch(e){return {ok:false,message:MESSAGES.noDictation};}
  if(!('processLocally' in r))return {ok:false,message:MESSAGES.noDictation};
  r.processLocally=true;r.continuous=true;r.interimResults=false;r.lang=opts.lang||'en-US';
  r.onresult=ev=>{for(let i=ev.resultIndex||0;i<ev.results.length;i++){const res=ev.results[i];if(res.isFinal){const t=clean(res[0].transcript);if(t&&opts.onText)opts.onText(t);}}};
  r.onerror=ev=>{if(opts.onError)opts.onError(ERRORS[ev&&ev.error]||'Dictation stopped: '+((ev&&ev.error)||'error'));};
  r.onend=()=>{if(recognition===r)recognition=null;if(opts.onEnd)opts.onEnd();};
  recognition=r;
  try{r.start();}catch(e){recognition=null;return {ok:false,message:'Dictation could not start: '+e.message};}
  return {ok:true,stop};
 }
 return {support,speak,stop,dictate};
}
return {MESSAGES,chunk,create};
});
