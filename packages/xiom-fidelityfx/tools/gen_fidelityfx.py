#!/usr/bin/env python3
# ============================================================================
# XIOM xiom.fidelityfx -- surface generator for the AMD FidelityFX SDK 2.3.0
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Parses the vendored (verbatim, MIT-listed) FidelityFX-SDK v2.3.0 headers and
# emits:
#   src/ffx_gen_types.xi        enum values + integer #define constants + blob hashes
#   src/ffx_gen_structs.xi      struct sizes/field offsets + loop tables
#   src/ffx_gen_surface.xi      declared-function records + coverage tables
#   src/ffx_gen_abi.cpp         C++20 oracle: static_asserts + runtime sizeof/
#                               offsetof probe + function signature pins
#   docs/COVERAGE.md            per-component coverage table
#   docs/gen_manifest.json      full machine-readable surface census
#   vendor/fidelityfx/PIN.md    per-file SHA256 of the vendored tree
#
# The generator FAILS LOUDLY on any construct it does not understand -- the
# emitted surface is only valid when the parse is complete.
#
# Usage:
#   python tools/gen_fidelityfx.py            # regenerate
#   python tools/gen_fidelityfx.py --check    # verify committed == regenerated
#   python tools/gen_fidelityfx.py --pin      # regenerate PIN.md only
# ============================================================================

import hashlib
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PKG  = os.path.dirname(HERE)
VENDOR_DIR = os.path.join(PKG, "vendor", "fidelityfx")

PIN = {
    "upstream": "https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK",
    "tag": "v2.3.0",
    "commit": "60f4ea81909200d8542eca14dccb2628b763a9a3",
    "date": "2026-06-24",
    "sdk_name": 'AMD FSR SDK 2.3.0 "Redstone"',
}

# ---------------------------------------------------------------------------
# Parse sets.
#   SURFACE: types + functions (the declared C surface)
#   SUPPORT: types only (transitively needed by the surface headers)
# Conditions are evaluated with FFX_CPU=1 (the C path of the GPU headers) and
# FFX_GPU/FFX_HLSL/FFX_GLSL=0.
# ---------------------------------------------------------------------------

SUPPORT_SET = [
    ("core", "api/internal/ffx_internal_types.h"),
    ("core", "api/internal/gpu/ffx_common_types.h"),
]

SURFACE_SET = [
    ("core",               "api/include/ffx_api.h"),
    ("core",               "api/include/ffx_api_types.h"),
    ("core",               "api/include/ffx_api_loader.h"),
    ("core",               "api/include/dx12/ffx_api_dx12.h"),
    ("core",               "api/internal/ffx_message.h"),
    ("upscale",            "upscalers/include/ffx_upscale.h"),
    ("fsr2",               "upscalers/fsr3/include/ffx_fsr2.h"),
    ("fsr3upscaler",       "upscalers/fsr3/include/ffx_fsr3upscaler.h"),
    ("spd",                "upscalers/fsr3/include/ffx_spd.h"),
    ("fsr1",               "upscalers/fsr3/include/gpu/fsr1/ffx_fsr1.h"),
    ("spd",                "upscalers/fsr3/include/gpu/spd/ffx_spd.h"),
    ("framegeneration",    "framegeneration/include/ffx_framegeneration.h"),
    ("framegeneration",    "framegeneration/include/ffx_framegeneration_api_types.h"),
    ("framegeneration",    "framegeneration/include/dx12/ffx_api_framegeneration_dx12.h"),
    ("frameinterpolation", "framegeneration/fsr3/include/ffx_frameinterpolation.h"),
    ("opticalflow",        "framegeneration/fsr3/include/ffx_opticalflow.h"),
    ("core",               "api/internal/ffx_interface.h"),
    ("core",               "api/internal/ffx_error.h"),
]

# Headers expected to compile into the ABI oracle (the dx12 headers need the
# DirectX-Headers SDK and are parse-only).
ABI_INCLUDE_ORDER = [
    "api/include/ffx_api.h",
    "api/include/ffx_api_types.h",
    "api/include/ffx_api_loader.h",
    "upscalers/include/ffx_upscale.h",
    "upscalers/fsr3/include/ffx_fsr2.h",
    "upscalers/fsr3/include/ffx_fsr3upscaler.h",
    "upscalers/fsr3/include/ffx_spd.h",
    "framegeneration/include/ffx_framegeneration.h",
    "framegeneration/fsr3/include/ffx_frameinterpolation.h",
    "framegeneration/fsr3/include/ffx_opticalflow.h",
    "api/internal/gpu/ffx_core.h",
    "upscalers/fsr3/include/gpu/fsr1/ffx_fsr1.h",
    "upscalers/fsr3/include/gpu/spd/ffx_spd.h",
]

BLOBS = [
    ("fsr3_swapchain_debug_pacing_ps",           "ps", "framegeneration/fsr3/dx12/FrameInterpolationSwapchainDebugPacingPS.h"),
    ("fsr3_swapchain_debug_pacing_vs",           "vs", "framegeneration/fsr3/dx12/FrameInterpolationSwapchainDebugPacingVS.h"),
    ("fsr3_swapchain_ui_composition_ps",         "ps", "framegeneration/fsr3/dx12/FrameInterpolationSwapchainUiCompositionPS.h"),
    ("fsr3_swapchain_ui_composition_vs",         "vs", "framegeneration/fsr3/dx12/FrameInterpolationSwapchainUiCompositionVS.h"),
    ("fsr3_swapchain_ui_composition_premul_ps",  "ps", "framegeneration/fsr3/dx12/FrameInterpolationSwapchainUiCompositionPremulPS.h"),
    ("fsr3_swapchain_ui_composition_premul_vs",  "vs", "framegeneration/fsr3/dx12/FrameInterpolationSwapchainUiCompositionPremulVS.h"),
]

COND_CONTEXT = {"__cplusplus": 1, "FFX_CPU": 1}
ANNOTATION_MACROS = ("FFX_PARAMETER_IN", "FFX_PARAMETER_OUT", "FFX_PARAMETER_INOUT",
                     "FFX_PARAMETER_UNIFORM", "FFX_INLINE")


def die(msg):
    print("gen_fidelityfx: FATAL: " + msg, file=sys.stderr)
    sys.exit(2)


def read_vendor(rel):
    path = os.path.join(VENDOR_DIR, rel)
    if not os.path.exists(path):
        die("missing vendored header: " + rel)
    with open(path, "r", encoding="utf-8", errors="strict") as f:
        return f.read()


def strip_comments(text):
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                if text[i] == "\n":
                    out.append("\n")
                i += 1
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


# ---------------------------------------------------------------------------
# Integer expression evaluator (C preprocessor subset)
# ---------------------------------------------------------------------------

class ExprError(Exception):
    pass


TOK_RE = re.compile(
    r"""\s*(?:
        (?P<num>0[xX][0-9a-fA-F]+[uUlL]*|\d+[uUlL]*)
      | (?P<id>[A-Za-z_][A-Za-z0-9_]*)
      | (?P<op><<|>>|<=|>=|==|!=|&&|\|\||[()+\-*/%&|^~!<>?:,])
    )""", re.X)


def lex_expr(s):
    toks = []
    pos = 0
    while pos < len(s):
        m = TOK_RE.match(s, pos)
        if not m:
            if s[pos:].strip() == "":
                break
            raise ExprError("cannot lex %r" % s[pos:pos + 24])
        pos = m.end()
        if m.group("num"):
            raw = re.sub(r"[uUlL]+$", "", m.group("num"))
            toks.append(("num", int(raw, 0)))
        elif m.group("id"):
            toks.append(("id", m.group("id")))
        else:
            toks.append(("op", m.group("op")))
    return toks


def wrap_i32(v):
    """C enum values are int: wrap the evaluated integer to the signed 32-bit
    domain (FFX_EOF etc. are 0x80000000|x in the headers)."""
    return ((v + 0x80000000) & 0xFFFFFFFF) - 0x80000000


class MacroTable(object):
    def __init__(self):
        self.obj = {}
        self.fun = {}
        self.eval_cache = {}
        self.permissive = False
        self.defined_extra = set()
        self.obj_origin = {}

    def define_line(self, text, origin=None):
        rest = text[len("#define"):].strip()
        m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)(\((.*?)\))?\s*(.*)$", rest, re.S)
        if not m:
            return
        name = m.group(1)
        params = m.group(3)
        body = m.group(4).strip()
        if params is not None:
            plist = [p.strip() for p in params.split(",") if p.strip()]
            self.fun[name] = (plist, body)
        else:
            self.obj[name] = body
        if origin is not None:
            self.obj_origin[name] = origin

    def is_defined(self, name):
        return name in self.obj or name in self.fun or name in self.defined_extra or name in COND_CONTEXT

    def eval(self, expr, depth=0):
        if depth > 32:
            raise ExprError("macro recursion too deep: " + expr)
        key = (expr.strip(), self.permissive)
        if key in self.eval_cache:
            return self.eval_cache[key]
        toks = lex_expr(expr)
        val = _EvalParser(toks, self, depth).parse()
        self.eval_cache[key] = val
        return val

    def expand_id(self, name, depth):
        if name in self.obj:
            return self.eval(self.obj[name], depth + 1)
        if self.permissive:
            return 0
        raise ExprError("unknown identifier %r" % name)

    def expand_fun(self, name, args, depth):
        if name not in self.fun:
            if self.permissive:
                return 0
            raise ExprError("unknown macro function %r" % name)
        plist, body = self.fun[name]
        if len(plist) != len(args):
            raise ExprError("macro %s: %d args expected, %d given" % (name, len(plist), len(args)))
        subst = body
        for pn, pv in zip(plist, args):
            subst = re.sub(r"\b%s\b" % re.escape(pn), "(%s)" % pv, subst)
        return self.eval(subst, depth + 1)


