#!/usr/bin/env python3
# ============================================================================
# XIOM -- xiom.harfbuzz binding generator
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
# Licensed under the MIT or Apache-2.0 license, at your option.
# ============================================================================
#
# Regenerates the xiom.harfbuzz binding surface from the PINNED public
# headers in `vendor/harfbuzz/src` (harfbuzz 14.6.0 =
# c7a7457b7385f33178e8cf87615ca077a810bbe7; "Old MIT").
#
# DECLARED SURFACE (SPEC.md section 2): the include closure of hb.h,
# hb-ot.h, hb-subset.h and hb-version.h.  hb-ft.h / hb-gobject.h /
# hb-icu.h / hb-cairo.h are NOT reachable from the four roots (external
# dependencies) and stay out of the declared scope by construction.
#
# Emitted artifacts (all machine-generated; `--check` verifies no drift):
#   src/hb_gen_<header>.xi      one module per public header: value
#                               constants + extern "C" declarations for
#                               100% of the functions it declares
#   src/hb_gen_surface.xi       surface bookkeeping: per-header counts,
#                               total, ordered-name FNV-1a hash
#   src/hb_symbols_gen.c        address-of table over every declared
#                               function + name hash + null count (links
#                               only if 100% of the symbols exist)
#   docs/gen_manifest.json      machine-readable counts / lists
#   docs/COVERAGE.md            human coverage table (declared/bound/skips)
#
# Conventions (docs/BINDINGS-COMPILER-FINDINGS.md discipline, v0.64.4):
#   * pointers AND opaque handles cross as `Int` (B-25: never cast
#     `Int as *UInt8`; the Int-param path is faithful)
#   * C scalar ABI is preserved exactly: hb_bool_t/hb_position_t -> Int32,
#     hb_codepoint_t/hb_mask_t/hb_tag_t/... -> UInt32, float -> Float32
#   * no bare `null` reaches C from generated code (B-23)
#   * externs are declaration-only; functional work lives in the C bridge
#     with C writing into XIOM-owned slots (B-20/B-24)
#
# Usage:
#   python tools/gen_harfbuzz.py            # regenerate in place
#   python tools/gen_harfbuzz.py --check    # verify committed files match
# ============================================================================

import argparse
import hashlib
import json
import os
import re
import sys

PIN_COMMIT = "c7a7457b7385f33178e8cf87615ca077a810bbe7"
PIN_VERSION = "14.6.0"
ROOTS = ["hb.h", "hb-ot.h", "hb-subset.h", "hb-version.h"]

# Scalar ABI map (normalized type text -> XIOM type).  Everything with a
# `*` or a function-pointer shape maps to Int before this table is used.
SCALAR_MAP = {
    "void": None,
    "int": "Int32",
    "unsigned": "UInt32",
    "unsigned int": "UInt32",
    "int32_t": "Int32",
    "uint32_t": "UInt32",
    "int64_t": "Int64",
    "uint64_t": "UInt64",
    "float": "Float32",
    "double": "Float64",
    "hb_bool_t": "Int32",
    "hb_position_t": "Int32",
    "hb_codepoint_t": "UInt32",
    "hb_mask_t": "UInt32",
    "hb_tag_t": "UInt32",
    "hb_ot_tag_t": "UInt32",
    "hb_ot_name_id_t": "UInt32",
    "hb_color_t": "UInt32",
    "hb_var_int_t": "UInt32",
    "size_t": "UInt64",
    "uint8_t": "UInt8",
    "int8_t": "Int8",
    "uint16_t": "UInt16",
    "int16_t": "Int16",
    # MSVC keyword spellings (hb-common.h typedef branches after
    # preprocessor stripping; same widths as the stdint names).
    "__int8": "Int8",
    "__int16": "Int16",
    "__int32": "Int32",
    "__int64": "Int64",
}

# Headers parsed for CONSTANT RESOLUTION ONLY (enum values referenced by
# deprecated aliases in the declared closure; their functions are never
# emitted and stay out of the declared surface).
RESOLVE_ONLY_HEADERS = ["hb-aat-layout.h"]

QUALIFIERS = re.compile(r"\b(const|volatile|struct|enum|register|restrict)\b")

ATTR_MACROS = [
    re.compile(r"HB_DEPRECATED_FOR\s*\([^)]*\)"),
    re.compile(r"\bHB_DEPRECATED\b"),
]

HEADER_SHORT = {
    "hb.h": "hb",
    "hb-ot.h": "ot",
    "hb-subset.h": "subset",
    "hb-version.h": "version",
}


def strip_comments(text):
    # Replace comments with spaces, preserving newlines (line numbers stay).
    def block(m):
        return re.sub(r"[^\n]", " ", m.group(0))
    text = re.sub(r"/\*.*?\*/", block, text, flags=re.S)
    text = re.sub(r"//[^\n]*", lambda m: " " * len(m.group(0)), text)
    return text


