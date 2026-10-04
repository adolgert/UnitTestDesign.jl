#!/usr/bin/env python3
"""Download external benchmark models and import them as scoped forbidden tuples. Stdlib only.

    python3 benchmark/scaling/datasets.py fetch casa      # CASA's 35 constrained models
    python3 benchmark/scaling/datasets.py fetch cart      # State of the CArt's 295 models (ACTS dialect)
    python3 benchmark/scaling/datasets.py fetch ct-comp   # IWCT 2023 CT competition, 240 models (ACTS dialect)
    python3 benchmark/scaling/datasets.py list
    python3 benchmark/scaling/datasets.py import-casa M.citmodel M.constraints OUT.json
    python3 benchmark/scaling/datasets.py import-acts M.txt OUT.json

Downloads go to benchmark/scaling/cache/<dataset>/raw/ and imports to
benchmark/scaling/cache/<dataset>/<model>.json. The cache is ignored by git:
none of these models may be committed (plan §7.2, D6). CASA's models carry no
license; the other two sets are CC BY-NC 2.0. Each import is the JSON that
the worker's `model` spec field reads (model_specs.jl):

    {"arity": [...], "names": [...] or null, "values": [[label, ...], ...] or null,
     "forbid": [{"scope": [p, ...], "tuples": [[x, ...], ...], "text": "..."}], ...}

Positions and values count from 1. Every constraint becomes one scoped rule
over exactly the parameters it mentions, listing the value tuples it
forbids, so scopes stay as narrow as the model wrote them. An ACTS
constraint whose top level is a conjunction becomes one rule per conjunct.
A rule over more than TUPLE_LIMIT value combinations, more than the worker
tabulates, keeps its expression instead, `{"scope": [...], "expr": tree}`,
and the worker compiles it to a predicate before timing starts.
"""
import argparse, hashlib, io, itertools, json, pathlib, re, subprocess, sys, tarfile, urllib.error, urllib.request

HERE = pathlib.Path(__file__).resolve().parent
CACHE = HERE / 'cache'
TUPLE_LIMIT = 100_000   # the worker's tabulation_limit: larger scopes are lazy rules in the package

# CASA's site (cse.unl.edu/citportal/tools/casa/) answered 404 on 2026-10-04,
# and the Internet Archive kept the page but not the models. The 35 models
# are mirrored, unchanged in CASA's format, by the CCAG repository (MIT
# license for its code; the models are CASA's), pinned here to one commit.
CASA_MIRROR = 'https://raw.githubusercontent.com/GIST-NJU/CCAG/e3aff2d6384888093dbe878d22a167e419242632/benchmark/'
CASA_MODELS = ['apache', 'bugzilla', 'gcc', 'spins', 'spinv'] + [f'benchmark_{i}' for i in range(1, 31)]
ZENODO = {
    # dataset: (archive URL, md5 from the Zenodo record, member prefix)
    'cart': ('https://zenodo.org/api/records/10079836/files/models.tar.gz/content',
             'df74c91a58c4c9389283ebd1474a3580', 'acts/'),
    'ct-comp': ('https://zenodo.org/api/records/7852557/files/ct-comp-iwct2023-models.tar.gz/content',
                'e7972c60c2a73b73086e941e5e0a111e', 'acts/'),
}


def download(url):
    """The body at `url`. Falls back to curl where Python has no CA certificates."""
    request = urllib.request.Request(url, headers={'User-Agent': 'UnitTestDesign.jl benchmark datasets'})
    try:
        with urllib.request.urlopen(request, timeout=120) as response: return response.read()
    except urllib.error.URLError as e:
        if 'CERTIFICATE_VERIFY_FAILED' not in str(e): raise
        return subprocess.run(['curl', '-fsSL', '--max-time', '300', url], check=True, capture_output=True).stdout


def sha256(data): return hashlib.sha256(data).hexdigest()


def forbidden_tuples(domains, violated):
    """Value tuples (1-based) over `domains` (lists of values) for which `violated(values)` holds."""
    out = []
    for combo in itertools.product(*[list(enumerate(d, 1)) for d in domains]):
        if violated(tuple(x for _, x in combo)): out.append([i for i, _ in combo])
    return out


## CASA: .citmodel and .constraints

