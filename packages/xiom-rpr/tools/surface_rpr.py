#!/usr/bin/env python3
# ============================================================================
# xiom.rpr declared-surface coverage oracle (fail-closed).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Verifies, for the package's DECLARED surface, that every item exists in the
# pinned vendored header (vendor/rpr/RadeonProRender.h, v3.1.7.1), is bridged
# in src/rpr_bridge.c (loader GetProcAddress + definition), and is wrapped in
# src/rpr_ffi.xi / src/rpr.xi.  Regenerates docs/surface_rpr.json and
# docs/COVERAGE.md.  Any missing item exits 1.
#
# Usage: python tools/surface_rpr.py

import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HEADER_PATH = os.path.join(ROOT, "vendor", "rpr", "RadeonProRender.h")
BRIDGE_PATH = os.path.join(ROOT, "src", "rpr_bridge.c")
FFI_PATH = os.path.join(ROOT, "src", "rpr_ffi.xi")
FACADE_PATH = os.path.join(ROOT, "src", "rpr.xi")
JSON_PATH = os.path.join(ROOT, "docs", "surface_rpr.json")
MD_PATH = os.path.join(ROOT, "docs", "COVERAGE.md")

# G2 pin: SHA256 over the stored (LF) bytes of the vendored header.
PIN_HEADER_SHA256 = "57ff864d1b8dfbd3c754a81413dec5536aa3d509209a10a8a35d1870fcd5fd20"
PIN_LICENSE_SHA256 = "5af0ad505b68b05ec5c5381595582769b9bcaaffed618cde3a1a46ac691d932c"
UPSTREAM = {
    "project": "AMD Radeon ProRender SDK",
    "repository": "github.com/GPUOpen-LibrariesAndSDKs/RadeonProRenderSDK",
    "pin": "v3.1.7.1",
    "commit": "2edd23c5fdb8eabf40bdf1ba4f6509e203e28c51",
    "license": "Apache-2.0",
}

# --- declared surface -------------------------------------------------------
# bridged: (rpr symbol, [bridge symbols], [xiom wrappers in src/rpr.xi])
# the bridge symbol must be GetProcAddress-resolved and defined in
# src/rpr_bridge.c; the xiom wrapper must exist in src/rpr.xi and the raw
# extern must exist in src/rpr_ffi.xi.

BRIDGED = [
    ("rprRegisterPlugin", ["rprx_register_plugin"], ["register_plugin"]),
    ("rprCreateContext", ["rprx_context_create"], ["context_create"]),
    ("rprContextSetActivePlugin", ["rprx_context_set_active_plugin"], ["context_set_active_plugin"]),
    ("rprContextGetInfo", ["rprx_context_info_str", "rprx_context_info_u"],
     ["context_info_str", "context_info_u", "context_last_error"]),
    ("rprContextSetScene", ["rprx_context_set_scene"], ["context_set_scene"]),
    ("rprContextSetParameterByKey1u", ["rprx_context_set_param_u"],
     ["context_set_param_u", "context_set_iterations"]),
    ("rprContextSetParameterByKey1f", ["rprx_context_set_param_f"], ["context_set_param_f"]),
    ("rprContextSetAOV", ["rprx_context_set_aov_color"], ["context_set_aov_color"]),
    ("rprContextRender", ["rprx_context_render"], ["context_render"]),
    ("rprContextResolveFrameBuffer", ["rprx_context_resolve"], ["context_resolve"]),
    ("rprContextCreateScene", ["rprx_scene_create"], ["scene_create"]),
    ("rprSceneAttachShape", ["rprx_scene_attach_shape"], ["scene_attach_shape"]),
    ("rprSceneAttachLight", ["rprx_scene_attach_light"], ["scene_attach_light"]),
    ("rprSceneSetCamera", ["rprx_scene_set_camera"], ["scene_set_camera"]),
    ("rprContextCreateCamera", ["rprx_camera_create"], ["camera_create"]),
    ("rprCameraLookAt", ["rprx_camera_look_at"], ["camera_look_at"]),
    ("rprCameraSetFocalLength", ["rprx_camera_set_focal_length"], ["camera_set_focal_length"]),
    ("rprCameraSetSensorSize", ["rprx_camera_set_sensor_size"], ["camera_set_sensor_size"]),
    ("rprContextCreatePointLight", ["rprx_light_create_point"], ["light_create_point"]),
    ("rprContextCreateDirectionalLight", ["rprx_light_create_directional"],
     ["light_create_directional"]),
    ("rprLightSetTransform", ["rprx_light_set_transform"], ["light_set_transform"]),
    ("rprPointLightSetRadiantPower3f", ["rprx_light_set_power"], ["light_set_radiance"]),
    ("rprDirectionalLightSetRadiantPower3f", ["rprx_light_set_power"], ["light_set_radiance"]),
    ("rprContextCreateMaterialSystem", ["rprx_material_system_create"], ["material_system_create"]),
    ("rprMaterialSystemCreateNode", ["rprx_material_create_node"], ["material_create_node"]),
    ("rprMaterialNodeSetInputFByKey", ["rprx_material_set_input_f"], ["material_set_input_f"]),
    ("rprMaterialNodeSetInputUByKey", ["rprx_material_set_input_u"], ["material_set_input_u"]),
    ("rprShapeSetMaterial", ["rprx_shape_set_material"], ["shape_set_material"]),
    ("rprShapeSetTransform", ["rprx_shape_set_transform"], ["shape_set_transform"]),
    ("rprContextCreateMesh", ["rprx_mesh_create"], ["mesh_create"]),
    ("rprContextCreateFrameBuffer", ["rprx_framebuffer_create"], ["framebuffer_create"]),
    ("rprFrameBufferClear", ["rprx_framebuffer_clear"], ["framebuffer_clear"]),
    ("rprFrameBufferGetInfo", ["rprx_framebuffer_desc", "rprx_framebuffer_read",
                               "rprx_framebuffer_read_bytes"],
     ["framebuffer_desc", "framebuffer_read", "framebuffer_read_bytes"]),
    ("rprObjectDelete", ["rprx_object_delete"],
     ["context_destroy", "scene_destroy", "camera_destroy", "shape_destroy", "light_destroy",
      "framebuffer_destroy", "material_system_destroy", "material_node_destroy"]),
]

