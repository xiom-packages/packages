#!/usr/bin/env python3
"""Combine ozz-animation sources into one translation unit (xiom.ozz pin).

This is the amalgamation step referenced by SPEC.md section 2: ozz is a C++
library with no C API and the xiom link line has no include-path passthrough,
so the libary and the bridge are vendored as two generated TUs.

Behaviour (matches the 0.16.0 pin's existing vendor output byte-for-byte):
  * an entry template lists `#include "<root-relative .cc>"` entries in
    dependency order;
  * a quoted include resolves relative to the including file's directory
    first (C-preprocessor semantics), then under each root (`-r`) in order;
  * every resolved include is inlined in place, once (keyed by the resolved
    canonical path), wrapped in start/end markers that quote the include
    name as written;
  * an include of an already-inlined file becomes a `skipping file` marker;
  * unresolvable includes (system headers, unknown paths) are kept verbatim;
  * CRLF is normalized to LF in the output.

Usage:
  python tools/combine.py -r include -r src -o out.cpp entries.cpp

Prints the output byte count and SHA256 (lowercase hex).
"""

import argparse
import hashlib
import os
import re
import sys

INC_RE = re.compile(r'^(\s*)#\s*include\s*"([^"]+)"\s*$')


def resolve(roots, name, base_dir):
    # Quoted includes search the including file's directory first, then the
    # roots in order (the pattern that lets src// headers include "platform.h"
    # next to them).
    candidates = []
    if base_dir:
        candidates.append(os.path.join(base_dir, name))
    for root in roots:
        candidates.append(os.path.join(root, name))
    for candidate in candidates:
        normalized = os.path.normpath(candidate)
        if os.path.isfile(normalized):
            return normalized
    return None


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-r", "--root", action="append", default=[],
                        help="include root (repeatable; searched in order)")
    parser.add_argument("-o", "--output", required=True)
    parser.add_argument("entries", help="entry template listing #include entries")
    args = parser.parse_args(argv)

    if not args.root:
        parser.error("at least one -r/--root is required")
    for root in args.root:
        if not os.path.isdir(root):
            parser.error("root is not a directory: %s" % root)

    inlined = set()
    out = []

    def inline(path, label):
        key = os.path.normcase(os.path.normpath(path))
        if key in inlined:
            out.append("/**** skipping file: %s ****/" % label)
            return
        inlined.add(key)
        out.append("/**** start inlining %s ****/" % label)
        with open(path, "rb") as handle:
            text = handle.read().decode("utf-8")
        text = text.replace("\r\n", "\n").replace("\r", "\n")
        for line in text.splitlines():
            match = INC_RE.match(line)
            if match:
                name = match.group(2)
                target = resolve(args.root, name, os.path.dirname(path))
                if target is not None:
                    inline(target, name)
                    continue
            out.append(line)
        out.append("/**** ended inlining %s ****/" % label)

    with open(args.entries, "rb") as handle:
        template = handle.read().decode("utf-8")
    template = template.replace("\r\n", "\n").replace("\r", "\n")
    entries_dir = os.path.dirname(os.path.abspath(args.entries))
    for line in template.splitlines():
        match = INC_RE.match(line)
        if match:
            name = match.group(2)
            target = resolve(args.root, name, entries_dir)
            if target is not None:
                inline(target, name)
                continue
        out.append(line)

    data = ("\n".join(out) + "\n").encode("utf-8")
    with open(args.output, "wb") as handle:
        handle.write(data)

    digest = hashlib.sha256(data).hexdigest()
    print("wrote %s: %d bytes sha256 %s" % (args.output, len(data), digest))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
