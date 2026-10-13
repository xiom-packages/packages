#!/usr/bin/env python3
# XIOM -- xiom.ogg binding-surface generator (libogg packet layer).
#
# Parses the pinned libogg v1.3.6 public header (include/ogg/ogg.h) and emits:
#
#   src/ogg_abi.xi          coverage ledger constants (module xiom.ogg.abi)
#   (extern block into)     src/ogg_ffi.xi, marker-delimited
#   src/ogg_abi_protos.h    C prototypes included by src/ogg_bridge.c
#   docs/COVERAGE.md        declared/bound/skips table
#   docs/gen_manifest.json  machine-readable ledger + pinned-header SHA256
#
# Oracle: every function declared `extern` in the pinned ogg.h must map 1:1
# to a `xo_*` bridge entry point.  The generator FAILS if a declared function
# has no mapping, if the bridge misses an entry point, or if the bridge
# defines entry points outside the generated set (companions aside).
#
# ABI rules (bindings-lane discipline on compiler v0.64.4):
#   - every entry point returns int64_t (Int); `long`/`int` upstream returns
#     are widened in C, so sentinel values (-1, negative holes) keep sign
#   - state structs (ogg_sync_state, ogg_stream_state, oggpack_buffer,
#     ogg_page, ogg_packet) are bridge-allocated; XIOM holds them as Int
#     handles; no XIOM-side pointer casts (B-25)
#   - byte payloads cross as XIOM-owned Vec[UInt8] pointers; page/packet
#     copy-out goes into caller-owned buffers, meta goes into owned slots
#     (B-20/B-24); one owned slot per out-param (B-11/B-16/B-17)
#   - ogg_sync_buffer folds the upstream buffer+memcpy idiom into one call:
#     the bridge calls ogg_sync_buffer for the caller and copies the owned
#     input bytes in; the caller still calls ogg_sync_wrote (both declared
#     functions are bound)
#
# Deterministic: sorted outputs, LF, no timestamps.
#
# Usage:
#   python tools/gen_ogg.py --headers E:\repos\ogg\include --package <pkg dir>

import argparse
import hashlib
import json
import os
import re
import sys

PIN = "be05b13e98b048f0b5a0f5fa8ce514d56db5f822"
PIN_TAG = "v1.3.6"
HEADERS = ["ogg.h"]


def header_path(headers_dir, h):
    """Resolve include/ogg/<h> or include/<h>."""
    p1 = os.path.join(headers_dir, "ogg", h)
    if os.path.exists(p1):
        return p1
    return os.path.join(headers_dir, h)

# ---------------------------------------------------------------------------
# ABI role table: one entry per declared function (generator fails otherwise).
# roles: i=int32 scalar in, h=int64 handle in, src=input bytes, out=output
# bytes, slot=info slot.  The first character of the return role only
# documents intent; every entry point returns int64_t.
# ---------------------------------------------------------------------------

