#!/usr/bin/env python3
# XIOM -- SPIR-V headers constants generator
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Generates the xiom.spirv.headers constant modules from the shipped SPIR-V
# header (spirv.h). Oracle (owner policy, docs/UPSTREAM-FIRST.md):
#   C:\VulkanSDK\1.4.350.0\Include\spirv-headers\spirv.h
# byte-identical (verified) to KhronosGroup/SPIRV-Headers at tag
# vulkan-sdk-1.4.350.0 (commit ad9184e76a66b1001c29db9b0a3e87f646c64de0).
#
# Emits, into the package directory:
#   spirv_headers.xi            -- module xiom.spirv_headers (header facts +
#                                  generated counts; SPV_CONST_COUNT is the
#                                  emitted-constant total used by the suite)
#   src/spv_consts_<family>.xi  -- one module per constant family, names and
#                                  values verbatim from the oracle (Spv* C
#                                  enumerator tokens)
#   tools/spirv_manifest.json   -- oracle sha256, upstream pin, counts,
#                                  spot checks, per-file hashes
#
# MODULE NAMESPACE NOTE (compiler workaround, v0.64.3): the package name is
# `xiom.spirv.headers`, but the modules are declared as `xiom.spirv_headers`
# + `xiom.spirv_headers.<family>`.  The checker on the pin resolves only the
# last of several sibling imports of a FOUR-segment module path under a
# three-segment package prefix (`use xiom.spirv.headers.core;` +
# `use xiom.spirv.headers.image;` -> the earlier module's bare constants go
# undefined; minimal repro in AUDIT.md).  Three-segment module paths
# (`xiom.spirv_headers.core`) resolve correctly, so the root module uses the
# underscore parent.  When the checker defect is fixed the modules can be
# re-rooted to the canonical dotted namespace in a re-carve.
#
# Modes:
#   python tools/gen_spirv_headers.py            generate + verify + manifest
#   python tools/gen_spirv_headers.py --check    regenerate in memory and
#                                                diff against the tree
# Exit code: 0 = ok, 1 = drift/parse/count failure (fails closed).

import argparse
import hashlib
import io
import json
import os
import re
import sys

DEFAULT_HEADER = r"C:\VulkanSDK\1.4.350.0\Include\spirv-headers\spirv.h"
DEFAULT_CLONE_HEADER = r"E:\repos\SPIRV-Headers\include\spirv\unified1\spirv.h"
UPSTREAM_REPO = "https://github.com/KhronosGroup/SPIRV-Headers.git"
UPSTREAM_TAG = "vulkan-sdk-1.4.350.0"
UPSTREAM_COMMIT = "ad9184e76a66b1001c29db9b0a3e87f646c64de0"

MAX_LINES_PER_FILE = 599  # family-split discipline: files < 600 lines

