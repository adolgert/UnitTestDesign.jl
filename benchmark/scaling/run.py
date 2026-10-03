#!/usr/bin/env python3
"""Serial, isolated Julia benchmarks with external wall/RSS watchdogs. Stdlib only."""
import argparse, datetime, hashlib, json, math, os, pathlib, platform, re, signal, statistics, subprocess, time
ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent

def specs(runs=3):
    jobs=[]
    def add(ladder, ns, vs, family='none', usage='reuse', solvers=('ipog','gnd'), strength=2, **extra):
        for solver in solvers:
            for n,v in zip(ns,vs):
                jobs.append(dict(id=f'{ladder}-{solver}-n{n}-v{v}-t{strength}', ladder=f'{ladder}-{solver}',
                    n=n,v=v,family=family,usage=usage,solver=solver,strength=strength,runs=runs,**extra))
    add('arguments',[8,16,32,64,128,256,512,1024],[2]*8)
    add('options',[8]*5,[4,8,16,32,64])
    add('mixed',[16]*4,[4,16,64,256],family='mixed')
    for t in (3,4,5): add(f'strength{t}',[12],[3],strength=t)
    for family in ('noop_scoped','noop_whole','scoped','whole','matching','chain','equality'):
        add(family,[8,16,32,64],[2]*4,family=family)
    add('equality-cheap-explanations',[8,16,32,64],[2]*4,family='equality',explanations=1)
    for family in ('pattern','macro','lazy_scoped','global_budget'):
        add(family,[8,16],[2,2],family=family)
    for usage in ('core','public','named','positional','seed','stronger'):
        add(usage,[8,32,64],[2]*3,usage=usage)
    for usage in ('coverage','report','collect','iterate','export'):
        add(usage,[8,16,32,64,128],[2]*5,usage=usage,solvers=('ipog',))
    for usage in ('upgrade','topup','audit_half','audit_empty'):
        add(usage,[8,16,32,64],[2]*4,usage=usage,solvers=('ipog',))
    for family in ('tabulated_scope','lazy_scope'):
        add(family,[8,16],[4,4],family=family)
    add('invalid',[4,8,16,32],[2]*4,family='invalid')
    add('partition',[8,32,64],[2]*3,family='partition',solvers=('ipog',))
    add('realize',[8,32,64],[2]*3,family='partition',usage='realize',solvers=('ipog',))
    add('factorial',[8,12,16,20],[2]*4,usage='factorial',solvers=('ipog',))
    add('excursion',[8,32,64,128],[2]*4,usage='excursion',solvers=('ipog',))
    add('gnd-candidates10',[8,16,32,64],[2]*4,solvers=('gnd10',))
    for q in (3,4,5,6,7,8,9):
        for sat in (True,False):
            add('alldifferent-'+('sat' if sat else 'unsat'),[q if sat else q+1],[q],
                family='alldifferent',usage='feasibility',solvers=('ipog',),nodes=100_000)
    return jobs

def read_events(path):
    events=[]
    for line in path.read_text().splitlines():
        try: e=json.loads(line)
        except json.JSONDecodeError: continue  # A terminated worker may leave a partial final line.
        if isinstance(e,dict) and 'event' in e: events.append(e)
    return events

def stop_group(process, sig):
    try: os.killpg(process.pid,sig)
    except ProcessLookupError: pass

def source_fingerprint(args):
    paths=sorted((ROOT/'src').glob('*.jl'))+[ROOT/'Project.toml', ROOT/'Manifest.toml',
        HERE/'worker.jl', HERE/'run.py']+[ROOT/f for f in ('benchmark/fixtures.jl',
        'test/checker.jl','test/random_problems.jl','test/fixtures.jl','test/fixture_model.jl')]+[
        pathlib.Path(f).resolve() for f in args.adapter]
    return {str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p):
            hashlib.sha256(p.read_bytes()).hexdigest() for p in paths if p.exists()}

