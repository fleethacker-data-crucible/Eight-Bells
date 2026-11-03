'use strict';
// The golden file that holds the PowerShell engine port to the JavaScript engine must match what the engine produces now.
// If this fails, run: node tools/gen-golden.js  and then make EightBells-Engine.ps1 agree (tests/Engine-Test.ps1).
const assert=require('assert');
const fs=require('fs');
const path=require('path');
const {generate}=require('../tools/gen-golden.js');
const committed=JSON.parse(fs.readFileSync(path.join(__dirname,'golden','engine.golden.json'),'utf8'));
const fresh=JSON.parse(JSON.stringify(generate()));
assert.deepStrictEqual(fresh,committed,'tests/golden/engine.golden.json is out of date: run node tools/gen-golden.js');
assert(committed.cases.length>=20&&committed.candidates.length>=3);
console.log('PASS: golden file matches the engine ('+committed.cases.length+' cases, '+committed.candidates.length+' candidate sets)');
