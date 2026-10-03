import fs from 'node:fs';
const dir='/tmp/suspend-token-cost/leash/';
const rows=fs.readFileSync(dir+'ast.jsonl','utf8').trim().split('\n').map(JSON.parse);
const fns=rows.filter(x=>x.kind==='function');
const byid=new Map(fns.map(x=>[x.id,x]));
const mods=rows.filter(x=>x.kind==='module_alias');
function ancestors(id) {let out=[]; while(id&&byid.has(id)){out.push(id);id=byid.get(id).parent;} out.push(''); return out;}
function normalize(r,n=r.callee) {for(const a of mods.filter(a=>a.file===r.file&&r.line>=a.line)){if(n.startsWith(a.name+'.'))n=a.target+n.slice(a.name.length);} if(n.startsWith('Leash.'))n=n.slice(6); return n;}
function resolve(r,n=r.callee) {n=normalize(r,n); if(n.includes('.')) {let prefixes=['',r.module+'.']; let m=r.module;while(m.includes('.')){m=m.slice(0,m.lastIndexOf('.'));prefixes.push(m+'.');} for(const p of prefixes){const cs=fns.filter(f=>!f.parent&&f.module+'.'+f.name===p+n); if(cs.length)return cs.at(-1).id;} return n;}
 const as=ancestors(r.owner); const cs=fns.filter(f=>f.file===r.file&&f.name===n&&as.includes(f.parent)&&(f.line<=r.line || f.line<=byid.get(r.owner)?.end));
 cs.sort((a,b)=>as.indexOf(a.parent)-as.indexOf(b.parent)||((a.line<=r.line?0:1)-(b.line<=r.line?0:1))||b.line-a.line); if(cs.length)return cs[0].id;
 for(const o of r.opens??[]) {const v=resolve({...r,opens:[]},o+'.'+n); if(byid.has(v)||o.startsWith('Eio'))return v;}
 return n;
}
const pureHelpers=new Set(['Model_usage.with_meter','Traces.protect','Learning.protect','Drive.measured','Models.with_key','Main.protect']);
function helper(f){return /^(let[+*]|>>=|>|<)/.test(f.name)||pureHelpers.has(f.module+'.'+f.name);}
const exactExternal=new Set(['Eio.Fiber.yield','Eio.Fiber.first','Eio.Fiber.fork','Eio.Fiber.fork_daemon','Eio.Fiber.fork_promise','Ox.Scope.fork','Ox.Scope.fork_error','Ox.Spawner.fork','Ox.Resource.use_in_scope','Ox.Scope.on_release','Eio.Promise.await','Eio.Stream.add','Eio.Stream.take','Eio.Mutex.lock','Eio.Mutex.use_ro','Eio.Mutex.use_rw','Eio.Condition.await','Eio.Time.sleep','Eio.Time.with_timeout_exn','Eio.Flow.single_read','Eio.Flow.copy_string','Eio.Net.connect','Eio.Path.stat','Eio.Path.kind','Eio.Process.parse_out','Eio.Switch.run','Eio.Switch.on_release','Eio.Resource.close','Eio_unix.pipe','Eio.Buf_read.char','Eio.Buf_read.line','Eio.Buf_read.take_while','Eio.Buf_read.at_end_of_input','Ox.Actor.create','Ox.Actor.ask','Ox.Actor.tell','Ox.Agent.create','Ox.Agent.update','Ox.Agent.get_and_update','Ox.Retry.repeat','Ox.Scope.supervised_error','Ox.Supervisor.start','Ox.Supervisor.stop','Ox.Supervisor.await','Ox.Timeout.timeout','Ox_ai_chat.complete','Ox_ai_systemone.Client.answer','Ox_ai_systemone.Client.evaluate','Ox_app.Config.read_regular','Ox_app.run_with_args','Ox_app.serve','Ox_ipc.Listener.run','Ox_otel.create','Ox_process.Child.spawn','Ox_process.Child.await','Ox_process.Child.stop','Ox_rpc.Correlator.create','Ox_rpc.Correlator.call','Ox_rpc.Correlator.close']);
const dynamicSeeds=new Set(['browser.call','browser.probe','browser.sleep','tab.refresh','tab.reread','tab.sleep','tab.engage','tab.all_tabs','t.act','t.await_handoff','t.await_load','t.decide','t.focus','t.notify','t.observe','t.sleep','t.text_value','t.warn','ctx.ready','handler.act','handler.decide','handler.hand_off','handler.navigate','handler.observe','handler.plan','handler.script','handler.step','handler.text_value','handler.verify','helper.complete','helper.Text_helper.complete','text_helper.Text_helper.complete','levels.Run.choose','levels.Run.plan','levels.Run.score','planner.Planner.plan','request.Run.on_script']);
function logging(n){return /^Ox_observability.Logger.(log|debug|info|warn|error|span|limited)/.test(n)||n==='t.warn';}
function external(n,logs=true){return exactExternal.has(n)||dynamicSeeds.has(n)&&(!logging(n)||logs)||logs&&logging(n);}
const edges=new Map(fns.map(f=>[f.id,new Set()]));
const uses=rows.filter(r=>r.kind==='call'||r.kind==='reference').map(r=>({...r,target:resolve(r)}));
for(const r of uses) if(edges.has(r.owner))edges.get(r.owner).add(r.target);
const factories=new Set(['Desktop.create','Desktop.notifier','Models.text_helper','Models.levels','Text_helper.create','Planner.create','Tabs.reading_browser','Tabs.action_view','Main.command','Main.playbook_command','Main.traces_command','Main.commands','Main.skill_command']);
function fixed(logs=true,adjust=true){const io=new Set();let changed=true;while(changed){changed=false;for(const f of fns){if(io.has(f.id)||helper(f)||adjust&&factories.has(f.module+'.'+f.name))continue;if([...edges.get(f.id)].some(t=>external(t,logs)||io.has(t))){io.add(f.id);changed=true;}}}return io;}
const rawIo=fixed(true,false); const io=fixed(); const noLogging=fixed(false);
const calls=uses.filter(r=>r.kind==='call'&&(io.has(r.target)||external(r.target)));
const seeds=uses.filter(r=>r.kind==='call'&&external(r.target));
const logcalls=uses.filter(r=>r.kind==='call'&&logging(r.target));
const rawSites=uses.filter(u=>u.kind==='call'&&(rawIo.has(u.target)||external(u.target)));
const references=uses.filter(r=>r.kind==='reference'&&(io.has(r.target)||external(r.target)));
const nonblockingSites=uses.filter(r=>r.kind==='call'&&(noLogging.has(r.target)||external(r.target,false)));
const nonblockingReferences=uses.filter(r=>r.kind==='reference'&&(noLogging.has(r.target)||external(r.target,false)));
const count={standaloneReferences:references.length,nonblocking:{functions:noLogging.size,applications:nonblockingSites.length,standaloneReferences:nonblockingReferences.length},rawSignatures:rawIo.size,rawCallSites:rawSites.length,factories:factories.size,ioSignatures:io.size,ioCallSites:calls.length,externalSites:seeds.length,loggingSites:logcalls.length,ioWithoutLogging:noLogging.size,helpers:fns.filter(helper).length};
const perModule={}; for(const f of fns.filter(f=>io.has(f.id))){const v=perModule[f.module]??={signatures:0,sites:0};v.signatures++;} for(const r of calls){const v=perModule[r.module]??={signatures:0,sites:0};v.sites++;}
const output={count,references,nonblockingFunctions:fns.filter(f=>noLogging.has(f.id)),nonblockingSites,nonblockingReferences,perModule,factories:fns.filter(f=>factories.has(f.module+'.'+f.name)),rawFunctions:fns.filter(f=>rawIo.has(f.id)),functions:fns.filter(f=>io.has(f.id)),sites:calls,seeds,helpers:fns.filter(helper),uses};
fs.writeFileSync(dir+'graph.json',JSON.stringify(output,null,2));
fs.writeFileSync(dir+'io-signatures.tsv','file	line	module	name	alias\n'+output.functions.map(f=>[f.file,f.line,f.module,f.name,f.alias].join('	')).join('\n')+'\n');
fs.writeFileSync(dir+'io-call-sites.tsv','file	line	position	callee	target\n'+calls.map(f=>[f.file,f.line,f.position,f.callee,f.target].join('	')).join('\n')+'\n');
fs.writeFileSync(dir+'io-references.tsv','file\tline\tposition\tname\ttarget\n'+references.map(r=>[r.file,r.line,r.position,r.callee,r.target].join('\t')).join('\n')+'\n');
fs.writeFileSync(dir+'nonblocking-logger-sites.tsv','kind\tfile\tline\tname\ttarget\n'+[...nonblockingSites,...nonblockingReferences].map(r=>[r.kind,r.file,r.line,r.callee,r.target].join('\t')).join('\n')+'\n');
console.log(JSON.stringify({count,perModule},null,2));
