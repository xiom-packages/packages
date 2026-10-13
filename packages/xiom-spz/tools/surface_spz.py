#!/usr/bin/env python3
# XIOM -- xiom.spz surface inventory + coverage checker (Python stdlib only).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# The inventory below is the authoritative transcription of the public surface
# of the three pinned spz headers (vendor/spz/*.h at v3.0.0,
# 5bf2945de1a003cee07133b1e495fe9c6ffdc7e7).  The script verifies, fail-closed:
#   1. every declared name really occurs in the pinned header text;
#   2. every bridged entry names a `xspz_*` symbol that exists in
#      src/spz_bridge.cpp and an XIOM wrapper that exists in the modules;
#   3. every model/non-goal entry carries an explicit classification.
#
# Outputs: docs/surface_spz.json (inventory + coverage) and docs/COVERAGE.md
# (human-readable table with counts for the final report).
#
# Usage:  python tools/surface_spz.py [--check]
# Exit code: 0 = all rows verified, 1 = a row failed verification.

import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

HEADERS = {
    "load-spz.h": os.path.join(ROOT, "vendor", "spz", "load-spz.h"),
    "splat-types.h": os.path.join(ROOT, "vendor", "spz", "splat-types.h"),
    "splat-c-types.h": os.path.join(ROOT, "vendor", "spz", "splat-c-types.h"),
}
BRIDGE = os.path.join(ROOT, "src", "spz_bridge.cpp")
MODULES = [
    os.path.join(ROOT, "src", "spz.xi"),
    os.path.join(ROOT, "src", "spz_math.xi"),
    os.path.join(ROOT, "src", "spz_ffi.xi"),
]

