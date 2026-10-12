#!/usr/bin/env python3
"""XIOM xiom.dx12 surface generator (0.3.0 wave).

Oracles:
  core  -- E:/repos/DirectX-Headers @ 461ef513, include/directx/d3d12.h
           (SHA256 AFA193D3...).
  dxgi  -- Windows SDK 10.0.26100.0 shared dxgi*.h+dxgitype.h (not in the
           clone; per-file SHA256 in PROVENANCE.md).  dxgiformat.h is
           byte-identical to the DirectX-Headers clone copy.
Emits into packages/xiom-dx12/src/:
  iface_<g>.xi        -- XIOM wrappers, own methods per interface (grouped)
  functions.xi        -- XIOM wrappers for the 9 D3D12* free functions
  consts_<n>.xi       -- D3D12 enum values as pub const ... : Int
  d3d12_calls.c       -- normalized COM/vtable call shims (slot-index calls)
  dxgi_iface_<g>.xi   -- DXGI interface wrappers (own methods, absolute slots)
  dxgi_functions.xi   -- CreateDXGIFactory/1/2 + DXGI free functions
  dxgi_consts_<n>.xi  -- DXGI enum values
  dxgi_calls.c        -- DXGI COM/vtable call shims (resolved on dxgi.dll)
  d3d12_types.gen.h   -- C definitions of the struct closure used by the
                         typed (sret / by-value) shims
  d3d12_structs.c     -- typed shims for the struct-by-value methods +
                         sizeof probes (oracle cross-check)
  structs.xi          -- XIOM wrappers for the typed shims + size probes
  gen_manifest.json (docs/) -- oracle vs emitted + skips

Modes:
  (default)      regenerate the whole surface
  --emit-dump    write tools/struct_dump.cpp (sizeof/offsetof oracle for
                 all parseable structs; compile+run, then feed the output
                 to tools/gen_dx12_struct_meta.py)

Deterministic; stdlib only.  Own methods = vtbl rows minus the base
interface's rows (COM order guarantees the base prefix).  Struct-by-value
returns > 8 bytes (sret) and by-value struct params are emitted as TYPED
shims (normal form: C bridge copies into an XIOM-owned out slot); 8-byte
descriptor handles return as uint64 (RAX).
"""
import json
import os
import re
import sys
from collections import OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
DOCS = os.path.join(ROOT, "docs")
D3D12_H = r"E:\repos\DirectX-Headers\include\directx\d3d12.h"
DX_HEADERS = r"E:\repos\DirectX-Headers\include\directx"
SDK_SHARED = (r"C:\Program Files (x86)\Windows Kits\10\Include"
              r"\10.0.26100.0\shared")
DXGI_HEADERS = [
    os.path.join(SDK_SHARED, "dxgi.h"),
    os.path.join(SDK_SHARED, "dxgi1_2.h"),
    os.path.join(SDK_SHARED, "dxgi1_3.h"),
    os.path.join(SDK_SHARED, "dxgi1_4.h"),
    os.path.join(SDK_SHARED, "dxgi1_5.h"),
    os.path.join(SDK_SHARED, "dxgi1_6.h"),
    os.path.join(SDK_SHARED, "dxgitype.h"),
    os.path.join(SDK_SHARED, "dxgicommon.h"),
    os.path.join(SDK_SHARED, "dxgiformat.h"),
]
IFACES_PER_FILE = 8
CONSTS_PER_FILE = 250

SCALARS = {
    "UINT": ("uint32_t", "UInt32"), "UINT32": ("uint32_t", "UInt32"),
    "ULONG": ("uint32_t", "UInt32"), "DWORD": ("uint32_t", "UInt32"),
    "UINT16": ("uint16_t", "UInt16"), "UINT8": ("uint8_t", "UInt8"),
    "BYTE": ("uint8_t", "UInt8"),
    "INT": ("int32_t", "Int32"), "INT32": ("int32_t", "Int32"),
    "LONG": ("int32_t", "Int32"), "INT16": ("int16_t", "Int16"),
    "INT8": ("int8_t", "Int8"),
    "HRESULT": ("int32_t", "Int32"), "BOOL": ("int32_t", "Int32"),
    "UINT64": ("uint64_t", "UInt64"), "INT64": ("int64_t", "Int64"),
    "SIZE_T": ("intptr_t", "Int"), "UINT_PTR": ("uintptr_t", "Int"),
    "FLOAT": ("float", "Float32"), "float": ("float", "Float32"),
    "WCHAR": ("uint16_t", "UInt16"), "CHAR": ("int8_t", "Int8"),
    "HANDLE": ("void*", "*UInt8"), "HWND": ("void*", "*UInt8"),
    "HINSTANCE": ("void*", "*UInt8"), "HMODULE": ("void*", "*UInt8"),
}
PTR_ALIASES = {
    "REFIID": "void*", "REFGUID": "void*", "REFCLSID": "void*",
    "LPCWSTR": "void*", "LPCSTR": "void*", "LPVOID": "void*",
    "LPCVOID": "void*", "PVOID": "void*", "LPCGUID": "void*",
    "REFSECURITY_ATTRIBUTES": "void*", "LPSTR": "void*", "LPWSTR": "void*",
}
BYVAL8 = {"D3D12_CPU_DESCRIPTOR_HANDLE", "D3D12_GPU_DESCRIPTOR_HANDLE",
          "LUID"}

# Callback typedefs (`typedef void (__stdcall *NAME)(...)`): passed as raw
# addresses (Int <-> void*).  XIOM handler functions cannot cross to C at
# cast-call positions yet (B-22); consumers pass 0 or a foreign address.
CALLBACK_FUNCS = {"D3D12PipelineStateFunc", "D3D12StateObjectFunc",
                  "D3D12ApplicationDescFunc"}

# External enums used by d3d12.h signatures (defined in d3dcommon.h/dxgi.h);
# int-sized, mapped as Int32.
EXT_ENUMS = {
    "DXGI_FORMAT", "D3D_ROOT_SIGNATURE_VERSION", "D3D_FEATURE_LEVEL",
    "D3D_PRIMITIVE_TOPOLOGY", "D3D_SHADER_MODEL", "D3D_SHADER_VARIABLE_FLAGS",
    "D3D_SHADER_INPUT_TYPE", "D3D_CBUFFER_TYPE", "D3D_SRV_DIMENSION",
    "D3D_NAME", "D3D_MIN_PRECISION", "D3D_INTERPOLATION_MODE",
    "D3D_REGISTER_COMPONENT_TYPE", "D3D_RESOURCE_RETURN_TYPE",
    "D3D_TESSELLATOR_DOMAIN", "D3D_TESSELLATOR_PARTITIONING",
    "D3D_TESSELLATOR_OUTPUT_PRIMITIVE",
}

RET_XIOM = {
    "void": "Unit", "int32_t": "Int32", "uint32_t": "UInt32",
    "int64_t": "Int64", "uint64_t": "UInt64", "intptr_t": "Int",
    "uintptr_t": "Int", "int16_t": "Int16", "uint16_t": "UInt16",
    "int8_t": "Int8", "uint8_t": "UInt8", "float": "Float32",
    "void*": "Int",
}

XIOM_KEYWORDS = {
    "as", "break", "const", "continue", "else", "enum", "extern", "false",
    "fn", "for", "if", "impl", "in", "let", "loop", "match", "module",
    "mut", "pub", "requires", "ensures", "return", "struct", "trait",
    "true", "type", "unsafe", "use", "var", "while",
}


