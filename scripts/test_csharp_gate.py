#!/usr/bin/env python3
import json
import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
GATE = ROOT / ".github" / "scripts" / "csharp-gate.sh"
WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
CATALOG_SHA = "a" * 64
TABLEGEN_SHA = "b" * 64


class GateFixture:
    def __init__(self, with_submodule: bool = True) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="csharp-gate-test-")
        self.root = pathlib.Path(self.temp.name)
        self.submodule = self.root / "asmstone"
        self.source = self.root / "source"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self._init_repo(self.submodule)
        (self.submodule / "spec").mkdir()
        (self.submodule / "spec" / "source-lock.json").write_text(
            json.dumps({"sources": {"llvm": {
                "tablegenJsonSha256": TABLEGEN_SHA,
                "generatedCatalogSha256": CATALOG_SHA,
            }}}),
            encoding="utf-8",
        )
        self._git(self.submodule, "add", ".")
        self._git(self.submodule, "commit", "-m", "catalog")

        self._init_repo(self.source)
        (self.source / "cs").mkdir(parents=True)
        (self.source / "cs" / "Vmp.sln").write_text("fixture\n", encoding="utf-8")
        if with_submodule:
            self._git(
                self.source,
                "-c",
                "protocol.file.allow=always",
                "submodule",
                "add",
                "-q",
                str(self.submodule),
                "third_party/AsmStone",
            )
        self._git(self.source, "add", ".")
        self._git(self.source, "commit", "-m", "source")
        self._git(self.source, "checkout", "--detach", "HEAD")
        self.sha = self._git(self.source, "rev-parse", "HEAD").stdout.strip()
        self.log = self.root / "gate.log"
        self.json = self.root / "gate.json"
        self.calls = self.root / "dotnet.calls"
        self._write_dotnet()

    def _init_repo(self, path: pathlib.Path) -> None:
        path.mkdir(parents=True, exist_ok=True)
        self._git(path, "init", "-q")
        self._git(path, "config", "user.email", "fixture@example.invalid")
        self._git(path, "config", "user.name", "fixture")

    def _git(self, cwd: pathlib.Path, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", "-C", str(cwd), *args],
            check=True,
            text=True,
            capture_output=True,
        )

    def _write_dotnet(self) -> None:
        path = self.bin / "dotnet"
        path.write_text(
            """#!/bin/sh
set -u
printf '%s\\n' "$*" >> "${DOTNET_CALLS:?}"
case "$1" in
  --version) printf '%s\\n' "${FAKE_DOTNET_VERSION:-8.0.424}"; exit 0 ;;
  restore) printf '%s\\n' 'Restore succeeded.'; exit "${FAKE_RESTORE_RC:-0}" ;;
  build) printf '%s\\n' 'Build succeeded.'; exit "${FAKE_BUILD_RC:-0}" ;;
  test)
    printf '%s\\n' "${FAKE_TEST_OUTPUT:-Passed! - Failed: 0, Passed: 1, Skipped: 0, Total: 1}"
    exit "${FAKE_TEST_RC:-0}" ;;
esac
printf '%s\\n' 'unknown command' >&2
exit 64
""",
            encoding="utf-8",
        )
        path.chmod(0o755)

    def run(self, **extra_env: str) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{self.bin}:{env.get('PATH', '')}",
                "DOTNET_CALLS": str(self.calls),
                "CSPROJ_GATE_LOG": str(self.log),
                "CSPROJ_GATE_JSON": str(self.json),
                "CSPROJ_DOTNET_SDK_FAMILY": "8.0",
                "CSPROJ_DOTNET_SDK_VERSION": "8.0.424",
                **extra_env,
            }
        )
        return subprocess.run(
            [str(GATE), self.sha, str(self.source)],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
        )

    def result(self) -> dict:
        return json.loads(self.json.read_text(encoding="utf-8"))

    def close(self) -> None:
        self.temp.cleanup()


