import json,collections,os,re
ROOT='/home/ribelo/projects/ribelo/ocaml/ox'
xs=[json.loads(x) for x in open('/tmp/suspend-token-cost/ox-ast.jsonl')]
fs={x['id']:x for x in xs if x['kind']=='function'}
es=[x for x in xs if x['kind'] in ['call','reference']]
aliases=[x for x in xs if x['kind']=='module_alias']
def pkg(file):
 d=file.split('/')[1]
 return 'Ox' if d=='ox' else 'Ox_'+d

def canon(file,module):
 p=pkg(file)
 return module if module==p or module.startswith(p+'.') else p+'.'+module
for f in fs.values():f['canonical']=canon(f['file'],f['module'])+'.'+f['name']
index=collections.defaultdict(list)
for f in fs.values():
 if not f['parent']: index[f['canonical']].append(f)

def norm(e,n):
 for _ in range(8):
  result=n
  for a in aliases:
   if a['file']!=e['file']:continue
   if e['module']==a['module'] or e['module'].startswith(a['module']+'.'):
    if n.startswith(a['name']+'.') and a['target']!=a['name']:
     result=a['target']+n[len(a['name']):];break
  if n==result:break
  n=result
 return n

def resolve(e):
 n=norm(e,e['callee']); owner=e['owner']
 if '.' not in n:
  chain=[];o=owner
  while o in fs:chain.append(o);o=fs[o]['parent']
  # Local binding closest to active lexical function; own recursive binding wins.
  for ancestor in chain:
   poss=[f for f in fs.values() if f['file']==e['file'] and f['name']==n and (f['parent']==ancestor or f['id']==ancestor)]
   if poss:
    valid=[f for f in poss if f['line']<=e['line'] or f['id']==ancestor]
    if valid:return max(valid,key=lambda f:f['line'])['id']
  # Current module, parents and opened modules.
  mod=e['module']
  while mod:
   opts=index.get(canon(e['file'],mod)+'.'+n,[])
   valid=[f for f in opts if f['line']<=e['line'] or f['file']!=e['file']]
   if valid:return max(valid,key=lambda f:f['line'])['id']
   mod=mod.rpartition('.')[0]
  for op in e['opens']:
   out=resolve(dict(e,callee=op+'.'+n,opens=[]))
   if out:return out
  return None
 candidates=[n,pkg(e['file'])+'.'+n]
 # For nested relative modules, e.g. Changes.push under Actor.
 mod=e['module']
 while mod:
  candidates.append(canon(e['file'],mod)+'.'+n);mod=mod.rpartition('.')[0]
 for op in e['opens']:candidates.append(op+'.'+n)
 for key in candidates:
  if key in index:return index[key][-1]['id']
 return None

sink_names=set('''Eio.Buf_read.parse Eio.Condition.await Eio.Condition.await_no_mutex Eio.Condition.loop_no_mutex Eio.Fiber.fork Eio.Fiber.fork_daemon Eio.Fiber.fork_promise Eio.Fiber.List.map Eio.Fiber.all Eio.Fiber.any Eio.Fiber.await_cancel Eio.Fiber.both Eio.Fiber.first Eio.Fiber.yield Eio.File.stat Eio.Flow.Pi.simple_copy Eio.Flow.close Eio.Flow.copy_string Eio.Flow.shutdown Eio.Flow.single_read Eio.Flow.write Eio.Mutex.use_ro Eio.Mutex.use_rw Eio.Net.accept Eio.Net.connect Eio.Net.getaddrinfo_stream Eio.Net.listen Eio.Net.with_tcp_connect Eio.Path.load Eio.Path.stat Eio.Path.with_open_in Eio.Pool.use Eio.Process.await Eio.Promise.await Eio.Promise.await_exn Eio.Resource.close Eio.Semaphore.acquire Eio.Stream.add Eio.Stream.take Eio.Switch.on_release Eio.Switch.run Eio.Switch.run_protected Eio.Time.sleep Eio.Time.sleep_until Eio.Time.with_timeout Eio.Time.with_timeout_exn Eio_unix.Process.spawn_unix Eio_unix.pipe Eio_unix.run_in_systhread'''.split())
# Parser supplied string-source only, verified nonblocking (client.cookies_of_headers).
# Deferred closure / guarded nonblocking exceptions and polymorphic foreign calls are refined in reviews.
exceptions={('lib/ox/actor.ml',43),('lib/ox/actor.ml',48),('lib/otel/ox_otel.ml',118),('lib/rpc/correlator.ml',45),('lib/rpc/correlator.ml',60),('lib/process/supervised.ml',26)}
manual_functions=set()
manual_calls=set()
# reviewed functional record dispatch whose implementation suspends
manual_keys={
 ('lib/ox/rate_limiter.ml','t.sleep'),
 ('lib/ox/select.ml','timeout.sleep_until'),('lib/ox/select.ml','r.wait'),
 ('lib/otel/ox_otel.ml','t.wait'),('lib/otel/ox_otel.ml','t.with_timeout'),
 ('lib/rpc/correlator.ml','t.write'),('lib/rpc/correlator.ml','t.timeout'),('lib/rpc/correlator.ml','read'),
 ('lib/http/client.ml','connector'),
 ('lib/http/ws_client.ml','t.shutdown'),
 ('lib/sql/pool.ml','guard'),
}
log_variant=os.environ.get('LOG_VARIANT','suspending')
if log_variant=='suspending':
 manual_keys|={('lib/observability/logger.ml','t.reporter.Reporter.emit'),('lib/observability/logger.ml','reporter.emit'),('lib/observability/logger.ml','write_line')}
