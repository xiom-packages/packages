#!/usr/bin/env python3
# XIOM -- xiom.sdl3 SDK100 surface generator.
#
# Parses the SDL3 public headers shipped with the pinned Vulkan SDK and the
# export table of the matching SDL3.dll, then emits:
#
#   src/sdl3_full_<family>[_N].xi   family-split modules: constants + symbol
#                                   struct + resolver + typed wrapper per
#                                   declared-and-exported function
#   src/sdl3_full_names.xi          oracle name lists (declared, exported,
#                                   declared-not-exported, export-only)
#   src/sdl3_full_registry.xi       one load+close call per module (wiring
#                                   proof used by tests/test_full_surface.xi)
#   docs/gen_manifest.json          counts, hashes, skipped-constant ledger,
#                                   device-surface pin (0.19.0)
#
# Oracle definition (owner policy docs/UPSTREAM-FIRST.md + SDK100 plan):
#   target = functions DECLARED in the shipped SDL3 headers that SDL3.dll
#            EXPORTS (declared-not-exported and export-only names are listed,
#            not bound).
#
# ABI notes (bindings-lane findings B-11..B-20):
#   - narrow integer returns are declared as Int32 in the fn cast and masked/
#     sign-extended in XIOM (B-19: declared widths are honored by m263+);
#   - bool returns are declared UInt8; bool params are converted to UInt8;
#   - float/double params are declared Float32/Float64; float/double RETURNS
#     are wrapped as Float64 but carry the B-12 caveat (fp cast-call returns
#     are miscompiled on v0.64.3 -- do not trust the value);
#   - struct-by-value params/returns use the Win64 by-reference/sret shapes
#     (SDL_GUID / SDL_FColor are 16 bytes, i.e. passed as pointers);
#   - variadic functions are bound on their fixed parameter list only;
#   - no pointer arithmetic, no constants inside confined blocks, locals are
#     prefixed (`a1..`, `f`, `v_<param>`) per B-02/B-10/B-16/B-17.
#
# Usage:
#   python tools/gen_sdl3_full.py --sdk C:\VulkanSDK\1.4.350.0
#
# Deterministic: sorted inputs, stable ordering, LF newlines, no timestamps.

import argparse
import glob
import hashlib
import json
import os
import re
import struct
import sys

HEADER_RE = re.compile(r"SDL[A-Za-z0-9_]*\.h$")
EXCLUDED_DEFINE_HEADERS = {"SDL_oldnames.h"}
MAX_FUNCS_PER_MODULE = 64
LINE_WIDTH = 150

KEYWORDS = {
    "as", "break", "case", "const", "continue", "defer", "down", "else",
    "ensures", "enum", "extern", "false", "fn", "for", "if", "impl", "import",
    "in", "invariant", "is", "let", "loop", "match", "module", "move", "mut",
    "new", "not", "null", "or", "out", "package", "pub", "ref", "requires",
    "return", "self", "spawn", "struct", "trait", "true", "type", "unsafe",
    "until", "up", "use", "var", "while", "with", "yield", "lib", "f",
}

INT_BASES = {
    "char": ("int", True, 8),
    "signed char": ("int", True, 8),
    "unsigned char": ("int", False, 8),
    "short": ("int", True, 16),
    "short int": ("int", True, 16),
    "unsigned short": ("int", False, 16),
    "unsigned short int": ("int", False, 16),
    "int": ("int", True, 32),
    "unsigned": ("int", False, 32),
    "unsigned int": ("int", False, 32),
    "long": ("int", True, 64),
    "long int": ("int", True, 64),
    "unsigned long": ("int", False, 64),
    "long long": ("int", True, 64),
    "unsigned long long": ("int", False, 64),
    "int8_t": ("int", True, 8),
    "uint8_t": ("int", False, 8),
    "int16_t": ("int", True, 16),
    "uint16_t": ("int", False, 16),
    "int32_t": ("int", True, 32),
    "uint32_t": ("int", False, 32),
    "int64_t": ("int", True, 64),
    "uint64_t": ("int", False, 64),
    "size_t": ("int", False, 64),
    "intptr_t": ("int", True, 64),
    "uintptr_t": ("int", False, 64),
    "ptrdiff_t": ("int", True, 64),
    "Uint8": ("int", False, 8),
    "Uint16": ("int", False, 16),
    "Uint32": ("int", False, 32),
    "Uint64": ("int", False, 64),
    "Sint8": ("int", True, 8),
    "Sint16": ("int", True, 16),
    "Sint32": ("int", True, 32),
    "Sint64": ("int", True, 64),
    "float": ("fp", True, 32),
    "double": ("fp", True, 64),
    "bool": ("bool", True, 8),
    "void": ("void", True, 0),
    "SDL_Time": ("int", True, 64),
}

BOOL_NAMES = {"bool"}
IDENT_CAST_RE = r"[A-Za-z_][A-Za-z0-9_]*"


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    return text


def norm(text):
    return " ".join(text.split())


def literal_int(expr):
    try:
        return int(re.sub(r"[uUlL]+$", "", expr.strip()), 0)
    except ValueError:
        return None


def snake(name):
    s = name[4:] if name.startswith("SDL_") else name
    out = []
    for i, ch in enumerate(s):
        if ch.isupper():
            prev = s[i - 1] if i else ""
            nxt = s[i + 1] if i + 1 < len(s) else ""
            if i and (prev.islower() or prev.isdigit() or (prev.isupper() and nxt.islower())):
                out.append("_")
            out.append(ch.lower())
        else:
            out.append(ch)
    return "".join(out)


def pascal(name):
    parts = re.split(r"[_]+", name)
    return "".join(p[:1].upper() + p[1:] for p in parts if p)


def pe_exports(path):
    with open(path, "rb") as fh:
        data = fh.read()
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    if data[e_lfanew:e_lfanew + 4] != b"PE\0\0":
        raise SystemExit("not a PE file: %s" % path)
    coff = e_lfanew + 4
    nsec = struct.unpack_from("<H", data, coff + 2)[0]
    opt_size = struct.unpack_from("<H", data, coff + 16)[0]
    opt = coff + 20
    magic = struct.unpack_from("<H", data, opt)[0]
    dd_off = opt + (112 if magic == 0x20B else 96)
    exp_rva, exp_size = struct.unpack_from("<II", data, dd_off)
    sec = opt + opt_size
    sections = []
    for i in range(nsec):
        off = sec + i * 40
        vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", data, off + 8)
        sections.append((vaddr, vsize, rawptr, rawsize))

    def rva2off(rva):
        for vaddr, vsize, rawptr, rawsize in sections:
            if vaddr <= rva < vaddr + max(vsize, rawsize):
                return rawptr + (rva - vaddr)
        raise SystemExit("RVA not mapped: 0x%x" % rva)

    exp_off = rva2off(exp_rva)
    n_names = struct.unpack_from("<I", data, exp_off + 24)[0]
    names_rva = struct.unpack_from("<I", data, exp_off + 32)[0]
    names_off = rva2off(names_rva)
    out = []
    for i in range(n_names):
        nrva = struct.unpack_from("<I", data, names_off + i * 4)[0]
        noff = rva2off(nrva)
        end = data.index(b"\0", noff)
        out.append(data[noff:end].decode("ascii", "replace"))
    return out


# ---------------------------------------------------------------------------
# C integer expression evaluator (enums + object-like defines)
# ---------------------------------------------------------------------------

class Unresolved(Exception):
    pass


TOKEN_RE = re.compile(
    r"\s*(0[xX][0-9a-fA-F]+[uUlL]*|\d+[uUlL]*|'(\\.|[^'\\])'|"
    r"[A-Za-z_][A-Za-z0-9_]*|<<|>>|[()+\-*/%&|^~])")


