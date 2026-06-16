#!/usr/bin/env python3
import json
import pathlib


ROOT = pathlib.Path("src")
OUT = pathlib.Path("avd-project-probe.json")


def find(pattern):
    return sorted(str(path) for path in ROOT.rglob(pattern))


def main():
    if not ROOT.is_dir():
        result = {
            "status": "missing_src",
            "summary": "private repo checkout not present",
            "signals": {},
        }
    else:
        signals = {
            "apk_files": find("*.apk"),
            "aab_files": find("*.aab"),
            "shared_libs": find("*.so"),
            "gradle_build_files": find("build.gradle") + find("build.gradle.kts"),
            "android_manifests": find("AndroidManifest.xml"),
        }
        result = {
            "status": "ok",
            "summary": {
                "apk_count": len(signals["apk_files"]),
                "aab_count": len(signals["aab_files"]),
                "shared_lib_count": len(signals["shared_libs"]),
                "gradle_file_count": len(signals["gradle_build_files"]),
                "manifest_count": len(signals["android_manifests"]),
            },
            "signals": signals,
        }

    OUT.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
