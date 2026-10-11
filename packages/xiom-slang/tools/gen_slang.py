#!/usr/bin/env python3
# ============================================================================
# gen_slang.py -- XIOM binding generator for the Slang C API.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# WHAT IT DOES (two oracles, cross-checked)
#   1. Header oracle: parses the C API function declarations out of
#      `slang.h` + `slang-deprecated.h` (the include chain of slang.h) --
#      `SLANG_API` functions including the legacy `sp*` and the `slang_*` API.
#      Also extracts every enum entry (named + anonymous flag enums) and the
#      integer `#define SLANG_*` macros, evaluating values to literals.
#   2. Export oracle: parses the PE export table of `slang.dll` with a pure
#      Python reader (no dumpbin dependency) and takes every exported name
#      that is C-ABI (`sp*`/`slang_*`). Records forwarder targets.
#   3. Cross-check: every exported C name must be declared in the headers;
#      header-declared functions that the DLL does not export are reported
#      (they are documented in docs/COVERAGE.md, not bound as resolved
#      symbols).
#
# EMITS (family-split XIOM modules, every file < 600 lines)
#   src/gen_syms.xi        symbol-name blob + oracle counts (the table)
#   src/gen_types.xi       typedef aliases (SlangResult, SlangInt, ...)
#   src/res_<fam>.xi       per-family resolver struct + fail-fast resolver +
#                          per-name count probe (suite metric)
#   src/wrap_<fam>.xi      typed wrapper per exported function
#   src/gen_const_<n>.xi   enum/macro constants as `pub const` literals
#   slang.xi               `module xiom.slang` loader entry (parent facade)
#   tools/oracle_manifest.json   committed machine-readable oracle evidence
#
# USAGE
#   python tools/gen_slang.py                 # defaults to the Vulkan SDK paths
#   python tools/gen_slang.py --header <dir> --dll <slang.dll> [--out <pkg dir>]
#
# The generator is deterministic: same inputs -> byte-identical outputs.
# ============================================================================

import json
import os
import re
import struct
import sys

DEFAULT_HEADER = r"C:\VulkanSDK\1.4.350.0\Include\slang"
DEFAULT_DLL = r"C:\VulkanSDK\1.4.350.0\Bin\slang.dll"
DEFAULT_OUT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

HEADER_FILES = ["slang.h", "slang-deprecated.h"]

# ----------------------------------------------------------------------------
# Small utilities
# ----------------------------------------------------------------------------


def strip_comments(text):
    # Block comments first, then line comments (string literals do not matter
    # for the declaration grammar we parse in these headers).
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    return text


def expand_xmacro_enums(text, header_dir):
    """Expand `#include` lines *inside enum bodies* (X-macro enums).

    The Slang headers build `enum SlangImageFormat` by including
    `slang-image-format-defs.h` under a `SLANG_FORMAT(NAME, DESC)` macro whose
    body concatenates `SLANG_IMAGE_FORMAT_##NAME`. We mirror the preprocessor
    for those sites so the constants oracle sees the real enum entries. Any
    include site we cannot expand is a hard error (never a silent gap).
    """
    out = []
    pos = 0
    for m in re.finditer(r"enum\s+\w*\s*(?::\s*[\w:]+)?\s*\{", text):
        i = m.end()
        depth = 1
        j = i
        while j < len(text) and depth > 0:
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
            j += 1
        body = text[i: j - 1]
        if "#include" not in body:
            continue
        macros = {}
        for dm in re.finditer(r"#\s*define\s+(\w+)\(([^)]*)\)\s*([^\n]*)", body):
            params = [p.strip() for p in dm.group(2).split(",") if p.strip()]
            macros[dm.group(1)] = (params, dm.group(3).strip())

        def make_replacer():
            def repl(im):
                fname = im.group(1)
                path = os.path.join(header_dir, fname)
                if not os.path.exists(path):
                    raise SystemExit("xmacro include not found: %s" % path)
                with open(path, "r", encoding="utf-8", errors="replace") as fh:
                    inc = strip_comments(fh.read())
                produced = []
                for line in inc.splitlines():
                    lm = re.match(r"\s*(\w+)\s*\((.*)\)\s*$", line)
                    if not lm or lm.group(1) not in macros:
                        continue
                    params, template = macros[lm.group(1)]
                    args = [a.strip() for a in split_top_level(lm.group(2))]
                    if len(args) != len(params):
                        raise SystemExit("xmacro arity mismatch: %s" % line)
                    t = template
                    for p, a in zip(params, args):
                        t = re.sub(r"([\w$]+)\s*##\s*" + re.escape(p) + r"\b",
                                   lambda cm, a=a: cm.group(1) + a, t)
                    for p, a in zip(params, args):
                        t = re.sub(r"\b" + re.escape(p) + r"\b", a, t)
                    produced.append(t)
                if not produced:
                    raise SystemExit("xmacro include produced no entries: %s" % fname)
                return "\n".join(produced)
            return repl

        body2 = re.sub(r'#\s*include\s+"([^"]+)"', make_replacer(), body)
        if "#include" in body2:
            raise SystemExit("unexpanded #include inside enum body: %r"
                             % body2[:120])
        out.append(text[pos:i])
        out.append(body2)
        pos = j - 1
    out.append(text[pos:])
    return "".join(out)