# Family table: module suffix -> (title, [enum type names in header order]).
# Every enum type in the oracle must appear exactly once; the generator fails
# closed on an uncovered or duplicate enum.
FAMILIES = [
    ("core", "core enums (language, execution model, memory model, storage)", [
        "SpvSourceLanguage", "SpvExecutionModel", "SpvAddressingModel",
        "SpvMemoryModel", "SpvExecutionMode", "SpvStorageClass", "SpvDim",
        "SpvSamplerAddressingMode", "SpvSamplerFilterMode",
    ]),
    ("image", "image/sampler constants", [
        "SpvImageFormat", "SpvImageChannelOrder", "SpvImageChannelDataType",
        "SpvImageOperandsShift", "SpvImageOperandsMask",
    ]),
    ("fp", "floating-point / numeric mode constants", [
        "SpvFPFastMathModeShift", "SpvFPFastMathModeMask", "SpvFPRoundingMode",
        "SpvFPDenormMode", "SpvFPOperationMode", "SpvQuantizationModes",
        "SpvOverflowModes", "SpvPackedVectorFormat", "SpvFPEncoding",
    ]),
    ("decorations", "decorations and built-ins", [
        "SpvDecoration", "SpvBuiltIn", "SpvFunctionParameterAttribute",
        "SpvLinkageType", "SpvAccessQualifier",
    ]),
    ("controls", "control/memory/ray/cooperative operand constants", [
        "SpvSelectionControlShift", "SpvSelectionControlMask",
        "SpvLoopControlShift", "SpvLoopControlMask",
        "SpvFunctionControlShift", "SpvFunctionControlMask",
        "SpvMemorySemanticsShift", "SpvMemorySemanticsMask",
        "SpvMemoryAccessShift", "SpvMemoryAccessMask", "SpvScope",
        "SpvGroupOperation", "SpvKernelEnqueueFlags",
        "SpvKernelProfilingInfoShift", "SpvKernelProfilingInfoMask",
        "SpvRayFlagsShift", "SpvRayFlagsMask", "SpvRayQueryIntersection",
        "SpvRayQueryCommittedIntersectionType",
        "SpvRayQueryCandidateIntersectionType", "SpvFragmentShadingRateShift",
        "SpvFragmentShadingRateMask", "SpvCooperativeMatrixOperandsShift",
        "SpvCooperativeMatrixOperandsMask", "SpvCooperativeMatrixLayout",
        "SpvCooperativeMatrixUse", "SpvCooperativeMatrixReduceShift",
        "SpvCooperativeMatrixReduceMask", "SpvTensorClampMode",
        "SpvTensorAddressingOperandsShift", "SpvTensorAddressingOperandsMask",
        "SpvTensorOperandsShift", "SpvTensorOperandsMask",
        "SpvInitializationModeQualifier", "SpvHostAccessQualifier",
        "SpvLoadCacheControl", "SpvStoreCacheControl",
        "SpvNamedMaximumNumberOfRegisters",
        "SpvMatrixMultiplyAccumulateOperandsShift",
        "SpvMatrixMultiplyAccumulateOperandsMask",
        "SpvRawAccessChainOperandsShift", "SpvRawAccessChainOperandsMask",
        "SpvCooperativeVectorMatrixLayout", "SpvComponentType",
    ]),
    ("capabilities", "capability constants", [
        "SpvCapability",
    ]),
]

# SpvOp is split by numeric range so every file stays < 600 lines.
OP_BUCKETS = [
    ("ops_core", "opcodes 0..999 (core SPIR-V)", 0, 1000),
    ("ops_4000", "opcodes 4000..4999 (vendor-assigned)", 4000, 5000),
    ("ops_5000", "opcodes 5000..5999 (Khronos/vendor extensions)", 5000, 6000),
    ("ops_6000", "opcodes 6000+ and SpvOpMax", 6000, 1 << 62),
]

# Spot checks: well-known values verified against the oracle (the generator
# fails closed if the header disagrees). Values are the verbatim header text.
SPOT_CHECKS = {
    "SpvOpTypeVoid": "19",
    "SpvOpTypeInt": "21",
    "SpvOpTypeFloat": "22",
    "SpvOpTypeVector": "23",
    "SpvOpConstant": "43",
    "SpvOpFunction": "54",
    "SpvOpEntryPoint": "15",
    "SpvOpExecutionMode": "16",
    "SpvOpDecorate": "71",
    "SpvOpLoad": "61",
    "SpvOpStore": "62",
    "SpvOpReturn": "253",
    "SpvOpMax": "0x7fffffff",
    "SpvOpTerminateInvocation": "4416",
    "SpvOpGroupNonUniformPartitionNV": "5296",
    "SpvOpRayQueryGetRayTMinKHR": "6016",
    "SpvExecutionModelVertex": "0",
    "SpvExecutionModelFragment": "4",
    "SpvExecutionModelGLCompute": "5",
    "SpvStorageClassUniform": "2",
    "SpvStorageClassFunction": "7",
    "SpvStorageClassPushConstant": "9",
    "SpvAddressingModelLogical": "0",
    "SpvMemoryModelGLSL450": "1",
    "SpvMemoryModelVulkan": "3",
    "SpvSourceLanguageGLSL": "2",
    "SpvSourceLanguageHLSL": "5",
    "SpvCapabilityShader": "1",
    "SpvCapabilityGeometry": "2",
    "SpvCapabilityFloat64": "10",
    "SpvCapabilityInt64": "11",
    "SpvCapabilityRayTracingKHR": "4479",
    "SpvCapabilityVulkanMemoryModel": "5345",
    "SpvDecorationLocation": "30",
    "SpvDecorationBinding": "33",
    "SpvDecorationDescriptorSet": "34",
    "SpvDecorationBuiltIn": "11",
    "SpvBuiltInPosition": "0",
    "SpvBuiltInVertexIndex": "42",
    "SpvDim2D": "1",
    "SpvDim3D": "2",
    "SpvImageFormatRgba32f": "1",
    "SpvScopeDevice": "1",
    "SpvGroupOperationReduce": "0",
    "SpvMemorySemanticsAcquireReleaseMask": "0x00000008",
    "SpvMemoryAccessVolatileMask": "0x00000001",
    "SpvFunctionControlInlineMask": "0x00000001",
    "SpvImageOperandsBiasMask": "0x00000001",
    "SpvFPFastMathModeNotNaNMask": "0x00000001",
    "SpvFPRoundingModeRTE": "0",
    "SpvSelectionControlFlattenMask": "0x00000001",
    "SpvRayFlagsOpaqueKHRMask": "0x00000001",
    "SpvLinkageTypeExport": "0",
    "SpvAccessQualifierReadOnly": "0",
    "SpvFunctionParameterAttributeNoAlias": "4",
    "SpvSamplerFilterModeLinear": "1",
    "SpvKernelEnqueueFlagsNoWait": "0",
    "SpvCooperativeMatrixUseMatrixAKHR": "0",
    "SpvStoreCacheControlWriteBackINTEL": "2",
    "SpvInitializationModeQualifierInitOnDeviceReprogramALTERA": "0",
    "SpvRayQueryCommittedIntersectionType"
    "RayQueryCommittedIntersectionTriangleKHR": "1",
}

