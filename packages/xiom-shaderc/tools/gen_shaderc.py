#!/usr/bin/env python3
# XIOM -- xiom.shaderc binding generator.
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Parses the pinned shaderc C headers and emits the XIOM binding modules:
#
#   shaderc.xi                    (module xiom.shaderc)
#       load error type, ShadercLibrary symbol table, shaderc_load() resolver,
#       one typed wrapper per SHADERC_EXPORT function, plus the owned-slot
#       decode helpers for the pointer-out / pointer-return functions.
#   src/shaderc_symbols.xi        (module xiom.shaderc.symbols)
#       ordered symbol-name table + count (the runtime resolve oracle).
#   src/shaderc_constants.xi      (module xiom.shaderc.constants)
#       every enum value from shaderc.h / env.h / status.h as `pub const`.
#
# The emitted wrapper shape follows the bindings-lane discipline (B-11..B-20):
# every C call lives in a small `unsafe` block inside module xiom.shaderc,
# out-params use XIOM-owned Vec[UInt8] slots created per call (never reused
# across calls), no raw pointer arithmetic (Int address math only), binary
# data is copied into owned slots with ffi.memcpy and read byte-indexed, and
# C strings cross as `Str`.
#
# The oracle is the pinned header set itself:
#   C:\VulkanSDK\1.4.350.0\Include\shaderc\{shaderc,env,status,visibility}.h
# which git-blob-matches upstream google/shaderc tag v2026.4 (see SPEC.md and
# PROVENANCE.md). Regenerate with:
#   python tools/gen_shaderc.py
#
import hashlib
import os
import re
import sys

DEFAULT_HEADER_DIR = r"C:\VulkanSDK\1.4.350.0\Include\shaderc"
HEADER_FILES = ["shaderc.h", "env.h", "status.h", "visibility.h"]
PACKAGE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    return text


