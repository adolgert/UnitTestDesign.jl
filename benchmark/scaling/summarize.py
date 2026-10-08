#!/usr/bin/env python3
"""Flatten saved benchmark studies and archive raw per-job evidence. Stdlib only."""
import argparse, csv, hashlib, json, pathlib, statistics, zipfile
ROOT=pathlib.Path(__file__).resolve().parents[2]
SHAPES=ROOT/'benchmark'/'best_known'/'uniform_shapes.csv'
PREPARED=('coverage','report','collect','iterate','realize','export','upgrade','topup','audit_half','audit_empty')

def best_known_table(path=SHAPES):
    """(t, v, k) -> row of uniform_shapes.csv, written by benchmark/best_known/write_table.jl."""
    if not path.exists(): return {}
    with path.open(newline='') as f:
        return {(int(r['t']),int(r['v']),int(r['k'])):r for r in csv.DictReader(f)}

def best_known_for(s,table):
    """The table's row for a uniform, unconstrained covering spec, else None (plan §7.3)."""
    if s['family']!='none' or s['usage'] not in ('reuse','core','public','named','positional'): return None
    if any(f in s for f in ('forbid','space','model','adapt','stronger')): return None
    if 'arity' in s and len(set(s['arity']))>1: return None
    return table.get((s['strength'],s['v'],s['n']))

def ratio(a,b): return a/b if a is not None and b else None

def spec_bound(s):
    """The elementary bound from the spec alone, for results without a `bounds` event (studies
    made before it, such as the 2798ecf baseline): unconstrained n × v, mixed or arity specs only."""
    if s['family'] not in ('none','mixed') or s['usage'] not in ('reuse','core','public','named','positional','seed'): return None
    if any(f in s for f in ('forbid','space','model','adapt','stronger')): return None
    arity=s.get('arity') or ([s['v']]+[2]*(s['n']-1) if s['family']=='mixed' else [s['v']]*s['n'])
    out=1
    for a in sorted(arity,reverse=True)[:s['strength']]: out*=a
    return out

def metrics(r,cases,construct0,cold,table):
    """Rows over the best known and over the bound, first-call time, engine extras (plan §7.3)."""
    s=r['spec']; bounds=r.get('bounds') or {}
    known=best_known_for(s,table)
    best=int(known['best_known']) if known and known['best_known'] else None
    rows=bounds.get('ordinary_cases',cases) if bounds else cases
    elementary=bounds.get('elementary') if bounds else spec_bound(s)
    required=bounds.get('required') if bounds else elementary
    first=construct0+cold if construct0 is not None and cold is not None and s['usage'] not in PREPARED else None
    extras=next((m.get('result',{}).get('engine_extras') for m in reversed(r.get('measurements',[]))
                 if m['stage'] in ('warm','cold') and m.get('result',{}).get('engine_extras')),None)
    return dict(grid=s.get('grid'),set=s.get('set'),space=s.get('space'),model=s.get('model'),adapt=s.get('adapt'),
        arity=' '.join(map(str,s['arity'])) if 'arity' in s else None,
        lower_bound=elementary,required_bound=required,best_known=best,
        best_known_source=known['source'] if known else None,
        rows_over_best_known=ratio(cases,best),rows_over_lower_bound=ratio(rows,required),
        minimum=s.get('minimum'),first_call_seconds=first,
        engine_extras=json.dumps(extras,sort_keys=True) if extras else None)