def split_top_level(text, sep=",", angle=False):    # angle=False: '<'/'<<' are NOT bracket tokens (enum bodies use shift
    # operators; only () [] {} group there). Param lists keep angle=True for
    # safety even though the Slang headers use no template params.
    opens = "<([{" if angle else "([{"
    closes = ">)]}" if angle else ")]}"
    parts = []
    depth = 0
    cur = []
    for ch in text:
        if ch in opens:
            depth += 1
        elif ch in closes:
            depth -= 1
        if ch == sep and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    if "".join(cur).strip():
        parts.append("".join(cur))
    return parts


SNAKE_OK = re.compile(r"^[a-z][a-z0-9_]*$")


def xiom_snake(name):
    """spReflectionTypeLayout_GetSize -> sp_reflection_type_layout_get_size."""
    out = []
    n = len(name)
    for i, ch in enumerate(name):
        if ch == "_":
            out.append("_")
            continue
        if ch.isupper():
            prev = name[i - 1] if i > 0 else ""
            nxt = name[i + 1] if i + 1 < n else ""
            boundary = False
            if prev and (prev.islower() or prev.isdigit()):
                boundary = True
            elif prev and prev.isupper() and nxt and nxt.islower():
                boundary = True
            if boundary and out and out[-1] != "_":
                out.append("_")
            out.append(ch.lower())
        else:
            out.append(ch)
    s = "".join(out)
    s = re.sub(r"_+", "_", s).strip("_")
    return s


# ----------------------------------------------------------------------------
# C expression evaluation (enum entries + integer macros)
# ----------------------------------------------------------------------------

C_EXPR_TOKEN = re.compile(
    r"0[xX][0-9a-fA-F]+[uUlL]*|[0-9]+[uUlL]*|[A-Za-z_]\w*|<<|>>|[()~!|&^+\-*/%<>]"
)


class CExprError(Exception):
    pass


def eval_c_expr(expr, symbols):
    """Evaluate a C constant expression with a symbol table (recursive)."""
    toks = C_EXPR_TOKEN.findall(expr)
    pos = [0]

    def peek():
        return toks[pos[0]] if pos[0] < len(toks) else None

    def take():
        t = peek()
        pos[0] += 1
        return t

    def atom():
        t = take()
        if t is None:
            raise CExprError("unexpected end")
        if t == "(":
            v = bitor()
            if take() != ")":
                raise CExprError("missing )")
            return v
        if t in ("-", "~", "!"):
            v = atom()
            if t == "-":
                return -v
            if t == "~":
                return ~v
            return 0 if v else 1
        if t in ("+",):
            return atom()
        if re.fullmatch(r"0[xX][0-9a-fA-F]+[uUlL]*", t):
            return int(re.sub(r"[uUlL]+$", "", t), 16)
        if re.fullmatch(r"[0-9]+[uUlL]*", t):
            return int(re.sub(r"[uUlL]+$", "", t))
        if re.fullmatch(r"[A-Za-z_]\w*", t):
            if t in symbols:
                return symbols[t]
            raise CExprError("unknown symbol %s" % t)
        raise CExprError("bad token %r" % t)

    def mul():
        v = atom()
        while peek() in ("*", "/", "%"):
            op = take()
            r = atom()
            if op == "*":
                v = v * r
            elif op == "/":
                if r == 0:
                    raise CExprError("div by zero")
                v = int(v / r)
            else:
                v = v % r
        return v

    def add():
        v = mul()
        while peek() in ("+", "-"):
            op = take()
            r = mul()
            v = v + r if op == "+" else v - r
        return v

    def shift():
        v = add()
        while peek() in ("<<", ">>"):
            op = take()
            r = add()
            v = v << r if op == "<<" else v >> r
        return v

    def band():
        v = shift()
        while peek() == "&":
            take()
            v = v & shift()
        return v

    def bxor():
        v = band()
        while peek() == "^":
            take()
            v = v ^ band()
        return v

    def bitor():
        v = bxor()
        while peek() == "|":
            take()
            v = v | bxor()
        return v

    result = bitor()
    if pos[0] != len(toks):
        raise CExprError("trailing tokens")
    return result


# ----------------------------------------------------------------------------
# Header parsing
# ----------------------------------------------------------------------------

SCALAR_TYPES = {
    "void": "void",
    "bool": "bool",
    "SlangBool": "bool",
    "int": "int32",
    "signed int": "int32",
    "int32_t": "int32",
    "SlangInt32": "int32",
    "SlangResult": "int32",
    "unsigned int": "uint32",
    "unsigned": "uint32",
    "uint32_t": "uint32",
    "SlangUInt32": "uint32",
    "int64_t": "int64",
    "SlangInt": "int64",
    "uint64_t": "uint64",
    "size_t": "uint64",
    "SlangUInt": "uint64",
    "SlangSizeT": "uint64",
    "float": "float32",
    "double": "float64",
}

FNPOINTER_PARAM = re.compile(r"^\s*[A-Za-z_]\w*\s*\*?\s*$")  # SlangDiagnosticCallback


class Function(object):
    def __init__(self, name, ret, params, source):
        self.name = name
        self.ret = ret
        self.params = params  # list of (type_text, param_name)
        self.source = source

    def ret_kind(self):
        return classify_type(self.ret, is_return=True)[0]

    def ret_base(self):
        return classify_type(self.ret, is_return=True)[1]

    def param_kinds(self):
        return [classify_type(t, is_return=False)[0] for (t, _n) in self.params]


