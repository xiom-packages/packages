#!/usr/bin/env python3
# XIOM -- xiom.spz vendor build-up (deterministic, Python stdlib only).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# The vendored `load-spz.cc` (byte-pinned upstream, see PROVENANCE.md) includes
# `<zlib.h>` and `<zstd.h>` with angle brackets. The pinned XIOM toolchain's
# `--c-source` path offers no include-directory flag (verified on v0.64.4:
# `xiom --help` has no -I; clang is invoked from a scratch cwd), so angle
# includes cannot resolve to the sibling vendor directories.
#
# This script produces `vendor/spz/load-spz.build.cc`: the pinned source with
# EXACTLY two documented include-style rewrites (angle -> quoted relative).
# Every rewrite is verified to apply exactly once; the build copy, the input
# and the rewrite list are hashed into docs/vendor_manifest.json. No other
# byte of the upstream file is touched.
#
# Usage:  python tools/build_vendor.py
# Exit code: 0 = manifest written, 1 = rewrite failed closed.

import hashlib
import io
import json
import os
import sys

REWRITES = [
    ("#include <zlib.h>", '#include "../zlib/zlib.h"'),
    ("#include <zstd.h>", '#include "../zstd/zstd.h"'),
]

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    src = os.path.join(ROOT, "vendor", "spz", "load-spz.cc")
    dst = os.path.join(ROOT, "vendor", "spz", "load-spz.build.cc")
    with open(src, "rb") as f:
        data = f.read()
    if b"\r\n" in data:
        sys.stderr.write("load-spz.cc is not LF-normalized; refusing\n")
        return 1

    applied = []
    for old, new in REWRITES:
        needle = old.encode("ascii")
        count = data.count(needle)
        if count != 1:
            sys.stderr.write("rewrite %r matched %d times (need exactly 1)\n" % (old, count))
            return 1
        data = data.replace(needle, new.encode("ascii"))
        applied.append({"from": old, "to": new, "occurrences": 1})

    with open(dst, "wb") as f:
        f.write(data)

    # Hash every vendored file (sorted, deterministic) except the generated
    # build copy itself.
    inputs = {}
    vendor_root = os.path.join(ROOT, "vendor")
    for dirpath, _dirnames, filenames in os.walk(vendor_root):
        for fn in sorted(filenames):
            path = os.path.join(dirpath, fn)
            rel = os.path.relpath(path, ROOT).replace("\\", "/")
            if rel == "vendor/spz/load-spz.build.cc":
                continue
            inputs[rel] = sha256_file(path)

    manifest = {
        "package": "xiom.spz",
        "generator": "tools/build_vendor.py",
        "inputs": inputs,
        "outputs": {
            "vendor/spz/load-spz.build.cc": sha256_file(dst),
        },
        "rewrites": applied,
    }
    out = os.path.join(ROOT, "docs", "vendor_manifest.json")
    with io.open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print("build_vendor: wrote %s (%d bytes, %d rewrite(s))" % (dst, len(data), len(applied)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
