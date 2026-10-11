# XIOM -- xiom.spirv-reflect oracle parser (committed coverage tool).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Parses the vendored SPIRV-Reflect header (vendor/spirv_reflect.h, byte-pinned
# to the Vulkan SDK 1.4.350.0 export) and emits the oracle inventory:
#
#   * public `spvReflect*` function declarations (the C API surface)
#   * every enum value defined in the header (with resolved values)
#   * the header's plain enum/macros (SPV_REFLECT_MAX_*, *_DONT_CHANGE)
#
# Modes:
#   python tools/oracle_spvreflect.py inventory
#       Print counts + full lists (the numbers quoted in docs/COVERAGE.md).
#   python tools/oracle_spvreflect.py emit-consts
#       Print the XIOM `pub const` block (paste source for re-pins).
#   python tools/oracle_spvreflect.py check <module.xi> <bridge.c>
#       Coverage check: every oracle function must appear as `fn <name>(` in
#       the XIOM module AND be called at least once in the bridge C file;
#       every enum value / macro must appear as a `pub const` in the module.
#       Exit 0 = complete, 1 = missing items (printed).
#
# The header is the single source of truth; no manual lists.

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
HEADER = os.path.join(HERE, "..", "vendor", "spirv_reflect.h")


def read_header():
    with open(HEADER, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    return text


def strip_strings(text):
    return re.sub(r'"(?:[^"\\]|\\.)*"', '""', text)


def c_section(text):
    # The C declarations end where the C++ wrapper class begins.
    marker = "SPIRV_REFLECT_DISABLE_CPP_BINDINGS"
    idx = text.find(marker)
    if idx >= 0:
        return text[:idx]
    return text


def parse_functions(text):
    body = strip_strings(strip_comments(c_section(text)))
    names = []
    for chunk in body.split(";"):
        m = re.search(r"\b(spvReflect[A-Za-z0-9_]+)\s*\([^)]*\)", chunk, flags=re.S)
        if not m:
            continue
        pre = chunk[:m.start()]
        # The return-type regex below pins the declaration shape; chunks are
        # cut at the C++ wrapper class, and no struct/enum body contains a
        # lowercase `spvReflect*(` token, so no extra guard is needed here.
        # Only declarations that start with a return type.
        if not re.search(r"(?:^|\n)\s*(?:SPV_REFLECT_DEPRECATED\([^)]*\)\s*)?"
                         r"(?:SpvReflectResult|size_t|uint32_t|void|const\s+"
                         r"(?:char|uint32_t|SpvReflect\w+)\s*\*)[^;\n]*$",
                         pre):
            continue
        if m.group(1) not in names:
            names.append(m.group(1))
    return names


def enum_values(text):
    """Return [(name, value, owner_enum)] for every enum value + enum macro."""
    body = strip_strings(strip_comments(text))
    out = []
    values = {}

    def eval_expr(expr):
        expr = expr.strip()
        expr = re.sub(r"\(int\)", "", expr)
        if expr in values:
            return values[expr]
        if expr.startswith("~"):
            inner = eval_expr(expr[1:])
            return (~inner) & 0xFFFFFFFF
        if expr.startswith("0x") or expr.startswith("0X"):
            return int(expr, 16)
        return int(expr, 10)

    # typedef enum Name { ... } Alias;  and  enum Name { ... };
    for m in re.finditer(r"enum\s+([A-Za-z_]\w*)?\s*\{([^}]*)\}", body, flags=re.S):
        owner = m.group(1) or "(anonymous)"
        entries = m.group(2).split(",")
        nxt = 0
        for e in entries:
            e = e.strip()
            if not e:
                continue
            if "=" in e:
                name, expr = e.split("=", 1)
                name = name.strip()
                nxt = eval_expr(expr)
            else:
                name = e
                nxt = len([x for x in out if x[2] == owner]) if name.startswith("SPV_REFLECT_") else nxt
            if not re.match(r"^[A-Za-z_]\w*$", name):
                continue
            values[name] = nxt
            out.append((name, nxt, owner))
            nxt = nxt + 1
    return out


def parse():
    text = read_header()
    fns = parse_functions(text)
    enums = enum_values(text)
    # Enum-valued names only (skip the typedef aliases and struct fields).
    seen = {}
    for name, value, owner in enums:
        seen[name] = (value, owner)
    return fns, seen


def u32(v):
    return v & 0xFFFFFFFF


def as_i32_literal(v):
    v = u32(v)
    if v >= 0x80000000:
        return "%d" % (v - 0x100000000)
    return "%d" % v


def cmd_inventory():
    fns, enums = parse()
    print("SPIRV-Reflect oracle (Vulkan SDK 1.4.350.0 export)")
    print("functions: %d" % len(fns))
    for f in sorted(fns):
        print("  FN %s" % f)
    print("enum/macro values: %d" % len(enums))
    owners = {}
    for name, (value, owner) in enums.items():
        owners.setdefault(owner, 0)
        owners[owner] += 1
    for o in sorted(owners):
        print("  ENUM %-32s %d values" % (o, owners[o]))


def cmd_emit_consts():
    fns, enums = parse()
    by_owner = {}
    for name, (value, owner) in enums.items():
        by_owner.setdefault(owner, []).append((name, value))
    for owner in sorted(by_owner):
        print("// ---- %s ----" % owner)
        for name, value in sorted(by_owner[owner], key=lambda kv: kv[0]):
            print("pub const %s: Int32 = %s as Int32;" % (name, as_i32_literal(value)))
        print()


def cmd_check(module_path, bridge_path):
    fns, enums = parse()
    with open(module_path, "r", encoding="utf-8", errors="replace") as f:
        module = f.read()
    with open(bridge_path, "r", encoding="utf-8", errors="replace") as f:
        bridge = f.read()

    missing_fns = [f for f in fns if ("fn %s(" % f) not in module]
    missing_calls = [f for f in fns if not re.search(r"\b%s\s*\(" % f, bridge)]
    missing_consts = [n for n in enums if ("pub const %s" % n) not in module]

    print("oracle: %d functions, %d enum/macro values" % (len(fns), len(enums)))
    print("bound fns in module:        %d/%d" % (len(fns) - len(missing_fns), len(fns)))
    print("called fns in bridge:       %d/%d" % (len(fns) - len(missing_calls), len(fns)))
    print("bound consts in module:     %d/%d" % (len(enums) - len(missing_consts), len(enums)))
    for f in missing_fns:
        print("  MISSING FN (module): %s" % f)
    for f in missing_calls:
        print("  MISSING FN (bridge): %s" % f)
    for n in missing_consts:
        print("  MISSING CONST: %s" % n)
    ok = not (missing_fns or missing_calls or missing_consts)
    print("check: %s" % ("OK" if ok else "INCOMPLETE"))
    return 0 if ok else 1


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    mode = sys.argv[1]
    if mode == "inventory":
        cmd_inventory()
        return 0
    if mode == "emit-consts":
        cmd_emit_consts()
        return 0
    if mode == "check" and len(sys.argv) == 4:
        return cmd_check(sys.argv[2], sys.argv[3])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
