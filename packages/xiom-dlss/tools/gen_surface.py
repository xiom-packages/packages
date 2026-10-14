#!/usr/bin/env python3
# xiom.dlss -- surface generator (declaration oracle transcription).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# Licensed under the MIT or Apache-2.0 license, at your option.
#
# Reads the PINNED public headers of the reference-only DLSS clone
# (E:\repos\DLSS, git tag v310.9.1 = commit 374959484e79a640feaba44c93ac8cfb0a03f5b5)
# and emits packages/xiom-dlss/surface.xi (module xiom.dlss.surface):
#
#   * NVSDK_NGX_Parameter_*  string keys (complete, deduped) + key table
#   * NVSDK_NGX_EParameter_* effective-key byte codes ("#\xNN" C literals)
#   * the NGX/DLSS entry-point table (per-API core + parameter C API +
#     globals), every name verified against the pinned headers
#
# LICENSE: the DLSS SDK is under the NVIDIA RTX SDKs License (CLOSED,
# reference-only).  NO NVIDIA code, header text, or binary is copied into
# this package; the emitted file contains only interface facts (symbol
# names, key strings, numeric codes) transcribed independently, which is
# the CLOSED-SDK pattern sanctioned for this lane (FFmpeg precedent).
#
# Usage:
#   python tools/gen_surface.py            # from packages/xiom-dlss/
#   python tools/gen_surface.py --check    # regenerate to stdout, diff only

import re
import sys
from pathlib import Path

CLONE = Path(r"E:\repos\DLSS")
PIN_TAG = "v310.9.1"
PIN_COMMIT = "374959484e79a640feaba44c93ac8cfb0a03f5b5"
HEADERS = [
    "nvsdk_ngx.h",
    "nvsdk_ngx_defs.h",
    "nvsdk_ngx_params.h",
    "nvsdk_ngx_vk.h",
    "nvsdk_ngx_defs_dlssd.h",
    "nvsdk_ngx_defs_dlssg.h",
]

# Entry-point table.  (id-name, runtime export spelling, group)
# The declared name is the header declaration; the runtime spelling is the
# export actually resolved from the loaded modules when it differs (observed
# via the SDK static lib's own GetProcAddress strings at the pin).
# Groups: 0 = D3D11, 1 = D3D12, 2 = CUDA, 3 = VULKAN, 4 = parameters, 5 = global.
GROUP_CORE_D3D11 = 0
GROUP_CORE_D3D12 = 1
GROUP_CORE_CUDA = 2
GROUP_CORE_VULKAN = 3
GROUP_PARAMETER = 4
GROUP_GLOBAL = 5

ENTRIES = []
for api, group in (("D3D11", GROUP_CORE_D3D11),
                   ("D3D12", GROUP_CORE_D3D12)):
    for name in ("Init", "Init_Ext", "Shutdown", "Shutdown1", "GetParameters",
                 "AllocateParameters", "GetCapabilityParameters",
                 "DestroyParameters", "GetScratchBufferSize", "CreateFeature",
                 "ReleaseFeature", "EvaluateFeature", "EvaluateFeature_C",
                 "GetFeatureRequirements"):
        ENTRIES.append((f"NVSDK_NGX_{api}_{name}", "", group))
    ENTRIES.append((f"NVSDK_NGX_{api}_Init_with_ProjectID",
                    f"NVSDK_NGX_{api}_Init_ProjectID", group))

for name in ("Init", "Init_Ext", "Init_Ext1", "Shutdown", "Shutdown1",
             "GetParameters", "AllocateParameters", "GetCapabilityParameters",
             "DestroyParameters", "GetScratchBufferSize", "CreateFeature",
             "CreateFeature1", "ReleaseFeature", "EvaluateFeature",
             "EvaluateFeature_C", "GetFeatureRequirements"):
    ENTRIES.append((f"NVSDK_NGX_CUDA_{name}", "", GROUP_CORE_CUDA))
ENTRIES.append(("NVSDK_NGX_CUDA_Init_with_ProjectID",
                "NVSDK_NGX_CUDA_Init_ProjectID", GROUP_CORE_CUDA))

for name in ("RequiredExtensions", "Init", "Init_Ext", "Init_Ext2",
             "Shutdown", "Shutdown1", "GetParameters", "AllocateParameters",
             "GetCapabilityParameters", "DestroyParameters",
             "GetScratchBufferSize", "CreateFeature", "CreateFeature1",
             "ReleaseFeature", "GetFeatureRequirements",
             "GetFeatureInstanceExtensionRequirements",
             "GetFeatureDeviceExtensionRequirements", "EvaluateFeature",
             "EvaluateFeature_C"):
    ENTRIES.append((f"NVSDK_NGX_VULKAN_{name}", "", GROUP_CORE_VULKAN))