def classify_type(type_text, is_return):
    """Return (kind, base_name).

    kind: void | bool | int32 | uint32 | int64 | uint64 | float32 | float64 |
          cstr | ptr
    """
    t = type_text.strip()
    t = re.sub(r"\s+", " ", t)
    # count pointer/reference markers
    stars = t.count("*") + t.count("&")
    base = t.replace("&", " ").replace("*", " ")
    base = re.sub(r"\s+", " ", base).strip()
    base = re.sub(r"^(const|volatile)\s+", "", base)
    base = re.sub(r"\s+(const|volatile)$", "", base)
    base = base.strip()
    if base == "" and stars > 0:
        base = "void"
    if stars > 0:
        if base == "char" and post_const_c_str(type_text) and stars == 1:
            return ("cstr", "char")
        if base == "char" and stars >= 1 and is_return and stars == 1:
            return ("cstr", "char")
        return ("ptr", base)
    if base in SCALAR_TYPES:
        return (SCALAR_TYPES[base], base)
    # function-pointer typedef param (SlangDiagnosticCallback)
    if FNPOINTER_PARAM.match(base):
        return ("ptr", base)
    # any other bare identifier: a Slang enum (C enums are 32-bit ints)
    return ("int32", base)


def post_const_c_str(type_text):
    # "char const*" / "const char*" -> returned as a C string
    t = re.sub(r"\s+", " ", type_text.strip())
    return bool(re.fullmatch(r"(const\s+)?char\s+(const\s+)?\*", t))


def parse_functions(text, source):
    """Parse `SLANG_API <ret> <name>(<params>);` declarations."""
    funcs = []
    for m in re.finditer(r"SLANG_EXTERN_C\s+SLANG_API\s+|SLANG_API\s+", text):
        i = m.end()
        j = text.find(";", i)
        if j < 0:
            continue
        decl = text[i:j].strip()
        k = decl.find("(")
        if k < 0:
            continue
        head = decl[:k].strip()
        mm = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*$", head)
        if not mm:
            continue
        fname = mm.group(1)
        if fname.startswith("__"):
            continue  # macro definition artifacts, not declarations
        ret = re.sub(r"\s+", " ", head[: mm.start()].strip())
        close = decl.rfind(")")
        if close < k:
            continue
        ptext = decl[k + 1: close]
        params = []
        for p in split_top_level(ptext):
            p = p.strip()
            if not p or p == "void":
                continue
            p = re.sub(r"\s*=\s*[^=]+$", "", p)  # default argument
            # split trailing parameter name
            tm = re.match(r"^(.*?)([A-Za-z_][A-Za-z0-9_]*)\s*$", p)
            if tm and tm.group(1).strip():
                ptype = tm.group(1).strip()
            else:
                ptype = p
            params.append((ptype, ""))
            # keep raw type text for signature docs
        funcs.append(Function(fname, ret, params, source))
    return funcs


def parse_enums(text):
    """Parse enum bodies (named + anonymous). Returns list of
    (enum_name, source_position, [(entry, expr_or_None)])."""
    enums = []
    pattern = re.compile(r"(?<![A-Za-z0-9_])(?:typedef\s+)?enum\s+([A-Za-z_]\w*)?\s*(?::\s*[\w:]+)?\s*\{")
    for m in pattern.finditer(text):
        name = m.group(1) or ""
        i = m.end()
        depth = 1
        j = i
        while j < len(text) and depth > 0:
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
            j += 1
        body = text[i: j - 1]
        entries = []
        for part in split_top_level(body, angle=False):
            part = part.strip()
            if not part:
                continue
            em = re.match(r"^([A-Za-z_]\w*)\s*(?:=\s*(.*))?$", part, re.S)
            if not em:
                continue
            entries.append((em.group(1), (em.group(2) or "").strip() or None))
        if entries:
            enums.append((name, m.start(), entries))
    return enums


def parse_macros(text):
    """Parse object-like `#define SLANG_* <value>` macros with a raw value."""
    text = text.replace("\\\n", " ")
    out = {}
    order = []
    for m in re.finditer(r"#\s*define\s+([A-Za-z_]\w*)(\([^)]*\))?\s+([^\n]*)", text):
        name, args, val = m.group(1), m.group(2), m.group(3).strip()
        if not name.startswith("SLANG"):
            continue
        if args:
            continue  # function-like macro
        if name not in out:
            order.append(name)
            out[name] = []
        out[name].append(val)
    return [(n, out[n]) for n in order]


# ----------------------------------------------------------------------------
# PE export parser (pure Python, no dumpbin)
# ----------------------------------------------------------------------------


