#!/usr/bin/env python3
# ============================================================================
# XIOM -- xiom.phonon binding generator (upstream-first).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Oracle: the pinned public Steam Audio header `phonon.h` (v4.8.1, sha256
# CFAB67684FE1ED75A16BB9BCCB81C31276B6FB3BAD904073407DB900045229E7), read
# from the clone at E:\repos\steam-audio (verified identical at v4.8.1 and
# at the clone HEAD 480dd64, v4.8.1-10-g480dd64).
#
# The generator emits, from that single source of truth:
#   src/phonon_abi.xi      -- enum values + struct sizes/field offsets
#                             (C/Win64 layout, computed from the header)
#   src/phonon_exports.xi  -- the complete public export manifest: every
#                             IPLAPI function name in header order, the
#                             declared-group partition (the audio-processing
#                             surface this package binds), and the index
#                             constants used by the loader table.
#
# Usage:
#   python tools/gen_phonon.py [--header PATH] [--package-dir DIR]
#                              [--check] [--coverage] [--verify-dll PATH]
#
#   --check        re-generate in memory and fail when the committed output
#                  differs (drift guard; run in CI / on touch).
#   --coverage     print the declared-surface coverage table.
#   --verify-dll   parse a PE32+ export table and assert every function the
#                  header declares is exported by that DLL.
# ============================================================================

import argparse
import hashlib
import os
import re
import struct
import sys

PINNED_HEADER_SHA256 = "CFAB67684FE1ED75A16BB9BCCB81C31276B6FB3BAD904073407DB900045229E7"
DEFAULT_HEADER = r"E:\repos\steam-audio\core\src\core\phonon.h"

ABI_FILE = os.path.join("src", "phonon_abi.xi")
EXPORTS_FILE = os.path.join("src", "phonon_exports.xi")

# ---------------------------------------------------------------------------
# Declared surface: the audio-processing groups this package binds (100%).
# Everything else in the header is simulation-domain and recorded as
# out-of-scope (see docs/COVERAGE.md in the package).
# ---------------------------------------------------------------------------

DECLARED_GROUPS = [
    # (group id name, list of name predicates)
    ("context",              lambda n: n.startswith("iplContext")),
    ("hrtf",                 lambda n: n.startswith("iplHRTF")),
    ("audio_buffer",         lambda n: n.startswith("iplAudioBuffer")),
    ("binaural",             lambda n: n.startswith("iplBinauralEffect")),
    ("panning",              lambda n: n.startswith("iplPanningEffect")),
    ("virtual_surround",     lambda n: n.startswith("iplVirtualSurroundEffect")),
    ("ambisonics_encode",    lambda n: n.startswith("iplAmbisonicsEncodeEffect")),
    ("ambisonics_panning",   lambda n: n.startswith("iplAmbisonicsPanningEffect")),
    ("ambisonics_binaural",  lambda n: n.startswith("iplAmbisonicsBinauralEffect")),
    ("ambisonics_rotation",  lambda n: n.startswith("iplAmbisonicsRotationEffect")),
    ("ambisonics_decode",    lambda n: n.startswith("iplAmbisonicsDecodeEffect")),
    ("direct_effect",        lambda n: n.startswith("iplDirectEffect")),
    ("path_effect",          lambda n: n.startswith("iplPathEffect")),
    ("pathing_helpers",      lambda n: n in (
        "iplCalculateRelativeDirection",
        "iplDistanceAttenuationCalculate",
        "iplAirAbsorptionCalculate",
        "iplDirectivityCalculate",
    )),
]

# Functions that are resolved (symbol present in the table) but whose typed
# wrapper is deferred on compiler finding B-12 (fp returns through fn-pointer
# cast calls are miscompiled) / struct returns via sret. Recorded in SPEC.
DEFERRED_TYPED = {
    "iplCalculateRelativeDirection": "B-12/sret: struct return via cast-call not verifiable",
    "iplDistanceAttenuationCalculate": "B-12: fp return via cast-call miscompiled",
    "iplAirAbsorptionCalculate": "B-12: fp return via cast-call miscompiled",
    "iplDirectivityCalculate": "B-12: fp return via cast-call miscompiled",
}