def tokenize(expr):
    pos = 0
    toks = []
    while pos < len(expr):
        m = TOKEN_RE.match(expr, pos)
        if not m:
            if expr[pos:].strip() == "":
                break
            raise Unresolved("bad token at %r" % expr[pos:pos + 20])
        toks.append(m.group(1))
        pos = m.end()
    return toks


class IntParser:
    def __init__(self, toks, lookup, is_type):
        self.toks = toks
        self.i = 0
        self.lookup = lookup
        self.is_type = is_type

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else None

    def take(self):
        t = self.peek()
        self.i += 1
        return t

    def parse(self):
        v = self.binary(0)
        if self.peek() is not None:
            raise Unresolved("trailing tokens %r" % self.toks[self.i:])
        return v

    LEVELS = [("|",), ("^",), ("&",), ("<<", ">>"), ("+", "-"), ("*", "/", "%")]

    def binary(self, level):
        if level >= len(self.LEVELS):
            return self.unary()
        ops = self.LEVELS[level]
        left = self.binary(level + 1)
        while self.peek() in ops:
            op = self.take()
            right = self.binary(level + 1)
            if op == "|":
                left = left | right
            elif op == "^":
                left = left ^ right
            elif op == "&":
                left = left & right
            elif op == "<<":
                left = left << right
            elif op == ">>":
                left = left >> right
            elif op == "+":
                left = left + right
            elif op == "-":
                left = left - right
            elif op == "*":
                left = left * right
            elif op == "/":
                left = left // right if left >= 0 else -((-left) // right)
            elif op == "%":
                left = left % right
        return left

    def unary(self):
        t = self.peek()
        if t == "-":
            self.take()
            return -self.unary()
        if t == "+":
            self.take()
            return self.unary()
        if t == "~":
            self.take()
            return ~self.unary()
        return self.primary()

    def primary(self):
        t = self.take()
        if t is None:
            raise Unresolved("missing operand")
        if t == "(":
            # cast?
            if self.peek() and self.is_type(self.peek()):
                save = self.i
                typename = self.take()
                # multi-word base types
                while self.peek() and self.peek() not in (")", "(", "[") and \
                        not re.match(r"^[()+\-*/%&|^~]", self.peek()) and \
                        self.peek() not in ("*",):
                    if self.is_type(self.peek()):
                        typename = typename + " " + self.take()
                    else:
                        break
                if self.peek() == ")":
                    self.take()
                    inner = self.binary(0)
                    return self.apply_cast(typename, inner)
                self.i = save
            v = self.binary(0)
            if self.take() != ")":
                raise Unresolved("missing )")
            return v
        if t.startswith("0x") or t.startswith("0X"):
            return int(re.sub(r"[uUlL]+$", "", t), 16)
        if t[0].isdigit():
            return int(re.sub(r"[uUlL]+$", "", t), 10)
        if t.startswith("'"):
            body = t[1:-1]
            if body.startswith("\\"):
                esc = {"n": 10, "t": 9, "r": 13, "0": 0, "\\": 92, "'": 39, '"': 34,
                       "a": 7, "b": 8, "f": 12, "v": 11}
                if body[1] in esc:
                    return esc[body[1]]
                if body[1] in "xX":
                    return int(body[2:], 16)
                return ord(body[1])
            return ord(body)
        if t in KEYWORD_INT_CONSTS:
            return KEYWORD_INT_CONSTS[t]
        val = self.lookup(t)
        if val is None:
            raise Unresolved("unknown symbol %s" % t)
        return val

    def apply_cast(self, typename, value):
        base = typename
        spec = None
        # masks: ((Uint32)-1) -> 4294967295; (Sint8)200 -> -56
        if base in INT_BASES:
            spec = INT_BASES[base]
        else:
            spec = self.cast_specs.get(base)
        if not spec:
            return value
        kind, signed, bits = spec
        if kind == "void" or bits == 0:
            return value
        mask = (1 << bits) - 1
        value = value & mask
        if signed and value >= (1 << (bits - 1)):
            value -= 1 << bits
        return value


KEYWORD_INT_CONSTS = {
    "true": 1, "false": 0, "NULL": 0,
    # win-x64 libc macro values referenced by SDL_* constants
    "SIZE_MAX": 0xFFFFFFFFFFFFFFFF, "INT_MAX": 0x7FFFFFFF,
    "INT_MIN": -0x80000000, "UINT_MAX": 0xFFFFFFFF,
}


class ConstantOracle:
    """Collects enum members and object-like defines, then resolves values.

    A name may be defined several times under #if/#else branches; each
    candidate is kept and the first candidate that evaluates wins (stable,
    deterministic across hosts).
    """

    def __init__(self, typedefs):
        self.typedefs = typedefs          # name -> kind tuple
        self.candidates = {}               # name -> [(kind, expr, source), ...]
        self.order = []                    # first-seen order
        self.sym = {}                      # resolved int values
        self.str_values = {}               # resolved string values
        self.float_values = {}             # resolved float values
        self.unresolved = []               # (name, source, reason)

    def scalar_spec(self, name):
        seen = set()
        while name in self.typedefs and name not in seen:
            seen.add(name)
            kind = self.typedefs[name]
            if kind[0] == "scalar":
                name = kind[1]
                if name in INT_BASES:
                    return INT_BASES[name]
            elif kind[0] == "enum":
                return ("int", False, 32)
            else:
                return None
        return INT_BASES.get(name)

    def is_type(self, tok):
        return self.scalar_spec(tok) is not None

    def add_int(self, name, expr, source):
        if name in self.sym or name in self.str_values:
            return False
        if name not in self.candidates:
            self.candidates[name] = []
            self.order.append(name)
        self.candidates[name].append(("int", expr, source))
        return True

    def add_str(self, name, value, source):
        if name in self.sym or name in self.str_values:
            return False
        if name not in self.candidates:
            self.candidates[name] = []
            self.order.append(name)
        if not any(k == "str" for k, _, _ in self.candidates[name]):
            self.candidates[name].append(("str", value, source))
        return True

    def resolve_all(self):
        pending = list(self.order)
        for _ in range(60):
            still = []
            progress = False
            for name in pending:
                done = False
                for kind, expr, source in self.candidates[name]:
                    if kind == "str":
                        self.str_values[name] = expr
                        done = True
                        break
                    if FLOAT_LITERAL_RE.match(expr):
                        self.float_values[name] = float(expr.rstrip("fF"))
                        done = True
                        break
                    if re.match(r"^SDL_[A-Za-z0-9_]+$", expr) and expr in self.str_values:
                        self.str_values[name] = self.str_values[expr]
                        done = True
                        break
                    try:
                        self.sym[name] = self.eval_expr(expr)
                        done = True
                        break
                    except Unresolved:
                        continue
                if done:
                    progress = True
                else:
                    still.append(name)
            pending = still
            if not pending or not progress:
                break
        for name in pending:
            kind, expr, source = self.candidates[name][0]
            self.unresolved.append((name, source, expr))

    def eval_expr(self, expr):
        expr = preprocess_macro_consts(expr)

        def lookup(nm):
            if nm in self.sym:
                return self.sym[nm]
            return None

        parser = IntParser(tokenize(expr), lookup, self.is_type)
        parser.cast_specs = self.__class__.CastSpecs(self)
        return parser.parse()

    class CastSpecs(object):
        def __init__(self, oracle):
            self.oracle = oracle

        def get(self, name, default=None):
            return self.oracle.scalar_spec(name)


