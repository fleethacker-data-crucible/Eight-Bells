'use strict';
const assert=require('assert');
const fs=require('fs');
const path=require('path');
const {spawnSync}=require('child_process');
const root=path.join(__dirname,'..');
const iconsPath=path.join(root,'web','icons.js');
const before=fs.readFileSync(iconsPath,'utf8');
(async()=>{
 const {stripHtmlComments,svgInner}=await import('../tools/gen-icons.mjs');
 assert.strictEqual(fs.readFileSync(iconsPath,'utf8'),before,'Importing the generator does not rewrite web/icons.js');
 assert.strictEqual(stripHtmlComments('a <!-- c --> b'),'a  b','A closed comment is removed');
 assert.strictEqual(stripHtmlComments('a<!--b-->c<!--d-->e'),'ace','Every comment is removed');
 assert.strictEqual(stripHtmlComments('<!<!--xxxx-->--'),'','A comment spliced back together is removed too');
 assert.strictEqual(stripHtmlComments('keep <!-- unclosed tail'),'keep ','An unclosed comment consumes the rest');
 assert.ok(!stripHtmlComments('<!<!--xxxx-->--<path/>').includes('<!--'),'No comment start remains');
 // The license header Lucide 1.54.0 writes above each icon, then the power icon body.
 const power=`<!-- @license lucide-static v1.54.0 - ISC -->
<svg
  class="lucide lucide-power"
  xmlns="http://www.w3.org/2000/svg"
  width="24"
  height="24"
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width="2"
  stroke-linecap="round"
  stroke-linejoin="round"
>
  <path d="M12 2v10" />
  <path d="M18.4 6.6a9 9 0 1 1-12.77.04" />
</svg>
`;
 const inner=svgInner(power);
 assert.strictEqual(inner,'<path d="M12 2v10" /><path d="M18.4 6.6a9 9 0 1 1-12.77.04" />','The power icon inner markup is unchanged');
 assert.ok(before.includes(JSON.stringify(inner)),'That markup is the string already committed in web/icons.js');
 const ran=spawnSync(process.execPath,[path.join(root,'tools','gen-icons.mjs')],{encoding:'utf8'});
 assert.strictEqual(ran.status,1,'The generator still requires an icons directory');
 assert.match(ran.stderr,/usage: node tools\/gen-icons\.mjs/);
 assert.strictEqual(fs.readFileSync(iconsPath,'utf8'),before,'A usage failure does not rewrite web/icons.js');
 console.log('PASS: icon comment stripping removes spliced comments and keeps Lucide inner markup');
})().catch(e=>{console.error(e);process.exit(1);});