def strip_preprocessor(text):
    # Drop full preprocessor lines (keeps offsets stable for line math).
    return re.sub(r"(?m)^[ \t]*#.*$", lambda m: " " * len(m.group(0)), text)


DIRECTIVE = re.compile(r"^[ \t]*#[ \t]*(if|ifdef|ifndef|elif|else|endif)\b(.*)$")

# Default-build values of the guards that gate declarations in the public
# headers.  Only these two macros change the DECLARED surface; every other
# conditional in the closure is an include guard, a platform branch, or an
# opt-out flag (HB_DISABLE_DEPRECATED) that stays off/on as noted.
#   HB_EXPERIMENTAL_API  -- undefined by default: its #ifdef branch is
#       opt-in and carries no default ABI.
#   HB_NO_SUBSET_DEPEND  -- DEFINED by default (hb-config.hh sets it
#       whenever HB_EXPERIMENTAL_API is undefined): the depend API is
#       absent from a default build.
DEFAULT_DEFINED = {
    "HB_NO_SUBSET_DEPEND": True,
    "HB_EXPERIMENTAL_API": False,
}


def strip_opt_in_regions(text):
    """Blank out `#ifdef HB_EXPERIMENTAL_API ... #endif` regions (nested
    aware; the #else branch of such a chain is kept).  Returns
    (kept_text, dropped_text)."""
    out = []
    dropped = []
    stack = []  # [{optin: bool, active_optin: bool}]
    for line in text.split("\n"):
        m = DIRECTIVE.match(line)
        if m:
            kind, rest = m.group(1), m.group(2)
            if kind in ("if", "ifdef", "ifndef"):
                name = rest.strip().split()[0] if rest.strip() else ""
                val = DEFAULT_DEFINED.get(name)
                if kind == "ifdef" and val is not None:
                    optin = not val
                elif kind == "ifndef" and val is not None:
                    optin = val
                else:
                    optin = False
                stack.append({"optin": optin, "active_optin": optin})
            elif kind == "else" and stack:
                stack[-1]["active_optin"] = not stack[-1]["optin"]
            elif kind == "elif" and stack:
                stack[-1]["active_optin"] = not stack[-1]["optin"]
            elif kind == "endif" and stack:
                stack.pop()
        dropping = any(e["active_optin"] for e in stack)
        if dropping:
            dropped.append(line)
            out.append(" " * len(line))
        else:
            out.append(line)
    return "\n".join(out), "\n".join(dropped)


def find_closure(src_dir):
    """Depth-first include closure of ROOTS over quoted local includes."""
    order = []
    seen = set()

    def visit(name):
        if name in seen:
            return
        path = os.path.join(src_dir, name)
        if not os.path.isfile(path):
            raise SystemExit("closure: missing include %s" % name)
        seen.add(name)
        order.append(name)
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            raw = f.read()
        body = strip_comments(raw)
        for m in re.finditer(r'#\s*include\s+"([^"]+)"', body):
            inc = m.group(1)
            if inc.endswith(".h"):
                visit(inc)
    for r in ROOTS:
        visit(r)
    return order


class ExprError(Exception):
    pass