MACRO_CONST_IDENT = re.compile(r"\b(SDL_UINT64_C|SDL_SINT64_C|SDL_INT64_C|SDL_UINT32_C|"
                               r"SDL_INT32_C|SDL_UINT16_C|SDL_INT16_C)\s*\(")
BUTTON_MASK_CALL = re.compile(r"\bSDL_BUTTON_MASK\s*\(([^()]*)\)")
BUTTON_CALL = re.compile(r"\bSDL_BUTTON\s*\(([^()]*)\)")
VERSIONNUM_CALL = re.compile(r"\bSDL_VERSIONNUM\s*\(([^,()]+),\s*([^,()]+),\s*([^,()]+)\)")
WINDOWPOS_UNDEF = re.compile(r"\bSDL_WINDOWPOS_UNDEFINED_DISPLAY\s*\(([^()]*)\)")
WINDOWPOS_CENTER = re.compile(r"\bSDL_WINDOWPOS_CENTERED_DISPLAY\s*\(([^()]*)\)")
FLOAT_LITERAL_RE = re.compile(
    r"^[+-]?((\d+\.\d*|\.\d+)([eE][+-]?\d+)?[fF]?|\d+[eE][+-]?\d+[fF]?|\d+[fF])$")


def preprocess_macro_consts(expr):
    # SDL_*_C(0x..) identity helpers for literals; a few SDL expression
    # macros that appear inside constant definitions.
    prev = None
    while prev != expr:
        prev = expr
        expr = MACRO_CONST_IDENT.sub("(", expr)
        expr = BUTTON_MASK_CALL.sub(r"(1 << ((\1)-1))", expr)
        expr = BUTTON_CALL.sub(r"(1 << ((\1)-1))", expr)
        expr = VERSIONNUM_CALL.sub(r"((\1) * 1000000 + (\2) * 1000 + (\3))", expr)
        expr = WINDOWPOS_UNDEF.sub(r"(0x1FFF0000 | (\1))", expr)
        expr = WINDOWPOS_CENTER.sub(r"(0x2FFF0000 | (\1))", expr)
    return expr


# ---------------------------------------------------------------------------
# Header parsing
# ---------------------------------------------------------------------------

def parse_typedefs(texts):
    typedefs = {}

    def put(name, kind):
        if name and name not in typedefs:
            typedefs[name] = kind

    for fname in sorted(texts):
        text = texts[fname]
        for m in re.finditer(
                r"typedef\s+[\w\s\*]+?\(\s*(?:SDLCALL\s+)?\*\s*(SDL_[A-Za-z0-9_]+)\s*\)\s*\([^;]*\)\s*;",
                text):
            put(m.group(1), ("fnptr",))
        # struct typedefs (named and anonymous)
        for m in re.finditer(r"typedef\s+struct\s*([A-Za-z0-9_]*)\s*\{", text):
            i = m.end() - 1
            depth = 0
            while i < len(text):
                if text[i] == "{":
                    depth += 1
                elif text[i] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            j = text.find(";", i)
            tail = norm(text[i + 1:j])
            nm = tail.split()[-1].rstrip("*").strip() if tail else ""
            nm = nm.replace("(", " ").replace(")", " ").split()[-1] if nm else nm
            if nm.startswith("SDL_"):
                put(nm, ("struct",))
        for m in re.finditer(r"typedef\s+struct\s+(SDL_[A-Za-z0-9_]+)\s+(SDL_[A-Za-z0-9_]+)\s*;", text):
            put(m.group(2), ("opaque",))
        for m in re.finditer(r"typedef\s+enum\s+[A-Za-z0-9_]*\s*\{", text):
            i = m.end() - 1
            depth = 0
            while i < len(text):
                if text[i] == "{":
                    depth += 1
                elif text[i] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            j = text.find(";", i)
            tail = norm(text[i + 1:j])
            if tail.startswith("SDL_"):
                put(tail, ("enum",))
        for m in re.finditer(r"typedef\s+enum\s+[A-Za-z0-9_]+\s+(SDL_[A-Za-z0-9_]+)\s*;", text):
            put(m.group(1), ("enum",))
        for m in re.finditer(
                r"typedef\s+(?!struct|enum|union)([A-Za-z_][A-Za-z0-9_ ]*?)\s+(SDL_[A-Za-z0-9_]+)\s*;", text):
            base = norm(m.group(1))
            name = m.group(2)
            if "(" not in base and "*" not in base:
                put(name, ("scalar", base))
    return typedefs


def parse_functions(texts):
    funcs = {}
    order = []
    sig_re = re.compile(r"extern\s+SDL_DECLSPEC\s+(.+?)\bSDLCALL\s+(SDL_[A-Za-z0-9_]+)\s*\(")
    for fname in sorted(texts):
        text = texts[fname]
        for m in sig_re.finditer(text):
            name = m.group(2)
            ret = norm(m.group(1))
            i = m.end()
            depth = 1
            while i < len(text) and depth > 0:
                if text[i] == "(":
                    depth += 1
                elif text[i] == ")":
                    depth -= 1
                i += 1
            params_src = text[m.end():i - 1]
            if name in funcs:
                continue
            funcs[name] = {"ret": ret, "params_src": norm(params_src), "file": fname}
            order.append(name)
    return order, funcs


def split_params(params_src):
    if norm(params_src) in ("", "void"):
        return []
    out = []
    depth = 0
    cur = ""
    for ch in params_src:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(norm(cur))
            cur = ""
        else:
            cur += ch
    if norm(cur):
        out.append(norm(cur))
    return out


def parse_enums(texts, oracle):
    for fname in sorted(texts):
        text = texts[fname]
        for m in re.finditer(r"typedef\s+enum\s+[A-Za-z0-9_]*\s*\{", text):
            i = m.end() - 1
            depth = 0
            while i < len(text):
                if text[i] == "{":
                    depth += 1
                elif text[i] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            body = text[m.end():i]
            body = re.sub(r"#\s*(ifdef|ifndef|if|else|elif|endif)[^\n]*", " ", body)
            prev_name = None
            prev_value = None
            for raw_member in split_params(body):
                member = norm(raw_member)
                if not member:
                    continue
                m2 = re.match(r"^(SDL_[A-Za-z0-9_]+)\s*(?:=\s*(.*))?$", member)
                if not m2:
                    continue
                name = m2.group(1)
                expr = norm(m2.group(2)) if m2.group(2) is not None else None
                if expr is None:
                    if prev_value is not None:
                        expr = str(prev_value + 1)
                    elif prev_name is not None:
                        expr = "%s + 1" % prev_name
                    else:
                        expr = "0"
                oracle.add_int(name, expr, fname)
                prev_name = name
                prev_value = literal_int(expr)


def parse_defines(texts, oracle):
    define_re = re.compile(r"^#define\s+(SDL_[A-Za-z0-9_]+)(\([^)]*\))?[^\S\n]*(.*)$")
    for fname in sorted(texts):
        if fname in EXCLUDED_DEFINE_HEADERS:
            continue
        text = texts[fname]
        text = re.sub(r"\\\s*\n", " ", text)
        for line in text.split("\n"):
            m = define_re.match(line)
            if not m:
                continue
            name, args, value = m.group(1), m.group(2), m.group(3).strip()
            if args or not value:
                continue
            if value.startswith("#") or "#else" in value or "#endif" in value:
                continue
            if value.startswith('"'):
                lit = match_string_literal(value)
                if lit is not None:
                    oracle.add_str(name, lit, fname)
                continue
            oracle.add_int(name, value, fname)