# ---------------------------------------------------------------------------
# C parsing
# ---------------------------------------------------------------------------

def strip_comments(text):
    out = []
    i = 0
    n = len(text)
    while i < n:
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            out.append(" ")
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def parse_int_expr(expr, env):
    """Evaluate a C integer constant expression with enum-name lookup."""
    expr = expr.strip()

    def repl(m):
        token = m.group(0)
        if re.match(r"^(0[xX][0-9a-fA-F]+|\d+)$", token):
            return token
        if token in env:
            return "(%d)" % env[token]
        raise KeyError("unknown identifier in enum expression: %s" % token)

    token_re = r"0[xX][0-9a-fA-F]+|\d+|[A-Za-z_][A-Za-z0-9_]*"
    cleaned = re.sub(token_re, repl, expr)
    # C integer arithmetic subset used in this header.
    value = eval(cleaned, {"__builtins__": {}}, {})  # noqa: S307 (closed env)
    return int(value)


def parse_enums(text):
    """Returns (enum_members: OrderedDict name->value, enum_types: list of
    (type_name, [member names]))."""
    members = {}
    types = []
    for m in re.finditer(r"typedef\s+enum\s*\w*\s*\{(.*?)\}\s*(\w+)\s*;", text, re.S):
        body, type_name = m.group(1), m.group(2)
        names = []
        next_val = 0
        for item in body.split(","):
            item = item.strip()
            if not item:
                continue
            if "=" in item:
                name, expr = item.split("=", 1)
                name = name.strip()
                val = parse_int_expr(expr, members)
            else:
                name = item
                val = next_val
            members[name] = val
            names.append(name)
            next_val = val + 1
        types.append((type_name, names))
    return members, types


def parse_typedef_aliases(text):
    """typedef'd scalars/function pointers used inside structs."""
    aliases = {}
    # opaque handle macro: DECLARE_OPAQUE_HANDLE(IPLContext)
    for m in re.finditer(r"DECLARE_OPAQUE_HANDLE\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)", text):
        aliases[m.group(1)] = ("ptr", 8, 8)
    # opaque handle direct form: typedef struct _X_t* X;
    for m in re.finditer(r"typedef\s+struct\s+_[A-Za-z0-9_]+\s*\*\s*([A-Za-z_][A-Za-z0-9_]*)\s*;", text):
        aliases[m.group(1)] = ("ptr", 8, 8)
    # function pointers: typedef ret (CALL *Name)(args);
    for m in re.finditer(
            r"typedef\s+[A-Za-z_][A-Za-z0-9_]*\s*(?:\*\s*)?\(\s*[A-Za-z_]*\s*\*\s*"
            r"([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*\([^;]*\)\s*;", text):
        aliases[m.group(1)] = ("ptr", 8, 8)
    # plain aliases: typedef <type> <stars> Name;
    for m in re.finditer(
            r"typedef\s+(?!struct|enum|union)([A-Za-z_][A-Za-z0-9_]*)\s*(\**)\s*"
            r"([A-Za-z_][A-Za-z0-9_]*)\s*;", text):
        base, stars, name = m.group(1), m.group(2) or "", m.group(3)
        if base == name:
            continue
        aliases[name] = ("alias", base, len(stars) + 1 if stars else 0)
    return aliases


TYPE_SIZES = {
    "IPLint32": (4, 4),
    "int": (4, 4),
    "IPLuint32": (4, 4),
    "IPLuint8": (1, 1),
    "IPLfloat32": (4, 4),
    "float": (4, 4),
    "IPLsize": (8, 8),
    "size_t": (8, 8),
    "IPLbool": (4, 4),
    "char": (1, 1),
}


