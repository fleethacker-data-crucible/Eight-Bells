'use strict';
const assert=require('assert'),fs=require('fs'),path=require('path');
// Every kind of finding the engine can produce has a plain-language title in the page, and the page uses it.
const engine=fs.readFileSync(path.join(__dirname,'..','web','engine.js'),'utf8'),app=fs.readFileSync(path.join(__dirname,'..','web','app.js'),'utf8');
const kinds=[...new Set([...engine.matchAll(/add\('([a-z-]+)'/g)].map(m=>m[1]))];
assert(kinds.length>=5,'The engine produces at least the five known kinds, found '+kinds.join(', '));
const map=app.match(/const FINDING_TITLES=\{([^}]*)\}/);assert(map,'The page has a FINDING_TITLES map');
for(const k of kinds)assert(map[1].includes("'"+k+"':"),'No plain-language title for the finding kind '+k);
assert(/escapeHTML\(findingTitle\(x\.type\)\)/.test(app),'The findings list shows the title');
assert(/escapeHTML\(findingTitle\(f\.type\)\)/.test(app),'The finding detail shows the title');
console.log('PASS: finding kinds have plain-language titles in the list and in the detail ('+kinds.join(', ')+')');