class ConstEval(object):
    """Integer constant-expression evaluator (C subset used by HB headers)."""

    TOKEN = re.compile(r"""
        \s*(?:
          (?P<hex>0[xX][0-9a-fA-F]+)(?:[uUlL]*)
        | (?P<dec>\d+)(?:[uUlL]*)
        | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
        | (?P<chr>'(?:\\.|[^'\\])')
        | (?P<op><<|>>|<=|>=|==|!=|&&|\|\||[-+*/%&|^~!(),<>])
        )""", re.X)

    def __init__(self, env):
        self.env = env

    def eval(self, text):
        self.toks = []
        pos = 0
        while pos < len(text):
            m = self.TOKEN.match(text, pos)
            if not m:
                if text[pos:].strip() == "":
                    break
                raise ExprError("bad token at %r" % text[pos:pos + 20])
            pos = m.end()
            if m.group("hex") is not None:
                self.toks.append(("num", int(m.group("hex"), 16)))
            elif m.group("dec") is not None:
                self.toks.append(("num", int(m.group("dec"))))
            elif m.group("chr") is not None:
                s = m.group("chr")[1:-1]
                if s.startswith("\\"):
                    lut = {"n": 10, "t": 9, "r": 13, "0": 0, "\\": 92, "'": 39}
                    v = lut.get(s[1:])
                    if v is None:
                        raise ExprError("char escape %r" % s)
                else:
                    v = ord(s)
                self.toks.append(("num", v))
            elif m.group("name") is not None:
                self.toks.append(("name", m.group("name")))
            else:
                self.toks.append(("op", m.group("op")))
        self.i = 0
        v = self.parse_or()
        if self.i != len(self.toks):
            raise ExprError("trailing tokens")
        return v

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None)

    def eat(self, val=None):
        t = self.peek()
        if t[0] is None:
            raise ExprError("unexpected end")
        if val is not None and t[1] != val:
            raise ExprError("expected %r got %r" % (val, t[1]))
        self.i += 1
        return t

    def parse_or(self):
        v = self.parse_and()
        while self.peek()[1] == "|":
            self.eat("|")
            v |= self.parse_and()
        return v

    def parse_and(self):
        v = self.parse_xor()
        while self.peek()[1] == "&":
            self.eat("&")
            v &= self.parse_xor()
        return v

    def parse_xor(self):
        v = self.parse_add()
        while self.peek()[1] == "^":
            self.eat("^")
            v ^= self.parse_add()
        return v

    def parse_add(self):
        v = self.parse_mul()
        while self.peek()[1] in ("+", "-"):
            op = self.eat()[1]
            r = self.parse_mul()
            v = v + r if op == "+" else v - r
        return v

    def parse_mul(self):
        v = self.parse_shift()
        while self.peek()[1] in ("*", "/", "%"):
            op = self.eat()[1]
            r = self.parse_shift()
            if op == "*":
                v *= r
            elif r == 0:
                raise ExprError("division by zero")
            elif op == "/":
                v = int(v / r) if v >= 0 else -int((-v) / r)
            else:
                v = v % r
        return v

    def parse_shift(self):
        v = self.parse_unary()
        while self.peek()[1] in ("<<", ">>"):
            op = self.eat()[1]
            r = self.parse_unary()
            v = v << r if op == "<<" else v >> r
        return v

    def parse_unary(self):
        t = self.peek()
        if t[1] in ("-", "+", "~", "!"):
            op = self.eat()[1]
            v = self.parse_unary()
            if op == "-":
                return -v
            if op == "+":
                return v
            if op == "~":
                return ~v
            return 0 if v else 1
        return self.parse_primary()

    def parse_primary(self):
        t = self.eat()
        if t[0] == "num":
            return t[1]
        if t[0] == "name":
            name = t[1]
            if name == "HB_TAG":
                # HB_TAG(c1,c2,c3,c4) 4-char tag macro (function-like).
                self.eat("(")
                vals = []
                for k in range(4):
                    vals.append(self.parse_or() & 0xFF)
                    if k < 3:
                        self.eat(",")
                self.eat(")")
                return ((vals[0] << 24) | (vals[1] << 16) |
                        (vals[2] << 8) | vals[3]) & 0xFFFFFFFF
            try:
                return t[1] and self.env[name]
            except KeyError:
                raise ExprError("unknown identifier %s" % name)
        if t[1] == "(":
            # Distinguish a cast `(unsigned int) -1` from a group `(a | b)`.
            j = self.i
            depth = 1
            inner = []
            while j < len(self.toks) and depth > 0:
                tok = self.toks[j]
                if tok[1] == "(":
                    depth += 1
                elif tok[1] == ")":
                    depth -= 1
                if depth > 0:
                    inner.append(tok)
                j += 1
            if depth != 0:
                raise ExprError("unbalanced parens")
            is_cast = False
            if inner and all(t[0] == "name" for t in inner):
                is_cast = True
            if is_cast:
                cast_type = " ".join(t[1] for t in inner)
                self.i = j
                v = self.parse_unary()
                if "unsigned" in cast_type or cast_type in (
                        "hb_tag_t", "hb_codepoint_t", "hb_mask_t",
                        "uint32_t", "uint64_t", "hb_ot_tag_t"):
                    v &= 0xFFFFFFFF
                return v
            v = self.parse_or()
            self.eat(")")
            return v
        raise ExprError("unexpected token %r" % (t[1],))


def norm_type(t):
    t = t.strip()
    t = ATTR_MACROS[0].sub(" ", t)
    t = ATTR_MACROS[1].sub(" ", t)
    t = t.replace("*", " * ")
    t = QUALIFIERS.sub(" ", t)
    t = re.sub(r"\s+", " ", t).strip()
    t = t.replace(" *", "*").replace("* ", "*")
    return t


def map_c_type(t, enum_names, report):
    """Map a C parameter/return type text to an XIOM extern type."""
    n = norm_type(t)
    if n == "" or n == "void":
        return None
    n = resolve_alias(n, report)
    if n in report["fnptr_typedefs"] or n in report["ptr_typedefs"]:
        return "Int"                      # function-pointer / pointer typedef
    if "*" in n or "(" in n:
        return "Int"                      # pointer / function pointer (B-25)
    if n in SCALAR_MAP:
        return SCALAR_MAP[n]
    if n in enum_names:
        return "Int32"                    # C enum ABI (params/returns)
    report["unmapped_types"].add(n)
    return "Int"


