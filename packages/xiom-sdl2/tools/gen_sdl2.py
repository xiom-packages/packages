#!/usr/bin/env python3
"""XIOM xiom.sdl2 100% API-surface generator.

Oracle: the SDL2 headers shipped with the Vulkan SDK at
  C:/VulkanSDK/1.4.350.0/Include/SDL2/SDL*.h   (SDL_test* framework excluded)
intersected with the SDL2.dll export table (llvm-objdump -p).  Upstream pin:
SDL release-2.32.10 (5d249570393f7a37e037abf22cd6012a4cc56a71).

Emits (into packages/xiom-sdl2/):
  src/<family>_f<n>.xi   -- family-split symbol struct + dl.dl_sym resolver +
                            one typed wrapper per exported function; the
                            family's constants ride in the first chunk.
  src/<family>.xi        -- constants-only module (headers with no functions),
                            or src/<family>_c.xi when a family's constant
                            table is too large to share chunk 1.
  src/names_<n>.xi       -- exported-name table chunks (loadability suite).
  src/names.xi           -- name-table aggregator + SDL2_EXPORTED_COUNT.
  sdl2.xi                -- entry module: core constants, Sdl2Library aggregate
                            (one field per generated chunk), sdl2_load /
                            sdl2_close (sdl3_load-style).
  docs/sdl2-exports.txt  -- the committed export list (oracle evidence).
  docs/gen_manifest.json -- oracle vs bound vs emitted counts.

Deterministic; Python stdlib only.  Run from the package directory:
  python tools/gen_sdl2.py
"""

import json
import hashlib
import os
import re
import subprocess
import sys

SDK = r"C:\VulkanSDK\1.4.350.0"
DEFAULT_HEADERS = os.path.join(SDK, "Include", "SDL2")
DEFAULT_DLL = os.path.join(SDK, "Bin", "SDL2.dll")
OBJDUMP_CANDIDATES = [
    r"C:\Program Files\LLVM\bin\llvm-objdump.exe",
    "llvm-objdump.exe",
]

PIN = "release-2.32.10"
PIN_COMMIT = "5d249570393f7a37e037abf22cd6012a4cc56a71"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
DOCS = os.path.join(ROOT, "docs")

# Constants are taken from the SDL-core headers only: the GL/EGL passthrough
# headers (SDL_opengl*.h, SDL_egl.h, SDL_opengles*.h) re-declare the GL/EGL
# APIs, which SDL does not own and SDL2.dll does not export.
CONST_HEADER_EXCLUDE = ("SDL_opengl", "SDL_egl", "SDL_opengles")
TEST_PREFIX = "SDL_test"

# Family slug overrides (default: SDL_<name>.h -> <name>).
SLUG_OVERRIDES = {"SDL.h": "init"}

# Module line budget ("generated modules <600 lines each").
MODULE_BUDGET = 560
MAX_FUNCS_PER_CHUNK = 40

XIOM_KEYWORDS = {
    "as", "break", "const", "continue", "else", "enum", "extern", "false",
    "fn", "for", "if", "impl", "in", "let", "loop", "match", "module",
    "mut", "pub", "requires", "ensures", "return", "struct", "trait",
    "true", "type", "unsafe", "use", "var", "while",
}

SCALAR_WIDTH = {
    "int": "Int32",
    "unsigned": "UInt32",
    "unsigned int": "UInt32",
    "unsigned char": "UInt8",
    "unsigned short": "UInt16",
    "unsigned long": "UInt64",
    "unsigned long long": "UInt64",
    "long": "Int64",
    "long long": "Int64",
    "short": "Int16",
    "char": "Int32",
    "Sint8": "Int8", "Uint8": "UInt8",
    "Sint16": "Int16", "Uint16": "UInt16",
    "Sint32": "Int32", "Uint32": "UInt32",
    "Sint64": "Int64", "Uint64": "UInt64",
    "size_t": "UInt64",
    "SDL_bool": "Int32",
}


def die(msg):
    sys.stderr.write("gen_sdl2: ERROR: %s\n" % msg)
    sys.exit(2)


def norm(text):
    return re.sub(r"\s+", " ", (text or "").strip())


def strip_comments(s):
    s = re.sub(r"/\*.*?\*/", " ", s, flags=re.S)
    s = re.sub(r"//[^\n]*", " ", s)
    return s


def header_flat(text):
    """Comments and preprocessor lines removed, whitespace collapsed."""
    t = strip_comments(text)
    t = re.sub(r"^\s*#.*$", " ", t, flags=re.M)
    return norm(t)


def snake(name):
    s = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", name)
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s)
    s = re.sub(r"__+", "_", s).lower()
    return s


def camel(name):
    parts = [p for p in re.split(r"[_]+", name) if p]
    return "".join(p[:1].upper() + p[1:] for p in parts)


def slug_for(header):
    if header in SLUG_OVERRIDES:
        return SLUG_OVERRIDES[header]
    stem = header[:-2] if header.endswith(".h") else header
    if stem.startswith("SDL_"):
        stem = stem[4:]
    return stem.lower()


def sane_ident(name, used):
    n = name or ""
    if not re.match(r"^[A-Za-z_]\w*$", n):
        n = "arg"
    if n in XIOM_KEYWORDS:
        n = n + "_"
    base = n
    k = 1
    while n in used:
        k += 1
        n = "%s_%d" % (base, k)
    used.add(n)
    return n


# ---------------------------------------------------------------------------
# Header parsing
# ---------------------------------------------------------------------------

FN_RE = re.compile(
    r"extern\s+(?:SDL_DEPRECATED\s+)?DECLSPEC\s+(.*?)\s*SDLCALL\s+(\w+)\s*\(")
TYPEDEF_ALIAS_RE = re.compile(
    r"typedef\s+((?:unsigned\s+)?(?:int|char|short|long|long long)|Sint8|Uint8|Sint16|Uint16|Sint32|Uint32|Sint64|Uint64|size_t|SDL_bool)\s+(\w+)\s*;")
OPAQUE_RE = re.compile(r"typedef\s+(?:struct|union)\s+(\w+)\s+(\w+)\s*;")
DATA_RE = re.compile(r"typedef\s+(?:struct|union)\s+(\w+)\s*\{")
FNPTR_RE = re.compile(
    r"typedef\s+([^();]*?)\(\s*SDLCALL\s*\*\s*(\w+)\s*\)\s*\((.*?)\)\s*;")


