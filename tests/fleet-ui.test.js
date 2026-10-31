'use strict';
// Guards the vendored Fleet UI files: the stylesheet and the standard must name the same version, and the app must
// use the shared tokens (the files are copied unchanged from the other Fleet repos, so nothing is edited here).
const assert=require('assert');
const fs=require('fs');
const path=require('path');
const read=p=>fs.readFileSync(path.join(__dirname,'..',p),'utf8');
const css=read('web/vendor/fleet/fleet.css'),doc=read('docs/UNIFIED-UI.md');
const cssVersion=(css.match(/^\/\* Fleet UI v(\d+\.\d+)/)||[])[1];
const docVersion=(doc.match(/\*\*Version (\d+\.\d+)/)||[])[1];
assert(cssVersion,'fleet.css must start with its Fleet UI version');
assert(docVersion,'docs/UNIFIED-UI.md must state its version');
assert.strictEqual(cssVersion,docVersion,'The stylesheet and the standard must be the same version');
assert.strictEqual(cssVersion,'0.2','Eight Bells is on Fleet UI v0.2');
for(const token of ['--fl-background','--fl-foreground'])assert(css.includes(token),'fleet.css defines '+token);
assert(/prefers-color-scheme/.test(css)&&/data-theme/.test(css),'Both themes (Night watch and Chart room) are defined');
assert(/prefers-reduced-motion/.test(css),'Reduced motion is respected');
assert(/outline:\s*2px/.test(css),'The focus ring is 2px');
const styles=read('web/styles.css');
assert(/var\(--fl-/.test(styles),'Eight Bells styles are built on the shared tokens');
console.log('PASS: Fleet UI v'+cssVersion+' vendored files agree (stylesheet, standard, themes, reduced motion, focus ring)');