def split_top_commas(s):
    out = []
    depth = 0
    cur = []
    for ch in s:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    if "".join(cur).strip():
        out.append("".join(cur))
    return out


def parse_functions(body, header, report):
    """Extract HB_EXTERN function declarations from comment-stripped,
    preprocessor-stripped header text."""
    funcs = []
    for m in re.finditer(r"\bHB_EXTERN\b", body):
        start = m.end()
        # find the terminating ';' at paren depth 0
        depth = 0
        i = start
        end = -1
        while i < len(body):
            c = body[i]
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            elif c == ";" and depth == 0:
                end = i
                break
            i += 1
        if end < 0:
            report["parse_errors"].append("%s: unterminated HB_EXTERN" % header)
            continue
        decl = body[start:end]
        # params opener = last top-level '(' in the declaration
        opens = []
        depth = 0
        for k, c in enumerate(decl):
            if c == "(":
                if depth == 0:
                    opens.append(k)
                depth += 1
            elif c == ")":
                depth -= 1
        if not opens:
            report["parse_errors"].append("%s: no parens: %r" % (header, decl[:60]))
            continue
        open_idx = opens[-1]
        pre = decl[:open_idx]
        nm = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*$", pre)
        if not nm:
            report["parse_errors"].append("%s: no name: %r" % (header, decl[:60]))
            continue
        name = nm.group(1)
        ret_text = pre[:nm.start()]
        params_text = decl[open_idx + 1:]
        # drop the (single) closing paren of the param list
        close = params_text.rfind(")")
        if close >= 0:
            params_text = params_text[:close]
        params = []
        for raw in split_top_commas(params_text):
            p = raw.strip()
            if not p or norm_type(p) == "void":
                continue
            params.append(p)
        funcs.append({
            "header": header,
            "name": name,
            "ret": ret_text.strip(),
            "params": params,
            "c_sig": re.sub(r"\s+", " ", decl).strip(),
        })
    return funcs


def parse_typedefs(body, header, report):
    """Classify typedef names that map to Int without further analysis:
    function-pointer typedefs, non-function pointer typedefs, and simple
    typedef aliases (resolved transitively by map_c_type)."""
    fnptr = set(re.findall(
        r"typedef\s+[^;{]*\(\s*\*\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*\([^;]*\);",
        body))
    ptr = set()
    for m in re.finditer(r"typedef\s+([^;{]*?)\s*\*\s*([A-Za-z_][A-Za-z0-9_]*)\s*;",
                         body):
        name = m.group(2)
        if name not in fnptr:
            ptr.add(name)
    for m in re.finditer(
            r"typedef\s+([A-Za-z_][A-Za-z0-9_]*)\s+([A-Za-z_][A-Za-z0-9_]*)\s*;",
            body):
        target, name = m.group(1), m.group(2)
        if target != name:
            report["typedef_alias"][name] = target
    report["fnptr_typedefs"].update(fnptr)
    report["ptr_typedefs"].update(ptr)
    return fnptr, ptr


def resolve_alias(n, report):
    seen = set()
    while n in report["typedef_alias"] and n not in seen:
        seen.add(n)
        n = report["typedef_alias"][n]
    return n


def parse_enums(body, header, env, report):
    """Yield (name, value, header) for every enum member; updates env."""
    members = []
    for m in re.finditer(
            r"typedef\s+enum\s*(?:[A-Za-z_][A-Za-z0-9_]*)?\s*\{([^}]*)\}\s*"
            r"([A-Za-z_][A-Za-z0-9_]*)\s*;", body):
        body_e, enum_name = m.group(1), m.group(2)
        report["enum_names"].add(enum_name)
        ev = ConstEval(env)
        prev = -1
        for raw in split_top_commas(body_e):
            item = raw.strip()
            if not item:
                continue
            if "=" in item:
                name, expr = item.split("=", 1)
                name = name.strip()
                expr = expr.strip()
                try:
                    val = ev.eval(expr)
                except ExprError as e:
                    report["pending"].append({
                        "kind": "enum", "name": name, "header": header,
                        "enum": enum_name, "text": expr, "err": str(e)})
                    continue
            else:
                name = item.strip()
                val = prev + 1
            prev = val
            env[name] = val
            members.append({"name": name, "value": val,
                            "enum": enum_name, "header": header})
    return members