def parse_headers(headers_dir):
    """Returns (funcs, typedef_aliases, opaque, data_structs, fnptrs, raw)."""
    funcs = {}
    aliases = {}
    opaque = set()
    data = set()
    fnptrs = {}
    raw = {}
    names = sorted(n for n in os.listdir(headers_dir)
                   if n.startswith("SDL") and n.endswith(".h")
                   and not n.startswith(TEST_PREFIX))
    for hdr in names:
        with open(os.path.join(headers_dir, hdr), "r",
                  encoding="utf-8", errors="replace") as f:
            text = f.read()
        raw[hdr] = text
        flat = header_flat(text)

        for m in OPAQUE_RE.finditer(flat):
            opaque.add(m.group(2))
        for m in DATA_RE.finditer(flat):
            data.add(m.group(1))
        for m in TYPEDEF_ALIAS_RE.finditer(flat):
            aliases[m.group(2)] = m.group(1)
        for m in FNPTR_RE.finditer(flat):
            fnptrs[m.group(2)] = parse_fnptr(m.group(1), m.group(3))

        # function declarations: parens-balanced scan (multi-line safe)
        pos = 0
        while True:
            m = FN_RE.search(flat, pos)
            if not m:
                break
            pos = m.end()
            ret = norm(m.group(1))
            name = m.group(2)
            if not name.startswith("SDL_"):
                continue
            # find the matching close paren
            start = m.end() - 1
            depth = 0
            i = start
            while i < len(flat):
                if flat[i] == "(":
                    depth += 1
                elif flat[i] == ")":
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            if i >= len(flat):
                die("unbalanced parens in declaration of %s (%s)" % (name, hdr))
            params = flat[start + 1:i]
            # a declaration may carry trailing attribute macros
            # (SDL_ACQUIRE(x), SDL_PRINTF_VARARG_FUNC(1), SDL_ANALYZER_NORETURN, ...)
            j = i + 1
            ok = False
            while j < len(flat):
                while j < len(flat) and flat[j] in " \t":
                    j += 1
                if j < len(flat) and flat[j] == ";":
                    ok = True
                    break
                am = re.match(r"[A-Za-z_]\w*", flat[j:])
                if not am:
                    break
                j += am.end()
                while j < len(flat) and flat[j] in " \t":
                    j += 1
                if j < len(flat) and flat[j] == "(":
                    depth2 = 0
                    while j < len(flat):
                        if flat[j] == "(":
                            depth2 += 1
                        elif flat[j] == ")":
                            depth2 -= 1
                            if depth2 == 0:
                                break
                        j += 1
                    j += 1
            if not ok:
                continue  # not a plain declaration (e.g. a macro body)
            # last declaration wins: the shared-library default is declared
            # in the #else branch after the internal static-build variant
            # (SDL_CreateThread 3-arg vs 5-arg, SDL_RWFromFP void* vs FILE*).
            funcs[name] = {
                "name": name,
                "ret": ret,
                "params_raw": params,
                "header": hdr,
            }
    return funcs, aliases, opaque, data, fnptrs, raw


def parse_fnptr(ret, params):
    ret = norm(ret)
    parts = []
    for p in split_params(params):
        parts.append(map_abi_type(p))
    ret_t = "Unit" if ret == "void" else ("Float64" if ret == "double" else
                                          ("Float32" if ret == "float" else "Int"))
    return "fn(%s) -> %s" % (", ".join(parts), ret_t) if parts else "fn() -> %s" % ret_t


def map_abi_type(param):
    """XIOM type for one C param inside a callback fn-pointer typedef."""
    p = norm(param)
    if "float" in p.split():
        return "Float32"
    if "double" in p.split():
        return "Float64"
    return "Int"


def split_params(params):
    """Top-level comma split (params here contain no nested parens)."""
    out = []
    depth = 0
    cur = ""
    for ch in params:
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        cur += ch
    if cur.strip():
        out.append(cur)
    return out


PARAM_RE = re.compile(r"^(?P<base>.*?)\s*(?P<stars>\*+)?\s*(?P<name>\w*)\s*$")


def parse_param(p):
    """(base, stars, is_const, name, arr) or None for void."""
    s = norm(p)
    if s == "" or s == "void":
        return None
    if s == "...":
        return ("variadic", "", False, "", "")
    arr = ""
    m = re.match(r"^(.*)\[\s*\]$", s)
    if m:
        s = norm(m.group(1)) + " *"   # array decays to pointer
    # drop SAL-style annotation macros that precede the type
    # (SDL_PRINTF_FORMAT_STRING const char*, SDL_OUT_Z_CAP(n) char*, ...)
    s = re.sub(r"SDL_(?:(?:IN|OUT|INOUT)_[A-Z_]+\([^)]*\)|(?:PRINTF|SCANF)_FORMAT_STRING)\s+", "", s)
    s = re.sub(r"\bconst\b", "", s)
    s = norm(s)
    # normalize stars: "char * * x" -> "char ** x"
    s = re.sub(r"\s*\*\s*(\*)*\s*", lambda mm: "*" * (1 + len(mm.group(1) or "")) + " ", s)
    m = PARAM_RE.match(s)
    if not m:
        die("cannot parse param: %r" % p)
    return (norm(m.group("base")), m.group("stars") or "", "const" in p, m.group("name"), arr)


# ---------------------------------------------------------------------------
# Constant parsing (enums + object-like macros) with expression evaluation
# ---------------------------------------------------------------------------

ENUM_RE = re.compile(r"\benum\b[^;{]*\{([^}]*)\}")


def split_enum_body(body):
    """Comma-split an enum body, respecting char literals and parens."""
    parts = []
    cur = ""
    quote = None
    depth = 0
    i = 0
    while i < len(body):
        ch = body[i]
        if quote:
            cur += ch
            if ch == "\\" and i + 1 < len(body):
                cur += body[i + 1]
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "'\"":
            quote = ch
            cur += ch
        elif ch == "(":
            depth += 1
            cur += ch
        elif ch == ")":
            depth -= 1
            cur += ch
        elif ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
        i += 1
    if cur.strip():
        parts.append(cur)
    return parts


