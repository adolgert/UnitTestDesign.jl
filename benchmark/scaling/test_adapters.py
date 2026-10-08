"""Regression checks for trial solver certification using small real Julia jobs.

Run after the scaling sweep has stopped: each test launches serial Julia workers.
The repository Julia environment must already be instantiated. Set JULIA to use
a particular executable. These tests assert correctness, never benchmark timing.
"""

import importlib.util
import json
import os
import pathlib
import shutil
import tempfile
import types
import unittest


HERE = pathlib.Path(__file__).resolve().parent
MODULE_SPEC = importlib.util.spec_from_file_location("scaling_adapter_runner", HERE / "run.py")
runner = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(runner)
JULIA = os.environ.get("JULIA", "julia")


FUNCTION_WRAPPER = '''
register_solver("trial_function", (space, kw) -> covering(space; engine=IPOG(), kw...))
'''

DELEGATING_ENGINE = '''
struct TrialIPOG end
UnitTestDesign.generate(::TrialIPOG, request::UnitTestDesign.Request) =
    UnitTestDesign.generate(IPOG(), request)
register_solver("trial_engine", TrialIPOG())
'''

EMPTY_ENGINE = '''
struct EmptyTrialEngine end
function UnitTestDesign.generate(::EmptyTrialEngine, request::UnitTestDesign.Request)
    return UnitTestDesign.Design(zeros(Int, length(request.arity), 0),
        :covering, :EmptyTrial, nothing, 0, 0, UnitTestDesign.Excluded[], 0, (;))
end
register_solver("empty_engine", EmptyTrialEngine())
'''

ORDINARY_ONLY_FUNCTION = '''
function ordinary_only_trial(space, kw)
    ordinary = TestSpace((space.names[i] =>
        [v for v in space.values[i] if !(v isa Invalid)]
        for i in eachindex(space.names))...; constraints=space.constraints)
    return covering(ordinary; engine=IPOG(), kw...)
end
register_solver("ordinary_only", ordinary_only_trial)
'''


@unittest.skipUnless(shutil.which(JULIA), "Julia executable unavailable; set JULIA")
class AdapterCertificationTests(unittest.TestCase):
    def run_adapter(self, extension, solver, family="none"):
        with tempfile.TemporaryDirectory(prefix="utd-adapter-test-") as directory:
            out = pathlib.Path(directory)
            adapter = out / "extension.jl"
            adapter.write_text(extension)
            args = types.SimpleNamespace(
                julia=JULIA,
                poll=0.1,
                rss_mib=2048,
                stage_seconds=120,
                cold_seconds=180,
                diagnostic_seconds=120,
                startup_seconds=180,
                job_seconds=480,
            )
            job = dict(
                id=f"adapter-{solver}-{family}",
                ladder=f"adapter-{solver}-{family}",
                n=4,
                v=2,
                strength=2,
                family=family,
                usage="reuse",
                solver=solver,
                runs=1,
                adapters=[str(adapter)],
            )
            result = runner.run_job(job, out, args)
            result["test_stderr"] = (out / job["id"] / "stderr.txt").read_text()
            return result

    def assert_success(self, result, family):
        detail = json.dumps(result, indent=2)
        self.assertEqual(result["status"], "ok", detail)
        self.assertEqual(result["exit_code"], 0, detail)
        self.assertEqual(result["errors"], [], detail)
        self.assertEqual(result["completed_warm_runs"], 1, detail)
        warm = [event for event in result["measurements"] if event["stage"] == "warm"]
        self.assertEqual(len(warm), 1, detail)
        measurement = warm[0]
        self.assertGreater(measurement["result"]["cases"], 0, detail)
        self.assertEqual(
            measurement["result"]["covered"], measurement["result"]["required"], detail
        )
        self.assertIn("certification", measurement["certification"], detail)
        self.assertIn("operation timing", measurement["certification"], detail)
        self.assertIsInstance(result["validation"], dict, detail)
        if family == "invalid":
            self.assertGreater(measurement["result"]["negative_required"], 0, detail)
            self.assertEqual(
                measurement["result"]["negative_covered"],
                measurement["result"]["negative_required"],
                detail,
            )
            self.assertEqual(
                result["validation"]["public_coverage"], "passed_public_coverage", detail
            )
        else:
            self.assertEqual(result["validation"]["exhaustive"], "passed_exhaustive", detail)

    def assert_certification_failure(self, result, negative=False):
        detail = json.dumps(result, indent=2)
        self.assertEqual(result["status"], "error", detail)
        self.assertNotEqual(result["exit_code"], 0, detail)
        self.assertIsNone(result["validation"], detail)
        # Reject inside timed adapter certification, before any completed
        # operation measurement or the separate post-run oracle.
        self.assertEqual(result["completed_warm_runs"], 0, detail)
        self.assertFalse(
            any(event["stage"] in ("cold", "warm") for event in result["measurements"]),
            detail,
        )
        self.assertTrue(result["errors"], detail)
        message = "\n".join(error["message"] for error in result["errors"])
        self.assertIn("required target", message, detail)
        self.assertIn("not covered", message, detail)
        if negative:
            self.assertIn("Invalid", message, detail)

    def test_function_wrapper_ordinary_and_invalid(self):
        for family in ("none", "invalid"):
            with self.subTest(family=family):
                result = self.run_adapter(FUNCTION_WRAPPER, "trial_function", family)
                self.assert_success(result, family)

    def test_custom_engine_delegates_ipog(self):
        for family in ("none", "invalid"):
            with self.subTest(family=family):
                result = self.run_adapter(DELEGATING_ENGINE, "trial_engine", family)
                self.assert_success(result, family)

    def test_empty_design_cannot_claim_coverage(self):
        result = self.run_adapter(EMPTY_ENGINE, "empty_engine")
        self.assert_certification_failure(result)

    def test_ordinary_rows_cannot_satisfy_negative_targets(self):
        result = self.run_adapter(ORDINARY_ONLY_FUNCTION, "ordinary_only", "invalid")
        self.assert_certification_failure(result, negative=True)


if __name__ == "__main__":
    unittest.main()