def parse_defines(text):
    """Simple integer #define macros (needed for array extents)."""
    env = {}
    for m in re.finditer(r"^#define\s+([A-Za-z_][A-Za-z0-9_]*)\s+(.+)$",
                         text, re.M):
        name, val = m.group(1), m.group(2).strip()
        if re.match(r"^[0-9xXa-fA-F\s()+\-<>&|*/]+$", val) and "(" not in val.split()[0]:
            try:
                env[name] = int(eval(val, {"__builtins__": {}}, {}))  # noqa: S307
            except Exception:
                pass
    return env


def parse_structs(text, defines=None):
    """Returns dict of struct name -> list of (field_name, field_type)."""
    defines = defines or {}
    structs = {}
    for m in re.finditer(r"typedef\s+struct\s*\{(.*?)\}\s*(\w+)\s*;", text, re.S):
        body, name = m.group(1), m.group(2)
        fields = []
        for decl in body.split(";"):
            decl = decl.strip()
            if not decl:
                continue
            # e.g. "IPLVector3 right", "float elements[4][4]",
            #      "const char* sofaFileName", "IPLfloat32* data"
            fm = re.match(
                r"^(const\s+)?(?P<type>[A-Za-z_][A-Za-z0-9_]*)\s*(?P<stars>\**)\s*(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?P<array>(\[[A-Za-z0-9_]+\])*)$",
                decl)
            if not fm:
                raise ValueError("unparsed struct field in %s: %r" % (name, decl))
            ftype = fm.group("type")
            stars = fm.group("stars") or ""
            fname = fm.group("name")
            raw_arrays = re.findall(r"\[([A-Za-z0-9_]+)\]", fm.group("array"))
            arrays = []
            for a in raw_arrays:
                if a.isdigit():
                    arrays.append(int(a))
                elif a in defines:
                    arrays.append(defines[a])
                else:
                    raise ValueError("unknown array extent %s in %s" % (a, name))
            fields.append((fname, ftype, len(stars), arrays))
        structs[name] = fields
    return structs


def parse_functions(text):
    """Returns list of dicts: name, ret, params [(type, stars, name, const)]."""
    funcs = []
    pat = re.compile(
        r"IPLAPI\s+(?P<ret>[A-Za-z_][A-Za-z0-9_]*)\s*(?P<retstars>\**)\s+IPLCALL\s+"
        r"(?P<name>ipl[A-Za-z0-9_]+)\s*\((?P<params>.*?)\)\s*;", re.S)
    for m in pat.finditer(text):
        params = []
        raw = m.group("params").strip()
        # split at top-level commas
        depth = 0
        cur = ""
        for ch in raw:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            if ch == "," and depth == 0:
                params.append(cur)
                cur = ""
            else:
                cur += ch
        if cur.strip():
            params.append(cur)
        plist = []
        for p in params:
            p = p.strip()
            if p == "void" or p == "":
                continue
            pm = re.match(
                r"^(const\s+)?(?P<type>[A-Za-z_][A-Za-z0-9_]*)\s*(?P<stars>\**)\s*(?P<name>[A-Za-z_][A-Za-z0-9_]*)?$",
                p)
            if not pm:
                raise ValueError("unparsed param in %s: %r" % (m.group("name"), p))
            plist.append({
                "type": pm.group("type"),
                "stars": pm.group("stars") or "",
                "name": pm.group("name") or "",
                "const": bool(pm.group(1)),
            })
        funcs.append({
            "name": m.group("name"),
            "ret": m.group("ret"),
            "retstars": m.group("retstars") or "",
            "params": plist,
        })
    return funcs


# ---------------------------------------------------------------------------
# Layout (Win64 C ABI)
# ---------------------------------------------------------------------------

def type_size_align(tname, stars, structs, enums, memo, aliases):
    if stars:
        return 8, 8
    if tname in TYPE_SIZES:
        return TYPE_SIZES[tname]
    if tname in enums:
        return 4, 4
    if tname in aliases:
        kind = aliases[tname]
        if kind[0] == "ptr":
            return 8, 8
        # alias -> base type with N pointer stars
        base, nstars = kind[1], kind[2]
        return type_size_align(base, "*" * nstars, structs, enums, memo, aliases)
    if tname in structs:
        total, align, _placed = layout_struct(tname, structs, enums, memo, aliases)
        return total, align
    raise ValueError("unknown type for layout: %s" % tname)