class ConstTable(object):
    """Ordered constant definitions with lazy C-expression evaluation."""

    def __init__(self):
        self.raw = {}          # name -> ("num", expr) | ("str", text) | ("enum", expr)
        self.order = []
        self.cache = {}
        self.failed = {}       # name -> reason

    def add_num(self, name, expr):
        if name not in self.raw:
            self.raw[name] = ("num", expr)
            self.order.append(name)

    def add_seq(self, name, prev_name):
        """Enum entry without an explicit value: prev + 1 (resolved lazily)."""
        if name not in self.raw:
            self.raw[name] = ("seq", prev_name)
            self.order.append(name)

    def add_str(self, name, text):
        if name not in self.raw:
            self.raw[name] = ("str", text)
            self.order.append(name)

    def value(self, name):
        if name in self.cache:
            return self.cache[name]
        if name in self.failed:
            return None
        if name not in self.raw:
            return None
        kind, text = self.raw[name]
        if kind == "str":
            val = text
        elif kind == "seq":
            if text == "":
                val = 0
            else:
                prev = self.value(text)
                if prev is None or not isinstance(prev, int):
                    self.failed[name] = "unresolved previous enumerator: %s" % text
                    return None
                val = prev + 1
        else:
            val = eval_c_expr(text, self)
            if val is None and FLOAT_LITERAL_RE.match(text):
                val = float(re.sub(r"[fFlL]$", "", text))
            if val is None:
                self.failed[name] = "unevaluable expression: %s" % text
                return None
        self.cache[name] = val
        return val


def eval_c_expr(expr, table):
    expr = expand_known_macros(expr, table)
    if expr is None:
        return None
    toks = tokenize(expr)
    if toks is None:
        return None
    parser = ExprParser(toks, table)
    try:
        val = parser.parse()
    except Exception:
        return None
    if parser.pos != len(parser.toks):
        return None
    return val


FLOAT_LITERAL_RE = re.compile(r"^\d+\.\d*(?:[fFlL])?$|^\.\d+(?:[fFlL])?$")


def split_macro_args(s):
    args = []
    cur = ""
    depth = 0
    quote = None
    for ch in s:
        if quote:
            cur += ch
            if ch == quote:
                quote = None
            continue
        if ch in "'\"":
            quote = ch
            cur += ch
        elif ch == "(":
            depth += 1
            cur += ch
        elif ch == ")":
            depth -= 1
            cur += ch
        elif ch == "," and depth == 0:
            args.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        args.append(cur.strip())
    return args


def expand_known_macros(expr, table):
    """Inline the handful of function-like macros that constant values use."""
    def arg_int(s):
        e = expand_known_macros(s, table)
        if e is None:
            raise ValueError("unresolved macro arg")
        toks = tokenize(e)
        if toks is None:
            raise ValueError("bad macro arg")
        p = ExprParser(toks, table)
        v = p.parse()
        if p.pos != len(p.toks) or not isinstance(v, int):
            raise ValueError("non-int macro arg")
        return v

    def scancode_repl(m):
        return str(arg_int(m.group(1)) | (1 << 30))

    def button_repl(m):
        return str(1 << (arg_int(m.group(1)) - 1))

    def pixelformat_repl(m):
        a = split_macro_args(m.group(1))
        if len(a) != 5:
            raise ValueError("bad SDL_DEFINE_PIXELFORMAT")
        t, o, l, b, by = [arg_int(x) for x in a]
        return str((1 << 28) | (t << 24) | (o << 20) | (l << 16) | (b << 8) | by)

    def fourcc_repl(m):
        a = split_macro_args(m.group(1))
        if len(a) != 4:
            raise ValueError("bad SDL_DEFINE_PIXELFOURCC")
        v = [arg_int(x) for x in a]
        return str(v[0] | (v[1] << 8) | (v[2] << 16) | (v[3] << 24))

    def versionnum_repl(m):
        a = split_macro_args(m.group(1))
        if len(a) != 3:
            raise ValueError("bad SDL_VERSIONNUM")
        x, y, z = [arg_int(v) for v in a]
        return str((x * 1000 + y) * 1000 + z)

    def pos_undefined_repl(m):
        return str(arg_int(m.group(1)) | 0x1FFF0000)

    def pos_centered_repl(m):
        return str(arg_int(m.group(1)) | 0x2FFF0000)

    try:
        expr = re.sub(r"SDL_SCANCODE_TO_KEYCODE\(\s*([^()]+?)\s*\)", scancode_repl, expr)
        expr = re.sub(r"SDL_BUTTON\(\s*([^()]+?)\s*\)", button_repl, expr)
        expr = re.sub(r"SDL_DEFINE_PIXELFORMAT\(([^()]*(?:\([^()]*\)[^()]*)*)\)",
                      pixelformat_repl, expr)
        expr = re.sub(r"SDL_DEFINE_PIXELFOURCC\(([^()]*(?:\([^()]*\)[^()]*)*)\)",
                      fourcc_repl, expr)
        expr = re.sub(r"SDL_VERSIONNUM\(([^()]*(?:\([^()]*\)[^()]*)*)\)",
                      versionnum_repl, expr)
        expr = re.sub(r"SDL_WINDOWPOS_UNDEFINED_DISPLAY\(([^()]+?)\)",
                      pos_undefined_repl, expr)
        expr = re.sub(r"SDL_WINDOWPOS_CENTERED_DISPLAY\(([^()]+?)\)",
                      pos_centered_repl, expr)
    except ValueError:
        return None
    return expr


TOKEN_RE = re.compile(
    r"""\s*(?:
        (?P<num>0[xX][0-9A-Fa-f]+[uUlL]*|\d+[uUlL]*)
      | (?P<char>'(?:\\(?:x[0-9A-Fa-f]+|[0-7]{1,3}|.)|[^'\\])')
      | (?P<name>[A-Za-z_]\w*)
      | (?P<op><<|>>|[-+*/%&|^~()!])
      | (?P<bad>.)
    )""", re.X)


def tokenize(expr):
    toks = []
    pos = 0
    while pos < len(expr):
        m = TOKEN_RE.match(expr, pos)
        if not m:
            return None
        if m.group("bad"):
            return None
        pos = m.end()
        if m.group("num"):
            v = re.sub(r"[uUlL]+$", "", m.group("num"))
            toks.append(("num", int(v, 0)))
        elif m.group("char"):
            body = m.group("char")[1:-1]
            if body.startswith("\\"):
                esc = {"\\n": 10, "\\t": 9, "\\r": 13, "\\0": 0, "\\b": 8,
                       "\\f": 12, "\\v": 11, "\\a": 7,
                       "\\\\": 92, "\\'": 39, '\\"': 34}
                if body in esc:
                    toks.append(("num", esc[body]))
                elif body.startswith("\\x") or body.startswith("\\X"):
                    try:
                        toks.append(("num", int(body[2:], 16)))
                    except ValueError:
                        return None
                elif re.match(r"^\\[0-7]+$", body):
                    toks.append(("num", int(body[1:], 8)))
                else:
                    return None
            else:
                toks.append(("num", ord(body)))
        elif m.group("name"):
            toks.append(("name", m.group("name")))
        else:
            toks.append(("op", m.group("op")))
    return toks