class _EvalParser(object):
    LEVELS = [
        ["||"], ["&&"], ["|"], ["^"], ["&"], ["==", "!="],
        ["<", "<=", ">", ">="], ["<<", ">>"], ["+", "-"], ["*", "/", "%"],
    ]

    def __init__(self, toks, macros, depth):
        self.toks = toks
        self.i = 0
        self.macros = macros
        self.depth = depth

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else None

    def take(self, op=None):
        t = self.peek()
        if t is None:
            raise ExprError("unexpected end of expression")
        if op is not None and not (t[0] == "op" and t[1] == op):
            raise ExprError("expected %r, got %r" % (op, t))
        self.i += 1
        return t

    def parse(self):
        v = self.ternary()
        if self.peek() is not None:
            raise ExprError("trailing tokens: %r" % (self.toks[self.i:],))
        return v

    def ternary(self):
        c = self.binary(0)
        if self.peek() == ("op", "?"):
            self.take("?")
            a = self.ternary()
            self.take(":")
            b = self.ternary()
            return a if c else b
        return c

    def binary(self, lvl):
        if lvl >= len(self.LEVELS):
            return self.unary()
        left = self.binary(lvl + 1)
        while True:
            t = self.peek()
            if t and t[0] == "op" and t[1] in self.LEVELS[lvl]:
                op = t[1]
                self.take()
                right = self.binary(lvl + 1)
                left = self.apply(op, left, right)
            else:
                return left

    def apply(self, op, a, b):
        if op == "||":
            return 1 if (a or b) else 0
        if op == "&&":
            return 1 if (a and b) else 0
        if op == "|":   return a | b
        if op == "^":   return a ^ b
        if op == "&":   return a & b
        if op == "==":  return 1 if a == b else 0
        if op == "!=":  return 1 if a != b else 0
        if op == "<":   return 1 if a < b else 0
        if op == "<=":  return 1 if a <= b else 0
        if op == ">":   return 1 if a > b else 0
        if op == ">=":  return 1 if a >= b else 0
        if op == "<<":
            if b < 0 or b > 62:
                raise ExprError("shift out of range")
            return a << b
        if op == ">>":
            return a >> b
        if op == "+":   return a + b
        if op == "-":   return a - b
        if op == "*":   return a * b
        if op == "/":
            if b == 0:
                raise ExprError("division by zero")
            return int(a / b) if (a < 0) != (b < 0) else a // b
        if op == "%":
            if b == 0:
                raise ExprError("modulo by zero")
            return a % b
        raise ExprError("unhandled operator " + op)

    def unary(self):
        t = self.peek()
        if t is None:
            raise ExprError("unexpected end (unary)")
        if t[0] == "op" and t[1] in ("-", "~", "!", "+"):
            self.take()
            v = self.unary()
            if t[1] == "-":
                return -v
            if t[1] == "~":
                return ~v
            if t[1] == "!":
                return 0 if v else 1
            return v
        if t[0] == "num":
            self.take()
            return t[1]
        if t[0] == "id":
            name = t[1]
            nxt = self.toks[self.i + 1] if self.i + 1 < len(self.toks) else None
            if nxt == ("op", "(") and name in self.macros.fun:
                self.take()
                self.take("(")
                args = []
                depth = 1
                cur = []
                while True:
                    tt = self.peek()
                    if tt is None:
                        raise ExprError("unterminated macro call " + name)
                    if tt == ("op", "("):
                        depth += 1
                    elif tt == ("op", ")"):
                        depth -= 1
                        if depth == 0:
                            self.take()
                            break
                    if tt == ("op", ",") and depth == 1:
                        self.take()
                        args.append(self.render(cur))
                        cur = []
                        continue
                    cur.append(self.take())
                if cur or args:
                    args.append(self.render(cur))
                vals = [self.macros.eval(a, self.depth) for a in args]
                return self.macros.expand_fun(name, vals, self.depth)
            self.take()
            return self.macros.expand_id(name, self.depth)
        if t == ("op", "("):
            self.take("(")
            v = self.ternary()
            self.take(")")
            return v
        raise ExprError("unexpected token %r" % (t,))

    def render(self, toks):
        return " ".join(str(v) for _, v in toks)


# ---------------------------------------------------------------------------
# C declaration parser
# ---------------------------------------------------------------------------

BUILTIN_SIZES = {
    "char": (1, 1), "signed char": (1, 1), "unsigned char": (1, 1),
    "short": (2, 2), "unsigned short": (2, 2), "short int": (2, 2),
    "unsigned short int": (2, 2),
    "int": (4, 4), "unsigned int": (4, 4), "unsigned": (4, 4), "signed int": (4, 4),
    "long": (4, 4), "unsigned long": (4, 4), "long int": (4, 4), "unsigned long int": (4, 4),
    "long long": (8, 8), "unsigned long long": (8, 8),
    "long long int": (8, 8), "unsigned long long int": (8, 8),
    "float": (4, 4), "double": (8, 8), "long double": (8, 8),
    "bool": (1, 1), "_Bool": (1, 1),
    "wchar_t": (2, 2),   # Windows
    "size_t": (8, 8), "uint8_t": (1, 1), "uint16_t": (2, 2), "uint32_t": (4, 4),
    "uint64_t": (8, 8), "int8_t": (1, 1), "int16_t": (2, 2), "int32_t": (4, 4),
    "int64_t": (8, 8), "float32_t": (4, 4),
    # Win32 handle/pointer typedefs used by the parse-only dx12 descriptor headers
    "HWND": (8, 8), "HANDLE": (8, 8), "HINSTANCE": (8, 8), "HMODULE": (8, 8),
    "HKEY": (8, 8), "LPVOID": (8, 8), "LPCVOID": (8, 8), "LPCWSTR": (8, 8),
    "LPWSTR": (8, 8), "LPCSTR": (8, 8), "LPSTR": (8, 8), "HDC": (8, 8),
    "HBITMAP": (8, 8), "HICON": (8, 8), "HCURSOR": (8, 8),
    "UINT": (4, 4), "DWORD": (4, 4), "BOOL": (4, 4), "HRESULT": (4, 4),
    "BYTE": (1, 1), "WORD": (2, 2), "LONG": (4, 4), "ULONG": (4, 4),
}

TOKEN_RE = re.compile(
    r"""(?P<id>[A-Za-z_][A-Za-z0-9_]*)
      | (?P<num>0[xX][0-9a-fA-F]+[uUlL]*|\d+\.\d*[fF]?|\d+[uUlL]*)
      | (?P<str>"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')
      | (?P<eltipsis>\.\.\.)
      | (?P<punct>[{}()\[\];,*:=<>~!+\-/%&|^?.])
    """, re.X)


def tokenize(text):
    toks = []
    line = 1
    pos = 0
    while pos < len(text):
        c = text[pos]
        if c == "\n":
            line += 1
            pos += 1
            continue
        if c in " \t\r":
            pos += 1
            continue
        m = TOKEN_RE.match(text, pos)
        if not m:
            die("cannot tokenize %r (line %d)" % (text[pos:pos + 32], line))
        pos = m.end()
        if m.group("id"):
            toks.append(("id", m.group("id"), line))
        elif m.group("num"):
            toks.append(("num", m.group("num"), line))
        elif m.group("str"):
            toks.append(("str", m.group("str"), line))
        elif m.group("eltipsis"):
            toks.append(("punct", "...", line))
        else:
            toks.append(("punct", m.group("punct"), line))
    return toks


def tokens_to_expr(toks):
    """Rebuild an expression string from C token-stream tokens without breaking
    multi-char operators (the stream tokenizer emits single-char puncts)."""
    out = []
    prev = None
    for t in toks:
        kind, val = t[0], t[1]
        if prev is not None and prev[0] in ("id", "num") and kind in ("id", "num"):
            out.append(" ")
        out.append(str(val))
        prev = (kind, val)
    return "".join(out)


class TypeRef(object):
    """kind: prim|struct|union|enum|ptr|funptr|array|unresolved"""

    def __init__(self, kind, name=None, inner=None, array_len=None, args=None, ret=None, is_const=False):
        self.kind = kind
        self.name = name
        self.inner = inner
        self.array_len = array_len
        self.args = args
        self.ret = ret
        self.is_const = is_const

    def __repr__(self):
        if self.kind == "ptr":
            return "ptr(%r)" % self.inner
        if self.kind == "array":
            return "array(%r,%s)" % (self.inner, self.array_len)
        return "%s:%s" % (self.kind, self.name)


class StructInfo(object):
    def __init__(self, name, kind):
        self.name = name
        self.kind = kind          # struct | union
        self.fields = []          # list of (field_name, TypeRef); "" = anonymous
        self.size = None
        self.align = None
        self.header = None
        self.anonymous = False
        self.resolving = False
        self.promoted = {}        # member name -> inner field name (for anonymous)

    def resolve(self, types):
        if self.size is not None:
            return
        if self.resolving:
            die("by-value recursion in %s" % self.name)
        self.resolving = True
        off = 0
        max_align = 1
        max_size = 0
        offsets = {}
        for fname, ftype in self.fields:
            fs, fa = typename_size_align(ftype, types)
            max_align = max(max_align, fa)
            if fname == "":
                # anonymous union/struct member: promote members
                inner = types.get(ftype.name)
                if inner is None or not isinstance(inner, StructInfo):
                    die("anonymous member %r without StructInfo" % ftype.name)
                inner.resolve(types)
                base = off if self.kind == "struct" else 0
                if self.kind == "struct":
                    off = (off + fa - 1) // fa * fa
                    base = off
                for iname, ioff in inner.field_offsets().items():
                    offsets[iname] = base + ioff
                if self.kind == "struct":
                    off += inner.size
                else:
                    max_size = max(max_size, inner.size)
                continue
            if self.kind == "struct":
                off = (off + fa - 1) // fa * fa
                offsets[fname] = off
                off += fs
            else:
                offsets[fname] = 0
                max_size = max(max_size, fs)
        self.align = max_align
        body = off if self.kind == "struct" else max_size
        self.size = (body + max_align - 1) // max_align * max_align
        self._offsets = offsets
        self.resolving = False

    def field_offsets(self):
        return getattr(self, "_offsets", {})


