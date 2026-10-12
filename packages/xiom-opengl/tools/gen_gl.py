#!/usr/bin/env python3
"""XIOM xiom.opengl full-surface generator (OpenGL core profile 4.6).

Oracle: E:/repos/OpenGL-Registry/xml/gl.xml (KhronosGroup/OpenGL-Registry,
pinned commit; see PROVENANCE.md).  Emits into packages/xiom-opengl/src/:
  names.xi        -- gl_cmd_names() + count (core profile commands)
  cmds_<grp>.xi   -- one typed wrapper per core command (module xiom.opengl.cmds_<grp>)
  consts_<n>.xi   -- core enum values as `pub const ... : Int`
  gl_api.xi       -- GlApi + gl_api_resolve (module xiom.opengl.glapi)
  gen_manifest.json (packages/xiom-opengl/docs/) -- oracle vs emitted counts + skips

Deterministic; no hand-maintained lists. Uses only the Python stdlib.
Core profile set = union of <feature api="gl"> requires up to GL_VERSION_4_6
(profile core/no-profile), minus <remove profile="core"> entries.
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
MAX_VERSION = (4, 6)
CMDS_PER_FILE = 100
CONSTS_PER_FILE = 250

# Bound by hand in the package root (opengl.xi) as part of the G2 pin; skipping
# them here keeps a single definition per name for consumers importing both.
ROOT_OWNED_ENUMS = {
    "GL_VENDOR", "GL_RENDERER", "GL_VERSION", "GL_EXTENSIONS",
    "GL_SHADING_LANGUAGE_VERSION",
}

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
    "GLVULKANPROCNV": "Int",
}


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
            if pname in XIOM_KEYWORDS:
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
        if f.get("api") != "gl":
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


def main():
    commands, core_cmds, core_enums, enum_value, all_enums, features = \
        load_registry()

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
    }

    # ---- emit commands (grouped) ----
    names_sorted = sorted(core_cmds)
    groups = [names_sorted[i:i + CMDS_PER_FILE]
              for i in range(0, len(names_sorted), CMDS_PER_FILE)]
    for gi, group in enumerate(groups, 1):
        gname = "%02d" % gi
        lines = [
            "// GENERATED by tools/gen_gl.py from gl.xml (OpenGL core %d.%d) -- do not edit."
            % MAX_VERSION,
            "module xiom.opengl.cmds_%s" % gname,
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
            fname = snake(cname)
            sig = ", ".join("%s: %s" % (pn, pt) for pt, pn in params)
            if sig:
                sig = ", " + sig
            callargs = ", ".join(pn for _, pn in params)
            if ret == "Unit":
                lines.append("pub fn %s(api: &GlApi%s)" % (fname, sig))
                lines.append("  requires: api.active != 0")
                lines.append("{")
                lines.append("  unsafe {")
                lines.append("    let glres = gl_api_resolve(api, \"%s\".c_str());" % cname)
                lines.append("    if glres != 0 {")
                lines.append("      let glfn = glres as fn(%s);" % ", ".join(
                    pt for pt, _ in params) if params else "      let glfn = glres as fn();")
                lines.append("      glfn(%s);" % callargs)
                lines.append("    }")
                lines.append("  }")
                lines.append("}")
            else:
                lines.append("pub fn %s(api: &GlApi%s) -> %s" % (fname, sig, ret))
                lines.append("  requires: api.active != 0")
                lines.append("{")
                lines.append("  unsafe {")
                lines.append("    let glres = gl_api_resolve(api, \"%s\".c_str());" % cname)
                lines.append("    if glres == 0 { return %s; }" % zero_of(ret))
                lines.append("      let glfn = glres as fn(%s) -> %s;" % (", ".join(
                    pt for pt, _ in params), ret) if params
                    else "      let glfn = glres as fn() -> %s;" % ret)
                lines.append("      return glfn(%s);" % callargs)
                lines.append("  }")
                lines.append("}")
            lines.append("")
            manifest["emitted_commands"] += 1
        path = os.path.join(SRC, "cmds_%s.xi" % gname)
        with open(path, "w", encoding="ascii", newline="\n") as fh:
            fh.write("\n".join(lines).rstrip() + "\n")
        manifest["groups"].append({"file": "cmds_%s.xi" % gname, "count": len(group)})

    # ---- emit consts ----
    const_names = sorted(n for n in core_enums if n not in ROOT_OWNED_ENUMS)
    chunks = [const_names[i:i + CONSTS_PER_FILE]
              for i in range(0, len(const_names), CONSTS_PER_FILE)]
    for ci, chunk in enumerate(chunks, 1):
        lines = [
            "// GENERATED by tools/gen_gl.py from gl.xml -- do not edit.",
            "module xiom.opengl.consts_%d" % ci,
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
        path = os.path.join(SRC, "consts_%d.xi" % ci)
        with open(path, "w", encoding="ascii", newline="\n") as fh:
            fh.write("\n".join(lines).rstrip() + "\n")

    # ---- names.xi ----
    lines = [
        "// GENERATED by tools/gen_gl.py from gl.xml -- do not edit.",
        "module xiom.opengl.names",
        "",
        "pub const GL_CMD_COUNT: Int = %d;" % len(names_sorted),
        "",
        "pub fn gl_cmd_names() -> Vec[Str] {",
        "  var v: Vec[Str] = Vec[Str].new();",
    ]
    for name in names_sorted:
        lines.append("  v.push(\"%s\");" % name)
    lines.append("  return v;")
    lines.append("}")
    with open(os.path.join(SRC, "names.xi"), "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")

    # ---- gl_api.xi ----
    api_lines = [
        "// GENERATED by tools/gen_gl.py -- do not edit.",
        "// GlApi: live-session handle + the per-call proc resolver.",
        "module xiom.opengl.glapi",
        "",
        "use xiom.opengl;",
        "",
        "pub type GlApi = {",
        "  active: Int;",
        "}",
        "",
        "/// Create the API handle for a live session (see opengl_session_open).",
        "pub fn gl_api_new() -> GlApi",
        "  requires: true",
        "{",
        "  return GlApi{ active: 1 };",
        "}",
        "",
        "/// Resolve a GL command name through the live session (wglGetProcAddress",
        "/// first, then the opengl32 export table).  0 = unresolved.",
        "pub fn gl_api_resolve(api: &GlApi, name: *UInt8) -> Int",
        "  requires: api.active != 0",
        "{",
        "  return opengl_get_proc(name);",
        "}",
    ]
    with open(os.path.join(SRC, "gl_api.xi"), "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(api_lines) + "\n")

    os.makedirs(DOCS, exist_ok=True)
    with open(os.path.join(DOCS, "gen_manifest.json"), "w", encoding="ascii", newline="\n") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
        fh.write("\n")

    print("core commands: %d (emitted %d, skipped %d)" % (
        manifest["core_command_count"], manifest["emitted_commands"],
        len(manifest["command_skips"])))
    print("core enums:    %d (emitted %d, skipped %d)" % (
        manifest["core_enum_count"], manifest["emitted_consts"],
        len(manifest["const_skips"])))
    for sk in manifest["command_skips"][:10]:
        print("  skip cmd: %s -- %s" % (sk["name"], sk["reason"]))
    for sk in manifest["const_skips"][:10]:
        print("  skip const: %s -- %s" % (sk["name"], sk["reason"]))
    return 0


def zero_of(t):
    if t == "Float32":
        return "0.0"
    if t == "Float64":
        return "0.0"
    if t.startswith("*"):
        return "0"
    return "0"


if __name__ == "__main__":
    sys.exit(main())