ENTRIES.append(("NVSDK_NGX_VULKAN_Init_with_ProjectID",
                "NVSDK_NGX_VULKAN_Init_ProjectID", GROUP_CORE_VULKAN))

for name in ("SetULL", "SetF", "SetD", "SetUI", "SetI", "SetD3d11Resource",
             "SetD3d12Resource", "SetVoidPointer", "GetULL", "GetF", "GetD",
             "GetUI", "GetI", "GetD3d11Resource", "GetD3d12Resource",
             "GetVoidPointer"):
    ENTRIES.append((f"NVSDK_NGX_Parameter_{name}", "", GROUP_PARAMETER))

ENTRIES.append(("NVSDK_NGX_UpdateFeature", "", GROUP_GLOBAL))
ENTRIES.append(("GetNGXResultAsString", "", GROUP_GLOBAL))

PARAM_RE = re.compile(r'^#define\s+(NVSDK_NGX_(?:DLSSG_)?Parameter_\w+)\s+"([^"\\]*)"\s*(?://.*)?$')
EPARAM_RE = re.compile(r'^#define\s+(NVSDK_NGX_EParameter_\w+)\s+"#\\x([0-9a-fA-F]{2})"\s*(?://.*)?$')


def read_headers():
    texts = {}
    for h in HEADERS:
        texts[h] = (CLONE / "include" / h).read_text(encoding="utf-8", errors="strict")
    alltext = "\n".join(texts.values())
    return texts, alltext


def parse_parameters(texts):
    keys = []       # (name, value) in header order, deduped by name
    seen = {}
    for h in HEADERS:
        for line in texts[h].splitlines():
            m = PARAM_RE.match(line)
            if not m:
                continue
            name, value = m.group(1), m.group(2)
            if name in seen:
                if seen[name] != value:
                    raise SystemExit(f"conflicting values for {name}: {seen[name]!r} vs {value!r}")
                continue
            seen[name] = value
            keys.append((name, value))
    return keys


def parse_eparameters(texts):
    codes = []
    seen = {}
    for h in HEADERS:
        for line in texts[h].splitlines():
            m = EPARAM_RE.match(line)
            if not m:
                continue
            name, code = m.group(1), int(m.group(2), 16)
            if name in seen:
                continue
            seen[name] = code
            codes.append((name, code))
    return codes


def verify_entries(alltext):
    missing = []
    runtime_only = []
    for name, runtime, _group in ENTRIES:
        if re.search(r"\b" + re.escape(name) + r"\b", alltext) is None:
            missing.append(name)
        if runtime and re.search(r"\b" + re.escape(runtime) + r"\b", alltext) is None:
            runtime_only.append(runtime)
    if missing:
        raise SystemExit("entry names not found in the pinned headers:\n  " + "\n  ".join(missing))
    if runtime_only:
        # Runtime spellings are facts of the runtime loader surface (observed
        # via the SDK static lib's GetProcAddress strings at the pin), not
        # header declarations -- informational only.
        print("note: runtime spellings not in headers (expected):", ", ".join(runtime_only))