def norm(s):
    return re.sub(r"\s+", " ", s or "").strip()


SAL_RE = re.compile(r"(?<![\w])_[A-Za-z]\w*(?:\((?:[^()]|\([^()]*\))*\))?")

COMMENT_RE = re.compile(r"//[^\n]*|/\*.*?\*/", re.S)


def strip_sal(s):
    s = COMMENT_RE.sub(" ", s)
    return norm(SAL_RE.sub(" ", s))


def split_params(s):
    """Split a C parameter list on top-level commas only (SAL annotations
    contain commas, e.g. _In_range_(0, X))."""
    out = []
    depth = 0
    cur = ""
    for ch in s:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return out


def snake(name):
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name)
    s = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", "_", s)
    s = re.sub(r"__+", "_", s).lower()
    return s


def parse_header_text(h):
    enum_names = set(re.findall(r"typedef\s+enum\s+_?((?:D3D12|DXGI)_\w+)", h))
    brace_names = set(re.findall(r"\}\s*((?:D3D12|DXGI)_\w+)\s*;", h))
    struct_names = brace_names - enum_names
    typedefs = {}
    for base, name in re.findall(r"typedef\s+([A-Za-z_][\w\s\*]*?)\s+((?:D3D12|DXGI)_\w+)\s*;", h):
        typedefs.setdefault(name, norm(base))
    # vtbl blocks
    vtbl = OrderedDict()
    vpat = re.compile(
        r"(?P<ret>[\w\s\*]+?)\(\s*STDMETHODCALLTYPE\s*\*\s*(?P<name>\w+)\s*\)\s*\((?P<params>[^;]*?)\)\s*;",
        re.S)
    starts = [(m.start(), m.group(1)) for m in re.finditer(r"typedef struct (\w+Vtbl)\s*\{", h)]
    for start, name in starts:
        end = h.find("} " + name + ";", start)
        body = h[start:end]
        body = "\n".join(l for l in body.splitlines() if not l.lstrip().startswith("#"))
        rows = []
        for m in vpat.finditer(body):
            ret = norm(m.group("ret"))
            ret = re.sub(r"\b(virtual|const)\b", " ", ret)
            ret = norm(ret)
            params = []
            for piece in split_params(m.group("params")):
                piece = strip_sal(piece)
                if not piece or "STDMETHODCALLTYPE" in piece:
                    continue
                piece = re.sub(r"\[\s*\d*\s*\]", " * ", piece)
                mm = re.match(r"^(?P<base>[A-Za-z_][\w\s\*\[\]]*?)\s*(?P<stars>\*+)?\s*(?P<name>[A-Za-z_]\w*)?\s*(\[\s*\])?$", piece)
                if not mm:
                    params.append(("__bad__:" + piece, "arg%d" % len(params)))
                    continue
                base = norm(mm.group("base"))
                stars = mm.group("stars") or ""
                pname = mm.group("name") or ("arg%d" % len(params))
                if pname == "This":
                    continue
                if pname in XIOM_KEYWORDS:
                    pname = pname + "_"
                params.append((base + (" " + stars if stars else ""), pname))
            rows.append((ret, m.group("name"), params))
        # collapse the two preprocessor variants (XFGVIRT vs plain): drop a
        # row identical in name to its predecessor
        dedup = []
        for r in rows:
            if dedup and r[1] == dedup[-1][1]:
                continue
            dedup.append(r)
        vtbl[name[:-4]] = dedup

    # bases from the C++ declarations (`IXxx : public IYyy`, no `class` key)
    bases = {}
    for m in re.finditer(r"(?m)^\s*(I\w+)\s*:\s*public\s+(I\w+)", h):
        bases.setdefault(m.group(1), m.group(2))

    # IIDs
    iids = {}
    for m in re.finditer(r"DEFINE_GUID\(IID_(I\w+),\s*([0-9xA-Fa-f, ]+)\);", h):
        iids[m.group(1)] = norm(m.group(2))

    # free functions
    freefns = []
    for m in re.finditer(r"\n\w[\w\s\*]*?WINAPI ((?:D3D12|DXGI|CreateDXGI)\w+)\(([^;]*?)\);", h, re.S):
        raw = COMMENT_RE.sub(" ", m.group(2))
        freefns.append((m.group(1), norm(raw)))
    return enum_names, struct_names, typedefs, vtbl, bases, iids, freefns


def load_header(paths=None):
    """Parse one or more headers (concatenated) with the shared regex set."""
    if paths is None:
        paths = [D3D12_H]
    texts = []
    for p in paths:
        texts.append(open(p, encoding="utf-8", errors="replace").read())
    h = "\n".join(texts)
    enum_names, struct_names, typedefs, vtbl, bases, iids, freefns = parse_header_text(h)
    return enum_names, struct_names, typedefs, vtbl, bases, iids, freefns, h


def load_enums(h):
    """name -> value for `typedef enum ... } NAME;` blocks (expr-evaluated)."""
    out = {"values": OrderedDict(), "skips": []}
    for m in re.finditer(r"typedef\s+enum\s+(\w+)\s*\{(.*?)\}\s*(\w+)\s*;", h, re.S):
        body = m.group(2)
        cur = -1
        for piece in body.split(","):
            piece = piece.split("//")[0].strip()
            if not piece:
                continue
            mm = re.match(r"^(\w+)\s*(?:=\s*(.+))?$", piece)
            if not mm:
                continue
            name, val = mm.group(1), mm.group(2)
            if val is None:
                cur += 1
            else:
                v = val.strip()
                try:
                    cur = int(v, 0)
                except ValueError:
                    # allow simple expressions over already-known values
                    expr = v
                    for n2, v2 in out["values"].items():
                        expr = re.sub(r"\b%s\b" % re.escape(n2), str(v2), expr)
                    if re.match(r"^[\d\s\(\)\|\&\+\-\<\>xXa-fA-F]+$", expr):
                        try:
                            cur = int(eval(expr, {"__builtins__": None}, {}))
                        except Exception:
                            out["skips"].append({"name": name, "reason": "expr %r" % val})
                            continue
                    else:
                        out["skips"].append({"name": name, "reason": "expr %r" % val})
                        continue
            out["values"][name] = cur
    return out


def norm_type(base, stars, enums, typedefs, structs, where, skips):
    """-> (c_type, xiom_type) or (None, reason)."""
    stars = stars or ""
    b = norm(re.sub(r"\bconst\b", " ", base)).strip()
    b = b.replace("*", " ").strip()
    b = norm(b)
    if stars:
        return ("void*", "*UInt8")
    if b in PTR_ALIASES:
        return ("void*", "*UInt8")
    if b in SCALARS:
        return SCALARS[b]
    if b in enums:
        return ("int32_t", "Int32")
    if b in EXT_ENUMS:
        return ("int32_t", "Int32")
    if b == "void":
        return ("void", "Unit")
    seen = set()
    while b in typedefs and b not in seen:
        seen.add(b)
        b2 = typedefs[b]
        mm = re.match(r"^(?P<base>[\w\s\*]+?)\s*(?P<stars>\*+)?$", b2)
        if not mm:
            break
        if mm.group("stars"):
            return ("void*", "*UInt8")
        b = norm(mm.group("base"))
        if b in SCALARS:
            return SCALARS[b]
        if b in enums:
            return ("int32_t", "Int32")
        if b in EXT_ENUMS:
            return ("int32_t", "Int32")
    if b in BYVAL8:
        return ("uint64_t", "UInt64")
    if b in CALLBACK_FUNCS:
        return ("void*", "Int")
    if b in structs and (b.startswith("D3D12_") or b.startswith("DXGI_")):
        return (None, "struct-by-value %s" % b)
    return (None, "unmapped base %r" % b)


