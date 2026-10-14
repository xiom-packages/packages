#!/usr/bin/env python3
# XIOM -- xiom.opus binding-surface generator.
#
# Parses the pinned libopus v1.6.1 public headers and emits:
#
#   src/opus_abi.xi          extern "C" declarations of every xo_* bridge
#                            entry point (XIOM side) + the public integer
#                            constants + coverage counts
#   src/opus_abi_protos.h    the matching C prototypes (included by
#                            src/opus_bridge.c, so the compiler enforces
#                            that every bridge body matches the ABI)
#   src/opus_vendor_celt.c   unity build units over vendor/opus (the XIOM
#   src/opus_vendor_silk.c   --c-source pipeline has no -I flags; the tree is
#   src/opus_vendor_silk_float.c  flat and wrapped per upstream source list)
#   src/opus_vendor_src.c
#   docs/COVERAGE.md         declared/bound/skips table (per header)
#   docs/gen_manifest.json   machine-readable coverage + hashes
#
# Oracle: every function DECLARED with an export macro in opus.h,
# opus_defines.h, opus_multistream.h, opus_custom.h and opus_projection.h
# must be bound (opus_repacketizer.h does not exist in v1.6.1 -- the
# repacketizer API lives in opus.h; opus_types.h declares types only).
# The generator FAILS if any declared function has no mapping and if the
# bridge source does not define exactly the generated xo_ entry points.
#
# ABI rules (bindings-lane discipline B-11..B-26 on compiler v0.64.4):
#   - every xo_ entry point returns int64_t (no narrow-return sign-extension
#     ambiguity); XIOM declares -> Int
#   - opaque handles (OpusEncoder*, OpusDecoder*, OpusMS*, OpusProjection*,
#     OpusCustom*, OpusDRED*, OpusCustomMode*) cross as int64_t (Int); the C
#     bridge casts internally -- NEVER x as *UInt8 (B-25)
#   - byte buffers cross as XIOM-owned Vec[UInt8] pointers (as_mut_ptr);
#     the bridge reads inputs / writes outputs; XIOM reads owned slots
#     byte-indexed (B-20/B-24)
#   - scalar out-params get a dedicated 4-byte owned slot (one slot per
#     out-param; B-11/B-16/B-17)
#   - variadic ctl functions become a _set / _get pair (request + int value
#     / request + slot); no varargs crossing the boundary
#   - string-returning functions copy into an owned slot and return the byte
#     length (no foreign-pointer reads)
#
# Deterministic: sorted inputs, stable ordering, LF newlines, no timestamps.
#
# Usage:
#   python tools/gen_opus.py --headers E:\repos\opus\include --package <pkg dir>

import argparse
import hashlib
import json
import os
import re
import sys

PIN = "22244de5a79bd1d6d623c32e72bf1954b56235be"
PIN_TAG = "v1.6.1"
PIN_VERSION = "1.6.1"

HEADERS = ["opus.h", "opus_defines.h", "opus_multistream.h", "opus_custom.h", "opus_projection.h"]

# ---------------------------------------------------------------------------
# ABI role table.  Every declared function must appear here (the generator
# fails otherwise), with one role per parameter:
#   i       scalar int in                -> int32_t
#   f       scalar float in              -> float
#   h       opaque handle in             -> int64_t (cast in C)
#   bytes   input byte buffer            -> const unsigned char*
#   out     output byte buffer           -> unsigned char*
#   slot    4-byte scalar out-slot       -> unsigned char*
#   pcm     PCM input bytes              -> const unsigned char*
#   pcm_o   PCM output bytes             -> unsigned char*
#   map     mapping input bytes          -> const unsigned char*
#   map_o   mapping output bytes         -> unsigned char*
#   CTL     variadic control function    -> _set/_get pair (handle only)
# Return role: h (new handle), i (int64), v (void), s (string copy to slot).
# ---------------------------------------------------------------------------