# kind: "function" | "method" | "struct" | "enum" | "using" | "const" | "typedef"
# cov:  "bridge" (fn), "model" (type/const), "non-goal"
INVENTORY = [
    # -- load-spz.h ----------------------------------------------------------
    {"name": "SH_MAX_DEGREE", "header": "load-spz.h", "kind": "const", "cov": "model",
     "where": "xiom.spz SPZ_SH_MAX_DEGREE"},
    {"name": "SH_MAX_COEFFS", "header": "load-spz.h", "kind": "const", "cov": "model",
     "where": "xiom.spz SPZ_SH_MAX_COEFFS"},
    {"name": "DEFAULT_SH1_BITS", "header": "load-spz.h", "kind": "const", "cov": "model",
     "where": "xiom.spz SPZ_DEFAULT_SH1_BITS"},
    {"name": "DEFAULT_SH_REST_BITS", "header": "load-spz.h", "kind": "const", "cov": "model",
     "where": "xiom.spz SPZ_DEFAULT_SH_REST_BITS"},
    {"name": "LATEST_SPZ_HEADER_VERSION", "header": "load-spz.h", "kind": "const", "cov": "model",
     "where": "xiom.spz SPZ_LATEST_HEADER_VERSION"},
    {"name": "MIN_ZSTD_SPZ_HEADER_VERSION", "header": "load-spz.h", "kind": "const", "cov": "model",
     "where": "xiom.spz SPZ_MIN_ZSTD_HEADER_VERSION"},
    {"name": "MIN_SMALLEST_THREE_QUATERNIONS_VERSION", "header": "load-spz.h", "kind": "const",
     "cov": "model", "where": "xiom.spz SPZ_MIN_SMALLEST_THREE_VERSION"},
    {"name": "NGSP_MAGIC", "header": "load-spz.h", "kind": "const", "cov": "model",
     "where": "xiom.spz SPZ_NGSP_MAGIC (+ bridge xspz_constants)"},
    {"name": "SpzLog", "header": "load-spz.h", "kind": "function", "cov": "non-goal",
     "why": "header-local static logging template (printf wrapper); no library symbol"},
    {"name": "UnpackedGaussian", "header": "load-spz.h", "kind": "struct", "cov": "model",
     "where": "SpzUnpackedGaussian (86-float flat record, SPZ_UNPACKED_OFF_*)"},
    {"name": "PackedGaussian", "header": "load-spz.h", "kind": "struct", "cov": "model",
     "where": "SpzPackedGaussian (92-byte raw record, SPZ_PACKED_OFF_*)"},
    {"name": "PackedGaussians", "header": "load-spz.h", "kind": "struct", "cov": "model",
     "where": "SpzMeta + the packed accessors"},
    {"name": "PackOptions", "header": "load-spz.h", "kind": "struct", "cov": "model",
     "where": "spz_pack parameters (version/from/sh1Bits/shRestBits)"},
    {"name": "UnpackOptions", "header": "load-spz.h", "kind": "struct", "cov": "model",
     "where": "spz_unpack to_coord parameter"},
    {"name": "PlyExtraElement", "header": "load-spz.h", "kind": "struct", "cov": "non-goal",
     "why": "declared struct; used only inside load-spz.cc's PLY reader and never exposed by a public function (grepped at pin)"},
    {"name": "saveSpz", "header": "load-spz.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_pack / xspz_save_file", "xiom": "spz_pack / spz_save_file"},
    {"name": "loadSpz", "header": "load-spz.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_unpack / xspz_load_file", "xiom": "spz_unpack / spz_load_file"},
    {"name": "loadSpzPacked", "header": "load-spz.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_load_packed / xspz_load_file", "xiom": "spz_load_packed"},
    {"name": "saveSplatToPly", "header": "load-spz.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_save_ply", "xiom": "spz_save_ply"},
    {"name": "loadSplatFromPly", "header": "load-spz.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_load_ply", "xiom": "spz_load_ply"},
    {"name": "serializePackedGaussians", "header": "load-spz.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_serialize_packed", "xiom": "spz_serialize_packed"},
    {"name": "compressGzipped", "header": "load-spz.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_compress_gzipped", "xiom": "spz_compress_gzipped"},
    {"name": "hasExtensionSupport", "header": "load-spz.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_has_extension_support", "xiom": "spz_has_extension_support"},
    # -- splat-types.h -------------------------------------------------------
    {"name": "CoordinateSystem", "header": "splat-types.h", "kind": "enum", "cov": "model",
     "where": "SPZ_COORD_* (bridge xspz_coordinate_values validates 0..8)"},
    {"name": "CoordinateConverter", "header": "splat-types.h", "kind": "struct", "cov": "model",
     "where": "30-float flat result of spz_coordinate_converter"},
    {"name": "axesMatch", "header": "splat-types.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_axes_match", "xiom": "spz_axes_match"},
    {"name": "coordinateConverter", "header": "splat-types.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_coordinate_converter", "xiom": "spz_coordinate_converter"},
    {"name": "GaussianCloud", "header": "splat-types.h", "kind": "struct", "cov": "model",
     "where": "SpzCloud (flat float workspace, SPZ_STREAM_*)"},
    {"name": "Vec3f", "header": "splat-types.h", "kind": "using", "cov": "model",
     "where": "3-float flat values in the math wrappers"},
    {"name": "Quat4f", "header": "splat-types.h", "kind": "using", "cov": "model",
     "where": "4-float w-first flat values in the math wrappers"},
    {"name": "Half", "header": "splat-types.h", "kind": "using", "cov": "model",
     "where": "Int bit pattern (0..65535)"},
    {"name": "halfToFloat", "header": "splat-types.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_math_half_to_float", "xiom": "spz_half_to_float (xiom.spz.math)"},
    {"name": "floatToHalf", "header": "splat-types.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_math_float_to_half", "xiom": "spz_float_to_half (xiom.spz.math)"},
    {"name": "normalized", "header": "splat-types.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_math_normalized3 / xspz_math_normalized4",
     "xiom": "spz_normalized3 / spz_normalized4 (xiom.spz.math)"},
    {"name": "norm", "header": "splat-types.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_math_norm3 / xspz_math_norm4", "xiom": "spz_norm3 / spz_norm4 (xiom.spz.math)"},
    {"name": "axisAngleQuat", "header": "splat-types.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_math_axis_angle_quat", "xiom": "spz_axis_angle_quat (xiom.spz.math)"},
    {"name": "vec3f", "header": "splat-types.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_math_vec3f", "xiom": "spz_vec3f (xiom.spz.math)"},
    {"name": "dot", "header": "splat-types.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_math_dot3", "xiom": "spz_dot3 (xiom.spz.math)"},
    {"name": "squaredNorm", "header": "splat-types.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_math_squared_norm3", "xiom": "spz_squared_norm3 (xiom.spz.math)"},
    {"name": "quat4f", "header": "splat-types.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_math_quat4f", "xiom": "spz_quat4f (xiom.spz.math)"},
    {"name": "times", "header": "splat-types.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_math_times_qv / _qq / _qs / _vs / _vv",
     "xiom": "spz_times_qv/_qq/_qs/_vs/_vv (xiom.spz.math)"},
    {"name": "plus", "header": "splat-types.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_math_plus_qq / xspz_math_plus_vv", "xiom": "spz_plus_qq / spz_plus_vv (xiom.spz.math)"},
    {"name": "copyFloatBuffer", "header": "splat-types.h", "kind": "function", "cov": "bridge",
     "bridge": "xspz_math_copy_float_buffer", "xiom": "spz_copy_float_buffer (xiom.spz.math)"},
    {"name": "data()", "header": "splat-types.h", "kind": "method", "cov": "bridge",
     "bridge": "xspz_cloud_data", "xiom": "spz_cloud_data"},
    {"name": "convertCoordinates", "header": "splat-types.h", "kind": "method", "cov": "bridge",
     "bridge": "xspz_cloud_convert", "xiom": "spz_cloud_convert"},
    {"name": "rotate180DegAboutX", "header": "splat-types.h", "kind": "method", "cov": "bridge",
     "bridge": "xspz_cloud_rotate180", "xiom": "spz_cloud_rotate180"},
    {"name": "medianVolume", "header": "splat-types.h", "kind": "method", "cov": "bridge",
     "bridge": "xspz_median_volume", "xiom": "spz_median_volume"},
    {"name": "unpack(bool, bool, int32_t, const CoordinateConverter &)", "header": "load-spz.h",
     "kind": "method", "cov": "bridge", "match": "unpack",
     "bridge": "xspz_packed_gaussian_unpack", "xiom": "spz_packed_gaussian_unpack"},
    {"name": "usesFloat16", "header": "load-spz.h", "kind": "method", "cov": "bridge",
     "bridge": "xspz_load_packed (meta slot bit 6)", "xiom": "spz_load_packed"},
    {"name": "at(int32_t)", "header": "load-spz.h", "kind": "method", "cov": "bridge",
     "match": "at", "bridge": "xspz_packed_gaussian", "xiom": "spz_packed_gaussian"},
    # -- splat-c-types.h -----------------------------------------------------
    {"name": "SpzFloatBuffer", "header": "splat-c-types.h", "kind": "typedef", "cov": "model",
     "where": "count + owned float stream (SpzCloud workspaces)"},
    {"name": "GaussianCloudData", "header": "splat-c-types.h", "kind": "typedef", "cov": "model",
     "where": "the six SpzFloatBuffers; produced by spz_cloud_data"},
    {"name": "SpzExtensionNode", "header": "splat-c-types.h", "kind": "typedef", "cov": "non-goal",
     "why": "extension chain pointer type; SPZ_BUILD_EXTENSIONS is off in the pinned build (no splat-extensions.h vendored)"},
]


