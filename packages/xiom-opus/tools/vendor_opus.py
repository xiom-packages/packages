#!/usr/bin/env python3
# XIOM -- xiom.opus vendoring script.
#
# Copies the pinned libopus v1.6.1 sources from the local clone into
# vendor/opus/ in the FLAT layout the XIOM --c-source toolchain requires:
# the xiom toolchain compiles every --c-source file in one clang invocation
# with no -I flags, and the upstream opus sources use cross-directory quoted
# includes ("celt.h" from src/, "float/structs_FLP.h", ...) that only resolve
# when the whole tree is one directory.  Files are copied BYTE-IDENTICAL;
# vendor/MANIFEST.sha256 maps every vendored file back to its upstream path
# and records its SHA256, so the tree is auditable against the pin.
#
# Deterministic: sorted iteration, LF manifest, no timestamps.
#
# Usage:
#   python tools/vendor_opus.py                       # clone = E:\repos\opus
#   python tools/vendor_opus.py --clone <dir> --out <vendor dir>
#
# Exit code 0 = vendored + manifest written; 1 = pin/mismatch error.

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys

PIN = "22244de5a79bd1d6d623c32e72bf1954b56235be"  # v1.6.1
PIN_TAG = "v1.6.1"

HEADER_DIRS = ["celt", "silk", "silk/float", "silk/fixed", "src", "include"]
# The float (default) build compiles: CELT_SOURCES, SILK_SOURCES,
# SILK_SOURCES_FLOAT, OPUS_SOURCES, OPUS_SOURCES_FLOAT.
MK_FILES = {
    "celt": "celt_sources.mk",
    "silk": "silk_sources.mk",
    "opus": "opus_sources.mk",
}
MK_LISTS = {
    "celt": ["CELT_SOURCES"],
    "silk": ["SILK_SOURCES", "SILK_SOURCES_FLOAT"],
    "opus": ["OPUS_SOURCES", "OPUS_SOURCES_FLOAT"],
}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def parse_mk(path):
    text = open(path, encoding="utf8").read().replace("\\\n", "")
    out = {}
    for line in text.split("\n"):
        line = line.strip()
        if not line or "=" not in line:
            continue
        var, files = line.split("=", 1)
        out[var.strip()] = [f for f in files.split() if f]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clone", default=r"E:\repos\opus")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "vendor"))
    args = ap.parse_args()

    clone = os.path.abspath(args.clone)
    out = os.path.abspath(args.out)
    flat = os.path.join(out, "opus")

    head = subprocess.check_output(["git", "-C", clone, "rev-parse", "HEAD"]).decode().strip()
    if head != PIN:
        print("FATAL: clone HEAD %s != pinned %s (%s)" % (head, PIN, PIN_TAG))
        return 1

    build_c = []
    for group, mks in MK_LISTS.items():
        parsed = parse_mk(os.path.join(clone, MK_FILES[group]))
        for name in mks:
            build_c.extend(parsed[name])

    # Collect headers + build sources, checking basename uniqueness.
    seen = {}
    headers = []
    for sub in HEADER_DIRS:
        d = os.path.join(clone, *sub.split("/"))
        for f in sorted(os.listdir(d)):
            p = os.path.join(d, f)
            if not os.path.isfile(p) or not f.endswith(".h"):
                continue
            if f in seen:
                print("FATAL: header basename collision: %s (%s vs %s)" % (f, seen[f], sub))
                return 1
            seen[f] = sub
            headers.append((sub, f))
    for rel in build_c:
        f = os.path.basename(rel)
        if f in seen:
            print("FATAL: source basename collision: %s (%s vs %s)" % (f, seen[f], rel))
            return 1
        seen[f] = rel

    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(os.path.join(flat, "float"))
    os.makedirs(os.path.join(flat, "fixed"))

    manifest = []
    for sub, f in headers:
        src = os.path.join(clone, *sub.split("/"), f)
        dst = os.path.join(flat, f)
        shutil.copyfile(src, dst)
        manifest.append((dst, sub + "/" + f))
        # subdir copies for prefixed include spellings ("float/x.h").
        if sub == "silk/float":
            shutil.copyfile(src, os.path.join(flat, "float", f))
        if sub == "silk/fixed":
            shutil.copyfile(src, os.path.join(flat, "fixed", f))
    for rel in build_c:
        src = os.path.join(clone, *rel.split("/"))
        dst = os.path.join(flat, os.path.basename(rel))
        shutil.copyfile(src, dst)
        manifest.append((dst, rel))
    for lic in ["COPYING", "LICENSE_PLEASE_READ.txt"]:
        shutil.copyfile(os.path.join(clone, lic), os.path.join(out, lic))

    lines = []
    for dst, rel in sorted(manifest, key=lambda x: x[1]):
        lines.append("%s  %s  %s" % (sha256(dst), rel, os.path.relpath(dst, out).replace("\\", "/")))
    with open(os.path.join(out, "MANIFEST.sha256"), "w", newline="\n") as f:
        f.write("# xiom.opus vendored file manifest -- libopus %s %s\n" % (PIN_TAG, PIN))
        f.write("# columns: sha256  upstream-path  vendored-path (flat tree, byte-identical)\n")
        f.write("\n".join(lines) + "\n")

    print("vendored %d files + 2 license files from %s (%s)" % (len(manifest), clone, PIN_TAG))
    return 0


if __name__ == "__main__":
    sys.exit(main())
