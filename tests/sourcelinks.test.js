'use strict';
const assert=require('assert');
const S=require('../web/sourcelinks.js'),E=require('../web/engine.js');
// Real turnover text from the engine: every reference it writes becomes a button, and nothing else changes.
const log={id:'t1',name:'T',watch:'Engineering',imported:'2026-11-04T00:00:00Z',entries:[
 {line:1,time:'08:00',text:'0800 Assumed watch. Prior log noted Pump B vibration for follow-up.',issue:true,resolution:false},
 {line:2,time:'08:15',text:'0815 Pump B abnormal vibration observed.',issue:true,resolution:false}]};
log.analysis=E.analyze(log.entries);
const text=E.turnover(log),html=S.linkRefs(text);
assert((html.match(/class="src-ref"/g)||[]).length>=3,'Observation lines, open conditions and quality lines are linked');
assert(/^Line <button[^>]*data-line="1"[^>]*>1<\/button> \|/m.test(html),'An observation line links its line number');
assert(/\(source line <button[^>]*data-line="2"/.test(html),'An open-condition reference is linked');
// Inverse of linkRefs: drop only the buttons it inserts, then decode the entities it wrote.
// A general /<[^>]*>/ strip can leave a <script behind; that is not the property this check proves.
function undo(html){
 return html.replace(/<button type="button" class="src-ref" data-line="(\d+)" title="Show source line \1">\1<\/button>/g,'$1')
  .replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&amp;/g,'&');
}
const back=undo(html);
assert.strictEqual(back,text,'Stripping the buttons gives back exactly the draft text');
assert.strictEqual(undo(S.linkRefs('Line 9 | <script>alert(1)</script> <!--kept-->')),'Line 9 | <script>alert(1)</script> <!--kept-->','Escaped script and comment text round-trips');
// Hostile text is escaped, never run.
const evil=S.linkRefs('Line 3 | <img src=x onerror=alert(1)> (source line 4)');
assert(!/<img/.test(evil)&&evil.includes('&lt;img'),'Markup in a log line is escaped');
assert.strictEqual(S.linkRefs('[lines 3, 4, 6]').match(/data-line/g).length,3,'A list of lines links each number');
assert.strictEqual(S.linkRefs(null),'','No text gives no output');
assert.deepStrictEqual(S.sourceRows(log).map(r=>r.line),[1,2],'The source panel has every line');
assert.deepStrictEqual(S.sourceRows(null),[],'No log gives no rows');
console.log('PASS: turnover line references link to source lines (real engine text, escaping, plain text preserved)');