class CSharpGateTest(unittest.TestCase):
    def test_invalid_sha_fails_closed(self) -> None:
        fixture = GateFixture()
        try:
            result = subprocess.run(
                [str(GATE), "short-sha", str(fixture.source)],
                cwd=ROOT,
                env={
                    **os.environ,
                    "CSPROJ_GATE_LOG": str(fixture.log),
                    "CSPROJ_GATE_JSON": str(fixture.json),
                },
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 2)
            receipt = fixture.result()
            self.assertEqual(receipt["status"], "failure")
            self.assertEqual(receipt["failure_step"], "source_sha")
            self.assertTrue(fixture.log.stat().st_size > 0)
        finally:
            fixture.close()

    def test_missing_sdk_fails_before_dotnet_commands(self) -> None:
        fixture = GateFixture()
        try:
            result = fixture.run(CSPROJ_DOTNET_BIN=str(fixture.root / "missing-dotnet"))
            self.assertNotEqual(result.returncode, 0)
            receipt = fixture.result()
            self.assertEqual(receipt["failure_step"], "sdk")
            self.assertEqual(receipt["dotnet_sdk"], "")
            self.assertFalse(fixture.calls.exists())
        finally:
            fixture.close()

    def test_incompatible_sdk_family_fails_closed(self) -> None:
        fixture = GateFixture()
        try:
            result = fixture.run(FAKE_DOTNET_VERSION="9.0.100")
            self.assertNotEqual(result.returncode, 0)
            receipt = fixture.result()
            self.assertEqual(receipt["failure_step"], "sdk")
            self.assertEqual(receipt["dotnet_sdk"], "9.0.100")
            self.assertFalse(fixture.calls.read_text(encoding="utf-8").splitlines()[1:])
        finally:
            fixture.close()

    def test_missing_submodule_fails_closed(self) -> None:
        fixture = GateFixture(with_submodule=False)
        try:
            result = fixture.run()
            self.assertNotEqual(result.returncode, 0)
            receipt = fixture.result()
            self.assertEqual(receipt["failure_step"], "submodule")
            self.assertEqual(receipt["asmstone_commit"], "")
            self.assertFalse(fixture.calls.exists())
        finally:
            fixture.close()

    def test_empty_test_selection_is_a_failure(self) -> None:
        fixture = GateFixture()
        try:
            result = fixture.run(FAKE_TEST_OUTPUT="Passed! - Failed: 0, Passed: 0, Skipped: 0, Total: 0")
            self.assertEqual(result.returncode, 1)
            receipt = fixture.result()
            self.assertEqual(receipt["failure_step"], "test_count")
            self.assertEqual(receipt["test_count"], 0)
            self.assertEqual(receipt["test"]["status"], "failed")
        finally:
            fixture.close()

    def test_first_failed_command_status_is_preserved(self) -> None:
        fixture = GateFixture()
        try:
            result = fixture.run(FAKE_BUILD_RC="17")
            self.assertEqual(result.returncode, 17)
            receipt = fixture.result()
            self.assertEqual(receipt["failure_status"], 17)
            self.assertEqual(receipt["failure_step"], "build")
            self.assertEqual(receipt["build"]["exit_status"], 17)
            self.assertEqual(receipt["test"]["status"], "not-run")
        finally:
            fixture.close()

    def test_missing_log_fails_closed(self) -> None:
        fixture = GateFixture()
        try:
            blocked_parent = fixture.root / "not-a-directory"
            blocked_parent.write_text("fixture", encoding="utf-8")
            result = fixture.run(CSPROJ_GATE_LOG=str(blocked_parent / "gate.log"))
            self.assertNotEqual(result.returncode, 0)
            receipt = fixture.result()
            self.assertEqual(receipt["failure_step"], "log")
            self.assertIn(receipt["log_status"], {"missing", "write-error"})
            self.assertFalse((blocked_parent / "gate.log").exists())
        finally:
            fixture.close()

    def test_successful_provenance_contains_source_and_toolchain_identity(self) -> None:
        fixture = GateFixture()
        try:
            result = fixture.run(FAKE_TEST_OUTPUT="Passed! - Failed: 0, Passed: 3, Skipped: 0, Total: 3")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            receipt = fixture.result()
            self.assertEqual(receipt["status"], "pass")
            self.assertEqual(receipt["source_commit"], fixture.sha)
            self.assertEqual(receipt["checked_out_commit"], fixture.sha)
            self.assertTrue(receipt["detached"])
            self.assertEqual(receipt["asmstone_gitlink"], receipt["asmstone_commit"])
            self.assertEqual(receipt["asmstone_catalog_sha256"], TABLEGEN_SHA)
            self.assertEqual(receipt["asmstone_generated_catalog_sha256"], CATALOG_SHA)
            self.assertEqual(receipt["dotnet_sdk"], "8.0.424")
            self.assertEqual(receipt["test_count"], 3)
            self.assertEqual(receipt["log_status"], "present")
            self.assertGreater(receipt["log"]["bytes"], 0)
            self.assertEqual(len(receipt["test"]["focused_gates"]), 5)
            self.assertTrue(all(gate["status"] == "passed" for gate in receipt["test"]["focused_gates"]))
        finally:
            fixture.close()

    def test_workflow_declares_csharp_unit_job_and_nuget_cache_without_cutover_jobs(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("  csharp_glibc_unit:", workflow)
        self.assertIn("if: ${{ inputs.layer == 'all' || inputs.layer == 'unit' }}", workflow)
        self.assertIn("runs-on: ubuntu-24.04-arm", workflow)
        self.assertIn("uses: actions/setup-dotnet@v4", workflow)
        self.assertIn("dotnet-version: 8.0.424", workflow)
        self.assertIn('CSPROJ_DOTNET_SDK_FAMILY: "8.0"', workflow)
        self.assertIn("uses: actions/cache@v4", workflow)
        self.assertIn("~/.nuget/packages", workflow)
        self.assertIn("src/cs/Vmp.sln", workflow)
        self.assertIn("src/cs/**/*.csproj", workflow)
        self.assertIn("src/third_party/AsmStone/spec/source-lock.json", workflow)
        self.assertIn("csharp-gate.sh", workflow)
        self.assertNotIn("csharp_glibc_artifact:", workflow)
        self.assertNotIn("csharp_bionic_e2e:", workflow)
        for rust_job in ("public_demo", "glibc_unit", "bionic_unit", "glibc_e2e", "bionic_e2e"):
            self.assertIn(f"  {rust_job}:", workflow)


if __name__ == "__main__":
    unittest.main()