def flatten(study,r,table={}):
    s=r['spec']; measurements=r.get('measurements',[])
    calls=[m for m in measurements if m['stage'] in ('warm','cold')]
    warm=[m for m in measurements if m['stage']=='warm']
    last=calls[-1] if calls else {}; result=last.get('result',{});search=last.get('search',{})
    prepare=next((m for m in measurements if m['stage']=='prepare'),{})
    cold=next((m for m in measurements if m['stage']=='cold'),{})
    construct=[m for m in measurements if m['stage']=='construct_warm']
    construct0=next((m['seconds'] for m in measurements if m['stage']=='construct'),None)
    exclusions=result.get('exclusions',result.get('ordinary',{}).get('exclusions',{}))
    validation=r.get('validation') or {}
    if isinstance(validation,str): validation={'exhaustive':validation}
    rss=r.get('os_peak_rss_bytes') or r.get('sampled_peak_rss_bytes')
    return dict(study=study,id=s['id'],family=s['family'],usage=s['usage'],solver=s['solver'],
        n=s['n'],v=s['v'],strength_requested=s['strength'],
        effective_strength=3 if s['usage']=='upgrade' else 0 if s['usage'] in ('factorial','excursion') else s['strength'],
        status=r['status'],stopped_stage=r.get('stopped_stage'),cases=result.get('cases',prepare.get('cases')),
        required=result.get('required'),negative_required=result.get('negative_required'),
        forbidden=exclusions.get('forbidden'),implied=exclusions.get('implied'),minimal_unresolved=exclusions.get('minimal_unresolved'),
        warm_seconds=r.get('warm_median_seconds'),warm_min_seconds=r.get('warm_min_seconds'),warm_max_seconds=r.get('warm_max_seconds'),
        cold_seconds=cold.get('seconds'),warm_allocated_bytes=r.get('warm_median_allocated_bytes'),
        peak_rss_bytes=rss,peak_footprint_bytes=r.get('os_peak_footprint_bytes'),
        result_retained_bytes=last.get('retained_bytes'),search_retained_bytes=search.get('search_retained_bytes'),
        primary_queries=search.get('queries'),primary_nodes=search.get('nodes'),primary_rule_checks=search.get('rule_checks'),
        assignment_memo=search.get('assignment_memo'),component_cache=search.get('component_cache'),rule_memo=search.get('rule_memo'),
        warm_construct_seconds=statistics.median(m['seconds'] for m in construct) if construct else None,
        completed_warm_runs=r.get('completed_warm_runs'),wall_seconds=r.get('wall_seconds'),
        exhaustive_validation=validation.get('exhaustive'),public_validation=validation.get('public_coverage'),
        feasibility_answer=result.get('status'),feasibility_nodes=result.get('nodes'),
        missing=result.get('missing'),bonus_strength=result.get('bonus',{}).get('strength'),
        **metrics(r,result.get('cases',prepare.get('cases')),construct0,cold.get('seconds'),table))

def archive(path):
    # Per-job directories are ignored in git; this compact archive preserves
    # specs, measurements, stderr, completed partial calls and limit events.
    target=path/'raw_jobs.zip'
    raw={}
    if target.exists():
        with zipfile.ZipFile(target) as z: raw={name:z.read(name) for name in z.namelist()}
    for p in sorted(path.glob('*/*')):
        if p.is_file() and p.suffix in ('.json','.jsonl','.txt'):
            raw[str(p.relative_to(path))]=p.read_bytes()
    temporary=path/'raw_jobs.tmp.zip'
    with zipfile.ZipFile(temporary,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for entry,data in raw.items(): z.writestr(entry,data)
    temporary.replace(target)
    metadata=json.loads((path/'results.json').read_text())['metadata']
    snapshot=path/'protocol_snapshot.zip'
    previous={}
    if snapshot.exists():
        with zipfile.ZipFile(snapshot) as z:
            previous={name:z.read(name) for name in z.namelist()}
    contents={}
    for name,digest in metadata.get('source_sha256',{}).items():
        p=pathlib.Path(name)
        if not p.is_absolute(): p=ROOT/p
        if p.is_relative_to(ROOT): entry='protocol/'+str(p.relative_to(ROOT))
        else: entry='protocol/external/'+hashlib.sha256(str(p).encode()).hexdigest()[:16]+'/'+p.name
        current=p.read_bytes() if p.exists() else b''
        data=current if hashlib.sha256(current).hexdigest()==digest else previous.get(entry,previous.get('protocol/'+p.name,b''))
        if hashlib.sha256(data).hexdigest()!=digest:
            raise RuntimeError(f'Cannot archive measured source {name}: current file changed and no matching snapshot exists')
        contents[entry]=data
    # Older protocols pinned these fixture dependencies by the source commit.
    # Preserve their existing snapshots if the working tree has since changed.
    for name in ('benchmark/fixtures.jl','test/checker.jl','test/random_problems.jl','test/fixtures.jl','test/fixture_model.jl'):
        entry='protocol/'+name
        if entry not in contents:
            contents[entry]=previous.get(entry,(ROOT/name).read_bytes())
    temporary=path/'protocol_snapshot.tmp.zip'
    with zipfile.ZipFile(temporary,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for entry,data in contents.items(): z.writestr(entry,data)
    temporary.replace(snapshot)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('results',type=pathlib.Path,nargs='+');p.add_argument('--out',type=pathlib.Path,required=True)
    p.add_argument('--archive',action='store_true')
    args=p.parse_args();rows=[];table=best_known_table()
    for source in args.results:
        data=json.loads(source.read_text());rows.extend(flatten(source.parent.name,r,table) for r in data['results'])
        if args.archive: archive(source.parent)
    with args.out.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
    print(f'{len(rows)} rows: {args.out}')
if __name__=='__main__': main()
