#!/usr/bin/env python3
"""XIOM xiom.opengl WGL-surface generator (WGL extensions + version 1.0).

Oracle: E:/repos/OpenGL-Registry/xml/wgl.xml (KhronosGroup/OpenGL-Registry,
pinned commit; see PROVENANCE.md).  Emits into packages/xiom-opengl/src/:
  wgl_names.xi      -- wgl_cmd_names() + count + wgl_core_names() + count
  wgl_cmds_<grp>.xi -- one typed wrapper per WGL command (module xiom.opengl.wgl_cmds_<grp>)
  wgl_consts_<n>.xi -- WGL enum values as `pub const ... : Int`
  gen_wgl_manifest.json (packages/xiom-opengl/docs/) -- oracle vs emitted + skips

Deterministic; no hand-maintained lists. Uses only the Python stdlib.
Commands are resolved through the live session (`gl_api_resolve` ->
`opengl_get_proc`: wglGetProcAddress first, then the opengl32 export table),
so WGL_VERSION_1_0 exports and driver WGL extensions both work.
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
DOCS = os.path.join(ROOT, "docs")
WGL_XML = r"E:\repos\OpenGL-Registry\xml\wgl.xml"
CMDS_PER_FILE = 100
CONSTS_PER_FILE = 250

XIOM_KEYWORDS = {
    "as", "break", "const", "continue", "else", "enum", "extern", "false",
    "fn", "for", "if", "impl", "in", "let", "loop", "match", "module",
    "mut", "pub", "requires", "ensures", "return", "struct", "trait",
    "true", "type", "unsafe", "use", "var", "while",
}

# Scalar C types -> XIOM scalar types.
SCALAR = {
    # GL scalar types (shared with the core surface)
    "GLbitfield": "UInt32", "GLboolean": "UInt8", "GLbyte": "Int8",
    "GLubyte": "UInt8", "GLshort": "Int16", "GLushort": "UInt16",
    "GLint": "Int32", "GLuint": "UInt32", "GLenum": "UInt32",
    "GLsizei": "Int32",
    "GLfloat": "Float32", "GLdouble": "Float64", "GLchar": "Int8",
    "GLintptr": "Int", "GLsizeiptr": "Int", "GLint64": "Int64",
    "GLuint64": "UInt64",
    # Windows scalar types
    "BOOL": "Int32", "CHAR": "Int8", "char": "Int8", "DWORD": "UInt32",
    "FLOAT": "Float32", "float": "Float32", "INT": "Int32", "int": "Int32",
    "INT32": "Int32", "INT64": "Int64", "UINT": "UInt32", "unsigned": "UInt32",
    "USHORT": "UInt16", "COLORREF": "UInt32", "PROC": "Int",
}

# Pointer-sized handle types -> XIOM Int (raw handle).
HANDLE = {
    "HDC", "HGLRC", "HANDLE", "HENHMETAFILE", "HPBUFFERARB", "HPBUFFEREXT",
    "HGPUNV", "HVIDEOINPUTDEVICENV", "HVIDEOOUTPUTDEVICENV", "HPVIDEODEV",
}

# Pointer typedefs (already pointers) -> opaque pointer.
OPAQUE_PTR = {
    "LPCSTR", "LPVOID", "LPGLYPHMETRICSFLOAT", "LPLAYERPLANEDESCRIPTOR",
    "LPCOLORREF", "PGPU_DEVICE",
}

# Struct types only ever passed by pointer -> opaque pointer at star 1.
STRUCT = {"PIXELFORMATDESCRIPTOR", "LAYERPLANEDESCRIPTOR", "GPU_DEVICE"}


# wingdi.h macros with no exported symbol (they expand to the A/W variants):
# wglUseFontBitmaps -> wglUseFontBitmapsA/W, wglUseFontOutlines -> ...A/W.
WGL_MACRO_ALIASES = {"wglUseFontBitmaps", "wglUseFontOutlines"}


def norm(text):
    return re.sub(r"\s+", " ", (text or "").strip())


def snake(name):
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name)
    s = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", "_", s)
    s = re.sub(r"__+", "_", s).lower()
    return s


def text_without_name(el):
    """Element text with the <name> child removed (types only)."""
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


DECL_RE = re.compile(
    r"^(?P<base>[A-Za-z_]\w*)\s*(?P<stars>\*+)?$")


def parse_ctype(s):
    s = norm(s)
    s = re.sub(r"\bconst\b", " ", s)
    s = s.replace("unsigned int", "unsigned").replace("unsigned long", "unsigned")
    s = s.replace("unsigned short", "USHORT")
    s = re.sub(r"\s*\*\s*", "*", s)
    s = norm(s)
    m = DECL_RE.match(s)
    if not m:
        raise ValueError("cannot parse decl: %r" % s)
    return m.group("base"), (m.group("stars") or "")


def xiom_type(base, stars, where):
    if base == "void":
        return "Unit" if not stars else "*UInt8"
    if base == "VOID":
        return "Unit" if not stars else "*UInt8"
    if len(stars) >= 2:
        return "*UInt8"  # pointer-to-pointer: opaque (documented)
    if stars:
        if base in ("char", "CHAR", "GLchar", "GLcharARB"):
            return "*UInt8"  # C strings -> *UInt8 (Str::from_c_str)
        if base in SCALAR:
            return "*" + SCALAR[base]
        if base in HANDLE or base in OPAQUE_PTR or base in STRUCT:
            return "*UInt8"  # opaque slot (handle/struct/pointer typedef)
        raise ValueError("unknown pointer base %r in %s" % (base, where))
    if base in SCALAR:
        return SCALAR[base]
    if base in HANDLE:
        return "Int"
    if base in OPAQUE_PTR:
        return "*UInt8"
    raise ValueError("unknown base %r in %s" % (base, where))


def load_registry():
    root = ET.parse(WGL_XML).getroot()
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
            if pname in XIOM_KEYWORDS:
                pname = pname + "_"
            params.append((ptype, pname))
        if ok:
            commands[cname] = (ret, params)

    # feature WGL_VERSION_1_0 command set (the opengl32 export surface)
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
    if t in ("Float32", "Float64"):
        return "0.0"
    return "0"


def main():
    commands, core_cmds, features_used, extensions, ext_cmds, enum_value, all_enums = load_registry()

    all_names = sorted(set(commands) | set(core_cmds) | set(ext_cmds))
    manifest = {
        "oracle": WGL_XML,
        "registry_pin": "OpenGL-Registry 6af574a14089ccfee87efe230ebcdd8742859813",
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
    }

    # ---- emit commands (grouped) ----
    groups = [all_names[i:i + CMDS_PER_FILE]
              for i in range(0, len(all_names), CMDS_PER_FILE)]
    for gi, group in enumerate(groups, 1):
        gname = "%02d" % gi
        lines = [
            "// GENERATED by tools/gen_wgl.py from wgl.xml (WGL extensions + 1.0) -- do not edit.",
            "module xiom.opengl.wgl_cmds_%s" % gname,
            "",
            "use xiom.opengl.glapi;",
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
            fname = "wgl_" + snake(cname[3:] if cname.startswith("wgl") else cname)
            sig = ", ".join("%s: %s" % (pn, pt) for pt, pn in params)
            if sig:
                sig = ", " + sig
            callargs = ", ".join(pn for _, pn in params)
            if ret == "Unit":
                lines.append("pub fn %s(api: &GlApi%s)" % (fname, sig))
                lines.append("  requires: api.active != 0")
                lines.append("{")
                lines.append("  unsafe {")
                lines.append("    let wglres = gl_api_resolve(api, \"%s\".c_str());" % cname)
                lines.append("    if wglres != 0 {")
                fmt = ", ".join(pt for pt, _ in params)
                lines.append("      let wglfn = wglres as fn(%s);" % fmt if fmt
                             else "      let wglfn = wglres as fn();")
                lines.append("      wglfn(%s);" % callargs)
                lines.append("    }")
                lines.append("  }")
                lines.append("}")
            else:
                lines.append("pub fn %s(api: &GlApi%s) -> %s" % (fname, sig, ret))
                lines.append("  requires: api.active != 0")
                lines.append("{")
                lines.append("  unsafe {")
                lines.append("    let wglres = gl_api_resolve(api, \"%s\".c_str());" % cname)
                lines.append("    if wglres == 0 { return %s; }" % zero_of(ret))
                fmt = ", ".join(pt for pt, _ in params)
                lines.append("    let wglfn = wglres as fn(%s) -> %s;" % (fmt, ret) if fmt
                             else "    let wglfn = wglres as fn() -> %s;" % ret)
                lines.append("    return wglfn(%s);" % callargs)
                lines.append("  }")
                lines.append("}")
            lines.append("")
            manifest["emitted_commands"] += 1
        path = os.path.join(SRC, "wgl_cmds_%s.xi" % gname)
        with open(path, "w", encoding="ascii", newline="\n") as fh:
            fh.write("\n".join(lines).rstrip() + "\n")
        manifest["groups"].append({"file": "wgl_cmds_%s.xi" % gname, "count": len(group)})

    # ---- emit consts ----
    const_names = sorted(all_enums)
    chunks = [const_names[i:i + CONSTS_PER_FILE]
              for i in range(0, len(const_names), CONSTS_PER_FILE)]
    for ci, chunk in enumerate(chunks, 1):
        lines = [
            "// GENERATED by tools/gen_wgl.py from wgl.xml -- do not edit.",
            "module xiom.opengl.wgl_consts_%d" % ci,
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
        path = os.path.join(SRC, "wgl_consts_%d.xi" % ci)
        with open(path, "w", encoding="ascii", newline="\n") as fh:
            fh.write("\n".join(lines).rstrip() + "\n")

    # ---- wgl_names.xi ----
    core_resolvable = [n for n in sorted(core_cmds) if n not in WGL_MACRO_ALIASES]
    lines = [
        "// GENERATED by tools/gen_wgl.py from wgl.xml -- do not edit.",
        "module xiom.opengl.wgl_names",
        "",
        "pub const WGL_CMD_COUNT: Int = %d;" % len(all_names),
        "pub const WGL_CORE_COUNT: Int = %d;" % len(core_cmds),
        "pub const WGL_CORE_RESOLVABLE_COUNT: Int = %d;" % len(core_resolvable),
        "",
        "pub fn wgl_cmd_names() -> Vec[Str] {",
        "  var v: Vec[Str] = Vec[Str].new();",
    ]
    for name in all_names:
        lines.append("  v.push(\"%s\");" % name)
    lines.append("  return v;")
    lines.append("}")
    lines.append("")
    lines.append("// WGL_VERSION_1_0 minus the wingdi.h macro aliases (no exported")
    lines.append("// symbol; they expand to the A/W variants, which are in the full list).")
    lines.append("pub fn wgl_core_names() -> Vec[Str] {")
    lines.append("  var v: Vec[Str] = Vec[Str].new();")
    for name in core_resolvable:
        lines.append("  v.push(\"%s\");" % name)
    lines.append("  return v;")
    lines.append("}")
    with open(os.path.join(SRC, "wgl_names.xi"), "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")

    manifest["core_macro_aliases"] = sorted(n for n in core_cmds if n in WGL_MACRO_ALIASES)
    manifest["core_resolvable_count"] = len(core_resolvable)

    os.makedirs(DOCS, exist_ok=True)
    with open(os.path.join(DOCS, "gen_wgl_manifest.json"), "w", encoding="ascii", newline="\n") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
        fh.write("\n")

    print("wgl commands: %d (core %d [%d resolvable], ext %d; emitted %d, skipped %d)" % (
        manifest["command_count"], manifest["core_command_count"],
        manifest["core_resolvable_count"], manifest["extension_command_count"],
        manifest["emitted_commands"], len(manifest["command_skips"])))
    print("wgl enums:    %d (emitted %d, skipped %d)" % (
        manifest["enum_count"], manifest["emitted_consts"],
        len(manifest["const_skips"])))
    for sk in manifest["command_skips"][:10]:
        print("  skip cmd: %s -- %s" % (sk["name"], sk["reason"]))
    for sk in manifest["const_skips"][:10]:
        print("  skip const: %s -- %s" % (sk["name"], sk["reason"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
