"""Safety/recording tests using fake workers; no Julia solver benchmark is run."""
import importlib.util, json, pathlib, tempfile, types, unittest
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('scaling',pathlib.Path(__file__).with_name('run.py'))
runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)

class WatchdogTests(unittest.TestCase):
    def run_fake(self,code,**limits):
        with tempfile.TemporaryDirectory() as d:
            out=pathlib.Path(d)
            fake=out/'fake-julia'
            fake.write_text('#!/usr/bin/env python3\nimport json,time,sys\n'+code)
            fake.chmod(0o755)
            args=types.SimpleNamespace(julia=str(fake),poll=.05,rss_mib=256,stage_seconds=.3,
                cold_seconds=.3,diagnostic_seconds=.3,startup_seconds=2,job_seconds=3)
            for k,v in limits.items(): setattr(args,k,v)
            s=dict(id='fake',n=2,v=2,strength=2,usage='reuse',family='none',solver='ipog',runs=1)
            return runner.run_job(s,out,args)
    def test_success(self):
        r=self.run_fake('print(json.dumps({"event":"measurement","stage":"warm","seconds":.125,"allocated_bytes":32,"result":{}}),flush=True)\nprint(json.dumps({"event":"done","validation":"fake"}),flush=True)\n')
        self.assertEqual(r['status'],'ok');self.assertEqual(r['warm_median_seconds'],.125)
    def test_timeout_and_partial_json(self):
        r=self.run_fake('print(json.dumps({"event":"stage","name":"warm"}),flush=True)\nsys.stdout.write(\'{"event":\');sys.stdout.flush()\ntime.sleep(5)\n')
        self.assertEqual(r['status'],'stage_timeout');self.assertLess(r['wall_seconds'],3)
        self.assertIsNone(r.get('warm_median_seconds'))
    def test_rss_stop(self):
        r=self.run_fake('print(json.dumps({"event":"stage","name":"warm"}),flush=True)\nx=bytearray(120*2**20)\ntime.sleep(5)\n',rss_mib=80,stage_seconds=2)
        self.assertEqual(r['status'],'rss_limit');self.assertGreater(r['sampled_peak_rss_bytes'],80*2**20)
    def test_unknown_is_limited(self):
        r=self.run_fake('print(json.dumps({"event":"measurement","stage":"warm","seconds":.1,"allocated_bytes":0,"result":{"status":"unknown"}}),flush=True)\nprint(json.dumps({"event":"done","validation":"not_applicable"}),flush=True)\n')
        self.assertEqual(r['status'],'resource_limit')
    def test_monitor_failure_stops_worker(self):
        with patch.object(runner.subprocess,'run',side_effect=PermissionError('blocked ps')):
            r=self.run_fake('print(json.dumps({"event":"stage","name":"warm"}),flush=True)\ntime.sleep(5)\n')
        self.assertEqual(r['status'],'monitor_error')
        self.assertIn('blocked ps',r['monitor_error'])
        self.assertLess(r['wall_seconds'],3)
    def test_resume_fingerprint_changes_with_spec_or_limit(self):
        args=types.SimpleNamespace(julia='julia',rss_mib=256,stage_seconds=1,cold_seconds=2,
            diagnostic_seconds=1,startup_seconds=1,job_seconds=2,poll=.1)
        original=runner.fingerprint({'n':4},args,{'worker':'abc'})
        self.assertNotEqual(original,runner.fingerprint({'n':8},args,{'worker':'abc'}))
        args.rss_mib=512
        self.assertNotEqual(original,runner.fingerprint({'n':4},args,{'worker':'abc'}))
        self.assertNotEqual(original,runner.fingerprint({'n':4},args,{'worker':'def'}))
        args.rss_mib=256
        args.julia_arg=['--heap-size-hint=1G']
        self.assertNotEqual(original,runner.fingerprint({'n':4},args,{'worker':'abc'}))
    def test_payload_fast_path_and_dense_path(self):
        s=dict(n=1024,v=2,strength=2,family='mixed',usage='reuse',solver='ipog')
        self.assertEqual(runner.payload_floor(s),0)
        s.update(family='none',solver='gnd')
        self.assertGreater(runner.payload_floor(s),2**30)
        # The registry's names are the same engines.
        self.assertEqual(runner.payload_floor({**s,'solver':'GND()'}),runner.payload_floor(s))
        self.assertEqual(runner.payload_floor({**s,'solver':'IPOG()','usage':'seed'}),
                         runner.payload_floor({**s,'solver':'ipog','usage':'seed'}))
        self.assertEqual(runner.payload_floor({**s,'solver':'Auto()'}),0)

if __name__=='__main__': unittest.main()