# ---------------------------------------------------------------------------
# Struct definitions (parseable subset), typed shims, metadata dump (0.3.0)
# ---------------------------------------------------------------------------

C_SCALARS = {
    "UINT": "uint32_t", "UINT32": "uint32_t", "ULONG": "uint32_t",
    "DWORD": "uint32_t", "UINT16": "uint16_t", "UINT8": "uint8_t",
    "BYTE": "uint8_t", "INT": "int32_t", "INT32": "int32_t",
    "LONG": "int32_t", "INT16": "int16_t", "INT8": "int8_t",
    "HRESULT": "int32_t", "BOOL": "int32_t", "UINT64": "uint64_t",
    "INT64": "int64_t", "SIZE_T": "size_t", "UINT_PTR": "uintptr_t",
    "INT_PTR": "intptr_t", "FLOAT": "float", "float": "float",
    "WCHAR": "uint16_t", "CHAR": "int8_t",
}
C_PTR_ALIAS = {
    "LPCWSTR": "const wchar_t*", "LPWSTR": "wchar_t*",
    "LPCSTR": "const char*", "LPSTR": "char*",
    "LPVOID": "void*", "LPCVOID": "const void*", "PVOID": "void*",
    "REFIID": "const GUID*", "REFGUID": "const GUID*",
    "REFCLSID": "const GUID*", "LPCGUID": "const GUID*",
    "HANDLE": "void*", "HWND": "void*", "HINSTANCE": "void*",
    "HMODULE": "void*",
}
C_XIOM = {
    "uint32_t": "UInt32", "int32_t": "Int32", "uint64_t": "UInt64",
    "int64_t": "Int64", "int16_t": "Int16", "uint16_t": "UInt16",
    "int8_t": "Int8", "uint8_t": "UInt8", "float": "Float32",
    "size_t": "Int", "uintptr_t": "Int", "intptr_t": "Int",
}
C_WINDOWS_TYPES = {"GUID", "LUID", "RECT", "POINT"}


def _find_close_brace(text, open_idx):
    depth = 0
    for i in range(open_idx, len(text)):
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i
    return -1


def parse_struct_defs(text):
    """Parse `typedef struct [tag] { ... } NAME;` definitions.

    -> (OrderedDict name -> [(base, stars, member, array_expr)], skips).
    Rejects nested aggregates, bitfields, preprocessor conditionals and
    function-pointer members (documented gaps).
    """
    clean = COMMENT_RE.sub(" ", text)
    structs = OrderedDict()
    skips = []
    for m in re.finditer(r"typedef\s+struct\s*\w*\s*\{", clean):
        start = clean.index("{", m.start())
        end = _find_close_brace(clean, start)
        if end < 0:
            continue
        tm = re.match(r"\}\s*(?P<name>D3D12_\w+|DXGI_\w+)\s*;", clean[end:end + 160])
        if not tm:
            continue
        name = tm.group("name")
        if name in structs:
            continue
        body = clean[start + 1:end]
        if "{" in body or "}" in body:
            skips.append({"struct": name, "reason": "nested aggregate"})
            structs[name] = None
            continue
        if "#" in body:
            skips.append({"struct": name, "reason": "preprocessor conditional"})
            structs[name] = None
            continue
        if ":" in body:
            skips.append({"struct": name, "reason": "bitfield"})
            structs[name] = None
            continue
        members = []
        for piece in body.split(";"):
            p = norm(piece)
            if not p:
                continue
            if "(" in p:
                members = None
                break
            mm = re.match(
                r"^(?P<base>[A-Za-z_][\w\s\*]*?)\s*(?P<name>[A-Za-z_]\w*)"
                r"\s*(?P<arr>\[[^\]]*\])?$", p)
            if not mm:
                members = None
                break
            base = norm(mm.group("base"))
            stars = "*" if "*" in base else ""
            base = norm(base.replace("*", " "))
            members.append((base, stars, mm.group("name"),
                            (mm.group("arr") or "").strip()))
        if members is None:
            skips.append({"struct": name, "reason": "member grammar"})
            structs[name] = None
            continue
        structs[name] = members
    return structs, skips


def c_and_xiom_type(base, stars, enums, structs, typedefs):
    """-> (c_type, xiom_type); c_type None = struct-by-value, xiom None =
    only usable as a struct member (GUID/LUID)."""
    stars = stars or ""
    b = norm(base.replace("*", " "))
    seen = set()
    while b in typedefs and b not in seen:
        seen.add(b)
        mm = re.match(r"^(?P<base>[\w\s\*]+?)\s*(?P<stars>\*+)?$", typedefs[b])
        if not mm:
            break
        if mm.group("stars"):
            return ("void*", "*UInt8")
        b = norm(mm.group("base"))
    if stars:
        if b in structs:
            return (b + "*", "*UInt8")
        return ("void*", "*UInt8")
    if b in C_SCALARS:
        ct = C_SCALARS[b]
        return (ct, C_XIOM[ct])
    if b in C_PTR_ALIAS:
        return (C_PTR_ALIAS[b], "*UInt8")
    if b in enums or b in EXT_ENUMS:
        return ("int32_t", "Int32")
    if b in BYVAL8:
        return ("uint64_t", "UInt64")
    if b in structs:
        return (b, None)
    if b in C_WINDOWS_TYPES:
        return (b, None)
    return (None, None)


def struct_closure(roots, structs):
    """DFS closure of struct-by-value structs; -> ordered list (deps first)."""
    order = []
    seen = set()

    def visit(name, chain):
        if name in seen or name not in structs or structs[name] is None:
            return
        if name in chain:
            return
        seen.add(name)
        for base, _stars, _mn, _arr in structs[name]:
            if base in structs:
                visit(base, chain | {name})
        order.append(name)

    for r in roots:
        visit(r, set())
    return order


