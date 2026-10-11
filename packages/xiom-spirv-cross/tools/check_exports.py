#!/usr/bin/env python3
"""Compare spirv-cross-c-shared.dll exports against the header oracle.

Oracle: the spvc_* functions parsed from spirv_cross_c.h by
tools/gen_spirv_cross.py.  Proof target: every header-declared function is
EXPORTED by the shipped DLL (so the suite's `resolved=N/N` can be N == N).

Pure stdlib: parses the PE export table directly (no dumpbin/objdump needed).

Usage:
  python tools/check_exports.py [--dll <path>] [--header <path>]

Prints: exports=<n> header=<n> missing=<n> extra=<n> and lists any mismatch.
Exit code 0 when missing == 0.
"""

import argparse
import io
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gen_spirv_cross  # noqa: E402  (committed sibling generator)

DEFAULT_DLL = r"C:\VulkanSDK\1.4.350.0\Bin\spirv-cross-c-shared.dll"


def pe_exports(path):
    data = io.open(path, "rb").read()
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    if data[e_lfanew:e_lfanew + 4] != b"PE\x00\x00":
        raise ValueError("not a PE file: %s" % path)
    coff = e_lfanew + 4
    nsec = struct.unpack_from("<H", data, coff + 2)[0]
    optsize = struct.unpack_from("<H", data, coff + 16)[0]
    optoff = coff + 20
    magic = struct.unpack_from("<H", data, optoff)[0]
    dd = optoff + (112 if magic == 0x20B else 96)
    exp_rva, _exp_size = struct.unpack_from("<II", data, dd)
    secs = []
    so = optoff + optsize
    for i in range(nsec):
        b = so + i * 40
        _name = data[b:b + 8].rstrip(b"\x00").decode()
        vsize, vaddr, rsize, raddr = struct.unpack_from("<IIII", data, b + 8)
        secs.append((vaddr, max(vsize, rsize), raddr))

    def rva2off(rva):
        for vaddr, size, raddr in secs:
            if vaddr <= rva < vaddr + size:
                return raddr + (rva - vaddr)
        raise ValueError("rva not mapped: 0x%x" % rva)

    def rd(rva, fmt):
        return struct.unpack_from(fmt, data, rva2off(rva))

    _nfun, nname = rd(exp_rva + 20, "<II")
    _afun, aname, _aord = rd(exp_rva + 28, "<III")
    names = []
    for i in range(nname):
        nrva, = rd(aname + 4 * i, "<I")
        off = rva2off(nrva)
        end = data.index(b"\x00", off)
        names.append(data[off:end].decode())
    return sorted(names)


def header_functions(header_path):
    raw = gen_spirv_cross.strip_comments(io.open(header_path, encoding="utf-8").read())
    text = re.sub(r"\s+", " ", gen_spirv_cross.strip_preprocessor(raw))
    return sorted(f["name"] for f in gen_spirv_cross.parse_functions(text))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dll", default=DEFAULT_DLL)
    ap.add_argument("--header", default=gen_spirv_cross.DEFAULT_HEADER)
    args = ap.parse_args()

    if not os.path.isfile(args.dll):
        print("DLL not found: %s (SKIP)" % args.dll)
        return 0

    exports = set(pe_exports(args.dll))
    oracle = set(header_functions(args.header))
    spvc_exports = set(n for n in exports if n.startswith("spvc_"))
    missing = sorted(oracle - spvc_exports)
    extra = sorted(spvc_exports - oracle)
    print("exports=%d (spvc_*=%d) header=%d missing=%d extra=%d"
          % (len(exports), len(spvc_exports), len(oracle), len(missing), len(extra)))
    for n in missing:
        print("  MISSING: %s" % n)
    for n in extra:
        print("  EXTRA (exported, not declared): %s" % n)
    return 0 if not missing else 1


if __name__ == "__main__":
    raise SystemExit(main())