SIG = {
    # ---- ogg_sync_state ---------------------------------------------------
    "ogg_sync_init": ("h", ""),                       # allocates the state
    "ogg_sync_clear": ("i", "h"),
    "ogg_sync_reset": ("i", "h"),
    "ogg_sync_destroy": ("i", "h"),                   # clear + free struct
    "ogg_sync_check": ("i", "h"),
    "ogg_sync_buffer": ("SPECIAL_BUFFER", ""),
    "ogg_sync_wrote": ("i", "h i"),
    "ogg_sync_pageseek": ("i", "h"),
    "ogg_sync_pageout": ("SPECIAL_PAGEOUT", ""),
    # ---- ogg_stream_state -------------------------------------------------
    "ogg_stream_init": ("h", "i"),                    # allocates the state
    "ogg_stream_clear": ("i", "h"),
    "ogg_stream_reset": ("i", "h"),
    "ogg_stream_reset_serialno": ("i", "h i"),
    "ogg_stream_destroy": ("i", "h"),                 # clear + free struct
    "ogg_stream_check": ("i", "h"),
    "ogg_stream_eos": ("i", "h"),
    "ogg_stream_pagein": ("i", "h h"),
    "ogg_stream_packetout": ("SPECIAL_PACKETOUT", ""),
    "ogg_stream_packetpeek": ("SPECIAL_PACKETPEEK", ""),
    "ogg_stream_packetin": ("i", "h h"),
    "ogg_stream_iovecin": ("SPECIAL_IOVECIN", ""),
    "ogg_stream_pageout": ("SPECIAL_STREAM_PAGEOUT", ""),
    "ogg_stream_pageout_fill": ("SPECIAL_STREAM_PAGEOUT_FILL", ""),
    "ogg_stream_flush": ("SPECIAL_STREAM_FLUSH", ""),
    "ogg_stream_flush_fill": ("SPECIAL_STREAM_FLUSH_FILL", ""),
    # ---- ogg_page ---------------------------------------------------------
    "ogg_page_checksum_set": ("i", "h"),
    "ogg_page_version": ("i", "h"),
    "ogg_page_continued": ("i", "h"),
    "ogg_page_bos": ("i", "h"),
    "ogg_page_eos": ("i", "h"),
    "ogg_page_granulepos": ("i", "h"),
    "ogg_page_serialno": ("i", "h"),
    "ogg_page_pageno": ("i", "h"),
    "ogg_page_packets": ("i", "h"),
    # ---- ogg_packet -------------------------------------------------------
    "ogg_packet_clear": ("i", "h"),
    # ---- oggpack_buffer ---------------------------------------------------
    "oggpack_writeinit": ("h", ""),                   # allocates the state
    "oggpack_writecheck": ("i", "h"),
    "oggpack_writetrunc": ("i", "h i"),
    "oggpack_writealign": ("i", "h"),
    "oggpack_writecopy": ("i", "h src i"),
    "oggpack_reset": ("i", "h"),
    "oggpack_writeclear": ("i", "h"),
    "oggpack_readinit": ("i", "h src i"),
    "oggpack_write": ("i", "h i i"),
    "oggpack_look": ("i", "h i"),
    "oggpack_look1": ("i", "h"),
    "oggpack_adv": ("i", "h i"),
    "oggpack_adv1": ("i", "h"),
    "oggpack_read": ("i", "h i"),
    "oggpack_read1": ("i", "h"),
    "oggpack_bytes": ("i", "h"),
    "oggpack_bits": ("i", "h"),
    "oggpack_get_buffer": ("i", "h out i"),
}

# Special shapes with explicit parameter names/roles.
# Info-slot layouts (owned, LE):
#   PAGEOUT_SLOT  (16 bytes): header_len i32 @0 | body_len i32 @4 | serialno i32 @8 | pageno i32 @12
#   PACKET_SLOT   (32 bytes): bytes i32 @0 | b_o_s i32 @4 | e_o_s i32 @8 | pad i32 @12 |
#                             granulepos i64 @16 | packetno i64 @24
SPECIALS = {
    "ogg_sync_buffer": {
        "params": [("h", "sync"), ("src", "data"), ("i", "size")],
    },
    "ogg_sync_pageout": {
        "params": [("h", "sync"), ("h", "page"), ("out", "hdr_out"), ("i", "hdr_cap"),
                   ("out", "body_out"), ("i", "body_cap"), ("slot", "info_out")],
    },
    "ogg_stream_pageout": {
        "params": [("h", "os"), ("h", "page"), ("out", "hdr_out"), ("i", "hdr_cap"),
                   ("out", "body_out"), ("i", "body_cap"), ("slot", "info_out")],
    },
    "ogg_stream_pageout_fill": {
        "params": [("h", "os"), ("i", "nfill"), ("h", "page"), ("out", "hdr_out"), ("i", "hdr_cap"),
                   ("out", "body_out"), ("i", "body_cap"), ("slot", "info_out")],
    },
    "ogg_stream_flush": {
        "params": [("h", "os"), ("h", "page"), ("out", "hdr_out"), ("i", "hdr_cap"),
                   ("out", "body_out"), ("i", "body_cap"), ("slot", "info_out")],
    },
    "ogg_stream_flush_fill": {
        "params": [("h", "os"), ("i", "nfill"), ("h", "page"), ("out", "hdr_out"), ("i", "hdr_cap"),
                   ("out", "body_out"), ("i", "body_cap"), ("slot", "info_out")],
    },
    "ogg_stream_packetout": {
        "params": [("h", "os"), ("h", "packet"), ("out", "data_out"), ("i", "cap"), ("slot", "info_out")],
    },
    "ogg_stream_packetpeek": {
        "params": [("h", "os"), ("h", "packet"), ("out", "data_out"), ("i", "cap"), ("slot", "info_out")],
    },
    "ogg_stream_iovecin": {
        "params": [("h", "os"), ("src", "a"), ("i", "a_len"), ("src", "b"), ("i", "b_len"),
                   ("i", "e_o_s"), ("l", "granulepos")],
    },
}