def layout_struct(name, structs, enums, memo, aliases):
    """Returns (size, align, [(field, offset, size, type, stars, arrays)])."""
    if name in memo:
        return memo[name]
    fields = structs[name]
    off = 0
    align = 1
    placed = []
    for (fname, ftype, fstars, arrays) in fields:
        sz, al = type_size_align(ftype, "*" * fstars, structs, enums, memo, aliases)
        for cnt in reversed(arrays):
            sz *= cnt
        if al > align:
            align = al
        off = (off + al - 1) // al * al
        placed.append((fname, off, sz, ftype, fstars, arrays))
        off += sz
    total = (off + align - 1) // align * align
    memo[name] = (total, align, placed)
    return total, align, placed


# ---------------------------------------------------------------------------
# Emitters
# ---------------------------------------------------------------------------

def camel_to_snake(name):
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name)
    s = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", "_", s)
    return s.upper()


def abi_prefix(struct_name):
    """Canonical `IPL_`-prefixed constant prefix for a struct.

    'IPLContextSettings' -> 'IPL_CONTEXT_SETTINGS'
    'IPLHRTFSettings'    -> 'IPL_HRTF_SETTINGS'
    """
    if struct_name.startswith("IPL"):
        return "IPL_" + camel_to_snake(struct_name[3:])
    return camel_to_snake(struct_name)


def emit_abi(header_sha, enums_members, enums_types, structs, wanted_structs,
             funcs, aliases):
    memo = {}
    enum_names = set(name for (name, _members) in enums_types)
    lines = []
    a = lines.append
    a("// XIOM -- xiom.phonon generated ABI constants.")
    a("// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors")
    a("// Licensed under the MIT or Apache-2.0 license, at your option.")
    a("//")
    a("// GENERATED by tools/gen_phonon.py -- do not edit by hand.")
    a("// Oracle: Steam Audio v4.8.1 phonon.h (sha256 %s)." % header_sha)
    a("// Layouts are Win64 C ABI: enum = 4, pointer = 8, float = 4.")
    a("")
    a("module xiom.phonon.abi")
    a("")
    a("/// The pinned oracle header this module was generated from.")
    a('pub const PHONON_HEADER_SHA256: Str = "%s";' % header_sha)
    a("")
    a("// =====================================================================")
    a("// Version and fixed-size constants (phonon.h / phonon_version.h)")
    a("// =====================================================================")
    a("")
    a("pub const STEAMAUDIO_VERSION_MAJOR: Int = 4;")
    a("pub const STEAMAUDIO_VERSION_MINOR: Int = 8;")
    a("pub const STEAMAUDIO_VERSION_PATCH: Int = 1;")
    a("pub const STEAMAUDIO_VERSION: Int = 0x040801;")
    a("pub const IPL_NUM_BANDS: Int = %d;" % enums_members.get("IPL_NUM_BANDS", 3))
    a("")
    a("// =====================================================================")
    a("// Enums (every value declared in phonon.h)")
    a("// =====================================================================")
    a("")
    for tname, names in enums_types:
        for n in names:
            a("pub const %s: Int = %d;" % (n, enums_members[n]))
        a("")
    a("pub const PHONON_ENUM_COUNT: Int = %d;" % len(enums_types))
    a("pub const PHONON_ENUM_MEMBER_COUNT: Int = %d;" % len(enums_members))
    a("")

    def emit_struct(st_name, prefix):
        size, _align, placed = layout_struct(st_name, structs, enum_names, memo, aliases)
        a("// ---- %s (%d bytes) ----" % (st_name, size))
        a("pub const %s_SIZE: Int = %d;" % (prefix, size))
        for (fname, foff, fsz, ftype, fstars, arrays) in placed:
            a("pub const %s_%s: Int = %d;" % (prefix, camel_to_snake(fname), foff))
            # flatten nested struct fields one level (e.g. speakerLayout.type)
            if ftype in wanted_structs and not fstars and not arrays:
                _nsz, _nal, nplaced = layout_struct(ftype, structs, enum_names, memo, aliases)
                for (nfname, nfoff, _, _, _, _) in nplaced:
                    a("pub const %s_%s_%s: Int = %d;" % (
                        prefix, camel_to_snake(fname), camel_to_snake(nfname),
                        foff + nfoff))
        a("")

    a("// =====================================================================")
    a("// Struct layouts for the declared surface (field byte offsets)")
    a("// =====================================================================")
    a("")
    for st in wanted_structs:
        emit_struct(st, abi_prefix(st))
    a("pub const PHONON_LAYOUT_STRUCT_COUNT: Int = %d;" % len(wanted_structs))
    a("")
    return "\n".join(lines)


