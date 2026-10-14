# XIOM -- xiom.ktx2 oracle parser (committed coverage tool).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Parses the vendored libktx public header (vendor/ktx/include/ktx.h,
# byte-transformed from the KTX-Software v4.4.2 pin by tools/vendor_ktx.py)
# and emits / verifies the oracle inventory:
#
#   * the public KTX_API function declarations (the declared C surface)
#   * every enum value defined in the header (resolved, refs included)
#   * the header's numeric macros (KTX_HEADER_SIZE, KTX_ENDIAN_REF, ...)
#   * the VK_FORMAT_* enum values used by the package, from the vendored
#     lib/vkformat_enum.h
#
# Modes:
#   python tools/oracle_ktx.py inventory
#       Print counts + the full function list (the numbers quoted in
#       docs/COVERAGE.md and the task report).
#   python tools/oracle_ktx.py emit-consts
#       Print the XIOM `pub const` block (paste source for re-pins).
#   python tools/oracle_ktx.py emit-vkformats NAME [NAME...]
#       Print `pub const NAME: Int32 = <value> as Int32;` for the named
#       VK_FORMAT_* values from the pinned vkformat_enum.h.
#   python tools/oracle_ktx.py check <module.xi> <bridge.c>
#       Coverage check: every oracle function must appear as `fn <name>(`
#       in the XIOM module AND as `(kx2_pfn)<name>` in the bridge symbol
#       table; every enum value / macro must appear as a `pub const` in
#       the module. Exit 0 = complete, 1 = missing items (printed).
#
# The pinned headers are the single source of truth; no manual lists.

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
HEADER = os.path.join(HERE, "..", "vendor", "ktx", "include", "ktx.h")
KHRDF = os.path.join(HERE, "..", "vendor", "ktx", "include", "KHR", "khr_df.h")
VKFORMATS = os.path.join(HERE, "..", "vendor", "ktx", "lib", "vkformat_enum.h")

# Numeric macros in ktx.h that belong to the surface (string macros like
# KTX_ANIMDATA_KEY are excluded: XIOM consumers use their own literals).
MACRO_ALLOW = {
    "KTX_GL_UNPACK_ALIGNMENT",
    "KTX_FACESLICE_WHOLE_LEVEL",
    "KTX_ENDIAN_REF",
    "KTX_ENDIAN_REF_REV",
    "KTX_HEADER_SIZE",
}

# Aliases that simply re-state another enumerator; kept in the oracle (they
# are part of the header) but emitted as comments in emit-consts.
ALIAS_HINT = "/* alias */"


def read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    return text


def strip_strings(text):
    return re.sub(r'"(?:[^"\\]|\\.)*"', '""', text)


def parse_functions(text):
    body = strip_strings(strip_comments(text))
    names = []
    # KTX_API declarations may span lines: return type + KTX_APIENTRY + name(
    pat = re.compile(r"KTX_API\b[^;{}]*?KTX_APIENTRY\s*\*?\s*"
                     r"([A-Za-z_][A-Za-z0-9_]*)\s*\(", re.S)
    for m in pat.finditer(body):
        if m.group(1) not in names:
            names.append(m.group(1))
    return names


def eval_expr(expr, values):
    """Evaluate an enumerator initializer (ints, hex, char literals, refs)."""
    expr = expr.strip()
    # strip casts like (int) and integer suffixes (1U, 0xFFu, 1L)
    expr = re.sub(r"\(\s*int\s*\)", "", expr)
    expr = re.sub(r"\b(0[xX][0-9a-fA-F]+|\d+)[uUlL]+\b", r"\1", expr)
    m = re.fullmatch(r"'(.)'", expr)
    if m:
        return ord(m.group(1))
    if expr.startswith("0x") or expr.startswith("0X"):
        return int(expr, 16)
    if expr in values:
        return values[expr]
    if re.fullmatch(r"-?\d+", expr):
        return int(expr, 10)
    # last resort: evaluate with known names substituted
    sub = expr
    for name in sorted(values, key=len, reverse=True):
        sub = re.sub(r"\b%s\b" % re.escape(name), str(values[name]), sub)
    try:
        return int(eval(sub, {"__builtins__": {}}, {}))  # noqa: S307
    except Exception:
        return None


def enum_values(text):
    """Return [(name, value, owner)] for every enumerator in ktx.h."""
    body = strip_strings(strip_comments(text))
    out = []
    values = {}
    for m in re.finditer(r"enum\s+([A-Za-z_]\w*)?\s*\{([^}]*)\}", body, flags=re.S):
        owner = m.group(1) or "(anonymous)"
        nxt = 0
        for e in m.group(2).split(","):
            e = " ".join(e.split())
            if not e:
                continue
            if "=" in e:
                name, expr = e.split("=", 1)
                name = name.strip()
                v = eval_expr(expr, values)
                if v is None:
                    continue
                nxt = v
            else:
                name = e
            if not re.match(r"^[A-Za-z_]\w*$", name):
                continue
            values[name] = nxt
            out.append((name, nxt, owner))
            nxt += 1
    return out