ENUM_BLOCK_RE = re.compile(
    r"typedef enum\s+(Spv\w+?)\s*\{(.*?)\}\s*(Spv\w+)\s*;", re.S)
ENUMERATOR_RE = re.compile(r"^\s*(Spv\w+)\s*=\s*(0x[0-9a-fA-F]+|\d+)\s*,?\s*$", re.M)
STATIC_CONST_RE = re.compile(r"static const unsigned int\s+(Spv\w+)\s*=\s*([^;]+);")
MACRO_RE = re.compile(r"^#define\s+(SPV_\w+)\s+([^\s/]+)\s*$", re.M)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest().upper()


def parse_oracle(text):
    """Structured parse; returns (enums, macros, statics, spot_values)."""
    enums = []  # list of (type_name, [(const_name, value_text)])
    seen = set()
    for m in ENUM_BLOCK_RE.finditer(text):
        closed = m.group(3)
        if closed != m.group(1).rstrip("_"):
            raise SystemExit(
                "enum block mismatch: %s vs %s" % (m.group(1), closed))
        if closed in seen:
            raise SystemExit("duplicate enum block: %s" % closed)
        seen.add(closed)
        members = ENUMERATOR_RE.findall(m.group(2))
        # independent audit: every '=' in the body must be one enumerator
        if m.group(2).count("=") != len(members):
            raise SystemExit("enumerator parse gap in %s" % closed)
        enums.append((closed, members))

    macros = MACRO_RE.findall(text)
    statics = [(n, v.strip()) for n, v in STATIC_CONST_RE.findall(text)]

    values = {}
    for _, members in enums:
        for name, value in members:
            if name in values:
                raise SystemExit("duplicate constant name: %s" % name)
            values[name] = value
    for name, value in statics:
        if name in values:
            raise SystemExit("duplicate constant name: %s" % name)
        values[name] = value

    for name, want in SPOT_CHECKS.items():
        got = values.get(name)
        if got != want:
            raise SystemExit(
                "spot-check drift: %s is %r, expected %r" % (name, got, want))
    return enums, macros, statics, values


def assign_families(enums):
    """Map every enum type to exactly one module; fail closed on gaps."""
    assigned = {}
    for mod, _, names in FAMILIES:
        for name in names:
            if name in assigned:
                raise SystemExit("enum assigned twice: %s" % name)
            assigned[name] = mod
    oracle_names = [name for name, _ in enums]
    for name in oracle_names:
        if name == "SpvOp":
            continue
        if name not in assigned:
            raise SystemExit("enum not assigned to a family: %s" % name)
    extra = sorted(set(assigned) - set(oracle_names))
    if extra:
        raise SystemExit("family table names not in oracle: %s" % extra)
    return assigned


def op_bucket(value_text):
    v = int(value_text, 0)
    for mod, _, lo, hi in OP_BUCKETS:
        if lo <= v < hi:
            return mod
    raise SystemExit("SpvOp value outside all buckets: %s" % value_text)


def file_header(title, oracle_sha):
    return [
        "// XIOM -- SPIR-V constants: %s" % title,
        "// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors",
        "// SPDX-License-Identifier: MIT OR Apache-2.0",
        "//",
        "// GENERATED by tools/gen_spirv_headers.py -- DO NOT EDIT.",
        "// Oracle: spirv.h (SPIRV-Headers %s, sha256 %s)." % (
            UPSTREAM_TAG, oracle_sha),
        "// Names and values are verbatim C enumerator tokens from the header.",
        "//",
    ]