def fingerprint(s,args,sources):
    limits={key:getattr(args,key) for key in ('julia','rss_mib','stage_seconds','cold_seconds',
            'diagnostic_seconds','startup_seconds','job_seconds','poll')}
    limits['julia_arg']=getattr(args,'julia_arg',[])
    return hashlib.sha256(json.dumps(dict(spec=s,limits=limits,sources=sources),sort_keys=True).encode()).hexdigest()

def payload_floor(s):
    # Proven raw integer payload for native dense target storage, only when
    # all targets are known feasible. Other families/solvers get runtime guards.
    if s['solver'] not in ('ipog','gnd','gnd10'): return 0
    if s['family'] not in ('none','noop_scoped','noop_whole','mixed'): return 0
    if s['usage'] in ('coverage','report','audit_half','audit_empty','feasibility','factorial','excursion'): return 0
    if s['solver']=='ipog' and s['family'] in ('none','mixed') and s['usage'] not in ('seed','stronger','upgrade','topup'): return 0
    n,v,t=s['n'],s['v'],s['strength']
    if s['family']=='mixed': targets=math.comb(n-1,t)*2**t+math.comb(n-1,t-1)*v*2**(t-1)
    else: targets=math.comb(n,t)*v**t
    if s['usage']=='upgrade': targets=math.comb(n,3)*v**3
    if s['usage']=='stronger' and t<3: targets+=math.comb(min(6,n),3)*v**3
    return 8*n*targets

def run_job(s,out,args):
    jobdir=out/s['id']; jobdir.mkdir(parents=True,exist_ok=True)
    (jobdir/'spec.json').write_text(json.dumps(s,indent=2)+'\n')
    command=[args.julia,*getattr(args,'julia_arg',[]),'--startup-file=no','--project='+str(ROOT),'--threads=1',str(HERE/'worker.jl'),str(jobdir/'spec.json')]
    timecmd=['/usr/bin/time','-l' if platform.system()=='Darwin' else '-v']
    env={**os.environ,'JULIA_NUM_THREADS':'1','OPENBLAS_NUM_THREADS':'1'}
    start=time.monotonic(); stage_start=start; stage='startup'; sampled_peak=0; stopped=None; stage_peaks={}
    with (jobdir/'events.jsonl').open('w') as stdout,(jobdir/'stderr.txt').open('w') as stderr:
        p=subprocess.Popen(timecmd+command,stdout=stdout,stderr=stderr,env=env,start_new_session=True)
        observed_events=0; monitor_error=None
        try:
            while p.poll() is None:
                time.sleep(args.poll)
                # time launches a single child; monitor every process in its group.
                try:
                    listing=subprocess.run(['ps','-axo','pid=,pgid=,rss='],capture_output=True,text=True,timeout=2)
                    if listing.returncode: raise RuntimeError(listing.stderr.strip() or 'ps failed')
                except (subprocess.TimeoutExpired,RuntimeError,OSError) as e:
                    monitor_error=str(e);stopped='monitor_error'
                    stop_group(p,signal.SIGKILL);p.wait();break
                members=[tuple(map(int,line.split())) for line in listing.stdout.splitlines() if len(line.split())==3]
                rss=sum(kib*1024 for pid,pgid,kib in members if pgid==p.pid)
                sampled_peak=max(sampled_peak,rss)
                stage_peaks[stage]=max(stage_peaks.get(stage,0),rss)
                events=read_events(jobdir/'events.jsonl')
                for e in events[observed_events:]:
                    if e['event']=='stage': stage=e['name'];stage_start=time.monotonic()
                observed_events=len(events)
                now=time.monotonic()
                allowance=args.startup_seconds if stage=='startup' else args.cold_seconds if stage in ('cold','prepare','construct') else args.diagnostic_seconds if stage in ('diagnostics','oracle') else args.stage_seconds
                if rss > args.rss_mib*2**20: stopped='rss_limit'
                elif now-start > args.job_seconds: stopped='job_timeout'
                elif now-stage_start > allowance: stopped='stage_timeout'
                if stopped:
                    stop_group(p,signal.SIGTERM)
                    try: p.wait(timeout=2)
                    except subprocess.TimeoutExpired: stop_group(p,signal.SIGKILL);p.wait()
                    break
        except BaseException:
            if p.poll() is None: stop_group(p,signal.SIGKILL);p.wait()
            raise
    events=read_events(jobdir/'events.jsonl')
    measurements=[e for e in events if e['event']=='measurement']
    warm=[e for e in measurements if e['stage']=='warm']
    errors=[e for e in events if e['event']=='error']
    done=[e for e in events if e['event']=='done']
    environments=[e for e in events if e['event']=='environment']
    phases=[];active_stage=None
    for e in events:
        if e['event']=='stage': active_stage=e['name']
        elif e['event']=='phase': phases.append(dict(e,stage=active_stage))
    unknown=any(e.get('result',{}).get('status')=='unknown' for e in measurements) or any('ResourceLimitError' in e['type'] for e in errors)
    result=dict(spec=s,status=stopped or ('resource_limit' if unknown else 'ok' if p.returncode==0 and done else 'error'),
        stopped_stage=stage if stopped else None,exit_code=p.returncode,wall_seconds=time.monotonic()-start,
        sampled_peak_rss_bytes=sampled_peak,measurements=measurements,errors=errors,
        validation=done[-1]['validation'] if done else None,command=command,
        completed_warm_runs=len(warm),sampled_stage_peak_rss_bytes=stage_peaks,monitor_error=monitor_error,
        environment=environments[-1] if environments else None,phase_measurements=phases)
    stderr=(jobdir/'stderr.txt').read_text()
    match=re.search(r'(\d+)\s+maximum resident set size',stderr) if platform.system()=='Darwin' else re.search(r'Maximum resident set size \(kbytes\):\s*(\d+)',stderr)
    result['os_peak_rss_bytes']=int(match[1])*(1 if platform.system()=='Darwin' else 1024) if match else None
    footprint=re.search(r'(\d+)\s+peak memory footprint',stderr)
    result['os_peak_footprint_bytes']=int(footprint[1]) if footprint else None
    if warm and result['status'] in ('ok','resource_limit') and len(warm)==s['runs']:
        result.update(warm_median_seconds=statistics.median(e['seconds'] for e in warm),
            warm_min_seconds=min(e['seconds'] for e in warm),warm_max_seconds=max(e['seconds'] for e in warm),
            warm_median_allocated_bytes=statistics.median(e['allocated_bytes'] for e in warm))
    return result

