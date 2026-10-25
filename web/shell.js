/* Eight Bells on the Fleet shell (docs/UNIFIED-UI.md sections 3.1, 5 and 7).
   Loaded synchronously in <head> so the remembered theme and sidebar state apply before the first paint
   (the CSP allows no inline script). Browser storage can be unavailable; everything still works without it. */
(function(root){
'use strict';
const THEME_KEY='eight-bells-theme';
const SIDEBAR_KEY='eight-bells-sidebar';
const html=document.documentElement;
function load(key){try{return root.localStorage.getItem(key);}catch(e){return null;}}
function save(key,value){
 try{if(value===null)root.localStorage.removeItem(key);else root.localStorage.setItem(key,value);}
 catch(e){/* not persisted; the choice still applies for this page */}
}
function readTheme(){const v=load(THEME_KEY);return v==='dark'||v==='light'?v:'system';}
// Follows Windows by default; 'dark' (Night watch) or 'light' (Chart room) sets <html data-theme> and is remembered.
function applyTheme(choice){
 if(choice==='system')html.removeAttribute('data-theme');else html.setAttribute('data-theme',choice);
 save(THEME_KEY,choice==='system'?null:choice);
}
const nextTheme=t=>t==='system'?'dark':t==='dark'?'light':'system';
const themeName=t=>t==='system'?'Follow Windows':t==='dark'?'Night watch':'Chart room';
const THEME_ICON={system:'themeSystem',dark:'themeDark',light:'themeLight'};
let theme=readTheme();
applyTheme(theme);
// Sidebar: 240 px, or 64 px icons only. Below 1024 px CSS collapses it by itself, whatever is stored.
if(load(SIDEBAR_KEY)==='collapsed')html.classList.add('sidebar-collapsed');

const ENGINE_WORD={connecting:'Connecting',running:'Running',disconnected:'Disconnected',stopped:'Stopped'};
function setEngine(state){
 const box=document.getElementById('engineState');if(!box)return;
 box.className='engine engine-'+state;
 box.querySelector('.engine-word').textContent=ENGINE_WORD[state]||state;
}
function setSession(text){const s=document.getElementById('sessionState');if(s)s.textContent=text;}
function icon(name,size){return root.EightBellsIcons?root.EightBellsIcons.svg(name,size):'';}
function renderTheme(){
 const b=document.getElementById('themeBtn');if(!b)return;
 b.title='Theme: '+themeName(theme)+'. Click for '+themeName(nextTheme(theme))+'.';
 b.setAttribute('aria-label',b.title);
 b.querySelector('.nav-icon').innerHTML=icon(THEME_ICON[theme],20);
 b.querySelector('.nav-label').textContent=themeName(theme);
}
function renderSidebar(){
 const b=document.getElementById('collapseBtn');if(!b)return;
 const collapsed=html.classList.contains('sidebar-collapsed');
 b.setAttribute('aria-expanded',String(!collapsed));
 b.title=collapsed?'Expand the sidebar':'Collapse the sidebar';
 b.querySelector('.nav-icon').innerHTML=icon(collapsed?'expand':'collapse',20);
}
function init(){
 if(root.EightBellsIcons)root.EightBellsIcons.hydrate(document);
 const address=document.getElementById('boundAddress');
 if(address)address.textContent=location.host||'—';
 renderTheme();renderSidebar();
 document.getElementById('themeBtn').addEventListener('click',()=>{theme=nextTheme(theme);applyTheme(theme);renderTheme();});
 document.getElementById('collapseBtn').addEventListener('click',()=>{
  const collapsed=!html.classList.contains('sidebar-collapsed');
  html.classList.toggle('sidebar-collapsed',collapsed);
  save(SIDEBAR_KEY,collapsed?'collapsed':'expanded');
  renderSidebar();
 });
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
root.EightBellsShell={setEngine,setSession,readTheme,applyTheme,nextTheme,themeName};
})(window);
