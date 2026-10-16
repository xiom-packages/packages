#!/usr/bin/env python3
"""XIOM xiom.gles GLES-surface generator (OpenGL ES 2.0 -> 3.2 core + the
NDK r27b android delta).

Oracles:
  - E:/repos/OpenGL-Registry/xml/gl.xml (KhronosGroup/OpenGL-Registry,
    pinned commit; see PROVENANCE.md) for the core surface and for every
    signature/value of the android delta names.
  - the NDK r27b sysroot GLES2/GLES3/KHR headers (pin
    `27.1.12297006`, same oracle family as the Android wave) for the SET
    of android-delta names (which extensions the Android platform
    declares), clamped to everything the pinned registry can resolve.
    The ES1 headers (GLES/gl.h, GLES/glext.h) are excluded -- documented
    in SPEC.md / docs/COVERAGE.md.

Emits into packages/xiom-gles/src/:
  gles_names.xi            -- gles_cmd_names() + count; gles_load_candidates();
                              gles_android_cmd_names() + GLES_ANDROID_* counts
  gles_cmds_<grp>.xi       -- one typed wrapper per gles2 core command
  gles_consts_<n>.xi       -- core enum values as `pub const ... : Int`
  gles_android_cmds_<grp>.xi  -- one typed wrapper per android-delta command
  gles_android_consts_<n>.xi  -- android-delta enum values
  gles_api.xi              -- GlesApi + gles_api_resolve (module xiom.gles.gles_api)
  gen_gles_manifest.json (packages/xiom-gles/docs/) -- oracle vs emitted +
    skips + the runtime-load candidate list + the android-delta ledger

Deterministic; no hand-maintained lists. Uses only the Python stdlib.
Core set = union of <feature api="gles2"> requires up to GL_ES_VERSION_3_2.
Android delta = names declared by the NDK r27b GLES2/GLES3/KHR headers that
the generated core surface does not already carry (guards/version macros
excluded; ES1 excluded; NDK-only unresolved names skip with a reason).
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
DOCS = os.path.join(ROOT, "docs")
GL_XML = r"E:\repos\OpenGL-Registry\xml\gl.xml"
API = "gles2"
MAX_VERSION = (3, 2)
CMDS_PER_FILE = 100
CONSTS_PER_FILE = 250

# The NDK r27b oracle (same pin as the Android wave; XIOM_ANDROID_NDK
# overrides the root for non-standard SDK layouts).
ANDROID_NDK = os.environ.get("XIOM_ANDROID_NDK", r"C:\Android\sdk\ndk\27.1.12297006")
ANDROID_VERSION = "r27b 27.1.12297006"
ANDROID_INCLUDE = os.path.join(
    ANDROID_NDK, "toolchains", "llvm", "prebuilt", "windows-x86_64",
    "sysroot", "usr", "include")
ANDROID_HEADERS = [
    "GLES2/gl2.h", "GLES2/gl2ext.h",
    "GLES3/gl3.h", "GLES3/gl31.h", "GLES3/gl32.h", "GLES3/gl3ext.h",
    "KHR/khrplatform.h",
]
ANDROID_EXCLUDED_HEADERS = {
    "GLES/gl.h": "ES1 fixed-function surface (out of target: the package binds ES 2.0+)",
    "GLES/glext.h": "ES1 extension pack (ES1-only; libGLESv1_CM.so stays a loader candidate only)",
}

# Runtime-load candidate sonames (GLES side; the EGL side lives in
# gen_egl.py).  Mirrored by the xgs_pairs table in src/gles_probe.c --
# keep both in sync (the suite asserts this list exactly).
GLES_LOAD_CANDIDATES = [
    "libGLESv2.dll", "GLESv2.dll",
    "libGLESv2.so", "libGLESv3.so", "libGLESv1_CM.so",
]

# Bound by hand in the package root (gles.xi) as part of the G2 pin; skipping
# them here keeps a single definition per name for consumers importing both.
ROOT_OWNED_ENUMS = set()

XIOM_KEYWORDS = {
    "as", "break", "const", "continue", "else", "enum", "extern", "false",
    "fn", "for", "if", "impl", "in", "let", "loop", "match", "module",
    "mut", "pub", "requires", "ensures", "return", "struct", "trait",
    "true", "type", "unsafe", "use", "var", "while",
}

TYPE_MAP = {
    "GLenum": "UInt32", "GLboolean": "UInt8", "GLbitfield": "UInt32",
    "GLbyte": "Int8", "GLubyte": "UInt8", "GLshort": "Int16",
    "GLushort": "UInt16", "GLint": "Int32", "GLuint": "UInt32",
    "GLsizei": "Int32", "GLfloat": "Float32", "GLclampf": "Float32",
    "GLdouble": "Float64", "GLclampd": "Float64", "GLchar": "Int8",
    "GLcharARB": "Int8", "GLhandleARB": "UInt32", "GLintptr": "Int",
    "GLsizeiptr": "Int", "GLint64": "Int64", "GLuint64": "UInt64",
    "GLsync": "Int", "GLhalf": "UInt16", "GLhalfARB": "UInt16",
    "GLfixed": "Int32", "GLclampx": "Int32",
    "GLDEBUGPROC": "Int", "GLDEBUGPROCARB": "Int", "GLDEBUGPROCAMD": "Int",
    "GLDEBUGPROCKHR": "Int", "GLVULKANPROCNV": "Int", "GLeglImageOES": "Int",
    # Registry alias types (same widths; ARB/EXT/NV spellings).
    "GLintptrARB": "Int", "GLsizeiptrARB": "Int",
    "GLuint64EXT": "UInt64", "GLint64EXT": "Int64",
    "GLhalfNV": "UInt16", "GLeglClientBufferEXT": "Int",
    "GLvdpauSurfaceNV": "Int",
}

# Opaque foreign structs (OpenCL interop): the pointer is an opaque handle
# slot; B-series: no pointer arithmetic, owned by the caller.
OPAQUE_STRUCT_BASES = {"_cl_context", "_cl_event"}


def norm(text):
    return re.sub(r"\s+", " ", (text or "").strip())


def snake(name):
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name)
    s = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", "_", s)
    s = re.sub(r"__+", "_", s).lower()
    return s


DECL_RE = re.compile(
    r"^(?P<base>[A-Za-z_]\w*)\s*(?P<stars>\*+)?\s*(?P<name>[A-Za-z_]\w*)?$")


def parse_decl(s):
    """Parse a C decl (consts stripped, stars joined) into base/stars/name."""
    s = norm(s)
    s = re.sub(r"\bconst\b", " ", s)
    s = re.sub(r"\bstruct\b", " ", s)
    s = re.sub(r"\s*\*\s*", "*", s)
    s = norm(s)
    m = DECL_RE.match(s)
    if not m:
        raise ValueError("cannot parse decl: %r" % s)
    return m.group("base"), (m.group("stars") or ""), (m.group("name") or "")


def xiom_type(base, stars, where):
    if base == "void":
        if not stars:
            return "Unit"
        return "*UInt8" if len(stars) == 1 else "*UInt8"
    if len(stars) >= 2:
        return "*UInt8"  # pointer-to-pointer: opaque (documented)
    if len(stars) == 1:
        if base in OPAQUE_STRUCT_BASES:
            return "*UInt8"  # opaque foreign struct slot (documented)
        inner = TYPE_MAP.get(base)
        if inner is None:
            raise ValueError("unknown pointer base %r in %s" % (base, where))
        if base == "void":
            return "*UInt8"
        return "*" + inner
    t = TYPE_MAP.get(base)
    if t is None:
        raise ValueError("unknown base %r in %s" % (base, where))
    return t


def load_registry():
    root = ET.parse(GL_XML).getroot()

    # enum name -> value (first definition wins; skip <unused>)
    enums = {}
    enum_alias = {}
    for enums_el in root.findall("./enums"):
        for e in enums_el.findall("enum"):
            name = e.get("name")
            if not name:
                continue
            if "unused" in (e.get("comment") or "") or e.get("value") is None:
                if e.get("alias"):
                    enum_alias[name] = e.get("alias")
                continue
            enums[name] = e.get("value")

    # commands: name -> (ret_type, [(type, name)])
    commands = {}
    for c in root.findall("./commands/command"):
        proto = c.find("proto")
        if proto is None:
            continue
        name_el = proto.find("name")
        if name_el is None or not name_el.text:
            continue
        cname = name_el.text.strip()
        ptext = norm("".join(proto.itertext()))
        # drop the trailing fn name
        ptext = ptext[: ptext.rfind(cname)].strip()
        try:
            base, stars, _ = parse_decl(ptext)
            ret = xiom_type(base, stars, cname + " ret")
        except ValueError as exc:
            commands[cname] = ("__error__:" + str(exc), [])
            continue
        params = []
        ok = True
        for p in c.findall("param"):
            t = norm("".join(p.itertext()))
            try:
                pbase, pstars, pname = parse_decl(t)
                ptype = xiom_type(pbase, pstars, cname + " param " + (pname or "?"))
            except ValueError as exc:
                ok = False
                commands[cname] = ("__error__:" + str(exc), [])
                break
            if not pname:
                pname = "arg%d" % len(params)
            if pname in XIOM_KEYWORDS or pname in ("api", "glres", "glfn"):
                pname = pname + "_"
            params.append((ptype, pname))
        if ok:
            commands[cname] = (ret, params)

    # features api="gl" up to MAX_VERSION: core command/enum sets
    core_cmds = set()
    core_enums = set()
    removed_cmds = set()
    removed_enums = set()
    features_used = []
    for f in root.findall("./feature"):
        if f.get("api") != API:
            continue
        num = f.get("number") or "0.0"
        try:
            major, minor = (int(x) for x in num.split("."))
        except ValueError:
            continue
        if (major, minor) > MAX_VERSION:
            continue
        features_used.append(f.get("name"))
        for req in f.findall("require"):
            prof = req.get("profile")
            if prof == "compatibility":
                continue
            for e in req.findall("enum"):
                if e.get("name"):
                    core_enums.add(e.get("name"))
            for cmd in req.findall("command"):
                if cmd.get("name"):
                    core_cmds.add(cmd.get("name"))
        for rem in f.findall("remove"):
            prof = rem.get("profile")
            if prof == "compatibility":
                continue
            for e in rem.findall("enum"):
                if e.get("name"):
                    removed_enums.add(e.get("name"))
            for cmd in rem.findall("command"):
                if cmd.get("name"):
                    removed_cmds.add(cmd.get("name"))
    core_cmds -= removed_cmds
    core_enums -= removed_enums

    # resolve aliases for enum values
    def enum_value(name, seen=None):
        seen = seen or set()
        if name in enums:
            return enums[name]
        if name in enum_alias and name not in seen:
            seen.add(name)
            return enum_value(enum_alias[name], seen)
        return None

    return commands, core_cmds, core_enums, enum_value, enums, features_used


def parse_int(v):
    v = v.strip()
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


def fmt_int(n):
    if n < 0:
        return str(n)
    return "0x%08X" % n if n <= 0xFFFFFFFF else "0x%016X" % n


def zero_of(t):
    if t == "Float32":
        return "0.0"
    if t == "Float64":
        return "0.0"
    if t.startswith("*"):
        return "0"
    return "0"


# -- android delta (NDK r27b oracle) -----------------------------------------

# A `#define GL_... 1` that the pinned registry does not know as an enum
# value is a preprocessor guard/extension token (e.g. `GL_KHR_debug 1`,
# `GL_GLES_PROTOTYPES 1`, `GL_ES_VERSION_3_0 1`); the android delta must
# not redeclare guards as constants.  Registry-resolved names are always
# real constants.
ANDROID_DEFINE_RE = re.compile(
    r"^#define\s+(GL_[A-Za-z0-9_]+)\s+([^\n/]+)", re.M)
ANDROID_PROTO_RE = re.compile(r"\b(gl[A-Za-z0-9_]+)\s*\(")
ANDROID_INT_RE = re.compile(r"^(0[xX][0-9a-fA-F]+|-?\d+)[uUlL]*$")
ANDROID_TYPEDEF_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\*?$")


def load_android_delta(core_consts, core_names, commands, enum_value):
    """Measure the NDK r27b android delta over the generated core surface.

    Returns (const_delta, cmd_delta, guards, const_skips, cmd_skips,
    per_header_counts).  const_delta: name -> (raw_value, source) where
    source is 'gl.xml' (verbatim pinned registry value) or 'ndk'."""
    missing = [h for h in ANDROID_HEADERS
               if not os.path.isfile(os.path.join(ANDROID_INCLUDE, h.replace("/", os.sep)))]
    if missing:
        raise SystemExit(
            "android oracle headers missing under %s: %s\n"
            "set XIOM_ANDROID_NDK to the NDK root (pin %s)"
            % (ANDROID_INCLUDE, ", ".join(missing), ANDROID_VERSION))

    const_delta = {}
    cmd_delta = {}
    guards = []
    const_skips = []
    cmd_skips = []
    per_header = {}

    for rel in ANDROID_HEADERS:
        path = os.path.join(ANDROID_INCLUDE, rel.replace("/", os.sep))
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        n_const = 0
        n_cmd = 0

        for m in ANDROID_DEFINE_RE.finditer(text):
            name, raw = m.group(1), m.group(2).strip()
            if name in core_consts:
                continue
            if name in const_delta:
                continue
            if any(sk["name"] == name for sk in const_skips):
                continue
            reg = enum_value(name)
            if reg is None and raw == "1":
                guards.append(name)
                continue
            if reg is None and ANDROID_TYPEDEF_RE.match(raw):
                const_skips.append({"name": name, "reason": "typedef macro %r (not an ABI constant)" % raw})
                continue
            if reg is None and not ANDROID_INT_RE.match(raw):
                const_skips.append({"name": name, "reason": "unparsed value %r" % raw})
                continue
            if reg is not None:
                const_delta[name] = (reg, "gl.xml")
            else:
                const_delta[name] = (raw, "ndk")
            n_const += 1

        for m in ANDROID_PROTO_RE.finditer(text):
            cname = m.group(1)
            if cname in core_names or cname in cmd_delta:
                continue
            if cname not in commands:
                cmd_skips.append({"name": cname, "reason": "no pinned-registry signature"})
                continue
            if isinstance(commands[cname][0], str) and commands[cname][0].startswith("__error__"):
                cmd_skips.append({"name": cname, "reason": commands[cname][0]})
                continue
            cmd_delta[cname] = commands[cname]
            n_cmd += 1

        per_header[rel] = {"const_delta": n_const, "cmd_delta": n_cmd}

    return (dict(sorted(const_delta.items())), dict(sorted(cmd_delta.items())),
            sorted(set(guards)), const_skips, cmd_skips, per_header)


def clean_generated(patterns):
    """Remove stale generated files (group counts can shrink on re-pin)."""
    for fn in os.listdir(SRC):
        for pat in patterns:
            if re.match(pat, fn):
                os.remove(os.path.join(SRC, fn))
                break


def main():
    commands, core_cmds, core_enums, enum_value, all_enums, features = \
        load_registry()

    clean_generated([
        r"^gles_cmds_\d+\.xi$", r"^gles_consts_\d+\.xi$",
        r"^gles_android_cmds_\d+\.xi$", r"^gles_android_consts_\d+\.xi$",
        r"^gles_names\.xi$", r"^gles_api\.xi$",
    ])

    # Delta measurement needs the emitted core name/value surface.
    core_const_names = set(n for n in core_enums if n not in ROOT_OWNED_ENUMS)
    core_names = sorted(core_cmds)

    (android_consts, android_cmds, android_guards, android_const_skips,
     android_cmd_skips, android_per_header) = load_android_delta(
        core_const_names, set(core_names), commands, enum_value)

    manifest = {
        "oracle": GL_XML,
        "features": features,
        "core_command_count": len(core_cmds),
        "core_enum_count": len(core_enums),
        "emitted_commands": 0,
        "emitted_consts": 0,
        "command_skips": [],
        "const_skips": [],
        "groups": [],
        "runtime_load": {
            "candidates": GLES_LOAD_CANDIDATES,
            "note": ("mirrored by the xgs_pairs table in src/gles_probe.c; "
                     "Windows ANGLE DLLs retained, Android system sonames added"),
        },
        "android_delta": {
            "oracle_root": ANDROID_INCLUDE,
            "ndk_version": ANDROID_VERSION,
            "headers": ANDROID_HEADERS,
            "excluded_headers": ANDROID_EXCLUDED_HEADERS,
            "guards_excluded": android_guards,
            "const_delta": len(android_consts),
            "cmd_delta": len(android_cmds),
            "emitted_consts": 0,
            "emitted_commands": 0,
            "const_skips": android_const_skips,
            "cmd_skips": android_cmd_skips,
            "groups": [],
            "per_header": android_per_header,
        },
    }

    # ---- emit commands (grouped) ----
    names_sorted = sorted(core_cmds)
    groups = [names_sorted[i:i + CMDS_PER_FILE]
              for i in range(0, len(names_sorted), CMDS_PER_FILE)]
    for gi, group in enumerate(groups, 1):
        gname = "%02d" % gi
        lines = [
            "// GENERATED by tools/gen_gles.py from gl.xml (OpenGL ES %d.%d) -- do not edit."
            % MAX_VERSION,
            "module xiom.gles.gles_cmds_%s" % gname,
            "",
            "use xiom.gles.gles_api;",
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
            lines.extend(emit_wrapper(cname, ret, params))
            manifest["emitted_commands"] += 1
        path = os.path.join(SRC, "gles_cmds_%s.xi" % gname)
        with open(path, "w", encoding="ascii", newline="\n") as fh:
            fh.write("\n".join(lines).rstrip() + "\n")
        manifest["groups"].append({"file": "gles_cmds_%s.xi" % gname, "count": len(group)})

    # ---- emit consts ----
    const_names = sorted(core_const_names)
    chunks = [const_names[i:i + CONSTS_PER_FILE]
              for i in range(0, len(const_names), CONSTS_PER_FILE)]
    for ci, chunk in enumerate(chunks, 1):
        lines = [
            "// GENERATED by tools/gen_gles.py from gl.xml -- do not edit.",
            "module xiom.gles.gles_consts_%d" % ci,
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
        path = os.path.join(SRC, "gles_consts_%d.xi" % ci)
        with open(path, "w", encoding="ascii", newline="\n") as fh:
            fh.write("\n".join(lines).rstrip() + "\n")

    # ---- emit android-delta commands (grouped) ----
    android_names = sorted(android_cmds)
    a_groups = [android_names[i:i + CMDS_PER_FILE]
                for i in range(0, len(android_names), CMDS_PER_FILE)]
    for gi, group in enumerate(a_groups, 1):
        gname = "%02d" % gi
        lines = [
            "// GENERATED by tools/gen_gles.py from the NDK %s GLES2/GLES3/KHR headers" % ANDROID_VERSION,
            "// (android delta; signatures from the pinned gl.xml) -- do not edit.",
            "module xiom.gles.gles_android_cmds_%s" % gname,
            "",
            "use xiom.gles.gles_api;",
            "",
        ]
        for cname in group:
            ret, params = android_cmds[cname]
            lines.extend(emit_wrapper(cname, ret, params))
            manifest["android_delta"]["emitted_commands"] += 1
        path = os.path.join(SRC, "gles_android_cmds_%s.xi" % gname)
        with open(path, "w", encoding="ascii", newline="\n") as fh:
            fh.write("\n".join(lines).rstrip() + "\n")
        manifest["android_delta"]["groups"].append(
            {"file": "gles_android_cmds_%s.xi" % gname, "count": len(group)})

    # ---- emit android-delta consts ----
    a_const_names = sorted(android_consts)
    a_chunks = [a_const_names[i:i + CONSTS_PER_FILE]
                for i in range(0, len(a_const_names), CONSTS_PER_FILE)]
    for ci, chunk in enumerate(a_chunks, 1):
        lines = [
            "// GENERATED by tools/gen_gles.py from the NDK %s GLES2/GLES3/KHR headers" % ANDROID_VERSION,
            "// (android delta; values from the pinned gl.xml where declared) -- do not edit.",
            "module xiom.gles.gles_android_consts_%d" % ci,
            "",
        ]
        for name in chunk:
            raw, _source = android_consts[name]
            try:
                n = parse_int(raw)
            except ValueError:
                manifest["android_delta"]["const_skips"].append(
                    {"name": name, "reason": "unparsed value %r" % raw})
                continue
            lines.append("pub const %s: Int = %s;" % (name, fmt_int(n)))
            manifest["android_delta"]["emitted_consts"] += 1
        path = os.path.join(SRC, "gles_android_consts_%d.xi" % ci)
        with open(path, "w", encoding="ascii", newline="\n") as fh:
            fh.write("\n".join(lines).rstrip() + "\n")
    return manifest


def emit_wrapper(cname, ret, params):
    """One mechanical resolve-per-call wrapper (core + android delta share it)."""
    lines = []
    fname = snake(cname)
    sig = ", ".join("%s: %s" % (pn, pt) for pt, pn in params)
    if sig:
        sig = ", " + sig
    callargs = ", ".join(pn for _, pn in params)
    if ret == "Unit":
        lines.append("pub fn %s(api: &GlesApi%s)" % (fname, sig))
        lines.append("  requires: api.active != 0")
        lines.append("{")
        lines.append("  unsafe {")
        lines.append("    let glres = gles_api_resolve(api, \"%s\".c_str());" % cname)
        lines.append("    if glres != 0 {")
        lines.append("      let glfn = glres as fn(%s);" % ", ".join(
            pt for pt, _ in params) if params else "      let glfn = glres as fn();")
        lines.append("      glfn(%s);" % callargs)
        lines.append("    }")
        lines.append("  }")
        lines.append("}")
    else:
        lines.append("pub fn %s(api: &GlesApi%s) -> %s" % (fname, sig, ret))
        lines.append("  requires: api.active != 0")
        lines.append("{")
        lines.append("  unsafe {")
        lines.append("    let glres = gles_api_resolve(api, \"%s\".c_str());" % cname)
        lines.append("    if glres == 0 { return %s; }" % zero_of(ret))
        lines.append("      let glfn = glres as fn(%s) -> %s;" % (", ".join(
            pt for pt, _ in params), ret) if params
            else "      let glfn = glres as fn() -> %s;" % ret)
        lines.append("      return glfn(%s);" % callargs)
        lines.append("  }")
        lines.append("}")
    lines.append("")
    return lines


def write_names_and_api(manifest):
    commands, core_cmds, core_enums, enum_value, all_enums, features = \
        load_registry()
    names_sorted = sorted(core_cmds)
    (android_consts, android_cmds, _guards, _cs, _ms, _ph) = load_android_delta(
        set(core_enums) - ROOT_OWNED_ENUMS, set(names_sorted), commands, enum_value)
    android_names = sorted(android_cmds)

    # ---- gles_names.xi ----
    lines = [
        "// GENERATED by tools/gen_gles.py from gl.xml + the NDK %s headers -- do not edit." % ANDROID_VERSION,
        "module xiom.gles.gles_names",
        "",
        "pub const GLES_CMD_COUNT: Int = %d;" % len(names_sorted),
        "pub const GLES_ANDROID_CMD_COUNT: Int = %d;" % len(android_names),
        "pub const GLES_ANDROID_CONST_COUNT: Int = %d;" % len(android_consts),
        "pub const GLES_LOAD_CANDIDATE_COUNT: Int = %d;" % len(GLES_LOAD_CANDIDATES),
        "",
        "pub fn gles_cmd_names() -> Vec[Str] {",
        "  var v: Vec[Str] = Vec[Str].new();",
    ]
    for name in names_sorted:
        lines.append("  v.push(\"%s\");" % name)
    lines.append("  return v;")
    lines.append("}")
    lines.append("")
    lines.append("/// The android delta: every command declared by the NDK GLES2/GLES3/KHR")
    lines.append("/// headers beyond the ES 2.0->3.2 core surface (ES1 excluded; see SPEC.md).")
    lines.append("pub fn gles_android_cmd_names() -> Vec[Str] {")
    lines.append("  var v: Vec[Str] = Vec[Str].new();")
    for name in android_names:
        lines.append("  v.push(\"%s\");" % name)
    lines.append("  return v;")
    lines.append("}")
    lines.append("")
    lines.append("/// Runtime-load candidate sonames (GLES side), probed in order by the")
    lines.append("/// bridge: the Windows ANGLE DLLs (retained) then the Android system")
    lines.append("/// libraries.  Mirrors the xgs_pairs table in src/gles_probe.c.")
    lines.append("pub fn gles_load_candidates() -> Vec[Str] {")
    lines.append("  var v: Vec[Str] = Vec[Str].new();")
    for name in GLES_LOAD_CANDIDATES:
        lines.append("  v.push(\"%s\");" % name)
    lines.append("  return v;")
    lines.append("}")
    with open(os.path.join(SRC, "gles_names.xi"), "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")

    # ---- gles_api.xi ----
    api_lines = [
        "// GENERATED by tools/gen_gles.py -- do not edit.",
        "// GlesApi: live-session handle + the per-call proc resolver.",
        "module xiom.gles.gles_api",
        "",
        "use xiom.gles;",
        "",
        "pub type GlesApi = {",
        "  active: Int;",
        "}",
        "",
        "/// Create the API handle for a live session (see gles_session_open).",
        "pub fn gles_api_new() -> GlesApi",
        "  requires: true",
        "{",
        "  return GlesApi{ active: 1 };",
        "}",
        "",
        "/// Resolve a GLES command name through the live session (eglGetProcAddress",
        "/// first, then the runtime GLES/EGL export tables).  0 = unresolved.",
        "pub fn gles_api_resolve(api: &GlesApi, name: *UInt8) -> Int",
        "  requires: api.active != 0",
        "{",
        "  return gles_get_proc(name);",
        "}",
    ]
    with open(os.path.join(SRC, "gles_api.xi"), "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(api_lines) + "\n")

    manifest["android_delta"]["const_delta_names"] = len(android_consts)
    manifest["android_delta"]["cmd_delta_names"] = len(android_names)
    return manifest


def run():
    manifest = main()
    manifest = write_names_and_api(manifest)

    os.makedirs(DOCS, exist_ok=True)
    with open(os.path.join(DOCS, "gen_gles_manifest.json"), "w", encoding="ascii", newline="\n") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
        fh.write("\n")

    print("core commands: %d (emitted %d, skipped %d)" % (
        manifest["core_command_count"], manifest["emitted_commands"],
        len(manifest["command_skips"])))
    print("core enums:    %d (emitted %d, skipped %d)" % (
        manifest["core_enum_count"], manifest["emitted_consts"],
        len(manifest["const_skips"])))
    ad = manifest["android_delta"]
    print("android delta: consts %d (emitted %d, skipped %d), commands %d (emitted %d, skipped %d), guards excluded %d" % (
        ad["const_delta"], ad["emitted_consts"], len(ad["const_skips"]),
        ad["cmd_delta"], ad["emitted_commands"], len(ad["cmd_skips"]),
        len(ad["guards_excluded"])))
    for sk in manifest["command_skips"][:10]:
        print("  skip cmd: %s -- %s" % (sk["name"], sk["reason"]))
    for sk in manifest["const_skips"][:10]:
        print("  skip const: %s -- %s" % (sk["name"], sk["reason"]))
    for sk in ad["cmd_skips"][:10]:
        print("  android skip cmd: %s -- %s" % (sk["name"], sk["reason"]))
    for sk in ad["const_skips"][:10]:
        print("  android skip const: %s -- %s" % (sk["name"], sk["reason"]))
    return 0


if __name__ == "__main__":
    sys.exit(run())