def parse_pe_exports(dll_path):
    d = open(dll_path, "rb").read()
    e_lfanew = struct.unpack_from("<I", d, 0x3C)[0]
    if d[e_lfanew:e_lfanew + 4] != b"PE\x00\x00":
        raise ValueError("not a PE file: %s" % dll_path)
    nsec = struct.unpack_from("<H", d, e_lfanew + 6)[0]
    soh = struct.unpack_from("<H", d, e_lfanew + 20)[0]
    opt = e_lfanew + 24
    magic = struct.unpack_from("<H", d, opt)[0]
    if magic != 0x20B:
        raise ValueError("expected PE32+ (x64), magic=0x%x" % magic)
    dd = opt + 112
    exp_rva, exp_size = struct.unpack_from("<II", d, dd)
    if exp_rva == 0:
        return {}, None
    secs = []
    for i in range(nsec):
        o = opt + soh + i * 40
        name = d[o:o + 8].rstrip(b"\x00").decode()
        vsize, vaddr, rsize, raddr = struct.unpack_from("<IIII", d, o + 8)
        secs.append((name, vaddr, vsize, raddr, rsize))

    def rva2off(rva):
        for _name, vaddr, vsize, raddr, rsize in secs:
            if vaddr <= rva < vaddr + max(vsize, rsize):
                return raddr + (rva - vaddr)
        return None

    off = rva2off(exp_rva)
    nfun, nname = struct.unpack_from("<II", d, off + 20)
    funcs_rva = struct.unpack_from("<I", d, off + 28)[0]
    name_rva = struct.unpack_from("<I", d, off + 32)[0]
    foff = rva2off(funcs_rva)
    noff = rva2off(name_rva)
    addrs = [struct.unpack_from("<I", d, foff + i * 4)[0] for i in range(nfun)]
    names = []
    for i in range(nname):
        nrva = struct.unpack_from("<I", d, noff + i * 4)[0]
        o = rva2off(nrva)
        end = d.index(b"\x00", o)
        names.append(d[o:end].decode())
    edir_end = exp_rva + exp_size
    exports = []
    for i in range(nfun):
        a = addrs[i]
        forward = None
        if exp_rva <= a < edir_end:
            o = rva2off(a)
            end = d.index(b"\x00", o)
            forward = d[o:end].decode()
        exports.append({"name": names[i], "forward": forward})
    return exports, os.path.basename(dll_path)


# ----------------------------------------------------------------------------
# Oracle assembly
# ----------------------------------------------------------------------------

FORWARD_TARGET_DLLS = set()


def is_c_api_export(name):
    if name.startswith("slang_"):
        return True
    if re.match(r"^sp[A-Z_]", name):
        return True
    return False


# Family assignment: explicit ordered rules over C names.
# The generic rule keeps the legacy top-level API in three parts.
def family_rules(name):
    if name.startswith("slang_"):
        return "slangapi"
    for pre, fam in [
        ("spReflectionTypeLayout_", "refl_typelayout"),
        ("spReflectionTypeParameter_", "refl_type"),
        ("spReflectionType_", "refl_type"),
        ("spReflectionDecl_", "refl_decl"),
        ("spReflectionVariableLayout_", "refl_decl"),
        ("spReflectionVariable_", "refl_decl"),
        ("spReflectionFunction_", "refl_func"),
        ("spReflectionEntryPoint_", "refl_func"),
        ("spReflectionUserAttribute_", "refl_generic"),
        ("spReflectionGeneric_", "refl_generic"),
        ("spReflectionParameter_", "refl_misc"),
        ("spReflection_", "refl_misc"),
        ("spCompileRequest_", "sp_request"),
    ]:
        if name.startswith(pre):
            return fam
    return "legacy_top"


MAX_FAMILY = 30  # fns per generated family chunk (keeps files < 600 lines)


def build_families(c_names):
    grouped = {}
    order = []
    for n in c_names:
        fam = family_rules(n)
        if fam not in grouped:
            grouped[fam] = []
            order.append(fam)
        grouped[fam].append(n)
    families = []  # (fam_key, [names])
    for fam in order:
        names = sorted(grouped[fam])
        if len(names) <= MAX_FAMILY:
            families.append((fam, names))
        else:
            parts = (len(names) + MAX_FAMILY - 1) // MAX_FAMILY
            size = (len(names) + parts - 1) // parts
            for k in range(parts):
                chunk = names[k * size:(k + 1) * size]
                if chunk:
                    families.append(("%s_p%d" % (fam, k + 1), chunk))
    return families


# ----------------------------------------------------------------------------
# XIOM emission helpers
# ----------------------------------------------------------------------------

BANNER = (
    "// AUTO-GENERATED by tools/gen_slang.py -- DO NOT EDIT BY HAND.\n"
    "// Source: {header} + slang.dll export table (generator header says when).\n"
    "// XIOM -- xiom.slang bindings. MIT OR Apache-2.0.\n"
)


def emit_line_count(path):
    with open(path, "r", encoding="utf-8") as fh:
        return sum(1 for _ in fh)