# modeled constants: (name, expected integer value)
CONSTANTS = [
    ("RPR_VERSION_MAJOR", 3),
    ("RPR_VERSION_MINOR", 1),
    ("RPR_VERSION_REVISION", 7),
    ("RPR_VERSION_MAJOR_MINOR_REVISION", 0x00300107),
    ("RPR_SUCCESS", 0),
    ("RPR_CREATION_FLAGS_ENABLE_GPU0", 1),
    ("RPR_CREATION_FLAGS_ENABLE_CPU", 16),
    ("RPR_AOV_COLOR", 0x0),
    ("RPR_CONTEXT_ITERATIONS", 0x10B),
    ("RPR_CONTEXT_RENDER_STATUS", 0x104),
    ("RPR_CONTEXT_DEVICE_COUNT", 0x106),
    ("RPR_CONTEXT_DISPLAY_GAMMA", 0x124),
    ("RPR_CONTEXT_GPU0_NAME", 0x127),
    ("RPR_CONTEXT_CPU_NAME", 0x12B),
    ("RPR_CONTEXT_LAST_ERROR_MESSAGE", 0x137),
    ("RPR_CONTEXT_API_VERSION", 0x141),
    ("RPR_COMPONENT_TYPE_FLOAT32", 0x3),
    ("RPR_FRAMEBUFFER_FORMAT", 0x1301),
    ("RPR_FRAMEBUFFER_DESC", 0x1302),
    ("RPR_FRAMEBUFFER_DATA", 0x1303),
    ("RPR_MATERIAL_NODE_DIFFUSE", 0x1),
    ("RPR_MATERIAL_NODE_EMISSIVE", 0x7),
    ("RPR_MATERIAL_NODE_UBERV2", 0x2b),
    ("RPR_MATERIAL_INPUT_COLOR", 0x0),
    ("RPR_MATERIAL_INPUT_UBER_DIFFUSE_COLOR", 0x910),
    ("RPR_MATERIAL_INPUT_UBER_DIFFUSE_WEIGHT", 0x927),
    ("RPR_MATERIAL_INPUT_UBER_REFLECTION_COLOR", 0x913),
    ("RPR_MATERIAL_INPUT_UBER_REFLECTION_WEIGHT", 0x928),
    ("RPR_MATERIAL_INPUT_UBER_REFLECTION_MODE", 0x917),
    ("RPR_LIGHT_TYPE_POINT", 0x1),
    ("RPR_LIGHT_TYPE_DIRECTIONAL", 0x2),
]

