// Captures the walkthrough screenshots (docs/assets/walkthrough/NN-<screen>.png) with Playwright Chromium (headless).
// Mock data only: run it against an isolated test server with an EMPTY store, never a real one:
//   $env:EIGHTBELLS_TEST_SESSION='1'; $env:EIGHTBELLS_TEST_DATA_DIR='<empty temp folder>'
//   powershell.exe -NoProfile -File .\Start-EightBells.ps1 -NoBrowser -Stay -Port 8774 -TestSessionToken synthetic-token
//   node docs/screenshots/capture-walkthrough.js http://127.0.0.1:8774 synthetic-token
// It follows docs/walkthrough/README.md step by step: first launch on the empty workspace, imports three synthetic
// fixtures from samples/, then Quality Assurance, Watch Turnover, Operational Memory (two lessons, one reviewed),
// the Command Center and AI & Diagnostics. 1440x900, sidebar expanded, Night watch (prefers-color-scheme dark).
'use strict';
const path=require('node:path');
const {chromium}=require('playwright');
const [base,token]=process.argv.slice(2);
if(!base||!token)throw Error('Usage: node capture-walkthrough.js <server-url> <test-session-token>');
const root=path.resolve(__dirname,'..','..');
const out=path.join(root,'docs','assets','walkthrough');
const samples=['engineering_discrepancy.txt','engineering_repetition.log','engineering_chronology.txt'];
const lessons=[
 {title:'Pump B vibration carried across turnover',source:'engineering_discrepancy.txt',review:true,
  body:'Lines 3–12: Pump B vibration above expected baseline from 1215; observation frequency increased at 1330; still open at 1600 turnover. Verified: incoming watch advised. Unknown: root cause and follow-up assessment.'},
 {title:'Copy-forward readings mask real trends',source:'engineering_repetition.log',review:false,
  body:'Loop A/B readings repeated verbatim across entries in the training log. Verified: QA flagged the repetition. Limitation: identical values may be legitimate; check source instruments.'}
];
(async()=>{
 const browser=await chromium.launch({headless:true});
 try{
  const context=await browser.newContext({viewport:{width:1440,height:900},deviceScaleFactor:1,colorScheme:'dark'});
  const page=await context.newPage();
  page.on('dialog',d=>d.accept());
  const shoot=async name=>{await page.evaluate(()=>document.activeElement&&document.activeElement.blur());await page.mouse.move(0,0);await page.waitForTimeout(300);await page.screenshot({path:path.join(out,name)});};
  const nav=async view=>{await page.click('button.nav-btn[data-view="'+view+'"]');await page.evaluate(()=>{document.querySelector('.scroll-area').scrollTop=0;});};
  const toBottom=()=>page.evaluate(()=>{const s=document.querySelector('.scroll-area');s.scrollTop=s.scrollHeight;});
  const notice=text=>page.waitForFunction(t=>document.getElementById('notice').textContent.includes(t),text);
  const logId=name=>page.evaluate(n=>{const o=[...document.querySelectorAll('#qualityLog option')].find(x=>x.textContent.startsWith(n+' '));return o&&o.value;},name);
  await page.goto(base.replace(/\/$/,'')+'/#token='+token);
  await notice('synchronized');
  await page.waitForFunction(()=>document.getElementById('engineState').classList.contains('engine-running'));
  if(await page.textContent('#metricLogs')!=='0')throw Error('The test store is not empty; start the server on an empty EIGHTBELLS_TEST_DATA_DIR.');
  // 1. First launch: the empty workspace.
  await shoot('01-first-launch.png');
  // 2. Import logs, then load one more file to show its extraction preview next to the source library.
  for(const file of samples){
   await nav('ingest');
   // Clear the previous file's text first: waiting for any text would otherwise pass before the new file loads.
   await page.fill('#logText','');
   await page.setInputFiles('#importFile',path.join(root,'samples',file));
   await page.waitForFunction(()=>document.getElementById('logText').value.length>0);
   await page.selectOption('#watchType','Engineering');
   await page.click('#analyzeBtn');
   await notice('import completed');
  }
  await nav('ingest');
  await page.fill('#logText','');
  await page.setInputFiles('#importFile',[]);
  await page.setInputFiles('#importFile',path.join(root,'samples',samples[2]));
  await page.waitForFunction(()=>document.getElementById('logText').value.length>0);
  await toBottom();
  await shoot('02-ingest.png');
  // 3. Quality: the discrepancy log and its first finding.
  const disc=await logId(samples[0]);
  await nav('quality');
  await page.selectOption('#qualityLog',disc);
  await page.click('#qualityFindings [data-finding]');
  await shoot('03-quality.png');
  // 4. Turnover draft for the same log.
  await nav('turnover');
  await page.selectOption('#turnLog',disc);
  await page.click('#generateTurn');
  await notice('Turnover draft generated');
  await shoot('04-turnover.png');
  // 5. Memory: two lessons from the samples, the first one marked reviewed.
  await nav('memory');
  for(const l of lessons){
   await page.fill('#lessonTitle',l.title);
   await page.selectOption('#lessonSource',await logId(l.source));
   await page.fill('#lessonBody',l.body);
   await page.click('#lessonSave');
   await notice('Memory draft encrypted');
   if(l.review){await page.click('#lessonList [data-review-lesson]');await notice('Lesson marked reviewed');}
  }
  await toBottom();
  await shoot('05-memory.png');
  // 6. Command Center with the imported logs.
  await nav('overview');
  await shoot('06-command-center.png');
  // 7. AI & Diagnostics with AI off.
  await nav('settings');
  await page.waitForFunction(()=>document.getElementById('diagOutput').textContent.startsWith('STORAGE'));
  await shoot('07-settings.png');
  await context.close();
 }finally{await browser.close();}
})().catch(err=>{console.error(err);process.exit(1)});
