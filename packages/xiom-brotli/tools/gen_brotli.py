#!/usr/bin/env python3
# XIOM -- xiom.brotli vendoring tool.
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Generates the vendored brotli C tree (vendor/brotli) from the upstream
# study clone (E:\repos\brotli, pinned release tag -- see PROVENANCE.md).
#
# Vendored layout (strips the upstream `c/` level, everything else identical):
#
#   vendor/brotli/LICENSE
#   vendor/brotli/include/brotli/*.h        (the 5 public headers)
#   vendor/brotli/{common,dec,enc}/*.c,*.h  (the sources the C build compiles)
#
# Skipped on purpose (not part of the C build; recorded in PROVENANCE.md):
#   c/common/dictionary.bin, dictionary.bin.br  (dictionary rebuild inputs;
#     dictionary.c embeds the data through dictionary_inc.h)
#   c/enc/static_init_lazy.cc                   (experimental C++ static-init
#     variant; the default build compiles static_init.c)
#
# THE ONE MECHANICAL REWRITE (the only textual change vs upstream):
#   angle includes of the public headers cannot resolve without an -I path
#   (the xiom `--c-source` link line adds none), so each
#       #include <brotli/NAME.h>
#   is rewritten to a relative quoted include:
#   from include/brotli/  ->  #include "NAME.h"
#       from common|dec|enc/  ->  #include "../include/brotli/NAME.h"
#   Exactly 24 lines across 16 files at v1.2.0; the tool fails if the count
#   changes (a re-pin must re-bless the rule). No other line is touched.
#   All files are LF-normalized before hashing (Windows checkout note).
#
# Usage:
#   python tools/gen_brotli.py --write            # regenerate vendor/
#   python tools/gen_brotli.py --verify           # byte-compare vendor/ vs clone
#   python tools/gen_brotli.py --print-tree       # name:sha256 table + digest
#
# Exit codes: 0 ok; 1 mismatch/error.

import argparse
import hashlib
import re
import sys
from pathlib import Path

DEFAULT_CLONE = r"E:\repos\brotli"
DEFAULT_OUT = str(Path(__file__).resolve().parent.parent / "vendor" / "brotli")

# Directories to vendor, relative to the upstream `c/` root, with file globs.
VENDOR_DIRS = {
    "include/brotli": ["*.h"],
    "common": ["*.c", "*.h"],
    "dec": ["*.c", "*.h"],
    "enc": ["*.c", "*.h"],
}

# Files explicitly not vendored (documented above).
SKIP_NAMES = {"dictionary.bin", "dictionary.bin.br", "static_init_lazy.cc"}

ANGLE_RE = re.compile(r"^(?P<pre>\s*#\s*include\s*)<brotli/(?P<name>[A-Za-z0-9_.]+\.h)>(?P<post>\s*(?:/\*.*)?)$")
EXPECTED_REWRITES = 24


def collect(clone: Path):
    """Yield (relative-path-under-vendor/brotli, source-path) pairs."""
    croot = clone / "c"
    entries = []
    for vdir, globs in sorted(VENDOR_DIRS.items()):
        sdir = croot / vdir
        if not sdir.is_dir():
            raise SystemExit("error: missing upstream dir: " + str(sdir))
        for pattern in globs:
            for src in sorted(sdir.glob(pattern)):
                if src.name in SKIP_NAMES:
                    continue
                entries.append((Path(vdir) / src.name, src))
    entries.append((Path("LICENSE"), clone / "LICENSE"))
    return entries


def rewrite(data: bytes, rel: Path):
    """Apply the mechanical angle-include rewrite; return (bytes, count)."""
    text = data.replace(b"\r\n", b"\n").decode("utf-8")
    out_lines = []
    rewritten = 0
    in_public = rel.parts[0] == "include"
    for line in text.split("\n"):
        m = ANGLE_RE.match(line)
        if m:
            name = m.group("name")
            if in_public:
                target = '"%s"' % name
            else:
                target = '"../include/brotli/%s"' % name
            line = m.group("pre") + target + m.group("post")
            rewritten += 1
        out_lines.append(line)
    return ("\n".join(out_lines)).encode("utf-8"), rewritten


def generate(clone: Path, out: Path):
    """Generate the vendor tree; return (files, total_rewrites) or raise."""
    entries = collect(clone)
    total_rewrites = 0
    payload = []
    for rel, src in entries:
        data, n = rewrite(src.read_bytes(), rel)
        total_rewrites += n
        payload.append((rel, data))
    if total_rewrites != EXPECTED_REWRITES:
        raise SystemExit(
            "error: angle-include rewrite count changed: %d (expected %d); "
            "a re-pin must re-bless the rule in tools/gen_brotli.py"
            % (total_rewrites, EXPECTED_REWRITES)
        )
    if "--dry" not in sys.argv:
        for rel, data in payload:
            dest = out / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
    return payload, total_rewrites


def tree_digest(payload):
    """sha256 over sorted 'relpath:sha256' lines (LF), stable across machines."""
    lines = []
    for rel, data in payload:
        digest = hashlib.sha256(data).hexdigest().upper()
        lines.append("%s:%s" % (rel.as_posix(), digest))
    blob = ("\n".join(sorted(lines)) + "\n").encode("utf-8")
    return hashlib.sha256(blob).hexdigest().upper(), lines


def main():
    ap = argparse.ArgumentParser(description="xiom.brotli vendoring tool")
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true", help="write vendor/brotli")
    mode.add_argument("--verify", action="store_true", help="compare vendor/ vs clone")
    mode.add_argument("--print-tree", action="store_true", help="print per-file hashes")
    ap.add_argument("--clone", default=DEFAULT_CLONE)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--dry", action="store_true", help=argparse.SUPPRESS)
    args = ap.parse_args()

    clone = Path(args.clone)
    out = Path(args.out)
    if not (clone / "LICENSE").is_file():
        raise SystemExit("error: clone not found or incomplete: " + str(clone))

    payload, rewrites = generate(clone, out)

    if args.verify:
        bad = 0
        for rel, data in payload:
            dest = out / rel
            if not dest.is_file():
                print("MISSING " + rel.as_posix())
                bad += 1
            elif dest.read_bytes() != data:
                print("DIFFERS " + rel.as_posix())
                bad += 1
        extra = []
        if out.is_dir():
            expected = {rel.as_posix() for rel, _ in payload}
            for f in sorted(out.rglob("*")):
                if f.is_file() and f.relative_to(out).as_posix() not in expected:
                    extra.append(f.relative_to(out).as_posix())
        for e in extra:
            print("UNEXPECTED " + e)
        if bad or extra:
            raise SystemExit("verify: %d differing/missing, %d unexpected" % (bad, len(extra)))
        digest, _ = tree_digest(payload)
        print("verify OK: %d files, %d rewritten include lines, tree sha256 %s"
              % (len(payload), rewrites, digest))
        return

    digest, lines = tree_digest(payload)
    if args.print_tree:
        for line in sorted(lines):
            print(line)
    if args.write:
        print("wrote %d files to %s (%d rewritten include lines)"
              % (len(payload), out, rewrites))
    print("tree sha256 %s" % digest)


if __name__ == "__main__":
    main()
