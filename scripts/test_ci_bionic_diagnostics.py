#!/usr/bin/env python3
import pathlib
import unittest


WORKFLOW = pathlib.Path(__file__).resolve().parents[1] / ".github" / "workflows" / "ci.yml"


class BionicDiagnosticsWorkflowTest(unittest.TestCase):
    def setUp(self) -> None:
        self.text = WORKFLOW.read_text(encoding="utf-8")

    def test_bionic_cargo_cache_key_is_commit_specific(self) -> None:
        self.assertIn(
            "key: cargo-bionic-${{ hashFiles('src/Cargo.lock') }}-${{ inputs.commit_sha }}",
            self.text,
            "bionic target cache must not reuse an exact key across private repo commits",
        )
        self.assertIn(
            "cargo-bionic-${{ hashFiles('src/Cargo.lock') }}-",
            self.text,
            "bionic target cache should still restore from same-lockfile prefixes",
        )

    def test_bionic_userland_cache_key_tracks_image_source(self) -> None:
        self.assertIn(
            "BIONIC_CACHE_VERSION:",
            self.text,
            "bionic userland cache must expose one version string shared by restore/save",
        )
        self.assertIn(
            "key: bionic-userland-${{ env.BIONIC_CACHE_VERSION }}-${{ hashFiles('docker/Dockerfile') }}",
            self.text,
            "bionic userland cache key must change when the baked image recipe changes",
        )

    def test_failed_bionic_run_uploads_real_fixture_tarball(self) -> None:
        self.assertIn(
            "E2E_DIR=src/vmp-lifter/fixtures/e2e",
            self.text,
            "fixture packaging must read from the actual private checkout, not TERMUX_HOME/src",
        )
        self.assertIn(
            "cp -a \"$TERMUX_HOME/target/debug/vmp-runner\" /tmp/bionic-diagnostics/vmp-runner",
            self.text,
            "artifact must include the bionic-built runner needed to replay remote .so files",
        )
        self.assertIn(
            "if-no-files-found: error",
            self.text,
            "missing bionic diagnostic artifacts must fail visibly instead of warning",
        )


if __name__ == "__main__":
    unittest.main()