def match_string_literal(value):
    pos = 0
    out = []

    def skip_ws():
        nonlocal pos
        while pos < len(value) and value[pos].isspace():
            pos += 1

    while True:
        skip_ws()
        if pos >= len(value) or value[pos] != '"':
            break
        pos += 1
        buf = []
        while pos < len(value):
            ch = value[pos]
            if ch == "\\":
                nxt = value[pos + 1] if pos + 1 < len(value) else ""
                esc = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"',
                       "'": "'", "0": "\0", "a": "\a", "b": "\b", "f": "\f", "v": "\v"}
                if nxt in esc:
                    buf.append(esc[nxt])
                    pos += 2
                    continue
                if nxt in "xX":
                    j = pos + 2
                    hexs = ""
                    while j < len(value) and value[j] in "0123456789abcdefABCDEF":
                        hexs += value[j]
                        j += 1
                    if hexs:
                        buf.append(chr(int(hexs, 16) & 0xFF))
                        pos = j
                        continue
                buf.append(nxt)
                pos += 2
                continue
            if ch == '"':
                pos += 1
                break
            buf.append(ch)
            pos += 1
        else:
            return None
        out.append("".join(buf))
    trailing = value[pos:].strip()
    if not out or trailing:
        return None
    return "".join(out)


# ---------------------------------------------------------------------------
# Emission helpers
# ---------------------------------------------------------------------------

def xiom_escape(s):
    out = []
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        elif ord(ch) < 32:
            out.append("\\x%02x" % ord(ch))
        else:
            out.append(ch)
    return "".join(out)


def emit_int_const(value):
    if value < 0:
        return str(value)
    if value >= 1 << 63:
        return str(value - (1 << 64))
    return str(value)


class TypeMap:
    """Maps C types to (xiom param type, cast type, call expr builder)."""

    def __init__(self, typedefs, oracle):
        self.typedefs = typedefs
        self.oracle = oracle

    def resolve(self, ctype):
        ctype = norm(ctype)
        if ctype.endswith("*") or "*" in ctype:
            return ("ptr", ctype)
        return ("value", self.scalar_spec(ctype), ctype)

    def scalar_spec(self, ctype):
        name = re.sub(r"^const\s+", "", norm(ctype))
        seen = set()
        while name not in INT_BASES and name not in seen:
            seen.add(name)
            kind = self.typedefs.get(name)
            if not kind:
                return None
            if kind[0] == "scalar":
                name = kind[1]
            elif kind[0] == "enum":
                return ("int", False, 32)
            elif kind[0] == "fnptr":
                return ("int", False, 64)
            elif kind[0] == "struct":
                return ("struct", False, 0)
            else:
                return None
        return INT_BASES.get(name)


# ---------------------------------------------------------------------------
# Device-surface pin (0.19.0): Win64 layouts + symbol/constant annotations
# ---------------------------------------------------------------------------
# The hand-written root module (sdl3.xi) decodes pen/tablet events and encodes
# SDL_HapticEffect slots with byte-indexed reads/writes pinned to Win64
# offsets.  This audit recomputes every offset from the pinned header member
# lists (MSVC x64 natural alignment; struct size rounded up to the struct
# alignment) and fails generation when a re-pin moves a field, so the 100%
# declared-addition accounting stays checkable instead of hand-transcribed.
# The expected values below are the MSVC x64 ABI values, independently
# cross-checked against the same pinned headers with a clang probe
# (x86_64-pc-windows-msvc, offsetof/sizeof):
#   SDL_PenProximityEvent=24 SDL_PenMotionEvent=40 SDL_PenTouchEvent=40
#   SDL_PenButtonEvent=40 SDL_PenAxisEvent=48 SDL_TouchFingerEvent=56
#   SDL_HapticDirection=16 SDL_HapticPeriodic=48 SDL_HapticEffect=72

DEVICE_LAYOUT_EXPECTED = {
    # pen/tablet + touch event members (SDL_events.h)
    "SDL_PenProximityEvent": {"size": 24, "windowID": 16, "which": 20},
    "SDL_PenMotionEvent": {"size": 40, "windowID": 16, "which": 20,
                           "pen_state": 24, "x": 28, "y": 32},
    "SDL_PenTouchEvent": {"size": 40, "windowID": 16, "which": 20,
                          "pen_state": 24, "x": 28, "y": 32,
                          "eraser": 36, "down": 37},
    "SDL_PenButtonEvent": {"size": 40, "windowID": 16, "which": 20,
                           "pen_state": 24, "x": 28, "y": 32,
                           "button": 36, "down": 37},
    "SDL_PenAxisEvent": {"size": 48, "windowID": 16, "which": 20,
                         "pen_state": 24, "x": 28, "y": 32,
                         "axis": 36, "value": 40},
    "SDL_TouchFingerEvent": {"size": 56, "touchID": 16, "fingerID": 24,
                             "x": 32, "y": 36, "dx": 40, "dy": 44,
                             "pressure": 48, "windowID": 52},
    # haptic wave-form members (SDL_haptic.h)
    "SDL_HapticDirection": {"size": 16, "type": 0, "dir": 4},
    "SDL_HapticPeriodic": {"size": 48, "type": 0, "direction": 4,
                           "length": 20, "delay": 24, "button": 26,
                           "interval": 28, "period": 30, "magnitude": 32,
                           "offset": 34, "phase": 36, "attack_length": 38,
                           "attack_level": 40, "fade_length": 42,
                           "fade_level": 44},
    "SDL_HapticConstant": {"size": 40},
    "SDL_HapticCondition": {"size": 68},
    "SDL_HapticRamp": {"size": 44},
    "SDL_HapticLeftRight": {"size": 12},
    "SDL_HapticCustom": {"size": 56},
}

DEVICE_UNION_EXPECTED = {
    "SDL_HapticEffect": {"size": 72, "align": 8},
}

DEVICE_SURFACE_SYMBOLS = [
    # joystick caps: capability flags live on the joystick properties group
    # (SDL3 has no SDL_JoystickHasRumble/LED functions in the pinned header)
    "SDL_GetJoystickProperties", "SDL_GetBooleanProperty",
    "SDL_SetBooleanProperty", "SDL_GetNumJoystickAxes",
    "SDL_GetNumJoystickButtons", "SDL_GetNumJoystickHats",
    "SDL_GetNumJoystickBalls", "SDL_GetJoystickType",
    # haptic wave-form surface
    "SDL_GetHaptics", "SDL_GetHapticFromID", "SDL_GetHapticName",
    "SDL_GetHapticNameForID", "SDL_OpenHaptic", "SDL_CloseHaptic",
    "SDL_IsJoystickHaptic", "SDL_OpenHapticFromJoystick",
    "SDL_GetHapticFeatures", "SDL_GetMaxHapticEffects",
    "SDL_GetMaxHapticEffectsPlaying", "SDL_GetNumHapticAxes",
    "SDL_HapticEffectSupported", "SDL_CreateHapticEffect",
    "SDL_UpdateHapticEffect", "SDL_RunHapticEffect", "SDL_StopHapticEffect",
    "SDL_DestroyHapticEffect", "SDL_GetHapticEffectStatus",
    "SDL_HapticRumbleSupported", "SDL_InitHapticRumble",
    "SDL_PlayHapticRumble", "SDL_StopHapticRumble",
    # pen/tablet tool-type query
    "SDL_GetPenDeviceType",
]