def typename_size_align(tref, types):
    if isinstance(tref, str):
        key = resolve_prim_alias(tref, types)
        if key in BUILTIN_SIZES:
            return BUILTIN_SIZES[key]
        die("unknown primitive %r" % tref)
    if tref.kind == "prim":
        key = resolve_prim_alias(tref.name, types)
        if key in BUILTIN_SIZES:
            return BUILTIN_SIZES[key]
        die("unknown primitive %r" % tref.name)
    if tref.kind == "ptr" or tref.kind == "funptr":
        return (8, 8)
    if tref.kind == "array":
        if tref.array_len is None:
            die("array without length")
        inner_s, inner_a = typename_size_align(tref.inner, types)
        return (inner_s * tref.array_len, inner_a)
    if tref.kind in ("struct", "union", "enum", "unresolved"):
        name = tref.name
        st = types.get(name)
        if st is None:
            die("unknown type used by value: %r" % name)
        if isinstance(st, str):
            return typename_size_align(st, types)
        if isinstance(st, TypeRef):
            if st.kind == "enum":
                return (4, 4)
            return typename_size_align(st, types)
        if not isinstance(st, StructInfo):
            die("unexpected type entry %r" % name)
        if st.kind == "enum":
            return (4, 4)
        st.resolve(types)
        return (st.size, st.align)
    die("unresolvable type %r" % (tref,))


def resolve_prim_alias(name, types):
    seen = set()
    while name in types and isinstance(types[name], str):
        if name in seen:
            die("primitive alias cycle at %r" % name)
        seen.add(name)
        name = types[name]
    return name


def is_cpp_member_seg(seg):
    """C++ helper members (static member functions/initializers, access
    specifiers) inside the otherwise C-layout structs: no ABI impact."""
    if not seg:
        return True
    if seg[0][0] != "id":
        return False
    return seg[0][1] in ("static", "inline", "virtual", "public", "private", "protected",
                         "constexpr", "using", "friend", "template", "operator")