class ExprParser(object):
    """C subset: | ^ & << >> + - * / % unary(~ - !) parens casts refs."""

    def __init__(self, toks, table):
        self.toks = toks
        self.pos = 0
        self.table = table

    def peek(self):
        return self.toks[self.pos] if self.pos < len(self.toks) else (None, None)

    def take(self):
        t = self.peek()
        self.pos += 1
        return t

    def parse(self):
        return self.orexpr()

    def orexpr(self):
        val = self.xorexpr()
        while self.peek() == ("op", "|"):
            self.take()
            val |= self.xorexpr()
        return val

    def xorexpr(self):
        val = self.andexpr()
        while self.peek() == ("op", "^"):
            self.take()
            val ^= self.andexpr()
        return val

    def andexpr(self):
        val = self.shift()
        while self.peek() == ("op", "&"):
            self.take()
            val &= self.shift()
        return val

    def shift(self):
        val = self.addsub()
        while self.peek() in (("op", "<<"), ("op", ">>")):
            op = self.take()[1]
            rhs = self.addsub()
            val = val << rhs if op == "<<" else val >> rhs
        return val

    def addsub(self):
        val = self.muldiv()
        while self.peek() in (("op", "+"), ("op", "-")):
            op = self.take()[1]
            rhs = self.muldiv()
            val = val + rhs if op == "+" else val - rhs
        return val

    def muldiv(self):
        val = self.unary()
        while self.peek() in (("op", "*"), ("op", "/"), ("op", "%")):
            op = self.take()[1]
            rhs = self.unary()
            if op == "*":
                val = val * rhs
            elif op == "/":
                if rhs == 0:
                    raise ValueError("div0")
                val = int(val / rhs) if (val < 0) != (rhs < 0) else val // rhs
            else:
                val = val % rhs
        return val

    def unary(self):
        t = self.peek()
        if t == ("op", "~"):
            self.take()
            return ~self.unary()
        if t == ("op", "-"):
            self.take()
            return -self.unary()
        if t == ("op", "!"):
            self.take()
            return 0 if self.unary() else 1
        if t == ("op", "+"):
            self.take()
            return self.unary()
        if t == ("op", "("):
            # cast or paren
            saved = self.pos
            self.take()
            if self.peek()[0] == "name":
                nm = self.peek()[1]
                self.take()
                if self.peek() == ("op", ")"):
                    self.take()
                    nxt = self.peek()
                    starts_expr = (nxt[0] in ("num", "name")
                                   or nxt in (("op", "("), ("op", "-"),
                                              ("op", "+"), ("op", "~"),
                                              ("op", "!")))
                    if starts_expr:
                        return self.unary()  # drop the cast
                    # `(NAME)` with nothing after: not a cast, rewind
                self.pos = saved
                self.take()
                val = self.orexpr()
                if self.peek() != ("op", ")"):
                    raise ValueError("missing )")
                self.take()
                return val
            val = self.orexpr()
            if self.peek() != ("op", ")"):
                raise ValueError("missing )")
            self.take()
            return val
        if t[0] == "num":
            self.take()
            return t[1]
        if t[0] == "name":
            self.take()
            v = self.table.value(t[1])
            if v is None or not isinstance(v, int):
                raise ValueError("unresolved")
            return v
        raise ValueError("bad token %r" % (t,))


C_BUILTIN_RE = re.compile(
    r"__\w+__|__attribute__|__declspec|__cdecl|__stdcall|_MSC_VER|__STDC|"
    r"__|\basm\b|\binline\b")


def const_skip_reason(expr, table=None):
    """Classify an unevaluable object-like macro (kept out of the binding)."""
    if "#" in expr:
        return "preprocessor fragment"
    if expr.lstrip().startswith('"'):
        return "string expression (concatenation/alias)"
    if C_BUILTIN_RE.search(expr):
        return "C compiler builtin/attribute"
    if re.match(r"^\([^()]*,[^()]*\)$", expr):
        return "non-scalar macro value"
    if re.match(r"^[A-Za-z_]\w*$", expr):
        return "unresolved identifier (type/alias or absent constant)"
    if table is not None:
        toks = tokenize(expr)
        if toks:
            unknown = sorted(set(t[1] for t in toks if t[0] == "name")
                             - set(table.raw))
            if unknown:
                return "unresolved identifier expression (%s)" % ",".join(unknown[:3])
    return "unevaluable expression"


def parse_constants(raw):
    """Returns (table, const_headers, skips, origin[name] = header)."""
    table = ConstTable()
    skips = []
    origin = {}
    const_headers = []
    for hdr in sorted(raw):
        if any(hdr.startswith(p) for p in CONST_HEADER_EXCLUDE):
            continue
        if hdr.startswith(TEST_PREFIX):
            continue
        const_headers.append(hdr)
        text = raw[hdr]
        t = strip_comments(text)
        t = re.sub(r"\\\r?\n", " ", t)   # join continuation lines first

        # object-like macros
        for m in re.finditer(r"^\s*#\s*define\s+(\w+)(\([^)]*\))?\s*(.*)$", t, flags=re.M):
            name, fnlike, val = m.group(1), m.group(2), m.group(3).strip()
            if fnlike:
                skips.append((name, hdr, "function-like macro"))
                continue
            if not val:
                skips.append((name, hdr, "empty macro"))
                continue
            if not const_name_ok(name, hdr):
                skips.append((name, hdr, "out of constant oracle (name filter)"))
                continue
            before = len(table.raw)
            sm = re.match(r'^"([^"\\]*)"$', val)
            if sm:
                table.add_str(name, sm.group(1))
            else:
                table.add_num(name, val)
            if len(table.raw) > before:
                origin[name] = hdr

        # enums
        for m in ENUM_RE.finditer(t):
            body = m.group(1)
            prev_name = ""
            for part in split_enum_body(body):
                part = part.strip()
                if not part:
                    continue
                em = re.match(r"^(\w+)\s*(?:=\s*(.+))?$", part, flags=re.S)
                if not em:
                    continue
                name = em.group(1)
                if not const_name_ok(name, hdr):
                    skips.append((name, hdr, "out of constant oracle (name filter)"))
                    continue
                if name not in origin:
                    origin[name] = hdr
                if em.group(2):
                    table.add_num(name, norm(em.group(2)))
                else:
                    table.add_seq(name, prev_name)
                prev_name = name
    return table, const_headers, skips, origin