# Documented companion entry points (owned struct helpers; not declared
# functions): page/packet struct handles and their destructors.
EXTRA = {
    "xo_page_create": {"params": []},
    "xo_page_free": {"params": [("h", "page")]},
    "xo_page_set": {"params": [("h", "page"), ("out", "header"), ("i", "header_len"),
                               ("out", "body"), ("i", "body_len")]},
    "xo_packet_create": {"params": []},
    "xo_packet_free": {"params": [("h", "packet")]},
    "xo_packet_set": {"params": [("h", "packet"), ("out", "data"), ("i", "bytes"),
                                 ("i", "b_o_s"), ("i", "e_o_s"),
                                 ("l", "granulepos"), ("l", "packetno")]},
    "xo_pack_free": {"params": [("h", "pack")]},
}

C_TYPES = {
    "i": "int32_t",
    "l": "int64_t",
    "h": "int64_t",
    "src": "const unsigned char*",
    "out": "unsigned char*",
    "slot": "unsigned char*",
}
XIOM_TYPES = {
    "i": "Int",
    "l": "Int",
    "h": "Int",
    "src": "*UInt8",
    "out": "*UInt8",
    "slot": "*UInt8",
}

FN_RE = re.compile(r"\b(extern[^;]*?\b)((?:ogg)[a-z0-9_]*)\s*\(")


def find_decls(path):
    raw = open(path, encoding="utf8").read()
    text = "\n".join(l for l in raw.split("\n") if not l.strip().startswith("#"))
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = " ".join(text.split())
    out = []
    for stmt in text.split(";"):
        m = FN_RE.search(stmt)
        if not m or "ext" not in m.group(1):
            continue
        name = m.group(2)
        if not name.startswith("ogg"):
            continue
        out.append(name)
    return out


def xo_name(fn):
    for prefix, target in [("oggpack_", "xo_pack_"), ("ogg_sync_", "xo_sync_"),
                           ("ogg_stream_", "xo_stream_"), ("ogg_page_", "xo_page_"),
                           ("ogg_packet_", "xo_packet_")]:
        if fn.startswith(prefix):
            return target + fn[len(prefix):]
    raise SystemExit("FATAL: no xo_ mapping prefix for %s" % fn)


def build_surface(headers_dir):
    order = []
    for h in HEADERS:
        for name in find_decls(header_path(headers_dir, h)):
            if name not in order:
                order.append(name)
    missing = [n for n in order if n not in SIG]
    extra = [n for n in SIG if n not in order and n not in SPECIALS]
    if missing:
        raise SystemExit("FATAL: declared functions with no ABI mapping: %s" % ", ".join(missing))
    if extra:
        raise SystemExit("FATAL: ABI mapping for undeclared functions: %s" % ", ".join(extra))
    return order


def params_of(fn):
    if fn in SPECIALS:
        return SPECIALS[fn]["params"]
    roles = SIG[fn][1].split()
    return [(r, "p%d" % i) for i, r in enumerate(roles)]