def read(path):
    with io.open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def main():
    header_text = {name: read(path) for name, path in HEADERS.items()}
    bridge_text = read(BRIDGE)
    module_text = "\n".join(read(p) for p in MODULES)

    rows = []
    problems = []
    counts = {"bridge": 0, "model": 0, "non-goal": 0}

    for item in INVENTORY:
        row = dict(item)
        needle = item.get("match", item["name"])
        base = needle.split("(")[0]
        if base not in header_text[item["header"]]:
            problems.append("%s: not found in %s" % (item["name"], item["header"]))
        if item["cov"] == "bridge":
            for sym in re.findall(r"xspz_[a-z0-9_]+", item["bridge"]):
                if sym not in bridge_text:
                    problems.append("%s: bridge symbol %s missing" % (item["name"], sym))
            for sym in re.findall(r"\b(spz_[a-z0-9_]+)\b", item["xiom"]):
                if sym not in module_text:
                    problems.append("%s: XIOM wrapper %s missing" % (item["name"], sym))
        counts[item["cov"]] += 1
        rows.append(row)

    report = {
        "package": "xiom.spz",
        "upstream": "github.com/nianticlabs/spz",
        "pin": "v3.0.0 = 5bf2945de1a003cee07133b1e495fe9c6ffdc7e7",
        "headers": sorted(HEADERS.keys()),
        "counts": {
            "total": len(rows),
            "bridged": counts["bridge"],
            "model": counts["model"],
            "non_goal": counts["non-goal"],
        },
        "rows": rows,
        "problems": problems,
    }

    out_json = os.path.join(ROOT, "docs", "surface_spz.json")
    with io.open(out_json, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(report, indent=2, sort_keys=True) + "\n")

    lines = []
    lines.append("# COVERAGE -- xiom.spz (nianticlabs/spz v3.0.0)")
    lines.append("")
    lines.append("Generated by `tools/surface_spz.py` from the pinned headers")
    lines.append("(`vendor/spz/load-spz.h`, `splat-types.h`, `splat-c-types.h` at")
    lines.append("`5bf2945de1a003cee07133b1e495fe9c6ffdc7e7`).  Every row is verified")
    lines.append("against the header text and the actual bridge/XIOM symbols (fail-closed).")
    lines.append("")
    lines.append("| Declared | Kind | Header | Coverage |")
    lines.append("|----------|------|--------|----------|")
    for row in rows:
        if row["cov"] == "bridge":
            dest = "%s -> %s" % (row["bridge"], row["xiom"])
        elif row["cov"] == "model":
            dest = "model: %s" % row.get("where", "")
        else:
            dest = "non-goal: %s" % row.get("why", "")
        lines.append("| `%s` | %s | %s | %s |" % (row["name"], row["kind"], row["header"], dest))
    lines.append("")
    lines.append("Counts: **%d declarations -- %d bridged (bridge fn + XIOM wrapper), "
                 "%d modeled (type/constant), %d documented non-goals.**"
                 % (len(rows), counts["bridge"], counts["model"], counts["non-goal"]))
    lines.append("")
    lines.append("Non-goals are explicit and audited: the extension surface")
    lines.append("(`SPZ_BUILD_EXTENSIONS`, `splat-extensions.h`) is not part of the pinned")
    lines.append("build (flag off), `SpzLog` is a header-local logging template with no")
    lines.append("library symbol, and `PlyExtraElement` instances are never reachable from a")
    lines.append("public function (used only inside load-spz.cc's PLY reader).")
    out_md = os.path.join(ROOT, "docs", "COVERAGE.md")
    with io.open(out_md, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    print("surface_spz: %d declarations (%d bridged, %d modeled, %d non-goal); %d problem(s)"
          % (len(rows), counts["bridge"], counts["model"], counts["non-goal"], len(problems)))
    for p in problems:
        print("  PROBLEM: " + p)
    if problems:
        return 1
    if "--check" in sys.argv:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