def read_casa(model_text, constraints_text):
    """CASA's format, as its files are written: the model is the strength, the
    number of parameters and the value counts; the constraints are a clause
    count, then per clause its literal count and the literals, each a sign and
    a value index. Value indices count every parameter's values in order from 0.
    A clause is a disjunction: `- x` holds when value x is not chosen, `+ x`
    when it is. A forbidden tuple (x, y) is the clause `- x - y`."""
    m = model_text.split()
    strength, k = int(m[0]), int(m[1])
    arity = [int(a) for a in m[2:2 + k]]
    if len(arity) != k: raise ValueError(f'model lists {len(arity)} value counts for {k} parameters')
    offsets = list(itertools.accumulate([0] + arity[:-1]))
    owner = {offsets[p] + x: (p, x) for p in range(k) for x in range(arity[p])}
    tokens = constraints_text.split() if constraints_text else ['0']
    pos = 0
    def take():
        nonlocal pos
        pos += 1
        return tokens[pos - 1]
    clauses = []
    for _ in range(int(take())):
        literals = []
        for _ in range(int(take())):
            sign, index = take(), int(take())
            if sign not in '+-' or index not in owner: raise ValueError(f'bad literal {sign} {index}')
            literals.append((sign == '+', *owner[index]))
        clauses.append(literals)
    if pos != len(tokens): raise ValueError('trailing tokens in constraints file')
    return strength, arity, clauses


def import_casa(model_text, constraints_text, name):
    strength, arity, clauses = read_casa(model_text, constraints_text)
    forbid, skipped = [], []
    for c, literals in enumerate(clauses, 1):
        scope = sorted({p for _, p, _ in literals})
        domains = [list(range(arity[p])) for p in scope]
        where = {p: i for i, p in enumerate(scope)}
        # The clause is violated when every literal is false.
        def violated(xs, literals=literals, where=where):
            return all((xs[where[p]] == x) != positive for positive, p, x in literals)
        tuples = forbidden_tuples(domains, violated)
        text = f'CASA clause {c}: ' + ' || '.join(f'p{p + 1} {"==" if positive else "!="} {x + 1}' for positive, p, x in literals)
        if not tuples:
            skipped.append(dict(clause=c, reason='excludes nothing', text=text)); continue
        forbid.append(dict(scope=[p + 1 for p in scope], tuples=tuples, text=text))
    return dict(name=name, format='casa', strength=strength, arity=arity, names=None, values=None,
                forbid=forbid, clauses=len(clauses), skipped=skipped)


## ACTS: [System], [Parameter], [Constraint]

TOKEN = re.compile(r'\s*(?:(=>|&&|\|\||!=|<=|>=|==|[=<>!+\-*/%()])|("[^"]*")|([A-Za-z_][A-Za-z0-9_.]*)|(\d+))')


def tokenize(text):
    out, pos = [], 0
    text = text.rstrip()
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m or m.end() == pos: raise ValueError(f'cannot read {text[pos:pos + 20]!r}')
        op, string, word, number = m.groups()
        out.append(('op', op) if op else ('str', string[1:-1]) if string else ('word', word) if word else ('num', int(number)))
        pos = m.end()
    return out


