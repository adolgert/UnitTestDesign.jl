"""Checks of the generated families and the best-known table (plan §7.1, §7.2). No benchmark runs.

The Julia check runs benchmark/best_known/check.jl when Julia is available.
"""
import csv, hashlib, importlib.util, itertools, json, math, os, pathlib, re, shutil, subprocess, unittest

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
spec = importlib.util.spec_from_file_location('scaling_families_runner', HERE / 'run.py')
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)
families = runner.families
JULIA = os.environ.get('JULIA', 'julia')
# json.dumps(specs(3), sort_keys=True) at 2798ecf, the grid of STUDY.md: the default grid must not move.
DEFAULT_GRID_SHA256 = 'bad761cabba712f1e39ccf877a988f47100efecbc034c190890c8ad09c57ddcd'


class FamilyTests(unittest.TestCase):
    def test_default_grid_is_the_studys(self):
        grid = runner.specs(3)
        self.assertEqual(len(grid), 245)
        self.assertEqual(hashlib.sha256(json.dumps(grid, sort_keys=True).encode()).hexdigest(), DEFAULT_GRID_SHA256)

    def test_targets_is_the_count_of_combinations(self):
        for arity in ([2, 3, 4], [5, 5, 2, 3], [2] * 6):
            for t in range(1, len(arity) + 1):
                brute = sum(math.prod(arity[p] for p in s) for s in itertools.combinations(range(len(arity)), t))
                self.assertEqual(families.targets(arity, t), brute)

    def test_specs_are_well_formed(self):
        names = set(re.findall(r'^\s*"([\w-]+)" => \(\) ->', (HERE / 'spaces.jl').read_text(), re.M))
        jobs = families.select([n for n in families.FAMILIES if n not in ('casa', 'ct-comp', 'cart')], expensive=True)
        ids = [s['id'] for s in jobs]
        self.assertEqual(len(ids), len(set(ids)), 'job ids must be unique')
        for s in jobs:
            with self.subTest(id=s['id']):
                for field in ('id', 'ladder', 'n', 'v', 'family', 'usage', 'solver', 'strength', 'runs', 'grid'):
                    self.assertIn(field, s)
                if 'arity' in s:
                    self.assertEqual(len(s['arity']), s['n']); self.assertEqual(max(s['arity']), s['v'])
                if 'space' in s: self.assertIn(s['space'], names)
                if s.get('expensive'): self.assertEqual(s['runs'], 1)
                self.assertLessEqual(s['strength'], s['n'])
                for rule in s.get('forbid', []):
                    for t in rule['tuples']:
                        self.assertEqual(len(t), len(rule['scope']))
                        for p, x in zip(rule['scope'], t): self.assertTrue(1 <= x <= s['arity'][p - 1])

    def test_families_hold_the_probe_sets(self):
        jobs = families.select(['mainstream', 'mainstream-r1', 'exact'])
        count = {}
        for s in jobs: count[s.get('set')] = count.get(s.get('set'), 0) + 1
        # Probe 16's sets; r3 is Phase 1's gate (92 of 100 at the bound, plan §5.3), r2 the exact family's.
        self.assertEqual((count['r1'], count['r2'], count['r3'], count['r4']), (150, 150, 100, 60))
        self.assertEqual((count['r3-rules'], count['r4-rules']), (100, 60))
        self.assertEqual(sum(1 for s in jobs if s.get('space') == 'bench12'), 3)
        self.assertTrue(all(1 <= len(s['forbid']) <= 4 for s in jobs if s.get('set', '').endswith('-rules')))

    def test_default_selection_leaves_out_expensive_points(self):
        everything = families.select(['strength'], expensive=True)
        default = families.select(['strength'])
        self.assertTrue(all(not s.get('expensive') for s in default))
        self.assertEqual(len(everything) - len(default), sum(1 for s in everything if s.get('expensive')))
        # D3's points at strengths 5 and 6 on 20 parameters stay in the grid.
        ids = {s['id'] for s in everything}
        for point in ('strength-v3-k20-ipog-t6', 'strength-v4-k20-ipog-t5', 'strength-v2-k20-ipog-t6'):
            self.assertIn(point, ids)

    def test_adapted_applies_each_change(self):
        jobs = families.select(['adapted'])
        self.assertEqual({s['adapt'] for s in jobs}, set(families.ADAPTATIONS))
        self.assertTrue({s['base_grid'] for s in jobs} >= {'mainstream', 'smallest', 'uniform-pp', 'uniform-npp', 'strength', 'exact'})

    def test_best_known_table_holds_every_uniform_shape(self):
        table = ROOT / 'benchmark' / 'best_known' / 'uniform_shapes.csv'
        with table.open(newline='') as f: rows = {(int(r['t']), int(r['v']), int(r['k'])): r for r in csv.DictReader(f)}
        shapes = families.uniform_shapes(runner.specs(3) + families.select(['all'], expensive=True))
        missing = [x for x in shapes if x not in rows]
        self.assertEqual(missing, [], 'rerun benchmark/best_known/write_table.jl')
        for (t, v, k), r in rows.items():
            self.assertEqual(int(r['lower_bound']), v ** t)
            if r['best_known']: self.assertGreaterEqual(int(r['best_known']), v ** t)

    @unittest.skipUnless(shutil.which(JULIA), 'Julia executable unavailable; set JULIA')
    def test_best_known_spot_checks(self):
        result = subprocess.run([JULIA, '--project=' + str(ROOT), '--startup-file=no',
                                 str(ROOT / 'benchmark' / 'best_known' / 'check.jl')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__': unittest.main()
