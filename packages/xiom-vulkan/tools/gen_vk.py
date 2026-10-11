#!/usr/bin/env python3
"""XIOM xiom.vulkan 100% SDK-surface generator.

Oracle: C:/VulkanSDK/1.4.350.0/share/vulkan/registry/vk.xml (vulkan API).
Emits (into packages/xiom-vulkan/src/):
  api.xi         -- VkApi type + loader/resolve helpers (module xiom.vulkan.api)
  names.xi       -- full command name/class table for the loadability suite
  cmds_<grp>.xi  -- one typed loader wrapper per command (incl. aliases)
  consts_<n>.xi  -- every enum value + API constant as `pub const ... : Int`
  gen_manifest.json (packages/xiom-vulkan/docs/) -- oracle vs emitted counts

Deterministic; no hand-maintained lists. Uses only the Python stdlib.
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import OrderedDict

SDK = r"C:\VulkanSDK\1.4.350.0"
VK_XML = os.path.join(SDK, "share", "vulkan", "registry", "vk.xml")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
DOCS = os.path.join(ROOT, "docs")

XIOM_KEYWORDS = {
    "as", "break", "const", "continue", "else", "enum", "extern", "false",
    "fn", "for", "if", "impl", "in", "let", "loop", "match", "module",
    "mut", "pub", "requires", "ensures", "return", "struct", "trait",
    "true", "type", "unsafe", "use", "var", "while",
}

GLOBAL_ENTRY_POINTS = {
    "vkGetInstanceProcAddr", "vkGetDeviceProcAddr", "vkCreateInstance",
    "vkEnumerateInstanceExtensionProperties", "vkEnumerateInstanceLayerProperties",
    "vkEnumerateInstanceVersion",
}


def norm(text):
    return re.sub(r"\s+", " ", (text or "").strip())


def elem_decl(el):
    """Reconstruct a C declaration string from an element's itertext."""
    return norm("".join(el.itertext()))


DECL_RE = re.compile(
    r"^(?:(?P<pre>const)\s+)?"
    r"(?:(?:struct|union|enum)\s+)?"
    r"(?P<base>[A-Za-z_]\w*)\s*"
    r"(?P<stars>\*+)?\s*"
    r"(?P<name>[A-Za-z_]\w*)?\s*"
    r"(?P<arr>(?:\[[^\]]*\])*)$"
)


def parse_decl(s):
    s = re.sub(r"\bconst\b", "", s)
    s = norm(s)
    # rejoin spaces before stars for stable parsing: "char * * pp" -> "char ** pp"
    s = re.sub(r"\s*\*\s*", "*", s)
    s = re.sub(r"\s*\[\s*", "[", s)
    s = re.sub(r"\s*\]\s*", "] ", s).strip()
    m = DECL_RE.match(s)
    if not m:
        raise ValueError("cannot parse decl: %r" % s)
    return {
        "const": False,
        "base": m.group("base"),
        "stars": m.group("stars") or "",
        "name": m.group("name") or "",
        "arr": m.group("arr") or "",
    }


def snake(name):
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name)
    s = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", "_", s)
    s = re.sub(r"__+", "_", s).lower()
    return s


