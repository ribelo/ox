import fs from 'node:fs';
const out='/tmp/suspend-token-cost/leash/';
const g=JSON.parse(fs.readFileSync(out+'graph.json','utf8'));
const rows=fs.readFileSync(out+'ast.jsonl','utf8').trim().split('\n').map(JSON.parse);
const fns=rows.filter(x=>x.kind==='function');
const calls=g.uses.filter(x=>x.kind==='call');
// Tabs explicitly declares its protected use_rw bodies synchronous; classify by module/operation, not unstable line offsets.
const regions=[];
function add(c,a,kind,rule,note='') {
 let body=a;
 if(a?.name&&!a.function&&a.name!=='<expr>') {const named=fns.filter(f=>f.file===c.file&&f.name===a.name.split('.').pop()&&f.line<=c.line); const f=named.sort((x,y)=>y.line-x.line)[0]; if(f) body={line:f.line,end:f.end};}
 if(!body)body={line:c.line,end:c.end};
 const sites=g.sites.filter(s=>s.file===c.file&&(body.startpos!=null?s.position>=body.startpos&&s.position<body.endpos:s.line>=body.line&&s.line<=body.end));
 regions.push({file:c.file,module:c.module,registration:c.line,kind,rule,bodyLine:body.line,bodyEnd:body.end,note,sites});
}
for(const c of calls){
 if(c.callee==='Ox.Actor.create') {const a=c.arguments.find(x=>x.label==='handle');add(c,{...a,name:'fold'},'Actor handle','must-not-suspend');}
 else if(/^Ox.Agent.(update|get_and_update)$/.test(c.callee)) add(c,c.arguments.find(x=>x.label==='fn'),'Agent fn','must-not-suspend');
 else if(c.callee==='Eio.Cancel.protect') add(c,c.arguments[0],'Cancel.protect','may-suspend');
 else if(/^Eio.Mutex.use_(rw|ro)$/.test(c.callee)) add(c,c.arguments.at(-1),c.callee,c.module==='Tabs'?'declared-synchronous':'may-suspend',c.arguments.at(-1).name==='work'?'Opaque work callback; current callback may yield.':'');
 else if(c.callee==='with_tab_lock') add(c,c.arguments.at(-1),'with_tab_lock callback','may-suspend','Manual lock at tabs.ml:727; unlock in finally at :728. Run.hand_off temporarily releases/reacquires the lock; lexical list includes that unlocked phase.');
}
for(const f of fns.filter(x=>x.name==='status')) add({file:f.file,module:f.module,line:f.line,end:f.end},{line:f.line,end:f.end},'status function','must-not-suspend');
for(const r of regions){const todo=g.uses.filter(x=>x.file===r.file&&x.line>=r.bodyLine&&x.line<=r.bodyEnd).map(x=>x.target),seen=new Set(),desc=[]; while(todo.length){const id=todo.pop();if(seen.has(id)||!g.functions.some(x=>x.id===id))continue;seen.add(id);desc.push(...g.sites.filter(x=>x.owner===id));todo.push(...g.uses.filter(x=>x.owner===id).map(x=>x.target));}r.transitiveSites=desc;}
fs.writeFileSync(out+'critical-regions.json',JSON.stringify(regions,null,2));
fs.writeFileSync(out+'critical-reachable-sites.tsv',['region_file\tregion_registration\trule\tsite_file\tsite_line\tcallee',...regions.flatMap(r=>[...r.sites,...r.transitiveSites].map(s=>[r.file,r.registration,r.rule,s.file,s.line,s.callee].join('\t')))].join('\n')+'\n');
const entries=regions.flatMap(r=>r.sites.map(s=>({...s,region:r.kind,registration:r.registration,rule:r.rule})));
fs.writeFileSync(out+'critical-sites.tsv',['file\tline\tcallee\ttarget\tregion_registration\trule',...entries.map(x=>[x.file,x.line,x.callee,x.target,x.registration,x.rule].join('\t'))].join('\n')+'\n');
const unique=(ss)=>new Set(ss.map(x=>x.file+':'+x.position+':'+JSON.stringify(x.arguments))).size;
console.log(JSON.stringify({regions:regions.length,byKind:regions.reduce((a,r)=>(a[r.kind]=(a[r.kind]||0)+1,a),{}),criticalRegions:regions.filter(r=>r.rule!=='may-suspend').length,uniqueListedSites:unique(entries),conflicts:entries.filter(x=>x.rule!=='may-suspend').map(x=>[x.module,x.line,x.callee,x.region,x.registration])},null,2));
