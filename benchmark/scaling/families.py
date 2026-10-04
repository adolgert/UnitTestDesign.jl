"""Generated benchmark families (plan §7.2). Stdlib only; run.py's --family selects them.

Each family is a list of job specs in the harness's format (README.md), with
`grid` naming the family. Specs use the worker's `arity`, `forbid`, `space`,
`model`, `stronger` and `adapt` fields (model_specs.jl) where an n × v space
won't do. A spec with more than EXPENSIVE_TARGETS targets, or whose targets
times its lower bound (a proxy for IPOG's work: each row scans the targets)
exceeds EXPENSIVE_COST, is marked `expensive`, runs once, and is left out
unless run.py gets --expensive. At 2798ecf on the Apple M2, IPOG's warm call
took about targets × rows / 5·10⁷ seconds over the study's uniform points, so
EXPENSIVE_COST is a call of roughly ten seconds.

| Family | What | Specs per solver, default + expensive |
|:--|:--|--:|
| mainstream | probe 16's r3 and r4 random spaces, each also with 1–4 scoped rules; bench12; the docs' examples | 341 |
| mainstream-r1 | probe 12/16's r1 random spaces, 2–5 values | 150 |
| smallest | t + 1 and t + 2 parameters, t = 2, 3: 2–12 values equal, probe 20's mixed, random mixed | 98 |
| uniform-pp | t = 2, 3; prime-power v; k in {v+1, 2v, v²+v+1, 50, 100, 250} | 76 + 53 |
| uniform-npp | v in {6, 10, 12, 15, 20, 24}; the same k, and at t = 2 every k in v+2..3v | 166 + 66 |
| strength | t = 2–5, v = 2–5, k in {10, 20, 50, 100}; t = 6 at k in {10, 20}, v in {2, 3} | 41 + 27 |
| exact | probe 25's shapes with known minima or bounds; the r2 random spaces (2–3 values) | 177 |
| adapted | six points of each family above and of casa at t = 2, bench12 and docs-solver, each with one of five changes | 220 |
| casa | CASA's 35 constrained models, t = 2, 3 (datasets.py fetch casa) | 70 |
| ct-comp | IWCT 2023's 240 models; t = 2, and t = 3–5 expensive (datasets.py fetch ct-comp) | 240 + 718 |
| cart | State of the CArt's 295 models; t = 2, and t = 3–5 expensive (datasets.py fetch cart) | 295 + 791 |

The README has what each costs to run.
"""
import hashlib, json, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RANDOM_SPACES = HERE / 'families' / 'random_spaces.json'
EXPENSIVE_TARGETS = 2_000_000
EXPENSIVE_COST = 400_000_000
ADAPTATIONS = ('seed', 'stronger', 'noop_scoped', 'forbid3', 'invalid')
BENCH12 = [4, 4, 4, 4, 3, 3, 3, 3, 2, 2, 2, 2]
MIX1 = [7, 7, 7, 7, 5, 4, 3, 3, 2, 2, 2, 2]


def targets(arity, t):
    """The number of t-way targets: the elementary symmetric polynomial e_t of the value counts."""
    e = [1] + [0] * t
    for a in arity:
        for j in range(t, 0, -1): e[j] += e[j - 1] * a
    return e[t]


def bound(arity, t):
    """The elementary lower bound: the product of the t largest value counts."""
    out = 1
    for a in sorted(arity, reverse=True)[:t]: out *= a
    return out


def job(grid, name, arity, strength, solver, runs, ladder=None, by_targets=True, **extra):
    """One spec. Uniform spaces without a named space or model stay n × v; others carry `arity`.
    With `by_targets`, a spec over EXPENSIVE_TARGETS targets or EXPENSIVE_COST is marked expensive."""
    extra = {k: v for k, v in extra.items() if v is not None}
    s = dict(id=f'{grid}-{name}-{solver}-t{strength}', ladder=f'{grid}-{ladder or name}-{solver}-t{strength}',
             n=len(arity), v=max(arity), family='none', usage='reuse', solver=solver, strength=strength,
             runs=runs, grid=grid)
    if len(set(arity)) > 1 or 'space' in extra or 'model' in extra: s['arity'] = list(arity)
    s.update(extra)
    s['targets'] = targets(arity, strength)
    s['cost'] = s['targets'] * bound(arity, strength)
    if by_targets and (s['targets'] > EXPENSIVE_TARGETS or s['cost'] > EXPENSIVE_COST): s.update(expensive=True, runs=1)
    return s