class Expression:
    """ACTS constraint syntax: `=>` (lowest, right-associative), `||`, `&&`,
    comparisons `= == != < <= > >=`, `+ -`, `* / %`, unary `!` and `-`,
    parentheses; parameter names, integers, `true`/`false`, quoted enum values."""
    def __init__(self, text, parameters):
        self.tokens, self.pos, self.parameters, self.used = tokenize(text), 0, parameters, set()
        self.tree = self.implication()
        if self.pos != len(self.tokens): raise ValueError(f'unexpected {self.tokens[self.pos]}')

    def peek(self): return self.tokens[self.pos] if self.pos < len(self.tokens) else (None, None)
    def accept(self, *ops):
        kind, value = self.peek()
        if kind == 'op' and value in ops: self.pos += 1; return value
        return None
    def implication(self):
        left = self.disjunction()
        return ('=>', left, self.implication()) if self.accept('=>') else left
    def disjunction(self):
        node = self.conjunction()
        while self.accept('||'): node = ('||', node, self.conjunction())
        return node
    def conjunction(self):
        node = self.comparison()
        while self.accept('&&'): node = ('&&', node, self.comparison())
        return node
    def comparison(self):
        node = self.additive()
        op = self.accept('=', '==', '!=', '<', '<=', '>', '>=')
        return (('=' if op == '==' else op), node, self.additive()) if op else node
    def additive(self):
        node = self.multiplicative()
        while (op := self.accept('+', '-')): node = (op, node, self.multiplicative())
        return node
    def multiplicative(self):
        node = self.unary()
        while (op := self.accept('*', '/', '%')): node = (op, node, self.unary())
        return node
    def unary(self):
        if self.accept('!'): return ('!', self.unary())
        if self.accept('-'): return ('neg', self.unary())
        return self.primary()
    def primary(self):
        if self.accept('('):
            node = self.implication()
            if not self.accept(')'): raise ValueError('missing )')
            return node
        kind, value = self.peek()
        self.pos += 1
        if kind == 'word' and value in self.parameters: self.used.add(value); return ('param', value)
        if kind == 'word' and value in ('true', 'false'): return ('lit', value == 'true')
        if kind in ('num', 'str'): return ('lit', value)
        if kind == 'word': return ('lit', value)  # an unquoted enum value
        raise ValueError(f'unexpected {kind} {value}')

    def compile(self, node=None):
        """A Python function of a dict {parameter: value} for the tree."""
        node = self.tree if node is None else node
        op = node[0]
        if op == 'param': name = node[1]; return lambda env: env[name]
        if op == 'lit': value = node[1]; return lambda env: value
        if op == '!': f = self.compile(node[1]); return lambda env: not f(env)
        if op == 'neg': f = self.compile(node[1]); return lambda env: -f(env)
        a, b = self.compile(node[1]), self.compile(node[2])
        return {'=>': lambda env: (not a(env)) or b(env), '||': lambda env: a(env) or b(env),
                '&&': lambda env: a(env) and b(env), '=': lambda env: a(env) == b(env),
                '!=': lambda env: a(env) != b(env), '<': lambda env: a(env) < b(env),
                '<=': lambda env: a(env) <= b(env), '>': lambda env: a(env) > b(env),
                '>=': lambda env: a(env) >= b(env), '+': lambda env: a(env) + b(env),
                '-': lambda env: a(env) - b(env), '*': lambda env: a(env) * b(env),
                '/': lambda env: a(env) // b(env), '%': lambda env: a(env) % b(env)}[op]


def conjuncts(node):
    """The top-level conjuncts of a tree, so each becomes its own narrower rule."""
    return conjuncts(node[1]) + conjuncts(node[2]) if node[0] == '&&' else [node]


def tree_json(node):
    """The tree as JSON lists: ["param", name], ["lit", value], [op, child, ...]."""
    return [node[0], node[1]] if node[0] in ('param', 'lit') else [node[0]] + [tree_json(c) for c in node[1:]]


def used_parameters(node):
    if node[0] == 'param': return {node[1]}
    return set().union(*[used_parameters(c) for c in node[1:] if isinstance(c, tuple)]) if node[0] != 'lit' else set()


def read_acts(text):
    section, names, domains, constraints, system = None, [], [], [], None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith('--'): continue
        if line.startswith('[') and line.endswith(']'): section = line; continue
        if section == '[System]' and line.startswith('Name:'): system = line[5:].strip()
        elif section == '[Parameter]':
            m = re.match(r'(\S+)\s*\((\w+)\)\s*:\s*(.*)$', line)
            if not m: raise ValueError(f'cannot read parameter line {line!r}')
            name, kind, values = m.group(1), m.group(2), [x.strip() for x in m.group(3).split(',')]
            if kind == 'boolean': values = [x == 'true' for x in values]
            elif kind == 'int': values = [int(x) for x in values]
            elif kind != 'enum': raise ValueError(f'unknown parameter type {kind}')
            names.append(name); domains.append(values)
        elif section == '[Constraint]': constraints.append(line)
        elif section is not None and section not in ('[System]',):
            raise ValueError(f'unsupported section {section}')
    return system, names, domains, constraints


def import_acts(text, name):
    system, names, domains, constraints = read_acts(text)
    index = {n: i for i, n in enumerate(names)}
    forbid, skipped = [], []
    for c, line in enumerate(constraints, 1):
        expression = Expression(line, set(names))
        for part in conjuncts(expression.tree):
            scope = sorted((index[n] for n in used_parameters(part)))
            size = 1
            for p in scope: size *= len(domains[p])
            text = f'ACTS constraint {c}' + ('' if part is expression.tree else ' (one conjunct)')
            if size > TUPLE_LIMIT:
                forbid.append(dict(scope=[p + 1 for p in scope], expr=tree_json(part), text=text)); continue
            f = expression.compile(part)
            tuples = forbidden_tuples([domains[p] for p in scope],
                                      lambda xs, f=f, scope=scope: not f({names[p]: x for p, x in zip(scope, xs)}))
            if not tuples: skipped.append(dict(constraint=c, reason='excludes nothing', text=text)); continue
            forbid.append(dict(scope=[p + 1 for p in scope], tuples=tuples, text=text))
    return dict(name=name, system=system, format='acts', arity=[len(d) for d in domains], names=names,
                values=domains, forbid=forbid, constraints=len(constraints), skipped=skipped)


## Fetching

def write(path, record, sources):
    record['source'] = sources
    path.write_text(json.dumps(record) + '\n')


def fetch_casa():
    raw = CACHE / 'casa' / 'raw'; raw.mkdir(parents=True, exist_ok=True)
    for model in CASA_MODELS:
        texts = {}
        for suffix in ('model', 'constraints'):
            path = raw / f'{model}.{suffix}'
            if not path.exists(): path.write_bytes(download(CASA_MIRROR + path.name))
            texts[suffix] = path.read_bytes()
        record = import_casa(texts['model'].decode(), texts['constraints'].decode(), model)
        write(CACHE / 'casa' / f'{model}.json', record,
              dict(url=CASA_MIRROR, files={f'{model}.{s}': sha256(d) for s, d in texts.items()}))
        print(f'casa/{model}: {len(record["arity"])} parameters, {len(record["forbid"])} rules', file=sys.stderr)


def fetch_zenodo(dataset):
    url, md5, prefix = ZENODO[dataset]
    raw = CACHE / dataset / 'raw'; raw.mkdir(parents=True, exist_ok=True)
    archive = raw / url.split('/')[-2]
    if not archive.exists(): archive.write_bytes(download(url))
    data = archive.read_bytes()
    if hashlib.md5(data).hexdigest() != md5: raise RuntimeError(f'{archive}: md5 differs from the Zenodo record')
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        for member in sorted(tar.getmembers(), key=lambda m: m.name):
            if not (member.isfile() and member.name.startswith(prefix) and member.name.endswith('.txt')): continue
            text = tar.extractfile(member).read()
            name = pathlib.Path(member.name).stem
            record = import_acts(text.decode(), name)
            write(CACHE / dataset / f'{name}.json', record,
                  dict(url=url, archive_md5=md5, member=member.name, sha256=sha256(text)))
            lazy = sum('expr' in e for e in record['forbid'])
            print(f'{dataset}/{name}: {len(record["arity"])} parameters, {len(record["forbid"])} rules'
                  + (f', {lazy} kept as expressions' if lazy else ''), file=sys.stderr)


def models(dataset):
    """The imported models of a dataset in the cache, as (path, record), sorted by name."""
    directory = CACHE / dataset
    if not directory.exists(): return []
    return [(p, json.loads(p.read_text())) for p in sorted(directory.glob('*.json'))]


def main():
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = a.add_subparsers(dest='command', required=True)
    f = sub.add_parser('fetch'); f.add_argument('dataset', choices=['casa', 'cart', 'ct-comp'])
    sub.add_parser('list')
    c = sub.add_parser('import-casa'); c.add_argument('model'); c.add_argument('constraints'); c.add_argument('out')
    t = sub.add_parser('import-acts'); t.add_argument('model'); t.add_argument('out')
    args = a.parse_args()
    if args.command == 'fetch':
        fetch_casa() if args.dataset == 'casa' else fetch_zenodo(args.dataset)
    elif args.command == 'list':
        for dataset in ('casa', 'cart', 'ct-comp'):
            found = models(dataset)
            lazy = sum(any('expr' in e for e in r['forbid']) for _, r in found)
            print(f'{dataset}: {len(found)} imported models' + (f', {lazy} with rules kept as expressions' if lazy else ''))
    elif args.command == 'import-casa':
        model, constraints = pathlib.Path(args.model), pathlib.Path(args.constraints)
        record = import_casa(model.read_text(), constraints.read_text() if constraints.exists() else '', model.stem)
        write(pathlib.Path(args.out), record, dict(files={model.name: sha256(model.read_bytes())}))
    else:
        model = pathlib.Path(args.model)
        write(pathlib.Path(args.out), import_acts(model.read_text(), model.stem), dict(files={model.name: sha256(model.read_bytes())}))


if __name__ == '__main__': main()