def const_name_ok(name, hdr):
    if name.startswith("SDL_") or name.startswith("SDLK_"):
        return True
    if hdr == "SDL_audio.h" and name.startswith("AUDIO_"):
        return True
    if hdr == "SDL_keycode.h" and name.startswith("KMOD_"):
        return True
    if hdr == "SDL_main.h" and name in ("SDL_MAIN_HANDLED",):
        return True
    return False


# ---------------------------------------------------------------------------
# Export table
# ---------------------------------------------------------------------------

def load_exports(dll, exports_file):
    if exports_file:
        with open(exports_file, "r", encoding="utf-8") as f:
            return sorted(set(l.strip() for l in f if l.strip()))
    objdump = None
    for cand in OBJDUMP_CANDIDATES:
        if os.path.sep in cand:
            if os.path.exists(cand):
                objdump = cand
                break
        else:
            from shutil import which
            if which(cand):
                objdump = cand
                break
    if not objdump:
        die("llvm-objdump not found; pass --exports-file")
    proc = subprocess.run([objdump, "-p", dll], stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, universal_newlines=True)
    names = []
    for line in proc.stdout.splitlines():
        m = re.match(r"^\s+\d+\s+0x[0-9a-fA-F]+\s+(\S+)\s*$", line)
        if m:
            names.append(m.group(1))
    if not names:
        die("no exports parsed from %s (objdump rc=%d)" % (dll, proc.returncode))
    return sorted(set(names))


# ---------------------------------------------------------------------------
# Emission
# ---------------------------------------------------------------------------

def module_prologue(slug, chunk_idx, nchunks, nfuncs, headers):
    L = []
    L.append("// GENERATED by tools/gen_sdl2.py from the shipped SDL2 headers -- do not edit.")
    L.append("// Oracle: C:/VulkanSDK/1.4.350.0/Include/SDL2/SDL*.h (SDL_test* excluded);")
    L.append("// upstream pin SDL %s (%s)." % (PIN, PIN_COMMIT))
    L.append("// Headers: %s." % ", ".join(sorted(headers)))
    L.append("// Family '%s' chunk %d/%d: %d exported function(s)%s." %
             (slug, chunk_idx, nchunks, nfuncs,
              "" if nfuncs else "; constants only"))
    L.append("module xiom.sdl2.%s" % (("%s_f%d" % (slug, chunk_idx)) if nfuncs else slug))
    L.append("")
    L.append("use xiom.ffi;")
    L.append("use xiom.ffi.dl;")
    L.append("")
    return L


def render_const(name, kind, value):
    if kind == "str":
        esc = value.replace("\\", "\\\\").replace('"', '\\"')
        return 'pub const %s: Str = "%s";' % (name, esc)
    if kind == "flt":
        return "pub const %s: Float64 = %r;" % (name, value)
    return "pub const %s: Int = %d;" % (name, value)


def wrapper_types(fn, fndef):
    """Returns (params, cast_types, call_args, notes)."""
    raw = fn["params_raw"]
    parts = split_params(raw)
    params = []       # (name, wtype)
    cast_types = []
    call_args = []
    notes = []
    variadic = False
    used = set()
    for i, p in enumerate(parts):
        pp = parse_param(p)
        if pp is None:
            continue
        base, stars, is_const, cname, arr = pp
        if base == "variadic":
            variadic = True
            notes.append("variadic C function -- only the fixed-arity prefix is bound")
            continue
        name = sane_ident(cname, used)
        if stars:
            if base == "void":
                params.append((name, "Int"))
                cast_types.append("Int")
            elif base == "char" and is_const:
                params.append((name, "Str"))
                cast_types.append("*UInt8")
                call_args.append("%s.c_str()" % name)
                continue
            elif base in fndef["fnptrs"] and stars == "*":
                # pointer-to-callback (out param) -> owned 8-byte slot
                params.append((name, "*UInt8"))
                cast_types.append("*UInt8")
            elif base in fndef["opaque"]:
                params.append((name, "Int"))
                cast_types.append("Int")
            else:
                params.append((name, "*UInt8"))
                cast_types.append("*UInt8")
                if base in fndef["fnptrs"]:
                    notes.append("callback out-param is an owned 8-byte slot")
            call_args.append(name)
            continue
        # no stars
        if base in fndef["fnptrs"]:
            params.append((name, fndef["fnptrs"][base]))
            cast_types.append(fndef["fnptrs"][base])
            call_args.append(name)
            continue
        if base == "float":
            params.append((name, "Float32"))
            cast_types.append("Float32")
        elif base == "double":
            params.append((name, "Float64"))
            cast_types.append("Float64")
        elif "va_list" in base:
            params.append((name, "Int"))
            cast_types.append("Int")
            notes.append("va_list is passed through raw (never constructed)")
        else:
            # integer / enum / handle-ish value; Int in both directions is
            # ABI-correct on win-x64 for every width <= 64.
            params.append((name, "Int"))
            cast_types.append("Int")
        call_args.append(name)
    return params, cast_types, call_args, variadic, notes


def return_mapping(fn, fndef):
    """(wrapper_ret or None, cast_ret, kind) -- kind in
    unit/int/f32/f64/str/handle."""
    ret = norm(fn["ret"])
    ret = re.sub(r"\bconst\b", "", ret)
    ret = norm(ret)
    ret = re.sub(r"\s*\*\s*", "*", ret)
    m = re.match(r"^(?P<base>.*?)(?P<stars>\*+)?$", ret)
    base = norm(m.group("base")) if m else ret
    stars = m.group("stars") if m else None
    if base == "void" and not stars:
        return None, None, "unit"
    if stars:
        if base == "char":
            return "Str", "*UInt8", "str"
        return "Int", "Int", "handle"
    if base == "float":
        return "Float32", "Float32", "f32"
    if base == "double":
        return "Float64", "Float64", "f64"
    width = SCALAR_WIDTH.get(base)
    if width is None:
        alias = fndef["aliases"].get(base)
        width = SCALAR_WIDTH.get(alias) if alias else None
    if width is None:
        width = "Int32"
    return "Int", width, "int"