def load_registry():
    root = ET.parse(VK_XML).getroot()

    handles, enums, bitmasks = set(), set(), {}
    handle_parent = {}
    for t in root.findall("./types/type"):
        cat = t.get("category")
        name = t.get("name")
        if not name:
            ne = t.find("name")
            if ne is not None and ne.text:
                name = ne.text.strip()
        if not name:
            continue
        if cat == "handle":
            handles.add(name)
            if t.get("parent"):
                handle_parent[name] = t.get("parent")
        elif cat == "enum":
            enums.add(name)
        elif cat == "bitmask":
            inner = t.find("type")
            if inner is not None and inner.text:
                body = norm(inner.text)
            else:
                body = norm("".join(t.itertext()))
            bitmasks[name] = 8 if "64" in body else 4

    cmds = OrderedDict()
    for c in root.findall("./commands/command"):
        api = c.get("api")
        if api and "vulkan" not in [a.strip() for a in api.split(",")]:
            continue  # vulkansc-only variant; not part of the desktop Vulkan API
        alias = c.get("alias")
        proto = c.find("proto")
        pname = None
        if proto is not None:
            ne = proto.find("name")
            if ne is not None and ne.text:
                pname = ne.text.strip()
        name = c.get("name") or pname
        if not name:
            continue
        if alias:
            cmds[name] = {"name": name, "alias": alias}
            continue
        if proto is None:
            continue
        rd = parse_decl(elem_decl(proto))
        params = []
        seen = set()
        for p in c.findall("param"):
            pd = parse_decl(elem_decl(p))
            if pd["name"] and pd["name"] in seen:
                continue  # registry repeats the same param element (e.g. pCreateInfo)
            if pd["name"]:
                seen.add(pd["name"])
            params.append(pd)
        cmds[name] = {"name": name, "ret": rd, "params": params}

        # resolve alias chains to a callable shape
    pending = OrderedDict((n, c) for n, c in cmds.items() if "alias" in c)
    for _ in range(20):
        if not pending:
            break
        progressed = False
        for name in list(pending.keys()):
            cd = pending[name]
            target = cd["alias"]
            tc = cmds.get(target)
            if tc is not None and "ret" in tc:
                cd["ret"] = tc["ret"]
                cd["params"] = tc["params"]
                cd["resolve_name"] = tc.get("resolve_name", target)
                del pending[name]
                progressed = True
        if not progressed:
            break
    if pending:
        raise ValueError("unresolved alias chain: %s" % list(pending.keys())[:5])

    for name, cd in cmds.items():
        if "resolve_name" not in cd:
            cd["resolve_name"] = cd["name"]

    # classification: walk the first parameter's handle parent chain
    def dispatch_level(base):
        seen = set()
        cur = base
        while cur and cur not in seen:
            seen.add(cur)
            if cur in ("VkDevice", "VkQueue"):
                return "device"
            if cur in ("VkPhysicalDevice", "VkInstance"):
                return "instance"
            cur = handle_parent.get(cur)
        return None

    for name, cd in cmds.items():
        if name in GLOBAL_ENTRY_POINTS:
            cd["cls"] = "global"
        else:
            first = cd["params"][0]["base"] if cd["params"] else None
            cd["cls"] = dispatch_level(first) if first else "global"

    # group map (first feature/extension that requires the command)
    group_of = OrderedDict()
    order = []
    for feat in root.findall("./feature"):
        if not is_vulkan_api(feat):
            continue
        gname = feat.get("name")
        if gname not in order:
            order.append(gname)
        for req in feat.findall("require"):
            for cmd in req.findall("command"):
                n = cmd.get("name")
                if n and n not in group_of:
                    group_of[n] = gname
    for ext in root.findall("./extensions/extension"):
        gname = ext.get("name")
        if gname not in order:
            order.append(gname)
        for req in ext.findall("require"):
            for cmd in req.findall("command"):
                n = cmd.get("name")
                if n and n not in group_of:
                    group_of[n] = gname
    for name in cmds:
        group_of.setdefault(name, "VK_MISC")

    return root, handles, enums, bitmasks, cmds, group_of, order


def param_xiom_type(pd, handles, enums, bitmasks):
    if pd["stars"] or pd["arr"]:
        return "*UInt8"
    b = pd["base"]
    if b in ("float",):
        return "Float32"
    if b in ("double",):
        return "Float64"
    if b.startswith("PFN_"):
        return "*UInt8"
    return "Int"  # all integer scalars, enums, bitmasks, handles by value


def ret_xiom_type(rd, handles, enums, bitmasks):
    if rd["base"] == "void" and not rd["stars"]:
        return None
    if rd["stars"] or rd["base"] == "void" or rd["base"].startswith("PFN_"):
        return "Int"
    b = rd["base"]
    if b in ("float",):
        return "Float32"
    if b in ("double",):
        return "Float64"
    if b in handles or b == "VkDeviceAddress" or b == "VkDeviceSize":
        return "Int"
    if b in enums:
        return "Int32"
    if b in bitmasks:
        return "UInt64" if bitmasks[b] == 8 else "UInt32"
    if b in ("uint8_t", "uint16_t", "uint32_t", "VkBool32", "VkSampleMask"):
        return "UInt32"
    if b in ("int8_t", "int16_t", "int32_t", "int"):
        return "Int32"
    if b in ("uint64_t", "size_t"):
        return "UInt64"
    if b in ("int64_t",):
        return "Int64"
    return "Int32"