# modeled core typedefs
TYPES = [
    "rpr_int", "rpr_uint", "rpr_float", "rpr_status", "rpr_bool",
    "rpr_context", "rpr_scene", "rpr_camera", "rpr_shape", "rpr_light",
    "rpr_framebuffer", "rpr_material_system", "rpr_material_node",
    "rpr_creation_flags", "rpr_context_info", "rpr_aov", "rpr_component_type",
    "rpr_framebuffer_info", "rpr_material_node_type", "rpr_material_node_input",
    "rpr_light_type", "rpr_framebuffer_desc", "rpr_framebuffer_format",
]


def read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read()


def find_line(text, pattern):
    rx = re.compile(pattern)
    for idx, line in enumerate(text.splitlines(), start=1):
        if rx.search(line):
            return idx, line.strip()
    return None, None


def eval_define(rhs):
    rhs = rhs.strip()
    m = re.match(r"^\(\s*1\s*<<\s*(\d+)\s*\)$", rhs)
    if m:
        return 1 << int(m.group(1))
    m = re.match(r"^0[xX]([0-9a-fA-F]+)$", rhs)
    if m:
        return int(m.group(1), 16)
    if re.match(r"^[0-9]+$", rhs):
        return int(rhs)
    return None


def main():
    header = read(HEADER_PATH)
    bridge = read(BRIDGE_PATH)
    ffi = read(FFI_PATH)
    facade = read(FACADE_PATH)

    header_bytes = os.path.getsize(HEADER_PATH)
    header_sha = hashlib.sha256(open(HEADER_PATH, "rb").read()).hexdigest()
    license_sha = hashlib.sha256(
        open(os.path.join(ROOT, "vendor", "rpr", "license.txt"), "rb").read()).hexdigest()

    problems = []
    bridged_rows = []
    for rpr_name, bridge_syms, wrappers in BRIDGED:
        hline, hdecl = find_line(
            header, r"^\s*extern\s+RPR_API_ENTRY\s+\w+\s+" + rpr_name + r"\s*\(")
        if hline is None:
            problems.append("header: missing declaration for %s" % rpr_name)
        for sym in bridge_syms:
            if ('GetProcAddress(g_api.mod, "%s")' % rpr_name) not in bridge and \
               ('"%s"' % rpr_name) not in bridge:
                problems.append("bridge: %s not resolved by GetProcAddress" % rpr_name)
            if not re.search(r"\b" + sym + r"\s*\(", bridge):
                problems.append("bridge: symbol %s not defined" % sym)
            if not re.search(r"\bfn\s+" + sym + r"\s*\(", ffi):
                problems.append("ffi: extern %s missing in src/rpr_ffi.xi" % sym)
        for w in wrappers:
            if not re.search(r"pub\s+fn\s+" + w + r"\s*\(", facade):
                problems.append("facade: wrapper %s missing in src/rpr.xi" % w)
        bridged_rows.append({
            "rpr": rpr_name,
            "bridge": bridge_syms,
            "xiom": wrappers,
            "header_line": hline,
            "header_decl": hdecl,
        })

    const_rows = []
    for name, value in CONSTANTS:
        m = re.search(r"^#define\s+" + name + r"\s+(.+?)\s*$", header, re.MULTILINE)
        if not m:
            problems.append("header: missing #define %s" % name)
            const_rows.append({"name": name, "value": value, "header": None, "ok": False})
            continue
        got = eval_define(m.group(1))
        if got != value:
            problems.append("constant %s: header=%r evaluated=%r package=%r"
                            % (name, m.group(1), got, value))
        if not re.search(r"pub\s+const\s+" + name + r"\s*:\s*Int\s*=", facade):
            problems.append("facade: pub const %s missing in src/rpr.xi" % name)
        line, _ = find_line(header, r"^#define\s+" + name + r"\s+")
        const_rows.append({"name": name, "value": value, "header": m.group(1),
                           "header_line": line, "ok": got == value})

    type_rows = []
    for name in TYPES:
        m = re.search(r"typedef\s+[^;\n]*\b" + name + r"\s*;", header)
        if not m:
            problems.append("header: missing typedef %s" % name)
            type_rows.append({"name": name, "header_line": None, "ok": False})
            continue
        line, _ = find_line(header, r"typedef\s+[^;]*\b" + name + r"\s*;")
        type_rows.append({"name": name, "header_line": line, "ok": True})

    counts = {
        "bridged": len(bridged_rows),
        "modeled_constants": len(const_rows),
        "modeled_types": len(type_rows),
        "total_declared": len(bridged_rows) + len(const_rows) + len(type_rows),
        "gaps": len(problems),
    }

    surface = {
        "package": "xiom.rpr",
        "upstream": UPSTREAM,
        "header": {
            "path": "vendor/rpr/RadeonProRender.h",
            "bytes": header_bytes,
            "sha256": header_sha,
            "pin_sha256": PIN_HEADER_SHA256,
            "pin_ok": header_sha == PIN_HEADER_SHA256,
        },
        "license": {
            "path": "vendor/rpr/license.txt",
            "sha256": license_sha,
            "pin_sha256": PIN_LICENSE_SHA256,
            "pin_ok": license_sha == PIN_LICENSE_SHA256,
        },
        "counts": counts,
        "bridged": bridged_rows,
        "modeled_constants": const_rows,
        "modeled_types": type_rows,
        "non_goals": [
            "RadeonProRender_v2.h (v2 object API): separate header, phase 2",
            "RprLoadStore.h / ProRenderGLTF.h / MaterialX / interop (GL/VK/D3D12/Metal/CL) headers: phase 2",
            "rprDeprecatedApi.h surface: intentionally not bound",
            "the remaining core-header functions (images, buffers, AOV extras, composites, curves, volumes, post effects, subdivision): phase 2 (ROADMAP)",
        ],
    }

    if header_sha != PIN_HEADER_SHA256:
        problems.append("vendored header hash drifted from the G2 pin")
    if license_sha != PIN_LICENSE_SHA256:
        problems.append("vendored license hash drifted from the G2 pin")

    os.makedirs(os.path.dirname(JSON_PATH), exist_ok=True)
    with open(JSON_PATH, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(surface, fh, indent=2, sort_keys=False)
        fh.write("\n")

    lines = []
    lines.append("# COVERAGE -- xiom.rpr declared surface (100% of declared)")
    lines.append("")
    lines.append("Generated by `tools/surface_rpr.py` (fail-closed) from the pinned")
    lines.append("header `vendor/rpr/RadeonProRender.h` -- %s %s = `%s`"
                 % (UPSTREAM["project"], UPSTREAM["pin"], UPSTREAM["commit"]))
    lines.append("(SHA256 `%s`, %d bytes)." % (header_sha, header_bytes))
    lines.append("")
    lines.append("Counts: **%d bridged**, **%d modeled constants**, **%d modeled types**"
                 % (counts["bridged"], counts["modeled_constants"], counts["modeled_types"]))
    lines.append("-- **%d declared items, %d gaps**." % (counts["total_declared"], counts["gaps"]))
    lines.append("")
    lines.append("## Bridged functions (loader + bridge + XIOM wrapper)")
    lines.append("")
    lines.append("| RPR function (header line) | bridge symbol(s) | XIOM wrapper(s) |")
    lines.append("|---|---|---|")
    for row in bridged_rows:
        lines.append("| `%s` (L%d) | %s | %s |"
                     % (row["rpr"], row["header_line"],
                        ", ".join("`%s`" % s for s in row["bridge"]),
                        ", ".join("`%s`" % s for s in row["xiom"])))
    lines.append("")
    lines.append("## Modeled constants (value-verified against the header)")
    lines.append("")
    lines.append("| Constant | Header value | Value |")
    lines.append("|---|---|---|")
    for row in const_rows:
        lines.append("| `%s` | `%s` | %d |" % (row["name"], row["header"], row["value"]))
    lines.append("")
    lines.append("## Modeled core types")
    lines.append("")
    lines.append("`" + "`, `".join(t["name"] for t in type_rows) + "`")
    lines.append("")
    lines.append("## Audited non-goals (explicit, not silent gaps)")
    lines.append("")
    for ng in surface["non_goals"]:
        lines.append("- " + ng)
    lines.append("")
    lines.append("Runtime SKIP-when-absent (host library / backend plugins) is a classified")
    lines.append("platform state (SPEC.md sec. 5), not a coverage gap.")
    lines.append("")

    with open(MD_PATH, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))

    if problems:
        for p in problems:
            sys.stderr.write("ERROR %s\n" % p)
        sys.stderr.write("surface_rpr: %d problem(s) -- FAIL\n" % len(problems))
        return 1
    print("surface_rpr: %d bridged + %d constants + %d types = %d declared, 0 gaps -- OK"
          % (counts["bridged"], counts["modeled_constants"], counts["modeled_types"],
             counts["total_declared"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
