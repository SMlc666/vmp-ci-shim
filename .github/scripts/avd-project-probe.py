#!/usr/bin/env python3
import json
import pathlib
import struct


ROOT = pathlib.Path("src")
OUT = pathlib.Path("avd-project-probe.json")
EM_X86_64 = 62
EM_AARCH64 = 183
ELF_TYPE_SHARED = 3
ELF_TYPE_EXEC = 2


def read_elf_metadata(path):
    try:
        with path.open("rb") as f:
            ident = f.read(16)
            if len(ident) < 16 or ident[:4] != b"\x7fELF":
                return {"kind": "non_elf"}
            elf_class = ident[4]
            data = ident[5]
            if elf_class != 2 or data != 1:
                return {"kind": "unsupported_elf", "class": elf_class, "data": data}
            header = f.read(48)
            if len(header) < 48:
                return {"kind": "truncated_elf"}
            e_type, e_machine = struct.unpack("<HH", header[:4])
            return {
                "kind": "elf",
                "e_type": e_type,
                "e_machine": e_machine,
            }
    except OSError as exc:
        return {"kind": "error", "detail": str(exc)}


def find(pattern):
    return sorted(str(path) for path in ROOT.rglob(pattern))


def arch_name(e_machine):
    if e_machine == EM_X86_64:
        return "x86_64"
    if e_machine == EM_AARCH64:
        return "aarch64"
    return f"machine_{e_machine}"


def classify_shared_libs(paths):
    arch_summary = {}
    entries = []
    avd_compatible = []
    android_arm64 = []
    for path_str in paths:
        path = pathlib.Path(path_str)
        meta = read_elf_metadata(path)
        kind = meta["kind"]
        if kind == "elf":
            arch = arch_name(meta["e_machine"])
            arch_summary[arch] = arch_summary.get(arch, 0) + 1
            entry = {
                "path": path_str,
                "kind": "elf",
                "arch": arch,
                "elf_type": meta["e_type"],
                "looks_loadable_on_android": meta["e_type"] in {ELF_TYPE_SHARED, ELF_TYPE_EXEC},
                "avd_x86_64_candidate": meta["e_machine"] == EM_X86_64,
                "android_arm64_candidate": meta["e_machine"] == EM_AARCH64,
            }
            if entry["avd_x86_64_candidate"]:
                avd_compatible.append(path_str)
            if entry["android_arm64_candidate"]:
                android_arm64.append(path_str)
        else:
            arch_summary[kind] = arch_summary.get(kind, 0) + 1
            entry = {
                "path": path_str,
                "kind": kind,
                "looks_loadable_on_android": False,
                "avd_x86_64_candidate": False,
                "android_arm64_candidate": False,
            }
            if "detail" in meta:
                entry["detail"] = meta["detail"]
            if "class" in meta:
                entry["class"] = meta["class"]
            if "data" in meta:
                entry["data"] = meta["data"]
        entries.append(entry)
    return {
        "elf_arch_summary": dict(sorted(arch_summary.items())),
        "shared_lib_details": entries,
        "avd_compatible_shared_lib_count": len(avd_compatible),
        "avd_compatible_shared_libs": avd_compatible,
        "android_arm64_shared_lib_count": len(android_arm64),
        "android_arm64_shared_libs": android_arm64,
    }


def main():
    if not ROOT.is_dir():
        result = {
            "status": "missing_src",
            "summary": "private repo checkout not present",
            "signals": {},
            "native_probe": {},
        }
    else:
        signals = {
            "apk_files": find("*.apk"),
            "aab_files": find("*.aab"),
            "shared_libs": find("*.so"),
            "gradle_build_files": find("build.gradle") + find("build.gradle.kts"),
            "android_manifests": find("AndroidManifest.xml"),
        }
        native_probe = classify_shared_libs(signals["shared_libs"])
        result = {
            "status": "ok",
            "summary": {
                "apk_count": len(signals["apk_files"]),
                "aab_count": len(signals["aab_files"]),
                "shared_lib_count": len(signals["shared_libs"]),
                "gradle_file_count": len(signals["gradle_build_files"]),
                "manifest_count": len(signals["android_manifests"]),
                "avd_compatible_shared_lib_count": native_probe["avd_compatible_shared_lib_count"],
                "android_arm64_shared_lib_count": native_probe["android_arm64_shared_lib_count"],
            },
            "signals": signals,
            "native_probe": native_probe,
        }

    OUT.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
