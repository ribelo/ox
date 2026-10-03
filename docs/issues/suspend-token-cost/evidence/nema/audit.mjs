import fs from 'node:fs';
const root='/tmp/suspend-token-cost/nema/';
const all=fs.readFileSync(root+'ast.jsonl','utf8').trim().split('\n').map(JSON.parse);
const io=JSON.parse(fs.readFileSync(root+'io-calls.json','utf8'));
const sigs=JSON.parse(fs.readFileSync(root+'io-signatures.json','utf8'));
const functions=all.filter(x=>x.kind==='function');
const path=e=>e.file.replace(root+'sources/','');
const normalize=a=>({...a,file:path(a)});
const sites=[];
function add(e,category,kind,ranges){const applications=io.filter(c=>c.file===path(e)&&(ranges.some(r=>c.position>=r.startpos&&c.position<r.endpos)||(['Eio.Mutex.lock','Eio.Mutex.use_ro','Eio.Mutex.use_rw','Eio.Condition.await'].includes(e.callee)&&c.position===e.position)));sites.push({file:path(e),line:kind==='explicit on_waiting contract'?ranges[0].line:e.line,end:kind==='explicit on_waiting contract'?ranges[0].end:e.end,callee:e.callee??e.name,category,kind,ranges,ioApplications:applications.map(c=>({callee:c.callee,line:c.line,target:c.target})),loggingDirect:applications.filter(c=>c.target.startsWith('Ox_observability.Logger.')).length});}
for(const e of all.filter(e=>e.kind==='call')){
 const args=e.arguments.filter(a=>a.function);
 const ranges=args.map(a=>({line:a.line,end:a.end,startpos:a.startpos,endpos:a.endpos}));
 if(e.callee==='Eio.Cancel.protect')add(e,'may-suspend','cancellation protection',ranges);
 else if(['Eio.Mutex.use_ro','Eio.Mutex.use_rw','Eio.Mutex.lock','with_lock'].includes(e.callee))add(e,'may-suspend','Eio mutex acquisition/body',ranges);
 else if(e.callee==='Eio.Condition.await')add(e,'may-suspend','condition wait under mutex',ranges);
 else if(['Gate.with_write','with_write_value'].includes(e.callee)){add(e,'may-suspend','exclusive Eio publication lease',ranges.filter(r=>!e.arguments.some(a=>a.label==='on_waiting'&&a.startpos===r.startpos)));const a=e.arguments.find(a=>a.label==='on_waiting');if(a)add(e,'must-not-suspend','explicit on_waiting contract',[a]);}
 else if(['Mutex.lock','locked','with_gate'].includes(e.callee))add(e,'must-not-suspend','Stdlib mutex guard',ranges);
 else if(['if_database_open','if_connection_open','Connection.transaction'].includes(e.callee)&&path(e)==='lib/ladybug/nema_ladybug.ml')add(e,'must-not-suspend','native C-state/transaction guard',ranges);
}
for(const e of functions.filter(e=>e.module==='Nema_ladybug.Connection'&&e.name==='transaction'))add(e,'must-not-suspend','native transaction callback contract',[]);
// No Ox_app SERVICE.status callback implementation occurs in this corpus.
// Cli_error.status is an exit-code classifier, not a status query.
for(const e of functions.filter(e=>e.module==='Watch_intake'&&e.name==='status'))add(e,'must-not-suspend','pure status query',[]);
const violation=sites.find(s=>s.kind==='explicit on_waiting contract');
if(violation){violation.indirectLogging={site:{file:'lib/nema/service.ml',line:739,callee:'t.work_observer.run'},reaches:[{file:'bin/nema/telemetry.ml',line:85,callee:'Logger.span'},{file:'bin/nema/telemetry.ml',line:90,callee:'Logger.info'}]};}
const aliases=functions.filter(f=>f.alias&&all.some(e=>e.kind==='reference'&&e.owner===f.id&&e.callee==='Result.bind'));
const bindDefs=functions.filter(f=>f.name==='let*'&&!f.alias);
const helpers=[...aliases,...bindDefs].map(f=>({file:path(f),line:f.line,name:f.module+'.'+f.name,reason:'pure result bind; yielding callback mode only'}));
for(const [file,line,name,reason] of [
 ['lib/nema/exit_result.ml',3,'Exit_result.iter_exit','generic result iteration'],
 ['lib/nema/db.ml',988,'Db.resolve_endpoint_index_with','pure algorithm parameterized by query_rows; yielding callback mode'],
 ['lib/nema/vault.ml',92,'Vault.with_verified_directory','pure/native descriptor lifetime wrapper; callback mode, unyielding when called under locked'],
 ['lib/nema/vault.ml',206,'Vault.with_directory_path','pure/native directory validation wrapper; callback mode, native callers remain unyielding'],
 ['lib/nema/vault.ml',233,'Vault.inspection_parent','pure/native validation wrapper; callback mode, unyielding when called under locked'],
 ['lib/nema/db.ml',145,'Db.with_cleanup','generic protected cleanup/body; no intrinsic suspension'],
 ['lib/nema/vault.ml',51,'Vault.with_revision','pure revision guard; callback mode'],
 ['lib/nema/vault.ml',63,'Vault.protect','pure exception-to-result wrapper; callback mode'],
 ['lib/nema/vault.ml',67,'Vault.locked','Stdlib-mutex callback must be local unyielding, not yielding'],
 ['lib/ladybug/nema_ladybug.ml',513,'Nema_ladybug.wrap','pure error wrapper; native callers may choose unyielding'],
 ['lib/ladybug/nema_ladybug.ml',527,'Nema_ladybug.if_database_open','native state callback must be local unyielding'],
 ['lib/ladybug/nema_ladybug.ml',529,'Nema_ladybug.if_connection_open','native state callback must be local unyielding'],
 ['lib/ladybug/nema_ladybug.ml',838,'Nema_ladybug.Owner.with_gate','Stdlib-mutex callback must be local unyielding'],
 ['lib/ladybug/nema_ladybug.ml',1171,'Nema_ladybug.Owner.statement','pure statement validation; yielding continuation'],
 ['bin/nema/main.ml',196,'Main.with_service','pure configuration wrapper around yielding callback']
])helpers.push({file,line,name,reason});
fs.writeFileSync(root+'critical-sections.json',JSON.stringify(sites,null,2));
fs.writeFileSync(root+'generic-helpers.json',JSON.stringify(helpers,null,2));
const cat=c=>sites.filter(s=>s.category===c);
const unique=c=>new Set(cat(c).flatMap(s=>s.ioApplications.map(a=>s.file+':'+a.line+':'+a.callee))).size;
const summary={totalSites:sites.length,mustNotSuspend:cat('must-not-suspend').length,maySuspend:cat('may-suspend').length,mustNotSuspendIoApplications:unique('must-not-suspend'),maySuspendIoApplications:unique('may-suspend'),mustNotSuspendDirectLogging:cat('must-not-suspend').reduce((n,s)=>n+s.loggingDirect,0),mustNotSuspendIndirectLoggingSites:violation?1:0,loggingCallsReachableFromMustNotSuspend:violation?2:0,actualViolationSites:violation?1:0,resultBindHelpers:aliases.length+bindDefs.length,genericHelpers:helpers.length};
fs.writeFileSync(root+'audit-counts.json',JSON.stringify(summary,null,2));console.log(summary);console.log(sites.map(s=>s.file+':'+s.line+' '+s.category+' '+s.callee+' -> '+s.ioApplications.map(a=>a.callee+'@'+a.line).join(', ')).join('\n'));
