#!/usr/bin/env python3
import json
import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
GATE = ROOT / ".github" / "scripts" / "csharp-performance-gate.sh"


class CSharpPerformanceGateTest(unittest.TestCase):
    def test_script_is_valid_bash(self) -> None:
        subprocess.run(["bash", "-n", str(GATE)], check=True)

    def test_workflow_wires_informational_performance_job(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("  csharp_performance:", text)
        self.assertIn("if: ${{ inputs.layer == 'all' || inputs.layer == 'unit' }}", text)
        self.assertIn("checkout-private.sh", text)
        self.assertIn("git submodule update --init --recursive third_party/AsmStone", text)
        self.assertIn("dotnet-version: '8.0.424'", text)
        self.assertIn(".github/scripts/csharp-performance-gate.sh", text)
        self.assertIn("CSHARP_PERFORMANCE_REPORT", text)
        self.assertIn("continue-on-error: true", text)
        self.assertIn("if: always()", text)
        self.assertIn("/tmp/csharp-performance.json", text)
        self.assertIn("/tmp/csharp-performance.log", text)

    def test_blocked_report_returns_three_and_keeps_reason(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            source, source_sha = self._make_source(root)
            reason = "native runner is not available on this host"
            report_fixture = root / "blocked.json"
            report_fixture.write_text(
                json.dumps(self._report(source_sha, "blocked", reason)), encoding="utf-8"
            )
            result, report, log = self._run_gate(root, source, source_sha, report_fixture)

            self.assertEqual(3, result.returncode, result.stderr)
            self.assertEqual(reason, json.loads(report.read_text(encoding="utf-8"))["results"][0]["preflight"]["reason"])
            self.assertIn("BLOCKED_CASE: blocked.case", log.read_text(encoding="utf-8"))
            self.assertIn(reason, log.read_text(encoding="utf-8"))

    def test_malformed_and_zero_case_reports_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            source, source_sha = self._make_source(root)
            for name, payload in (
                ("malformed", "not json"),
                ("zero", json.dumps(self._report(source_sha, "error", zero_cases=True))),
            ):
                with self.subTest(report=name):
                    fixture = root / f"{name}-fixture"
                    fixture.write_text(payload, encoding="utf-8")
                    result, _report, log = self._run_gate(root, source, source_sha, fixture)
                    self.assertEqual(1, result.returncode, result.stderr)
                    self.assertIn("malformed/error benchmark report", log.read_text(encoding="utf-8"))

    @staticmethod
    def _make_source(root: pathlib.Path) -> tuple[pathlib.Path, str]:
        source = root / "source"
        project = source / "cs" / "benchmarks" / "Vmp.Lifter.PerformanceBench"
        project.mkdir(parents=True)
        (project / "Vmp.Lifter.PerformanceBench.csproj").write_text(
            "<Project Sdk=\"Microsoft.NET.Sdk\" />\n", encoding="utf-8"
        )
        subprocess.run(["git", "init", "--quiet", str(source)], check=True)
        subprocess.run(["git", "-C", str(source), "config", "user.email", "ci@example.invalid"], check=True)
        subprocess.run(["git", "-C", str(source), "config", "user.name", "CI Test"], check=True)
        subprocess.run(["git", "-C", str(source), "add", "."], check=True)
        subprocess.run(["git", "-C", str(source), "commit", "--quiet", "-m", "fixture"], check=True)
        source_sha = subprocess.check_output(
            ["git", "-C", str(source), "rev-parse", "HEAD"], text=True
        ).strip()
        return source, source_sha

    def _run_gate(
        self,
        root: pathlib.Path,
        source: pathlib.Path,
        source_sha: str,
        fixture: pathlib.Path,
    ) -> tuple[subprocess.CompletedProcess[str], pathlib.Path, pathlib.Path]:
        fake_bin = root / "bin"
        fake_bin.mkdir(exist_ok=True)
        fake_dotnet = fake_bin / "dotnet"
        fake_dotnet.write_text(
            "#!/usr/bin/env python3\n"
            "import os, shutil, sys\n"
            "if sys.argv[1:] == ['--version']:\n"
            "    print('8.0.424')\n"
            "    raise SystemExit(0)\n"
            "output = sys.argv[sys.argv.index('--output') + 1]\n"
            "shutil.copyfile(os.environ['REPORT_FIXTURE'], output)\n"
            "raise SystemExit(int(os.environ.get('FAKE_DOTNET_RC', '0')))\n",
            encoding="utf-8",
        )
        fake_dotnet.chmod(0o755)
        log = root / f"{fixture.stem}.log"
        report = root / f"{fixture.stem}.report.json"
        environment = os.environ.copy()
        environment["PATH"] = f"{fake_bin}{os.pathsep}{environment['PATH']}"
        environment["REPORT_FIXTURE"] = str(fixture)
        result = subprocess.run(
            ["bash", str(GATE), str(source), source_sha, str(log), str(report)],
            cwd=ROOT,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
        )
        return result, report, log

    @staticmethod
    def _report(
        source_sha: str,
        status: str,
        reason: str = "blocked by test fixture",
        zero_cases: bool = False,
    ) -> dict:
        if zero_cases:
            selected = []
            results = []
        elif status == "blocked":
            selected = ["blocked.case"]
            results = [
                {
                    "case_id": "blocked.case",
                    "status": "blocked",
                    "preflight": {
                        "status": "blocked",
                        "reason": reason,
                        "capability": "native-runner",
                        "diagnostic": "test diagnostic",
                    },
                    "first_error": reason,
                }
            ]
        else:
            selected = ["error.case"]
            results = [
                {
                    "case_id": "error.case",
                    "status": "error",
                    "preflight": {"status": "error"},
                    "first_error": "fixture error",
                }
            ]
        return {
            "schema_version": 1,
            "run_kind": "csharp-performance",
            "mode": "quick",
            "ci_mode": True,
            "status": status,
            "provenance": {
                "source_commit": source_sha,
                "target_framework": "net8.0",
                "runtime_version": ".NET test",
                "process_architecture": "aarch64",
                "runner_version": "test",
            },
            "selected_case_ids": selected,
            "selected_case_count": len(selected),
            "results": results,
            "blocked_case_count": sum(row["status"] == "blocked" for row in results),
            "error_case_count": sum(row["status"] == "error" for row in results),
            "regression_case_count": 0,
            "exit_code": 3 if status == "blocked" else 1,
        }


if __name__ == "__main__":
    unittest.main()