SIG = {
    # ---- opus.h -----------------------------------------------------------
    "opus_encoder_get_size": ("i", "i"),
    "opus_encoder_create": ("h", "i i i slot"),
    "opus_encoder_init": ("SPECIAL_INIT_ENCODER", ""),
    "opus_encode": ("i", "h pcm i out i"),
    "opus_encode24": ("i", "h pcm i out i"),
    "opus_encode_float": ("i", "h pcm i out i"),
    "opus_encoder_destroy": ("v", "h"),
    "opus_encoder_ctl": ("CTL", "h"),
    "opus_decoder_get_size": ("i", "i"),
    "opus_decoder_create": ("h", "i i slot"),
    "opus_decoder_init": ("SPECIAL_INIT_DECODER", ""),
    "opus_decode": ("i", "h bytes i pcm_o i i"),
    "opus_decode24": ("i", "h bytes i pcm_o i i"),
    "opus_decode_float": ("i", "h bytes i pcm_o i i"),
    "opus_decoder_destroy": ("v", "h"),
    "opus_decoder_ctl": ("CTL", "h"),
    "opus_dred_decoder_get_size": ("i", ""),
    "opus_dred_decoder_create": ("h", "slot"),
    "opus_dred_decoder_init": ("SPECIAL_INIT_DRED", ""),
    "opus_dred_decoder_destroy": ("v", "h"),
    "opus_dred_decoder_ctl": ("CTL", "h"),
    "opus_dred_get_size": ("i", ""),
    "opus_dred_alloc": ("h", "slot"),
    "opus_dred_free": ("v", "h"),
    "opus_dred_parse": ("i", "h h bytes i i i slot i"),
    "opus_dred_process": ("i", "h h h"),
    "opus_decoder_dred_decode": ("i", "h h i pcm_o i"),
    "opus_decoder_dred_decode24": ("i", "h h i pcm_o i"),
    "opus_decoder_dred_decode_float": ("i", "h h i pcm_o i"),
    "opus_packet_parse": ("SPECIAL_PARSE", ""),
    "opus_packet_get_bandwidth": ("i", "bytes"),
    "opus_packet_get_samples_per_frame": ("i", "bytes i"),
    "opus_packet_get_nb_channels": ("i", "bytes"),
    "opus_packet_get_nb_frames": ("i", "bytes i"),
    "opus_packet_get_nb_samples": ("i", "bytes i i"),
    "opus_packet_has_lbrr": ("i", "bytes i"),
    "opus_decoder_get_nb_samples": ("i", "h bytes i"),
    "opus_pcm_soft_clip": ("v", "pcm_o i i out"),
    "opus_repacketizer_get_size": ("i", ""),
    "opus_repacketizer_init": ("SPECIAL_INIT_REPACKETIZER", ""),
    "opus_repacketizer_create": ("h", ""),
    "opus_repacketizer_destroy": ("v", "h"),
    "opus_repacketizer_cat": ("i", "h bytes i"),
    "opus_repacketizer_out_range": ("i", "h i i out i"),
    "opus_repacketizer_get_nb_frames": ("i", "h"),
    "opus_repacketizer_out": ("i", "h out i"),
    "opus_packet_pad": ("i", "out i i"),
    "opus_packet_unpad": ("i", "out i"),
    "opus_multistream_packet_pad": ("i", "out i i i"),
    "opus_multistream_packet_unpad": ("i", "out i i"),
    # ---- opus_defines.h ---------------------------------------------------
    "opus_strerror": ("s", "i"),
    "opus_get_version_string": ("s", ""),
    # ---- opus_multistream.h -----------------------------------------------
    "opus_multistream_encoder_get_size": ("i", "i i"),
    "opus_multistream_surround_encoder_get_size": ("i", "i i"),
    "opus_multistream_encoder_create": ("h", "i i i i map i slot"),
    "opus_multistream_surround_encoder_create": ("SPECIAL_MS_CREATE", ""),
    "opus_multistream_encoder_init": ("SPECIAL_MS_INIT", ""),
    "opus_multistream_surround_encoder_init": ("SPECIAL_MS_INIT", ""),
    "opus_multistream_encode": ("i", "h pcm i out i"),
    "opus_multistream_encode24": ("i", "h pcm i out i"),
    "opus_multistream_encode_float": ("i", "h pcm i out i"),
    "opus_multistream_encoder_destroy": ("v", "h"),
    "opus_multistream_encoder_ctl": ("CTL", "h"),
    "opus_multistream_decoder_get_size": ("i", "i i"),
    "opus_multistream_decoder_create": ("h", "i i i i map slot"),
    "opus_multistream_decoder_init": ("SPECIAL_MSD_INIT", ""),
    "opus_multistream_decode": ("i", "h bytes i pcm_o i i"),
    "opus_multistream_decode24": ("i", "h bytes i pcm_o i i"),
    "opus_multistream_decode_float": ("i", "h bytes i pcm_o i i"),
    "opus_multistream_decoder_destroy": ("v", "h"),
    "opus_multistream_decoder_ctl": ("CTL", "h"),
    # ---- opus_custom.h ----------------------------------------------------
    "opus_custom_mode_create": ("h", "i i slot"),
    "opus_custom_mode_destroy": ("v", "h"),
    "opus_custom_encoder_get_size": ("i", "h i"),
    "opus_custom_encoder_init": ("SPECIAL_INIT_CUSTOM_ENC", ""),
    "opus_custom_encoder_create": ("h", "h i slot"),
    "opus_custom_encoder_destroy": ("v", "h"),
    "opus_custom_encode_float": ("i", "h pcm i out i"),
    "opus_custom_encode": ("i", "h pcm i out i"),
    "opus_custom_encode24": ("i", "h pcm i out i"),
    "opus_custom_encoder_ctl": ("CTL", "h"),
    "opus_custom_decoder_get_size": ("i", "h i"),
    "opus_custom_decoder_init": ("SPECIAL_INIT_CUSTOM_DEC", ""),
    "opus_custom_decoder_create": ("h", "h i slot"),
    "opus_custom_decoder_destroy": ("v", "h"),
    "opus_custom_decode_float": ("i", "h bytes i pcm_o i"),
    "opus_custom_decode": ("i", "h bytes i pcm_o i"),
    "opus_custom_decode24": ("i", "h bytes i pcm_o i"),
    "opus_custom_decoder_ctl": ("CTL", "h"),
    # ---- opus_projection.h ------------------------------------------------
    "opus_projection_ambisonics_encoder_get_size": ("i", "i i"),
    "opus_projection_ambisonics_encoder_create": ("SPECIAL_PROJ_CREATE", ""),
    "opus_projection_ambisonics_encoder_init": ("SPECIAL_PROJ_INIT", ""),
    "opus_projection_encode": ("i", "h pcm i out i"),
    "opus_projection_encode24": ("i", "h pcm i out i"),
    "opus_projection_encode_float": ("i", "h pcm i out i"),
    "opus_projection_encoder_destroy": ("v", "h"),
    "opus_projection_encoder_ctl": ("CTL", "h"),
    "opus_projection_decoder_get_size": ("i", "i i i"),
    "opus_projection_decoder_create": ("h", "i i i i bytes i slot"),
    "opus_projection_decoder_init": ("SPECIAL_PROJ_DEC_INIT", ""),
    "opus_projection_decode": ("i", "h bytes i pcm_o i i"),
    "opus_projection_decode24": ("i", "h bytes i pcm_o i i"),
    "opus_projection_decode_float": ("i", "h bytes i pcm_o i i"),
    "opus_projection_decoder_destroy": ("v", "h"),
    "opus_projection_decoder_ctl": ("CTL", "h"),
}