def write_summary(out,results,meta):
    (out/'results.json').write_text(json.dumps(dict(metadata=meta,results=results),indent=2)+'\n')
    lines=['# Scaling benchmark measurements','', 'Each job is an isolated serial process. RSS includes Julia, compilation, setup, all runs and diagnostics; allocation is cumulative warm-call allocation, not peak memory. Cold calls include compilation. Censored jobs have no completed warm estimate.', '',
           '| Job | Status | Cases | Warm median s | Warm allocated MiB | Peak RSS MiB |',
           '|:--|:--|--:|--:|--:|--:|']
    for r in results:
        w=[e for e in r.get('measurements',[]) if e['stage']=='warm']
        completed=[e for e in r.get('measurements',[]) if e['stage'] in ('warm','cold')]
        cases=completed[-1].get('result',{}).get('cases','') if completed else ''
        def fmt(v): return '' if v is None else f'{v:.4g}'
        rss=r.get('os_peak_rss_bytes') or r.get('sampled_peak_rss_bytes')
        allocated=r.get('warm_median_allocated_bytes')
        lines.append(f"| {r['spec']['id']} | {r['status']} | {cases} | {fmt(r.get('warm_median_seconds'))} | {fmt(allocated/2**20) if allocated is not None else ''} | {fmt(rss/2**20) if rss else ''} |")
    (out/'summary.md').write_text('\n'.join(lines)+'\n')

