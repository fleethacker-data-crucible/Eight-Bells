// Captures the README landing-page screenshot (Command Center) with Playwright Chromium.
// Mock data only: run it against an isolated test server, never a real store:
//   $env:EIGHTBELLS_TEST_SESSION='1'; $env:EIGHTBELLS_TEST_DATA_DIR='<empty temp folder>'
//   powershell.exe -NoProfile -File .\Start-EightBells.ps1 -NoBrowser -Stay -Port 8774 -TestSessionToken synthetic-token
//   node docs/screenshots/capture-landing.js http://127.0.0.1:8774 synthetic-token
// It imports the synthetic fixtures from samples/ through the Ingestion Studio, then shoots
// the landing view at 1440x900. Eight Bells has one (dark) theme, so only Night watch is captured.
'use strict';
const path=require('node:path');
const {chromium}=require('playwright');
const [base,token]=process.argv.slice(2);
if(!base||!token)throw Error('Usage: node capture-landing.js <server-url> <test-session-token>');
const root=path.resolve(__dirname,'..','..');
const samples=[
 ['engineering_discrepancy.txt','Engineering'],
 ['engineering_repetition.log','Engineering'],
 ['engineering_chronology.txt','Engineering'],
 ['quarterdeck_watch.txt','Bridge / Quarterdeck'],
 ['damage_control_watch.txt','Damage Control'],
 ['security_patrol.txt','Security']
];
const url=base.replace(/\/$/,'')+'/#token='+token;
async function fresh(browser,colorScheme){
 const context=await browser.newContext({viewport:{width:1440,height:900},deviceScaleFactor:1,colorScheme});
 const page=await context.newPage();
 await page.goto(url);
 await page.waitForFunction(()=>document.getElementById('notice').textContent.includes('synchronized'));
 return {context,page};
}
(async()=>{
 const browser=await chromium.launch();
 try{
  const {context,page}=await fresh(browser,'dark');
  if(await page.textContent('#metricLogs')==='0'){
   for(const [file,watch] of samples){
    await page.click('button.nav-btn[data-view="ingest"]');
    await page.setInputFiles('#importFile',path.join(root,'samples',file));
    await page.waitForFunction(()=>document.getElementById('logText').value.length>0);
    await page.selectOption('#watchType',watch);
    await page.click('#analyzeBtn');
    await page.waitForFunction(()=>document.getElementById('notice').textContent.includes('import completed'));
   }
  }
  await context.close();
  const shot=await fresh(browser,'dark');
  await shot.page.mouse.move(0,0);
  await shot.page.screenshot({path:path.join(__dirname,'command-center-night-watch.png')});
  await shot.context.close();
 }finally{await browser.close();}
})().catch(err=>{console.error(err);process.exit(1)});
