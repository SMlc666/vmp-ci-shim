#!/usr/bin/env python3
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
GATE = ROOT / ".github" / "scripts" / "csharp-gate.sh"


class CSharpGateTest(unittest.TestCase):
    def test_workflow_has_fail_closed_csharp_job(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("  csharp_glibc_unit:", text)
        self.assertIn("actions/setup-dotnet@v4", text)
        self.assertIn("dotnet-version: '8.0.424'", text)
        self.assertIn(".github/scripts/csharp-gate.sh", text)
        self.assertIn("CSHARP_GLIBC_UNIT", text)
        self.assertIn("csharp_glibc_unit.result == 'failure'", text)

    def test_gate_has_pinned_provenance_and_nonzero_test_guard(self) -> None:
        text = GATE.read_text(encoding="utf-8")
        self.assertIn('EXPECTED_DOTNET_SDK="8.0.424"', text)
        self.assertIn('EXPECTED_ASMSTONE_COMMIT="477e07eb58f26c6c05960a3f5e55a2f3798df8cb"', text)
        self.assertIn('EXPECTED_LLVM_COMMIT="87b1a2f7246bc0a4ed5335c45635bddb75847890"', text)
        self.assertIn("unable to prove that dotnet test executed at least one test", text)
        self.assertIn("zero tests were executed", text)
        self.assertIn("gitlink", text)
        self.assertIn("tablegenJsonSha256", text)
        subprocess.run(["bash", "-n", str(GATE)], check=True)

    def test_gate_rejects_short_sha_before_using_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                ["bash", str(GATE), directory, "deadbeef"],
                check=False,
                capture_output=True,
                text=True,
            )
        self.assertEqual(2, result.returncode)
        self.assertIn("full 40-character SHA", result.stderr)

    def test_gate_rejects_missing_source_directory(self) -> None:
        result = subprocess.run(
            ["bash", str(GATE), "/definitely/missing/csharp-source", "a" * 40],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(2, result.returncode)
        self.assertIn("source directory does not exist", result.stderr)


if __name__ == "__main__":
    unittest.main()