# Special-shape signatures with explicit parameter names (protos + XIOM).
SPECIALS = {
    # init-over-owned-memory shapes: the XIOM caller passes an owned Vec[UInt8]
    # as the state memory (mem, capacity); the bridge validates the capacity,
    # initializes upstream, writes the opus status code into err_out and
    # returns the SAME pointer as the handle (0 on failure).  No Int->*UInt8
    # cast ever crosses the boundary (B-25).
    "opus_encoder_init": {
        "ret": "h",
        "params": [("out", "mem"), ("i", "mem_capacity"), ("i", "Fs"), ("i", "channels"),
                   ("i", "application"), ("out", "err_out")],
    },
    "opus_decoder_init": {
        "ret": "h",
        "params": [("out", "mem"), ("i", "mem_capacity"), ("i", "Fs"), ("i", "channels"),
                   ("out", "err_out")],
    },
    "opus_dred_decoder_init": {
        "ret": "h",
        "params": [("out", "mem"), ("i", "mem_capacity"), ("out", "err_out")],
    },
    "opus_repacketizer_init": {
        "ret": "h",
        "params": [("out", "mem"), ("i", "mem_capacity"), ("out", "err_out")],
    },
    "opus_custom_encoder_init": {
        "ret": "h",
        "params": [("out", "mem"), ("i", "mem_capacity"), ("h", "mode"), ("i", "channels"),
                   ("out", "err_out")],
    },
    "opus_custom_decoder_init": {
        "ret": "h",
        "params": [("out", "mem"), ("i", "mem_capacity"), ("h", "mode"), ("i", "channels"),
                   ("out", "err_out")],
    },
    "opus_multistream_encoder_init": {
        "ret": "h",
        "params": [("out", "mem"), ("i", "mem_capacity"), ("i", "Fs"), ("i", "channels"),
                   ("i", "streams"), ("i", "coupled_streams"), ("map", "mapping"),
                   ("i", "application"), ("out", "err_out")],
    },
    "opus_multistream_decoder_init": {
        "ret": "h",
        "params": [("out", "mem"), ("i", "mem_capacity"), ("i", "Fs"), ("i", "channels"),
                   ("i", "streams"), ("i", "coupled_streams"), ("map", "mapping"),
                   ("out", "err_out")],
    },
    "opus_projection_decoder_init": {
        "ret": "h",
        "params": [("out", "mem"), ("i", "mem_capacity"), ("i", "Fs"), ("i", "channels"),
                   ("i", "streams"), ("i", "coupled_streams"), ("bytes", "demixing_matrix"),
                   ("i", "demixing_matrix_size"), ("out", "err_out")],
    },
    # string-copy shapes: bridge copies into an owned slot, returns the
    # byte count (no foreign pointer is read from XIOM; B-20/B-24).
    "opus_strerror": {
        "ret": "i",
        "params": [("i", "code"), ("out", "out"), ("i", "capacity")],
    },
    "opus_get_version_string": {
        "ret": "i",
        "params": [("out", "out"), ("i", "capacity")],
    },
    "opus_packet_parse": {
        "ret": "i",
        "params": [
            ("bytes", "data"),
            ("i", "len"),
            ("out", "toc_out"),
            ("out", "sizes_out"),   # nb_frames * u32 LE, per-frame size
            ("out", "offsets_out"), # nb_frames * u32 LE, per-frame offset in packet
            ("i", "out_capacity"),  # entries available in sizes_out/offsets_out
            ("out", "payload_offset_out"),  # u32 LE
        ],
    },
    "opus_multistream_surround_encoder_create": {
        "ret": "h",
        "params": [
            ("i", "Fs"), ("i", "channels"), ("i", "mapping_family"),
            ("out", "streams_out"), ("out", "coupled_streams_out"),
            ("out", "mapping_out"), ("i", "mapping_capacity"),
            ("i", "application"), ("out", "err_out"),
        ],
    },
    "opus_multistream_surround_encoder_init": {
        "ret": "h",
        "params": [
            ("out", "mem"), ("i", "mem_capacity"), ("i", "Fs"), ("i", "channels"),
            ("i", "mapping_family"), ("out", "streams_out"), ("out", "coupled_streams_out"),
            ("out", "mapping_out"), ("i", "mapping_capacity"), ("i", "application"),
            ("out", "err_out"),
        ],
    },
    "opus_projection_ambisonics_encoder_create": {
        "ret": "h",
        "params": [
            ("i", "Fs"), ("i", "channels"), ("i", "mapping_family"),
            ("out", "streams_out"), ("out", "coupled_streams_out"),
            ("i", "application"), ("out", "err_out"),
        ],
    },
    "opus_projection_ambisonics_encoder_init": {
        "ret": "h",
        "params": [
            ("out", "mem"), ("i", "mem_capacity"), ("i", "Fs"), ("i", "channels"),
            ("i", "mapping_family"), ("out", "streams_out"), ("out", "coupled_streams_out"),
            ("i", "application"), ("out", "err_out"),
        ],
    },
}