def render_module(mod, title, enums_for_mod, oracle_sha):
    lines = file_header(title, oracle_sha)
    lines.append("module xiom.spirv_headers.%s" % mod)
    count = 0
    for type_name, members in enums_for_mod:
        lines.append("")
        lines.append("// ==== %s (%d values) ====" % (type_name, len(members)))
        lines.append("")
        for name, value in members:
            lines.append("pub const %s: Int = %s;" % (name, value))
            count += 1
    return "\n".join(lines) + "\n", count


def render_root(oracle_sha, meta):
    lines = file_header("header facts + generated counts", oracle_sha)
    lines.append("module xiom.spirv_headers")
    lines.append("")
    lines.append("// SPIR-V header version macros (#define in spirv.h).")
    lines.append("pub const SPV_VERSION: Int = %s;" % meta["spv_version"])
    lines.append("pub const SPV_REVISION: Int = %s;" % meta["spv_revision"])
    lines.append("")
    lines.append("// Header constants (static const unsigned int in spirv.h).")
    for name, value in meta["statics"]:
        lines.append("pub const %s: Int = %s;" % (name, value))
    lines.append("")
    lines.append("// Generated coverage counts (match tools/spirv_manifest.json).")
    lines.append("pub const SPV_ENUM_TYPE_COUNT: Int = %d;" % meta["enum_type_count"])
    lines.append("pub const SPV_ENUM_COUNT: Int = %d;" % meta["enum_count"])
    lines.append("pub const SPV_CONST_COUNT: Int = %d;" % meta["const_count"])
    lines.append("")
    lines.append("// SHA256 of the oracle spirv.h this package was generated from.")
    lines.append('pub const SPV_HEADER_SHA256: Str = "%s";' % oracle_sha)
    return "\n".join(lines) + "\n"


