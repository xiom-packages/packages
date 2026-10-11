#!/usr/bin/env python3
"""Iteratively compile tools/struct_dump.cpp and record header-unavailable
struct names in tools/struct_dump_skip.json until the dump compiles clean.

The unavailable set = registry structs declared only in headers this SDK does
not ship for the C API (Vulkan SC pipeline-cache safety structs etc.); they are
listed in docs/struct_meta_manifest.json with this reason.

Run (repo root): python packages/xiom-vulkan/tools/find_unavailable_structs.py
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLANG = r"C:\Program Files\LLVM\bin\clang++.exe"
INCLUDE = r"C:\VulkanSDK\1.4.350.0\Include"
SKIP = os.path.join(ROOT, "tools", "struct_dump_skip.json")
CPP = os.path.join(ROOT, "tools", "struct_dump.cpp")
GEN = os.path.join(ROOT, "tools", "gen_vk.py")
OUT = os.path.join(os.environ.get("TEMP", "."), "struct_dump.exe")


def load_skip():
    if os.path.exists(SKIP):
        try:
            v = json.load(open(SKIP, encoding="utf-8"))
            if isinstance(v, list):
                return sorted({x for x in v if isinstance(x, str)})
        except Exception:
            pass
    return []


def save_skip(names):
    with open(SKIP, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(sorted(set(names)), fh, indent=1)


def main():
    for i in range(1, 15):
        subprocess.run([sys.executable, GEN, "--emit-dump"], check=True,
                       capture_output=True)
        r = subprocess.run([CLANG, "-std=c++14", "-ferror-limit=0", "-I", INCLUDE,
                            CPP, "-o", OUT], capture_output=True, text=True)
        if r.returncode == 0:
            print("CLEAN after iteration", i, "; unavailable skips:",
                  len(load_skip()))
            return 0
        flat = re.sub(r"\s+", " ", r.stderr)
        names = set(re.findall(r"unknown type name '(\w+)'", flat))
        names |= set(re.findall(r"use of undeclared identifier '(\w+)'", flat))
        if not names:
            print("no names parsed; stderr head:", r.stderr[:600])
            return 1
        cur = load_skip()
        new = sorted(names - set(cur))
        if not new:
            print("iteration", i, "no progress; names:", sorted(names))
            return 1
        save_skip(cur + new)
        print("iteration", i, "added", len(new), "skip names:", ", ".join(new))
    print("max iterations reached")
    return 1


if __name__ == "__main__":
    sys.exit(main())
