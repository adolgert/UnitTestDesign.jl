"""Checks of the CASA and ACTS importers on small hand-written models (no download).

The last two tests run real Julia workers, as test_adapters.py does: they build
the imported models through the `model` spec field, run IPOG with the
exhaustive oracle, and count the valid rows of the full product, which must
equal a brute-force count over the original constraints.
"""
import importlib.util, itertools, json, os, pathlib, shutil, tempfile, types, unittest

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('scaling_datasets', HERE / 'datasets.py')
datasets = importlib.util.module_from_spec(spec); spec.loader.exec_module(datasets)
spec = importlib.util.spec_from_file_location('scaling_datasets_runner', HERE / 'run.py')
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
JULIA = os.environ.get('JULIA', 'julia')

# Three parameters of 2, 3 and 2 values: value indices 0-1, 2-4 and 5-6.
CASA_MODEL = '2\n3\n2 3 2\n'
CASA_CONSTRAINTS = '''3
2
- 0 - 2
3
+ 1 - 4 - 5
2
- 2 - 3
'''

ACTS_MODEL = '''[System]
-- a comment
Name: tiny

[Parameter]
-- general syntax is parameter_name : value1, value2, ...
Mode (enum) : fast, exact, debug
Gpu (boolean) : true, false
Size (int) : -2, 0, 3
Level (int) : 1, 2

[Constraint]
(Mode = "exact") => (Gpu = false)
((Size >= 0) || (! (Level != 2))) && (Mode != "debug" || Size < 3)
Level + Size > -1
'''


def acts_valid_rows(text):
    """Brute force: the full rows that satisfy every ACTS constraint, as written."""
    _, names, domains, constraints = datasets.read_acts(text)
    checks = [datasets.Expression(c, set(names)).compile() for c in constraints]
    return sum(all(f(dict(zip(names, row))) for f in checks) for row in itertools.product(*domains))


class ImporterTests(unittest.TestCase):
    def test_casa_clauses_become_forbidden_tuples(self):
        record = datasets.import_casa(CASA_MODEL, CASA_CONSTRAINTS, 'tiny')
        self.assertEqual(record['arity'], [2, 3, 2])
        self.assertEqual(record['strength'], 2)
        rules = [(r['scope'], r['tuples']) for r in record['forbid']]
        self.assertEqual(rules[0], ([1, 2], [[1, 1]]))               # - 0 - 2: p1 = 1 with p2 = 1
        self.assertEqual(rules[1], ([1, 2, 3], [[1, 3, 1]]))         # + 1 - 4 - 5: p1 = 2 or p2 != 3 or p3 != 1
        self.assertEqual(record['skipped'][0]['clause'], 3)           # p2 is never both 1 and 2
        self.assertEqual(len(record['forbid']), 2)

    def test_casa_rejects_bad_files(self):
        with self.assertRaises(ValueError): datasets.import_casa('2\n3\n2 3\n', '0\n', 'short')
        with self.assertRaises(ValueError): datasets.import_casa(CASA_MODEL, '1\n1\n- 7\n', 'range')
        with self.assertRaises(ValueError): datasets.import_casa(CASA_MODEL, '1\n1\n- 0 - 1\n', 'trailing')

    def test_acts_rules_are_narrow_and_exact(self):
        record = datasets.import_acts(ACTS_MODEL, 'tiny')
        self.assertEqual(record['names'], ['Mode', 'Gpu', 'Size', 'Level'])
        self.assertEqual(record['arity'], [3, 2, 3, 2])
        self.assertEqual(record['values'][1], [True, False])
        scopes = [r['scope'] for r in record['forbid']]
        # The second constraint's two conjuncts become two rules.
        self.assertEqual(scopes, [[1, 2], [3, 4], [1, 3], [3, 4]])
        self.assertEqual(record['forbid'][0]['tuples'], [[2, 1]])    # exact with a GPU
        valid = [row for row in itertools.product(*[range(1, a + 1) for a in record['arity']])
                 if not any(tuple(row[p - 1] for p in r['scope']) in map(tuple, r['tuples']) for r in record['forbid'])]
        self.assertEqual(len(valid), acts_valid_rows(ACTS_MODEL))

    def test_acts_keeps_wide_rules_as_expressions(self):
        limit = datasets.TUPLE_LIMIT
        try:
            datasets.TUPLE_LIMIT = 0
            record = datasets.import_acts(ACTS_MODEL, 'tiny')
        finally:
            datasets.TUPLE_LIMIT = limit
        self.assertTrue(all('expr' in r and 'tuples' not in r for r in record['forbid']))
        self.assertEqual(record['forbid'][0]['expr'], ['=>', ['=', ['param', 'Mode'], ['lit', 'exact']],
                                                       ['=', ['param', 'Gpu'], ['lit', False]]])

    def test_acts_syntax(self):
        tree = datasets.Expression('a => b => !c', {'a', 'b', 'c'}).tree
        self.assertEqual(tree, ('=>', ('param', 'a'), ('=>', ('param', 'b'), ('!', ('param', 'c')))))
        f = datasets.Expression('x * 2 - 1 >= -3 && x % 2 == 1', {'x'}).compile()
        self.assertEqual([x for x in range(-3, 4) if f({'x': x})], [-1, 1, 3])
        with self.assertRaises(ValueError): datasets.Expression('(a = 1', {'a'})


@unittest.skipUnless(shutil.which(JULIA), 'Julia executable unavailable; set JULIA')
class ImportedModelJobTests(unittest.TestCase):
    def run_model(self, record, usage, n, v):
        with tempfile.TemporaryDirectory(prefix='utd-model-test-') as directory:
            out = pathlib.Path(directory)
            path = out / 'model.json'
            path.write_text(json.dumps(record))
            args = types.SimpleNamespace(julia=JULIA, poll=0.1, rss_mib=2048, stage_seconds=120, cold_seconds=180,
                                         diagnostic_seconds=120, startup_seconds=180, job_seconds=480)
            job = dict(id=f'model-{usage}', ladder='model', n=n, v=v, arity=record['arity'], family='none',
                       usage=usage, solver='ipog', strength=2, runs=1, model=str(path), adapters=[])
            result = runner.run_job(job, out, args)
            self.assertEqual(result['status'], 'ok', json.dumps(result, indent=2) + (out / job['id'] / 'stderr.txt').read_text())
            return result

    def test_imported_rules_cover_and_count(self):
        casa = datasets.import_casa(CASA_MODEL, CASA_CONSTRAINTS, 'tiny')
        result = self.run_model(casa, 'reuse', 3, 3)
        self.assertEqual(result['validation']['exhaustive'], 'passed_exhaustive')
        self.assertEqual(result['bounds']['elementary'], 6)
        rows = self.run_model(casa, 'factorial', 3, 3)['measurements'][-1]['result']['cases']
        self.assertEqual(rows, 12 - 2 - 1)   # (1, 1, ·) twice, (1, 3, 1) once
        expected = acts_valid_rows(ACTS_MODEL)
        limit = datasets.TUPLE_LIMIT
        for wide in (False, True):
            with self.subTest(expressions=wide):
                try:
                    datasets.TUPLE_LIMIT = 0 if wide else limit
                    acts = datasets.import_acts(ACTS_MODEL, 'tiny')
                finally:
                    datasets.TUPLE_LIMIT = limit
                result = self.run_model(acts, 'reuse', 4, 3)
                self.assertEqual(result['validation']['exhaustive'], 'passed_exhaustive')
                rows = self.run_model(acts, 'factorial', 4, 3)['measurements'][-1]['result']['cases']
                self.assertEqual(rows, expected)


if __name__ == '__main__': unittest.main()