class Parser(object):
    def __init__(self):
        self.types = {}
        self.enums = {}
        self.enum_values = {}
        self.enum_origin = {}
        self.macros = MacroTable()
        self.functions = []
        self.integer_defines = {}
        self.declared_in = {}
        self.struct_order = []
        self.opaque_names = set()
        self.anon_counter = 0

    # -- preprocessing -----------------------------------------------------
    def eval_cond(self, expr):
        def repl(m):
            name = m.group(1) or m.group(2)
            return "1" if self.macros.is_defined(name) else "0"
        expr = re.sub(r"defined\s*\(\s*([A-Za-z_]\w*)\s*\)|defined\s+([A-Za-z_]\w*)", repl, expr)
        self.macros.permissive = True
        try:
            return bool(self.macros.eval(expr))
        except ExprError:
            return False
        finally:
            self.macros.permissive = False

    def preprocess(self, text, origin=None):
        lines = text.split("\n")
        joined = []
        buf = None
        for ln in lines:
            if buf is None:
                buf = ln
            else:
                buf = buf + "\n" + ln
            if buf.rstrip("\r").endswith("\\"):
                buf = buf.rstrip("\r")[:-1]
                continue
            joined.append(buf)
            buf = None
        if buf is not None:
            joined.append(buf)
        out = []
        stack = []

        def active():
            return all(f["active"] for f in stack)

        for raw in joined:
            line = raw.strip()
            if line.startswith("#"):
                rest = line[1:].strip()
                words = rest.split(None, 1)
                word = words[0] if words else ""
                body = words[1].strip() if len(words) > 1 else ""
                if word == "define":
                    if active():
                        self.macros.define_line("#define " + body, origin)
                elif word == "undef":
                    if active() and body:
                        name = body.split()[0]
                        self.macros.obj.pop(name, None)
                        self.macros.fun.pop(name, None)
                elif word in ("if", "ifdef", "ifndef"):
                    parent = active()
                    if word == "ifdef":
                        val = self.eval_cond("defined(%s)" % body)
                    elif word == "ifndef":
                        val = not self.eval_cond("defined(%s)" % body)
                    else:
                        val = self.eval_cond(body)
                    stack.append({"parent": parent, "active": parent and bool(val), "taken": bool(val)})
                elif word == "elif":
                    if not stack:
                        die("#elif without #if")
                    top = stack[-1]
                    if top["taken"]:
                        top["active"] = False
                    else:
                        val = self.eval_cond(body)
                        top["active"] = top["parent"] and bool(val)
                        top["taken"] = bool(val)
                elif word == "else":
                    if not stack:
                        die("#else without #if")
                    top = stack[-1]
                    top["active"] = top["parent"] and not top["taken"]
                    top["taken"] = True
                elif word == "endif":
                    if not stack:
                        die("#endif without #if")
                    stack.pop()
                # include/pragma/error: dropped
                continue
            if active():
                out.append(raw)
        if stack:
            die("unterminated #if")
        return "\n".join(out)

    def evaluate_integer_defines(self):
        self.macros.permissive = False
        for name in list(self.macros.obj.keys()):
            if name.startswith("_"):
                continue
            body = self.macros.obj[name].strip()
            if not body or body.startswith('"') or body.startswith("'") or body.startswith("{"):
                continue
            try:
                self.integer_defines[name] = int(self.macros.eval(name))
            except ExprError:
                continue

    # -- token stream ------------------------------------------------------
    def parse_text(self, component, header, text, collect_functions):
        toks = tokenize(strip_comments(text))
        self._parse_tokens(component, header, toks, collect_functions)

    def _parse_tokens(self, component, header, toks, collect_functions):
        i = 0
        n = len(toks)
        while i < n:
            t = toks[i]
            if t[0] == "punct" and t[1] == ";":
                i += 1
                continue
            if t[0] == "punct" and t[1] == "}":
                i += 1
                continue
            if t[0] == "id" and t[1] == "extern":
                j = i + 1
                if j < n and toks[j][0] == "str":
                    j += 1
                if j < n and toks[j][0] == "punct" and toks[j][1] == "{":
                    i = j + 1
                    continue
                die("unsupported extern form in %s line %d" % (header, t[2]))
            start = i
            j = i
            depth = 0
            brace_start = None
            semi_at = None
            while j < n:
                tt = toks[j]
                if tt[0] == "punct" and tt[1] in "([":
                    depth += 1
                elif tt[0] == "punct" and tt[1] in ")]":
                    depth -= 1
                elif tt[0] == "punct" and tt[1] == "{":
                    if depth == 0:
                        brace_start = j
                        break
                elif tt[0] == "punct" and tt[1] == ";":
                    if depth == 0:
                        semi_at = j
                        break
                j += 1
            if brace_start is not None:
                close = None
                depth2 = 0
                k = brace_start
                while k < n:
                    tt = toks[k]
                    if tt[0] == "punct" and tt[1] == "{":
                        depth2 += 1
                    elif tt[0] == "punct" and tt[1] == "}":
                        depth2 -= 1
                        if depth2 == 0:
                            close = k
                            break
                    k += 1
                if close is None:
                    die("unterminated block in %s line %d" % (header, toks[brace_start][2]))
                k2 = close + 1
                head = toks[start:brace_start]
                is_fn = False
                for k in range(len(head)):
                    if head[k][0] == "punct" and head[k][1] == "(":
                        if k > 0 and head[k - 1][0] == "id" and head[k - 1][1] not in ("FFX_DEPRECATION", "DEPRECATION"):
                            is_fn = True
                        break
                if is_fn:
                    # function definition: the declaration ends at the body's '}'
                    if k2 < n and toks[k2][0] == "punct" and toks[k2][1] == ";":
                        k2 += 1
                    self.handle_block_decl(component, header, head, toks[brace_start + 1:close], [])
                    i = k2
                    continue
                trail = []
                while k2 < n and not (toks[k2][0] == "punct" and toks[k2][1] == ";"):
                    trail.append(toks[k2])
                    k2 += 1
                if k2 >= n:
                    die("missing ';' after block in %s line %d" % (header, toks[close][2]))
                self.handle_block_decl(component, header, head, toks[brace_start + 1:close], trail)
                i = k2 + 1
                continue
            if semi_at is None:
                die("unterminated declaration in %s line %d" % (header, t[2]))
            self.handle_simple_decl(component, header, toks[start:semi_at], collect_functions)
            i = semi_at + 1

    # -- declarations --------------------------------------------------------
    def handle_simple_decl(self, component, header, decl, collect_functions):
        if not decl:
            return
        txt = " ".join(str(t[1]) for t in decl)
        if txt.startswith("typedef "):
            self.handle_typedef(component, header, decl[1:])
            return
        if txt.startswith("static_assert") or txt.startswith("using ") or txt.startswith("namespace"):
            return
        if txt.startswith("class ") or txt.startswith("template"):
            die("C++ construct in C parse set: %s" % txt)
        if decl[0][0] == "id" and decl[0][1] in ("struct", "union"):
            # forward declaration: struct X;  /  union X;
            if len(decl) == 2 and decl[1][0] == "id":
                name = decl[1][1]
                self.opaque_names.add(name)
                self.types[name] = TypeRef(decl[0][1], name=name)
                self.declared_in[name] = (component, header)
                return
        if decl[0][0] == "id" and decl[0][1] in ("static", "const", "constexpr", "inline", "FFX_FORWARD_DECLARE"):
            # file-scope data / template fragments / forward-declare macro: no
            # declared-function surface
            return
        if collect_functions:
            has_paren = any(t[0] == "punct" and t[1] == "(" for t in decl)
            if has_paren:
                self.handle_function_decl(component, header, decl, has_body=False)
                return
        # anything else is ignored only if it looks like an extern declaration
        if any(t[0] == "id" and t[1] == "extern" for t in decl):
            return
        die("unhandled simple declaration in %s: %s" % (header, txt[:140]))

    def handle_typedef(self, component, header, decl):
        if not decl:
            die("empty typedef in %s" % header)
        first = decl[0]
        if first[0] != "id":
            die("weird typedef start in %s: %r" % (header, first))
        kw = first[1]
        if kw in ("struct", "union"):
            i = 1
            while i < len(decl) and decl[i][0] == "id" and decl[i][1] == "FFX_DEPRECATION":
                depth = 0
                while i < len(decl):
                    if decl[i][0] == "punct" and decl[i][1] == "(":
                        depth += 1
                    elif decl[i][0] == "punct" and decl[i][1] == ")":
                        depth -= 1
                        if depth == 0:
                            i += 1
                            break
                    i += 1
            tag = None
            if i < len(decl) and decl[i][0] == "id":
                tag = decl[i][1]
                i += 1
            self.register_aliases(decl[i:], kw, tag, component, header)
            return
        if kw == "enum":
            i = 1
            tag = None
            if i < len(decl) and decl[i][0] == "id":
                tag = decl[i][1]
                i += 1
            self.register_enum_aliases(decl[i:], tag, component, header)
            return
        # typedef <type...> <name>[ [N] ];  or  ret (*name)(args);
        lp = None
        for k, t in enumerate(decl):
            if t[0] == "punct" and t[1] == "(":
                lp = k
                break
        if lp is not None and lp + 1 < len(decl) and decl[lp + 1][0] == "punct" and decl[lp + 1][1] == "*":
            name_tok = decl[lp + 2] if lp + 2 < len(decl) else None
            if name_tok is None or name_tok[0] != "id":
                die("bad function pointer typedef in %s" % header)
            name = name_tok[1]
            depth = 0
            rp = None
            for k in range(lp, len(decl)):
                tt = decl[k]
                if tt[0] == "punct" and tt[1] == "(":
                    depth += 1
                elif tt[0] == "punct" and tt[1] == ")":
                    depth -= 1
                    if depth == 0:
                        rp = k
                        break
            if rp is None:
                die("unterminated fn ptr typedef in %s" % header)
            ret_type = self.parse_type_tokens(decl[:lp], header)
            # args: optional '(' ... ')' after rp
            k = rp + 1
            args = []
            if k < len(decl) and decl[k][0] == "punct" and decl[k][1] == "(":
                depth = 0
                rp2 = None
                for kk in range(k, len(decl)):
                    if decl[kk][0] == "punct" and decl[kk][1] == "(":
                        depth += 1
                    elif decl[kk][0] == "punct" and decl[kk][1] == ")":
                        depth -= 1
                        if depth == 0:
                            rp2 = kk
                            break
                if rp2 is None:
                    die("unterminated fn ptr arg list in %s" % header)
                args = self.parse_arg_list(decl[k + 1:rp2], header)
                k = rp2 + 1
            if k != len(decl):
                die("trailing tokens in fn ptr typedef %s: %r" % (name, decl[k:]))
            self.types[name] = TypeRef("funptr", name=name, args=args, ret=ret_type)
            self.declared_in[name] = (component, header)
            return
        # array typedef?  find trailing "name [ N ]"
        if len(decl) >= 4 and decl[-1][0] == "punct" and decl[-1][1] == "]" and decl[-3][0] == "punct" and decl[-3][1] == "[":
            name_tok = decl[-4]
            if name_tok[0] != "id":
                die("array typedef without name in %s" % header)
            name = name_tok[1]
            arr = self.eval_array_len(decl[-2:-1], header)
            base = self.parse_type_tokens(decl[:-4], header)
            self.types[name] = TypeRef("array", inner=base, array_len=arr)
            self.declared_in[name] = (component, header)
            return
        name_tok = decl[-1]
        if name_tok[0] != "id":
            die("typedef without name in %s: %r" % (header, decl))
        name = name_tok[1]
        base = self.parse_type_tokens(decl[:-1], header)
        self.types[name] = base
        self.declared_in[name] = (component, header)

    def register_aliases(self, rest, kind, tag, component, header):
        names = [t[1] for t in rest if t[0] == "id"]
        if tag:
            self.declared_in[tag] = (component, header)
        for nm in names:
            self.types[nm] = TypeRef(kind, name=tag if tag else nm)
            self.declared_in[nm] = (component, header)

    def register_enum_aliases(self, rest, tag, component, header):
        names = [t[1] for t in rest if t[0] == "id"]
        if tag:
            self.declared_in[tag] = (component, header)
        for nm in names:
            self.types[nm] = TypeRef("enum", name=tag if tag else nm)
            self.declared_in[nm] = (component, header)

    def handle_block_decl(self, component, header, head, body, trail):
        if head and head[0][0] == "id" and head[0][1] == "typedef":
            head = head[1:]
        head_is_fn = False
        for k in range(len(head)):
            if head[k][0] == "punct" and head[k][1] == "(":
                if k > 0 and head[k - 1][0] == "id" and head[k - 1][1] not in ("FFX_DEPRECATION", "DEPRECATION"):
                    head_is_fn = True
                break
        if head and head[0][0] == "id" and head[0][1] in ("static", "const", "constexpr", "inline") and not head_is_fn:
            # file-scope static data with a brace initializer: no ABI surface
            return
        if head and head[0][0] == "id" and head[0][1] in ("struct", "union"):
            kind = head[0][1]
            i = 1
            while i < len(head) and head[i][0] == "id" and head[i][1] == "FFX_DEPRECATION":
                depth = 0
                while i < len(head):
                    if head[i][0] == "punct" and head[i][1] == "(":
                        depth += 1
                    elif head[i][0] == "punct" and head[i][1] == ")":
                        depth -= 1
                        if depth == 0:
                            i += 1
                            break
                    i += 1
            tag = None
            if i < len(head) and head[i][0] == "id":
                tag = head[i][1]
            st = self.parse_struct_body(kind, tag, header, body)
            names = [t[1] for t in trail if t[0] == "id"]
            if tag is None and names:
                st.name = names[0]
            if tag is not None:
                self.types[tag] = TypeRef(kind, name=st.name)
                self.declared_in[tag] = (component, header)
            for nm in names:
                self.types[nm] = TypeRef(kind, name=st.name)
                self.declared_in[nm] = (component, header)
            self.types[st.name] = st
            if st.name not in self.struct_order:
                self.struct_order.append(st.name)
            return
        if head and head[0][0] == "id" and head[0][1] == "enum":
            tag = None
            if len(head) > 1 and head[1][0] == "id":
                tag = head[1][1]
            self.parse_enum_body(tag, header, body)
            names = [t[1] for t in trail if t[0] == "id"]
            for nm in names:
                self.types[nm] = TypeRef("enum", name=tag if tag else nm)
                self.declared_in[nm] = (component, header)
            if tag:
                self.types[tag] = TypeRef("enum", name=tag)
                self.declared_in[tag] = (component, header)
            return
        self.handle_function_decl(component, header, head, has_body=True)

    def parse_struct_body(self, kind, tag, header, body):
        st = StructInfo(tag if tag else "<anonymous>", kind)
        st.header = header
        segs = []
        cur = []
        depth = 0
        for t in body:
            if t[0] == "punct" and t[1] in "([{":
                depth += 1
            elif t[0] == "punct" and t[1] in ")]}":
                depth -= 1
            if t[0] == "punct" and t[1] == ";" and depth == 0:
                if cur:
                    segs.append(cur)
                cur = []
                continue
            cur.append(t)
        if cur:
            if not is_cpp_member_seg(cur):
                die("struct %s: trailing tokens without ';'" % st.name)
        for seg in segs:
            if is_cpp_member_seg(seg):
                continue
            self.parse_struct_field(st, seg, header)
        return st

    def parse_struct_field(self, st, seg, header):
        if not seg:
            return
        # inline union/struct member
        if seg[0][0] == "id" and seg[0][1] in ("union", "struct"):
            b0 = None
            for k, t in enumerate(seg):
                if t[0] == "punct" and t[1] == "{":
                    b0 = k
                    break
            if b0 is None:
                pass  # `struct X y;` reference: normal field path below
            else:
                depth = 0
                b1 = None
                for k in range(b0, len(seg)):
                    if seg[k][0] == "punct" and seg[k][1] == "{":
                        depth += 1
                    elif seg[k][0] == "punct" and seg[k][1] == "}":
                        depth -= 1
                        if depth == 0:
                            b1 = k
                            break
                if b1 is None:
                    die("struct %s: unterminated inline type" % st.name)
                inner = self.parse_struct_body(seg[0][1], None, header, seg[b0 + 1:b1])
                decl_toks = seg[b1 + 1:]
                if not decl_toks:
                    inner.name = "%s::anon%d" % (st.name, self.anon_counter)
                    self.anon_counter += 1
                    inner.anonymous = True
                    self.types[inner.name] = inner
                    self.struct_order.append(inner.name)
                    st.fields.append(("", TypeRef(seg[0][1], name=inner.name)))
                    return
                # named inline type: `union { ... } name;`
                star = 0
                idx = 0
                while idx < len(decl_toks) and decl_toks[idx][0] == "punct" and decl_toks[idx][1] == "*":
                    star += 1
                    idx += 1
                if idx >= len(decl_toks) or decl_toks[idx][0] != "id":
                    die("struct %s: bad inline declarator" % st.name)
                nm = decl_toks[idx][1]
                inner.name = "%s::%s" % (st.name, nm)
                self.types[inner.name] = inner
                self.struct_order.append(inner.name)
                tref = TypeRef(seg[0][1], name=inner.name)
                for _ in range(star):
                    tref = TypeRef("ptr", inner=tref)
                st.fields.append((nm, tref))
                return
        # function pointer field
        lp = None
        for k, t in enumerate(seg):
            if t[0] == "punct" and t[1] == "(":
                lp = k
                break
        if lp is not None and lp + 1 < len(seg) and seg[lp + 1][0] == "punct" and seg[lp + 1][1] == "*":
            name_tok = seg[lp + 2] if lp + 2 < len(seg) else None
            if name_tok is None or name_tok[0] != "id":
                die("struct %s: bad function-pointer field" % st.name)
            st.fields.append((name_tok[1], TypeRef("funptr", name=name_tok[1])))
            return
        # normal field(s)
        parts = []
        cur = []
        depth = 0
        for t in seg:
            if t[0] == "punct" and t[1] in "([":
                depth += 1
            elif t[0] == "punct" and t[1] in ")]":
                depth -= 1
            if t[0] == "punct" and t[1] == "," and depth == 0:
                parts.append(cur)
                cur = []
                continue
            cur.append(t)
        parts.append(cur)
        first = parts[0]
        k = len(first) - 1
        if k >= 0 and first[k][0] == "punct" and first[k][1] == "]":
            depth = 0
            while k >= 0:
                if first[k][0] == "punct" and first[k][1] == "]":
                    depth += 1
                elif first[k][0] == "punct" and first[k][1] == "[":
                    depth -= 1
                    if depth == 0:
                        break
                k -= 1
            k -= 1
        if k < 0 or first[k][0] != "id":
            die("struct %s: cannot find field name in %r" % (st.name, first[:12]))
        name_idx = k
        stars = 0
        kk = name_idx - 1
        while kk >= 0 and first[kk][0] == "punct" and first[kk][1] == "*":
            stars += 1
            kk -= 1
        base_toks = first[:kk + 1]
        if not base_toks:
            die("struct %s: empty base type for %s" % (st.name, first[name_idx][1]))
        base_type = self.parse_type_tokens(base_toks, header)
        self.add_field_declarator(st, base_type, first[kk + 1:], header)
        for part in parts[1:]:
            self.add_field_declarator(st, base_type, part, header)

    def add_field_declarator(self, st, base_type, decl_toks, header):
        stars = 0
        i = 0
        while i < len(decl_toks) and decl_toks[i][0] == "punct" and decl_toks[i][1] == "*":
            stars += 1
            i += 1
        if i >= len(decl_toks) or decl_toks[i][0] != "id":
            die("struct %s: bad declarator %r" % (st.name, decl_toks))
        name = decl_toks[i][1]
        i += 1
        arr = None
        if i < len(decl_toks) and decl_toks[i][0] == "punct" and decl_toks[i][1] == "[":
            depth = 0
            j = i
            while j < len(decl_toks):
                if decl_toks[j][0] == "punct" and decl_toks[j][1] == "[":
                    depth += 1
                elif decl_toks[j][0] == "punct" and decl_toks[j][1] == "]":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            arr = self.eval_array_len(decl_toks[i + 1:j], header)
            i = j + 1
        if i != len(decl_toks):
            die("struct %s: trailing declarator tokens for %s" % (st.name, name))
        t = base_type
        for _ in range(stars):
            t = TypeRef("ptr", inner=t)
        if arr is not None:
            t = TypeRef("array", inner=t, array_len=arr)
        st.fields.append((name, t))

    def parse_type_tokens(self, toks, header):
        orig = list(toks)
        drop = ("volatile", "struct", "union", "enum", "class", "register",
                "static", "inline", "extern", "FFX_API", "FFX_API_ENTRY", "FFX_STATIC") + ANNOTATION_MACROS
        toks = [t for t in toks if not (t[0] == "id" and t[1] in drop)]
        has_const = any(t[0] == "id" and t[1] == "const" for t in toks)
        toks = [t for t in toks if not (t[0] == "id" and t[1] == "const")]
        if not toks:
            die("empty type in %s (raw tokens: %r)" % (header, orig[:10]))
        stars = 0
        while toks and toks[-1][0] == "punct" and toks[-1][1] == "*":
            stars += 1
            toks = toks[:-1]
        if len(toks) == 1 and toks[0][0] == "id":
            base = self.resolve_type_name(toks[0][1], header)
        elif all(t[0] == "id" for t in toks):
            name = " ".join(t[1] for t in toks)
            base = name if name in BUILTIN_SIZES else self.resolve_type_name(name, header)
        else:
            die("cannot parse type tokens %r in %s" % (toks, header))
        t = base
        if isinstance(t, str):
            t = TypeRef("prim", name=t)
        if has_const and isinstance(t, TypeRef) and t.kind != "ptr":
            t = TypeRef(t.kind, name=t.name, inner=t.inner, array_len=t.array_len,
                        args=t.args, ret=t.ret, is_const=True)
        for _ in range(stars):
            t = TypeRef("ptr", inner=t)
        return t

    def resolve_type_name(self, name, header):
        if name in BUILTIN_SIZES:
            return name
        if name in self.types:
            v = self.types[name]
            if isinstance(v, StructInfo):
                return TypeRef(v.kind, name=v.name)
            return v
        # lazy: may be declared later in another file
        return TypeRef("unresolved", name=name)

    def parse_arg_list(self, toks, header):
        args = []
        if not toks:
            return args
        if len(toks) == 1 and toks[0][0] == "id" and toks[0][1] == "void":
            return args
        parts = []
        cur = []
        depth = 0
        for t in toks:
            if t[0] == "punct" and t[1] in "([":
                depth += 1
            elif t[0] == "punct" and t[1] in ")]":
                depth -= 1
            if t[0] == "punct" and t[1] == "," and depth == 0:
                parts.append(cur)
                cur = []
                continue
            cur.append(t)
        parts.append(cur)
        for part in parts:
            if not part:
                continue
            args.append(self.parse_param(part, header))
        return args

    def parse_param(self, toks, header):
        if len(toks) == 1 and toks[0][0] == "punct" and toks[0][1] == "...":
            return {"name": "...", "type": "..."}
        lp = None
        for k, t in enumerate(toks):
            if t[0] == "punct" and t[1] == "(":
                lp = k
                break
        if lp is not None and lp + 1 < len(toks) and toks[lp + 1][0] == "punct" and toks[lp + 1][1] == "*":
            nm = toks[lp + 2][1] if lp + 2 < len(toks) and toks[lp + 2][0] == "id" else "?"
            return {"name": nm, "type": TypeRef("funptr", name=nm)}
        # strip a default argument (`= expr`): not part of the function type
        cut = None
        depth = 0
        for k, t in enumerate(toks):
            if t[0] == "punct" and t[1] in "([":
                depth += 1
            elif t[0] == "punct" and t[1] in ")]":
                depth -= 1
            elif t[0] == "punct" and t[1] == "=" and depth == 0:
                cut = k
                break
        if cut is not None:
            toks = toks[:cut]
        name = None
        k = len(toks) - 1
        if k >= 1 and toks[k][0] == "punct" and toks[k][1] == "]":
            depth = 0
            while k >= 0:
                if toks[k][0] == "punct" and toks[k][1] == "]":
                    depth += 1
                elif toks[k][0] == "punct" and toks[k][1] == "[":
                    depth -= 1
                    if depth == 0:
                        break
                k -= 1
            k -= 1
        if k >= 0 and toks[k][0] == "id":
            name = toks[k][1]
            toks = toks[:k]
        t = self.parse_type_tokens(toks, header)
        return {"name": name, "type": t}

    def eval_array_len(self, toks, header):
        expr = tokens_to_expr(toks)
        try:
            return int(self.macros.eval(expr))
        except ExprError as e:
            die("cannot evaluate array length %r in %s: %s" % (expr, header, e))

    def parse_enum_body(self, tag, header, body):
        cur_val = 0
        cur = []
        entries = []
        for t in body:
            if t[0] == "punct" and t[1] == ",":
                if cur:
                    entries.append(cur)
                cur = []
                continue
            cur.append(t)
        if cur:
            entries.append(cur)
        for e in entries:
            if not e:
                continue
            if e[0][0] != "id":
                die("enum %s: bad entry %r" % (tag, e[:6]))
            name = e[0][1]
            val = cur_val
            if len(e) > 1:
                if not (e[1][0] == "punct" and e[1][1] == "="):
                    die("enum %s: unexpected tokens after %s" % (tag, name))
                expr = tokens_to_expr(e[2:])
                try:
                    val = int(self.macros.eval(expr))
                except ExprError as ex:
                    die("enum %s: cannot evaluate %r: %s" % (tag, expr, ex))
            self.enum_values[name] = wrap_i32(val)
            self.enum_origin[name] = header
            self.macros.obj[name] = str(wrap_i32(val))
            cur_val = val + 1
        if tag:
            self.enums[tag] = True

    def handle_function_decl(self, component, header, decl, has_body):
        toks = list(decl)
        kind = None
        saw_static = False
        saw_inline = False
        saw_ffx_static = False
        saw_export = False
        i = 0
        while i < len(toks) and toks[i][0] == "id" and toks[i][1] in (
                "FFX_API", "FFX_API_ENTRY", "FFX_STATIC", "static", "inline", "FFX_INLINE"):
            if toks[i][1] in ("FFX_API", "FFX_API_ENTRY"):
                saw_export = True
            if toks[i][1] == "FFX_STATIC":
                saw_ffx_static = True
            if toks[i][1] == "static":
                saw_static = True
            if toks[i][1] in ("inline", "FFX_INLINE"):
                saw_inline = True
            i += 1
        toks = toks[i:]
        if not toks:
            die("function decl without tokens in %s" % header)
        lp = None
        for k, t in enumerate(toks):
            if t[0] == "punct" and t[1] == "(":
                lp = k
                break
        if lp is None:
            die("function decl without '(' in %s: %s" % (header, decl[:8]))
        name_tok = toks[lp - 1] if lp >= 1 else None
        if name_tok is None or name_tok[0] != "id":
            die("function decl without name in %s: %s" % (header, decl[:8]))
        name = name_tok[1]
        if lp - 1 <= 0:
            die("function decl %s: no return type tokens (raw: %r)" % (name, toks[:8]))
        ret_type = self.parse_type_tokens(toks[:lp - 1], header)
        depth = 0
        rp = None
        for k in range(lp, len(toks)):
            if toks[k][0] == "punct" and toks[k][1] == "(":
                depth += 1
            elif toks[k][0] == "punct" and toks[k][1] == ")":
                depth -= 1
                if depth == 0:
                    rp = k
                    break
        if rp is None:
            die("function %s: unterminated params" % name)
        trailing = toks[rp + 1:]
        for t in trailing:
            if t[0] == "id" and t[1] not in ("const", "noexcept"):
                die("function %s: trailing tokens %r" % (name, trailing[:6]))
        args = self.parse_arg_list(toks[lp + 1:rp], header)
        if name == "ffxLoadFunctions":
            kind = "loader"
        elif saw_ffx_static:
            kind = "cpu"
        elif saw_export:
            kind = "unified" if header.startswith("api/include/") else "hostapi"
        elif saw_static or saw_inline:
            kind = "inline"
        else:
            kind = "hostapi"
        fn = {
            "name": name,
            "component": component,
            "header": header,
            "kind": kind,
            "ret": ret_type,
            "args": args,
            "has_body": has_body,
        }
        self.functions.append(fn)
        self.declared_in[name] = (component, header)