def emit_exports(header_sha, funcs, groups):
    func_index = {}
    for i, f in enumerate(funcs):
        func_index[f["name"]] = i
    lines = []
    a = lines.append
    a("// XIOM -- xiom.phonon generated export manifest.")
    a("// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors")
    a("// Licensed under the MIT or Apache-2.0 license, at your option.")
    a("//")
    a("// GENERATED by tools/gen_phonon.py -- do not edit by hand.")
    a("// Oracle: Steam Audio v4.8.1 phonon.h (sha256 %s)." % header_sha)
    a("//")
    a("// The complete public export surface: every `IPLAPI` function the pinned")
    a("// header declares, in header order. The loader resolves all %d names;" % len(funcs))
    a("// the declared groups below are the audio-processing surface this")
    a("// package binds with typed wrappers.")
    a("")
    a("module xiom.phonon.exports")
    a("")
    a("pub const PHONON_PUBLIC_FN_COUNT: Int = %d;" % len(funcs))
    a("pub const PHONON_GROUP_COUNT: Int = %d;" % len(groups))
    a("")
    group_ids = {}
    for gid, (gname, _) in enumerate(groups):
        group_ids[gname] = gid
        a("pub const PHONON_GROUP_%s: Int = %d;" % (gname.upper(), gid))
    a("")
    declared = []
    for gid, (gname, pred) in enumerate(groups):
        names = [f["name"] for f in funcs if pred(f["name"])]
        declared.extend(names)
        for n in names:
            a("pub const PHONON_IDX_%s: Int = %d;" % (camel_to_snake(n), func_index[n]))
    a("pub const PHONON_DECLARED_FN_COUNT: Int = %d;" % len(declared))
    a("")
    a("/// Every public export name, in header order.")
    a("/// Complexity: O(n).")
    a("pub fn phonon_all_export_names() -> Vec[Str]")
    a("  requires: true")
    a("{")
    a("  var out: Vec[Str] = Vec[Str].new();")
    for f in funcs:
        a('  out.push("%s");' % f["name"])
    a("  return out;")
    a("}")
    a("")
    a("/// Group name for a group id.")
    a("/// Complexity: O(1).")
    a("pub fn phonon_group_name(g: Int) -> Str")
    a("  requires: g >= 0")
    a("  requires: g < PHONON_GROUP_COUNT")
    a("{")
    for gid, (gname, _) in enumerate(groups):
        if gid == 0:
            a('  if g == 0 { return "%s"; }' % gname)
        else:
            a('  if g == %d { return "%s"; }' % (gid, gname))
    a('  return "unknown";')
    a("}")
    a("")
    a("/// Export names of one declared group, in header order.")
    a("/// Complexity: O(n).")
    a("pub fn phonon_group_export_names(g: Int) -> Vec[Str]")
    a("  requires: g >= 0")
    a("  requires: g < PHONON_GROUP_COUNT")
    a("{")
    a("  var out: Vec[Str] = Vec[Str].new();")
    for gid, (gname, pred) in enumerate(groups):
        names = [f["name"] for f in funcs if pred(f["name"])]
        a("  if g == %d {" % gid)
        for n in names:
            a('    out.push("%s");' % n)
        a("  }")
    a("  return out;")
    a("}")
    a("")
    a("/// The declared (typed-wrapper) surface, in group then header order.")
    a("/// Complexity: O(n).")
    a("pub fn phonon_declared_export_names() -> Vec[Str]")
    a("  requires: true")
    a("{")
    a("  var out: Vec[Str] = Vec[Str].new();")
    for gid, (gname, pred) in enumerate(groups):
        names = [f["name"] for f in funcs if pred(f["name"])]
        for n in names:
            a('  out.push("%s");' % n)
    a("  return out;")
    a("}")
    a("")
    a("/// Per-group declared export counts, aligned with PHONON_GROUP_* ids.")
    a("/// Complexity: O(1).")
    a("pub fn phonon_group_export_count(g: Int) -> Int")
    a("  requires: g >= 0")
    a("  requires: g < PHONON_GROUP_COUNT")
    a("{")
    for gid, (gname, pred) in enumerate(groups):
        names = [f["name"] for f in funcs if pred(f["name"])]
        if gid == 0:
            a("  if g == 0 { return %d; }" % len(names))
        else:
            a("  if g == %d { return %d; }" % (gid, len(names)))
    a("  return 0;")
    a("}")
    a("")
    a("/// Indexes (into the header-order table) of one group's exports.")
    a("/// Complexity: O(n).")
    a("pub fn phonon_group_export_indexes(g: Int) -> Vec[Int]")
    a("  requires: g >= 0")
    a("  requires: g < PHONON_GROUP_COUNT")
    a("{")
    a("  var out: Vec[Int] = Vec[Int].new();")
    for gid, (gname, pred) in enumerate(groups):
        idxs = [i for i, f in enumerate(funcs) if pred(f["name"])]
        a("  if g == %d {" % gid)
        for i in idxs:
            a("    out.push(%d);" % i)
        a("  }")
    a("  return out;")
    a("}")
    a("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# PE32+ export table (minimal, read-only; used by --verify-dll)
# ---------------------------------------------------------------------------

def pe_exports(path):
    data = open(path, "rb").read()
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    if data[e_lfanew:e_lfanew + 4] != b"PE\0\0":
        raise ValueError("not a PE file: %s" % path)
    coff = e_lfanew + 4
    machine, nsec, _ts, _sym, _nsym, optsz, _chars = struct.unpack_from(
        "<HHIIIHH", data, coff)
    opt = coff + 20
    magic = struct.unpack_from("<H", data, opt)[0]
    if magic != 0x20B:
        raise ValueError("not PE32+: %s" % path)
    ddoff = opt + 112
    export_rva = struct.unpack_from("<I", data, ddoff)[0]
    sec = opt + optsz
    secs = []
    for i in range(nsec):
        off = sec + i * 40
        name = data[off:off + 8].rstrip(b"\0").decode("ascii", "replace")
        vsize, vaddr, rawsz, rawptr = struct.unpack_from("<IIII", data, off + 8)
        secs.append((name, vaddr, vsize, rawptr, rawsz))

    def rva2off(rva):
        for (_n, vaddr, vsize, rawptr, rawsz) in secs:
            if vaddr <= rva < vaddr + max(vsize, rawsz):
                return rawptr + (rva - vaddr)
        return None

    eo = rva2off(export_rva)
    if eo is None:
        raise ValueError("no export directory")
    # IMAGE_EXPORT_DIRECTORY: NumberOfFunctions @20, NumberOfNames @24,
    # AddressOfNames @32, AddressOfNameOrdinals @36.
    _nfun, nnames = struct.unpack_from("<II", data, eo + 20)
    anames = struct.unpack_from("<I", data, eo + 32)[0]
    names = []
    for i in range(nnames):
        nrva = struct.unpack_from("<I", data, rva2off(anames) + i * 4)[0]
        o = rva2off(nrva)
        end = data.index(b"\0", o)
        names.append(data[o:end].decode("ascii", "replace"))
    return names


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--header", default=DEFAULT_HEADER)
    ap.add_argument("--package-dir", default=".")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--coverage", action="store_true")
    ap.add_argument("--verify-dll", default="")
    ap.add_argument("--allow-hash-drift", action="store_true")
    args = ap.parse_args()

    raw = open(args.header, "rb").read()
    header_sha = hashlib.sha256(raw).hexdigest().upper()
    if header_sha != PINNED_HEADER_SHA256 and not args.allow_hash_drift:
        sys.stderr.write(
            "ERROR: header hash drift:\n  got      %s\n  pinned   %s\n"
            "Re-pin deliberately (SPEC.md) before regenerating.\n"
            % (header_sha, PINNED_HEADER_SHA256))
        return 2

    text = strip_comments(raw.decode("utf-8", "replace"))
    defines = parse_defines(text)
    enums_members, enums_types = parse_enums(text)
    structs = parse_structs(text, defines)
    aliases = parse_typedef_aliases(text)
    funcs = parse_functions(text)

    groups = DECLARED_GROUPS

    # Which structs does the declared surface touch (by pointer/slot use)?
    wanted = []
    for f in funcs:
        if not any(pred(f["name"]) for (_g, pred) in groups):
            continue
        for p in f["params"]:
            t = p["type"]
            if t in structs and t not in wanted:
                wanted.append(t)
    # recurse into nested struct fields
    i = 0
    while i < len(wanted):
        for (fname, ftype, fstars, arrays) in structs[wanted[i]]:
            if ftype in structs and ftype not in wanted:
                wanted.append(ftype)
        i += 1

    abi_src = emit_abi(header_sha, enums_members, enums_types, structs, wanted, funcs, aliases)
    exports_src = emit_exports(header_sha, funcs, groups)

    if args.check:
        ok = True
        for rel, src in ((ABI_FILE, abi_src), (EXPORTS_FILE, exports_src)):
            path = os.path.join(args.package_dir, rel)
            if not os.path.exists(path):
                sys.stderr.write("MISSING generated file: %s\n" % path)
                ok = False
                continue
            cur = open(path, "r", encoding="utf-8").read()
            if cur != src:
                sys.stderr.write("DRIFT: %s differs from generator output\n" % path)
                ok = False
        print("gen_phonon --check: %s" % ("clean" if ok else "DRIFT"))
        return 0 if ok else 1

    written = []
    for rel, src in ((ABI_FILE, abi_src), (EXPORTS_FILE, exports_src)):
        path = os.path.join(args.package_dir, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(src)
        written.append(path)

    if args.verify_dll:
        exp = set(pe_exports(args.verify_dll))
        declared = set(f["name"] for f in funcs)
        missing = sorted(declared - exp)
        print("verify-dll: %d exports; %d/%d header-declared present"
              % (len(exp), len(declared) - len(missing), len(declared)))
        if missing:
            print("MISSING FROM DLL:")
            for n in missing:
                print("  " + n)
            return 1
        extra = sorted(n for n in exp if n not in declared and n.startswith("ipl"))
        print("verify-dll: %d additional ipl* exports not in the public header"
              % len(extra))

    if args.coverage:
        print("declared-surface coverage (oracle: phonon.h %s)" % header_sha[:12])
        total = 0
        for gid, (gname, pred) in enumerate(groups):
            names = [f["name"] for f in funcs if pred(f["name"])]
            deferred = [n for n in names if n in DEFERRED_TYPED]
            total += len(names)
            print("  %-22s %3d declared, %3d typed, %d deferred"
                  % (gname, len(names), len(names) - len(deferred), len(deferred)))
        print("  %-22s %3d" % ("TOTAL DECLARED", total))
        print("  %-22s %3d" % ("TOTAL PUBLIC HEADER", len(funcs)))
        print("  %-22s %3d" % ("OUT OF SCOPE (simulation)", len(funcs) - total))

    print("gen_phonon: wrote %s" % ", ".join(os.path.basename(p) for p in written))
    return 0


if __name__ == "__main__":
    sys.exit(main())