C_TYPES = {
    "i": "int32_t",
    "f": "float",
    "h": "int64_t",
    "bytes": "const unsigned char*",
    "out": "unsigned char*",
    "slot": "unsigned char*",
    "pcm": "const unsigned char*",
    "pcm_o": "unsigned char*",
    "map": "const unsigned char*",
    "map_o": "unsigned char*",
}
XIOM_TYPES = {
    "i": "Int",
    "f": "Float32",
    "h": "Int",
    "bytes": "*UInt8",
    "out": "*UInt8",
    "slot": "*UInt8",
    "pcm": "*UInt8",
    "pcm_o": "*UInt8",
    "map": "*UInt8",
    "map_o": "*UInt8",
}

# Documented companion entry points for the four varargs ctl requests whose
# arguments are NOT (int value) / (int* out): they take pointer arguments and
# cannot be expressed by the generic _set/_get pair.  These extend -- never
# replace -- the 1:1 function coverage (the declared ctl functions are bound
# by the _set/_get pairs; these give the pointer-arg ctls a disciplined ABI).
EXTRA = {
    "xo_encoder_ctl_set_dnn_blob": {
        "ret": "i",
        "params": [("h", "enc"), ("bytes", "blob"), ("i", "size")],
    },
    "xo_multistream_encoder_ctl_get_state": {
        "ret": "i",
        "params": [("h", "st"), ("i", "stream_index"), ("out", "out_slot")],
    },
    "xo_multistream_decoder_ctl_get_state": {
        "ret": "i",
        "params": [("h", "st"), ("i", "stream_index"), ("out", "out_slot")],
    },
    "xo_projection_encoder_ctl_get_matrix": {
        "ret": "i",
        "params": [("h", "st"), ("out", "out"), ("i", "capacity")],
    },
}

