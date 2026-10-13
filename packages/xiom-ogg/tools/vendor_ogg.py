#!/usr/bin/env python3
# XIOM -- xiom.ogg vendoring script (libogg packet layer).
#
# Copies pinned libogg v1.3.6 sources from the local clone into vendor/ogg/
# and records the audit chain in vendor/MANIFEST.sha256.
#
# THE REWRITE (documented carve; see PROVENANCE.md and MANIFEST.sha256):
# the XIOM --c-source pipeline compiles C without -I flags, and the upstream
# sources use ANGLE includes of the public headers
# (`#include <ogg/ogg.h>`, `#include <ogg/os_types.h>`); angle includes are
# not resolved relative to the including file, so upstream files cannot
# compile in place.  Exactly four include lines are rewritten to quoted
# relative form (the ONLY delta):
#
#   src/bitwise.c      #include <ogg/ogg.h>        -> #include "ogg.h"
#   src/framing.c      #include <ogg/ogg.h>        -> #include "ogg.h"
#   include/ogg/ogg.h  #include <ogg/os_types.h>   -> #include "os_types.h"
#   src/crctable.h     #include <ogg/os_types.h>   -> #include "os_types.h"
#
# The rewrite is deterministic (exact-string replacement, abort on miss) and
# the manifest records BOTH the upstream SHA256 and the vendored SHA256 per
# file so the delta stays auditable.  No other byte changes.
#
# Usage:
#   python tools/vendor_ogg.py                      # clone = E:\repos\ogg
#   python tools/vendor_ogg.py --clone <dir> --out <vendor dir>

import argparse
import hashlib
import os
import subprocess
import sys

PIN = "be05b13e98b048f0b5a0f5fa8ce514d56db5f822"  # v1.3.6
PIN_TAG = "v1.3.6"

# (upstream relative path, vendored flat name)
FILES = [
    ("src/bitwise.c", "bitwise.c"),
    ("src/framing.c", "framing.c"),
    ("src/crctable.h", "crctable.h"),
    ("include/ogg/ogg.h", "ogg.h"),
    ("include/ogg/os_types.h", "os_types.h"),
]

REWRITES = [
    (b"#include <ogg/ogg.h>", b'#include "ogg.h"'),
    (b"#include <ogg/os_types.h>", b'#include "os_types.h"'),
]


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest().upper()


def sha256_file(path):
    with open(path, "rb") as f:
        return sha256_bytes(f.read())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clone", default=r"E:\repos\ogg")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "vendor"))
    args = ap.parse_args()

    clone = os.path.abspath(args.clone)
    out = os.path.abspath(args.out)
    flat = os.path.join(out, "ogg")

    head = subprocess.check_output(["git", "-C", clone, "rev-parse", "HEAD"]).decode().strip()
    if head != PIN:
        print("FATAL: clone HEAD %s != pinned %s (%s)" % (head, PIN, PIN_TAG))
        return 1

    os.makedirs(flat, exist_ok=True)

    manifest = []
    for rel, flatname in FILES:
        src = os.path.join(clone, *rel.split("/"))
        raw = open(src, "rb").read()
        upstream_sha = sha256_bytes(raw)
        out_bytes = raw
        for old, new in REWRITES:
            out_bytes = out_bytes.replace(old, new)
        dst = os.path.join(flat, flatname)
        with open(dst, "wb") as f:
            f.write(out_bytes)
        manifest.append((rel, flatname, upstream_sha, sha256_bytes(out_bytes),
                         "rewritten" if out_bytes != raw else "verbatim"))

    # license files, verbatim
    for lic in ["COPYING"]:
        lic_src = os.path.join(clone, lic)
        with open(lic_src, "rb") as f:
            raw = f.read()
        with open(os.path.join(out, lic), "wb") as f:
            f.write(raw)
        manifest.append((lic, lic, sha256_bytes(raw), sha256_bytes(raw), "verbatim"))

    # aborts if a rewrite pattern went missing (pin drift), enforced above by
    # construction; verify the rewrite actually applied where expected.
    for rel, flatname, up_sha, v_sha, kind in manifest:
        if rel in ("src/bitwise.c", "src/framing.c", "include/ogg/ogg.h", "src/crctable.h") and kind != "rewritten":
            print("FATAL: rewrite did not apply for %s (pattern missing)" % rel)
            return 1

    lines = []
    for rel, flatname, up_sha, v_sha, kind in sorted(manifest, key=lambda x: x[0]):
        lines.append("%s  %s  %s  %s  upstream=%s" % (v_sha, rel, "vendor/ogg/" + flatname, kind, up_sha))
    with open(os.path.join(out, "MANIFEST.sha256"), "w", newline="\n") as f:
        f.write("# xiom.ogg vendored file manifest -- libogg %s %s\n" % (PIN_TAG, PIN))
        f.write("# columns: vendored-sha256  upstream-path  vendored-path  kind  upstream-sha256\n")
        f.write("# 'rewritten' = four include lines converted from <angle> to \"quoted\" form;\n")
        f.write("# the ONLY delta (see tools/vendor_ogg.py header).\n")
        f.write("\n".join(lines) + "\n")

    print("vendored %d files from %s (%s)" % (len(manifest), clone, PIN_TAG))
    return 0


if __name__ == "__main__":
    sys.exit(main())