def random_spaces():
    return json.loads(RANDOM_SPACES.read_text())['spaces']


def random_set(sets, solvers, runs, grid='mainstream'):
    """The random spaces of `sets`, with ids mainstream-<space id>-<solver>-t<t> whatever their `grid` label."""
    return [dict(job('mainstream', s['id'], s['arity'], s['strength'], solver, runs, set=s['set'], forbid=s.get('forbid')),
                 grid=grid)
            for solver in solvers for s in random_spaces() if s['set'] in sets]


def mainstream(solvers, runs):
    """Probe 16's r3 (2-7 values, Phase 1's gate) and r4 (strength 3), each also with rules; bench12; the docs."""
    jobs = random_set(('r3', 'r3-rules', 'r4', 'r4-rules'), solvers, runs)
    for solver in solvers:
        for t in (2, 3): jobs.append(job('mainstream', 'bench12', BENCH12, t, solver, runs, space='bench12'))
        for name, arity, t, stronger in DOCS:
            label = name + ('-stronger' if stronger else '')
            jobs.append(job('mainstream', label, arity, t, solver, runs, space=name, stronger=stronger))
    return jobs


# The docs' examples (spaces.jl) with the call the manual makes.
DOCS = [
    ('docs-solver', [2, 3, 2], 2, None), ('docs-solver-plain', [2, 3, 2], 2, None),
    ('docs-wide', [3, 3, 3, 3], 3, None), ('docs-wide', [3, 3, 3, 3], 2, [[['n', 'tol', 'kind'], 3]]),
    ('docs-negative', [2, 3, 2], 2, None), ('docs-hilbert', [10, 10, 2, 3, 4], 2, None),
    ('docs-rules', [3, 2, 2], 2, None), ('docs-spend', [4] * 40, 2, None),
    ('docs-spend', [4] * 40, 2, [[[3, 4, 5, 6], 3]]), ('docs-spend', [4] * 40, 3, None),
    ('docs-periodic', [3, 2, 2], 2, None), ('docs-periodic-invalid', [3, 2, 2], 2, None),
    ('docs-diagnose', [3, 3, 2, 2], 2, None), ('docs-types', [5, 3, 3], 2, None),
    ('docs-smooth', [3, 3, 3, 3], 2, None), ('docs-campaign', [3, 3, 3, 3, 3, 2], 2, [[['R0', 'contact', 'vaccination'], 3]]),
    ('docs-ci', [3, 3, 2, 2], 2, None), ('docs-interp', [3, 3, 2, 2], 2, None), ('docs-generic', [3, 3, 3], 2, None),
]
# Probe 20's mixed spaces on t + 1 parameters.
PROBE20 = {2: [[5, 4, 3], [6, 4, 2], [8, 5, 5], [5, 5, 3], [10, 6, 3], [6, 6, 4]],
           3: [[5, 4, 3, 2], [6, 5, 4, 3], [4, 4, 3, 3], [5, 5, 5, 2], [8, 4, 4, 2]]}


def zero_sum_minimum(arity, t):
    """With t + 1 parameters the minimum is the bound, the product of the t largest (§2.2, the zero-sum array)."""
    return bound(arity, t)


def smallest(solvers, runs):
    jobs = []
    for solver in solvers:
        for t in (2, 3):
            for k in (t + 1, t + 2):
                for v in range(2, 13):
                    jobs.append(job('smallest', f'k{k}-v{v}', [v] * k, t, solver, runs, ladder=f'k{k}',
                                    minimum=zero_sum_minimum([v] * k, t) if k == t + 1 else None))
                for i, sizes in enumerate(PROBE20[t], 1):
                    arity = sizes if k == t + 1 else sizes + [min(sizes)]
                    jobs.append(job('smallest', f'k{k}-probe20-{i}', arity, t, solver, runs,
                                    minimum=zero_sum_minimum(arity, t) if k == t + 1 else None))
            for s in random_spaces():
                if s['set'].startswith(f's{t}-'):
                    k = len(s['arity'])
                    jobs.append(job('smallest', f'k{k}-{s["id"]}', s['arity'], t, solver, runs, set=s['set'],
                                    minimum=zero_sum_minimum(s['arity'], t) if k == t + 1 else None))
    return jobs