def parse_defines(body, header, env, report):
    """Object-like #define value constants (int / string)."""
    consts = []
    # join continuations first
    joined = re.sub(r"\\\n", " ", body)
    for m in re.finditer(r"(?m)^[ \t]*#[ \t]*define[ \t]+"
                         r"([A-Za-z_][A-Za-z0-9_]*)(\([^)]*\))?[ \t]*(.*)$",
                         joined):
        name, arglist, value = m.group(1), m.group(2), m.group(3).strip()
        if arglist is not None:
            report["macro_defines"].append([name, header, "function-like"])
            continue
        if value == "":
            continue  # include guards
        sm = re.match(r'^"(.*)"\s*$', value)
        if sm:
            consts.append({"name": name, "kind": "str",
                           "value": sm.group(1), "header": header})
            continue
        try:
            v = ConstEval(env).eval(value)
        except ExprError as e:
            if value.startswith("{"):
                report["annotation_defines"].append(
                    [name, header, "struct initializer"])
            elif "__attribute__" in value or "__declspec" in value:
                report["annotation_defines"].append(
                    [name, header, "attribute"])
            elif re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", value) and \
                    value in env:
                consts.append({"name": name, "kind": "int",
                               "value": env[value], "header": header})
            else:
                report["pending"].append({
                    "kind": "define", "name": name, "header": header,
                    "text": value, "err": str(e)})
            continue
        env[name] = v
        consts.append({"name": name, "kind": "int", "value": v,
                       "header": header})
    return consts


def fnv1a32(names):
    h = 2166136261
    for nm in names:
        for ch in nm.encode("ascii"):
            h ^= ch
            h = (h * 16777619) & 0xFFFFFFFF
        h ^= 0x0A
        h = (h * 16777619) & 0xFFFFFFFF
    return h


def short_for(header):
    if header in HEADER_SHORT:
        return HEADER_SHORT[header]
    s = header
    if s.startswith("hb-"):
        s = s[3:]
    if s.endswith(".h"):
        s = s[:-2]
    return s.replace("-", "_")


def emit_module(out_dir, header, funcs, consts, report):
    short = short_for(header)
    mod = "xiom.harfbuzz.gen." + short
    # Resolver convention (repo-wide): module `a.b.c` lives in `src/c.xi`.
    path = os.path.join(out_dir, "src", "%s.xi" % short)
    L = []
    L.append("// GENERATED by tools/gen_harfbuzz.py -- do not edit.")
    L.append("// Source header: %s (harfbuzz %s = %s, Old MIT)."
             % (header, PIN_VERSION, PIN_COMMIT))
    L.append("// Declared surface: %d function(s), %d value constant(s)."
             % (len(funcs), len(consts)))
    L.append("// Pointers/handles cross as Int (B-25); scalar C ABI exact.")
    L.append("module %s" % mod)
    L.append("")
    L.append("pub const HB_GEN_%s_MODULE: Int = 1;"
             % short.upper())
    if consts:
        L.append("")
        L.append("// ---- value constants "
                 "(enum members + object-like #defines) ----")
        L.append("")
        for c in consts:
            if c.get("kind") == "str":
                L.append('pub const %s: Str = "%s";'
                         % (c["name"], c["value"].replace("\\", "\\\\")
                            .replace('"', '\\"')))
            else:
                v = c["value"]
                if v < 0:
                    v &= 0xFFFFFFFF
                L.append("pub const %s: Int = %d;" % (c["name"], v))
    if funcs:
        L.append("")
        L.append('extern "C" {')
        for f in funcs:
            ret = map_c_type(f["ret"], report["enum_names"], report)
            L.append("")
            L.append("  /// %s" % f["c_sig"])
            parts = []
            for k, p in enumerate(f["params"]):
                pt = map_c_type(param_type(p), report["enum_names"], report)
                parts.append("p%d: %s" % (k, pt))
            sig = ", ".join(parts)
            if ret is None:
                L.append("  fn %s(%s);" % (f["name"], sig))
            else:
                L.append("  fn %s(%s) -> %s;" % (f["name"], sig, ret))
        L.append("}")
    L.append("")
    data = "\n".join(L)
    write_or_check(path, data, report)
    return short, mod


def param_type(p):
    """C param text -> type text (strip parameter name)."""
    t = norm_type(p)
    m = re.search(r"([A-Za-z_][A-Za-z0-9_]*)$", t)
    if not m:
        return t
    return t[:m.start()].strip()


def write_or_check(path, data, report):
    if report["check"]:
        if not os.path.isfile(path):
            report["drift"].append("missing: %s" % path)
            return
        with open(path, "r", encoding="utf-8", newline="") as f:
            cur = f.read()
        if cur.replace("\r\n", "\n") != data.replace("\r\n", "\n"):
            report["drift"].append("stale: %s" % path)
        return
    d = os.path.dirname(path)
    if d and not os.path.isdir(d):
        os.makedirs(d)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(data)