def default_ret(ret):
    if ret is None:
        return None
    if ret in ("Float32", "Float64"):
        return "0.0"
    if ret in ("Int32", "Int64", "Int"):
        return "0 - 1"
    return "0"


def resolve_fn(cls):
    return {
        "global": "vk_api_resolve_global",
        "instance": "vk_api_resolve_instance",
        "device": "vk_api_resolve_device",
    }[cls]


def emit_wrapper(cd, handles, enums, bitmasks):
    name = cd["name"]
    fname = snake(name)
    ret = ret_xiom_type(cd["ret"], handles, enums, bitmasks)
    params = []
    used = set()
    for i, pd in enumerate(cd["params"]):
        pname = pd["name"] or ("arg%d" % i)
        if pname in XIOM_KEYWORDS or pname in used or pname == "api":
            pname = "p_" + pname
        used.add(pname)
        params.append((pname, param_xiom_type(pd, handles, enums, bitmasks)))
    sig_params = ["api: &VkApi"] + ["%s: %s" % (n, t) for n, t in params]
    cast_sig = ", ".join(t for _, t in params)
    args = ", ".join(n for n, _ in params)
    r = resolve_fn(cd["cls"])
    rname = cd["resolve_name"]
    lines = []
    req = "  requires: api.loader != 0"
    if ret is None:
        lines.append("pub fn %s(%s)" % (fname, ", ".join(sig_params)))
        lines.append(req)
        lines.append("{")
        lines.append("  unsafe {")
        lines.append('    let p = %s(api, "%s".c_str());' % (r, rname))
        lines.append("    if p != 0 {")
        lines.append("      let f = p as fn(%s);" % cast_sig)
        lines.append("      f(%s);" % args)
        lines.append("    }")
        lines.append("  }")
        lines.append("}")
    else:
        lines.append("pub fn %s(%s) -> %s" % (fname, ", ".join(sig_params), ret))
        lines.append(req)
        lines.append("{")
        lines.append("  unsafe {")
        lines.append('    let p = %s(api, "%s".c_str());' % (r, rname))
        lines.append("    if p == 0 { return %s; }" % default_ret(ret))
        if cast_sig:
            lines.append("      let f = p as fn(%s) -> %s;" % (cast_sig, ret))
        else:
            lines.append("      let f = p as fn() -> %s;" % ret)
        lines.append("      return f(%s);" % args)
        lines.append("  }")
        lines.append("}")
    return "\n".join(lines)


def emit_commands(cmds, group_of, handles, enums, bitmasks):
    # ordered groups, in registry order
    groups = OrderedDict()
    for name in cmds:
        groups.setdefault(group_of[name], []).append(name)

    # pack groups into files (keep group cohesion; ~<=110 commands/file)
    chunks = []
    cur, cur_count = [], 0
    for g, names in groups.items():
        if cur and cur_count + len(names) > 110 and cur_count >= 40:
            chunks.append(cur)
            cur, cur_count = [], 0
        cur.extend(names)
        cur_count += len(names)
        if cur_count >= 110:
            chunks.append(cur)
            cur, cur_count = [], 0
    if cur:
        chunks.append(cur)

    emitted = []
    index = 0
    files = OrderedDict()
    for i, chunk in enumerate(chunks):
        fname = "cmds_%02d" % (i + 1)
        groups_in = []
        for n in chunk:
            g = group_of[n]
            if g not in groups_in:
                groups_in.append(g)
        body = []
        body.append("// GENERATED by tools/gen_vk.py from vk.xml -- do not edit.")
        body.append("// Groups: %s" % ", ".join(groups_in))
        body.append("module xiom.vulkan.%s" % fname)
        body.append("")
        body.append("use xiom.vulkan.api;")
        body.append("")
        for name in chunk:
            body.append(emit_wrapper(cmds[name], handles, enums, bitmasks))
            body.append("")
        path = os.path.join(SRC, fname + ".xi")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(body))
        files[fname] = chunk
        for name in chunk:
            emitted.append((name, fname, index))
            index += 1
    return files, emitted