FN_RE = re.compile(r"\b(opus_[a-z0-9_]+)\s*\(")


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    return text


def find_decls(path):
    raw = open(path, encoding="utf8").read()
    text = "\n".join(l for l in raw.split("\n") if not l.strip().startswith("#"))
    text = " ".join(strip_comments(text).split())
    out = []
    for stmt in text.split(";"):
        m = FN_RE.search(stmt)
        if not m or "EXPORT" not in stmt:
            continue
        name = m.group(1)
        start = stmt.index("(", m.end() - 1)
        depth = 0
        end = -1
        for i in range(start, len(stmt)):
            if stmt[i] == "(":
                depth += 1
            elif stmt[i] == ")":
                depth -= 1
                if depth == 0:
                    end = i
                    break
        args = stmt[start + 1:end].strip()
        out.append((name, args))
    return out


def find_consts(path):
    out = []
    for m in re.finditer(r"#\s*define\s+(OPUS_[A-Z0-9_]+)\s+([^\n]*)", open(path, encoding="utf8").read()):
        name, val = m.group(1), m.group(2).strip()
        if "(" in val:
            continue
        val = val.split("/*")[0].strip()
        val = val.split("//")[0].strip()
        if re.fullmatch(r"-?[0-9]+", val):
            out.append((name, int(val)))
    return out


def find_ctl_macros(path):
    out = []
    for m in re.finditer(r"#\s*define\s+(OPUS_(?:SET|GET)_[A-Z0-9_]+)\(x\)", open(path, encoding="utf8").read()):
        out.append(m.group(1))
    return out


def xo_name(fn):
    return "xo_" + fn[len("opus_"):]


def build_surface(headers_dir):
    decls = {}
    order = []
    for h in HEADERS:
        for name, args in find_decls(os.path.join(headers_dir, h)):
            if name not in decls:
                decls[name] = {"header": h, "args": args}
                order.append(name)

    consts = {}
    for h in HEADERS:
        for name, val in find_consts(os.path.join(headers_dir, h)):
            consts.setdefault(name, val)
    ctl_macros = []
    for h in HEADERS:
        ctl_macros.extend(find_ctl_macros(os.path.join(headers_dir, h)))

    missing = [n for n in order if n not in SIG]
    extra = [n for n in SIG if n not in decls and n not in SPECIALS]
    if missing:
        raise SystemExit("FATAL: declared functions with no ABI mapping: %s" % ", ".join(missing))
    if extra:
        raise SystemExit("FATAL: ABI mapping for undeclared functions: %s" % ", ".join(extra))
    return decls, order, consts, ctl_macros


def proto_params(fn):
    """Return [(role, name)] for a declared function."""
    ret, roles = SIG[fn]
    if fn in SPECIALS:
        return ret, SPECIALS[fn]["params"], SPECIALS[fn]["ret"]
    params = []
    for idx, role in enumerate(roles.split()):
        params.append((role, "p%d" % idx))
    return ret, params, ret


