#!/usr/bin/env python3
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / ".github" / "scripts" / "build-native-bridge-harness.sh"


class BuildNativeBridgeHarnessTest(unittest.TestCase):
    def test_packages_cpp_business_android_artifacts_instead_of_toy_jni(self) -> None:
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertIn(
            'CPP_BUSINESS_DIR="$PRIVATE_SRC_DIR/tests/realib_fixtures/cpp_business"',
            text,
            "builder must point at the private cpp_business fixture tree",
        )
        self.assertIn(
            'bash "$CPP_BUSINESS_DIR/build.sh" --android-arm64',
            text,
            "builder must invoke the private cpp_business Android build",
        )
        self.assertIn(
            "libcpp_business.so",
            text,
            "builder must package libcpp_business.so into the APK payload",
        )
        self.assertIn(
            "libcpp_business_jni.so",
            text,
            "builder must package libcpp_business_jni.so into the APK payload",
        )
        self.assertIn(
            "libc++_shared.so",
            text,
            "builder must package the Android C++ runtime needed by the translated JNI libraries",
        )
        self.assertNotIn(
            "bridge_jni.c",
            text,
            "builder must stop compiling the toy bridge_jni.c harness",
        )
        self.assertNotIn(
            "libbridge_smoke.so",
            text,
            "builder must stop packaging the toy libbridge_smoke.so payload",
        )


if __name__ == "__main__":
    unittest.main()
