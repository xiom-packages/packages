#!/usr/bin/env python3
"""XIOM xiom.gles EGL-surface generator (EGL 1.0 -> 1.5 + all extensions).

Oracle: E:/repos/EGL-Registry/api/egl.xml (KhronosGroup/EGL-Registry, pinned
commit; see PROVENANCE.md).  Emits into packages/xiom-gles/src/:
  egl_names.xi      -- egl_cmd_names() + count + egl_core_names() + count +
                       egl_load_candidates() (runtime-load sonames)
  egl_cmds_<grp>.xi -- one typed wrapper per EGL command
  egl_consts_<n>.xi -- EGL enum values as `pub const ... : Int`
  egl_api.xi        -- EglApi + egl_api_resolve (module xiom.gles.egl_api)
  gen_egl_manifest.json (packages/xiom-gles/docs/) -- oracle vs emitted +
    skips + the runtime-load candidate list + the android-delta measurement

The manifest also MEASURES the android delta over the NDK r27b EGL headers
(same pin as the Android wave): every declared EGL constant and entry point
not already carried by the generated surface.  At the r27b pin the measured
delta is empty (the pin `27.1.12297006` declares nothing beyond the pinned
registry surface) -- the generator fails loudly when that changes so the
delta gets declared instead of drifting by.

Deterministic; no hand-maintained lists. Uses only the Python stdlib.
Commands are resolved through the live session (`egl_api_resolve` ->
`gles_egl_proc`: eglGetProcAddress first, then the libEGL export table).
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
DOCS = os.path.join(ROOT, "docs")
EGL_XML = r"E:\repos\EGL-Registry\api\egl.xml"
CMDS_PER_FILE = 100
CONSTS_PER_FILE = 250

# The NDK r27b oracle (same pin as the Android wave; XIOM_ANDROID_NDK
# overrides the root for non-standard SDK layouts).
ANDROID_NDK = os.environ.get("XIOM_ANDROID_NDK", r"C:\Android\sdk\ndk\27.1.12297006")
ANDROID_VERSION = "r27b 27.1.12297006"
ANDROID_INCLUDE = os.path.join(
    ANDROID_NDK, "toolchains", "llvm", "prebuilt", "windows-x86_64",
    "sysroot", "usr", "include")
ANDROID_HEADERS = ["EGL/egl.h", "EGL/eglext.h"]

# Runtime-load candidate sonames (EGL side; the GLES side lives in
# gen_gles.py).  Mirrored by the xgs_pairs table in src/gles_probe.c --
# keep both in sync (the suite asserts this list exactly).
EGL_LOAD_CANDIDATES = ["libEGL.dll", "EGL.dll", "libEGL.so"]

XIOM_KEYWORDS = {
    "as", "break", "const", "continue", "else", "enum", "extern", "false",
    "fn", "for", "if", "impl", "in", "let", "loop", "match", "module",
    "mut", "pub", "requires", "ensures", "return", "struct", "trait",
    "true", "type", "unsafe", "use", "var", "while",
}

# Scalar EGL/aux C types -> XIOM scalar types.
SCALAR = {
    "EGLBoolean": "UInt32", "EGLint": "Int32", "EGLenum": "UInt32",
    "EGLAttrib": "Int", "EGLTime": "UInt64", "EGLTimeKHR": "UInt64",
    "EGLTimeNV": "UInt64", "EGLuint64KHR": "UInt64", "EGLuint64NV": "UInt64",
    "EGLnsecsANDROID": "Int64", "EGLNativeFileDescriptorKHR": "Int32",
    "int": "Int32", "unsigned": "UInt32", "char": "Int8", "float": "Float32",
    "void": "Unit", "khronos_int64_t": "Int64", "khronos_uint64_t": "UInt64",
}

# Pointer-sized handle types -> XIOM Int (raw handle).
HANDLE = {
    "EGLDisplay", "EGLConfig", "EGLSurface", "EGLContext", "EGLImage",
    "EGLImageKHR", "EGLSync", "EGLSyncKHR", "EGLSyncNV", "EGLStreamKHR",
    "EGLDeviceEXT", "EGLOutputLayerEXT", "EGLOutputPortEXT", "EGLObjectKHR",
    "EGLLabelKHR", "EGLClientBuffer", "EGLNativeDisplayType",
    "EGLNativeWindowType", "EGLNativePixmapType", "EGLDEBUGPROCKHR",
    "EGLSetBlobFuncANDROID", "EGLGetBlobFuncANDROID",
    "__eglMustCastToProperFunctionPointerType", "EGLNativeFileDescriptorKHR",
}


def norm(text):
    return re.sub(r"\s+", " ", (text or "").strip())


def snake(name):
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name)
    s = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", "_", s)
    s = re.sub(r"__+", "_", s).lower()
    return s


def text_without_name(el):
    parts = []
    if el.text:
        parts.append(el.text)
    for child in el:
        if child.tag == "name":
            if child.tail:
                parts.append(child.tail)
            continue
        parts.append("".join(child.itertext()))
        if child.tail:
            parts.append(child.tail)
    return norm(" ".join(parts))


DECL_RE = re.compile(r"^(?P<base>[A-Za-z_]\w*)\s*(?P<stars>\*+)?$")


def parse_ctype(s):
    s = norm(s)
    s = re.sub(r"\bconst\b", " ", s)
    s = re.sub(r"\bstruct\b", " ", s)
    s = s.replace("unsigned int", "unsigned").replace("unsigned long", "unsigned")
    s = s.replace("unsigned short", "UInt16")
    s = re.sub(r"\s*\*\s*", "*", s)
    s = norm(s)
    m = DECL_RE.match(s)
    if not m:
        raise ValueError("cannot parse decl: %r" % s)
    return m.group("base"), (m.group("stars") or "")


def xiom_type(base, stars, where):
    if base in ("void", "VOID"):
        return "Unit" if not stars else "*UInt8"
    if len(stars) >= 2:
        return "*UInt8"  # pointer-to-pointer: opaque (documented)
    if stars:
        if base in ("char", "CHAR"):
            return "*UInt8"  # C strings -> *UInt8 (Str::from_c_str)
        if base in SCALAR and SCALAR[base] != "Unit":
            return "*" + SCALAR[base]
        return "*UInt8"  # handle slot / struct / opaque pointer (documented)
    if base in SCALAR:
        return SCALAR[base]
    if base in HANDLE:
        return "Int"
    raise ValueError("unknown base %r in %s" % (base, where))


def load_registry():
    root = ET.parse(EGL_XML).getroot()

    enums = {}
    enum_alias = {}
    for enums_el in root.findall("./enums"):
        for e in enums_el.findall("enum"):
            name = e.get("name")
            if not name:
                continue
            if e.get("value") is None:
                if e.get("alias"):
                    enum_alias[name] = e.get("alias")
                continue
            enums[name] = e.get("value")

    commands = {}
    for c in root.findall("./commands/command"):
        proto = c.find("proto")
        name_el = proto.find("name")
        if name_el is None or not name_el.text:
            continue
        cname = name_el.text.strip()
        try:
            base, stars = parse_ctype(text_without_name(proto))
            ret = xiom_type(base, stars, cname + " ret")
        except ValueError as exc:
            commands[cname] = ("__error__:" + str(exc), [])
            continue
        params = []
        ok = True
        for p in c.findall("param"):
            pname_el = p.find("name")
            pname = pname_el.text.strip() if (pname_el is not None and pname_el.text) else ""
            try:
                pbase, pstars = parse_ctype(text_without_name(p))
                ptype = xiom_type(pbase, pstars, cname + " param " + (pname or "?"))
            except ValueError as exc:
                ok = False
                commands[cname] = ("__error__:" + str(exc), [])
                break
            if not pname:
                pname = "arg%d" % len(params)
            else:
                pname = snake(pname)
            if pname in XIOM_KEYWORDS or pname in ("api", "eglres", "eglfn"):
                pname = pname + "_"
            params.append((ptype, pname))
        if ok:
            commands[cname] = (ret, params)

    # feature command sets (EGL 1.0 -> 1.5)
    core_cmds = []
    features_used = []
    for f in root.findall("./feature"):
        features_used.append("%s %s" % (f.get("name"), f.get("number") or ""))
        for req in f.findall("require"):
            for cmd in req.findall("command"):
                if cmd.get("name"):
                    core_cmds.append(cmd.get("name"))

    extensions_used = []
    ext_cmds = set()
    for ext in root.findall("./extensions/extension"):
        supported = ext.get("supported")
        if supported and supported != "egl":
            continue
        extensions_used.append(ext.get("name"))
        for req in ext.findall("require"):
            for cmd in req.findall("command"):
                if cmd.get("name"):
                    ext_cmds.add(cmd.get("name"))

    def enum_value(name, seen=None):
        seen = seen or set()
        if name in enums:
            return enums[name]
        if name in enum_alias and name not in seen:
            seen.add(name)
            return enum_value(enum_alias[name], seen)
        return None

    return commands, core_cmds, features_used, extensions_used, ext_cmds, enum_value, enums


def parse_int(v):
    v = v.strip()
    m = re.match(r"^EGL_CAST\(\s*[A-Za-z_]\w*\s*,\s*([^)]+)\)$", v)
    if m:
        v = m.group(1).strip()
    if v.lower().startswith("0x"):
        digits = v[2:]
        if digits and digits[-1] in "uUlL":
            digits = digits.rstrip("uUlL")
        n = int(digits, 16)
    else:
        v2 = v.rstrip("uUlL")
        n = int(v2, 10)
    if n > 0x7FFFFFFFFFFFFFFF:
        n -= 1 << 64
    return n


EGL_ANDROID_DEFINE_RE = re.compile(
    r"^#define\s+(EGL_[A-Za-z0-9_]+)\s+([^\n/]+)", re.M)
EGL_ANDROID_PROTO_RE = re.compile(r"\b(egl[A-Za-z0-9_]+)\s*\(")


def measure_android(generated_consts, generated_names):
    """Measure the android delta over the NDK r27b EGL headers.

    Returns (const_delta, cmd_delta, guards, version_macros, const_skips).
    Any real delta means the NDK declares EGL surface beyond the pinned
    registry -- it must be declared (extend the emission) instead of
    drifting; main() fails loudly on a non-empty delta."""
    missing = [h for h in ANDROID_HEADERS
               if not os.path.isfile(os.path.join(ANDROID_INCLUDE, h.replace("/", os.sep)))]
    if missing:
        raise SystemExit(
            "android oracle headers missing under %s: %s\n"
            "set XIOM_ANDROID_NDK to the NDK root (pin %s)"
            % (ANDROID_INCLUDE, ", ".join(missing), ANDROID_VERSION))

    const_delta = {}
    cmd_delta = set()
    guards = []
    version_macros = []
    const_skips = []

    for rel in ANDROID_HEADERS:
        path = os.path.join(ANDROID_INCLUDE, rel.replace("/", os.sep))
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        for m in EGL_ANDROID_DEFINE_RE.finditer(text):
            name, raw = m.group(1), m.group(2).strip()
            if name in generated_consts or name in const_delta:
                continue
            if name == "EGL_EGLEXT_VERSION":
                version_macros.append(name)
                continue
            try:
                n = parse_int(raw)
            except ValueError:
                const_skips.append({"name": name, "reason": "unparsed value %r" % raw})
                continue
            # A value-1 define the registry does not carry as an enum value
            # is a guard/extension token (`EGL_KHR_debug 1`,
            # `EGL_VERSION_1_5 1`, ...); never an ABI constant.
            if n == 1 and name not in generated_consts:
                guards.append(name)
                continue
            const_delta[name] = raw
        for m in EGL_ANDROID_PROTO_RE.finditer(text):
            cname = m.group(1)
            if cname in generated_names:
                continue
            cmd_delta.add(cname)

    return (dict(sorted(const_delta.items())), sorted(cmd_delta),
            sorted(set(guards)), sorted(set(version_macros)), const_skips)


def fmt_int(n):
    if n < 0:
        return str(n)
    return "0x%08X" % n if n <= 0xFFFFFFFF else "0x%016X" % n


def zero_of(t):
    if t in ("Float32", "Float64"):
        return "0.0"
    return "0"


def clean_generated(patterns):
    """Remove stale generated files (group counts can shrink on re-pin)."""
    for fn in os.listdir(SRC):
        for pat in patterns:
            if re.match(pat, fn):
                os.remove(os.path.join(SRC, fn))
                break


def main():
    commands, core_cmds, features_used, extensions, ext_cmds, enum_value, all_enums = load_registry()

    clean_generated([
        r"^egl_cmds_\d+\.xi$", r"^egl_consts_\d+\.xi$",
        r"^egl_names\.xi$", r"^egl_api\.xi$",
    ])

    all_names = sorted(set(commands) | set(core_cmds) | set(ext_cmds))

    # android-delta measurement (NDK r27b EGL headers, clamped to the
    # generated surface; see measure_android).
    generated_consts = set(n for n in all_enums if enum_value(n) is not None)
    (android_consts, android_cmds, android_guards, android_version_macros,
     android_const_skips) = measure_android(generated_consts, set(all_names))

    manifest = {
        "oracle": EGL_XML,
        "registry_pin": "EGL-Registry db3425b8246136faccb5e2782b5694960bd6edf1",
        "features": features_used,
        "extensions_declared": len(extensions),
        "command_count": len(all_names),
        "core_command_count": len(core_cmds),
        "extension_command_count": len(ext_cmds),
        "enum_count": len(all_enums),
        "emitted_commands": 0,
        "emitted_consts": 0,
        "command_skips": [],
        "const_skips": [],
        "groups": [],
        "runtime_load": {
            "candidates": EGL_LOAD_CANDIDATES,
            "note": ("mirrored by the xgs_pairs table in src/gles_probe.c; "
                     "Windows ANGLE DLLs retained, Android system soname added"),
        },
        "android_delta": {
            "oracle_root": ANDROID_INCLUDE,
            "ndk_version": ANDROID_VERSION,
            "headers": ANDROID_HEADERS,
            "const_delta": sorted(android_consts),
            "cmd_delta": android_cmds,
            "guards_excluded": android_guards,
            "version_macros_excluded": android_version_macros,
            "const_skips": android_const_skips,
            "note": ("empty delta = the r27b EGL headers declare nothing beyond "
                     "the pinned registry surface (measured)"),
        },
    }

    # ---- emit commands (grouped) ----
    groups = [all_names[i:i + CMDS_PER_FILE]
              for i in range(0, len(all_names), CMDS_PER_FILE)]
    for gi, group in enumerate(groups, 1):
        gname = "%02d" % gi
        lines = [
            "// GENERATED by tools/gen_egl.py from egl.xml (EGL 1.0-1.5 + extensions) -- do not edit.",
            "module xiom.gles.egl_cmds_%s" % gname,
            "",
            "use xiom.gles.egl_api;",
            "",
        ]
        for cname in group:
            ret, params = commands.get(cname, ("__missing__", []))
            if isinstance(ret, str) and ret.startswith("__error__"):
                manifest["command_skips"].append({"name": cname, "reason": ret})
                continue
            if ret == "__missing__":
                manifest["command_skips"].append({"name": cname, "reason": "not in <commands>"})
                continue
            fname = "egl_" + snake(cname[3:] if cname.startswith("egl") else cname)
            sig = ", ".join("%s: %s" % (pn, pt) for pt, pn in params)
            if sig:
                sig = ", " + sig
            callargs = ", ".join(pn for _, pn in params)
            if ret == "Unit":
                lines.append("pub fn %s(api: &EglApi%s)" % (fname, sig))
                lines.append("  requires: api.active != 0")
                lines.append("{")
                lines.append("  unsafe {")
                lines.append("    let eglres = egl_api_resolve(api, \"%s\".c_str());" % cname)
                lines.append("    if eglres != 0 {")
                fmt = ", ".join(pt for pt, _ in params)
                lines.append("      let eglfn = eglres as fn(%s);" % fmt if fmt
                             else "      let eglfn = eglres as fn();")
                lines.append("      eglfn(%s);" % callargs)
                lines.append("    }")
                lines.append("  }")
                lines.append("}")
            else:
                lines.append("pub fn %s(api: &EglApi%s) -> %s" % (fname, sig, ret))
                lines.append("  requires: api.active != 0")
                lines.append("{")
                lines.append("  unsafe {")
                lines.append("    let eglres = egl_api_resolve(api, \"%s\".c_str());" % cname)
                lines.append("    if eglres == 0 { return %s; }" % zero_of(ret))
                fmt = ", ".join(pt for pt, _ in params)
                lines.append("    let eglfn = eglres as fn(%s) -> %s;" % (fmt, ret) if fmt
                             else "    let eglfn = eglres as fn() -> %s;" % ret)
                lines.append("    return eglfn(%s);" % callargs)
                lines.append("  }")
                lines.append("}")
            lines.append("")
            manifest["emitted_commands"] += 1
        path = os.path.join(SRC, "egl_cmds_%s.xi" % gname)
        with open(path, "w", encoding="ascii", newline="\n") as fh:
            fh.write("\n".join(lines).rstrip() + "\n")
        manifest["groups"].append({"file": "egl_cmds_%s.xi" % gname, "count": len(group)})

    # ---- emit consts ----
    const_names = sorted(all_enums)
    chunks = [const_names[i:i + CONSTS_PER_FILE]
              for i in range(0, len(const_names), CONSTS_PER_FILE)]
    for ci, chunk in enumerate(chunks, 1):
        lines = [
            "// GENERATED by tools/gen_egl.py from egl.xml -- do not edit.",
            "module xiom.gles.egl_consts_%d" % ci,
            "",
        ]
        for name in chunk:
            raw = enum_value(name)
            if raw is None:
                manifest["const_skips"].append({"name": name, "reason": "no value"})
                continue
            try:
                n = parse_int(raw)
            except ValueError:
                manifest["const_skips"].append({"name": name, "reason": "unparsed value %r" % raw})
                continue
            lines.append("pub const %s: Int = %s;" % (name, fmt_int(n)))
            manifest["emitted_consts"] += 1
        path = os.path.join(SRC, "egl_consts_%d.xi" % ci)
        with open(path, "w", encoding="ascii", newline="\n") as fh:
            fh.write("\n".join(lines).rstrip() + "\n")

    # ---- egl_names.xi ----
    lines = [
        "// GENERATED by tools/gen_egl.py from egl.xml -- do not edit.",
        "module xiom.gles.egl_names",
        "",
        "pub const EGL_CMD_COUNT: Int = %d;" % len(all_names),
        "pub const EGL_CORE_COUNT: Int = %d;" % len(core_cmds),
        "pub const EGL_LOAD_CANDIDATE_COUNT: Int = %d;" % len(EGL_LOAD_CANDIDATES),
        "",
        "pub fn egl_cmd_names() -> Vec[Str] {",
        "  var v: Vec[Str] = Vec[Str].new();",
    ]
    for name in all_names:
        lines.append("  v.push(\"%s\");" % name)
    lines.append("  return v;")
    lines.append("}")
    lines.append("")
    lines.append("// EGL 1.0-1.5 feature command set (the libEGL export surface).")
    lines.append("pub fn egl_core_names() -> Vec[Str] {")
    lines.append("  var v: Vec[Str] = Vec[Str].new();")
    for name in sorted(core_cmds):
        lines.append("  v.push(\"%s\");" % name)
    lines.append("  return v;")
    lines.append("}")
    lines.append("")
    lines.append("// Runtime-load candidate sonames (EGL side), probed in order by the")
    lines.append("// bridge: the Windows ANGLE DLLs (retained) then the Android system")
    lines.append("// library.  Mirrors the xgs_pairs table in src/gles_probe.c.")
    lines.append("pub fn egl_load_candidates() -> Vec[Str] {")
    lines.append("  var v: Vec[Str] = Vec[Str].new();")
    for name in EGL_LOAD_CANDIDATES:
        lines.append("  v.push(\"%s\");" % name)
    lines.append("  return v;")
    lines.append("}")
    with open(os.path.join(SRC, "egl_names.xi"), "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")

    # ---- egl_api.xi ----
    api_lines = [
        "// GENERATED by tools/gen_egl.py -- do not edit.",
        "// EglApi: live-session handle + the per-call proc resolver.",
        "module xiom.gles.egl_api",
        "",
        "use xiom.gles;",
        "",
        "pub type EglApi = {",
        "  active: Int;",
        "}",
        "",
        "/// Create the API handle for a live session (see gles_session_open).",
        "pub fn egl_api_new() -> EglApi",
        "  requires: true",
        "{",
        "  return EglApi{ active: 1 };",
        "}",
        "",
        "/// Resolve an EGL command name through the live session (eglGetProcAddress",
        "/// first, then the libEGL export table).  0 = unresolved.",
        "pub fn egl_api_resolve(api: &EglApi, name: *UInt8) -> Int",
        "  requires: api.active != 0",
        "{",
        "  return gles_egl_proc(name);",
        "}",
    ]
    with open(os.path.join(SRC, "egl_api.xi"), "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(api_lines) + "\n")

    os.makedirs(DOCS, exist_ok=True)
    with open(os.path.join(DOCS, "gen_egl_manifest.json"), "w", encoding="ascii", newline="\n") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
        fh.write("\n")

    print("egl commands: %d (core %d, ext %d; emitted %d, skipped %d)" % (
        manifest["command_count"], manifest["core_command_count"],
        manifest["extension_command_count"], manifest["emitted_commands"],
        len(manifest["command_skips"])))
    print("egl enums:    %d (emitted %d, skipped %d)" % (
        manifest["enum_count"], manifest["emitted_consts"],
        len(manifest["const_skips"])))
    ad = manifest["android_delta"]
    print("android delta: consts %d, commands %d (measured over the NDK %s EGL headers; guards %d, version macros %d excluded)" % (
        len(ad["const_delta"]), len(ad["cmd_delta"]), ANDROID_VERSION,
        len(ad["guards_excluded"]), len(ad["version_macros_excluded"])))
    for sk in manifest["command_skips"][:10]:
        print("  skip cmd: %s -- %s" % (sk["name"], sk["reason"]))
    for sk in manifest["const_skips"][:10]:
        print("  skip const: %s -- %s" % (sk["name"], sk["reason"]))
    if ad["const_delta"] or ad["cmd_delta"]:
        print("ERROR: the NDK %s EGL headers declare surface beyond the generated set." % ANDROID_VERSION)
        print("       Declare it (extend the emission or document an exclusion) before re-pinning.")
        print("       consts: %s" % ", ".join(ad["const_delta"][:20]))
        print("       commands: %s" % ", ".join(ad["cmd_delta"][:20]))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