def emit_surface(out_dir, header_funcs, all_funcs, report):
    total = len(all_funcs)
    names = [f["name"] for f in all_funcs]
    h = fnv1a32(names)
    L = []
    L.append("// GENERATED by tools/gen_harfbuzz.py -- do not edit.")
    L.append("// Surface bookkeeping for the pinned public headers.")
    L.append("module xiom.harfbuzz.gen.surface")
    L.append("")
    L.append("pub const HB_GEN_SURFACE_MODULE: Int = 1;")
    L.append("")
    L.append('/// Upstream harfbuzz release pin (SPEC.md section 2).')
    L.append('pub const HB_PIN_VERSION: Str = "%s";' % PIN_VERSION)
    L.append("")
    L.append("/// Upstream commit pin (shallow clone E:\\repos\\harfbuzz, tag %s)."
             % PIN_VERSION)
    L.append('pub const HB_PIN_COMMIT: Str = "%s";' % PIN_COMMIT)
    L.append("")
    L.append("/// Declared functions across the hb.h + hb-ot.h + hb-subset.h")
    L.append("/// + hb-version.h include closure (generation oracle).")
    L.append("pub const HB_SURFACE_TOTAL: Int = %d;" % total)
    L.append("")
    L.append("/// FNV-1a 32 of the ordered declared names "
             "(\\n-terminated, header order).")
    L.append("pub const HB_SURFACE_NAME_HASH: Int = %d;" % h)
    L.append("")
    for header in sorted(header_funcs, key=lambda x: x):
        short = short_for(header)
        L.append("/// Declared in %s." % header)
        L.append("pub const HB_SURFACE_%s: Int = %d;"
                 % (short.upper(), len(header_funcs[header])))
        L.append("")
    L.append("/// Ordinal of the last function (sanity: == TOTAL - 1).")
    L.append("pub const HB_SURFACE_LAST_ORDINAL: Int = %d;"
             % (total - 1))
    L.append("")
    write_or_check(os.path.join(out_dir, "src", "surface.xi"),
                   "\n".join(L), report)


def emit_symbols(out_dir, all_funcs, report):
    L = []
    L.append("/* GENERATED by tools/gen_harfbuzz.py -- do not edit.")
    L.append(" *")
    L.append(" * Address-of table over every function declared by the pinned")
    L.append(" * public headers (harfbuzz %s = %s)." % (PIN_VERSION, PIN_COMMIT))
    L.append(" *")
    L.append(" * This translation unit ONLY links when 100%% of the declared")
    L.append(" * surface exists in the vendored amalgam -- the binding proof")
    L.append(" * consumed by tests/test_conformance.xi (count + name hash +")
    L.append(" * null scan).")
    L.append(" */")
    L.append("")
    L.append('#include "../vendor/harfbuzz/src/hb.h"')
    L.append('#include "../vendor/harfbuzz/src/hb-ot.h"')
    L.append('#include "../vendor/harfbuzz/src/hb-subset.h"')
    L.append("")
    L.append("#include <stdint.h>")
    L.append("")
    L.append("typedef struct xhb_symbol_t {")
    L.append("  const char *name;")
    L.append("  const void *addr;")
    L.append("} xhb_symbol_t;")
    L.append("")
    L.append("static const xhb_symbol_t xhb_symbols[] = {")
    for f in all_funcs:
        L.append('  { "%s", (const void *) &%s },' % (f["name"], f["name"]))
    L.append("};")
    L.append("")
    L.append("int32_t xhb_symbol_count(void) {")
    L.append("  return (int32_t) (sizeof(xhb_symbols) / sizeof(xhb_symbols[0]));")
    L.append("}")
    L.append("")
    L.append("int32_t xhb_symbol_null_count(void) {")
    L.append("  int32_t n = 0;")
    L.append("  for (unsigned int i = 0; i < sizeof(xhb_symbols) / sizeof(xhb_symbols[0]); i++)")
    L.append("    if (xhb_symbols[i].addr == 0) n++;")
    L.append("  return n;")
    L.append("}")
    L.append("")
    L.append("uint32_t xhb_symbol_name_hash(void) {")
    L.append("  uint32_t h = 2166136261u;")
    L.append("  for (unsigned int i = 0; i < sizeof(xhb_symbols) / sizeof(xhb_symbols[0]); i++) {")
    L.append("    for (const char *p = xhb_symbols[i].name; *p; p++) {")
    L.append("      h ^= (uint32_t) (unsigned char) *p;")
    L.append("      h *= 16777619u;")
    L.append("    }")
    L.append("    h ^= 0x0A;")
    L.append("    h *= 16777619u;")
    L.append("  }")
    L.append("  return h;")
    L.append("}")
    L.append("")
    write_or_check(os.path.join(out_dir, "src", "hb_symbols_gen.c"),
                   "\n".join(L), report)


