#!/usr/bin/env python3
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
SCRIPTS = ROOT / ".github" / "scripts"
REALIB_SUITES = (
    "tinylib",
    "sqlite",
    "libcrypto",
    "libz",
    "yamlcpp",
    "protobuflite",
    "cpp_business",
    "matrix",
)


class LayeredWorkflowTest(unittest.TestCase):
    def setUp(self) -> None:
        self.workflow = WORKFLOW.read_text(encoding="utf-8")
        self.checkout = (SCRIPTS / "checkout-private.sh").read_text(encoding="utf-8")
        self.runner = (SCRIPTS / "run-e2e-targets.sh").read_text(encoding="utf-8")
        self.gate = (SCRIPTS / "realib-gate.sh").read_text(encoding="utf-8")
        self.deps = (SCRIPTS / "prepare-realib-deps.sh").read_text(encoding="utf-8")

    def test_layer_jobs_are_explicit(self) -> None:
        for job in ("glibc_unit", "bionic_unit", "glibc_e2e", "bionic_e2e"):
            self.assertIn(f"  {job}:", self.workflow)
        self.assertIn("layer:", self.workflow)
        self.assertIn("- unit", self.workflow)
        self.assertIn("- e2e", self.workflow)
        self.assertIn("cargo test --workspace --lib --bins --quiet", self.workflow)

    def test_private_checkout_requires_and_verifies_full_sha(self) -> None:
        self.assertIn("checkout-private.sh", self.workflow)
        self.assertIn("[0-9a-fA-F]{40}", self.checkout)
        self.assertIn('git -C "$dest" fetch --no-tags --depth=1 origin', self.checkout)
        self.assertIn('git -C "$dest" checkout --detach', self.checkout)
        self.assertIn("SOURCE_CHECKOUT_OK", self.checkout)

    def test_realib_targets_are_built_once_and_run_directly(self) -> None:
        self.assertIn("run-e2e-targets.sh", self.workflow)
        self.assertNotIn("Precompile realib e2e binaries", self.workflow)
        self.assertNotIn("run_realib_suite", self.workflow)
        self.assertIn("--no-run --quiet", self.runner)
        self.assertIn('"$binary" --nocapture', self.runner)
        for suite in REALIB_SUITES:
            with self.subTest(suite=suite):
                self.assertIn(f"realib_{suite}_e2e", self.workflow)
                self.assertIn("realib_${suite}", self.gate)

    def test_realib_gate_checks_every_suite_and_eh(self) -> None:
        for suite in REALIB_SUITES:
            with self.subTest(suite=suite):
                self.assertIn("realib_${suite}", self.gate)
        self.assertIn("e2e_eh_fixture", self.gate)
        self.assertIn("REALIB CARGO TEST FAIL", self.gate)
        self.assertIn("surviving_pass_ratio", self.gate)

    def test_dependency_setup_is_shared(self) -> None:
        self.assertEqual(self.workflow.count("prepare-realib-deps.sh"), 2)
        self.assertIn("REALIB_LIBC", self.deps)
        self.assertIn("https://zlib.net/zlib-1.3.1.tar.gz", self.deps)
        self.assertIn("/tmp/zlib-1.3.1", self.workflow)

    def test_bionic_setup_fails_fast_on_missing_toolchain_or_proxy(self) -> None:
        self.assertGreaterEqual(self.workflow.count("curl -fsSI --max-time 15 -x http://127.0.0.1:3128"), 2)
        self.assertIn("TOOLCHAIN_FAILURE", (SCRIPTS / "configure-bionic-env.sh").read_text(encoding="utf-8"))
        self.assertIn('for tool in cargo rustc clang clang++ llvm-ar', (SCRIPTS / "configure-bionic-env.sh").read_text(encoding="utf-8"))
        self.assertIn("Create LD-clean host compiler wrappers", self.workflow)
        self.assertIn("unset LD_LIBRARY_PATH", (SCRIPTS / "create-ld-clean-wrappers.sh").read_text(encoding="utf-8"))

    def test_failed_diagnostics_are_optional(self) -> None:
        self.assertIn("Package bionic diagnostics", self.workflow)
        self.assertIn("if-no-files-found: ignore", self.workflow)
        self.assertIn("No e2e log was produced", self.workflow)

    def test_rust_incremental_is_disabled(self) -> None:
        self.assertIn('CARGO_INCREMENTAL: "0"', self.workflow)


if __name__ == "__main__":
    unittest.main()