# ---------------------------------------------------------------------------
# Rendering helpers
# ---------------------------------------------------------------------------

def render_type(tref):
    if isinstance(tref, str):
        return tref
    prefix = "const " if getattr(tref, "is_const", False) else ""
    if tref.kind == "prim":
        return prefix + tref.name
    if tref.kind == "ptr":
        return render_type(tref.inner) + " *"
    if tref.kind == "array":
        return render_type(tref.inner) + " *"
    if tref.kind == "funptr":
        args = ", ".join(render_arg(a) for a in (tref.args or []))
        return "%s (*)(%s)" % (render_type(tref.ret), args)
    if tref.kind in ("struct", "union", "enum", "unresolved"):
        return prefix + tref.name
    die("cannot render %r" % (tref,))


def render_arg(a):
    t = a["type"]
    if t == "...":
        return "..."
    if isinstance(t, TypeRef) and t.kind == "funptr":
        return render_type(t)
    if isinstance(t, TypeRef) and t.kind not in ("ptr", "array") and getattr(t, "is_const", False):
        # top-level const on a by-value parameter is adapted away in the
        # function type; render without it
        t = TypeRef(t.kind, name=t.name, inner=t.inner, array_len=t.array_len,
                    args=t.args, ret=t.ret, is_const=False)
    return render_type(t)