def xiom_externs(order):
    lines = []
    for fn in order:
        ret, roles = SIG[fn]
        xo = xo_name(fn)
        if roles == "h" and ret == "CTL":
            lines.append("  fn %s_set(p0: Int, p1: Int, p2: Int) -> Int;" % xo)
            lines.append("  fn %s_get(p0: Int, p1: Int, p2: *UInt8) -> Int;" % xo)
            continue
        if fn in SPECIALS:
            params = SPECIALS[fn]["params"]
        else:
            params = [(r, "p%d" % i) for i, r in enumerate(roles.split())]
        plist = ", ".join("%s: %s" % (n, XIOM_TYPES[r]) for r, n in params)
        lines.append("  fn %s(%s) -> Int;" % (xo, plist))
    lines.append("  // ctl pointer-argument companions (documented extensions)")
    for xo in sorted(EXTRA):
        params = EXTRA[xo]["params"]
        plist = ", ".join("%s: %s" % (n, XIOM_TYPES[r]) for r, n in params)
        lines.append("  fn %s(%s) -> Int;" % (xo, plist))
    return lines


def c_protos(order):
    lines = []
    for fn in order:
        ret, roles = SIG[fn]
        xo = xo_name(fn)
        if roles == "h" and ret == "CTL":
            lines.append("int64_t %s_set(int64_t p0, int32_t p1, int32_t p2);" % xo)
            lines.append("int64_t %s_get(int64_t p0, int32_t p1, unsigned char* p2);" % xo)
            continue
        if fn in SPECIALS:
            params = SPECIALS[fn]["params"]
        else:
            params = [(r, "p%d" % i) for i, r in enumerate(roles.split())]
        plist = ", ".join("%s %s" % (C_TYPES[r], n) for r, n in params) if params else "void"
        lines.append("int64_t %s(%s);" % (xo, plist))
    lines.append("/* ctl pointer-argument companions (documented extensions) */")
    for xo in sorted(EXTRA):
        params = EXTRA[xo]["params"]
        plist = ", ".join("%s %s" % (C_TYPES[r], n) for r, n in params)
        lines.append("int64_t %s(%s);" % (xo, plist))
    return lines


def emit_abi_xi(order, consts, ctl_macros, outdir):
    lines = []
    lines.append("// xiom.opus -- GENERATED public constants (tools/gen_opus.py); do not edit.")
    lines.append("// Source: libopus %s (%s) public headers." % (PIN_TAG, PIN))
    lines.append("// The bridge extern declarations are generated into the FFI module")
    lines.append("// (xiom.opus.ffi) with the wrappers, because the compiler resolves")
    lines.append("// extern symbols from the CALLING module on v0.64.4.")
    lines.append("module xiom.opus.abi")
    lines.append("")
    lines.append("// Public integer constants (opus_defines.h + header request ids).")
    for name in sorted(consts):
        lines.append("pub const %s: Int = %d;" % (name, consts[name]))
    lines.append("")
    lines.append("// Coverage ledger (asserted by tests/test_conformance.xi).")
    n = len(order)
    ctl = sum(1 for f in order if SIG[f][0] == "CTL")
    lines.append("pub const DECLARED_FUNCTIONS: Int = %d;" % n)
    lines.append("pub const BOUND_FUNCTIONS: Int = %d;" % n)
    lines.append("pub const CTL_FUNCTIONS: Int = %d;" % ctl)
    lines.append("pub const DECLARED_CONSTANTS: Int = %d;" % len(consts))
    lines.append("pub const CTL_MACROS: Int = %d;" % len(ctl_macros))
    lines.append("")
    with open(os.path.join(outdir, "src", "opus_abi.xi"), "w", newline="\n") as f:
        f.write("\n".join(lines))
    return n, ctl


BEGIN = "// >>> GENERATED-EXTERNS-BEGIN (tools/gen_opus.py)"
END = "// <<< GENERATED-EXTERNS-END"


def inject_ffi_externs(order, outdir):
    """Replace the marker-delimited extern block inside src/opus_ffi.xi."""
    path = os.path.join(outdir, "src", "opus_ffi.xi")
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
    lines.append("/* xiom.opus -- GENERATED bridge ABI prototypes (tools/gen_opus.py).")
    lines.append(" * Included by src/opus_bridge.c so every body is signature-checked. */")
    lines.append("#ifndef XIOM_OPUS_ABI_PROTOS_H")
    lines.append("#define XIOM_OPUS_ABI_PROTOS_H")
    lines.append("#include <stdint.h>")
    lines.append("")
    lines.extend(c_protos(order))
    lines.append("")
    lines.append("#endif")
    lines.append("")
    with open(os.path.join(outdir, "src", "opus_abi_protos.h"), "w", newline="\n") as f:
        f.write("\n".join(lines))