def emit_types_header(name, closure, structs, enums, typedefs, extra_guard):
    """C definitions for the closure (enum typedefs + struct defs)."""
    lines = [
        "/* GENERATED by tools/gen_dx12.py from the pinned headers -- do not edit.",
        " * C definitions of the struct closure used by the typed shims",
        " * (sret / by-value normal forms).  Layout oracle: see",
        " * tools/struct_dump.cpp + docs/struct_dump.txt. */",
        "#ifndef %s" % extra_guard,
        "#define %s" % extra_guard,
        "",
        "#include <windows.h>",
        "#include <stdint.h>",
        "",
    ]
    enum_names = set()
    for sn in closure:
        for base, _stars, _mn, _arr in structs[sn]:
            if base not in structs and base not in C_SCALARS \
                    and base not in C_PTR_ALIAS and base not in C_WINDOWS_TYPES \
                    and base not in typedefs:
                enum_names.add(base)
    for en in sorted(enum_names):
        lines.append("typedef int32_t %s;" % en)
    lines.append("")
    for sn in closure:
        lines.append("typedef struct %s {" % sn)
        for base, stars, mn, arr in structs[sn]:
            if stars:
                ctype = "const void*" if base.startswith("LP") else "void*"
            elif base in C_SCALARS:
                ctype = C_SCALARS[base]
            elif base in C_PTR_ALIAS:
                ctype = C_PTR_ALIAS[base]
            elif base in C_WINDOWS_TYPES:
                ctype = base
            elif base in structs:
                ctype = base
            else:
                ctype = "int32_t"
            lines.append("  %s %s%s;" % (ctype, mn, arr))
        lines.append("} %s;" % sn)
        lines.append("")
    lines.append("#endif /* %s */" % extra_guard)
    with open(os.path.join(SRC, name), "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(lines).rstrip() + "\n")
    return sorted(enum_names)


def typed_shim_name(iface, method):
    return (snake(iface) + "_" + snake(method)).replace("id3_d12", "d3d12").replace("d3_d12", "d3d12")


def plan_surface(vtbl, bases, enums, typedefs, structs, skips_key, manifest):
    """Own-method plan + typed (struct-by-value) entries for one oracle set.

    Shared by the d3d12 and dxgi emission passes; `skips_key` is the
    manifest list name for surface skips ("skips" / "dxgi_skips").
    """
    plan = OrderedDict()
    typed = []
    for iface, rows in vtbl.items():
        base = bases.get(iface)
        base_len = len(vtbl.get(base, [])) if base else 0
        own = []
        for slot in range(base_len, len(rows)):
            ret, name, params = rows[slot]
            where = "%s.%s" % (iface, name)
            mm = re.match(r"^(?P<base>[\w\s]+?)\s*(?P<stars>\*+)?$", ret)
            rbase = norm(mm.group("base")) if mm else ret
            rstars = (mm.group("stars") or "") if mm else ""
            c_ret, x_ret = norm_type(rbase, rstars, enums, typedefs, structs, where, [])
            if c_ret is None:
                manifest[skips_key].append({"iface": iface, "method": name, "reason": x_ret})
                m_struct = re.match(r"struct-by-value (\w+)", str(x_ret))
                if m_struct:
                    typed.append({"iface": iface, "method": name, "slot": slot,
                                  "ret_struct": m_struct.group(1), "params": params})
                continue
            conv = []
            bad = None
            bad_struct = None
            for pbase, pname in params:
                stars = "*" if "*" in pbase else ""
                base_clean = norm(pbase.replace("*", " "))
                c_t, x_t = norm_type(base_clean, stars, enums, typedefs, structs, where + ":" + pname, [])
                if c_t is None:
                    bad = "%s (%s)" % (x_t, pname)
                    m_s = re.match(r"struct-by-value (\w+)", str(x_t))
                    if m_s:
                        bad_struct = m_s.group(1)
                    break
                conv.append(((c_t, pname), (x_t, pname)))
            if bad:
                manifest[skips_key].append({"iface": iface, "method": name, "reason": "param " + bad})
                if bad_struct:
                    typed.append({"iface": iface, "method": name, "slot": slot,
                                  "ret_struct": None, "c_ret": c_ret,
                                  "x_ret": x_ret, "params": params,
                                  "byval_struct": bad_struct})
                continue
            own.append((slot, c_ret, x_ret, name, conv))
        if own:
            plan[iface] = own
    return plan, typed


def emit_iface_files(plan, c_lines, file_prefix, module_prefix, manifest,
                     groups_key="groups", counter_key="own_methods_emitted"):
    """Emit iface_<NN>.xi groups + collect C shims into c_lines."""
    groups = list(plan.items())
    chunks = [groups[i:i + IFACES_PER_FILE] for i in range(0, len(groups), IFACES_PER_FILE)]
    for gi, chunk in enumerate(chunks, 1):
        gname = "%02d" % gi
        lines = [
            "// GENERATED by tools/gen_dx12.py from the pinned headers -- do not edit.",
            "module %s_%s" % (module_prefix, gname),
            "",
        ]
        for iface, methods in chunk:
            lines.append("// ---- %s ----" % iface)
            lines.append("")
            for slot, c_ret, x_ret, name, conv in methods:
                cfn = "xd12c_%s_%s" % (iface, name)
                fnname = dxgi_normalize(snake(iface) + "_" + snake(name))
                cparams = ", ".join(["void* obj"] + ["%s %s" % (t, n) for (t, n), _ in conv])
                xparams = ", ".join(["obj: Int"] + ["%s: %s" % (n, t) for _, (t, n) in conv])
                cdecl = "%s __cdecl %s(%s)" % (c_ret if c_ret != "void" else "void", cfn, cparams)
                lines.append("extern \"C\" {")
                lines.append("  fn %s(%s) -> %s;" % (cfn, xparams, RET_XIOM[c_ret]) if c_ret != "void"
                    else "  fn %s(%s);" % (cfn, xparams))
                lines.append("}")
                if c_ret == "void":
                    lines.append("pub fn %s(%s)" % (fnname, xparams))
                    lines.append("  requires: obj != 0")
                    lines.append("{")
                    lines.append("  unsafe { %s(%s); }" % (cfn, ", ".join(["obj"] + [n for _, (_, n) in conv])))
                    lines.append("}")
                else:
                    xr = RET_XIOM[c_ret]
                    lines.append("pub fn %s(%s) -> %s" % (fnname, xparams, xr))
                    lines.append("  requires: obj != 0")
                    lines.append("{")
                    lines.append("  unsafe { return %s(%s); }" % (cfn, ", ".join(["obj"] + [n for _, (_, n) in conv])))
                    lines.append("}")
                lines.append("")
                c_lines.append("%s {" % cdecl)
                c_lines.append("  typedef %s (WINAPI *FN)(%s);" % (c_ret if c_ret != "void" else "void",
                    ", ".join(["void*"] + [t for (t, _), _ in conv])))
                c_lines.append("  FN fn = (FN)((*(void***)obj)[%d]);" % slot)
                call = "fn(obj%s)" % ("" if not conv else ", " + ", ".join(n for _, (_, n) in conv))
                if c_ret == "void":
                    c_lines.append("  %s;" % call)
                else:
                    c_lines.append("  return %s;" % call)
                c_lines.append("}")
                c_lines.append("")
                manifest[counter_key] += 1
        with open(os.path.join(SRC, "%s_%s.xi" % (file_prefix, gname)), "w",
                  encoding="ascii", newline="\n") as fh:
            fh.write("\n".join(lines).rstrip() + "\n")
        manifest[groups_key].append({"file": "%s_%s.xi" % (file_prefix, gname),
                                     "interfaces": [i for i, _ in chunk]})


def dxgi_normalize(name):
    return name.replace("id3_d12", "d3d12").replace("d3_d12", "d3d12").replace("idxgi", "dxgi")


def emit_typed_shims(cfile, xfile, module, typed, structs, enums, typedefs,
                     manifest, probe_exclude=None, types_header="d3d12_types.gen.h"):
    """C typed shims + XIOM wrappers for struct-by-value methods.

    Normal forms:
      sret  -> `int32_t shim(obj, <args>, void* out_slot)`; C calls the
               typed vtable method and memcpy()s the result into the
               XIOM-owned out slot (B-20 discipline).
      byval -> the struct param arrives as an owned slot pointer; C copies
               it into a local typed value and calls the method.
    """
    c_lines = [
        "/* GENERATED by tools/gen_dx12.py from the pinned headers -- do not edit.",
        " * Typed shims for struct-by-value methods (sret > 8B returns and",
        " * by-value struct params): the C side owns the normal form and copies",
        " * through XIOM-owned slots. */",
        '#include "%s"' % types_header,
        "#include <string.h>",
        "",
    ]
    x_lines = [
        "// GENERATED by tools/gen_dx12.py from the pinned headers -- do not edit.",
        "module %s" % module,
        "",
    ]
    emitted = []
    for t in typed:
        iface, method, slot = t["iface"], t["method"], t["slot"]
        base_name = typed_shim_name(iface, method)
        cfn = "xd12s_" + base_name
        # param resolution: public C params (slot pointer for by-value
        # structs) vs the vtable FN param types (the struct itself).
        c_params = []      # (pub_type, name)
        fn_params = []     # types for the FN typedef, after `void* obj`
        x_params = []
        call_args = []
        ok = True
        for pbase, pname in t["params"]:
            stars = "*" if "*" in pbase else ""
            pconst = "const " if norm(pbase).startswith("const") else ""
            base_clean = norm(pbase.replace("*", " "))
            ct, xt = c_and_xiom_type(base_clean, stars, enums, structs, typedefs)
            if ct is not None and ct in structs:
                # by-value struct param: slot pointer on the public edge
                c_params.append(("const void*", pname + "_slot"))
                fn_params.append(ct)
                x_params.append((pname + "_slot", "*UInt8"))
                call_args.append("*(%s*)%s" % (ct, pname + "_slot"))
                continue
            if ct is None:
                ok = False
                break
            if stars and base_clean in structs:
                ct = pconst + base_clean + "*"
            elif stars:
                ct = pconst + ct
            c_params.append((ct, pname))
            fn_params.append(ct)
            x_params.append((pname, xt))
            call_args.append(pname)
        if not ok:
            manifest["typed_skips"].append(
                {"iface": iface, "method": method, "reason": "param unmapped"})
            continue
        ret_struct = t.get("ret_struct")
        if ret_struct:
            # x64 MS ABI for a MEMBER returning a >8B aggregate: RCX=this,
            # RDX=hidden out pointer, visible args shift right.  Declare the
            # FN as a free function with (self, out, ...) so the generated
            # call matches that exactly; the out pointer IS the XIOM-owned
            # slot (no local copy).
            fn_ret = ret_struct
            shim_ret = "int32_t"
            cfn_params = ["void* obj"] + ["%s %s" % (c, n) for c, n in c_params] + ["void* out_slot"]
            x_params_all = [("obj", "Int")] + x_params + [("out_slot", "*UInt8")]
            fn_ptr_sig = "void (WINAPI *FN)(void*, void*%s)" % (
                "".join(", " + c for c in fn_params))
            body = [
                "int32_t __cdecl %s(%s) {" % (cfn, ", ".join(cfn_params)),
                "  typedef %s;" % fn_ptr_sig,
                "  if (!obj || !out_slot) return -1;",
                "  ((FN)((*(void***)obj)[%d]))(obj, out_slot%s);" % (
                    slot, "".join(", " + a for a in call_args)),
                "  return 0;",
                "}",
                "",
            ]
            x_ret = "Int"
        else:
            # by-value param method: scalar return passes through
            x_ret = t["x_ret"]
            fn_ret = t["c_ret"]
            shim_ret = t["c_ret"]
            cfn_params = ["void* obj"] + ["%s %s" % (c, n) for c, n in c_params]
            x_params_all = [("obj", "Int")] + x_params
            fn_ptr_sig = "%s (WINAPI *FN)(%s)" % (
                fn_ret, ", ".join(["void*"] + fn_params))
            body = [
                "%s __cdecl %s(%s) {" % (shim_ret, cfn, ", ".join(cfn_params)),
                "  typedef %s;" % fn_ptr_sig,
                "  return ((FN)((*(void***)obj)[%d]))(obj%s);" % (
                    slot, "".join(", " + a for a in call_args)),
                "}",
                "",
            ]
        c_lines.extend(body)
        x_ext = ", ".join("%s: %s" % (n, ty) for n, ty in x_params_all)
        x_lines.append("extern \"C\" {")
        x_lines.append("  fn %s(%s) -> %s;" % (cfn, x_ext, x_ret))
        x_lines.append("}")
        x_lines.append("pub fn %s(%s) -> %s" % (base_name, x_ext, x_ret))
        x_lines.append("  requires: obj != 0")
        x_lines.append("{")
        x_lines.append("  unsafe { return %s(%s); }" % (cfn, ", ".join(n for n, _t in x_params_all)))
        x_lines.append("}")
        x_lines.append("")
        emitted.append({"iface": iface, "method": method, "shim": cfn,
                        "xiom": base_name, "slot": slot,
                        "kind": "sret" if ret_struct else "byval-param"})
        manifest["typed_shims"] += 1
    # sizeof probes: oracle (clang dump) vs the build compiler, cross-checked
    # by the suite against D3D12_SIZEOF_* / DXGI_SIZEOF_* constants.
    roots = set()
    for t in typed:
        if t.get("ret_struct"):
            roots.add(t["ret_struct"])
        if t.get("byval_struct"):
            roots.add(t["byval_struct"])
        for pbase, _pname in t["params"]:
            pbase_clean = norm(pbase.replace("*", " "))
            if pbase_clean in structs and structs[pbase_clean] is not None:
                roots.add(pbase_clean)
    for sn in struct_closure(sorted(roots), structs):
        if probe_exclude and sn in probe_exclude:
            continue
        sname = dxgi_normalize(snake(sn))
        cfn = "xd12s_sizeof_" + sname
        c_lines.append("int __cdecl %s(void) { return (int)sizeof(%s); }" % (cfn, sn))
        x_lines.append("extern \"C\" {")
        x_lines.append("  fn %s() -> Int32;" % cfn)
        x_lines.append("}")
        x_lines.append("pub fn dx12_sizeof_%s() -> Int" % sname)
        x_lines.append("  requires: true")
        x_lines.append("{")
        x_lines.append("  unsafe { return %s() as Int; }" % cfn)
        x_lines.append("}")
        x_lines.append("")
        manifest["size_probes"] += 1
    with open(os.path.join(SRC, cfile), "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(c_lines).rstrip() + "\n")
    with open(os.path.join(SRC, xfile), "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(x_lines).rstrip() + "\n")
    return emitted


def emit_struct_dump(structs_by_source, path):
    """tools/struct_dump.cpp: sizeof + offsetof for every parseable struct."""
    lines = [
        "// GENERATED by tools/gen_dx12.py -- do not edit.",
        "// Struct metadata oracle: sizeof + offsetof vs the pinned headers.",
        "#include <cstddef>",
        "#include <cstdio>",
        "#include <windows.h>",
    ]
    for inc in structs_by_source["includes"]:
        lines.append('#include %s' % inc)
    lines.append("")
    lines.append("int main(void) {")
    for name, members in structs_by_source["structs"].items():
        if members is None:
            continue
        lines.append('  printf("SIZE %s %%zu\\n", sizeof(%s));' % (name, name))
        for _base, _stars, mn, _arr in members:
            lines.append('  printf("OFF %s %s %%zu\\n", offsetof(%s, %s));'
                         % (name, mn, name, mn))
    lines.append("  return 0;")
    lines.append("}")
    with open(path, "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    return path


def main():
    enum_names, struct_names, typedefs, vtbl, bases, iids, freefns, h = load_header()
    enums = load_enums(h)
    # Struct parsing spans d3d12.h + its direct includes present in the clone
    # (dxgicommon.h declares DXGI_SAMPLE_DESC, a member of RESOURCE_DESC).
    core_texts = [h]
    for extra in ("dxgicommon.h", "dxgiformat.h"):
        p = os.path.join(DX_HEADERS, extra)
        if os.path.exists(p):
            core_texts.append(open(p, encoding="utf-8", errors="replace").read())
    structs, struct_skips = parse_struct_defs("\n".join(core_texts))

    if "--emit-dump" in sys.argv:
        dump_structs = OrderedDict(structs)
        includes = ['"d3d12.h"']
        if os.path.exists(DXGI_HEADERS[0]):
            _, _, _, _, _, _, _, dh = load_header(DXGI_HEADERS)
            d_structs, d_skips = parse_struct_defs(dh)
            for k, v in d_structs.items():
                dump_structs.setdefault(k, v)
            includes.extend(["<dxgi.h>", "<dxgi1_2.h>", "<dxgi1_3.h>",
                             "<dxgi1_4.h>", "<dxgi1_5.h>", "<dxgi1_6.h>"])
        path = emit_struct_dump(
            {"includes": includes, "structs": dump_structs},
            os.path.join(ROOT, "tools", "struct_dump.cpp"))
        parsed = sum(1 for v in dump_structs.values() if v is not None)
        print("struct dump emitted: %s (parseable=%d)" % (path, parsed))
        return 0

    manifest = {
        "oracle": D3D12_H,
        "interfaces": len(vtbl),
        "vtbl_rows": sum(len(v) for v in vtbl.values()),
        "own_methods_emitted": 0,
        "free_functions_emitted": 0,
        "consts_emitted": 0,
        "typed_shims": 0,
        "typed_skips": [],
        "size_probes": 0,
        "structs_parsed": sum(1 for v in structs.values() if v is not None),
        "struct_skips": struct_skips,
        "skips": [],
        "groups": [],
        "dxgi_interfaces": 0,
        "dxgi_vtbl_rows": 0,
        "dxgi_own_methods": 0,
        "dxgi_free_functions": 0,
        "dxgi_consts": 0,
        "dxgi_typed_shims": 0,
        "dxgi_skips": [],
        "dxgi_groups": [],
    }

    # ---- plan own methods with absolute slots (shared helper) ----
    plan, typed = plan_surface(vtbl, bases, enum_names, typedefs,
                               struct_names, "skips", manifest)

    # ---- emit iface_<g>.xi + collect C ----
    c_lines = [
        "/* GENERATED by tools/gen_dx12.py from DirectX-Headers (461ef513) -- do not edit.",
        " * Normalized COM/vtable call shims: slot-index calls over the object's",
        " * vtable (x64 WINAPI).  Free-function shims resolve lazily. */",
    ]
    c_lines.append('#include <windows.h>')
    c_lines.append('#include <stdint.h>')
    c_lines.append("")
    c_lines.append("void* __cdecl xd12_resolve(const char* name);")
    c_lines.append("")

    groups = list(plan.items())
    chunks = [groups[i:i + IFACES_PER_FILE] for i in range(0, len(groups), IFACES_PER_FILE)]
    for gi, chunk in enumerate(chunks, 1):
        gname = "%02d" % gi
        lines = [
            "// GENERATED by tools/gen_dx12.py from DirectX-Headers -- do not edit.",
            "module xiom.dx12.iface_%s" % gname,
            "",
        ]
        for iface, methods in chunk:
            lines.append("// ---- %s ----" % iface)
            lines.append("")
            for slot, c_ret, x_ret, name, conv in methods:
                cfn = "xd12c_%s_%s" % (iface, name)
                fnname = (snake(iface) + "_" + snake(name)).replace("id3_d12", "d3d12").replace("d3_d12", "d3d12")
                cparams = ", ".join(["void* obj"] + ["%s %s" % (t, n) for (t, n), _ in conv])
                xparams = ", ".join(["obj: Int"] + ["%s: %s" % (n, t) for _, (t, n) in conv])
                cdecl = "%s __cdecl %s(%s)" % (c_ret if c_ret != "void" else "void", cfn, cparams)
                lines.append("extern \"C\" {")
                lines.append("  fn %s(%s) -> %s;" % (cfn, xparams, RET_XIOM[c_ret]) if c_ret != "void"
                    else "  fn %s(%s);" % (cfn, xparams))
                lines.append("}")
                if c_ret == "void":
                    lines.append("pub fn %s(%s)" % (fnname, xparams))
                    lines.append("  requires: obj != 0")
                    lines.append("{")
                    lines.append("  unsafe { %s(%s); }" % (cfn, ", ".join(["obj"] + [n for _, (_, n) in conv])))
                    lines.append("}")
                else:
                    xr = RET_XIOM[c_ret]
                    lines.append("pub fn %s(%s) -> %s" % (fnname, xparams, xr))
                    lines.append("  requires: obj != 0")
                    lines.append("{")
                    lines.append("  unsafe { return %s(%s); }" % (cfn, ", ".join(["obj"] + [n for _, (_, n) in conv])))
                    lines.append("}")
                lines.append("")
                # C shim
                c_lines.append("%s {" % cdecl.replace("__cdecl", "__cdecl"))
                c_lines.append("  typedef %s (WINAPI *FN)(%s);" % (c_ret if c_ret != "void" else "void",
                    ", ".join(["void*"] + [t for (t, _), _ in conv])))
                c_lines.append("  FN fn = (FN)((*(void***)obj)[%d]);" % slot)
                call = "fn(obj%s)" % ("" if not conv else ", " + ", ".join(n for _, (_, n) in conv))
                if c_ret == "void":
                    c_lines.append("  %s;" % call)
                else:
                    c_lines.append("  return %s;" % call)
                c_lines.append("}")
                c_lines.append("")
                manifest["own_methods_emitted"] += 1
        with open(os.path.join(SRC, "iface_%s.xi" % gname), "w", encoding="ascii", newline="\n") as fh:
            fh.write("\n".join(lines).rstrip() + "\n")
        manifest["groups"].append({"file": "iface_%s.xi" % gname,
                                   "interfaces": [i for i, _ in chunk]})

    # ---- free functions ----
    flines = [
        "// GENERATED by tools/gen_dx12.py from DirectX-Headers -- do not edit.",
        "module xiom.dx12.functions",
        "",
    ]
    for name, params in freefns:
        conv = []
        bad = None
        for pbase, pname in []:
            pass
        # parse params (SAL-stripped) with the same normalizer
        for piece in split_params(params):
            piece = strip_sal(piece)
            if not piece:
                continue
            mm = re.match(r"^(?P<base>[A-Za-z_][\w\s\*]*?)\s*(?P<stars>\*+)?\s*(?P<name>[A-Za-z_]\w*)?\s*$", piece)
            if not mm:
                bad = piece
                break
            c_t, x_t = norm_type(norm(mm.group("base")), mm.group("stars") or "", enum_names, typedefs, struct_names, name, manifest["skips"])
            if c_t is None:
                bad = x_t
                break
            pname = mm.group("name") or ("arg%d" % len(conv))
            conv.append(((c_t, pname), (x_t, pname)))
        if bad:
            manifest["skips"].append({"func": name, "reason": bad})
            continue
        # return type is HRESULT for all 9 currently
        cfn = "xd12f_%s" % name
        xparams = ", ".join("%s: %s" % (n, t) for _, (t, n) in conv)
        flines.append("extern \"C\" {")
        flines.append("  fn %s(%s) -> Int32;" % (cfn, xparams) if xparams else "  fn %s() -> Int32;" % cfn)
        flines.append("}")
        flines.append("pub fn %s(%s) -> Int32" % (snake(name).replace("d3_d12", "d3d12"), xparams))
        flines.append("  requires: true")
        flines.append("{")
        flines.append("  unsafe { return %s(%s); }" % (cfn, ", ".join(n for _, (_, n) in conv)))
        flines.append("}")
        flines.append("")
        c_lines.append("int32_t __cdecl %s(%s) {" % (cfn, ", ".join("%s %s" % (t, n) for (t, n), _ in conv) if conv else "void"))
        c_lines.append('  typedef int32_t (WINAPI *FN)(%s);' % ", ".join(t for (t, _), _ in conv))
        c_lines.append('  void* p = xd12_resolve("%s");' % name)
        c_lines.append('  if (!p) return (int32_t)0x80004005; /* E_FAIL */')
        c_lines.append('  return ((FN)p)(%s);' % ", ".join(n for _, (_, n) in conv))
        c_lines.append("}")
        c_lines.append("")
        manifest["free_functions_emitted"] += 1

    with open(os.path.join(SRC, "functions.xi"), "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(flines).rstrip() + "\n")

    # ---- consts ----
    names = sorted(enums["values"].keys())
    chunks = [names[i:i + CONSTS_PER_FILE] for i in range(0, len(names), CONSTS_PER_FILE)]
    for ci, chunk in enumerate(chunks, 1):
        lines = [
            "// GENERATED by tools/gen_dx12.py from DirectX-Headers -- do not edit.",
            "module xiom.dx12.consts_%d" % ci,
            "",
        ]
        for n in chunk:
            v = enums["values"][n]
            lines.append("pub const %s: Int = %s;" % (n, ("0x%X" % v) if v >= 0 else str(v)))
            manifest["consts_emitted"] += 1
        with open(os.path.join(SRC, "consts_%d.xi" % ci), "w", encoding="ascii", newline="\n") as fh:
            fh.write("\n".join(lines).rstrip() + "\n")

    with open(os.path.join(SRC, "d3d12_calls.c"), "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(c_lines).rstrip() + "\n")

    # ---- IID table include (C) for the probe bridge helper ----
    CORE_IIDS = [
        "ID3D12Device", "ID3D12CommandAllocator", "ID3D12CommandQueue",
        "ID3D12CommandList", "ID3D12GraphicsCommandList", "ID3D12Resource",
        "ID3D12Fence", "ID3D12DescriptorHeap", "ID3D12RootSignature",
        "ID3D12PipelineState", "ID3D12Heap", "ID3D12QueryHeap",
    ]
    inc = [
        "/* GENERATED by tools/gen_dx12.py -- core IIDs for xd12_iid(). */",
        "static const unsigned char g_xd12_iids[][16] = {",
    ]
    order = []
    for iname in CORE_IIDS:
        g = iids.get(iname)
        if not g:
            continue
        parts = [p.strip() for p in g.split(",")]
        if len(parts) != 11:
            continue
        d1 = int(parts[0], 16) if parts[0].lower().startswith("0x") else int(parts[0])
        d2 = int(parts[1], 16) if parts[1].lower().startswith("0x") else int(parts[1])
        d3 = int(parts[2], 16) if parts[2].lower().startswith("0x") else int(parts[2])
        b = [int(p, 16) if p.lower().startswith("0x") else int(p) for p in parts[3:]]
        bs = [d1 & 0xFF, (d1 >> 8) & 0xFF, (d1 >> 16) & 0xFF, (d1 >> 24) & 0xFF,
              d2 & 0xFF, (d2 >> 8) & 0xFF, d3 & 0xFF, (d3 >> 8) & 0xFF] + b
        inc.append("  { /* %s */ %s }," % (iname, ", ".join("0x%02X" % x for x in bs)))
        order.append(iname)
    inc.append("};")
    inc.append("static const int g_xd12_iid_count = %d;" % len(order))
    with open(os.path.join(SRC, "d3d12_iids.inc"), "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(inc) + "\n")

    # ---- typed shims (struct-by-value normal forms) + types header ----
    core_closure = []
    if typed:
        roots = set()
        for t in typed:
            if t.get("ret_struct"):
                roots.add(t["ret_struct"])
            if t.get("byval_struct"):
                roots.add(t["byval_struct"])
            for pbase, _pn in t["params"]:
                pc = norm(pbase.replace("*", " "))
                if pc in structs and structs[pc] is not None:
                    roots.add(pc)
        core_closure = struct_closure(sorted(roots), structs)
        emit_types_header("d3d12_types.gen.h", core_closure, structs, enum_names,
                          typedefs, "XD12_TYPES_GEN_H")
        emit_typed_shims("d3d12_structs.c", "structs.xi",
                         "xiom.dx12.structs", typed, structs, enum_names,
                         typedefs, manifest)

    # ---- DXGI (dxgi.dll): full IDXGI* surface + free functions ----
    dxgi_structs = OrderedDict()
    if os.path.exists(DXGI_HEADERS[0]):
        d_enum_names, d_struct_names, d_typedefs, d_vtbl, d_bases, d_iids, d_freefns, dh = load_header(DXGI_HEADERS)
        d_enums = OrderedDict()
        d_enum_skips = []
        for p in DXGI_HEADERS:
            e = load_enums(open(p, encoding="utf-8", errors="replace").read())
            for k, v in e["values"].items():
                d_enums.setdefault(k, v)
            d_enum_skips.extend(e["skips"])
        d_structs, d_struct_skips = parse_struct_defs(dh)
        for k, v in d_structs.items():
            dxgi_structs.setdefault(k, v)
        manifest["struct_skips"].extend(d_struct_skips)
        manifest["structs_parsed"] += sum(1 for v in d_structs.values() if v is not None)

        manifest["dxgi_interfaces"] = len(d_vtbl)
        manifest["dxgi_vtbl_rows"] = sum(len(v) for v in d_vtbl.values())

        d_plan, d_typed = plan_surface(d_vtbl, d_bases, d_enum_names, d_typedefs,
                                       d_struct_names, "dxgi_skips", manifest)
        d_c_lines = [
            "/* GENERATED by tools/gen_dx12.py from the pinned DXGI headers -- do not edit.",
            " * Normalized COM/vtable call shims over dxgi.dll objects. */",
            '#include <windows.h>',
            '#include <stdint.h>',
            "",
            "void* __cdecl xd12_resolve_dxgi(const char* name);",
            "",
        ]
        before = manifest["own_methods_emitted"]
        emit_iface_files(d_plan, d_c_lines, "dxgi_iface", "xiom.dx12.dxgi_iface",
                         manifest, "dxgi_groups", "dxgi_own_methods")
        manifest["own_methods_emitted"] = before

        # free functions -> dxgi_functions.xi + dxgi_calls.c
        df_lines = [
            "// GENERATED by tools/gen_dx12.py from the pinned DXGI headers -- do not edit.",
            "module xiom.dx12.dxgi_functions",
            "",
        ]
        for name, params in d_freefns:
            conv = []
            bad = None
            for piece in split_params(params):
                piece = strip_sal(piece)
                if not piece:
                    continue
                mm = re.match(r"^(?P<base>[A-Za-z_][\w\s\*]*?)\s*(?P<stars>\*+)?\s*(?P<name>[A-Za-z_]\w*)?\s*$", piece)
                if not mm:
                    bad = piece
                    break
                c_t, x_t = norm_type(norm(mm.group("base")), mm.group("stars") or "",
                                     d_enum_names, d_typedefs, d_struct_names, name, [])
                if c_t is None:
                    bad = x_t
                    break
                pname = mm.group("name") or ("arg%d" % len(conv))
                conv.append(((c_t, pname), (x_t, pname)))
            if bad:
                manifest["dxgi_skips"].append({"func": name, "reason": bad})
                continue
            cfn = "xd12f_%s" % name
            xparams = ", ".join("%s: %s" % (n, t) for _, (t, n) in conv)
            df_lines.append("extern \"C\" {")
            df_lines.append("  fn %s(%s) -> Int32;" % (cfn, xparams) if xparams else "  fn %s() -> Int32;" % cfn)
            df_lines.append("}")
            df_lines.append("pub fn %s(%s) -> Int32" % (dxgi_normalize(snake(name)), xparams))
            df_lines.append("  requires: true")
            df_lines.append("{")
            df_lines.append("  unsafe { return %s(%s); }" % (cfn, ", ".join(n for _, (_, n) in conv)))
            df_lines.append("}")
            df_lines.append("")
            d_c_lines.append("int32_t __cdecl %s(%s) {" % (cfn, ", ".join("%s %s" % (t, n) for (t, n), _ in conv) if conv else "void"))
            d_c_lines.append('  typedef int32_t (WINAPI *FN)(%s);' % ", ".join(t for (t, _), _ in conv))
            d_c_lines.append('  void* p = xd12_resolve_dxgi("%s");' % name)
            d_c_lines.append('  if (!p) return (int32_t)0x80004005; /* E_FAIL */')
            d_c_lines.append('  return ((FN)p)(%s);' % ", ".join(n for _, (_, n) in conv))
            d_c_lines.append("}")
            d_c_lines.append("")
            manifest["dxgi_free_functions"] += 1
        with open(os.path.join(SRC, "dxgi_functions.xi"), "w", encoding="ascii", newline="\n") as fh:
            fh.write("\n".join(df_lines).rstrip() + "\n")

        # consts -> dxgi_consts_<n>.xi
        dnames = sorted(d_enums.keys())
        dchunks = [dnames[i:i + CONSTS_PER_FILE] for i in range(0, len(dnames), CONSTS_PER_FILE)]
        for ci, chunk in enumerate(dchunks, 1):
            lines = [
                "// GENERATED by tools/gen_dx12.py from the pinned DXGI headers -- do not edit.",
                "module xiom.dx12.dxgi_consts_%d" % ci,
                "",
            ]
            for n in chunk:
                v = d_enums[n]
                lines.append("pub const %s: Int = %s;" % (n, ("0x%X" % v) if v >= 0 else str(v)))
                manifest["dxgi_consts"] += 1
            with open(os.path.join(SRC, "dxgi_consts_%d.xi" % ci), "w", encoding="ascii", newline="\n") as fh:
                fh.write("\n".join(lines).rstrip() + "\n")

        # IID table for the bridge helper
        DXGI_IIDS = [
            "IDXGIObject", "IDXGIFactory", "IDXGIFactory1", "IDXGIFactory2",
            "IDXGIFactory3", "IDXGIFactory4", "IDXGIAdapter", "IDXGIAdapter1",
            "IDXGIAdapter4", "IDXGIDevice", "IDXGIOutput", "IDXGISwapChain",
            "IDXGISwapChain1", "IDXGISwapChain3", "IDXGIResource", "IDXGISurface",
        ]
        dinc = [
            "/* GENERATED by tools/gen_dx12.py -- DXGI IIDs for xd12_dxgi_iid(). */",
            "static const unsigned char g_xd12_dxgi_iids[][16] = {",
        ]
        dorder = []
        for iname in DXGI_IIDS:
            g = d_iids.get(iname)
            if not g:
                continue
            parts = [p.strip() for p in g.split(",")]
            if len(parts) != 11:
                continue
            d1 = int(parts[0], 16) if parts[0].lower().startswith("0x") else int(parts[0])
            d2 = int(parts[1], 16) if parts[1].lower().startswith("0x") else int(parts[1])
            d3 = int(parts[2], 16) if parts[2].lower().startswith("0x") else int(parts[2])
            bb = [int(p, 16) if p.lower().startswith("0x") else int(p) for p in parts[3:]]
            bs = [d1 & 0xFF, (d1 >> 8) & 0xFF, (d1 >> 16) & 0xFF, (d1 >> 24) & 0xFF,
                  d2 & 0xFF, (d2 >> 8) & 0xFF, d3 & 0xFF, (d3 >> 8) & 0xFF] + bb
            dinc.append("  { /* %s */ %s }," % (iname, ", ".join("0x%02X" % x for x in bs)))
            dorder.append(iname)
        dinc.append("};")
        dinc.append("static const int g_xd12_dxgi_iid_count = %d;" % len(dorder))
        with open(os.path.join(SRC, "dxgi_iids.inc"), "w", encoding="ascii", newline="\n") as fh:
            fh.write("\n".join(dinc) + "\n")

        # typed shims (DXGI sret shapes) -> dxgi_structs.c/xi
        dtyped = d_typed
        if dtyped:
            droots = set()
            for t in dtyped:
                if t.get("ret_struct"):
                    droots.add(t["ret_struct"])
                if t.get("byval_struct"):
                    droots.add(t["byval_struct"])
                for pbase, _pn in t["params"]:
                    pc = norm(pbase.replace("*", " "))
                    if pc in d_structs and d_structs[pc] is not None:
                        droots.add(pc)
            dclosure = struct_closure(sorted(droots), d_structs)
            emit_types_header("dxgi_types.gen.h", dclosure, d_structs,
                              d_enum_names, d_typedefs, "XD12_DXGI_TYPES_GEN_H")
            emitted = emit_typed_shims("dxgi_structs.c", "dxgi_structs.xi",
                                       "xiom.dx12.dxgi_structs", dtyped,
                                       d_structs, d_enum_names, d_typedefs,
                                       manifest, probe_exclude=set(core_closure),
                                       types_header="dxgi_types.gen.h")
            manifest["dxgi_typed_shims"] = len(emitted)
        else:
            manifest["dxgi_typed_shims"] = 0

        with open(os.path.join(SRC, "dxgi_calls.c"), "w", encoding="ascii", newline="\n") as fh:
            fh.write("\n".join(d_c_lines).rstrip() + "\n")

    os.makedirs(DOCS, exist_ok=True)
    with open(os.path.join(DOCS, "gen_manifest.json"), "w", encoding="ascii", newline="\n") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
        fh.write("\n")

    print("interfaces: %d, vtbl rows: %d" % (manifest["interfaces"], manifest["vtbl_rows"]))
    print("own methods emitted: %d (skips %d)" % (manifest["own_methods_emitted"], len(manifest["skips"])))
    print("free functions emitted: %d" % manifest["free_functions_emitted"])
    print("consts emitted: %d" % manifest["consts_emitted"])
    print("typed shims: %d + dxgi %d (skips %d); structs parsed %d, skipped %d; size probes %d"
          % (manifest["typed_shims"], manifest["dxgi_typed_shims"],
             len(manifest["typed_skips"]),
             manifest["structs_parsed"], len(manifest["struct_skips"]),
             manifest["size_probes"]))
    print("dxgi: %d interfaces / %d vtbl rows / %d wrappers / %d free fns / %d consts (skips %d)"
          % (manifest["dxgi_interfaces"], manifest["dxgi_vtbl_rows"],
             manifest["dxgi_own_methods"], manifest["dxgi_free_functions"],
             manifest["dxgi_consts"], len(manifest["dxgi_skips"])))
    for sk in manifest["dxgi_skips"][:10]:
        key = sk.get("iface") or sk.get("func") or sk.get("name")
        print("  dxgi skip: %s -- %s" % (key, sk["reason"]))
    for sk in manifest["skips"][:15]:
        key = sk.get("iface") or sk.get("func") or sk.get("name")
        print("  skip: %s -- %s" % (key, sk["reason"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