def emit_manifest(out_dir, report):
    man = {
        "pin": {"version": PIN_VERSION, "commit": PIN_COMMIT},
        "declared_functions": report["total_functions"],
        "declared_function_name_hash": report["name_hash"],
        "per_header": report["per_header"],
        "value_constants": report["const_count"],
        "unresolved": report["unresolved"],
        "macro_defines": report["macro_defines"],
        "annotation_defines": report["annotation_defines"],
        "parse_errors": report["parse_errors"],
        "unmapped_types": sorted(report["unmapped_types"]),
        "closure_headers": report["closure"],
        "opt_in_excluded": sorted(report["opt_in_excluded"]),
    }
    data = json.dumps(man, indent=2, sort_keys=True) + "\n"
    write_or_check(os.path.join(out_dir, "docs", "gen_manifest.json"),
                   data, report)


def emit_coverage(out_dir, report):
    L = []
    L.append("<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->")
    L.append("<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->")
    L.append("# COVERAGE: xiom.harfbuzz -- declared vs bound vs skips")
    L.append("")
    L.append("Generated by `tools/gen_harfbuzz.py` from the pinned headers "
             "(harfbuzz %s," % PIN_VERSION)
    L.append("commit `%s`); source of truth: `docs/gen_manifest.json`." % PIN_COMMIT)
    L.append("")
    L.append("**Declared surface** = the include closure of hb.h + hb-ot.h + "
             "hb-subset.h + hb-version.h")
    L.append("(%d headers). hb-ft.h / hb-gobject.h / hb-icu.h / hb-cairo.h "
             "are not reachable from" % len(report["closure"]))
    L.append("the four roots (external dependencies) and are out of declared "
             "scope by construction.")
    L.append("")
    L.append("## Functions: declared / bound / skips")
    L.append("")
    L.append("| Header | Declared | Bound (extern) | Skips |")
    L.append("|---|---|---|---|")
    skips = 0
    for header in report["closure"]:
        n = len(report["per_header"].get(header, []))
        L.append("| %s | %d | %d | 0 |" % (header, n, n))
    L.append("| **total** | **%d** | **%d** | **%d** |"
             % (report["total_functions"], report["total_functions"], skips))
    L.append("")
    L.append("Every declared function is emitted as an XIOM `extern \"C\"` "
             "declaration and its")
    L.append("address is taken in `src/hb_symbols_gen.c`, so the suite links "
             "only when 100%%")
    L.append("of the symbols exist in the vendored amalgam (count + FNV-1a "
             "name hash + null scan).")
    L.append("")
    if report["opt_in_excluded"]:
        L.append("`HB_EXPERIMENTAL_API`-gated declarations are NOT part of "
                 "the declared surface")
        L.append("(opt-in macro; not declared/compiled in a default build, "
                 "no ABI promise): %d"
                 % len(report["opt_in_excluded"]))
        for n in sorted(report["opt_in_excluded"]):
            L.append("- `%s`" % n)
        L.append("")
    L.append("## Value constants")
    L.append("")
    L.append("| Kind | Count |")
    L.append("|---|---|")
    L.append("| enum members + object-like #defines "
             "(int/string) | %d |" % report["const_count"])
    L.append("| function-like / annotation macros (not value constants) | %d |"
             % (len(report["macro_defines"]) +
                len(report["annotation_defines"])))
    L.append("| unresolved value expressions | %d |" % len(report["unresolved"]))
    L.append("")
    if report["unresolved"]:
        L.append("### Unresolved value expressions")
        L.append("")
        for item in report["unresolved"]:
            L.append("- `%s` (%s): `%s` (%s)" % tuple(item))
        L.append("")
    L.append("## Verification")
    L.append("")
    L.append("`python tools/gen_harfbuzz.py --check` fails on any drift "
             "between the pinned")
    L.append("headers and the committed generated artifacts. The conformance "
             "suite asserts")
    L.append("`HB_SURFACE_TOTAL == xhb_symbol_count()` and that the C-side "
             "FNV-1a name hash")
    L.append("equals `HB_SURFACE_NAME_HASH` (declaration order fixed by the "
             "generator).")
    L.append("")
    write_or_check(os.path.join(out_dir, "docs", "COVERAGE.md"),
                   "\n".join(L), report)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="verify generated files match (no writes)")
    ap.add_argument("--package", default=None,
                    help="package dir (default: parent of this script)")
    args = ap.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    pkg = args.package or os.path.dirname(here)
    src_dir = os.path.join(pkg, "vendor", "harfbuzz", "src")
    if not os.path.isdir(src_dir):
        raise SystemExit("vendor headers not found: %s" % src_dir)

    report = {
        "check": args.check,
        "drift": [],
        "parse_errors": [],
        "unresolved": [],
        "pending": [],
        "macro_defines": [],
        "annotation_defines": [],
        "unmapped_types": set(),
        "enum_names": set(),
        "fnptr_typedefs": set(),
        "ptr_typedefs": set(),
        "typedef_alias": {},
        "opt_in_excluded": [],
        "per_header": {},
    }

    closure = find_closure(src_dir)
    report["closure"] = closure

    env = {}
    enums = []
    defines = []
    header_funcs = {}
    by_header_consts = {h: [] for h in closure}
    all_funcs = []
    seen_funcs = {}

    def consume_header(header, emit):
        with open(os.path.join(src_dir, header), "r",
                  encoding="utf-8", errors="replace") as f:
            raw = f.read()
        body_c = strip_comments(raw)
        body_c, dropped = strip_opt_in_regions(body_c)
        if dropped.strip():
            scratch = {"parse_errors": [], "unresolved": []}
            for f2 in parse_functions(strip_preprocessor(dropped),
                                      header, scratch):
                if f2["name"] not in report["opt_in_excluded"]:
                    report["opt_in_excluded"].append(f2["name"])
        body = strip_preprocessor(body_c)
        parse_typedefs(body, header, report)
        # defines first: object-like value constants (HB_TAG_NONE,
        # HB_TAG_MAX_SIGNED, HB_VERSION_*) feed enum expressions.
        ds = parse_defines(body_c, header, env, report)
        hs = parse_enums(body, header, env, report)
        if emit:
            defines.extend(ds)
            enums.extend(hs)
            by_header_consts[header].extend(hs)
            by_header_consts[header].extend(
                [d for d in ds if d["header"] == header])
            funcs = parse_functions(body, header, report)
            for f in funcs:
                if f["name"] in seen_funcs:
                    report["parse_errors"].append(
                        "duplicate function %s (%s + %s)"
                        % (f["name"], seen_funcs[f["name"]], header))
                    continue
                seen_funcs[f["name"]] = header
                all_funcs.append(f)
            header_funcs[header] = funcs

    for header in closure:
        consume_header(header, emit=True)
    for header in RESOLVE_ONLY_HEADERS:
        if header not in closure:
            consume_header(header, emit=False)

    # Fixpoint: forward-referenced constants (headers reference values
    # defined by later headers -- e.g. hb-ot-deprecated.h -> hb-ot-math.h).
    pending = report["pending"]
    for _ in range(16):
        again = []
        for item in pending:
            try:
                v = ConstEval(env).eval(item["text"])
            except ExprError:
                again.append(item)
                continue
            env[item["name"]] = v
            if item["kind"] == "enum":
                by_header_consts[item["header"]].append(
                    {"name": item["name"], "value": v,
                     "enum": item["enum"], "header": item["header"]})
            else:
                by_header_consts[item["header"]].append(
                    {"name": item["name"], "kind": "int", "value": v,
                     "header": item["header"]})
        if not again:
            pending = []
            break
        if len(again) == len(pending):
            pending = again
            break
        pending = again
    for item in pending:
        if item["kind"] == "define" and re.match(
                r"^HB_(EXTERN|BEGIN_DECLS|END_DECLS|DEPRECATED)",
                item["name"]):
            report["annotation_defines"].append(
                [item["name"], item["header"], item["text"][:60]])
        else:
            report["unresolved"].append(
                [item["name"], item["header"], item["text"], item["err"]])

    # constants not attributable to a closure header cannot happen; guard
    report["per_header"] = {h: [f["name"] for f in header_funcs[h]]
                            for h in closure}
    report["total_functions"] = len(all_funcs)
    report["name_hash"] = fnv1a32([f["name"] for f in all_funcs])
    report["const_count"] = sum(len(v) for v in by_header_consts.values())

    for header in closure:
        emit_module(pkg, header, header_funcs[header],
                    by_header_consts[header], report)
    emit_surface(pkg, header_funcs, all_funcs, report)
    emit_symbols(pkg, all_funcs, report)
    emit_manifest(pkg, report)
    emit_coverage(pkg, report)

    print("gen_harfbuzz: %s" % ("check" if args.check else "generate"))
    print("  closure headers: %d" % len(closure))
    print("  declared functions: %d (hash %d)"
          % (report["total_functions"], report["name_hash"]))
    print("  value constants: %d" % report["const_count"])
    print("  unresolved value expressions: %d" % len(report["unresolved"]))
    for item in report["unresolved"]:
        print("    UNRESOLVED %s (%s): %s" % (item[0], item[1], item[2]))
    print("  unmapped type texts: %d" % len(report["unmapped_types"]))
    for t in sorted(report["unmapped_types"]):
        print("    UNMAPPED %s" % t)
    print("  parse errors: %d" % len(report["parse_errors"]))
    for e in report["parse_errors"]:
        print("    ERROR %s" % e)
    if args.check:
        for d in report["drift"]:
            print("  DRIFT %s" % d)
    if report["drift"] or report["parse_errors"]:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
