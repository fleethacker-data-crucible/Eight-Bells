'use strict';
// Writes samples/synthetic_watch.pdf, a tiny synthetic text-layer PDF, using the test builder.
// Run: node tools/make-sample-pdf.js
const fs=require('fs');
const path=require('path');
const {buildPdf,text}=require('../tests/helpers/pdf-builder.js');
const lines=[
 'SYNTHETIC TRAINING LOG - ENGINEERING WATCH',
 '0800 Watch assumed',
 '0830 Pump B abnormal vibration observed',
 '0845 Supervisor notified',
 '0915 Pump B vibration cleared and returned to service'
];
fs.writeFileSync(path.join(__dirname,'..','samples','synthetic_watch.pdf'),buildPdf([text(lines)],{compress:true}));
console.log('Wrote samples/synthetic_watch.pdf');