DEVICE_SURFACE_CONSTANTS = {
    # joystick cap property names (Str)
    "SDL_PROP_JOYSTICK_CAP_MONO_LED_BOOLEAN": "SDL.joystick.cap.mono_led",
    "SDL_PROP_JOYSTICK_CAP_RGB_LED_BOOLEAN": "SDL.joystick.cap.rgb_led",
    "SDL_PROP_JOYSTICK_CAP_PLAYER_LED_BOOLEAN": "SDL.joystick.cap.player_led",
    "SDL_PROP_JOYSTICK_CAP_RUMBLE_BOOLEAN": "SDL.joystick.cap.rumble",
    "SDL_PROP_JOYSTICK_CAP_TRIGGER_RUMBLE_BOOLEAN": "SDL.joystick.cap.trigger_rumble",
    # haptic wave-form types + direction encodings
    "SDL_HAPTIC_INFINITY": 4294967295,
    "SDL_HAPTIC_SINE": 2, "SDL_HAPTIC_SQUARE": 4, "SDL_HAPTIC_TRIANGLE": 8,
    "SDL_HAPTIC_SAWTOOTHUP": 16, "SDL_HAPTIC_SAWTOOTHDOWN": 32,
    "SDL_HAPTIC_POLAR": 0, "SDL_HAPTIC_CARTESIAN": 1,
    "SDL_HAPTIC_SPHERICAL": 2,
    # pen/tablet device types + input-state flags + event types
    "SDL_PEN_DEVICE_TYPE_INVALID": -1, "SDL_PEN_DEVICE_TYPE_UNKNOWN": 0,
    "SDL_PEN_DEVICE_TYPE_DIRECT": 1, "SDL_PEN_DEVICE_TYPE_INDIRECT": 2,
    "SDL_PEN_INPUT_DOWN": 1, "SDL_PEN_INPUT_BUTTON_1": 2,
    "SDL_PEN_INPUT_BUTTON_2": 4, "SDL_PEN_INPUT_BUTTON_3": 8,
    "SDL_PEN_INPUT_BUTTON_4": 16, "SDL_PEN_INPUT_BUTTON_5": 32,
    "SDL_PEN_INPUT_ERASER_TIP": 1073741824,
    "SDL_PEN_INPUT_IN_PROXIMITY": 2147483648,
    "SDL_EVENT_PEN_PROXIMITY_IN": 4864, "SDL_EVENT_PEN_PROXIMITY_OUT": 4865,
    "SDL_EVENT_PEN_DOWN": 4866, "SDL_EVENT_PEN_UP": 4867,
    "SDL_EVENT_PEN_BUTTON_DOWN": 4868, "SDL_EVENT_PEN_BUTTON_UP": 4869,
    "SDL_EVENT_PEN_MOTION": 4870, "SDL_EVENT_PEN_AXIS": 4871,
    # joystick device types (SDL_JoystickType enum)
    "SDL_JOYSTICK_TYPE_UNKNOWN": 0, "SDL_JOYSTICK_TYPE_GAMEPAD": 1,
    "SDL_JOYSTICK_TYPE_WHEEL": 2, "SDL_JOYSTICK_TYPE_ARCADE_STICK": 3,
    "SDL_JOYSTICK_TYPE_FLIGHT_STICK": 4, "SDL_JOYSTICK_TYPE_DANCE_PAD": 5,
    "SDL_JOYSTICK_TYPE_GUITAR": 6, "SDL_JOYSTICK_TYPE_DRUM_KIT": 7,
    "SDL_JOYSTICK_TYPE_ARCADE_PAD": 8, "SDL_JOYSTICK_TYPE_THROTTLE": 9,
    "SDL_JOYSTICK_TYPE_COUNT": 10,
}


def align_up(value, align):
    return (value + align - 1) // align * align