else:
 exceptions|={('lib/observability/logger.ml',120)}
for e in es:
 e['resolved']=resolve(e)
 e['normal']=norm(e,e['callee'])
 e['sink']=e['normal'] in sink_names or (e['file'],e['callee']) in manual_keys or (e['file'],e['line']) in manual_calls
 if (e['file'],e['line']) in exceptions:e['sink']=False
deferred_names={('lib/ox/select.ml','receive_clause'),('lib/ox/select.ml','send_clause'),('lib/ox/select.ml','timeout_clause'),('lib/ox/rate_limiter.ml','create'),('lib/observability/logger.ml','journal'),('lib/observability/logger.ml','at_least'),('lib/observability/logger.ml','writer'),('lib/observability/logger.ml','tee')}
deferred={f['id'] for f in fs.values() if (f['file'],f['name']) in deferred_names}
marked=set(manual_functions)
for e in es:
 if e['sink'] and e['owner'] in fs:marked.add(e['owner'])
deferred_touched=marked & deferred
marked-=deferred
direct=set(marked)
rounds=0
while True:
 new={e['owner'] for e in es if e['resolved'] in marked and e['owner'] in fs}
 deferred_touched |= new & deferred
 new-=marked | deferred
 if not new:break
 marked|=new;rounds+=1
for f in fs.values():f['suspends']=f['id'] in marked
sites=[e for e in es if e['sink'] or e['resolved'] in marked]
# Count only call expressions; standalone function references are displayed separately.
calls=[e for e in sites if e['kind']=='call']
refs=[e for e in sites if e['kind']=='reference']
byfile=collections.Counter(fs[n]['file'] for n in marked)
files=json.load(open('/tmp/suspend-token-cost/ox-files.json'))
lines=collections.Counter()
for file in files:
 with open(ROOT+'/'+file) as inp:lines['ml' if file.endswith('.ml') else 'mli']+=sum(1 for _ in inp)
print('lines',dict(lines),'files',len(files),'functions',len(fs),'marked',len(marked),'direct',len(direct),'fixedpoint_rounds',rounds,'call_sites',len(calls),'references',len(refs),'deferred_fields',len(deferred_touched))
for file in sorted(byfile):
 print(file,byfile[file],':',', '.join(f['name']+'@'+str(f['line']) for f in fs.values() if f['file']==file and f['id'] in marked))
json.dump(dict(functions=list(fs.values()),expressions=es,marked=sorted(marked),direct=sorted(direct),calls=calls,references=refs,lines=dict(lines),rounds=rounds,deferred=sorted(deferred_touched)),open('/tmp/suspend-token-cost/ox-resolved-'+log_variant+'.json','w'),indent=2)
print('UNRESOLVED EIO/IO DISPATCH')
cs=collections.Counter((e['file'],e['callee']) for e in es if e['kind']=='call' and not e['resolved'] and not e['sink'] and (e['callee'].startswith('Eio') or any(x in e['callee'].lower() for x in ['read','write','send','recv','sql','tls'])))
for k,v in sorted(cs.items()): print(v,*k)