def parse_const_value(e, default_extnumber=None):
    if e.get("alias"):
        return ("alias", e.get("alias"))
    if e.get("bitpos") is not None:
        return ("int", to_signed64(1 << int(e.get("bitpos"))))
    if e.get("offset") is not None:
        extn = e.get("extnumber") or default_extnumber
        if extn is None:
            return ("raw", "offset-without-extnumber")
        val = 1000000000 + (int(extn) - 1) * 1000 + int(e.get("offset"))
        if e.get("dir") == "-":
            val = -val
        return ("int", val)
    v = e.get("value")
    if v is None:
        return ("skip", None)
    v = v.strip()
    if v.startswith('"') and v.endswith('"') and len(v) >= 2:
        return ("str", v[1:-1])
    if v.startswith("(") and v.endswith(")"):
        v = v[1:-1].strip()
    m = re.match(r"^~(\d+)(U|ULL|UL|L)?$", v)
    if m:
        n = int(m.group(1))
        wide = (m.group(2) or "") in ("ULL", "UL", "L")
        return ("int", to_signed64(((1 << 64) - 1 - n) if wide else ((1 << 32) - 1 - n)))
    if v.endswith(("f", "F")) and re.match(r"^[+-]?\d+(\.\d+)?$", v[:-1]):
        return ("float", v[:-1])
    v2 = re.sub(r"(?i)(ULL|LLU|UL|LU|U|L)$", "", v)
    try:
        return ("int", to_signed64(int(v2, 0)))
    except ValueError:
        return ("raw", v)


def to_signed64(v):
    v &= 0xFFFFFFFFFFFFFFFF
    if v >= (1 << 63):
        return v - (1 << 64)
    return v