def ret_to_xiom(ret):
    if ret == "void":
        return "Unit"
    if ret in ("ffxReturnCode_t", "FfxErrorCode", "uint32_t", "int32_t", "bool", "FfxVersionNumber"):
        return "Int32"
    if ret == "float":
        return "Float"
    if ret.endswith("*"):
        return "Int"
    die("cannot map return type %r to XIOM" % ret)


# ---------------------------------------------------------------------------
# Main generation
# ---------------------------------------------------------------------------

def run(check_mode=False, pin_only=False):
    p = Parser()
    all_files = [(c, h, False) for (c, h) in SUPPORT_SET] + [(c, h, True) for (c, h) in SURFACE_SET]
    texts = {}
    for comp, rel, is_surface in all_files:
        texts[rel] = read_vendor(rel)

    # converge the conditional evaluation across files (2 passes)
    filtered = {}
    for _ in range(2):
        filtered = {}
        for comp, rel, is_surface in all_files:
            filtered[rel] = p.preprocess(texts[rel], origin=rel)
    p.evaluate_integer_defines()

    for comp, rel, is_surface in all_files:
        p.parse_text(comp, rel, filtered[rel], collect_functions=is_surface)

    # resolve layouts (lazy refs must now resolve)
    for name in p.struct_order:
        st = p.types.get(name)
        if isinstance(st, StructInfo):
            st.resolve(p.types)
    for name, entry in list(p.types.items()):
        if isinstance(entry, TypeRef) and entry.kind == "unresolved":
            if name not in p.types or isinstance(p.types.get(name), TypeRef):
                # outer alias to an unresolved struct: only a problem if used
                pass
    # check unresolved structs used by value via a resolution sweep
    for name in p.struct_order:
        st = p.types.get(name)
        if isinstance(st, StructInfo):
            for fname, ftype in st.fields:
                if isinstance(ftype, TypeRef) and ftype.kind in ("unresolved", "struct", "union"):
                    if ftype.name not in p.types and ftype.name not in p.opaque_names:
                        die("struct %s field %s references unknown type %s" % (st.name, fname, ftype.name))

    seen = set()
    funcs = []
    for fn in p.functions:
        key = (fn["name"], fn["header"], len(fn["args"]))
        if key in seen:
            continue
        seen.add(key)
        funcs.append(fn)
    for fn in funcs:
        fn["callable"] = fn["kind"] in ("unified", "loader", "cpu")
        fn["runtime_export"] = fn["kind"] in ("unified",)

    blobs = []
    for bname, bkind, brel in BLOBS:
        text = read_vendor(brel)
        m = re.search(r"const unsigned char\s+(\w+)\s*\[\]\s*=\s*\{(.*?)\}\s*;", text, re.S)
        if not m:
            die("cannot extract payload from blob %s" % brel)
        hexbytes = re.findall(r"0[xX]([0-9a-fA-F]{1,2})", m.group(2))
        data = bytes(int(h, 16) for h in hexbytes)
        blobs.append({
            "name": bname,
            "kind": bkind,
            "file": brel,
            "sym": m.group(1),
            "size": len(data),
            "sha256": hashlib.sha256(data).hexdigest().lower(),
        })

    outputs = {}
    outputs["src/ffx_gen_types.xi"] = emit_types(p, blobs)
    outputs["src/ffx_gen_structs.xi"] = emit_structs(p)
    outputs["src/ffx_gen_surface.xi"] = emit_surface(p, funcs)
    outputs["src/ffx_gen_abi.cpp"] = emit_abi(p, funcs)
    outputs["docs/COVERAGE.md"] = emit_coverage(p, funcs, blobs)
    outputs["docs/gen_manifest.json"] = emit_manifest(p, funcs, blobs)
    outputs["vendor/fidelityfx/PIN.md"] = emit_pin()

    if pin_only:
        outputs = {k: v for k, v in outputs.items() if k.endswith("PIN.md")}

    failures = []
    for rel, content in sorted(outputs.items()):
        path = os.path.join(PKG, rel)
        if check_mode:
            if not os.path.exists(path):
                failures.append(rel + ": missing")
                continue
            with open(path, "r", encoding="utf-8") as f:
                have = f.read()
            if have.replace("\r\n", "\n") != content.replace("\r\n", "\n"):
                failures.append(rel + ": drift")
            continue
        d = os.path.dirname(path)
        if d and not os.path.isdir(d):
            os.makedirs(d)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
        print("wrote " + rel)

    if check_mode:
        if failures:
            for f in failures:
                print("CHECK FAIL: " + f, file=sys.stderr)
            sys.exit(1)
        print("gen_fidelityfx --check: OK (%d files)" % len(outputs))
        return

    print("surface records: %d (%d callable, %d metadata)" % (
        len(funcs),
        sum(1 for f in funcs if f["callable"]),
        sum(1 for f in funcs if not f["callable"])))
    print("structs: %d, integer defines: %d, enumerators: %d, blobs: %d" % (
        len(real_structs(p)),
        len(p.integer_defines), len(p.enum_values), len(blobs)))


def emit_header(comment):
    return ("// GENERATED by tools/gen_fidelityfx.py -- do not edit by hand.\n"
            "// %s\n"
            "// Source pin: FidelityFX-SDK %s (%s), AMD FSR SDK 2.3.0 \"Redstone\".\n"
            "// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors\n"
            "// SPDX-License-Identifier: MIT OR Apache-2.0\n\n" % (comment, PIN["tag"], PIN["commit"][:8]))


COMPILED_ORIGINS = set(ABI_INCLUDE_ORDER) | set(h for _, h in SUPPORT_SET)


def compiled_origin(header):
    return header in COMPILED_ORIGINS


def real_structs(p):
    """Structs that exist as named types in the compiled headers. Anonymous
    inline union/struct members are synthetic layout helpers: their promoted
    members are covered through the parent's offsets."""
    out = []
    for n in p.struct_order:
        st = p.types.get(n)
        if isinstance(st, StructInfo) and not st.name.startswith("<") and "::" not in st.name:
            out.append(st)
    return out