def read_header(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return strip_comments(fh.read())


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        h.update(fh.read())
    return h.hexdigest().upper()


def split_params(params_text):
    """Split a C parameter list on commas at paren depth 0."""
    items = []
    depth = 0
    cur = ""
    for ch in params_text:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            items.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        items.append(cur)
    return [p.strip() for p in items if p.strip()]


def parse_declarator(param_text):
    """Return (base_type, name) for a C parameter declaration."""
    text = re.sub(r"\s+", " ", param_text).strip()
    if "(*" in text or "(" in text:
        return (text, "")
    words = text.rsplit(" ", 1)
    if len(words) == 1:
        return (text, "")
    base, name = words[0], words[1]
    name = name.strip().lstrip("*")
    if base.endswith("*") and not name:
        return (base, "")
    return (base, name)


def parse_functions(text):
    """Parse every `SHADERC_EXPORT <ret> <name>(<params>);` declaration."""
    pat = re.compile(r"SHADERC_EXPORT\s+(.+?)\b([A-Za-z_]\w*)\s*\(([^;]*?)\)\s*;", re.S)
    out = []
    for m in pat.finditer(text):
        ret_raw = re.sub(r"\s+", " ", m.group(1)).strip()
        name = m.group(2)
        params = []
        for ptext in split_params(m.group(3)):
            if re.sub(r"\s+", " ", ptext).strip() in ("void", ""):
                continue
            base, pname = parse_declarator(ptext)
            params.append({"raw": re.sub(r"\s+", " ", ptext).strip(), "base": base, "name": pname})
        out.append({"name": name, "ret": ret_raw, "params": params})
    return out


class ExprEval:
    """Tiny integer expression evaluator for C enum initializers."""

    def __init__(self, expr, env):
        self.s = expr.strip()
        self.i = 0
        self.env = env

    def peek(self):
        return self.s[self.i] if self.i < len(self.s) else ""

    def skip_ws(self):
        while self.i < len(self.s) and self.s[self.i].isspace():
            self.i += 1

    def parse(self):
        v = self.parse_or()
        self.skip_ws()
        if self.i != len(self.s):
            raise ValueError("trailing input in enum expr: " + self.s)
        return v

    def parse_or(self):
        v = self.parse_shift()
        while True:
            self.skip_ws()
            if self.peek() == "|":
                self.i += 1
                v = v | self.parse_shift()
            else:
                return v

    def parse_shift(self):
        v = self.parse_primary()
        while True:
            self.skip_ws()
            if self.s.startswith("<<", self.i):
                self.i += 2
                v = v << self.parse_primary()
            else:
                return v

    def parse_primary(self):
        self.skip_ws()
        if self.peek() == "(":
            self.i += 1
            v = self.parse_or()
            self.skip_ws()
            if self.peek() != ")":
                raise ValueError("missing ) in enum expr: " + self.s)
            self.i += 1
            return v
        if self.peek().isdigit():
            j = self.i
            while self.i < len(self.s) and (self.s[self.i].isalnum() or self.s[self.i] == "x"):
                self.i += 1
            tok = self.s[j:self.i]
            tok = tok.rstrip("uUlL")
            return int(tok, 0)
        if self.peek().isalpha() or self.peek() == "_":
            j = self.i
            while self.i < len(self.s) and (self.s[self.i].isalnum() or self.s[self.i] == "_"):
                self.i += 1
            tok = self.s[j:self.i]
            if tok not in self.env:
                raise ValueError("unknown identifier in enum expr: " + tok)
            return self.env[tok]
        raise ValueError("cannot parse enum expr at %d: %s" % (self.i, self.s))


ENUM_RE = re.compile(r"enum(?:\s+[A-Za-z_]\w*)?\s*\{(.*?)\}\s*(?:[A-Za-z_]\w*\s*)?;", re.S)


def parse_enums(text):
    """Return [(enumerator_name, value)] in declaration order."""
    out = []
    env = {}
    for m in ENUM_RE.finditer(text):
        body = m.group(1)
        body = body.replace(",\n", ",")
        items = []
        depth = 0
        cur = ""
        for ch in body:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            if ch == "," and depth == 0:
                items.append(cur)
                cur = ""
            else:
                cur += ch
        if cur.strip():
            items.append(cur)
        next_val = 0
        for item in items:
            item = item.strip()
            if not item:
                continue
            if "=" in item:
                name, expr = item.split("=", 1)
                name = name.strip()
                value = ExprEval(expr, env).parse()
                next_val = value + 1
            else:
                name = item
                value = next_val
                next_val = value + 1
            env[name] = value
            out.append((name, value))
    return out


# ---------------------------------------------------------------------------
# Type mapping
# ---------------------------------------------------------------------------


def normalize_type(t):
    t = re.sub(r"\s+", " ", t).strip()
    t = t.replace("const ", "").replace("struct ", "")
    if t.endswith("*") and "*" in t[:-1]:
        t = t[:-1].rstrip() + "*"
    return t


def classify_param(p):
    t = normalize_type(p["base"])
    if t == "char*":
        return "str"
    if t == "size_t":
        return "size"
    if t in ("int", "uint32_t", "unsigned int"):
        return "int"
    if t == "bool":
        return "bool"
    if t.endswith("*"):
        return "out"
    return "int"  # opaque handles, enums, fn-pointer typedefs, void*


def abi_type(role, ret=False):
    if role == "str":
        return "*UInt8"
    if role == "bool":
        return "UInt8" if not ret else "UInt8"
    if role == "handle":
        return "Int"
    return "Int"


HANDLE_SUFFIX = ("_compiler_t", "_compile_options_t", "_compilation_result_t")


def is_handle_type(t):
    t = normalize_type(t)
    return t.endswith(HANDLE_SUFFIX)


def map_params(fn):
    """Map C params to XIOM wrapper params plus the C call argument list.

    Returns (sig_params, call_args, bool_locals):
      sig_params  -- XIOM-visible parameters (Str / Int / Bool)
      call_args   -- C-ABI argument expressions in declaration order
      bool_locals -- Bool params needing a 0/1 UInt8 local before the call
    """
    sig = []
    args = []
    bool_locals = []
    last_str = None
    for p in fn["params"]:
        role = classify_param(p)
        if role == "str":
            name = p["name"] if p["name"] else "input"
            if name == "str":
                name = "input"
            sig.append({"role": "str", "name": name, "type": "Str"})
            args.append(name + ".c_str()")
            last_str = name
            continue
        if role == "size":
            name = p["name"]
            if last_str is not None and name and (name.endswith("_length") or name.endswith("_size")):
                args.append(last_str + ".len()")
            else:
                sig.append({"role": "int", "name": name, "type": "Int"})
                args.append(name)
            continue
        if role == "bool":
            name = p["name"]
            sig.append({"role": "bool", "name": name, "type": "Bool"})
            args.append("b_" + name)
            bool_locals.append(name)
            continue
        if role == "out":
            name = p["name"]
            sig.append({"role": "out", "name": name, "type": "Int"})
            args.append(name)
            continue
        name = p["name"] if p["name"] else derive_param_name(p["base"])
        sig.append({"role": "int", "name": name, "type": "Int"})
        args.append(name)
    return sig, args, bool_locals


def derive_param_name(base_type):
    """Name an unnamed C parameter from its type (e.g. shaderc_compiler_t)."""
    t = normalize_type(base_type)
    t = t.lstrip("*")
    if t.startswith("shaderc_"):
        t = t[len("shaderc_"):]
    if t.endswith("_t"):
        t = t[:-2]
    t = re.sub(r"[^A-Za-z0-9_]", "_", t)
    return t if t else "arg"


def map_return(fn):
    t = normalize_type(fn["ret"])
    if t == "void":
        return ("unit", "Unit", None)
    if t == "char*":
        return ("str", "Str", None)
    if t == "bool":
        return ("bool", "Bool", "UInt8")
    if is_handle_type(t):
        return ("int", "Int", "Int")
    if t == "size_t":
        return ("int", "Int", "Int")
    return ("int", "Int", "Int")


# ---------------------------------------------------------------------------
# Emission
# ---------------------------------------------------------------------------

BANNER = """// XIOM -- {title}
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// GENERATED FILE -- do not edit by hand.
// Source: tools/gen_shaderc.py
// Oracle: C:\\VulkanSDK\\1.4.350.0\\Include\\shaderc (shaderc,env,status,visibility).h
// Pinned upstream: google/shaderc v2026.4 (see SPEC.md / PROVENANCE.md).
// Regenerate: python tools/gen_shaderc.py
"""


def emit_symbols(functions, path):
    lines = []
    lines.append(BANNER.format(title="xiom.shaderc.symbols -- generated symbol-name oracle"))
    lines.append("")
    lines.append("module xiom.shaderc.symbols")
    lines.append("")
    lines.append("/// Number of shaderc C entry points declared by the pinned headers")
    lines.append("/// (the oracle N; equals the SHADERC_EXPORT declaration count).")
    lines.append("pub const SHADERC_SYMBOL_COUNT: Int = %d;" % len(functions))
    lines.append("")
    lines.append("/// Oracle function name at `index` (declaration order of the pinned")
    lines.append("/// headers); \"\" for an out-of-range index.")
    lines.append("/// Complexity: O(1).")
    lines.append("pub fn shaderc_symbol_name(index: Int) -> Str")
    lines.append("  requires: index >= 0")
    lines.append("{")
    for i, fn in enumerate(functions):
        lines.append('  if index == %d { return "%s"; }' % (i, fn["name"]))
    lines.append('  return "";')
    lines.append("}")
    lines.append("")
    write_file(path, lines)


def emit_constants(constants, path):
    lines = []
    lines.append(BANNER.format(title="xiom.shaderc.constants -- generated enum constants"))
    lines.append("")
    lines.append("module xiom.shaderc.constants")
    lines.append("")
    lines.append("/// Number of enum constants bound from the pinned headers.")
    lines.append("pub const SHADERC_CONSTANT_COUNT: Int = %d;" % len(constants))
    lines.append("")
    prev_family = None
    for name, value in constants:
        family = name.split("_")[1] if "_" in name else name
        if family != prev_family:
            lines.append("// ---- shaderc_%s ----" % family)
            prev_family = family
        lines.append("pub const %s: Int = %d;" % (name, value))
    lines.append("")
    write_file(path, lines)


def wrapper_lines(fn):
    """Emit one typed wrapper for a C function."""
    sig, args, bool_locals = map_params(fn)
    rkind, rtype, rabi = map_return(fn)
    short = fn["name"]
    if short.startswith("shaderc_"):
        short = short[len("shaderc_"):]
    lines = []
    sig_params = ["lib: &ShadercLibrary"]
    for p in sig:
        sig_params.append("%s: %s" % (p["name"], p["type"]))
    lines.append("#[unsafe_direct]")
    lines.append("pub fn %s(%s) -> %s" % (fn["name"], ", ".join(sig_params), rtype))
    lines.append("  requires: lib.handle != 0")
    lines.append("{")
    lines.append("  unsafe {")
    cast_params = ", ".join(abi_type(classify_param(p)) for p in fn["params"])
    if rkind == "unit":
        cast_ret = ""
    elif rkind == "str":
        cast_ret = " -> *UInt8"
    else:
        cast_ret = " -> " + rabi
    lines.append("    let f_%s = lib.p_%s as fn(%s)%s;" % (short, fn["name"], cast_params, cast_ret))
    for name in bool_locals:
        lines.append("    let b_%s: UInt8 = if %s { 1 as UInt8 } else { 0 as UInt8 };" % (name, name))
    call = "f_%s(%s)" % (short, ", ".join(args))
    if rkind == "unit":
        lines.append("    %s;" % call)
    elif rkind == "bool":
        lines.append("    return (%s as Int) != 0;" % call)
    elif rkind == "str":
        lines.append("    let p = %s;" % call)
        lines.append("    if (p as Int) == 0 { return \"\"; }")
        lines.append("    return Str::from_c_str(p);")
    else:
        lines.append("    return %s as Int;" % call)
    lines.append("  }")
    lines.append("}")
    lines.append("")
    return lines


DECODE_HELPERS = """
// =========================================================================
// Owned-slot decode helpers (B-11..B-20 shape): each helper creates fresh
// XIOM-owned 4-byte slots per call (never reuses slot memory across calls),
// lets C write through the slot pointers, then reads byte-indexed.  Binary
// output is copied into an owned Vec with ffi.memcpy before any byte-level
// read; no foreign pointer is ever read directly.
// =========================================================================

fn shaderc_slot4() -> Vec[UInt8] {
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 4 {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn shaderc_read_u32(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 4
{
  return (buf[0] as Int) | ((buf[1] as Int) << 8) | ((buf[2] as Int) << 16) | ((buf[3] as Int) << 24);
}

/// shaderc_get_spv_version decoded: the version/revision the compiler emits.
pub type ShadercSpvVersion = {
  version: Int;
  revision: Int;
}

#[unsafe_direct]
/// Decoded shaderc_get_spv_version() -- two owned slots, one per out-param.
/// Complexity: O(1).
pub fn shaderc_get_spv_version_values(lib: &ShadercLibrary) -> ShadercSpvVersion
  requires: lib.handle != 0
{
  unsafe {
    let f_ver = lib.p_shaderc_get_spv_version as fn(Int, Int);
    var vslot = shaderc_slot4();
    var rslot = shaderc_slot4();
    let va = vslot.as_mut_ptr() as Int;
    let ra = rslot.as_mut_ptr() as Int;
    f_ver(va, ra);
    return ShadercSpvVersion{ version: shaderc_read_u32(&vslot), revision: shaderc_read_u32(&rslot) };
  }
}

/// shaderc_parse_version_profile decoded outcome.
pub type ShadercVersionProfile = {
  ok: Bool;
  version: Int;
  profile: Int;
}

#[unsafe_direct]
/// Decoded shaderc_parse_version_profile() -- two owned slots, one per
/// out-param, fresh per call.
/// Complexity: O(len).
pub fn shaderc_parse_version_profile_values(lib: &ShadercLibrary, input: Str) -> ShadercVersionProfile
  requires: lib.handle != 0
{
  unsafe {
    let f_parse = lib.p_shaderc_parse_version_profile as fn(*UInt8, Int, Int) -> UInt8;
    var vslot = shaderc_slot4();
    var pslot = shaderc_slot4();
    let va = vslot.as_mut_ptr() as Int;
    let pa = pslot.as_mut_ptr() as Int;
    let ok = f_parse(input.c_str(), va, pa);
    return ShadercVersionProfile{ ok: (ok as Int) != 0, version: shaderc_read_u32(&vslot), profile: shaderc_read_u32(&pslot) };
  }
}

#[unsafe_direct]
/// First 32-bit word of a result's SPIR-V binary (the module magic 0x07230203
/// for SPIR-V output) -- the byte-level readback proof.
/// Complexity: O(1).
pub fn shaderc_result_first_word(lib: &ShadercLibrary, result: Int) -> Int
  requires: lib.handle != 0
  requires: result != 0
{
  unsafe {
    let f_bytes = lib.p_shaderc_result_get_bytes as fn(Int) -> *UInt8;
    let f_len = lib.p_shaderc_result_get_length as fn(Int) -> Int;
    if f_len(result) < 4 { return 0; }
    let p = f_bytes(result);
    if (p as Int) == 0 { return 0; }
    var buf = shaderc_slot4();
    ffi.memcpy(buf.as_mut_ptr(), (p as Int) as *UInt8, 4);
    return shaderc_read_u32(&buf);
  }
}

#[unsafe_direct]
/// Copy up to `max_bytes` of a result's output into an XIOM-owned Vec.
/// Complexity: O(n).
pub fn shaderc_result_copy_bytes(lib: &ShadercLibrary, result: Int, max_bytes: Int) -> Vec[UInt8]
  requires: lib.handle != 0
  requires: result != 0
  requires: max_bytes >= 0
{
  unsafe {
    let f_bytes = lib.p_shaderc_result_get_bytes as fn(Int) -> *UInt8;
    let f_len = lib.p_shaderc_result_get_length as fn(Int) -> Int;
    let total = f_len(result);
    if total <= 0 { return Vec[UInt8].new(); }
    let p = f_bytes(result);
    if (p as Int) == 0 { return Vec[UInt8].new(); }
    var n = total;
    if n > max_bytes { n = max_bytes; }
    // NOTE: push loop, NOT Vec.with_len -- with_len has a zero-fill overflow
    // on this toolchain (see AUDIT.md, "Vec.with_len finding"); the pushed
    // buffer is sized to n elements and the memcpy writes exactly n bytes.
    var buf: Vec[UInt8] = Vec[UInt8].new();
    var j: Int = 0;
    while j < n {
      buf.push(0 as UInt8);
      j = j + 1;
    }
    ffi.memcpy(buf.as_mut_ptr(), (p as Int) as *UInt8, n);
    return buf;
  }
}

#[unsafe_direct]
/// Text output of a result (SPIR-V assembly / preprocessed source), read as
/// the NUL-terminated C string the result holds.
/// Complexity: O(len).
pub fn shaderc_result_get_text(lib: &ShadercLibrary, result: Int) -> Str
  requires: lib.handle != 0
  requires: result != 0
{
  unsafe {
    let f_bytes = lib.p_shaderc_result_get_bytes as fn(Int) -> *UInt8;
    let p = f_bytes(result);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}
"""


def emit_module(functions, path):
    lines = []
    lines.append(BANNER.format(title="xiom.shaderc -- shaderc C API bindings (dynamic loader)"))
    lines.append("//")
    lines.append("// DESIGN: dynamic loader path.  The package does NOT link shaderc at")
    lines.append("// build time.  shaderc_load() resolves shaderc_shared.dll through")
    lines.append("// xiom.ffi.dl at runtime and every call goes through fn-pointer casts")
    lines.append("// inside this module -- the only module in the package with `unsafe`.")
    lines.append("// When the DLL is absent the suite reports SKIP (green); a present DLL")
    lines.append("// missing an oracle symbol reports an ABI failure naming the symbol.")
    lines.append("")
    lines.append("module xiom.shaderc")
    lines.append("")
    lines.append("use xiom.ffi;")
    lines.append("use xiom.ffi.dl;")
    lines.append("")
    lines.append("/// Runtime library name resolved by the loader (Windows soname).")
    lines.append('pub const SHADERC_SONAME: Str = "shaderc_shared.dll";')
    lines.append("")
    lines.append("/// Failure modes of `shaderc_load`: library absent (callers SKIP) vs")
    lines.append("/// present-but-ABI-mismatched (callers FAIL).")
    lines.append("pub const SHADERC_LOAD_ABSENT: Int = 0;")
    lines.append("pub const SHADERC_LOAD_ABI: Int = 1;")
    lines.append("")
    lines.append("pub type ShadercLoadError = {")
    lines.append("  kind: Int;")
    lines.append("  message: Str;")
    lines.append("}")
    lines.append("")
    lines.append("/// A loaded shaderc library.  `handle` is the dl handle; the `p_*`")
    lines.append("/// fields are resolved symbol addresses.  Release with `shaderc_close`.")
    lines.append("pub type ShadercLibrary = {")
    lines.append("  handle: Int;")
    for fn in functions:
        lines.append("  p_%s: Int;" % fn["name"])
    lines.append("}")
    lines.append("")
    lines.append("/// Load shaderc_shared.dll and resolve every oracle entry point")
    lines.append("/// (%d symbols).  Err(kind=SHADERC_LOAD_ABSENT) when the library cannot" % len(functions))
    lines.append("/// be loaded; Err(kind=SHADERC_LOAD_ABI) naming the first missing symbol")
    lines.append("/// otherwise (the handle is closed on failure).")
    lines.append("/// Complexity: O(symbols).")
    lines.append("pub fn shaderc_load() -> Result[ShadercLibrary, ShadercLoadError] {")
    lines.append("  let h = dl.dl_open(SHADERC_SONAME);")
    lines.append("  if !h.is_ok {")
    lines.append("    return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABSENT; message: h.error });")
    lines.append("  }")
    lines.append("  let handle: Int = h.value;")
    for i, fn in enumerate(functions):
        lines.append('  let a%d = dl.dl_sym(handle, "%s");' % (i, fn["name"]))
        lines.append("  if !a%d.is_ok { var ig = dl.dl_close(handle); return Err(ShadercLoadError{ kind: SHADERC_LOAD_ABI; message: \"%s: \" + a%d.error }); }" % (i, fn["name"], i))
    lines.append("  return Ok(ShadercLibrary{")
    lines.append("    handle: handle,")
    for i, fn in enumerate(functions):
        lines.append("    p_%s: a%d.value," % (fn["name"], i))
    lines.append("  });")
    lines.append("}")
    lines.append("")
    lines.append("/// Release a loaded library handle.")
    lines.append("/// Complexity: O(1).")
    lines.append("pub fn shaderc_close(lib: &ShadercLibrary) -> Result[Unit, Str]")
    lines.append("  requires: lib.handle != 0")
    lines.append("{")
    lines.append("  return dl.dl_close(lib.handle);")
    lines.append("}")
    lines.append("")
    lines.append("// =========================================================================")
    lines.append("// Typed wrappers -- one per SHADERC_EXPORT function (oracle order)")
    lines.append("// =========================================================================")
    lines.append("")
    for fn in functions:
        lines.extend(wrapper_lines(fn))
    lines.append(DECODE_HELPERS)
    write_file(path, lines)


def write_file(path, lines):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))
        if lines and lines[-1] != "":
            fh.write("\n")