def emit_constants(root):
    entries = OrderedDict()  # name -> int value
    floats = OrderedDict()   # name -> float text
    strings = OrderedDict()  # name -> str value
    conflicts = []
    pending_alias = []

    def put(nm, kind, source):
        if kind[0] == "skip":
            return
        if kind[0] == "alias":
            pending_alias.append((nm, kind[1]))
        elif kind[0] == "raw":
            pending_alias.append((nm, "__raw__" + kind[1]))
        elif kind[0] == "str":
            if nm not in strings:
                strings[nm] = kind[1]
        elif kind[0] == "float":
            if nm not in floats:
                floats[nm] = kind[1]
        else:
            val = to_signed64(kind[1])
            if nm in entries:
                if entries[nm] != val:
                    conflicts.append((nm, entries[nm], val, source))
            else:
                entries[nm] = val

    for enums_el in root.findall("./enums"):
        src = enums_el.get("name") or enums_el.get("type") or "?"
        for e in enums_el.findall("enum"):
            nm = e.get("name")
            if nm:
                put(nm, parse_const_value(e), src)
    for feat in root.findall("./feature"):
        src = feat.get("name") or "?"
        for req in feat.findall("require"):
            for e in req.findall("enum"):
                nm = e.get("name")
                if nm:
                    put(nm, parse_const_value(e), src)
    for ext in root.findall("./extensions/extension"):
        src = ext.get("name") or "?"
        num = ext.get("number")
        for req in ext.findall("require"):
            for e in req.findall("enum"):
                nm = e.get("name")
                if nm:
                    put(nm, parse_const_value(e, default_extnumber=num), src)

    # resolve aliases (chains; int and str targets)
    for _ in range(12):
        if not pending_alias:
            break
        remaining = []
        progressed = False
        for nm, target in pending_alias:
            if target.startswith("__raw__"):
                remaining.append((nm, target))
            elif target in entries:
                entries[nm] = entries[target]
                progressed = True
            elif target in strings:
                strings[nm] = strings[target]
                progressed = True
            else:
                remaining.append((nm, target))
        if not progressed:
            break
        pending_alias = remaining
    raw_skipped = [nm for nm, t in pending_alias if t.startswith("__raw__")]
    unresolved = [nm for nm, t in pending_alias if not t.startswith("__raw__")]

    items = list(entries.items())
    per_file = 450
    chunks = [items[i:i + per_file] for i in range(0, len(items), per_file)] or [[]]
    for i, chunk in enumerate(chunks, 1):
        lines = []
        lines.append("// GENERATED by tools/gen_vk.py from vk.xml -- do not edit.")
        lines.append("module xiom.vulkan.consts_%d" % i if len(chunks) > 1 else "module xiom.vulkan.consts")
        lines.append("")
        for nm, val in chunk:
            lines.append("pub const %s: Int = %d;" % (nm, val))
        path = os.path.join(SRC, ("consts_%d.xi" % i) if len(chunks) > 1 else "consts.xi")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(lines) + "\n")
    if floats:
        lines = []
        lines.append("// GENERATED by tools/gen_vk.py from vk.xml -- do not edit.")
        lines.append("module xiom.vulkan.consts_float")
        lines.append("")
        for nm, val in floats.items():
            lines.append("pub const %s: Float32 = %s;" % (nm, val))
        with open(os.path.join(SRC, "consts_float.xi"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(lines) + "\n")
    if strings:
        lines = []
        lines.append("// GENERATED by tools/gen_vk.py from vk.xml -- do not edit.")
        lines.append("module xiom.vulkan.consts_str")
        lines.append("")
        for nm, val in strings.items():
            esc = val.replace("\\", "\\\\").replace('"', '\\"')
            lines.append('pub const %s: Str = "%s";' % (nm, esc))
        with open(os.path.join(SRC, "consts_str.xi"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(lines) + "\n")
    return entries, floats, strings, raw_skipped, unresolved, conflicts, len(chunks)


def emit_api():
    text = """// GENERATED by tools/gen_vk.py -- do not edit.
module xiom.vulkan.api

use xiom.dl;

pub const VK_CLASS_GLOBAL: Int = 0;
pub const VK_CLASS_INSTANCE: Int = 1;
pub const VK_CLASS_DEVICE: Int = 2;

pub type VkApi = {
  loader: Int;
  gipa: Int;
  gdpa: Int;
  inst: Int;
  dev: Int;
}

pub fn vk_api_load(soname: Str) -> Result[VkApi, Str] {
  let h = dl.dl_open(soname);
  if !h.is_ok { return Err(h.error); }
  let handle = h.value;
  let g1 = dl.dl_sym(handle, "vkGetInstanceProcAddr");
  if !g1.is_ok { var ig = dl.dl_close(handle); return Err(g1.error); }
  let g2 = dl.dl_sym(handle, "vkGetDeviceProcAddr");
  if !g2.is_ok { var ig = dl.dl_close(handle); return Err(g2.error); }
  return Ok(VkApi{ loader: handle, gipa: g1.value, gdpa: g2.value, inst: 0, dev: 0 });
}

pub fn vk_api_load_full(soname: Str, inst: Int, dev: Int) -> Result[VkApi, Str] {
  let h = dl.dl_open(soname);
  if !h.is_ok { return Err(h.error); }
  let handle = h.value;
  let g1 = dl.dl_sym(handle, "vkGetInstanceProcAddr");
  if !g1.is_ok { var ig = dl.dl_close(handle); return Err(g1.error); }
  let g2 = dl.dl_sym(handle, "vkGetDeviceProcAddr");
  if !g2.is_ok { var ig = dl.dl_close(handle); return Err(g2.error); }
  return Ok(VkApi{ loader: handle, gipa: g1.value, gdpa: g2.value, inst: inst, dev: dev });
}

pub fn vk_api_resolve_global(api: &VkApi, name: *UInt8) -> Int
  requires: api.loader != 0
{
  unsafe {
    let f = api.gipa as fn(Int, *UInt8) -> Int;
    return f(0, name);
  }
}

pub fn vk_api_resolve_instance(api: &VkApi, name: *UInt8) -> Int
  requires: api.loader != 0
{
  unsafe {
    let f = api.gipa as fn(Int, *UInt8) -> Int;
    return f(api.inst, name);
  }
}

pub fn vk_api_resolve_device(api: &VkApi, name: *UInt8) -> Int
  requires: api.loader != 0
{
  unsafe {
    let f = api.gdpa as fn(Int, *UInt8) -> Int;
    return f(api.dev, name);
  }
}

pub fn vk_api_unload(api: &VkApi) {
  let c = dl.dl_close(api.loader);
}
"""
    with open(os.path.join(SRC, "api.xi"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def is_vulkan_api(el):
    api = el.get("api")
    if api is None:
        return True
    return "vulkan" in [a.strip() for a in api.split(",")]


def compute_excluded(root, cmds):
    """Commands not resolvable on Windows by loader design: foreign-platform
    extensions (platform attr != win32) and Vulkan SC-only groups."""
    ext_ok = {}
    for ext in root.findall("./extensions/extension"):
        name = ext.get("name")
        plat = ext.get("platform")
        sup = ext.get("supported", "")
        ok = True
        if plat and plat != "win32":
            ok = False
        if sup:
            sups = [s.strip() for s in sup.split(",")]
            if "vulkan" not in sups:
                ok = False
        ext_ok[name] = ok
    reqs = {}
    for feat in root.findall("./feature"):
        if not is_vulkan_api(feat):
            continue
        for req in feat.findall("require"):
            for cmd in req.findall("command"):
                reqs.setdefault(cmd.get("name"), []).append(feat.get("name"))
    for ext in root.findall("./extensions/extension"):
        for req in ext.findall("require"):
            for cmd in req.findall("command"):
                reqs.setdefault(cmd.get("name"), []).append(ext.get("name"))
    flags = []
    ungrouped = []
    for name in cmds:
        groups = reqs.get(name, [])
        if not groups:
            ungrouped.append(name)
            flags.append(1)
        else:
            flags.append(1 if all(not ext_ok.get(g, True) for g in groups) else 0)
    return flags, sum(flags), ungrouped


def emit_names(cmds, group_of, excluded_flags):
    names = list(cmds.keys())
    classes = []
    for name, cd in cmds.items():
        classes.append({"global": 0, "instance": 1, "device": 2}[cd["cls"]])
    L = []
    L.append("// GENERATED by tools/gen_vk.py -- do not edit.")
    L.append("module xiom.vulkan.names")
    L.append("")
    L.append("pub const VK_CMD_COUNT: Int = %d;" % len(names))
    L.append("")
    L.append("pub fn vk_cmd_names() -> Vec[Str] {")
    L.append("  var v: Vec[Str] = Vec[Str].new();")
    for n in names:
        L.append('  v.push("%s");' % n)
    L.append("  return v;")
    L.append("}")
    L.append("")
    L.append("pub fn vk_cmd_classes() -> Vec[Int] {")
    L.append("  var v: Vec[Int] = Vec[Int].new();")
    for c in classes:
        L.append("  v.push(%d);" % c)
    L.append("  return v;")
    L.append("}")
    L.append("")
    L.append("pub fn vk_cmd_groups() -> Vec[Str] {")
    L.append("  var v: Vec[Str] = Vec[Str].new();")
    for n in names:
        L.append('  v.push("%s");' % group_of[n])
    L.append("  return v;")
    L.append("}")
    L.append("")
    L.append("pub fn vk_cmd_excluded() -> Vec[Int] {")
    L.append("  var v: Vec[Int] = Vec[Int].new();")
    for f in excluded_flags:
        L.append("  v.push(%d);" % f)
    L.append("  return v;")
    L.append("}")
    with open(os.path.join(SRC, "names.xi"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(L) + "\n")


CPP_KEYWORDS = {
    "alignas", "alignof", "and", "and_eq", "asm", "auto", "bitand", "bitor",
    "bool", "break", "case", "catch", "char", "char8_t", "char16_t",
    "char32_t", "class", "compl", "concept", "const", "constexpr",
    "const_cast", "continue", "co_await", "co_return", "co_yield", "decltype",
    "default", "delete", "do", "double", "dynamic_cast", "else", "enum",
    "explicit", "export", "extern", "false", "float", "for", "friend", "goto",
    "if", "inline", "int", "long", "mutable", "namespace", "new", "noexcept",
    "not", "not_eq", "nullptr", "operator", "or", "or_eq", "private",
    "protected", "public", "register", "reinterpret_cast", "requires",
    "return", "short", "signed", "sizeof", "static", "static_assert",
    "static_cast", "struct", "switch", "template", "this", "thread_local",
    "throw", "true", "try", "typedef", "typeid", "typename", "union",
    "unsigned", "using", "virtual", "void", "volatile", "wchar_t", "while",
    "xor", "xor_eq",
}


def collect_structs(root):
    """struct/union types with their members, for the offset dumper."""
    skip_path = os.path.join(ROOT, "tools", "struct_dump_skip.json")
    skip = set()
    if os.path.exists(skip_path):
        with open(skip_path, "r", encoding="utf-8") as fh:
            skip = {x for x in json.load(fh) if isinstance(x, str)}
    structs = []
    skipped_sc = []
    skipped_kw = []
    skipped_hdr = []
    for t in root.findall("./types/type"):
        cat = t.get("category")
        if cat not in ("struct", "union"):
            continue
        name = t.get("name")
        if not name:
            ne = t.find("name")
            if ne is not None and ne.text:
                name = ne.text.strip()
        if not name or t.get("alias"):
            continue
        if name in skip:
            skipped_hdr.append((name, t.get("protect") or "header-unavailable"))
            continue
        api = t.get("api")
        if api and "vulkan" not in [a.strip() for a in api.split(",")]:
            skipped_sc.append(name)
            continue
        members = []
        for m in t.findall("member"):
            mn = m.find("name")
            mname = mn.text.strip() if mn is not None and mn.text else None
            if not mname:
                continue
            decl = elem_decl(m)
            if re.search(r":\s*\d", decl) or m.find("bitfield") is not None:
                skipped_kw.append((name, mname + " (bitfield)"))
                continue
            if mname in CPP_KEYWORDS:
                skipped_kw.append((name, mname))
                continue
            members.append(mname)
        structs.append({
            "name": name,
            "protect": t.get("protect"),
            "members": members,
        })
    return structs, skipped_sc, skipped_kw, skipped_hdr


def emit_struct_dump(structs):
    """Emit tools/struct_dump.cpp: sizeof + offsetof oracle for every struct."""
    out = os.path.join(ROOT, "tools", "struct_dump.cpp")
    lines = []
    lines.append("// GENERATED by tools/gen_vk.py -- do not edit.")
    lines.append("// SDK100 struct metadata oracle: sizeof + offsetof vs the SDK headers.")
    lines.append("#include <cstddef>")
    lines.append("#include <cstdio>")
    lines.append("#define VK_ENABLE_BETA_EXTENSIONS 1")
    lines.append("#define VK_USE_PLATFORM_WIN32_KHR 1")
    lines.append("#include <vulkan/vulkan.h>")
    for h in (
        "vulkan_video_codecs_common.h",
        "vulkan_video_codec_h264std.h",
        "vulkan_video_codec_h264std_decode.h",
        "vulkan_video_codec_h264std_encode.h",
        "vulkan_video_codec_h265std.h",
        "vulkan_video_codec_h265std_decode.h",
        "vulkan_video_codec_h265std_encode.h",
        "vulkan_video_codec_vp9std.h",
        "vulkan_video_codec_vp9std_decode.h",
        "vulkan_video_codec_av1std.h",
        "vulkan_video_codec_av1std_decode.h",
        "vulkan_video_codec_av1std_encode.h",
    ):
        lines.append("#include <vk_video/%s>" % h)
    lines.append("")
    lines.append("int main(void) {")
    for s in structs:
        guard = None
        if s["protect"] and s["protect"] != "VK_ENABLE_BETA_EXTENSIONS":
            guard = s["protect"]
        if guard:
            lines.append("#ifdef %s" % guard)
        lines.append('  printf("SIZE %s %%zu\\n", sizeof(%s));' % (s["name"], s["name"]))
        for mname in s["members"]:
            lines.append('  printf("OFF %s %s %%zu\\n", offsetof(%s, %s));'
                         % (s["name"], mname, s["name"], mname))
        if guard:
            lines.append("#endif")
    lines.append("  return 0;")
    lines.append("}")
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    return out, len(structs)


def main():
    check = "--check" in sys.argv
    if "--emit-dump" in sys.argv:
        root, _h, _e, _b, _c, _g, _o = load_registry()
        structs, skipped_sc, skipped_kw, skipped_hdr = collect_structs(root)
        out, n = emit_struct_dump(structs)
        side = {
            "structs_emitted": n,
            "unavailable_structs": sorted(set(skipped_hdr)),
            "sc_api_structs": sorted(set(skipped_sc)),
            "bitfield_members": [(s, m) for s, m in skipped_kw],
        }
        with open(os.path.join(ROOT, "tools", "struct_dump_skips_full.json"),
                  "w", encoding="utf-8") as fh:
            json.dump(side, fh, indent=2)
        print("struct dump emitted: %s structs=%d sc_skipped=%d hdr_skipped=%d keyword_members=%d"
              % (out, n, len(skipped_sc), len(skipped_hdr), len(skipped_kw)))
        return
    root, handles, enums, bitmasks, cmds, group_of, order = load_registry()

    raw_cmds = root.findall("./commands/command")
    skipped = []
    for c in raw_cmds:
        proto = c.find("proto")
        pname = None
        if proto is not None:
            ne = proto.find("name")
            if ne is not None and ne.text:
                pname = ne.text.strip()
        if not (c.get("name") or pname):
            skipped.append("unnamed")
        elif proto is None and not c.get("alias"):
            skipped.append("no-proto:" + (c.get("name") or "?"))
    real = sum(1 for c in cmds.values() if "alias" not in c)
    alias = len(cmds) - real
    fnames = {}
    collisions = []
    for name in cmds:
        f = snake(name)
        if f in fnames:
            collisions.append((name, fnames[f], f))
        fnames[f] = name

    # count constants without emitting
    if not check:
        entries, floats, strings, raw_skipped, unresolved, conflicts, nchunks = emit_constants(root)
    else:
        entries, floats, strings, raw_skipped, unresolved, conflicts, nchunks = (
            None, None, None, None, None, None, None)

    print("raw command elements=%d; parsed=%d; skipped=%s" % (len(raw_cmds), len(cmds), skipped[:10]))
    print("commands: total=%d real=%d alias=%d" % (len(cmds), real, alias))
    print("handles=%d enums=%d bitmasks=%d groups=%d" % (
        len(handles), len(enums), len(bitmasks), len(set(group_of.values()))))
    print("generated fn-name collisions: %d %s" % (len(collisions), collisions[:5]))
    if not check:
        files, emitted = emit_commands(cmds, group_of, handles, enums, bitmasks)
        emit_api()
        excluded_flags, n_excluded, ungrouped = compute_excluded(root, cmds)
        emit_names(cmds, group_of, excluded_flags)
        manifest = {
            "oracle": VK_XML,
            "commands_total": len(cmds),
            "commands_real": real,
            "commands_alias": alias,
            "handles": len(handles),
            "enum_types": len(enums),
            "bitmask_types": len(bitmasks),
            "constants_emitted": len(entries),
            "constants_floats": len(floats),
            "constants_strings": len(strings),
            "constants_raw_skipped": raw_skipped,
            "constants_alias_unresolved": unresolved,
            "constants_conflict_count": len(conflicts),
            "constants_conflicts": conflicts[:20],
            "const_files": nchunks,
            "platform_excluded": n_excluded,
            "ungrouped_commands": ungrouped,
            "command_files": {k: len(v) for k, v in files.items()},
        }
        os.makedirs(DOCS, exist_ok=True)
        with open(os.path.join(DOCS, "gen_manifest.json"), "w", encoding="utf-8") as fh:
            json.dump(manifest, fh, indent=2)
        print("emitted %d wrappers in %d files; %d int + %d float + %d str constants in %d files" % (
            len(emitted), len(files), len(entries), len(floats), len(strings), nchunks))
    else:
        print("sample wrapper:\n" + emit_wrapper(cmds["vkCreateInstance"], handles, enums, bitmasks))
        print("sample alias wrapper:\n" + emit_wrapper(cmds.get("vkCreateSwapchainKHR", cmds["vkCreateInstance"]), handles, enums, bitmasks))
    print("ok")


if __name__ == "__main__":
    main()