class LayoutEngine:
    """Win64 (MSVC x64) struct/union layout from the parsed header text."""

    def __init__(self, texts, typemap):
        self.texts = texts
        self.tm = typemap
        self.cache = {}

    def find_body(self, kind, name):
        pat = re.compile(r"typedef\s+" + kind + r"\s+" + re.escape(name) +
                         r"\s*\{(.*?)\}\s*" + re.escape(name) + r"\s*;", re.S)
        for fname in sorted(self.texts):
            m = pat.search(self.texts[fname])
            if m:
                return m.group(1)
        raise SystemExit("layout: %s %s not found in the pinned headers" % (kind, name))

    def members(self, body):
        out = []
        for raw in body.split(";"):
            m = norm(raw)
            if not m:
                continue
            m2 = re.match(r"^(.*?)\b([A-Za-z_][A-Za-z0-9_]*)\s*(\[\s*(\d+)\s*\])?$", m)
            if not m2:
                raise SystemExit("layout: unparsed member %r" % m)
            ctype = norm(m2.group(1))
            name = m2.group(2)
            if not ctype:
                raise SystemExit("layout: member %r without a type" % m)
            count = int(m2.group(4)) if m2.group(4) else None
            out.append((ctype, name, count))
        return out

    def type_size(self, ctype):
        ctype = norm(ctype)
        if "*" in ctype:
            return (8, 8)
        spec = self.tm.scalar_spec(ctype)
        if spec is None:
            raise SystemExit("layout: unmapped member type %r" % ctype)
        if spec[0] == "struct":
            lay = self.layout(ctype)
            return (lay["size"], lay["align"])
        if spec[0] == "fnptr" or (spec[0] == "int" and spec[2] == 64):
            return (8, 8)
        if spec[0] in ("int", "bool", "fp"):
            bits = spec[2] if len(spec) > 2 else 0
            n = max(1, bits // 8)
            return (n, n)
        raise SystemExit("layout: unmapped member type %r (%r)" % (ctype, spec))

    def layout(self, name):
        if name in self.cache:
            return self.cache[name]
        off = 0
        max_align = 1
        fields = {}
        for ctype, fname, count in self.members(self.find_body("struct", name)):
            size, align = self.type_size(ctype)
            if count is not None:
                size = size * count
            off = align_up(off, align)
            fields[fname] = off
            off += size
            max_align = max(max_align, align)
        lay = {"size": align_up(off, max_align), "align": max_align, "fields": fields}
        self.cache[name] = lay
        return lay

    def union_layout(self, name):
        size = 0
        max_align = 1
        for ctype, fname, count in self.members(self.find_body("union", name)):
            s, a = self.type_size(ctype)
            if count is not None:
                s = s * count
            size = max(size, s)
            max_align = max(max_align, a)
        return {"size": align_up(size, max_align), "align": max_align}


def audit_device_surface(texts, typemap, declared, export_set, oracle, wrapper_names):
    """Recompute the 0.19.0 device-surface layouts and verify the pinned
    symbol/constant annotations against the headers.  Any mismatch aborts
    generation (the hand-written decode layer would be stale)."""
    engine = LayoutEngine(texts, typemap)
    layouts = {}
    problems = []

    for name, expected in sorted(DEVICE_LAYOUT_EXPECTED.items()):
        got = engine.layout(name)
        row = {"size": got["size"], "align": got["align"]}
        for f, off in sorted(got["fields"].items()):
            row[f] = off
        layouts[name] = row
        if "size" in expected and got["size"] != expected["size"]:
            problems.append("layout %s.size = %d (pinned %d)"
                            % (name, got["size"], expected["size"]))
        for f, off in sorted(expected.items()):
            if f == "size":
                continue
            have = got["fields"].get(f)
            if have != off:
                problems.append("layout %s.%s = %s (pinned %s)" % (name, f, have, off))

    for name, expected in sorted(DEVICE_UNION_EXPECTED.items()):
        got = engine.union_layout(name)
        layouts[name] = {"size": got["size"], "align": got["align"]}
        if got["size"] != expected["size"] or got["align"] != expected["align"]:
            problems.append("union %s = size %d/align %d (pinned %d/%d)"
                            % (name, got["size"], got["align"],
                               expected["size"], expected["align"]))

    for sym in DEVICE_SURFACE_SYMBOLS:
        if sym not in declared:
            problems.append("device symbol not declared: %s" % sym)
        elif sym not in export_set:
            problems.append("device symbol not exported: %s" % sym)
        elif sym not in wrapper_names:
            problems.append("device symbol has no generated wrapper: %s" % sym)

    constants = {}
    for cname, cexp in sorted(DEVICE_SURFACE_CONSTANTS.items()):
        if isinstance(cexp, str):
            got = oracle.str_values.get(cname)
        else:
            got = oracle.sym.get(cname)
        if got != cexp:
            problems.append("constant %s = %r (pinned %r)" % (cname, got, cexp))
        constants[cname] = cexp

    if problems:
        for p in problems:
            sys.stderr.write("device-surface: %s\n" % p)
        raise SystemExit("device-surface audit failed (%d problem(s))" % len(problems))

    return {
        "layouts": layouts,
        "symbols": sorted(DEVICE_SURFACE_SYMBOLS),
        "symbols_verified": len(DEVICE_SURFACE_SYMBOLS),
        "constants": constants,
        "constants_verified": len(DEVICE_SURFACE_CONSTANTS),
        "abi": "Win64 (MSVC x64 natural alignment), cross-checked with a clang "
               "x86_64-pc-windows-msvc offsetof probe against the pinned headers",
    }


PARAM_ANNOTATION_RE = re.compile(
    r"\bSDL_[A-Z0-9_]*(?:_CAP|_BYTECAP|_FORMAT_STRING|_VARARG_FUNC[V]?|_STRING)\s*(?:\([^()]*\))?\s*")


def strip_param_name(param, idx):
    param = PARAM_ANNOTATION_RE.sub("", norm(param))
    m = re.match(r"^(.*?)([A-Za-z_][A-Za-z0-9_]*)(\[\d*\])?$", param)
    if not m:
        return param, "arg%d" % idx
    ctype = norm(m.group(1))
    pname = m.group(2)
    if pname in ("void", "const") and "*" not in ctype:
        return param, "arg%d" % idx
    return ctype, pname


COLLISION_RENAMES = {
    # SDL exposes both SDL_log (stdinc math) and SDL_Log (logging); the snake
    # forms collide. Deterministic, documented split (see COVERAGE doc).
    ("SDL_Log", "SDL_log"): {"SDL_Log": "sdl3full_log", "SDL_log": "sdl3full_math_log"},
}


class FuncWriter:
    def __init__(self, typemap):
        self.tm = typemap
        self.notes = []

    def classify_return(self, ret):
        ret = norm(ret)
        if "*" in ret:
            if re.match(r"^(const\s+)?char\s*\*$", ret):
                return {"kind": "strptr"}, "strptr"
            return {"kind": "int", "sign": True, "bits": 64}, "pointer"
        spec = self.tm.scalar_spec(ret)
        if spec is None:
            self.notes.append("unmapped return type: %s" % ret)
            return {"kind": "int", "sign": True, "bits": 64}, "pointer"
        if spec[0] == "bool":
            return {"kind": "bool"}, "bool"
        if spec[0] == "fp":
            return {"kind": "fp", "bits": spec[2]}, "fp"
        if spec[0] == "void":
            return {"kind": "void"}, "void"
        if spec[0] == "struct":
            return {"kind": "struct"}, "sret"
        if spec[0] == "int":
            return {"kind": "int", "sign": spec[1], "bits": spec[2]}, "int"
        return None, "void"

    def classify_param(self, ctype):
        ctype = norm(ctype)
        if "*" in ctype:
            if re.match(r"^const\s+char\s*\*$", ctype):
                return {"kind": "str"}
            return {"kind": "ptr"}
        spec = self.tm.scalar_spec(ctype)
        if spec is None:
            self.notes.append("unmapped param type: %s" % ctype)
            return {"kind": "ptr"}
        if spec[0] == "bool":
            return {"kind": "bool"}
        if spec[0] == "fp":
            return {"kind": "fp", "bits": spec[2]}
        if spec[0] == "struct":
            return {"kind": "struct"}
        return {"kind": "int"}

    def cast_type(self, desc):
        k = desc["kind"]
        if k == "str":
            return "*UInt8"
        if k == "ptr":
            return "Int"
        if k == "struct":
            return "Int"
        if k == "bool":
            return "UInt8"
        if k == "fp":
            return "Float32" if desc["bits"] == 32 else "Float64"
        if k == "strptr":
            return "*UInt8"
        return "Int"

    def ret_cast_type(self, desc):
        k = desc["kind"]
        if k == "int":
            bits = desc["bits"]
            if bits < 32:
                return "Int32"
            if bits == 32:
                return "Int32" if desc["sign"] else "UInt32"
            return "Int" if desc["sign"] else "UInt64"
        if k == "bool":
            return "UInt8"
        if k == "fp":
            return "Float32" if desc["bits"] == 32 else "Float64"
        if k == "strptr":
            return "*UInt8"
        return "Int"


def write_module(out_dir, module_name, header, consts, funcs, typemap, functab, wrapper_names):
    lines = []
    lines.append("// GENERATED by tools/gen_sdl3_full.py from the SDL3 headers shipped with")
    lines.append("// the pinned Vulkan SDK -- do not edit.")
    lines.append("// %s" % header)
    lines.append("module %s" % module_name)
    lines.append("")
    lines.append("use xiom.ffi.dl;")
    lines.append("")
    for kind, name, value in consts:
        if kind == "int":
            lines.append("pub const %s: Int = %s;" % (name, emit_int_const(value)))
        elif kind == "float":
            lines.append("pub const %s: Float64 = %s;" % (name, repr(value)))
        else:
            lines.append('pub const %s: Str = "%s";' % (name, xiom_escape(value)))
    if consts:
        lines.append("")
    mod_last = module_name.split(".")[-1]
    struct = "Sdl3Full" + pascal(mod_last)
    load_fn = "sdl3full_module_load_" + mod_last
    close_fn = "sdl3full_module_close_" + mod_last

    fw = FuncWriter(typemap)
    if funcs:
        lines.append("/// Resolved symbols for this family (%d functions)." % len(funcs))
        lines.append("pub type %s = {" % struct)
        lines.append("  handle: Int;")
        for f in funcs:
            lines.append("  p_%s: Int;" % snake(f))
        lines.append("}")
        lines.append("")
        lines.append("/// Resolve every symbol in this family from an already-open SDL3")
        lines.append("/// library; Err carries the first missing symbol name.")
        lines.append("/// Complexity: O(symbols).")
        lines.append("pub fn %s(soname: Str) -> Result[%s, Str] {" % (load_fn, struct))
        lines.append("  let h = dl.dl_open(soname);")
        lines.append("  if !h.is_ok { return Err(h.error); }")
        lines.append("  let handle: Int = h.value;")
        for i, f in enumerate(funcs):
            lines.append('  let a%d = dl.dl_sym(handle, "%s");' % (i + 1, f))
            lines.append('  if !a%d.is_ok { var ig = dl.dl_close(handle); return Err("%s: " + a%d.error); }'
                         % (i + 1, f, i + 1))
        lines.append("  return Ok(%s{" % struct)
        lines.append("    handle: handle,")
        for i, f in enumerate(funcs):
            lines.append("    p_%s: a%d.value," % (snake(f), i + 1))
        lines.append("  });")
        lines.append("}")
        lines.append("")
        lines.append("/// Release the loader handle.")
        lines.append("/// Complexity: O(1).")
        lines.append("pub fn %s(lib: &%s) -> Result[Unit, Str]" % (close_fn, struct))
        lines.append("  requires: lib.handle != 0")
        lines.append("{")
        lines.append("  return dl.dl_close(lib.handle);")
        lines.append("}")
        lines.append("")

        for f in funcs:
            sig = functab[f]
            lines.extend(emit_wrapper(f, sig, struct, fw, wrapper_names[f]))

    text = "\n".join(lines) + "\n"
    path = os.path.join(out_dir, "sdl3_full_%s.xi" % mod_last)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    return path, fw.notes


def emit_wrapper(fname, sig, struct, fw, wname):
    ret_desc, ret_style = fw.classify_return(sig["ret"])
    params = split_params(sig["params_src"])
    variadic = bool(params) and params[-1].strip() == "..."
    if variadic:
        params = params[:-1]
    plist = []          # (ctype, param name)
    used = set(["lib", "f", "p_ret", "raw_ret"])
    for idx, p in enumerate(params):
        ctype, pname = strip_param_name(p, idx)
        base = re.sub(r"[^A-Za-z0-9_]", "_", pname).strip("_") or ("arg%d" % idx)
        if base in KEYWORDS or base in used or not base[0].isalpha():
            base = "v_" + base
        while base in used:
            base = base + "_"
        used.add(base)
        plist.append((ctype, base))
    doc = "%s(%s) -> %s" % (fname, sig["params_src"], sig["ret"])
    if len(doc) > LINE_WIDTH:
        doc = doc[:LINE_WIDTH - 3] + "..."
    out = []
    out.append("/// %s" % doc)
    if variadic:
        out.append("/// Variadic: bound on the fixed parameter list only (caveat documented).")
    if ret_desc.get("kind") == "fp":
        out.append("/// B-12 caveat: fp cast-call returns are miscompiled on the pinned")
        out.append("/// toolchain -- the returned Float64 is NOT trustworthy.")
    if ret_style == "sret":
        out.append("/// sret shape: `out` is a caller-owned buffer address (Win64 hidden")
        out.append("/// first argument for struct returns); true when SDL returned it.")
    out.append("/// Complexity: O(1).")
    arglist = ["lib: &%s" % struct]
    for ctype, base in plist:
        desc = fw.classify_param(ctype)
        if desc["kind"] == "str":
            arglist.append("%s: Str" % base)
        elif desc["kind"] == "bool":
            arglist.append("%s: Bool" % base)
        elif desc["kind"] == "fp":
            arglist.append("%s: Float64" % base)
        else:
            arglist.append("%s: Int" % base)
    if ret_style == "sret":
        arglist.insert(1, "out: Int")
    if ret_desc["kind"] == "bool" or ret_style == "sret":
        ret_decl = " -> Bool"
    elif ret_desc["kind"] == "fp":
        ret_decl = " -> Float64"
    elif ret_style == "strptr":
        ret_decl = " -> Str"
    elif ret_desc["kind"] == "int":
        ret_decl = " -> Int"
    else:
        ret_decl = ""
    out.append("pub fn %s(%s)%s" % (wname, ", ".join(arglist), ret_decl))
    out.append("  requires: lib.handle != 0")
    if ret_style == "sret":
        out.append("  requires: out != 0")
    out.append("{")
    out.append("  unsafe {")

    cast_params = []
    call_args = []
    for ctype, base in plist:
        desc = fw.classify_param(ctype)
        cast_params.append(fw.cast_type(desc))
        if desc["kind"] == "str":
            call_args.append("%s.c_str()" % base)
        elif desc["kind"] == "bool":
            out.append("    let v_%s: UInt8 = if %s { 1 as UInt8 } else { 0 as UInt8 };"
                       % (base, base))
            call_args.append("v_%s" % base)
        elif desc["kind"] == "fp" and desc.get("bits", 64) == 32:
            out.append("    let v_%s: Float32 = %s as Float32;" % (base, base))
            call_args.append("v_%s" % base)
        else:
            call_args.append(base)
    if ret_style == "sret":
        cast_params.insert(0, "Int")
        call_args.insert(0, "out")
    cast_ret = ""
    if ret_desc["kind"] != "void":
        cast_ret = " -> " + fw.ret_cast_type(ret_desc)
    out.append("    let f = lib.p_%s as fn(%s)%s;" % (snake(fname), ", ".join(cast_params), cast_ret))
    call = "f(%s)" % ", ".join(call_args)

    if ret_desc["kind"] == "void":
        out.append("    %s;" % call)
    elif ret_style == "sret":
        out.append("    return %s != 0;" % call)
    elif ret_desc["kind"] == "bool":
        out.append("    return (%s as Int) != 0;" % call)
    elif ret_desc["kind"] == "fp":
        out.append("    return %s as Float64;" % call)
    elif ret_style == "strptr":
        out.append("    let p_ret = %s;" % call)
        out.append("    if (p_ret as Int) == 0 { return \"\"; }")
        out.append("    return Str::from_c_str(p_ret);")
    elif ret_desc["kind"] == "int" and ret_desc["bits"] < 32:
        out.append("    let raw_ret = (%s as Int) & %s;" % (call, hex((1 << ret_desc["bits"]) - 1)))
        if ret_desc["sign"]:
            out.append("    if raw_ret >= %s { return raw_ret - %s; }"
                       % (1 << (ret_desc["bits"] - 1), 1 << ret_desc["bits"]))
        out.append("    return raw_ret;")
    else:
        out.append("    return %s as Int;" % call)
    out.append("  }")
    out.append("}")
    out.append("")
    return out


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sdk", default=r"C:\VulkanSDK\1.4.350.0")
    ap.add_argument("--package", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    args = ap.parse_args()

    include = os.path.join(args.sdk, "Include", "SDL3")
    dll = os.path.join(args.sdk, "Bin", "SDL3.dll")
    src_dir = os.path.join(args.package, "src")
    docs_dir = os.path.join(args.package, "docs")
    os.makedirs(src_dir, exist_ok=True)
    os.makedirs(docs_dir, exist_ok=True)

    header_paths = sorted(p for p in glob.glob(os.path.join(include, "*.h"))
                          if HEADER_RE.match(os.path.basename(p)))
    texts = {}
    for path in header_paths:
        texts[os.path.basename(path)] = strip_comments(
            open(path, "r", encoding="utf-8", errors="replace").read())

    typedefs = parse_typedefs(texts)
    order, functab = parse_functions(texts)
    exports = sorted(set(n for n in pe_exports(dll) if n.startswith("SDL_")))
    export_set = set(exports)
    declared = set(functab)
    declared_order = sorted(declared)
    target = sorted(declared & export_set)
    declared_not_exported = sorted(declared - export_set)
    export_only = sorted(export_set - declared)

    oracle = ConstantOracle(typedefs)
    parse_enums(texts, oracle)
    parse_defines(texts, oracle)
    oracle.resolve_all()

    typemap = TypeMap(typedefs, oracle)

    # wrapper names (snake) + deterministic collision handling --------------
    snake_map = {}
    for name in target:
        snake_map.setdefault(snake(name), []).append(name)
    wrapper_names = {}
    for sn, names in sorted(snake_map.items()):
        if len(names) == 1:
            wrapper_names[names[0]] = "sdl3full_" + sn
        else:
            ren = COLLISION_RENAMES.get(tuple(sorted(names)))
            if not ren:
                raise SystemExit("unhandled wrapper name collision: %s" % names)
            wrapper_names.update(ren)

    # device-surface pin (0.19.0) -------------------------------------------
    device_surface = audit_device_surface(texts, typemap, declared, export_set,
                                          oracle, wrapper_names)

    # family plan -----------------------------------------------------------
    family_of = {}
    fam_funcs = {}
    for name in target:
        fam = os.path.basename(functab[name]["file"])[4:-2]  # SDL_x.h -> x
        family_of[name] = fam
        fam_funcs.setdefault(fam, []).append(name)

    def const_value(name):
        if name in oracle.sym:
            return ("int", oracle.sym[name])
        if name in oracle.str_values:
            return ("str", oracle.str_values[name])
        if name in oracle.float_values:
            return ("float", oracle.float_values[name])
        return None

    fam_consts = {}
    for name in oracle.order:
        if const_value(name) is None:
            continue
        source = oracle.candidates[name][0][2]
        fam = os.path.basename(source)[4:-2]
        fam_consts.setdefault(fam, [])

    modules = []       # (module_name, family, [funcs], [(kind,name,value)])
    all_families = set()
    for fam in sorted(set(list(fam_funcs.keys()) + list(fam_consts.keys()))):
        all_families.add(fam)
        funcs = fam_funcs.get(fam, [])
        n = len(funcs)
        parts = max(1, (n + MAX_FUNCS_PER_MODULE - 1) // MAX_FUNCS_PER_MODULE)
        chunk_size = (n + parts - 1) // parts if n else 0
        if n:
            chunks = [funcs[i:i + chunk_size] for i in range(0, n, chunk_size)]
        else:
            chunks = [[]]
        for idx, chunk in enumerate(chunks):
            mod_fam = fam if idx == 0 else "%s_%d" % (fam, idx + 1)
            consts = []
            if idx == 0:
                for cname in oracle.order:
                    value = const_value(cname)
                    if value is None:
                        continue
                    source = oracle.candidates[cname][0][2]
                    if os.path.basename(source)[4:-2] != fam:
                        continue
                    consts.append((value[0], cname, value[1]))
            modules.append((mod_fam, fam, chunk, consts))

    # emit ------------------------------------------------------------------
    infra_names = set()
    for mod_fam, fam, chunk, consts in modules:
        if chunk:
            infra_names.add("sdl3full_module_load_" + mod_fam)
            infra_names.add("sdl3full_module_close_" + mod_fam)
    clash = sorted(set(wrapper_names.values()) & infra_names)
    if clash:
        raise SystemExit("wrapper/infrastructure name clash: %s" % clash)

    all_notes = []
    manifest_modules = []
    for mod_fam, fam, chunk, consts in modules:
        module_name = "xiom.sdl3.full." + mod_fam
        path, notes = write_module(src_dir, module_name, "family %s" % fam, consts, chunk,
                                   typemap, functab, wrapper_names)
        all_notes.extend(notes)
        manifest_modules.append({
            "module": module_name,
            "family": fam,
            "functions": len(chunk),
            "constants": len(consts),
            "file": os.path.basename(path),
        })

    # names module ----------------------------------------------------------
    names_lines = []
    names_lines.append("// GENERATED by tools/gen_sdl3_full.py -- do not edit.")
    names_lines.append("// Oracle name lists: declared = SDL_FUNCTION declarations in the shipped")
    names_lines.append("// SDK headers; exported = SDL_* exports of the matching SDL3.dll.")
    names_lines.append("module xiom.sdl3.full.names")
    names_lines.append("")
    names_lines.append("pub const SDL3FULL_DECLARED_COUNT: Int = %d;" % len(declared_order))
    names_lines.append("pub const SDL3FULL_EXPORT_COUNT: Int = %d;" % len(exports))
    names_lines.append("pub const SDL3FULL_TARGET_COUNT: Int = %d;" % len(target))
    names_lines.append("")

    def emit_name_list(fn, names):
        names_lines.append("pub fn %s() -> Vec[Str] {" % fn)
        names_lines.append("  var v: Vec[Str] = Vec[Str].new();")
        for nm in names:
            names_lines.append('  v.push("%s");' % nm)
        names_lines.append("  return v;")
        names_lines.append("}")
        names_lines.append("")

    emit_name_list("sdl3full_export_names", exports)
    emit_name_list("sdl3full_declared_names", declared_order)
    emit_name_list("sdl3full_declared_not_exported", declared_not_exported)
    emit_name_list("sdl3full_export_only", export_only)
    with open(os.path.join(src_dir, "sdl3_full_names.xi"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(names_lines))

    # registry module -------------------------------------------------------
    reg = []
    reg.append("// GENERATED by tools/gen_sdl3_full.py -- do not edit.")
    reg.append("// Registry: loads+closes every function module over one SDL3.dll handle")
    reg.append("// path; used by tests/test_full_surface.xi to prove struct+resolver wiring.")
    reg.append("module xiom.sdl3.full.registry")
    reg.append("")
    fn_modules = [(mf, fam, len(chunk)) for mf, fam, chunk, consts in modules if chunk]
    for mf, fam, cnt in fn_modules:
        reg.append("use xiom.sdl3.full.%s;" % mf)
    reg.append("")
    reg.append("pub const SDL3FULL_MODULE_COUNT: Int = %d;" % len(fn_modules))
    reg.append("")
    reg.append("pub fn sdl3full_reg_count() -> Int { return %d; }" % len(fn_modules))
    reg.append("")
    reg.append("pub fn sdl3full_reg_load(i: Int, soname: Str) -> Result[Int, Str] {")
    for idx, (mf, fam, cnt) in enumerate(fn_modules):
        reg.append("  if i == %d {" % idx)
        reg.append("    let r = sdl3full_module_load_%s(soname);" % mf)
        reg.append("    if !r.is_ok { return Err(r.error); }")
        reg.append("    let lib = r.value;")
        reg.append("    var ig = sdl3full_module_close_%s(&lib);" % mf)
        reg.append("    return Ok(%d);" % cnt)
        reg.append("  }")
    reg.append('  return Err("bad module index");')
    reg.append("}")
    with open(os.path.join(src_dir, "sdl3_full_registry.xi"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(reg) + "\n")

    # manifest --------------------------------------------------------------
    header_hashes = {}
    for path in header_paths:
        header_hashes[os.path.basename(path)] = sha256_file(path)
    manifest = {
        "sdk_root": args.sdk,
        "dll": "SDL3.dll",
        "dll_sha256": sha256_file(dll),
        "header_count": len(header_paths),
        "header_sha256": header_hashes,
        "declared": len(declared_order),
        "exported": len(exports),
        "target": len(target),
        "declared_not_exported": declared_not_exported,
        "export_only": export_only,
        "constants_int": len(oracle.sym),
        "constants_str": len(oracle.str_values),
        "constants_float": len(oracle.float_values),
        "constants_unresolved": [[n, s, e] for (n, s, e) in oracle.unresolved],
        "device_surface": device_surface,
        "modules": manifest_modules,
        "unmapped_types": sorted(set(all_notes)),
    }
    with open(os.path.join(docs_dir, "gen_manifest.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)

    print("declared=%d exported=%d target=%d" % (len(declared_order), len(exports), len(target)))
    print("declared_not_exported=%s" % declared_not_exported)
    print("export_only=%s" % export_only)
    print("device-surface: symbols=%d/%d constants=%d/%d layouts=%d/%d (Win64 pin)"
          % (device_surface["symbols_verified"], len(DEVICE_SURFACE_SYMBOLS),
             device_surface["constants_verified"], len(DEVICE_SURFACE_CONSTANTS),
             len(device_surface["layouts"]),
             len(DEVICE_LAYOUT_EXPECTED) + len(DEVICE_UNION_EXPECTED)))
    print("constants: int=%d str=%d unresolved=%d" %
          (len(oracle.sym), len(oracle.str_values), len(oracle.unresolved)))
    for n, s, e in oracle.unresolved[:30]:
        print("  unresolved const: %s (%s) = %s" % (n, s, e))
    print("modules=%d" % len(manifest_modules))
    for m in manifest_modules:
        print("  %-46s fns=%-3d consts=%d" % (m["module"], m["functions"], m["constants"]))
    print("unmapped types: %s" % sorted(set(all_notes)))


if __name__ == "__main__":
    main()
