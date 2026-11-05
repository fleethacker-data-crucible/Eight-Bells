/* Eight Bells: turn the line references in a turnover draft into buttons that open the source line.
   linkRefs(text) returns safe HTML (the text is escaped first); sourceRows(log) returns the log's lines for the source panel.
   No network and no dependencies; the plain text of the draft (copy, save, read aloud) is unchanged. */
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.EightBellsSourceLinks=api;})(typeof globalThis!=='undefined'?globalThis:this,function(){
"use strict";
const esc=s=>String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
const btn=n=>'<button type="button" class="src-ref" data-line="'+n+'" title="Show source line '+n+'">'+n+'</button>';
// Recognised references, exactly as the turnover generator writes them: "Line 3 | ...", "(source line 10)" and "[lines 3, 4, 6]".
function linkRefs(text){
 return String(text==null?'':text).split('\n').map(line=>esc(line)
  .replace(/^(Line )(\d+)( \|)/,(m,a,n,b)=>a+btn(n)+b)
  .replace(/\(source line (\d+)\)/g,(m,n)=>'(source line '+btn(n)+')')
  .replace(/\[lines ([0-9, ]+)\]/g,(m,nums)=>'[lines '+nums.replace(/\d+/g,btn)+']')).join('\n');
}
function sourceRows(log){
 return (log&&Array.isArray(log.entries)?log.entries:[]).map(e=>({line:Number(e.line),time:e.time||'',text:String(e.text==null?'':e.text)}));
}
return {linkRefs,sourceRows};
});