def build(header_path, out_dir):
    text = io.open(header_path, "r", encoding="utf-8").read()
    oracle_sha = sha256_file(header_path)
    enums, macros, statics, values = parse_oracle(text)
    assigned = assign_families(enums)

    enum_by_mod = {mod: [] for mod, _, _ in FAMILIES}
    for name, members in enums:
        if name == "SpvOp":
            buckets = {}
            for cname, cvalue in members:
                buckets.setdefault(op_bucket(cvalue), []).append((cname, cvalue))
            for mod, _, _, _ in OP_BUCKETS:
                enum_by_mod.setdefault(mod, [])
                enum_by_mod[mod].append((name, buckets.get(mod, [])))
        else:
            enum_by_mod[assigned[name]].append((name, members))

    generated = {}  # relative path -> text
    module_reports = []

    module_order = [m for m, _, _ in FAMILIES] + [m for m, _, _, _ in OP_BUCKETS]
    titles = {m: t for m, t, _ in FAMILIES}
    titles.update({m: t for m, t, _, _ in OP_BUCKETS})
    for mod in module_order:
        rel = "src/spv_consts_%s.xi" % mod
        text_out, count = render_module(
            mod, titles[mod], enum_by_mod[mod], oracle_sha)
        lines = text_out.count("\n")
        if lines > MAX_LINES_PER_FILE:
            raise SystemExit("file too long (%d lines): %s" % (lines, rel))
        generated[rel] = text_out
        module_reports.append({
            "file": rel.replace("/", "\\"),
            "module": "xiom.spirv_headers.%s" % mod,
            "constants": count,
            "enums": [name for name, _ in enum_by_mod[mod]],
            "sha256": hashlib.sha256(text_out.encode("utf-8")).hexdigest().upper(),
        })

    enum_count = sum(len(members) for _, members in enums)
    const_count = enum_count + len(macros) + len(statics)
    meta = {
        "spv_version": dict(macros)["SPV_VERSION"],
        "spv_revision": dict(macros)["SPV_REVISION"],
        "statics": statics,
        "enum_type_count": len(enums),
        "enum_count": enum_count,
        "const_count": const_count,
    }
    root_text = render_root(oracle_sha, meta)
    generated["spirv_headers.xi"] = root_text

    # Independent audit count (line scan, no structured assumptions).
    naive = len(re.findall(r"^\s*Spv\w+\s*=\s*(?:0x[0-9a-fA-F]+|\d+)\s*,\s*$",
                           text, re.M))
    if naive != enum_count:
        raise SystemExit(
            "oracle audit mismatch: naive=%d structured=%d" % (naive, enum_count))

    manifest = {
        "generator": "tools/gen_spirv_headers.py",
        "package_name": "xiom.spirv.headers",
        "module_namespace": "xiom.spirv_headers",
        "oracle_header": header_path,
        "oracle_sha256": oracle_sha,
        "upstream": {
            "repo": UPSTREAM_REPO,
            "tag": UPSTREAM_TAG,
            "commit": UPSTREAM_COMMIT,
        },
        "spv_version": meta["spv_version"],
        "spv_revision": meta["spv_revision"],
        "enum_type_count": meta["enum_type_count"],
        "enum_count": meta["enum_count"],
        "macro_count": len(macros),
        "static_const_count": len(statics),
        "const_count": meta["const_count"],
        "modules": module_reports,
        "spot_checks": SPOT_CHECKS,
        "spot_check_count": len(SPOT_CHECKS),
    }
    return generated, manifest


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--header", default=DEFAULT_HEADER,
                    help="oracle spirv.h (default: SDK 1.4.350.0)")
    ap.add_argument("--clone-header", default=DEFAULT_CLONE_HEADER,
                    help="upstream clone copy to cross-verify (optional)")
    ap.add_argument("--out", default=os.path.dirname(
        os.path.dirname(os.path.abspath(__file__))),
        help="package directory (default: directory containing tools/)")
    ap.add_argument("--manifest", default="tools/spirv_manifest.json",
                    help="manifest path relative to --out")
    ap.add_argument("--check", action="store_true",
                    help="regenerate in memory and diff against the tree")
    args = ap.parse_args(argv)

    out_dir = os.path.abspath(args.out)
    generated, manifest = build(args.header, out_dir)

    if os.path.exists(args.clone_header):
        clone_sha = sha256_file(args.clone_header)
        manifest["upstream"]["clone_header_sha256"] = clone_sha
        manifest["upstream"]["clone_byte_identical"] = (
            clone_sha == manifest["oracle_sha256"])
        if clone_sha != manifest["oracle_sha256"]:
            raise SystemExit(
                "clone header differs from oracle (%s vs %s)" % (
                    clone_sha, manifest["oracle_sha256"]))

    problems = []
    if args.check:
        for rel, content in sorted(generated.items()):
            path = os.path.join(out_dir, *rel.split("/"))
            if not os.path.exists(path):
                problems.append("missing: %s" % rel)
            elif io.open(path, "r", encoding="utf-8").read() != content:
                problems.append("drift: %s" % rel)
        manifest_path = os.path.join(out_dir, *args.manifest.split("/"))
        if os.path.exists(manifest_path):
            current = json.load(io.open(manifest_path, "r", encoding="utf-8"))
            for key in ("oracle_sha256", "enum_count", "const_count"):
                if current.get(key) != manifest.get(key):
                    problems.append("manifest %s: %r != %r" % (
                        key, current.get(key), manifest.get(key)))
        else:
            problems.append("missing manifest: %s" % args.manifest)
    else:
        for rel, content in sorted(generated.items()):
            path = os.path.join(out_dir, *rel.split("/"))
            if not os.path.isdir(os.path.dirname(path)):
                os.makedirs(os.path.dirname(path))
            io.open(path, "w", encoding="utf-8", newline="\n").write(content)
        manifest_path = os.path.join(out_dir, *args.manifest.split("/"))
        if not os.path.isdir(os.path.dirname(manifest_path)):
            os.makedirs(os.path.dirname(manifest_path))
        io.open(manifest_path, "w", encoding="utf-8", newline="\n").write(
            json.dumps(manifest, indent=2) + "\n")

    print("oracle:   %s" % args.header)
    print("sha256:   %s" % manifest["oracle_sha256"])
    print("enums:    %d types / %d values" % (
        manifest["enum_type_count"], manifest["enum_count"]))
    print("emitted:  %d constants (%d enum + %d macro + %d static)" % (
        manifest["const_count"], manifest["enum_count"],
        manifest["macro_count"], manifest["static_const_count"]))
    print("spot:     %d checks, all match the oracle" % manifest["spot_check_count"])
    print("files:    %d modules" % (len(generated) - 1))
    if args.check:
        if problems:
            for p in problems:
                print("DRIFT %s" % p)
            return 1
        print("check:    tree matches a fresh generation (no drift)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
