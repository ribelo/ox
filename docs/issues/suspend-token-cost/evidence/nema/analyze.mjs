import fs from 'node:fs';
const root='/tmp/suspend-token-cost/nema/';
const nonblocking=process.argv.includes('--nonblocking-logger');
const prefix=nonblocking?'nonblocking-':process.argv.includes('--raw')?'raw-':'';
const ev=fs.readFileSync(root+'ast.jsonl','utf8').trim().split(String.fromCharCode(10)).map(JSON.parse);
const funs=ev.filter(x=>x.kind==='function'), byId=new Map(funs.map(x=>[x.id,x]));
const aliases=ev.filter(x=>x.kind==='module_alias');
function chain(id){const a=[];let x=byId.get(id);while(x){a.push(x);x=byId.get(x.parent)}return a}
function qualify(name,e){let n=name.replace(/^Nema[.]/,'').replace(/^Nema_cli_support[.]/,'');for(let i=0;i<5;i++){let a=aliases.filter(a=>a.file===e.file&&a.line<=e.line&&(e.module===a.module||e.module.startsWith(a.module+'.'))&&(n===a.name||n.startsWith(a.name+'.'))).sort((a,b)=>b.module.length-a.module.length||b.line-a.line)[0];if(!a||a.target===a.name)break;n=a.target+n.slice(a.name.length)}return n}
function resolve(e){let n=qualify(e.callee,e);if(n==='handle'&&e.module==='Main'&&e.line===1062)return funs.find(f=>f.module==='Service'&&f.name==='handler').id;if(n.startsWith('Logger.'))n='Ox_observability.'+n;if(e.module==='Main.Client'&&(n==='client_get'||n==='client_post')) {return funs.find(f=>f.module==='Main'&&f.name===n&&!f.parent).id;} if(!n.includes('.')){const ancestors=chain(e.owner);const anc=new Map(ancestors.map((x,i)=>[x.id,i]));const candidates=funs.filter(f=>f.file===e.file&&f.name===n&&f.line<=e.line&&(anc.has(f.parent)||anc.has(f.id)||(!f.parent&&f.module===e.module)));candidates.sort((a,b)=>{const rank=f=>anc.has(f.id)?-2:(anc.has(f.parent)?anc.get(f.parent):999);return rank(a)-rank(b)||b.line-a.line});if(candidates.length)return candidates[0].id;}
const candidates=[n,e.module+'.'+n,...(e.opens??[]).map(o=>qualify(o+'.'+n,e))];for(const c of candidates){const fs=funs.filter(f=>!f.parent&&f.module+'.'+f.name===c);if(fs.length)return fs.at(-1).id;}return n;}
const seedNames=new Set(['Eio.Condition.await','Eio.Condition.loop_no_mutex','Eio.Fiber.await_cancel','Eio.Fiber.first','Eio.Fiber.fork','Eio.Fiber.fork_daemon','Eio.Fiber.fork_promise','Eio.Fiber.yield','Eio.Mutex.lock','Eio.Mutex.use_ro','Eio.Mutex.use_rw','Eio.Net.listen','Eio.Promise.await','Eio.Semaphore.acquire','Eio.Switch.run','Eio.Switch.on_release','Ox.Scope.on_release','Ox.Resource.use_in_scope','Ox.Scope.fork','t.work_observer.run','Eio.Time.Mono.sleep','Eio.Time.sleep','Eio_unix.await_readable','Ox.Scope.await','Ox.Scope.fork_error','Ox.Scope.supervised_error','Ox.Timeout.timeout','Ox_ai_openrouter.Embeddings.create','Ox_app.Config.read_regular','Ox_app.run_with_args','Ox_app.serve','Ox_blocking.Pool.shutdown','Ox_blocking.Pool.shutdown_policy','Ox_blocking.run','Ox_blocking.run_result','Ox_blocking.try_run_result','Ox_blocking.try_run_result_timeout','Ox_http.Client.request','Ox_http.Server.Body.read_all','Ox_http.Server.run_h1_on_socket','Ox_observability.Logger.error','Ox_observability.Logger.info','Ox_observability.Logger.span','Ox_otel.create']);
if(nonblocking)for(const name of [...seedNames])if(name.startsWith('Ox_observability.Logger.')||name==='t.work_observer.run')seedNames.delete(name);
const factories=new Set(funs.filter(f=>f.module==='Main'&&['client_commands','daemon_cmd','status_cmd','stop_cmd','restart_cmd'].includes(f.name)).map(f=>f.id));
const excluded=new Set(process.argv.includes('--adjusted')?[...factories]:[]);
const shadowedReferences=new Set(['lib/nema/db.ml:71:query','lib/nema/http_api.ml:58:decode','lib/nema/search.ml:408:bm25','lib/ladybug/nema_ladybug.ml:1247:query','lib/ladybug/nema_ladybug.ml:1248:query']);
const edges=ev.filter(e=>(e.kind==='call'||e.kind==='reference')&&!(e.kind==='reference'&&shadowedReferences.has(e.file.replace(root+'sources/','')+':'+e.line+':'+e.callee))).map(e=>({...e,target:resolve(e)}));
const isIo=new Set(seedNames);let changed=true;while(changed){changed=false;for(const e of edges)if(e.owner&&isIo.has(e.target)&&!excluded.has(e.owner)&&!isIo.has(e.owner)){isIo.add(e.owner);changed=true;}}
const selected=funs.filter(f=>isIo.has(f.id));
const calls=edges.filter(e=>e.kind==='call'&&isIo.has(e.target));
const references=edges.filter(e=>e.kind==='reference'&&isIo.has(e.target));
const direct=edges.filter(e=>e.kind==='call'&&seedNames.has(e.target));
const printFile=p=>p.replace(root+'sources/','');
const showName=f=>f.module+'.'+f.name+(f.parent?' (local)':'')+(f.alias?' (alias)':'');
const rows=selected.map(f=>({name:showName(f),file:printFile(f.file),line:f.line,end:f.end,id:f.id,alias:f.alias,reasons:edges.filter(e=>e.owner===f.id&&isIo.has(e.target)).map(e=>({callee:e.callee,target:e.target,line:e.line,kind:e.kind}))}));
for(const [name,line] of [['client_post',745],['client_get',746]]) rows.push({name:'Main.client_commands.'+name+' (local partial binding)',file:'bin/nema/main.ml',line,end:line,id:root+'sources/bin/nema/main.ml:'+line+':'+name,alias:false,partial:true,reasons:[{callee:name,target:root+'sources/bin/nema/main.ml:'+(name==='client_post'?204:212)+':'+name,line,kind:'partial binding'}]});
rows.push({name:'Main.body.handle (local partial binding)',file:'bin/nema/main.ml',line:1057,end:1057,id:root+'sources/bin/nema/main.ml:1057:handle',partial:true,alias:false,reasons:[{callee:'Service.handler',line:1057,kind:'partial binding'}]});
fs.writeFileSync(root+prefix+'io-signatures.json',JSON.stringify(rows,null,2));
fs.writeFileSync(root+prefix+'io-calls.json',JSON.stringify(calls.map(e=>({...e,file:printFile(e.file)})),null,2));
fs.writeFileSync(root+prefix+'io-references.json',JSON.stringify(references.map(e=>({...e,file:printFile(e.file)})),null,2));
fs.writeFileSync(root+prefix+'resolved-events.json',JSON.stringify(edges,null,2));
const perModule={};for(const f of selected)(perModule[printFile(f.file)]??={signatures:0,calls:0,direct:0}).signatures++;for(const e of calls)(perModule[printFile(e.file)]??={signatures:0,calls:0,direct:0}).calls++;for(const e of direct)(perModule[printFile(e.file)]??={signatures:0,calls:0,direct:0}).direct++;
const summary={signatures:selected.length,ioApplications:calls.length,standaloneIoReferences:references.length,loggerVariant:nonblocking?'nonblocking bounded try-add queue':'current synchronous reporters',seedApplications:direct.length,aliases:selected.filter(f=>f.alias).length,namedLocal:selected.filter(f=>f.parent).length,loggingApplications:calls.filter(e=>e.target.startsWith('Ox_observability.Logger.')).length,perModule};
summary.deferredFactories=[...factories].map(id=>byId.get(id));summary.releaseRegistrationApplications=calls.filter(e=>['Eio.Switch.on_release','Ox.Scope.on_release','Ox.Resource.use_in_scope'].includes(e.target)).length;summary.partialNamedSignatures=3;summary.signaturesWithPartialBindings=summary.signatures+3;fs.writeFileSync(root+prefix+'counts.json',JSON.stringify(summary,null,2));
console.log(summary);
console.log('Affected names:',selected.map(showName).join(', '));
console.log('External roots:',[...new Set(direct.map(e=>e.target))].sort());
