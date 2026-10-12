#!/usr/bin/env python3
"""XIOM xiom.dx12 surface generator (0.2.0 wave, slice 1).

Oracle: E:/repos/DirectX-Headers @ 461ef513, include/directx/d3d12.h
(SHA256 AFA193D3...).  Emits into packages/xiom-dx12/src/:
  iface_<g>.xi      -- XIOM wrappers, own methods per interface (grouped)
  functions.xi      -- XIOM wrappers for the 9 D3D12* free functions
  consts_<n>.xi     -- D3D12 enum values as pub const ... : Int
  d3d12_calls.c     -- normalized COM/vtable call shims (slot-index calls)
  gen_manifest.json (docs/) -- oracle vs emitted + skips

Deterministic; stdlib only.  Own methods = vtbl rows minus the base
interface's rows (COM order guarantees the base prefix).  Struct-by-value
returns > 8 bytes (sret) are SKIPPED in this slice (struct-metadata wave);
8-byte descriptor handles return as uint64 (RAX).
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


def load_header():
    h = open(D3D12_H, encoding="utf-8", errors="replace").read()
    enum_names = set(re.findall(r"typedef\s+enum\s+(D3D12_\w+)", h))
    brace_names = set(re.findall(r"\}\s*(D3D12_\w+)\s*;", h))
    struct_names = brace_names - enum_names
    typedefs = {}
    for base, name in re.findall(r"typedef\s+([A-Za-z_][\w\s\*]*?)\s+(D3D12_\w+)\s*;", h):
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
    for m in re.finditer(r"\n\w[\w\s\*]*?WINAPI (D3D12\w+)\(([^;]*?)\);", h, re.S):
        raw = COMMENT_RE.sub(" ", m.group(2))
        freefns.append((m.group(1), norm(raw)))
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
    if b in structs and b.startswith("D3D12_"):
        return (None, "struct-by-value %s" % b)
    return (None, "unmapped base %r" % b)


def main():
    enum_names, struct_names, typedefs, vtbl, bases, iids, freefns, h = load_header()
    enums = load_enums(h)

    manifest = {
        "oracle": D3D12_H,
        "interfaces": len(vtbl),
        "vtbl_rows": sum(len(v) for v in vtbl.values()),
        "own_methods_emitted": 0,
        "free_functions_emitted": 0,
        "consts_emitted": 0,
        "skips": [],
        "groups": [],
    }

    # ---- plan own methods with absolute slots ----
    plan = OrderedDict()  # iface -> list[(slot, c_ret, xiom_ret, name, [(c,p),(x,p)])]
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
            c_ret, x_ret = norm_type(rbase, rstars, enum_names, typedefs, struct_names, where, manifest["skips"])
            if c_ret is None:
                manifest["skips"].append({"iface": iface, "method": name, "reason": x_ret})
                continue
            conv = []
            bad = None
            for pbase, pname in params:
                stars = "*" if "*" in pbase else ""
                base_clean = norm(pbase.replace("*", " "))
                c_t, x_t = norm_type(base_clean, stars, enum_names, typedefs, struct_names, where + ":" + pname, manifest["skips"])
                if c_t is None:
                    bad = "%s (%s)" % (x_t, pname)
                    break
                conv.append(((c_t, pname), (x_t, pname)))
            if bad:
                manifest["skips"].append({"iface": iface, "method": name, "reason": "param " + bad})
                continue
            own.append((slot, c_ret, x_ret, name, conv))
        if own:
            plan[iface] = own

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

    os.makedirs(DOCS, exist_ok=True)
    with open(os.path.join(DOCS, "gen_manifest.json"), "w", encoding="ascii", newline="\n") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
        fh.write("\n")

    print("interfaces: %d, vtbl rows: %d" % (manifest["interfaces"], manifest["vtbl_rows"]))
    print("own methods emitted: %d (skips %d)" % (manifest["own_methods_emitted"], len(manifest["skips"])))
    print("free functions emitted: %d" % manifest["free_functions_emitted"])
    print("consts emitted: %d" % manifest["consts_emitted"])
    for sk in manifest["skips"][:15]:
        key = sk.get("iface") or sk.get("func") or sk.get("name")
        print("  skip: %s -- %s" % (key, sk["reason"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