def uniform(grid, values, solvers, runs, wide=False):
    jobs = []
    for solver in solvers:
        for t in (2, 3):
            for v in values:
                ks = {v + 1, 2 * v, v * v + v + 1, 50, 100, 250}
                if wide and t == 2: ks |= set(range(v + 2, 3 * v + 1))
                for k in sorted(k for k in ks if k > t):
                    jobs.append(job(grid, f'v{v}-k{k}', [v] * k, t, solver, runs, ladder=f'v{v}'))
    return jobs


def strength(solvers, runs):
    jobs = []
    for solver in solvers:
        for t in (2, 3, 4, 5, 6):
            for v in (2, 3, 4, 5) if t < 6 else (2, 3):
                for k in (10, 20, 50, 100) if t < 6 else (10, 20):
                    jobs.append(job('strength', f'v{v}-k{k}', [v] * k, t, solver, runs, ladder=f'v{v}'))
    return jobs


# Probe 25, part 1: (t, k, v, minimum) for uniform shapes whose minimum is known.
PROBE25_UNIFORM = [(2, 10, 2, 6), (2, 15, 2, 7), (2, 4, 3, 9), (2, 5, 3, 11), (2, 6, 3, 12), (2, 7, 3, 12),
                   (2, 8, 3, 13), (2, 5, 4, 16), (2, 6, 4, 19), (2, 6, 5, 25), (2, 7, 5, 29),
                   (3, 5, 2, 10), (3, 6, 2, 12), (3, 8, 2, 12), (3, 11, 2, 12), (3, 5, 3, 33), (3, 6, 3, 33)]
# Probe 25, part 1: (space, arity, t, lower, upper); lower == upper where the SAT solver proved the minimum
# within 60 s per question, else the range it left (probe 25's .out).
PROBE25_NAMED = [('probe25-warmup', [2, 2, 2, 2], 2, 5, 5), ('docs-smooth', [3, 3, 3, 3], 2, 11, 11),
                 ('probe25-flags', [2] * 12, 2, 7, 7), ('probe25-flags', [2] * 12, 3, 18, 18),
                 ('bench12', BENCH12, 2, 17, 18), ('probe25-mix1', MIX1, 2, 49, 49),
                 ('probe25-mix1-forbid3', MIX1, 2, 50, 50), ('probe25-mix1-neq', MIX1, 2, 49, 50),
                 ('probe25-mix1-less', MIX1, 2, 49, 51), ('probe25-neighbours', [4] * 10, 2, 17, 24)]


def exact(solvers, runs):
    jobs = []
    for solver in solvers:
        for t, k, v, known in PROBE25_UNIFORM:
            jobs.append(job('exact', f'k{k}-v{v}', [v] * k, t, solver, runs, minimum=known,
                            minimum_source='known minimum, as probe 25 lists it'))
        for name, arity, t, lower, upper in PROBE25_NAMED:
            jobs.append(job('exact', name, arity, t, solver, runs, space=name,
                            minimum=lower if lower == upper else None, minimum_range=[lower, upper],
                            minimum_source='probe 25: SAT, 60 s per question'))
        for s in random_spaces():
            if s['set'] == 'r2': jobs.append(job('exact', s['id'], s['arity'], s['strength'], solver, runs, set='r2'))
    return jobs