def main():
    header_dir = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_HEADER_DIR
    functions = []
    constants = []
    hashes = []
    for name in HEADER_FILES:
        path = os.path.join(header_dir, name)
        if not os.path.isfile(path):
            print("header not found: " + path, file=sys.stderr)
            return 2
        text = read_header(path)
        hashes.append((name, sha256_file(path)))
        functions.extend(parse_functions(text))
        constants.extend(parse_enums(text))
    names = [fn["name"] for fn in functions]
    if len(names) != len(set(names)):
        print("duplicate function names in oracle", file=sys.stderr)
        return 2
    if len(constants) == 0:
        print("no enum constants parsed", file=sys.stderr)
        return 2
    emit_symbols(functions, os.path.join(PACKAGE_DIR, "src", "shaderc_symbols.xi"))
    emit_constants(constants, os.path.join(PACKAGE_DIR, "src", "shaderc_constants.xi"))
    emit_module(functions, os.path.join(PACKAGE_DIR, "shaderc.xi"))
    print("oracle: %d functions, %d constants" % (len(functions), len(constants)))
    for name, digest in hashes:
        print("  %-14s %s" % (name, digest))
    print("emitted: shaderc.xi, src/shaderc_symbols.xi, src/shaderc_constants.xi")
    return 0


if __name__ == "__main__":
    sys.exit(main())