def render_wrapper(fn, fndef):
    name = fn["name"]
    wbase = fndef["wnames"][name]
    field = "p_" + wbase
    params, cast_types, call_args, variadic, notes = wrapper_types(fn, fndef)
    ret = return_mapping(fn, fndef)
    L = []
    for n in notes:
        L.append("// NOTE: %s." % n)
    sig = ["pub fn %s(syms: &Sdl2%sSymbols" % (wbase, fndef["chunk_type"])]
    sig.append("".join(", %s: %s" % (pn, pt) for pn, pt in params))
    sig.append(")")
    ret_w, cast_ret, kind = ret
    if kind == "unit":
        pass
    elif kind == "str":
        sig.append(" -> Str")
    else:
        sig.append(" -> %s" % ret_w)
    L.append("".join(sig))
    L.append("  requires: syms.handle != 0")
    L.append("{")
    L.append("  unsafe {")
    cast_sig = "fn(%s)" % ", ".join(cast_types)
    if cast_ret is not None:
        cast_sig += " -> %s" % cast_ret
    L.append("    let f = syms.%s as %s;" % (field, cast_sig))
    call = "f(%s)" % ", ".join(call_args)
    if kind == "unit":
        L.append("    %s;" % call)
    elif kind == "str":
        L.append("    let p = %s;" % call)
        L.append("    if (p as Int) == 0 { return \"\"; }")
        L.append("    return Str::from_c_str(p);")
    elif kind == "f32":
        L.append("    return %s;" % call)
    elif kind == "f64":
        L.append("    return %s;" % call)
    elif kind == "handle":
        L.append("    return %s;" % call)
    else:
        L.append("    return %s as Int;" % call)
    L.append("  }")
    L.append("}")
    return field, "\n".join(L)


def render_func_chunk(slug, headers, chunk_idx, nchunks, funcs, fndef, consts):
    L = module_prologue(slug, chunk_idx, nchunks, len(funcs), headers)
    if consts:
        L.append("// ---- constants (%d) ----" % len(consts))
        for name, (kind, value) in consts:
            L.append(render_const(name, kind, value))
        L.append("")
    L.append("/// Resolved SDL2 '%s' symbols (chunk %d/%d, %d function(s))." %
             (slug, chunk_idx, nchunks, len(funcs)))
    L.append("pub type Sdl2%sSymbols = {" % ("%sF%d" % (camel(slug), chunk_idx)))
    L.append("  handle: Int;")
    fields = []
    wrappers = []
    for fn in funcs:
        f = dict(fndef)
        f["chunk_type"] = "%sF%d" % (camel(slug), chunk_idx)
        field, wtext = render_wrapper(fn, f)
        fields.append(field)
        wrappers.append(wtext)
    for fld in fields:
        L.append("  %s: Int;" % fld)
    L.append("}")
    L.append("")
    L.append("/// Resolve every '%s' chunk-%d symbol through `dl.dl_sym`." % (slug, chunk_idx))
    L.append("pub fn sdl2_%s_f%d_load(handle: Int) -> Result[Sdl2%sSymbols, Str]" %
             (slug, chunk_idx, "%sF%d" % (camel(slug), chunk_idx)))
    L.append("  requires: handle != 0")
    L.append("{")
    for i, fn in enumerate(funcs):
        L.append("  let a%d = dl.dl_sym(handle, \"%s\");" % (i + 1, fn["name"]))
        L.append("  if !a%d.is_ok { return Err(\"%s: \" + a%d.error); }" %
                 (i + 1, fn["name"], i + 1))
    L.append("  return Ok(Sdl2%sSymbols{" % ("%sF%d" % (camel(slug), chunk_idx)))
    L.append("    handle: handle,")
    for i, fld in enumerate(fields):
        L.append("    %s: a%d.value," % (fld, i + 1))
    L.append("  });")
    L.append("}")
    parts = ["\n".join(L)]
    for w in wrappers:
        parts.append(w)
    return "\n\n".join(parts) + "\n"


def render_const_module(module_name, headers, consts):
    slug = module_name.split(".")[-1]
    L = []
    L.append("// GENERATED by tools/gen_sdl2.py from the shipped SDL2 headers -- do not edit.")
    L.append("// Oracle: C:/VulkanSDK/1.4.350.0/Include/SDL2/SDL*.h (SDL_test* excluded);")
    L.append("// upstream pin SDL %s (%s)." % (PIN, PIN_COMMIT))
    L.append("// Headers: %s." % (", ".join(sorted(headers)) if headers else module_name))
    L.append("// Constants-only module: %d enum/macro value(s)." % len(consts))
    L.append("module %s" % module_name)
    L.append("")
    L.append("// ---- constants (%d) ----" % len(consts))
    for name, (kind, value) in consts:
        L.append(render_const(name, kind, value))
    return "\n".join(L) + "\n"


def render_names_chunk(idx, names):
    L = []
    L.append("// GENERATED by tools/gen_sdl2.py -- exported-name table chunk %d." % idx)
    L.append("// Oracle: SDL2.dll export table intersected with the shipped SDL2 headers.")
    L.append("module xiom.sdl2.names_%d" % idx)
    L.append("")
    L.append("pub fn sdl2_exported_names_%d() -> Vec[Str] {" % idx)
    L.append("  var v: Vec[Str] = Vec[Str].new();")
    for n in names:
        L.append('  v.push("%s");' % n)
    L.append("  return v;")
    L.append("}")
    return "\n".join(L) + "\n"


def render_names_agg(nchunks, total):
    L = []
    L.append("// GENERATED by tools/gen_sdl2.py -- exported-name table aggregator.")
    L.append("module xiom.sdl2.names")
    L.append("")
    for i in range(1, nchunks + 1):
        L.append("use xiom.sdl2.names_%d;" % i)
    L.append("")
    L.append("/// Exported-oracle count: functions declared in the shipped SDL2")
    L.append("/// headers that SDL2.dll exports.  The suite must resolve ALL of them.")
    L.append("pub const SDL2_EXPORTED_COUNT: Int = %d;" % total)
    L.append("")
    L.append("pub fn sdl2_exported_names() -> Vec[Str] {")
    L.append("  var v: Vec[Str] = Vec[Str].new();")
    for i in range(1, nchunks + 1):
        L.append("  var c%d = sdl2_exported_names_%d();" % (i, i))
        L.append("  var i%d = 0;" % i)
        L.append("  while i%d < c%d.len() {" % (i, i))
        L.append("    v.push(c%d[i%d]);" % (i, i))
        L.append("    i%d = i%d + 1;" % (i, i))
        L.append("  }")
    L.append("  return v;")
    L.append("}")
    return "\n".join(L) + "\n"