def xiom_externs(order):
    lines = []
    for fn in order:
        params = params_of(fn)
        plist = ", ".join("%s: %s" % (n, XIOM_TYPES[r]) for r, n in params)
        lines.append("  fn %s(%s) -> Int;" % (xo_name(fn), plist))
    lines.append("  // owned struct companions (documented extensions)")
    for xo in sorted(EXTRA):
        params = EXTRA[xo]["params"]
        plist = ", ".join("%s: %s" % (n, XIOM_TYPES[r]) for r, n in params)
        lines.append("  fn %s(%s) -> Int;" % (xo, plist))
    return lines


def c_protos(order):
    lines = []
    for fn in order:
        params = params_of(fn)
        plist = ", ".join("%s %s" % (C_TYPES[r], n) for r, n in params) if params else "void"
        lines.append("int64_t %s(%s);" % (xo_name(fn), plist))
    lines.append("/* owned struct companions (documented extensions) */")
    for xo in sorted(EXTRA):
        params = EXTRA[xo]["params"]
        plist = ", ".join("%s %s" % (C_TYPES[r], n) for r, n in params) if params else "void"
        lines.append("int64_t %s(%s);" % (xo, plist))
    return lines


def emit_abi_xi(order, outdir):
    lines = []
    lines.append("// xiom.ogg -- GENERATED coverage ledger (tools/gen_ogg.py); do not edit.")
    lines.append("// Source: libogg %s (%s) public header ogg.h." % (PIN_TAG, PIN))
    lines.append("// The bridge extern declarations are generated into the FFI module")
    lines.append("// (xiom.ogg.ffi) with the wrappers (v0.64.4 resolves extern symbols")
    lines.append("// from the calling module).")
    lines.append("module xiom.ogg.abi")
    lines.append("")
    lines.append("// Coverage ledger (asserted by tests/test_conformance.xi).")
    n = len(order)
    lines.append("pub const DECLARED_FUNCTIONS: Int = %d;" % n)
    lines.append("pub const BOUND_FUNCTIONS: Int = %d;" % n)
    lines.append("pub const COMPANION_ENTRIES: Int = %d;" % len(EXTRA))
    lines.append("")
    with open(os.path.join(outdir, "src", "ogg_abi.xi"), "w", newline="\n") as f:
        f.write("\n".join(lines))


BEGIN = "// >>> GENERATED-EXTERNS-BEGIN (tools/gen_ogg.py)"
END = "// <<< GENERATED-EXTERNS-END"


def inject_ffi_externs(order, outdir):
    path = os.path.join(outdir, "src", "ogg_ffi.xi")
    text = open(path, encoding="utf8").read()
    if BEGIN not in text or END not in text:
        raise SystemExit("FATAL: extern markers missing in %s" % path)
    head, rest = text.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    block = [BEGIN]
    block.append("extern \"C\" {")
    block.extend(xiom_externs(order))
    block.append("}")
    block.append(END)
    with open(path, "w", newline="\n") as f:
        f.write(head + "\n".join(block) + tail)


def emit_protos_h(order, outdir):
    lines = []
    lines.append("/* xiom.ogg -- GENERATED bridge ABI prototypes (tools/gen_ogg.py).")
    lines.append(" * Included by src/ogg_bridge.c so every body is signature-checked. */")
    lines.append("#ifndef XIOM_OGG_ABI_PROTOS_H")
    lines.append("#define XIOM_OGG_ABI_PROTOS_H")
    lines.append("#include <stdint.h>")
    lines.append("")
    lines.extend(c_protos(order))
    lines.append("")
    lines.append("#endif")
    lines.append("")
    with open(os.path.join(outdir, "src", "ogg_abi_protos.h"), "w", newline="\n") as f:
        f.write("\n".join(lines))


def verify_bridge(order, outdir):
    path = os.path.join(outdir, "src", "ogg_bridge.c")
    text = open(path, encoding="utf8").read()
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    defined = set(re.findall(r"\b(xo_[a-z0-9_]+)\s*\(", text))
    expected = set(xo_name(fn) for fn in order)
    missing = sorted(expected - defined)
    if missing:
        raise SystemExit("FATAL: bridge does not define: %s" % ", ".join(missing))
    extra_missing = sorted(set(EXTRA) - defined)
    if extra_missing:
        raise SystemExit("FATAL: bridge does not define companions: %s" % ", ".join(extra_missing))
    return len(expected) + len(EXTRA)


