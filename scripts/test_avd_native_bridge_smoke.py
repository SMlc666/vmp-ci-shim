#!/usr/bin/env python3
import importlib.util
import pathlib
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / ".github" / "scripts" / "avd-native-bridge-smoke.py"


def load_module():
    spec = importlib.util.spec_from_file_location("avd_native_bridge_smoke", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class AvdNativeBridgeSmokeTest(unittest.TestCase):
    def test_parser_requires_battery_fails_zero(self) -> None:
        module = load_module()
        sample = "\n".join(
            [
                "I/NativeBridgeSmoke: before System.loadLibrary",
                "I/NativeBridgeSmoke: JNI_OnLoad reached",
                "I/NativeBridgeSmoke: after System.loadLibrary",
                "I/NativeBridgeSmoke: MainActivity.onCreate",
            ]
        )
        with tempfile.TemporaryDirectory() as tmp:
            result = module.evaluate_smoke_output(sample, module.TAG, pathlib.Path(tmp))
        self.assertEqual(result["status"], "fail")
        self.assertIn("BATTERY-FAILS=0", result["detail"])


if __name__ == "__main__":
    unittest.main()