def imported(dataset, strengths, expensive_from, solvers, runs):
    """Specs for the imported models of a dataset in the cache; [] with a note if none are there.
    They search with the package's default feasibility_limit, 1,000,000 nodes per question, not
    the harness's 100,000: these are other people's constrained models, measured as a user would
    run them (at 100,000, ct-comp's NUMC_4 stops classifying at strength 2)."""
    sys.path.insert(0, str(HERE))
    import datasets
    found = datasets.models(dataset)
    if not found:
        print(f'note: no {dataset} models in {datasets.CACHE / dataset}; run python3 benchmark/scaling/datasets.py fetch {dataset}',
              file=sys.stderr)
    jobs = []
    for solver in solvers:
        for path, record in found:
            for t in strengths:
                if len(record['arity']) < t: continue
                # Imported models are marked expensive by strength only: the CASA set at
                # strength 3 is Phase 1's gate (plan §5.3), whatever its target count.
                s = job(dataset, record['name'], record['arity'], t, solver, runs, by_targets=False, nodes=1_000_000,
                        model=str(path.relative_to(ROOT)), model_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
                if t >= expensive_from: s.update(expensive=True, runs=1)
                jobs.append(s)
    return jobs


def adapted(solvers, runs):
    """Six points of each family, spread evenly over its default (not expensive) specs, and
    mainstream's bench12 and docs-solver at strength 2, each with each adaptation."""
    jobs = []
    for base in ('mainstream', 'smallest', 'uniform-pp', 'uniform-npp', 'strength', 'exact', 'casa'):
        # CASA at strength 3 mostly exceeds the 2 GiB guard at 2798ecf (README), so adapt its strength-2 runs.
        pool = [s for s in FAMILIES[base](solvers[:1], runs)
                if not s.get('expensive') and not (base == 'casa' and s['strength'] > 2)]
        picks = pool[::max(1, len(pool) // 6)][:6]
        if base == 'mainstream': picks += [s for s in pool if s.get('space') in ('bench12', 'docs-solver') and s['strength'] == 2]
        for solver in solvers:
            for s in picks:
                for adaptation in ADAPTATIONS:
                    if adaptation == 'forbid3' and s['n'] < 3: continue
                    if adaptation == 'stronger' and s['strength'] + 1 > min(6, s['n']): continue
                    name = s['id'][len(base) + 1:].rsplit('-', 2)[0]
                    a = dict(s, id=f'adapted-{adaptation}-{base}-{name}-{solver}-t{s["strength"]}',
                             ladder=f'adapted-{adaptation}-{base}-{name}-{solver}-t{s["strength"]}',
                             solver=solver, grid='adapted', base_grid=base, adapt=adaptation)
                    jobs.append(a)
    return jobs


FAMILIES = {
    'mainstream': mainstream,
    'mainstream-r1': lambda solvers, runs: random_set(('r1',), solvers, runs, grid='mainstream-r1'),
    'smallest': smallest,
    'uniform-pp': lambda solvers, runs: uniform('uniform-pp', (2, 3, 4, 5, 7, 8, 9, 11, 13, 16, 25), solvers, runs),
    'uniform-npp': lambda solvers, runs: uniform('uniform-npp', (6, 10, 12, 15, 20, 24), solvers, runs, wide=True),
    'strength': strength,
    'exact': exact,
    'adapted': adapted,
    'casa': lambda solvers, runs: imported('casa', (2, 3), 99, solvers, runs),
    'ct-comp': lambda solvers, runs: imported('ct-comp', (2, 3, 4, 5), 3, solvers, runs),
    'cart': lambda solvers, runs: imported('cart', (2, 3, 4, 5), 3, solvers, runs),
}


def select(names, solvers=('ipog',), runs=3, expensive=False):
    """The specs of the named families ("all" for every one), without expensive points unless asked."""
    names = list(FAMILIES) if 'all' in names else names
    unknown = [n for n in names if n not in FAMILIES]
    if unknown: raise SystemExit(f'unknown family {unknown}; choose from {", ".join(FAMILIES)} or all')
    jobs = [s for name in names for s in FAMILIES[name](list(solvers), runs)]
    return [s for s in jobs if expensive or not s.get('expensive')]


def uniform_shapes(jobs):
    """(t, v, k) of every uniform, unconstrained covering spec: the shapes the best-known table must hold."""
    shapes = set()
    for s in jobs:
        if s['family'] != 'none' or s['usage'] not in ('reuse', 'core', 'public', 'named', 'positional'): continue
        if any(f in s for f in ('forbid', 'space', 'model', 'adapt', 'stronger')): continue
        if 'arity' in s and len(set(s['arity'])) > 1: continue
        shapes.add((s['strength'], s['v'], s['n']))
    return sorted(shapes)