def write_file(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


class Codegen(object):
    def __init__(self, funcs, families, consts, out_dir, header_desc, dll_desc,
                 exports, header_only):
        self.funcs = funcs          # name -> Function
        self.families = families    # [(fam, [cnames])]
        self.consts = consts        # [(name, value)] in emission order
        self.out = out_dir
        self.header_desc = header_desc
        self.dll_desc = dll_desc
        self.exports = exports
        self.header_only = header_only
        self.manifest = {}

    # -- paths ------------------------------------------------------------

    def src(self, rel):
        return os.path.join(self.out, "src", rel)

    # -- names ------------------------------------------------------------

    def xiom_fn(self, cname):
        return xiom_snake(cname)

    def fam_mod(self, fam):
        return "xiom.slang.res_%s" % fam

    def wrap_mod(self, fam):
        return "xiom.slang.wrap_%s" % fam

    def fam_type(self, fam):
        return "".join(p.capitalize() for p in fam.split("_")) + "Syms"

    # -- emit: symbol table ----------------------------------------------

    def emit_syms(self):
        names = sorted(self.funcs.keys())
        out = [BANNER.format(header=self.header_desc)]
        out.append("module xiom.slang.syms\n")
        out.append("// Oracle of this package (measured by the generator):")
        out.append("//   header-declared C API functions: %d" % len(names))
        out.append("//   C functions exported by slang.dll: %d" % len(names))
        out.append("//   header-declared but NOT exported: %d" % len(self.header_only))
        out.append("")
        out.append("/// The forwarder target slang.dll relays every export to")
        out.append("/// (pure-forwarder proxy DLL in the Vulkan SDK).")
        out.append('pub const SLANG_FORWARD_TARGET: Str = "slang-compiler.dll";')
        out.append("")
        out.append("/// Every C function name exported by slang.dll (the oracle).")
        out.append("/// Newline-separated; split on '\\n' for the full list.")
        out.append('pub const SLANG_SYMBOLS: Str = "%s";' % "\\n".join(names))
        out.append("")
        out.append("/// Oracle size: number of exported C API functions.")
        out.append("pub const SLANG_SYMBOL_COUNT: Int = %d;" % len(names))
        out.append("")
        out.append("/// Header-declared functions the DLL does NOT export (proof in")
        out.append("/// docs/COVERAGE.md; not bound as resolved symbols).")
        out.append('pub const SLANG_HEADER_ONLY: Str = "%s";' %
                   "\\n".join(sorted(self.header_only)))
        out.append("")
        out.append("/// Count of header-declared-but-not-exported functions.")
        out.append("pub const SLANG_HEADER_ONLY_COUNT: Int = %d;" % len(self.header_only))
        out.append("")
        write_file(self.src("gen_syms.xi"), "\n".join(out) + "\n")

    # -- emit: type aliases ----------------------------------------------

    def emit_types(self):
        out = [BANNER.format(header=self.header_desc)]
        out.append("module xiom.slang.types\n")
        out.append("// C typedef aliases from slang.h (x64 widths). Pointers cross the")
        out.append("// FFI boundary as Int addresses; enums are 32-bit C enums.")
        out.append("")
        for alias, base in [
            ("SlangResult", "Int32"),
            ("SlangBool", "UInt8"),
            ("SlangInt32", "Int32"),
            ("SlangUInt32", "UInt32"),
            ("SlangInt", "Int"),
            ("SlangUInt", "UInt64"),
            ("SlangSizeT", "UInt64"),
        ]:
            out.append("pub type %s = %s;" % (alias, base))
        out.append("")
        write_file(self.src("gen_types.xi"), "\n".join(out) + "\n")

    # -- emit: per-family resolver ---------------------------------------

    def emit_res(self, fam, names):
        ftype = self.fam_type(fam)
        out = [BANNER.format(header=self.header_desc)]
        out.append("module %s" % self.fam_mod(fam))
        out.append("")
        out.append("use xiom.ffi.dl;")
        out.append("")
        out.append("/// Family size: number of exported names resolved here.")
        out.append("pub const %s_COUNT: Int = %d;" % (fam.upper(), len(names)))
        out.append("")
        out.append("/// Resolved symbol addresses for the `%s` family." % fam)
        out.append("pub type %s = {" % ftype)
        for n in names:
            out.append("  p_%s: Int;" % n)
        out.append("}")
        out.append("")
        out.append("/// Resolve every `%s` symbol; Err(<C name>) on the first missing" % fam)
        out.append("/// symbol (fail-fast: a present DLL must carry the full pinned surface).")
        out.append("/// Complexity: O(symbols).")
        out.append("pub fn resolve_%s(h: Int) -> Result[%s, Str]" % (fam, ftype))
        out.append("  requires: h != 0")
        out.append("{")
        for i, n in enumerate(names):
            out.append('  let a%d = dl.dl_sym(h, "%s");' % (i + 1, n))
            out.append('  if !a%d.is_ok { return Err("%s"); }' % (i + 1, n))
        out.append("  return Ok(%s{" % ftype)
        for i, n in enumerate(names):
            out.append("    p_%s: a%d.value," % (n, i + 1))
        out.append("  });")
        out.append("}")
        out.append("")
        out.append("/// Count the `%s` names that resolve in this DLL (suite metric)." % fam)
        out.append("/// Complexity: O(symbols).")
        out.append("pub fn count_%s(h: Int) -> Int" % fam)
        out.append("  requires: h != 0")
        out.append("{")
        out.append("  var my_n = 0;")
        for i, n in enumerate(names):
            out.append('  let a%d = dl.dl_sym(h, "%s");' % (i + 1, n))
            out.append("  if a%d.is_ok { my_n = my_n + 1; }" % (i + 1))
        out.append("  return my_n;")
        out.append("}")
        out.append("")
        write_file(self.src("res_%s.xi" % fam), "\n".join(out) + "\n")

    # -- emit: per-family typed wrappers ---------------------------------

    FN_TYPE = {
        "void": None,
        "bool": "UInt8",
        "int32": "Int32",
        "uint32": "UInt32",
        "int64": "Int",
        "uint64": "UInt64",
        "float32": "Float32",
        "float64": "Float64",
        "cstr": "*UInt8",
        "ptr": "*UInt8",
    }

    def wrapper(self, f):
        fname = self.xiom_fn(f.name)
        rk = f.ret_kind()
        rbase = f.ret_base()
        params = ["s: &%s" % self.fam_type(self.family_of(f.name))]
        params += ["p%d: Int" % (i + 1) for i in range(len(f.params))]
        args = ["p%d" % (i + 1) for i in range(len(f.params))]
        argtypes = ", ".join("Int" for _ in f.params)
        sig = "%s(%s)" % (f.name, ", ".join(
            (t + " " + n).strip() for (t, n) in f.params) if f.params else "")
        lines = []
        lines.append("/// `%s`" % sig)
        if f.params:
            lines.append("/// Params are addresses/values (`Int`); out-params are")
            lines.append("/// XIOM-owned slots passed as addresses.")
        lines.append("/// Complexity: O(1).")
        if rk == "void":
            lines.append("pub fn %s(%s)" % (fname, ", ".join(params)))
        elif rk == "cstr":
            lines.append("pub fn %s(%s) -> Str" % (fname, ", ".join(params)))
        elif rk == "ptr":
            lines.append("pub fn %s(%s) -> Int" % (fname, ", ".join(params)))
        elif rk == "bool":
            lines.append("pub fn %s(%s) -> Bool" % (fname, ", ".join(params)))
        else:
            lines.append("pub fn %s(%s) -> Int" % (fname, ", ".join(params)))
        lines.append("  requires: s.p_%s != 0" % f.name)
        lines.append("{")
        lines.append("  unsafe {")
        cast = "fn(%s)" % argtypes
        if rk != "void":
            if rk == "bool":
                # C `bool` is 1 byte in AL; the pinned DLL does NOT clear the
                # upper bits of RAX, so read the full register and mask the
                # low byte (robust under both truncating and non-truncating
                # declared-width toolchains -- measured on slang 2026.8).
                cast += " -> Int"
            else:
                cast += " -> %s" % self.FN_TYPE[rk]
        lines.append("    let f_call = s.p_%s as %s;" % (f.name, cast))
        call = "f_call(%s)" % ", ".join(args)
        if rk == "void":
            lines.append("    %s;" % call)
        elif rk == "cstr":
            lines.append("    let f_ret = %s;" % call)
            lines.append("    if (f_ret as Int) == 0 { return \"\"; }")
            lines.append("    return Str::from_c_str(f_ret);")
        elif rk == "ptr":
            lines.append("    return %s as Int;" % call)
        elif rk == "bool":
            lines.append("    return (%s & 255) != 0;" % call)
        else:
            lines.append("    return %s as Int;" % call)
        lines.append("  }")
        lines.append("}")
        return "\n".join(lines)

    def family_of(self, cname):
        for fam, names in self.families:
            if cname in names:
                return fam
        raise KeyError(cname)

    def emit_wrap(self, fam, names):
        out = [BANNER.format(header=self.header_desc)]
        out.append("module %s" % self.wrap_mod(fam))
        out.append("")
        out.append("use %s;" % self.fam_mod(fam))
        out.append("")
        out.append("// Typed wrappers for the `%s` family (%d functions). Every call" % (fam, len(names)))
        out.append("// goes through the resolved address; pointers cross as Int addresses.")
        out.append("")
        for n in names:
            out.append(self.wrapper(self.funcs[n]))
            out.append("")
        write_file(self.src("wrap_%s.xi" % fam), "\n".join(out) + "\n")

    # -- emit: constants --------------------------------------------------

    def emit_consts(self):
        # split into files <= 450 lines
        chunks = []
        cur = []
        for name, value in self.consts:
            cur.append((name, value))
            if len(cur) >= 400:
                chunks.append(cur)
                cur = []
        if cur:
            chunks.append(cur)
        for i, chunk in enumerate(chunks):
            out = [BANNER.format(header=self.header_desc)]
            out.append("module xiom.slang.const_%d" % (i + 1))
            out.append("")
            out.append("// Enum entries and integer macros from the pinned headers, part %d/%d"
                       % (i + 1, len(chunks)))
            out.append("// (%d constants). Values are evaluated literals (never aliases)."
                       % len(chunk))
            out.append("")
            for name, value in chunk:
                out.append("pub const %s: Int = %d;" % (name, value))
            out.append("")
            write_file(self.src("gen_const_%d.xi" % (i + 1)), "\n".join(out) + "\n")
        return len(chunks)

    # -- emit: parent loader ---------------------------------------------

    def emit_parent(self):
        names = sorted(self.funcs.keys())
        out = [BANNER.format(header=self.header_desc)]
        out.append("module xiom.slang")
        out.append("")
        out.append("// Loader entry for the Slang C API. `slang.dll` in the Vulkan SDK is")
        out.append("// a pure-forwarder proxy: all %d C exports relay to" % len(names))
        out.append("// `slang-compiler.dll` (recorded in docs/COVERAGE.md). `slang_load`")
        out.append("// resolves every exported oracle symbol fail-fast; when the DLL is")
        out.append("// absent it returns Err(kind = SLANG_LOAD_ABSENT) and the suite SKIPs.")
        out.append("")
        out.append("use xiom.ffi.dl;")
        for fam, _names in self.families:
            out.append("use %s;" % self.fam_mod(fam))
        out.append("")
        out.append("/// The runtime library name resolved by the loader.")
        out.append('pub const SLANG_SONAME: Str = "slang.dll";')
        out.append("")
        out.append("/// Load-error kinds: absent DLL (SKIP) vs present-DLL ABI mismatch.")
        out.append("pub const SLANG_LOAD_ABSENT: Int = 0;")
        out.append("pub const SLANG_LOAD_ABI: Int = 1;")
        out.append("")
        out.append("pub type SlangLoadError = {")
        out.append("  kind: Int;")
        out.append("  message: Str;")
        out.append("}")
        out.append("")
        out.append("/// Every resolved symbol family of the Slang C API.")
        out.append("pub type SlangLibrary = {")
        out.append("  handle: Int;")
        for fam, _names in self.families:
            out.append("  %s: %s;" % (fam, self.fam_type(fam)))
        out.append("}")
        out.append("")
        out.append("/// Load slang.dll and resolve every exported oracle symbol.")
        out.append("/// Complexity: O(symbols).")
        out.append("pub fn slang_load() -> Result[SlangLibrary, SlangLoadError] {")
        out.append("  let h_open = dl.dl_open(SLANG_SONAME);")
        out.append("  if !h_open.is_ok {")
        out.append("    return Err(SlangLoadError{ kind: SLANG_LOAD_ABSENT, message: h_open.error });")
        out.append("  }")
        out.append("  let my_handle: Int = h_open.value;")
        for i, (fam, _names) in enumerate(self.families):
            out.append("  let r_%s = resolve_%s(my_handle);" % (fam, fam))
            out.append("  if !r_%s.is_ok {" % fam)
            out.append("    var ig = dl.dl_close(my_handle);")
            out.append("    return Err(SlangLoadError{ kind: SLANG_LOAD_ABI, message: \"%s: \" + r_%s.error });" % (fam, fam))
            out.append("  }")
        out.append("  return Ok(SlangLibrary{")
        out.append("    handle: my_handle,")
        for fam, _names in self.families:
            out.append("    %s: r_%s.value," % (fam, fam))
        out.append("  });")
        out.append("}")
        out.append("")
        out.append("/// Release a loaded library handle.")
        out.append("/// Complexity: O(1).")
        out.append("pub fn slang_close(lib: &SlangLibrary) -> Result[Unit, Str]")
        out.append("  requires: lib.handle != 0")
        out.append("{")
        out.append("  return dl.dl_close(lib.handle);")
        out.append("}")
        out.append("")
        out.append("/// Total resolved-name count across every family (the suite's")
        out.append("/// resolved=N/N metric; N is SLANG_SYMBOL_COUNT in xiom.slang.syms).")
        out.append("/// Complexity: O(symbols).")
        out.append("pub fn slang_resolved_count(handle: Int) -> Int")
        out.append("  requires: handle != 0")
        out.append("{")
        out.append("  var my_n = 0;")
        for fam, _names in self.families:
            out.append("  my_n = my_n + count_%s(handle);" % fam)
        out.append("  return my_n;")
        out.append("}")
        out.append("")
        write_file(os.path.join(self.out, "slang.xi"), "\n".join(out) + "\n")

    # -- manifest ---------------------------------------------------------

    def emit_manifest(self, header_only, export_only, macro_report, const_skipped_report,
                      enum_report):
        manifest = {
            "generator": "tools/gen_slang.py",
            "header": self.header_desc,
            "dll": self.dll_desc,
            "header_files": HEADER_FILES,
            "oracle": {
                "exported_c_functions": len(self.funcs),
                "header_declared_c_functions": len(self.funcs) + len(header_only),
                "header_only": sorted(header_only),
                "export_only": sorted(export_only),
                "forward_targets": sorted(FORWARD_TARGET_DLLS),
            },
            "families": [{"name": fam, "count": len(names), "functions": names}
                         for fam, names in self.families],
            "constants": {
                "bound": len(self.consts),
                "enum_entries_total": enum_report["total"],
                "enum_entries_duplicate": enum_report["duplicate"],
                "cxx_helper_entries_excluded": enum_report["cxx_helper"],
                "skipped": const_skipped_report,
                "names": [c[0] for c in self.consts],
            },
            "macros": macro_report,
        }
        path = os.path.join(self.out, "tools", "oracle_manifest.json")
        write_file(path, json.dumps(manifest, indent=1, sort_keys=False) + "\n")
        return manifest


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------


def main(argv):
    header_dir = DEFAULT_HEADER
    dll_path = DEFAULT_DLL
    out_dir = DEFAULT_OUT
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--header":
            header_dir = argv[i + 1]; i += 2
        elif a == "--dll":
            dll_path = argv[i + 1]; i += 2
        elif a == "--out":
            out_dir = argv[i + 1]; i += 2
        else:
            print("unknown arg: %s" % a)
            return 2

    texts = []
    header_desc = None
    for fn in HEADER_FILES:
        p = os.path.join(header_dir, fn)
        with open(p, "r", encoding="utf-8", errors="replace") as fh:
            texts.append((fn, expand_xmacro_enums(strip_comments(fh.read()),
                                                  header_dir)))
    header_desc = "%s{%s}" % (header_dir, ", ".join(fn for fn, _ in texts))

    # --- functions
    decls = {}
    for fn, text in texts:
        for f in parse_functions(text, fn):
            if f.name in decls:
                continue
            decls[f.name] = f

    # --- exports
    exports, dll_desc = parse_pe_exports(dll_path)
    for e in exports:
        if e["forward"]:
            FORWARD_TARGET_DLLS.add(e["forward"].rsplit(".", 1)[0])
    c_exports = [e for e in exports if is_c_api_export(e["name"])]
    export_names = set(e["name"] for e in c_exports)
    export_only = sorted(n for n in export_names if n not in decls)
    header_only = sorted(n for n in decls if n not in export_names)
    funcs = {n: decls[n] for n in sorted(export_names)}
    if export_only:
        print("FATAL: DLL exports C names not declared in the headers: %r" % export_only)
        return 1
    missing_decl = [n for n in funcs if funcs[n].source not in HEADER_FILES]
    if missing_decl:
        print("FATAL: declarations missing for: %r" % missing_decl[:5])
        return 1

    # --- enums + macros -> constants
    consts = []
    const_seen = set()
    const_skipped = []
    const_duplicate = []
    const_cxx_helper = []
    enum_entries_total = 0
    symbol_values = {}
    for fn, text in texts:
        for ename, _pos, entries in parse_enums(text):
            for entry, expr in entries:
                enum_entries_total += 1
                if entry in const_seen:
                    const_duplicate.append(entry)
                    continue
                if not entry.startswith("SLANG_"):
                    # C++ helper enums (ScalarType::None, ParameterCategory,
                    # Modifier::ID, CompileCoreModuleFlag) carry non-SLANG_*
                    # names; they are C++ conveniences, not C API constants.
                    const_cxx_helper.append(entry)
                    continue
                if expr is None:
                    # implicit: previous entry + 1 within the enum (first = 0)
                    value = None
                    prev = -1
                    for e2, x2 in entries:
                        if e2 == entry:
                            break
                        if x2 is None:
                            prev = prev + 1 if prev is not None else None
                        else:
                            try:
                                prev = eval_c_expr(x2, symbol_values)
                            except CExprError:
                                prev = None
                    value = prev + 1 if prev is not None else None
                    if value is None:
                        const_skipped.append(entry)
                        continue
                else:
                    try:
                        value = eval_c_expr(expr, symbol_values)
                    except CExprError:
                        const_skipped.append("%s = %s" % (entry, expr))
                        continue
                if not re.fullmatch(r"[A-Za-z_]\w*", entry):
                    continue
                symbol_values[entry] = value
                const_seen.add(entry)
                consts.append((entry, value))

    macro_report = {"bound": [], "skipped_conditional": [], "skipped_expr": [], "skipped_other": []}
    for name, values in parse_macros("\n".join(t for _f, t in texts)):
        if len(values) > 1 and len(set(values)) > 1:
            macro_report["skipped_conditional"].append(name)
            continue
        raw = values[0]
        if not raw:
            macro_report["skipped_other"].append(name)
            continue
        if not re.fullmatch(r"[-+~()0-9xXa-fA-FuUlL\s<>&|:]*", raw):
            macro_report["skipped_expr"].append("%s = %s" % (name, raw[:60]))
            continue
        try:
            value = eval_c_expr(raw, symbol_values)
        except CExprError:
            macro_report["skipped_expr"].append("%s = %s" % (name, raw[:60]))
            continue
        if name in const_seen:
            continue
        symbol_values[name] = value
        const_seen.add(name)
        consts.append((name, value))
        macro_report["bound"].append(name)

    families = build_families(sorted(funcs.keys()))
    cg = Codegen(funcs, families, consts, out_dir, header_desc, dll_desc, exports, header_only)
    cg.emit_syms()
    cg.emit_types()
    for fam, names in families:
        cg.emit_res(fam, names)
        cg.emit_wrap(fam, names)
    nconst_files = cg.emit_consts()
    cg.emit_parent()
    enum_report = {"total": enum_entries_total, "duplicate": len(const_duplicate),
                   "cxx_helper": len(const_cxx_helper)}
    manifest = cg.emit_manifest(header_only, export_only, macro_report, const_skipped,
                                enum_report)

    print("gen_slang: functions=%d families=%d constants=%d const_files=%d" %
          (len(funcs), len(families), len(consts), nconst_files))
    print("gen_slang: header_only=%d export_only=%d forwarders->%s" %
          (len(header_only), len(export_only), sorted(FORWARD_TARGET_DLLS)))
    print("gen_slang: header-only names: %s" % ", ".join(header_only))
    # line-count guard for every emitted module
    worst = []
    for fam, names in families:
        for rel in ("src/res_%s.xi" % fam, "src/wrap_%s.xi" % fam):
            worst.append((emit_line_count(os.path.join(out_dir, rel)), rel))
    for i in range(1, nconst_files + 1):
        worst.append((emit_line_count(os.path.join(out_dir, "src/gen_const_%d.xi" % i)),
                      "src/gen_const_%d.xi" % i))
    worst.sort(reverse=True)
    print("gen_slang: largest generated files: %s" %
          ", ".join("%s=%d" % (r, n) for n, r in worst[:4]))
    if worst and worst[0][0] >= 600:
        print("WARNING: a generated file is >= 600 lines; lower MAX_FAMILY")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
