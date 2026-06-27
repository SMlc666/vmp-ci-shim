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

    def test_realib_extdeps_cache_keys_track_sources(self) -> None:
        self.assertIn(
            "key: realib-extdeps-glibc-v4-${{ hashFiles('src/tests/realib_fixtures/**', 'src/vmp-lifter/tests/realib_*', 'src/vmp-lifter/tests/realib_common/**') }}",
            self.text,
            "glibc realib extdeps cache must refresh when fixture recipes or suite code change",
        )
        self.assertIn(
            "key: realib-extdeps-bionic-v3-${{ hashFiles('docker/Dockerfile', 'src/tests/realib_fixtures/**', 'src/vmp-lifter/tests/realib_*', 'src/vmp-lifter/tests/realib_common/**') }}",
            self.text,
            "bionic realib extdeps cache must refresh when fixture recipes, suite code, or baked image source changes",
        )
        self.assertNotIn(
            "key: realib-extdeps-bionic-v2\n",
            self.text,
            "bionic realib extdeps cache must not be pinned to a static stale key",
        )
        self.assertNotIn(
            "key: realib-extdeps-glibc-v3\n",
            self.text,
            "glibc realib extdeps cache must not be pinned to a static stale key",
        )

    def test_bionic_host_toolchain_wrappers_clear_ld_library_path(self) -> None:
        self.assertIn(
            "Create LD-clean host compiler wrappers (bionic)",
            self.text,
            "bionic CI must install host compiler wrappers before cargo test",
        )
        self.assertIn(
            "for tool in aarch64-linux-gnu-gcc aarch64-linux-gnu-g++ gcc g++ cc c++ clang clang++; do",
            self.text,
            "wrapper must cover host cross compilers that tests may spawn",
        )
        self.assertIn(
            "unset LD_LIBRARY_PATH",
            self.text,
            "host compiler wrappers must not inherit Termux library paths",
        )
        self.assertIn(
            'export PATH="$TERMUX_PREFIX/bin:/tmp/host-toolchain-cleanbin:$PATH"',
            self.text,
            "Termux tools must stay first while host fallbacks run through LD-clean wrappers",
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
