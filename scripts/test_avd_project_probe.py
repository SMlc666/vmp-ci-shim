#!/usr/bin/env python3
import json
import os
import pathlib
import struct
import subprocess
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / ".github" / "scripts" / "avd-project-probe.py"


def write_elf_shared_object(path: pathlib.Path, machine: int) -> None:
    e_ident = bytearray(b"\x7fELF")
    e_ident.extend([2, 1, 1, 0, 0])
    e_ident.extend(b"\x00" * 7)
    header = struct.pack(
        "<16sHHIQQQIHHHHHH",
        bytes(e_ident),
        3,
        machine,
        1,
        0,
        0,
        0,
        0,
        64,
        0,
        0,
        0,
        0,
        0,
    )
    path.write_bytes(header)


class AvdProjectProbeTest(unittest.TestCase):
    def test_reports_native_architecture_breakdown_and_avd_candidates(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            src = root / "src"
            src.mkdir()
            write_elf_shared_object(src / "libx86_64.so", 62)
            write_elf_shared_object(src / "libarm64.so", 183)
            (src / "libfake.so").write_text("not an elf", encoding="utf-8")

            proc = subprocess.run(
                ["python3", str(SCRIPT)],
                cwd=root,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )
            self.assertEqual(proc.returncode, 0, proc.stderr)

            report = json.loads((root / "avd-project-probe.json").read_text(encoding="utf-8"))
            summary = report["summary"]
            native = report["native_probe"]

            self.assertEqual(summary["shared_lib_count"], 3)
            self.assertEqual(native["elf_arch_summary"]["x86_64"], 1)
            self.assertEqual(native["elf_arch_summary"]["aarch64"], 1)
            self.assertEqual(native["elf_arch_summary"]["non_elf"], 1)
            self.assertEqual(summary["android_arm64_shared_lib_count"], 1)
            self.assertEqual(native["android_arm64_shared_lib_count"], 1)
            self.assertEqual(native["android_arm64_shared_libs"], ["src/libarm64.so"])
            self.assertEqual(native["avd_compatible_shared_lib_count"], 1)
            self.assertEqual(native["avd_compatible_shared_libs"], ["src/libx86_64.so"])


if __name__ == "__main__":
    unittest.main()