def offset_entries(st, types):
    """(name, offset, c_expr) for every addressable member of `st`:
    promoted anonymous-union members plus one nested level into by-value
    struct/union fields (e.g. `header_type` -> offsetof(X, header) +
    offsetof(ffxApiHeader, type))."""
    out = []
    seen = set()
    for name in sorted(st.field_offsets().keys()):
        out.append((name, st.field_offsets()[name], "offsetof(%s, %s)" % (st.name, name)))
        seen.add(name)
    for fname, ftype in st.fields:
        if not fname:
            continue
        if not (isinstance(ftype, TypeRef) and ftype.kind in ("struct", "union", "unresolved")):
            continue
        inner = types.get(ftype.name)
        if not isinstance(inner, StructInfo):
            continue
        base = st.field_offsets().get(fname)
        if base is None:
            continue
        for gname in sorted(inner.field_offsets().keys()):
            path = fname + "_" + gname
            if path in seen:
                die("offset path collision in %s: %s" % (st.name, path))
            seen.add(path)
            out.append((path, base + inner.field_offsets()[gname],
                        "offsetof(%s, %s) + offsetof(%s, %s)" % (st.name, fname, inner.name, gname)))
    return out


def emit_types(p, blobs):
    out = io.StringIO()
    out.write(emit_header("Enum values and integer constants parsed from the pinned headers."))
    out.write("module xiom.fidelityfx.gen_types\n\n")
    out.write("// ---- #define integer constants ----\n")
    for name in sorted(p.integer_defines.keys()):
        out.write("pub const %s: Int = %d;\n" % (name, p.integer_defines[name]))
    out.write("\n// ---- enumerators ----\n")
    for name in sorted(p.enum_values.keys()):
        out.write("pub const %s: Int = %d;\n" % (name, p.enum_values[name]))
    out.write("\n// ---- vendored compiled shader blob payloads (see vendor/fidelityfx/PIN.md) ----\n")
    for i, b in enumerate(blobs):
        out.write('pub const FFX_BLOB_%d_NAME: Str = "%s";\n' % (i, b["name"]))
        out.write('pub const FFX_BLOB_%d_KIND: Str = "%s";\n' % (i, b["kind"]))
        out.write('pub const FFX_BLOB_%d_FILE: Str = "%s";\n' % (i, b["file"]))
        out.write("pub const FFX_BLOB_%d_SIZE: Int = %d;\n" % (i, b["size"]))
        out.write('pub const FFX_BLOB_%d_SHA256: Str = "%s";\n' % (i, b["sha256"]))
    out.write("pub const FFX_BLOB_COUNT: Int = %d;\n" % len(blobs))
    return out.getvalue()


def emit_structs(p):
    out = io.StringIO()
    out.write(emit_header("Struct sizes and field offsets computed from the pinned headers; verified against the compiler by src/ffx_gen_abi.cpp."))
    out.write("module xiom.fidelityfx.gen_structs\n\n")
    all_structs = real_structs(p)
    structs = [s for s in all_structs if s.header in ABI_INCLUDE_ORDER]
    for st in all_structs:
        out.write("// %s %s (%s), size %d, align %d%s\n" % (
            st.kind, st.name, st.header, st.size, st.align,
            "" if st.header in ABI_INCLUDE_ORDER else " [parse-only: dx12 headers not compiled]"))
        out.write("pub const FFX_SIZEOF_%s: Int = %d;\n" % (st.name, st.size))
        for ename, eoff, _expr in offset_entries(st, p.types):
            out.write("pub const FFX_OFFSET_%s_%s: Int = %d;\n" % (st.name, ename, eoff))
        out.write("\n")
    out.write("pub fn gen_size_count() -> Int\n  requires: true\n{\n  return %d;\n}\n\n" % len(structs))
    out.write("pub fn gen_size_name(i: Int) -> Str\n  requires: i >= 0\n{\n")
    for i, st in enumerate(structs):
        out.write('  if i == %d { return "%s"; }\n' % (i, st.name))
    out.write('  return "";\n}\n\n')
    out.write("pub fn gen_size_value(i: Int) -> Int\n  requires: i >= 0\n{\n")
    for i, st in enumerate(structs):
        out.write("  if i == %d { return %d; }\n" % (i, st.size))
    out.write("  return -1;\n}\n\n")
    pairs = []
    for st in structs:
        for ename, eoff, _expr in offset_entries(st, p.types):
            pairs.append((st.name, ename, eoff))
    out.write("pub fn gen_off_count() -> Int\n  requires: true\n{\n  return %d;\n}\n\n" % len(pairs))
    out.write("pub fn gen_off_struct(i: Int) -> Str\n  requires: i >= 0\n{\n")
    for i, (sn, fn_, _) in enumerate(pairs):
        out.write('  if i == %d { return "%s"; }\n' % (i, sn))
    out.write('  return "";\n}\n\n')
    out.write("pub fn gen_off_field(i: Int) -> Str\n  requires: i >= 0\n{\n")
    for i, (sn, fn_, _) in enumerate(pairs):
        out.write('  if i == %d { return "%s"; }\n' % (i, fn_))
    out.write('  return "";\n}\n\n')
    out.write("pub fn gen_off_value(i: Int) -> Int\n  requires: i >= 0\n{\n")
    for i, (sn, fn_, off) in enumerate(pairs):
        out.write("  if i == %d { return %d; }\n" % (i, off))
    out.write("  return -1;\n}\n")
    return out.getvalue()


def emit_surface(p, funcs):
    out = io.StringIO()
    out.write(emit_header("Declared C surface records (function census) from the pinned headers."))
    out.write("module xiom.fidelityfx.gen_surface\n\n")
    out.write("pub fn surface_count() -> Int\n  requires: true\n{\n  return %d;\n}\n\n" % len(funcs))
    for table, key in (("surface_name", "name"), ("surface_component", "component"), ("surface_kind", "kind")):
        out.write("pub fn %s(i: Int) -> Str\n  requires: i >= 0\n{\n" % table)
        for i, fn in enumerate(funcs):
            out.write('  if i == %d { return "%s"; }\n' % (i, fn[key]))
        out.write('  return "";\n}\n\n')
    out.write("pub fn surface_header(i: Int) -> Str\n  requires: i >= 0\n{\n")
    for i, fn in enumerate(funcs):
        out.write('  if i == %d { return "%s"; }\n' % (i, fn["header"]))
    out.write('  return "";\n}\n\n')
    out.write("pub fn surface_signature(i: Int) -> Str\n  requires: i >= 0\n{\n")
    for i, fn in enumerate(funcs):
        sig = render_type(fn["ret"]) + " " + fn["name"] + "(" + ", ".join(render_arg(a) for a in fn["args"]) + ")"
        out.write('  if i == %d { return "%s"; }\n' % (i, sig.replace('"', "'")))
    out.write('  return "";\n}\n\n')
    out.write("pub fn surface_callable(i: Int) -> Bool\n  requires: i >= 0\n{\n")
    for i, fn in enumerate(funcs):
        out.write("  if i == %d { return %s; }\n" % (i, "true" if fn["callable"] else "false"))
    out.write("  return false;\n}\n\n")
    out.write("pub fn surface_runtime_export(i: Int) -> Bool\n  requires: i >= 0\n{\n")
    for i, fn in enumerate(funcs):
        out.write("  if i == %d { return %s; }\n" % (i, "true" if fn["runtime_export"] else "false"))
    out.write("  return false;\n}\n\n")
    comps = []
    for fn in funcs:
        if fn["component"] not in comps:
            comps.append(fn["component"])
    out.write("pub fn component_count() -> Int\n  requires: true\n{\n  return %d;\n}\n\n" % len(comps))
    for table, mode in (("component_name", "name"), ("component_declared", "declared"),
                        ("component_callable", "callable"), ("component_metadata", "meta")):
        if mode == "name":
            out.write("pub fn %s(i: Int) -> Str\n  requires: i >= 0\n{\n" % table)
            for i, c in enumerate(comps):
                out.write('  if i == %d { return "%s"; }\n' % (i, c))
            out.write('  return "";\n}\n\n')
        else:
            out.write("pub fn %s(i: Int) -> Int\n  requires: i >= 0\n{\n" % table)
            for i, c in enumerate(comps):
                if mode == "declared":
                    v = sum(1 for f in funcs if f["component"] == c)
                elif mode == "callable":
                    v = sum(1 for f in funcs if f["component"] == c and f["callable"])
                else:
                    v = sum(1 for f in funcs if f["component"] == c and not f["callable"])
                out.write("  if i == %d { return %d; }\n" % (i, v))
            out.write("  return -1;\n}\n\n")
    return out.getvalue()