def render_entry(chunks, total):
    """chunks: ordered list of (slug, idx, nchunks) function chunk modules."""
    L = []
    L.append("// GENERATED by tools/gen_sdl2.py -- entry module.")
    L.append("// xiom.sdl2: SDL2 (Simple DirectMedia Layer 2) bindings, 100% of the")
    L.append("// exported public C API surface.  Dynamic loader: no link-time")
    L.append("// dependency; SDL2.dll is resolved at runtime via xiom.ffi.dl.")
    L.append("// Upstream pin: SDL %s (%s)." % (PIN, PIN_COMMIT))
    L.append("module xiom.sdl2")
    L.append("")
    L.append("use xiom.ffi;")
    L.append("use xiom.ffi.dl;")
    for slug, idx, n in chunks:
        L.append("use xiom.sdl2.%s_f%d;" % (slug, idx))
    L.append("")
    L.append('pub const SDL2_SONAME: Str = "SDL2.dll";')
    L.append("")
    L.append("// Failure kind: library absent (SKIP) vs present but missing symbols (FAIL).")
    L.append("pub const SDL2_LOAD_ABSENT: Int = 0;")
    L.append("pub const SDL2_LOAD_ABI: Int = 1;")
    L.append("")
    L.append("pub type Sdl2LoadError = {")
    L.append("  kind: Int;")
    L.append("  message: Str;")
    L.append("}")
    L.append("")
    L.append("/// A fully-resolved SDL2 library: the dl handle plus one resolved")
    L.append("/// symbol chunk per generated family module.")
    L.append("pub type Sdl2Library = {")
    L.append("  handle: Int;")
    for slug, idx, n in chunks:
        L.append("  %s_f%d: Sdl2%sF%dSymbols;" % (slug, idx, camel(slug), idx))
    L.append("}")
    L.append("")
    L.append("/// Load SDL2.dll and resolve every exported-oracle function (%d)." % total)
    L.append("/// Err(kind=SDL2_LOAD_ABSENT) when the DLL is not on the search path;")
    L.append("/// Err(kind=SDL2_LOAD_ABI) when it loads but a symbol is missing (the")
    L.append("/// handle is closed on failure -- nothing leaks).")
    L.append("pub fn sdl2_load() -> Result[Sdl2Library, Sdl2LoadError] {")
    L.append("  let h = dl.dl_open(SDL2_SONAME);")
    L.append("  if !h.is_ok {")
    L.append("    return Err(Sdl2LoadError{ kind: SDL2_LOAD_ABSENT; message: h.error });")
    L.append("  }")
    L.append("  let handle: Int = h.value;")
    for slug, idx, n in chunks:
        L.append("  let c_%s_%d = sdl2_%s_f%d_load(handle);" % (slug, idx, slug, idx))
        L.append("  if !c_%s_%d.is_ok {" % (slug, idx))
        L.append("    var ig = dl.dl_close(handle);")
        L.append("    return Err(Sdl2LoadError{ kind: SDL2_LOAD_ABI; message: c_%s_%d.error });" % (slug, idx))
        L.append("  }")
    L.append("  return Ok(Sdl2Library{")
    L.append("    handle: handle,")
    for slug, idx, n in chunks:
        L.append("    %s_f%d: c_%s_%d.value," % (slug, idx, slug, idx))
    L.append("  });")
    L.append("}")
    L.append("")
    L.append("/// Release a loaded library handle.")
    L.append("pub fn sdl2_close(lib: &Sdl2Library) -> Result[Unit, Str]")
    L.append("  requires: lib.handle != 0")
    L.append("{")
    L.append("  return dl.dl_close(lib.handle);")
    L.append("}")
    L.append("")
    L.append("/// SDL_VERSIONNUM(major, minor, patch) arithmetic (SDL_version.h).")
    L.append("pub fn sdl2_versionnum(major: Int, minor: Int, patch: Int) -> Int")
    L.append("  requires: major > 0")
    L.append("  requires: minor >= 0")
    L.append("  requires: patch >= 0")
    L.append("{")
    L.append("  return (major * 1000 + minor) * 1000 + patch;")
    L.append("}")
    return "\n".join(L) + "\n"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    args = sys.argv[1:]
    headers_dir = DEFAULT_HEADERS
    dll = DEFAULT_DLL
    exports_file = None
    if "--headers" in args:
        headers_dir = args[args.index("--headers") + 1]
    if "--dll" in args:
        dll = args[args.index("--dll") + 1]
    if "--exports-file" in args:
        exports_file = args[args.index("--exports-file") + 1]

    exports = load_exports(dll, exports_file)
    funcs, aliases, opaque, data, fnptrs, raw = parse_headers(headers_dir)
    table, const_headers, const_skips, const_origin = parse_constants(raw)

    exported = [n for n in exports if n.startswith("SDL_")]
    declared = set(funcs)
    exported_set = set(exported)
    bound_names = sorted(n for n in declared if n in exported_set)
    declared_not_exported = sorted(n for n in declared if n not in exported_set)
    exported_not_declared = sorted(n for n in exported_set if n not in declared)

    wrapper_names = {}
    seen_wrappers = set()
    for n in bound_names:
        w = "sdl2_" + snake(n[4:])
        k = 2
        while w in seen_wrappers:
            w = "sdl2_%s_%d" % (snake(n[4:]), k)
            k += 1
        seen_wrappers.add(w)
        wrapper_names[n] = w

    fndef = {
        "aliases": aliases,
        "opaque": opaque,
        "data": data,
        "fnptrs": fnptrs,
        "wnames": wrapper_names,
    }

    # group bound functions by family
    families = {}
    for name in bound_names:
        fdecl = funcs[name]
        hdr = fdecl["header"]
        families.setdefault(slug_for(hdr), {"headers": [], "funcs": []})
        fam = families[slug_for(hdr)]
        if hdr not in fam["headers"]:
            fam["headers"].append(hdr)
        fam["funcs"].append(fdecl)

    # group evaluable constants by family
    fam_consts = {}
    const_emitted = {}
    const_failed = []
    const_unevaluable = 0
    for name in table.order:
        v = table.value(name)
        hdr = const_origin.get(name)
        if v is None:
            kind, text = table.raw[name]
            reason = const_skip_reason(text, table)
            if reason == "unevaluable expression":
                const_failed.append((name, reason + ": " + text))
                const_unevaluable += 1
            else:
                const_skips.append((name, hdr or "?", reason))
            continue
        slug = slug_for(hdr) if hdr else "misc"
        fam_consts.setdefault(slug, [])
        if isinstance(v, str):
            kind = "str"
        elif isinstance(v, float):
            kind = "flt"
        else:
            kind = "num"
        fam_consts[slug].append((name, (kind, v)))
        const_emitted[name] = hdr

    # emit function chunks
    emitted = []   # (relpath, text)
    chunk_index = []  # (slug, idx, nchunks) for the entry
    for slug in sorted(families):
        fam = families[slug]
        flist = fam["funcs"]
        consts = sorted(fam_consts.get(slug, []), key=lambda c: c[0])
        chunks = []
        cur = []
        for fn in flist:
            if len(cur) >= MAX_FUNCS_PER_CHUNK:
                chunks.append(cur)
                cur = []
            trial = cur + [fn]
            text = render_func_chunk(slug, fam["headers"], 1, 1,
                                     trial, fndef, None)
            if cur and len(text.splitlines()) > MODULE_BUDGET:
                chunks.append(cur)
                cur = [fn]
            else:
                cur = trial
        if cur:
            chunks.append(cur)
        # constants placement
        consts_own = False
        if consts:
            first = render_func_chunk(slug, fam["headers"], 1, len(chunks),
                                      chunks[0], fndef, consts)
            if len(first.splitlines()) > MODULE_BUDGET:
                consts_own = True
        for i, chunk in enumerate(chunks):
            use_consts = consts if (i == 0 and not consts_own) else None
            text = render_func_chunk(slug, fam["headers"], i + 1, len(chunks),
                                     chunk, fndef, use_consts)
            emitted.append(("src/%s_f%d.xi" % (slug, i + 1), text))
            chunk_index.append((slug, i + 1, len(chunks)))
        if consts_own:
            emitted.append(("src/%s_c.xi" % slug,
                            render_const_module("xiom.sdl2.%s_c" % slug,
                                                fam["headers"], consts)))
    # constants-only families
    for slug in sorted(fam_consts):
        if slug in families:
            continue
        consts = sorted(fam_consts[slug], key=lambda c: c[0])
        emitted.append(("src/%s.xi" % slug,
                        render_const_module("xiom.sdl2.%s" % slug, [], consts)))

    # names table
    chunks_of_names = 300
    name_chunks = [bound_names[i:i + chunks_of_names]
                   for i in range(0, len(bound_names), chunks_of_names)]
    for i, nc in enumerate(name_chunks, 1):
        emitted.append(("src/names_%d.xi" % i, render_names_chunk(i, nc)))
    emitted.append(("src/names.xi", render_names_agg(len(name_chunks), len(bound_names))))

    # entry
    entry_chunks = [(s, i, n) for (s, i, n) in chunk_index]
    emitted.append(("sdl2.xi", render_entry(entry_chunks, len(bound_names))))

    # explicit cleanup of stale generated files
    if os.path.isdir(SRC):
        for f in os.listdir(SRC):
            if not f.endswith(".xi"):
                continue
            p = os.path.join(SRC, f)
            with open(p, "r", encoding="utf-8", errors="replace") as fh:
                head = fh.read(200)
            if head.startswith("// GENERATED by tools/gen_sdl2.py"):
                os.remove(p)
    os.makedirs(SRC, exist_ok=True)
    os.makedirs(DOCS, exist_ok=True)
    for rel, text in emitted:
        dest = os.path.join(ROOT, rel)
        with open(dest, "w", encoding="utf-8", newline="\r\n") as f:
            f.write(text)

    # exports evidence + manifest
    with open(os.path.join(DOCS, "sdl2-exports.txt"), "w",
              encoding="ascii", newline="\n") as f:
        f.write("\n".join(exported) + "\n")

    constants_skipped_names = {}
    for (nm, hdr, why) in const_skips:
        constants_skipped_names.setdefault(why, 0)
        constants_skipped_names[why] += 1

    kinds = {"int": 0, "str": 0, "flt": 0}
    for name in const_emitted:
        k = table.raw[name][0]
        if k == "str":
            kinds["str"] += 1
        elif isinstance(table.cache.get(name), float):
            kinds["flt"] += 1
        else:
            kinds["int"] += 1

    # pin hashes: header set (all oracle headers, sorted) + export list + DLL
    hh = hashlib.sha256()
    for hdr in sorted(raw):
        with open(os.path.join(headers_dir, hdr), "rb") as f:
            data = f.read()
        hh.update(hdr.encode("ascii"))
        hh.update(b"\0")
        hh.update(data)
        hh.update(b"\0")
    headers_sha = hh.hexdigest()
    export_text = "\n".join(exported) + "\n"
    exports_sha = hashlib.sha256(export_text.encode("ascii")).hexdigest()
    dll_sha = ""
    if os.path.exists(dll):
        dh = hashlib.sha256()
        with open(dll, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                dh.update(chunk)
        dll_sha = dh.hexdigest()

    manifest = {
        "pin": {"tag": PIN, "commit": PIN_COMMIT, "dll": dll,
                "headers": headers_dir,
                "header_count": len(raw),
                "header_names": sorted(raw)},
        "hashes": {
            "headers_sha256": headers_sha,
            "exports_sha256": exports_sha,
            "dll_sha256": dll_sha,
        },
        "functions": {
            "declared": len(declared),
            "exported_sdl": len(exported),
            "bound": len(bound_names),
            "declared_not_exported": declared_not_exported,
            "exported_not_declared": exported_not_declared,
        },
        "constants": {
            "emitted": len(const_emitted),
            "kinds": kinds,
            "unevaluable": [{"name": n, "reason": r} for (n, r) in const_failed],
            "skipped_by_rule": constants_skipped_names,
        },
        "modules": {
            "src": sorted(os.path.basename(p) for (p, t) in emitted
                          if p.startswith("src/")),
            "entry": "sdl2.xi",
            "max_lines": max(len(t.splitlines()) for (p, t) in emitted),
        },
    }
    with open(os.path.join(DOCS, "gen_manifest.json"), "w",
              encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")

    # summary
    print("gen_sdl2: declared=%d exported=%d bound=%d"
          % (len(declared), len(exported), len(bound_names)))
    print("gen_sdl2: declared-not-exported=%d exported-not-declared=%d"
          % (len(declared_not_exported), len(exported_not_declared)))
    print("gen_sdl2: constants emitted=%d unevaluable=%d skipped_by_rule=%d"
          % (len(const_emitted), len(const_failed), len(const_skips)))
    print("gen_sdl2: modules=%d max_lines=%d"
          % (len(emitted), manifest["modules"]["max_lines"]))
    for (nm, r) in const_failed[:20]:
        print("  unevaluable: %s (%s)" % (nm, r))
    if len(declared_not_exported) <= 40:
        print("gen_sdl2: declared-not-exported: %s" % ", ".join(declared_not_exported))
    print("gen_sdl2: exported-not-declared: %s" % ", ".join(exported_not_declared))


if __name__ == "__main__":
    main()