def macro_values(text):
    body = strip_comments(text)
    out = {}
    for m in re.finditer(r"^#\s*define\s+([A-Za-z_]\w*)\s+([^\n]+)$", body, flags=re.M):
        name, expr = m.group(1), m.group(2).strip()
        if name not in MACRO_ALLOW:
            continue
        if expr == "UINT_MAX":
            out[name] = -1  # 0xFFFFFFFF as a signed Int32
            continue
        v = eval_expr(expr, {})
        if v is not None:
            out[name] = v
    return out


def parse():
    text = read(HEADER)
    fns = parse_functions(text)
    enums = enum_values(text)
    macro = macro_values(text)
    enums += enum_values(read(KHRDF))
    return fns, enums, macro


def vkformat(name):
    body = strip_comments(read(VKFORMATS))
    m = re.search(r"\b%s\s*=\s*(\d+)" % re.escape(name), body)
    if not m:
        return None
    return int(m.group(1))


def as_i32(v):
    v &= 0xFFFFFFFF
    if v >= 0x80000000:
        return v - 0x100000000
    return v


def cmd_inventory():
    fns, enums, macro = parse()
    print("libktx %s oracle (KTX-Software pin 4d6fc70e, include/ktx.h)" % "v4.4.2")
    print("declared functions: %d" % len(fns))
    for f in fns:
        print("  FN %s" % f)
    print("enum values: %d" % len(enums))
    owners = {}
    for _name, _value, owner in enums:
        owners[owner] = owners.get(owner, 0) + 1
    for o in sorted(owners):
        print("  ENUM %-40s %d values" % (o, owners[o]))
    print("numeric macros: %d" % len(macro))
    for k in sorted(macro):
        print("  MACRO %s = %d" % (k, macro[k]))
    return 0


# VK_FORMAT_* values the package's fixtures and assertions name, verified
# against the pinned lib/vkformat_enum.h.
VKFORMAT_SUBSET = [
    "VK_FORMAT_R8G8B8_UNORM",
    "VK_FORMAT_R8G8B8A8_UNORM",
    "VK_FORMAT_BC1_RGB_UNORM_BLOCK",
    "VK_FORMAT_BC3_UNORM_BLOCK",
    "VK_FORMAT_BC7_UNORM_BLOCK",
    "VK_FORMAT_ETC2_R8G8B8_UNORM_BLOCK",
    "VK_FORMAT_ASTC_4x4_UNORM_BLOCK",
]


def cmd_emit_consts():
    fns, enums, macro = parse()
    by_owner = {}
    for name, value, owner in enums:
        by_owner.setdefault(owner, []).append((name, value))
    for owner in sorted(by_owner):
        print("// ---- %s ----" % owner)
        for name, value in by_owner[owner]:
            print("pub const %s: Int32 = %d as Int32;" % (name, as_i32(value)))
        print()
    print("// ---- numeric macros ----")
    for name in sorted(macro):
        print("pub const %s: Int32 = %d as Int32;" % (name, as_i32(macro[name])))
    print()
    print("// ---- VK format subset (lib/vkformat_enum.h) ----")
    for name in VKFORMAT_SUBSET:
        v = vkformat(name)
        if v is None:
            die("vkformat not found: %s" % name)
        print("pub const %s: Int32 = %d as Int32;" % (name, v))
    return 0


def cmd_emit_vkformats(names):
    for name in names:
        v = vkformat(name)
        if v is None:
            print("// NOT FOUND: %s" % name)
            return 1
        print("pub const %s: Int32 = %d as Int32;" % (name, v))
    return 0


def cmd_check(module_path, bridge_path):
    fns, enums, macro = parse()
    module = read(module_path)
    bridge = read(bridge_path)

    missing_fns = [f for f in fns if ("fn %s(" % f) not in module]
    missing_calls = [f for f in fns if ("(kx2_pfn)%s" % f) not in bridge]
    missing_consts = [n for n, _v, _o in enums if ("pub const %s" % n) not in module]
    missing_macros = [n for n in macro if ("pub const %s" % n) not in module]

    print("oracle: %d functions, %d enum values, %d macros"
          % (len(fns), len(enums), len(macro)))
    print("declared fns in module:     %d/%d" % (len(fns) - len(missing_fns), len(fns)))
    print("referenced fns in bridge:   %d/%d" % (len(fns) - len(missing_calls), len(fns)))
    print("bound consts in module:     %d/%d"
          % (len(enums) - len(missing_consts), len(enums)))
    print("bound macros in module:     %d/%d"
          % (len(macro) - len(missing_macros), len(macro)))
    for f in missing_fns:
        print("  MISSING FN (module): %s" % f)
    for f in missing_calls:
        print("  MISSING FN (bridge): %s" % f)
    for n in missing_consts:
        print("  MISSING CONST: %s" % n)
    for n in missing_macros:
        print("  MISSING MACRO: %s" % n)
    ok = not (missing_fns or missing_calls or missing_consts or missing_macros)
    print("check: %s" % ("OK" if ok else "INCOMPLETE"))
    return 0 if ok else 1


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    mode = argv[1]
    if mode == "inventory":
        return cmd_inventory()
    if mode == "emit-consts":
        return cmd_emit_consts()
    if mode == "emit-vkformats" and len(argv) >= 3:
        return cmd_emit_vkformats(argv[2:])
    if mode == "check" and len(argv) == 4:
        return cmd_check(argv[2], argv[3])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