def emit():
    texts, alltext = read_headers()
    verify_entries(alltext)
    params = parse_parameters(texts)
    eparams = parse_eparameters(texts)

    out = []
    w = out.append
    w("// XIOM -- xiom.dlss.surface: generated NGX/DLSS declaration data.")
    w("// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors")
    w("// SPDX-License-Identifier: MIT OR Apache-2.0")
    w("//")
    w("// GENERATED FILE -- do not edit by hand.  Emitted by tools/gen_surface.py")
    w("// from the PINNED public headers of the reference-only DLSS clone")
    w(f"// (E:\\repos\\DLSS, tag {PIN_TAG} = commit {PIN_COMMIT}).")
    w("//")
    w("// The NVIDIA DLSS SDK is under the NVIDIA RTX SDKs License (CLOSED).")
    w("// Nothing from NVIDIA is vendored: this file contains only interface")
    w("// facts (export names, parameter key strings, byte codes) transcribed")
    w("// independently per the CLOSED-SDK pattern (PROVENANCE.md).")
    w("")
    w("module xiom.dlss.surface")
    w("")
    w("use xiom.string.builder;")
    w("")
    w("// =========================================================================")
    w("// Entry table (resolvable NGX/DLSS export surface)")
    w("// =========================================================================")
    w("")
    w("/// Entry group: NVSDK_NGX_D3D11_* core API (15).")
    w(f"pub const DLSS_GROUP_CORE_D3D11: Int = {GROUP_CORE_D3D11};")
    w("/// Entry group: NVSDK_NGX_D3D12_* core API (15).")
    w(f"pub const DLSS_GROUP_CORE_D3D12: Int = {GROUP_CORE_D3D12};")
    w("/// Entry group: NVSDK_NGX_CUDA_* core API (17).")
    w(f"pub const DLSS_GROUP_CORE_CUDA: Int = {GROUP_CORE_CUDA};")
    w("/// Entry group: NVSDK_NGX_VULKAN_* core API (20).")
    w(f"pub const DLSS_GROUP_CORE_VULKAN: Int = {GROUP_CORE_VULKAN};")
    w("/// Entry group: NVSDK_NGX_Parameter_* C parameter API (16).")
    w(f"pub const DLSS_GROUP_PARAMETER: Int = {GROUP_PARAMETER};")
    w("/// Entry group: global entry points (2).")
    w(f"pub const DLSS_GROUP_GLOBAL: Int = {GROUP_GLOBAL};")
    w("")
    w("/// One table row: the header-declared API name, the runtime export")
    w("/// spelling when it differs (\"\" = same as `name`; tried first), and")
    w("/// the group (DLSS_GROUP_*).")
    w("pub type DlssEntryDef = {")
    w("  name: Str;")
    w("  runtime: Str;")
    w("  group: Int;")
    w("}")
    w("")
    w(f"/// The complete declared table: {len(ENTRIES)} entries.")
    w("/// Complexity: O(entries).")
    w("pub fn dlss_table_entries() -> Vec[DlssEntryDef]")
    w("  requires: true")
    w("{")
    w("  var v: Vec[DlssEntryDef] = Vec[DlssEntryDef].new();")
    for name, runtime, group in ENTRIES:
        w(f'  v.push(DlssEntryDef{{ name: "{name}"; runtime: "{runtime}"; group: {group}; }});')
    w("  return v;")
    w("}")
    w("")
    groups = {}
    for _name, _runtime, group in ENTRIES:
        groups[group] = groups.get(group, 0) + 1
    w("/// Per-group entry counts (DLSS_GROUP_*).  The suite cross-checks the")
    w("/// table against these pins.")
    w("/// Complexity: O(1).")
    w("pub fn dlss_group_entry_count(group: Int) -> Int")
    w("  requires: group >= 0")
    w("  requires: group <= 5")
    w("{")
    for g in sorted(groups):
        w(f"  if group == {g} {{ return {groups[g]}; }}")
    w("  return 0;")
    w("}")
    w("")
    w("// =========================================================================")
    w(f"// Parameter keys: {len(params)} NVSDK_NGX_Parameter_* string keys")
    w("// =========================================================================")
    w("")
    for name, value in params:
        w(f'pub const {name}: Str = "{value}";')
    w("")
    w(f"/// The complete parameter-key table ({len(params)} entries, same order)")
    w("/// as the constants above; names only.")
    w("/// Complexity: O(entries).")
    w("pub fn dlss_param_key_table() -> Vec[Str]")
    w("  requires: true")
    w("{")
    w("  var v: Vec[Str] = Vec[Str].new();")
    for name, _value in params:
        w(f'  v.push("{name}");')
    w("  return v;")
    w("}")
    w("")
    w(f"/// Number of declared parameter keys ({len(params)}).")
    w(f"pub const DLSS_PARAM_KEY_COUNT: Int = {len(params)};")
    w("")
    w("// =========================================================================")
    w(f"// Effective keys: {len(eparams)} NVSDK_NGX_EParameter_* byte codes")
    w("// =========================================================================")
    w("// The upstream C name is \"#\" for code 0, else \"#\" + one raw byte")
    w("// with that code (the header spells them \"#\\xNN\").")
    for name, code in eparams:
        w(f"pub const {name}: Int = {code};")
    w("")
    w(f"/// Number of declared effective-key codes ({len(eparams)}).")
    w(f"pub const DLSS_EPARAM_COUNT: Int = {len(eparams)};")
    w("")
    w("/// Build the C key string for an effective-key code: \"#\" for code 0,")
    w("/// else \"#\" followed by the raw byte.  Uses the byte-builder because")
    w("/// XIOM string literals cannot express raw control bytes.")
    w("/// Complexity: O(1).")
    w("pub fn dlss_eparameter_key(code: Int) -> Str")
    w("  requires: code >= 0")
    w("  requires: code <= 255")
    w("{")
    w("  var sb: Vec[UInt8] = builder.sb_new();")
    w('  builder.sb_push_str(&mut sb, "#");')
    w("  if code != 0 {")
    w("    builder.sb_push_byte(&mut sb, code as UInt8);")
    w("  }")
    w("  return builder.sb_to_str(&sb);")
    w("}")
    w("")
    return "\n".join(out), params, eparams


def main():
    text, params, eparams = emit()
    target = Path(__file__).resolve().parent.parent / "src" / "surface.xi"
    if "--check" in sys.argv:
        current = target.read_text(encoding="utf-8") if target.exists() else ""
        print("in sync" if current.replace("\r\n", "\n") == text else "OUT OF SYNC")
        return 0 if current.replace("\r\n", "\n") == text else 1
    with open(target, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(f"wrote {target}: {len(params)} parameter keys, {len(eparams)} effective codes, {len(ENTRIES)} entries")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