def main():
    a=argparse.ArgumentParser(description=__doc__)
    a.add_argument('--out',type=pathlib.Path,default=HERE/'results'/datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
    a.add_argument('--runs',type=int,default=3)
    a.add_argument('--filter',default='',help='Substring of job ID')
    a.add_argument('--specs',type=pathlib.Path,help='JSON array of custom job specs')
    a.add_argument('--adapter',action='append',default=[])
    a.add_argument('--julia',default='julia')
    a.add_argument('--julia-arg',action='append',default=[],help='Extra Julia flag; use --julia-arg=--heap-size-hint=1G for a leading dash')
    a.add_argument('--rss-mib',type=float,default=2048)
    a.add_argument('--stage-seconds',type=float,default=30)
    a.add_argument('--startup-seconds',type=float,default=60)
    a.add_argument('--cold-seconds',type=float,default=60,help='First-call/setup timer including compilation')
    a.add_argument('--diagnostic-seconds',type=float,default=30,help='Summary-size/oracle timer')
    a.add_argument('--job-seconds',type=float,default=180)
    a.add_argument('--poll',type=float,default=.2)
    a.add_argument('--continue-ladders',action='store_true',help='Attempt larger cases after censored/error jobs')
    a.add_argument('--resume',action='store_true')
    a.add_argument('--list',action='store_true')
    args=a.parse_args()
    jobs=json.loads(args.specs.read_text()) if args.specs else specs(args.runs)
    jobs=[s for s in jobs if args.filter in s['id']]
    for s in jobs: s['adapters']=[str(pathlib.Path(f).resolve()) for f in args.adapter]
    if args.list: print(json.dumps(jobs,indent=2));return
    if args.runs<1 or min(args.rss_mib,args.stage_seconds,args.cold_seconds,args.diagnostic_seconds,args.startup_seconds,args.job_seconds,args.poll)<=0: a.error('runs and limits must be positive')
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    def capture(cmd): return subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True).stdout.strip()
    sources=source_fingerprint(args)
    meta=dict(started=datetime.datetime.now().astimezone().isoformat(),platform=platform.platform(),source_sha256=sources,
        commit=capture(['git','rev-parse','HEAD']),git_status=capture(['git','status','--short']),
        source_diff=capture(['git','diff','--','src']),limits=vars(args).copy(),
        memory_before=capture(['vm_stat']) if platform.system()=='Darwin' else capture(['free','-b']))
    meta['limits']={k:str(v) if isinstance(v,pathlib.Path) else v for k,v in meta['limits'].items()}
    results=[];blocked={}
    for i,s in enumerate(jobs):
        path=out/s['id']/'result.json'
        key=fingerprint(s,args,sources)
        existing=json.loads(path.read_text()) if args.resume and path.exists() else None
        if existing and existing.get('fingerprint')==key: r=existing
        elif s['ladder'] in blocked and not args.continue_ladders:
            r=dict(spec=s,status='skipped_after_limit',reason=blocked[s['ladder']])
        elif payload_floor(s)>args.rss_mib*2**20:
            r=dict(spec=s,status='skipped_payload_floor',reason='Dense target integer payload alone exceeds RSS cap',payload_floor_bytes=payload_floor(s))
        else:
            print(f"[{i+1}/{len(jobs)}] {s['id']}",flush=True)
            r=run_job(s,out,args)
            print(f"  {r['status']}, warm={r.get('warm_median_seconds')}, RSS MiB={(r.get('os_peak_rss_bytes') or r.get('sampled_peak_rss_bytes',0))/2**20:.1f}",flush=True)
        r['fingerprint']=key
        if r['status'] not in ('ok','skipped_after_limit'): blocked[s['ladder']]=s['id']
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(json.dumps(r,indent=2)+'\n')
        results.append(r);write_summary(out,results,meta)
    meta['finished']=datetime.datetime.now().astimezone().isoformat()
    meta['memory_after']=capture(['vm_stat']) if platform.system()=='Darwin' else capture(['free','-b'])
    write_summary(out,results,meta)
    print(out/'summary.md',flush=True)
if __name__=='__main__': main()