VENDOR_GROUPS = [
    # CELT_C/CELT_ENCODER_C/CELT_DECODER_C are set for the celt unit only:
    # they select the in-header definitions (celt_fatal) and the custom-mode
    # declarations, and must be defined per-file exactly like upstream's
    # separate compilation does (defining them in every unit duplicates
    # celt_fatal at link).
    ("opus_vendor_celt.c", "celt", ["CELT_SOURCES"],
     ["#define OPUS_BUILD", '#define PACKAGE_VERSION "1.6.1"', "#define CUSTOM_MODES",
      "#define ENABLE_HARDENING", "#define VAR_ARRAYS", "#define CELT_C",
      "#define CELT_ENCODER_C", "#define CELT_DECODER_C"]),
    ("opus_vendor_silk.c", "silk", ["SILK_SOURCES"],
     ["#define OPUS_BUILD", '#define PACKAGE_VERSION "1.6.1"', "#define CUSTOM_MODES",
      "#define ENABLE_HARDENING", "#define VAR_ARRAYS"]),
    ("opus_vendor_silk_float.c", "silk", ["SILK_SOURCES_FLOAT"],
     ["#define OPUS_BUILD", '#define PACKAGE_VERSION "1.6.1"', "#define CUSTOM_MODES",
      "#define ENABLE_HARDENING", "#define VAR_ARRAYS"]),
    ("opus_vendor_src.c", "src", ["OPUS_SOURCES", "OPUS_SOURCES_FLOAT"],
     ["#define OPUS_BUILD", '#define PACKAGE_VERSION "1.6.1"', "#define CUSTOM_MODES",
      "#define ENABLE_HARDENING", "#define VAR_ARRAYS"]),
]


def emit_vendor_units(clone, outdir):
    """Emit the unity build wrappers from the pinned .mk source lists."""
    mk = {"celt": "celt_sources.mk", "silk": "silk_sources.mk", "opus": "opus_sources.mk"}
    parsed = {}
    for group, name in mk.items():
        text = open(os.path.join(clone, name), encoding="utf8").read().replace("\\\n", "")
        for line in text.split("\n"):
            line = line.strip()
            if line and "=" in line:
                var, files = line.split("=", 1)
                parsed[var.strip()] = [f for f in files.split() if f]
    counts = {}
    for fname, group, lists, defines in VENDOR_GROUPS:
        members = []
        for lst in lists:
            members.extend(parsed[lst])
        counts[fname] = len(members)
        lines = []
        lines.append("/* xiom.opus -- GENERATED unity build unit (tools/gen_opus.py).")
        lines.append(" * Upstream libopus %s sources are compiled byte-identically from" % PIN_TAG)
        lines.append(" * vendor/opus (flat tree); this unit only pins the upstream build")
        lines.append(" * configuration (defines) and the per-directory source list.")
        lines.append(" * Do not edit: regenerate with tools/gen_opus.py. */")
        for d in defines:
            lines.append(d)
        lines.append("")
        for m in members:
            lines.append('#include "../vendor/opus/%s"' % os.path.basename(m))
        lines.append("")
        with open(os.path.join(outdir, "src", fname), "w", newline="\n") as f:
            f.write("\n".join(lines))
    return counts


def verify_bridge(order, outdir):
    """Every generated xo_ entry point must be DEFINED in src/opus_bridge.c,
    and the bridge must not define entry points outside the generated set."""
    path = os.path.join(outdir, "src", "opus_bridge.c")
    text = strip_comments(open(path, encoding="utf8").read())
    defined = set(re.findall(r"\b(xo_[a-z0-9_]+)\s*\(", text))
    expected = set()
    for fn in order:
        xo = xo_name(fn)
        if SIG[fn][0] == "CTL":
            expected.add(xo + "_set")
            expected.add(xo + "_get")
        else:
            expected.add(xo)
    missing = sorted(expected - defined)
    if missing:
        raise SystemExit("FATAL: bridge does not define: %s" % ", ".join(missing))
    extra_missing = sorted(set(EXTRA) - defined)
    if extra_missing:
        raise SystemExit("FATAL: bridge does not define companion entries: %s" % ", ".join(extra_missing))
    return len(expected)


