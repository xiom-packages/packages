#!/usr/bin/env python3
"""Generate the xiom.assimp vendor tree from an upstream assimp checkout.

STATUS: staged for the xiom.assimp pilot (core + OBJ/STL/PLY importers; no
contribs needed by that subset).

Usage:
  python tools/combine.py <upstream-root> <package-dir>

Effects:
  * mirrors <upstream-root>/include/assimp/** -> <pkg>/vendor/include/assimp/**
    and <upstream-root>/code/** -> <pkg>/vendor/code/** (verbatim bytes).
  * rewrites include directives: every quoted/angled include that resolves to
    a vendored header is replaced by an exact relative path from the
    including file (system headers are left untouched).  The xiom link line
    has no -I passthrough, so this makes every vendored .cpp directly
    compilable via --c-source.
  * generates vendor/include/assimp/config.h (ASSIMP_BUILD_NO_EXPORT plus
    ASSIMP_BUILD_NO_<X>_IMPORTER/EXPORTER for everything outside the enabled
    set) and revision.h (v-pin constants) from the upstream .in templates.
  * writes <pkg>/port.args.json listing every compiled TU
    (${PACKAGE_DIR}-relative) -- core + Material + PostProcessing + the
    enabled importers (exporter TUs are skipped).
  * prints counts plus a deterministic sha256 over the generated tree.

Enabled importers are the constant ENABLED below (pilot: OBJ, STL, PLY).
"""

import hashlib
import os
import re
import shutil
import sys

ENABLED = ("OBJ", "STL", "PLY", "GLTF", "COLLADA", "FBX")

# Every ASSIMP_BUILD_*_IMPORTER option name (from code/CMakeLists.txt).
ALL_IMPORTERS = (
    "AMF", "3DS", "AC", "ASE", "ASSBIN", "B3D", "BVH", "COLLADA", "DXF",
    "CSM", "HMP", "IRRMESH", "IQM", "IRR", "LWO", "LWS", "M3D", "MD2",
    "MD3", "MD5", "MDC", "MDL", "NFF", "NDO", "OFF", "OBJ", "OGRE",
    "OPENGEX", "PLY", "MS3D", "COB", "BLEND", "IFC", "XGL", "FBX", "Q3D",
    "Q3BSP", "RAW", "SIB", "SMD", "STL", "TERRAGEN", "3D", "USD", "X",
    "X3D", "GLTF", "3MF", "MMD",
)

INC_RE = re.compile(r'^(\s*#\s*include\s*)([<"])([^">]+)([>"])', re.MULTILINE)
TEXT_EXT = (".h", ".hpp", ".inl", ".cpp", ".c")

# Never rewrite these, even if a vendored file shares the basename (e.g.
# rapidjson ships msinttypes/stdint.h and inttypes.h).
SYSTEM_HEADERS = frozenset((
    "stdint.h", "stddef.h", "stdlib.h", "stdio.h", "string.h", "strings.h",
    "limits.h", "float.h", "math.h", "assert.h", "errno.h", "time.h",
    "ctype.h", "wchar.h", "wctype.h", "inttypes.h", "stdbool.h", "stdarg.h",
    "signal.h", "setjmp.h", "locale.h", "fenv.h", "iso646.h", "complex.h",
    "tgmath.h", "threads.h", "stdalign.h", "stdatomic.h", "stdnoreturn.h",
    "unistd.h", "sys/types.h", "sys/stat.h", "fcntl.h", "io.h", "direct.h",
    "process.h", "windows.h", "winsock2.h", "malloc.h", "share.h",
    "cassert", "cctype", "cerrno", "cfenv", "cfloat", "cinttypes",
    "climits", "clocale", "cmath", "csetjmp", "csignal", "cstdarg",
    "cstddef", "cstdint", "cstdio", "cstdlib", "cstring", "ctime", "cwchar",
    "cwctype", "algorithm", "any", "array", "atomic", "bitset", "chrono",
    "codecvt", "complex", "deque", "exception", "filesystem", "forward_list",
    "fstream", "functional", "future", "initializer_list", "iomanip",
    "ios", "iosfwd", "iostream", "istream", "iterator", "limits", "list",
    "map", "memory", "mutex", "new", "numeric", "optional", "ostream",
    "queue", "random", "ratio", "regex", "scoped_allocator", "set", "shared_mutex",
    "sstream", "stack", "stdexcept", "streambuf", "string", "string_view",
    "strstream", "system_error", "thread", "tuple", "type_traits", "typeindex",
    "typeinfo", "unordered_map", "unordered_set", "utility", "valarray",
    "variant", "vector",
))