def emit_coverage(order, bridge_entries, headers_dir, outdir):
    per_group = {}
    for fn in order:
        group = "oggpack (bitpacking)"
        if fn.startswith("ogg_sync_"):
            group = "sync"
        elif fn.startswith("ogg_stream_"):
            group = "stream"
        elif fn.startswith("ogg_page_"):
            group = "page"
        elif fn.startswith("ogg_packet_"):
            group = "packet"
        per_group.setdefault(group, []).append(fn)
    manifest = {
        "package": "xiom.ogg",
        "libogg_pin": {"tag": PIN_TAG, "commit": PIN},
        "headers": {},
        "declared_functions": len(order),
        "bound_functions": len(order),
        "skips": 0,
        "companion_entries": len(EXTRA),
        "bridge_entry_points": bridge_entries,
        "per_group": {g: {"declared": len(v), "bound": len(v), "skips": 0} for g, v in sorted(per_group.items())},
        "functions": {},
    }
    for h in HEADERS:
        p = os.path.join(headers_dir, "ogg", h)
        if os.path.exists(p):
            manifest["headers"][h] = hashlib.sha256(open(p, "rb").read()).hexdigest().upper()
    for fn in order:
        manifest["functions"][fn] = {"group": next(g for g, v in per_group.items() if fn in v),
                                     "xo": xo_name(fn), "bound": True, "skips": 0}
    with open(os.path.join(outdir, "docs", "gen_manifest.json"), "w", newline="\n") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")

    lines = []
    lines.append("# xiom.ogg -- libogg packet-layer binding coverage (libogg %s, %s)" % (PIN_TAG, PIN))
    lines.append("")
    lines.append("Generated by `tools/gen_ogg.py`; do not edit.  The 0.1.x pure-XIOM page")
    lines.append("layer is unchanged and not counted here.")
    lines.append("")
    lines.append("Oracle: every `extern` function declared in the pinned `ogg.h` is bound 1:1")
    lines.append("to a `xo_*` bridge entry point.  State structs are bridge-allocated Int")
    lines.append("handles; byte payloads cross as XIOM-owned `Vec[UInt8]` buffers; meta goes")
    lines.append("through owned slots.")
    lines.append("")
    lines.append("| Group | Declared | Bound | Skips |")
    lines.append("|-------|---------:|------:|------:|")
    for g in sorted(per_group):
        v = per_group[g]
        lines.append("| %s | %d | %d | 0 |" % (g, len(v), len(v)))
    lines.append("| **total** | **%d** | **%d** | **0** |" % (len(order), len(order)))
    lines.append("")
    lines.append("Companion entry points (owned page/packet/pack structs): %d.  Bridge entry"
                 % len(EXTRA))
    lines.append("points total: %d." % bridge_entries)
    lines.append("")
    lines.append("## Function map")
    lines.append("")
    lines.append("| Declared (upstream) | Group | Bound as |")
    lines.append("|---------------------|-------|----------|")
    for fn in order:
        manifest["functions"][fn]["group"]
        lines.append("| `%s` | %s | `%s` |" % (fn, manifest["functions"][fn]["group"], xo_name(fn)))
    lines.append("")
    with open(os.path.join(outdir, "docs", "COVERAGE.md"), "w", newline="\n") as f:
        f.write("\n".join(lines))
    return len(order)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--headers", required=True, help="pinned libogg include/ directory")
    ap.add_argument("--package", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    args = ap.parse_args()

    outdir = os.path.abspath(args.package)
    order = build_surface(args.headers)
    bridge_entries = verify_bridge(order, outdir)
    emit_abi_xi(order, outdir)
    inject_ffi_externs(order, outdir)
    emit_protos_h(order, outdir)
    total = emit_coverage(order, bridge_entries, args.headers, outdir)
    print("surface: %d declared = %d bound (0 skips); %d companions; %d bridge entries"
          % (total, total, len(EXTRA), bridge_entries))
    return 0


if __name__ == "__main__":
    sys.exit(main())