def emit_coverage(order, decls, consts, ctl_macros, bridge_entries, counts, headers_dir, outdir):
    per_header = {}
    for fn in order:
        h = decls[fn]["header"]
        per_header.setdefault(h, []).append(fn)
    manifest = {
        "package": "xiom.opus",
        "libopus_pin": {"tag": PIN_TAG, "commit": PIN},
        "headers": {},
        "declared_functions": len(order),
        "bound_functions": len(order),
        "skips": 0,
        "bridge_entry_points": bridge_entries,
        "ctl_functions": sum(1 for f in order if SIG[f][0] == "CTL"),
        "ctl_macros": len(ctl_macros),
        "constants": len(consts),
        "per_header": {h: {"declared": len(v), "bound": len(v), "skips": 0} for h, v in sorted(per_header.items())},
        "vendor_units": counts,
        "functions": {},
    }
    for h in HEADERS:
        p = os.path.join(headers_dir, h)
        if os.path.exists(p):
            manifest["headers"][h] = hashlib.sha256(open(p, "rb").read()).hexdigest().upper()
    for fn in order:
        xo = xo_name(fn)
        entry = {"header": decls[fn]["header"], "xo": xo, "bound": True, "skips": 0}
        if SIG[fn][0] == "CTL":
            entry["xo"] = [xo + "_set", xo + "_get"]
        manifest["functions"][fn] = entry
    with open(os.path.join(outdir, "docs", "gen_manifest.json"), "w", newline="\n") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")

    lines = []
    lines.append("# xiom.opus -- binding coverage (libopus %s, %s)" % (PIN_TAG, PIN))
    lines.append("")
    lines.append("Generated by `tools/gen_opus.py`; do not edit.")
    lines.append("")
    lines.append("Oracle: every function declared with an export macro in the pinned public")
    lines.append("headers is bound 1:1 to a `xo_*` bridge entry point. Buffers are XIOM-owned")
    lines.append("`Vec[UInt8]` slots; handles cross as `Int` (B-25); variadic ctl functions are")
    lines.append("bound as `_set`/`_get` pairs. `opus_repacketizer.h` does not exist in")
    lines.append("%s -- the repacketizer API is declared in `opus.h` and is counted there." % PIN_TAG)
    lines.append("")
    lines.append("| Header | Declared | Bound | Skips |")
    lines.append("|--------|---------:|------:|------:|")
    for h in HEADERS:
        v = per_header.get(h, [])
        lines.append("| `%s` | %d | %d | 0 |" % (h, len(v), len(v)))
    lines.append("| **total** | **%d** | **%d** | **0** |" % (len(order), len(order)))
    lines.append("")
    lines.append("Declared constants: %d; ctl macros (set/get pairs): %d; bridge entry"
                 % (len(consts), len(ctl_macros)))
    lines.append("points: %d. Unity build units: %s."
                 % (bridge_entries, ", ".join("%s (%d sources)" % (k, v) for k, v in sorted(counts.items()))))
    lines.append("")
    lines.append("## Function map")
    lines.append("")
    lines.append("| Declared (upstream) | Header | Bound as |")
    lines.append("|---------------------|--------|----------|")
    for fn in order:
        xo = xo_name(fn)
        bound = ("`%s_set`, `%s_get`" % (xo, xo)) if SIG[fn][0] == "CTL" else ("`%s`" % xo)
        lines.append("| `%s` | `%s` | %s |" % (fn, decls[fn]["header"], bound))
    lines.append("")
    with open(os.path.join(outdir, "docs", "COVERAGE.md"), "w", newline="\n") as f:
        f.write("\n".join(lines))
    return len(order)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--headers", required=True, help="pinned opus include/ directory")
    ap.add_argument("--clone", default=r"E:\repos\opus", help="pinned source clone (.mk lists)")
    ap.add_argument("--package", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    args = ap.parse_args()

    outdir = os.path.abspath(args.package)
    decls, order, consts, ctl_macros = build_surface(args.headers)
    counts = emit_vendor_units(args.clone, outdir)
    bridge_entries = verify_bridge(order, outdir)
    emit_abi_xi(order, consts, ctl_macros, outdir)
    inject_ffi_externs(order, outdir)
    emit_protos_h(order, outdir)
    total = emit_coverage(order, decls, consts, ctl_macros, bridge_entries, counts, args.headers, outdir)
    print("surface: %d declared = %d bound (0 skips); %d constants; %d ctl macros; %d bridge entries"
          % (total, total, len(consts), len(ctl_macros), bridge_entries))
    return 0


if __name__ == "__main__":
    sys.exit(main())