CORE_DIRS = ("Common", "Material", "PostProcessing", "CApi", "Geometry")
ASSET_DIRS_BY_IMPORTER = {
    "OBJ": ("AssetLib/OBJ",),
    "STL": ("AssetLib/STL",),
    "PLY": ("AssetLib/PLY",),
    "GLTF": ("AssetLib/glTF", "AssetLib/glTF2", "AssetLib/glTFCommon"),
    "COLLADA": ("AssetLib/Collada",),
    "FBX": ("AssetLib/FBX",),
}
CONTRIB_MIRROR = ("zlib", "earcut-hpp", "utf8cpp", "rapidjson", "pugixml")
CONTRIB_EXTRA = (
    ("zlib", "contrib/minizip/unzip.c"),
    ("zlib", "contrib/minizip/ioapi.c"),
    ("pugixml", "src/pugixml.cpp"),
)


def read_text(path):
    with open(path, "rb") as f:
        data = f.read()
    return data.decode("utf-8", "surrogateescape")


def write_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def mirror_tree(src_root, dst_root, transform=True):
    """Copy src_root/** to dst_root/**; returns list of copied files."""
    copied = []
    for dirpath, dirnames, filenames in os.walk(src_root):
        dirnames.sort()
        for name in sorted(filenames):
            src = os.path.join(dirpath, name)
            rel = os.path.relpath(src, src_root)
            dst = os.path.join(dst_root, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if transform and name.endswith(TEXT_EXT):
                write_text(dst, read_text(src))
            else:
                shutil.copyfile(src, dst)
            copied.append(dst)
    return copied


def build_header_map(vendor):
    """Map include spellings -> vendored file path.

    Keys: (a) path relative to the include root (include/ -> 'assimp/...',
    code/ -> 'Common/...'), (b) unique basenames.
    """
    by_key = {}
    by_base = {}
    for sub in ("include", "code"):
        root = os.path.join(vendor, sub)
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames.sort()
            for name in sorted(filenames):
                if not name.endswith((".h", ".hpp", ".inl")):
                    continue
                full = os.path.join(dirpath, name)
                rel = os.path.relpath(full, root).replace("\\", "/")
                if sub == "include" and not rel.startswith("assimp/"):
                    rel = "assimp/" + rel
                by_key[rel] = full
                by_base.setdefault(name, []).append(full)
    # Contrib trees: keys relative to the lib root, to its include/ dir (if
    # present), to the vendor root, plus the basename.
    contrib_root = os.path.join(vendor, "contrib")
    for lib in CONTRIB_MIRROR:
        lib_root = os.path.join(contrib_root, lib)
        if not os.path.isdir(lib_root):
            continue
        roots = [lib_root]
        include_dir = os.path.join(lib_root, "include")
        if os.path.isdir(include_dir):
            roots.append(include_dir)
        for dirpath, dirnames, filenames in os.walk(lib_root):
            dirnames.sort()
            for name in sorted(filenames):
                if not name.endswith((".h", ".hpp", ".inl")):
                    continue
                full = os.path.join(dirpath, name)
                for r in roots:
                    if os.path.commonpath([full, r]) == r or full.startswith(r + os.sep):
                        key = os.path.relpath(full, r).replace("\\", "/")
                        by_key.setdefault(key, full)
                by_key.setdefault("contrib/" + os.path.relpath(full, contrib_root).replace("\\", "/"), full)
                by_base.setdefault(name, []).append(full)
    unique_base = {k: v[0] for k, v in by_base.items() if len(v) == 1}
    return by_key, unique_base


def rel_include(from_file, target):
    rel = os.path.relpath(target, os.path.dirname(from_file)).replace("\\", "/")
    return rel


def rewrite_includes(path, header_by_key, header_by_base, vendor):
    text = read_text(path)
    own_dir = os.path.dirname(path)

    def repl(match):
        head, quote, target, close = match.groups()
        target_slash = target.replace("\\", "/")
        if os.path.basename(target_slash) in SYSTEM_HEADERS:
            return match.group(0)  # never remap standard headers
        # 1. already resolvable next to the file (quoted only)
        if quote == '"' and os.path.exists(os.path.join(own_dir, target_slash)):
            return match.group(0)
        # 2. exact include-root key
        hit = header_by_key.get(target_slash)
        if hit is None:
            # 3. unique basename
            hit = header_by_base.get(os.path.basename(target_slash))
        if hit is None:
            return match.group(0)  # system header -- keep
        return head + '"' + rel_include(path, hit) + '"'

    return INC_RE.sub(repl, text)


def generate_config(path, upstream, enabled):
    """CMake-substitute config.h.in (keep every plain AI_CONFIG_* default),
    then append the subset's importer/exporter switches."""
    text = read_text(os.path.join(upstream, "include", "assimp", "config.h.in"))
    text = text.replace("#cmakedefine ASSIMP_DOUBLE_PRECISION 1",
                        "/* #undef ASSIMP_DOUBLE_PRECISION */")
    lines = [text.rstrip("\n"),
             "",
             "/* ------------------------------------------------------------------",
             " * Generated subset configuration (xiom.assimp pilot: core + %s)" % ", ".join(enabled),
             " * -- appended by tools/combine.py. */",
             "#define ASSIMP_BUILD_NO_EXPORT 1"]
    for name in ALL_IMPORTERS:
        if name not in enabled:
            lines.append("#define ASSIMP_BUILD_NO_%s_IMPORTER 1" % name)
        lines.append("#define ASSIMP_BUILD_NO_%s_EXPORTER 1" % name)
    # Non-free importer (no standard option name in the default set).
    lines.append("#define ASSIMP_BUILD_NO_C4D_IMPORTER 1")
    write_text(path, "\n".join(lines) + "\n")


def generate_revision(path, upstream):
    src = os.path.join(upstream, "include", "assimp", "revision.h.in")
    text = read_text(src)
    text = text.replace("@GIT_COMMIT_HASH@", "0")
    text = text.replace("@GIT_BRANCH@", "v6.0.5")
    text = text.replace("@ASSIMP_VERSION_MAJOR@", "6")
    text = text.replace("@ASSIMP_VERSION_MINOR@", "0")
    text = text.replace("@ASSIMP_VERSION_PATCH@", "5")
    text = text.replace("@ASSIMP_PACKAGE_VERSION@", "0")
    text = text.replace("@CMAKE_SHARED_LIBRARY_PREFIX@", "")
    text = text.replace("@LIBRARY_SUFFIX@", ".dll")
    text = text.replace("@CMAKE_DEBUG_POSTFIX@", "")
    write_text(path, text)


def collect_sources(vendor):
    sources = []
    for core in CORE_DIRS:
        base = os.path.join(vendor, "code", core)
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames.sort()
            for name in sorted(filenames):
                if name.endswith(".cpp") and "Export" not in name:
                    sources.append(os.path.join(dirpath, name))
    for imp in ENABLED:
        for asset_dir in ASSET_DIRS_BY_IMPORTER[imp]:
            base = os.path.join(vendor, "code", *asset_dir.split("/"))
            for dirpath, dirnames, filenames in os.walk(base):
                dirnames.sort()
                for name in sorted(filenames):
                    if name.endswith(".cpp") and "Export" not in name:
                        sources.append(os.path.join(dirpath, name))
    # C sources from the mirrored contribs (zlib core only -- the win32/ and
    # contrib/ subdirectories hold test/aux programs that upstream's CMake
    # does not build).
    for contrib in CONTRIB_MIRROR:
        base = os.path.join(vendor, "contrib", contrib)
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            full = os.path.join(base, name)
            if os.path.isfile(full) and name.endswith(".c"):
                sources.append(full)
    # Extra sources from contrib subdirectories (minizip, pugixml).
    for contrib, sub in CONTRIB_EXTRA:
        full = os.path.join(vendor, "contrib", contrib, *sub.split("/"))
        if os.path.isfile(full):
            sources.append(full)
    # Our bridge.
    bridge = os.path.join(os.path.dirname(vendor), "src", "assimp_bridge.cpp")
    if os.path.isfile(bridge):
        sources.append(bridge)
    return sorted(sources)


def write_port_args(path, pkg_dir, sources):
    items = []
    for src in sources:
        rel = os.path.relpath(src, pkg_dir).replace("\\", "/")
        items.append('  "--c-source",')
        items.append('  "${PACKAGE_DIR}/%s",' % rel)
    if items:
        items[-1] = items[-1].rstrip(",")
    body = "[\n" + "\n".join(items) + "\n]\n"
    write_text(path, body)


def tree_hash(vendor):
    h = hashlib.sha256()
    for dirpath, dirnames, filenames in os.walk(vendor):
        dirnames.sort()
        for name in sorted(filenames):
            if name in ("config.h", "revision.h"):
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, vendor).replace("\\", "/")
            h.update(rel.encode("utf-8"))
            h.update(b"\0")
            with open(full, "rb") as f:
                h.update(f.read())
    return h.hexdigest()


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    upstream = os.path.abspath(sys.argv[1])
    pkg = os.path.abspath(sys.argv[2])
    vendor = os.path.join(pkg, "vendor")
    if not os.path.isdir(os.path.join(upstream, "code")):
        print("error: no code/ under %s" % upstream)
        return 2

    for sub in ("include", "code"):
        dst = os.path.join(vendor, sub)
        if os.path.isdir(dst):
            shutil.rmtree(dst)

    inc_files = mirror_tree(os.path.join(upstream, "include", "assimp"),
                            os.path.join(vendor, "include", "assimp"))
    code_files = mirror_tree(os.path.join(upstream, "code"),
                             os.path.join(vendor, "code"))
    contrib_files = []
    for contrib in CONTRIB_MIRROR:
        contrib_files += mirror_tree(os.path.join(upstream, "contrib", contrib),
                                     os.path.join(vendor, "contrib", contrib))

    # zlib's CMake configuration steps: zconf.h is zconf.h.included (already
    # substituted in the tagged tree).
    zconf_included = os.path.join(vendor, "contrib", "zlib", "zconf.h.included")
    if os.path.isfile(zconf_included):
        shutil.copyfile(zconf_included, os.path.join(vendor, "contrib", "zlib", "zconf.h"))

    license_src = os.path.join(upstream, "LICENSE")
    if os.path.isfile(license_src):
        shutil.copyfile(license_src, os.path.join(vendor, "LICENSE"))

    generate_config(os.path.join(vendor, "include", "assimp", "config.h"), upstream, ENABLED)
    generate_revision(os.path.join(vendor, "include", "assimp", "revision.h"), upstream)

    header_by_key, header_by_base = build_header_map(vendor)
    rewritten = 0
    for path in code_files + inc_files + contrib_files:
        if path.endswith(TEXT_EXT):
            new = rewrite_includes(path, header_by_key, header_by_base, vendor)
            old = read_text(path)
            if new != old:
                write_text(path, new)
                rewritten += 1

    sources = collect_sources(vendor)
    write_port_args(os.path.join(pkg, "port.args.json"), pkg, sources)

    print("mirrored files (public headers + code + contrib): %d" % (len(inc_files) + len(code_files) + len(contrib_files)))
    print("files with rewritten includes:          %d" % rewritten)
    print("compiled TUs:                           %d" % len(sources))
    print("tree sha256 (generated, excl config/revision): %s" % tree_hash(vendor))
    return 0


if __name__ == "__main__":
    sys.exit(main())