def emit_abi(p, funcs):
    out = io.StringIO()
    out.write("/* GENERATED by tools/gen_fidelityfx.py -- do not edit by hand.\n"
              " *\n"
              " * ABI oracle: compiles the VENDORED headers and pins\n"
              " *  - every parsed struct size/field offset (static_assert),\n"
              " *  - every parsed enumerator (static_assert),\n"
              " *  - every declared function signature (unevaluated decltype cast).\n"
              " * Runtime exports (ffx_gen_*) hand the compiler-computed values to\n"
              " * the XIOM suite for the looped ABI comparison.\n"
              " */\n")
    out.write("#include <stdint.h>\n#include <cstddef>\n#include <type_traits>\n\n")
    out.write("#if defined(__clang__)\n#pragma clang diagnostic ignored \"-Wdeprecated-declarations\"\n#pragma clang diagnostic ignored \"-Wmacro-redefined\"\n#endif\n\n")
    for rel in ABI_INCLUDE_ORDER:
        out.write('#include "../vendor/fidelityfx/%s"\n' % rel)
    out.write("\n")

    structs = [s for s in real_structs(p) if s.header in ABI_INCLUDE_ORDER]
    for st in structs:
        out.write('static_assert(sizeof(%s) == %d, "size %s");\n' % (st.name, st.size, st.name))
        for ename, eoff, expr in offset_entries(st, p.types):
            out.write('static_assert((%s) == %d, "off %s.%s");\n' % (expr, eoff, st.name, ename))
    out.write("\n")
    for name in sorted(p.enum_values.keys()):
        if not compiled_origin(p.enum_origin.get(name, "")):
            continue
        out.write('static_assert((int)(%s) == %d, "enum %s");\n' % (name, p.enum_values[name], name))
    out.write("\n")
    from collections import Counter as _Counter
    name_counts = _Counter(f["name"] for f in funcs)
    for fn in funcs:
        if fn["header"] not in ABI_INCLUDE_ORDER:
            out.write("// sig %s: parse-only header (%s), not compiled into the oracle\n" % (fn["name"], fn["header"]))
            continue
        ret = render_type(fn["ret"])
        args = ", ".join(render_arg(a) for a in fn["args"])
        if fn["kind"] == "loader":
            sig = "void (*)(ffxFunctions *, void *)"
        else:
            sig = "%s (*)(%s)" % (ret, args)
        if name_counts[fn["name"]] > 1 and fn["kind"] != "loader":
            # overloaded name: pin through an exact-match static_cast
            out.write("static_assert(std::is_same_v<decltype(static_cast<%s>(&%s)), %s>, \"sig %s\");\n" % (
                sig, fn["name"], sig, fn["name"]))
        else:
            out.write("static_assert(std::is_same_v<decltype(&%s), %s>, \"sig %s\");\n" % (
                fn["name"], sig, fn["name"]))
    out.write("\n// ---- runtime probe (compiler-computed values) ----\n")
    out.write('extern "C" int64_t ffx_gen_size_count()\n{\n  return %d;\n}\n\n' % len(structs))
    out.write('extern "C" const char* ffx_gen_size_name(int64_t i)\n{\n  switch (i) {\n')
    for i, st in enumerate(structs):
        out.write('    case %d: return "%s";\n' % (i, st.name))
    out.write('    default: return "";\n  }\n}\n\n')
    out.write('extern "C" int64_t ffx_gen_size_value(int64_t i)\n{\n  switch (i) {\n')
    for i, st in enumerate(structs):
        out.write("    case %d: return (int64_t)sizeof(%s);\n" % (i, st.name))
    out.write("    default: return -1;\n  }\n}\n\n")
    pairs = []
    for st in structs:
        for ename, _eoff, expr in offset_entries(st, p.types):
            pairs.append((st.name, ename, expr))
    out.write('extern "C" int64_t ffx_gen_off_count()\n{\n  return %d;\n}\n\n' % len(pairs))
    out.write('extern "C" const char* ffx_gen_off_struct(int64_t i)\n{\n  switch (i) {\n')
    for i, (sn, fnm, _expr) in enumerate(pairs):
        out.write('    case %d: return "%s";\n' % (i, sn))
    out.write('    default: return "";\n  }\n}\n\n')
    out.write('extern "C" const char* ffx_gen_off_field(int64_t i)\n{\n  switch (i) {\n')
    for i, (sn, fnm, _expr) in enumerate(pairs):
        out.write('    case %d: return "%s";\n' % (i, fnm))
    out.write('    default: return "";\n  }\n}\n\n')
    out.write('extern "C" int64_t ffx_gen_off_value(int64_t i)\n{\n  switch (i) {\n')
    for i, (sn, fnm, expr) in enumerate(pairs):
        out.write("    case %d: return (int64_t)(%s);\n" % (i, expr))
    out.write("    default: return -1;\n  }\n}\n")
    return out.getvalue()


def emit_coverage(p, funcs, blobs):
    lines = []
    lines.append("# COVERAGE: xiom.fidelityfx")
    lines.append("")
    lines.append("GENERATED by `tools/gen_fidelityfx.py` -- do not edit by hand.")
    lines.append("")
    lines.append("Pinned upstream: FidelityFX-SDK `%s` (`%s`, %s)." % (PIN["tag"], PIN["commit"], PIN["date"]))
    lines.append("")
    lines.append("## Declared C surface (per component)")
    lines.append("")
    lines.append("| Component | Declared fns | Callable | Metadata (typed runtime classification) | Skips |")
    lines.append("|---|---|---|---|---|")
    comps = []
    for fn in funcs:
        if fn["component"] not in comps:
            comps.append(fn["component"])
    total = 0
    for c in comps:
        declared = sum(1 for f in funcs if f["component"] == c)
        callable_n = sum(1 for f in funcs if f["component"] == c and f["callable"])
        total += declared
        lines.append("| %s | %d | %d | %d | 0 |" % (c, declared, callable_n, declared - callable_n))
    lines.append("| **total** | **%d** | **%d** | **%d** | **0** |" % (
        total,
        sum(1 for f in funcs if f["callable"]),
        sum(1 for f in funcs if not f["callable"])))
    lines.append("")
    lines.append("## Function census (%d records)" % len(funcs))
    lines.append("")
    lines.append("| # | Function | Component | Kind | Header |")
    lines.append("|---|---|---|---|---|")
    for i, fn in enumerate(funcs):
        lines.append("| %d | `%s` | %s | %s | %s |" % (i, fn["name"], fn["component"], fn["kind"], fn["header"]))
    lines.append("")
    lines.append("## Vendored compiled shader blobs (%d)" % len(blobs))
    lines.append("")
    lines.append("| # | Blob | Kind | Payload bytes | SHA256 |")
    lines.append("|---|---|---|---|---|")
    for i, b in enumerate(blobs):
        lines.append("| %d | `%s` | %s | %d | `%s` |" % (i, b["name"], b["kind"], b["size"], b["sha256"]))
    lines.append("")
    lines.append("## Notes")
    lines.append("")
    lines.append("- `callable` = the binding executes the function on this host (bridge-compiled CPU")
    lines.append("  path, runtime-resolved unified API when a signed effect DLL is present, or the")
    lines.append("  header-inline loader helper).")
    lines.append("- `metadata` = source-level declaration bound as an introspectable record with a")
    lines.append("  deterministic typed runtime classification: the signed 2.3.0 binaries export the")
    lines.append("  provider-based unified API only, while the legacy host APIs are compiled into")
    lines.append("  consumers from source. The binding resolves each name at runtime and reports the")
    lines.append("  typed result; nothing is silently dropped (skips = 0).")
    lines.append("- CAS and LPM are absent from the pinned headers (the 2.x SDK moved past the")
    lines.append("  image-processing kit); they are out of the declared surface by construction.")
    lines.append("- The dx12 backend descriptor headers (`api/include/dx12/`, `framegeneration/")
    lines.append("  include/dx12/`) are parsed for metadata but not compiled into the ABI oracle")
    lines.append("  (they need the DirectX-Headers SDK); their layouts use pointer-only external")
    lines.append("  types, so the computed offsets are exact.")
    lines.append("")
    return "\n".join(lines)


def emit_manifest(p, funcs, blobs):
    structs = real_structs(p)
    man = {
        "pin": PIN,
        "counts": {
            "structs": len(structs),
            "integer_defines": len(p.integer_defines),
            "enumerators": len(p.enum_values),
            "functions": len(funcs),
            "blobs": len(blobs),
        },
        "functions": [
            {
                "name": f["name"], "component": f["component"], "kind": f["kind"],
                "header": f["header"], "callable": f["callable"],
                "ret": render_type(f["ret"]),
                "args": [render_arg(a) for a in f["args"]],
                "signature": render_type(f["ret"]) + " " + f["name"] + "(" + ", ".join(render_arg(a) for a in f["args"]) + ")",
            } for f in funcs
        ],
        "structs": [
            {"name": s.name, "kind": s.kind, "header": s.header, "size": s.size,
             "fields": [{"name": en, "offset": eo} for en, eo, _ex in offset_entries(s, p.types)]}
            for s in structs
        ],
        "blobs": blobs,
    }
    return json.dumps(man, indent=2, sort_keys=True) + "\n"


def emit_pin():
    rows = []
    for root, dirs, files in os.walk(VENDOR_DIR):
        dirs.sort()
        for fn in sorted(files):
            path = os.path.join(root, fn)
            rel = os.path.relpath(path, VENDOR_DIR).replace("\\", "/")
            if rel == "PIN.md":
                continue
            with open(path, "rb") as f:
                data = f.read()
            rows.append((rel, len(data), hashlib.sha256(data).hexdigest().upper()))
    out = []
    out.append("# PIN: vendored FidelityFX-SDK surface")
    out.append("")
    out.append("Copied **verbatim** (byte-exact) from the pinned upstream clone at")
    out.append("`E:\\repos\\FidelityFX-SDK`; nothing was edited after copying.")
    out.append("")
    out.append("| Field | Value |")
    out.append("|---|---|")
    out.append("| Upstream | %s |" % PIN["upstream"])
    out.append("| Tag | `%s` |" % PIN["tag"])
    out.append("| Commit | `%s` |" % PIN["commit"])
    out.append("| Commit date | %s |" % PIN["date"])
    out.append("| Release name | %s |" % PIN["sdk_name"])
    out.append("| License | MIT for every vendored file (each is listed by path in `vendor/fidelityfx/LICENSE.md`; AMD's binary-redistribution default applies to non-listed SDK bodies, which are NOT vendored here) |")
    out.append("| Files | %d |" % len(rows))
    out.append("")
    out.append("## Per-file SHA256 (vendor tree)")
    out.append("")
    out.append("| File | Bytes | SHA256 |")
    out.append("|---|---|---|")
    for rel, size, sha in rows:
        out.append("| `%s` | %d | `%s` |" % (rel, size, sha))
    out.append("")
    out.append("Re-carve: fetch the new release tag into `E:\\repos\\FidelityFX-SDK`, re-copy the")
    out.append("same file set byte-exact, re-run `python tools/gen_fidelityfx.py`, review the diff")
    out.append("(counts, offsets, blob hashes), re-run the suite x2, re-record `STATUS.json`.")
    out.append("")
    return "\n".join(out)


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--check" in args:
        run(check_mode=True)
    elif "--pin" in args:
        run(pin_only=True)
    else:
        run()
