#!/usr/bin/env python3
import pathlib
import unittest


MANIFEST = pathlib.Path(__file__).resolve().parents[1] / ".github" / "native_bridge_smoke" / "AndroidManifest.xml"


class NativeBridgeManifestTest(unittest.TestCase):
    def test_manifest_declares_internet_permission_for_loopback_socket_smoke(self) -> None:
        text = MANIFEST.read_text(encoding="utf-8")
        self.assertIn(
            'android.permission.INTERNET',
            text,
            "native-bridge smoke manifest must declare INTERNET for loopback socket battery cases",
        )


if __name__ == "__main__":
    unittest.main()
