# XIOM -- xiom.ktx2 vendoring tool (committed, re-run on every re-pin).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Mirrors the needed subset of Khronos KTX-Software (libktx + the Basis
# Universal transcoder/encoder + dfdutils + the Arm ASTC encoder + the
# vendored zstd) from a pinned clone into `vendor/ktx/`, then applies the
# transformations the XIOM link line requires (it has no -I/-D passthrough):
#
#   1. Extraction is `git cat-file blob <pin>:<path>` from the clone's
#      object store (canonical LF bytes; no working-tree EOL conversion),
#      so `git hash-object` of the pre-transform file equals the upstream
#      blob id even though the stored vendored bytes are transformed.
#
#   2. INCLUDE REWRITING. Every #include directive that resolves to a
#      vendored header is rewritten to an exact relative path. Resolution
#      order mirrors the upstream CMake include dirs: the including file's
#      own directory first (left untouched when it already resolves), then
#      include/, external/, external/basisu/transcoder/, external/basisu/,
#      external/basisu/zstd/, utils/, other_include/, lib/. System headers
#      are never rewritten. `<strings.h>` (absent from the Windows clang
#      target) is mapped to the package-local src/compat/strings.h.
#
#   3. BUILD-CONFIG INJECTION. Each compiled libktx/Basis translation unit
#      gets a two-line prologue that includes vendor/ktx/xiom_build_config.h
#      (KHRONOS_STATIC, LIBKTX, KTX_FEATURE_WRITE, KTX_FEATURE_KTX1/2,
#      SUPPORT_SOFTWARE_ETC_UNPACK=0, BASISD_SUPPORT_*, BASISU_SUPPORT_*).
#      The ASTC encoder TUs get no prologue: their own headers auto-detect
#      the baseline SSE2 backend from the compiler's predefined macros.
#
# Everything else is byte-verbatim. vendor/ktx/lib/version.h is generated
# (LIBKTX_VERSION v4.4.2, mirroring scripts/mkversion's output) because
# upstream generates it at CMake configure time.
#
# Usage:
#   python tools/vendor_ktx.py <upstream-root> <package-dir>
#   python tools/vendor_ktx.py --hash <package-dir>      # print tree hash
#
# The script rewrites <package-dir>/vendor/ktx/** and
# <package-dir>/port.args.json, writes <package-dir>/vendor/FILES.sha256
# and prints the aggregate sha256 over every vendored file (the G2 pin
# quoted in SPEC.md).

import glob
import hashlib
import json
import os
import posixpath
import re
import shutil
import subprocess
import sys

PIN_COMMIT = "4d6fc70eaf62ad0558e63e8d97eb9766118327a6"
PIN_TAG = "v4.4.2"
LIBKTX_VERSION = "v4.4.2"

# ---------------------------------------------------------------------------
# Mirror set (relative to the upstream root).
# ---------------------------------------------------------------------------

MIRROR_FILES = [
    "include/ktx.h",
    "include/KHR/khr_df.h",
    "LICENSE.md",
    "NOTICE.md",
    "REUSE.toml",
    "utils/unused.h",
    "other_include/GL/glcorearb.h",
    "other_include/GL/glext.h",
    "other_include/GLES2/gl2ext.h",
    "other_include/GLES2/gl2platform.h",
    "other_include/KHR/khrplatform.h",
    "other_include/zstd_errors.h",
    "external/dfdutils/dfd.h",
    "external/dfdutils/vk2dfd.inl",
    "external/dfdutils/LICENSE.adoc",
    "external/dfdutils/vulkan/vk_platform.h",
    "external/dfdutils/vulkan/vulkan_core.h",
    "external/basisu/zstd/zstd.c",
    "external/basisu/zstd/zstd.h",
    "external/basisu/zstd/LICENSE",
    "external/basisu/LICENSES/Apache-2.0.txt",
    "external/basisu/LICENSES/BSD.txt",
    "external/basisu/LICENSES/Zlib.txt",
    "external/astc-encoder/LICENSE.txt",
]

MIRROR_GLOBS = [
    "lib/*.c",
    "lib/*.cpp",
    "lib/*.h",
    "lib/*.inl",
    "lib/*.cxx",
    "external/dfdutils/*.c",
    "external/basisu/transcoder/*.h",
    "external/basisu/transcoder/*.cpp",
    "external/basisu/transcoder/*.inc",
    "external/basisu/encoder/*.h",
    "external/basisu/encoder/*.cpp",
    "external/astc-encoder/Source/*.h",
    "external/astc-encoder/Source/*.cpp",
    "LICENSES/*.txt",
]

# Present in the mirror set above but not vendored: LIBKTX=1 excludes their
# only consumers (basisu_tool.cpp and basisu_enc.cpp's image loaders).
MIRROR_EXCLUDE = {
    "external/basisu/encoder/jpgd.h",
    "external/basisu/encoder/pvpngreader.h",
}

# ---------------------------------------------------------------------------
# Translation units compiled into the suite binary.
# ---------------------------------------------------------------------------

KTX_C_TUS = [
    "lib/checkheader.c",
    "lib/filestream.c",
    "lib/glformat_str.c",
    "lib/hashlist.c",
    "lib/info.c",
    "lib/memstream.c",
    "lib/strings.c",
    "lib/swap.c",
    "lib/texture.c",
    "lib/texture1.c",
    "lib/texture2.c",
    "lib/vkformat_check.c",
    "lib/vkformat_check_variant.c",
    "lib/vkformat_str.c",
    "lib/vkformat_typesize.c",
    "lib/gl_funcs.c",
    "lib/glloader.c",
    "lib/writer1.c",
    "lib/writer2.c",
    "external/dfdutils/createdfd.c",
    "external/dfdutils/colourspaces.c",
    "external/dfdutils/interpretdfd.c",
    "external/dfdutils/printdfd.c",
    "external/dfdutils/queries.c",
    "external/dfdutils/vk2dfd.c",
]

KTX_CXX_TUS = [
    "lib/astc_codec.cpp",
    "lib/basis_transcode.cpp",
    "lib/basis_encode.cpp",
    "lib/miniz_wrapper.cpp",
    "external/basisu/transcoder/basisu_transcoder.cpp",
    "external/basisu/encoder/basisu_backend.cpp",
    "external/basisu/encoder/basisu_basis_file.cpp",
    "external/basisu/encoder/basisu_bc7enc.cpp",
    "external/basisu/encoder/basisu_comp.cpp",
    "external/basisu/encoder/basisu_enc.cpp",
    "external/basisu/encoder/basisu_etc.cpp",
    "external/basisu/encoder/basisu_frontend.cpp",
    "external/basisu/encoder/basisu_gpu_texture.cpp",
    "external/basisu/encoder/basisu_kernels_sse.cpp",
    "external/basisu/encoder/basisu_opencl.cpp",
    "external/basisu/encoder/basisu_pvrtc1_4.cpp",
    "external/basisu/encoder/basisu_resample_filters.cpp",
    "external/basisu/encoder/basisu_resampler.cpp",
    "external/basisu/encoder/basisu_ssim.cpp",
    "external/basisu/encoder/basisu_uastc_enc.cpp",
]

# Arm ASTC encoder TUs linked for ktxTexture2_CompressAstc/DecodeAstc.
# (astcenc_platform_isa_detection.cpp is CLI-only; the library dispatches
# on the defines auto-detected in astcenc_mathlib.h.)
ASTC_CXX_TUS = [
    "external/astc-encoder/Source/astcenc_averages_and_directions.cpp",
    "external/astc-encoder/Source/astcenc_block_sizes.cpp",
    "external/astc-encoder/Source/astcenc_color_quantize.cpp",
    "external/astc-encoder/Source/astcenc_color_unquantize.cpp",
    "external/astc-encoder/Source/astcenc_compress_symbolic.cpp",
    "external/astc-encoder/Source/astcenc_compute_variance.cpp",
    "external/astc-encoder/Source/astcenc_decompress_symbolic.cpp",
    "external/astc-encoder/Source/astcenc_diagnostic_trace.cpp",
    "external/astc-encoder/Source/astcenc_entry.cpp",
    "external/astc-encoder/Source/astcenc_find_best_partitioning.cpp",
    "external/astc-encoder/Source/astcenc_ideal_endpoints_and_weights.cpp",
    "external/astc-encoder/Source/astcenc_image.cpp",
    "external/astc-encoder/Source/astcenc_integer_sequence.cpp",
    "external/astc-encoder/Source/astcenc_mathlib.cpp",
    "external/astc-encoder/Source/astcenc_mathlib_softfloat.cpp",
    "external/astc-encoder/Source/astcenc_partition_tables.cpp",
    "external/astc-encoder/Source/astcenc_percentile_tables.cpp",
    "external/astc-encoder/Source/astcenc_pick_best_endpoint_format.cpp",
    "external/astc-encoder/Source/astcenc_quantization.cpp",
    "external/astc-encoder/Source/astcenc_symbolic_physical.cpp",
    "external/astc-encoder/Source/astcenc_weight_align.cpp",
    "external/astc-encoder/Source/astcenc_weight_quant_xfer_tables.cpp",
]

BUILD_CONFIG_TUS = KTX_C_TUS + KTX_CXX_TUS  # no prologue for ASTC or zstd

MIRROR_ROOT = "vendor/ktx"
CONFIG_HEADER_REL = "xiom_build_config.h"

SEARCH_DIRS = [
    "include",
    "external",
    "external/basisu/transcoder",
    "external/basisu",
    "external/basisu/zstd",
    "utils",
    "other_include",
    "lib",
]

# include basename -> package-root-relative target for headers the Windows
# clang target does not ship.
SPECIAL_RESOLVE = {
    "strings.h": "src/compat/strings.h",
}

TEXT_EXTS = (".c", ".h", ".cpp", ".cxx", ".inl", ".inc")

BUILD_CONFIG = """\
/* xiom.ktx2 build configuration -- GENERATED by tools/vendor_ktx.py.
 *
 * Injected as a prologue include into every compiled libktx/Basis TU
 * (the XIOM link line has no -D/-I passthrough). Values mirror the
 * upstream CMake build of the `ktx` (write) target at the pin, with the
 * wave-B carve-out: ETC software unpack disabled (Ericsson etcdec not
 * vendored). ETC targets remain reachable through Basis transcode.
 */
#ifndef XIOM_KTX2_BUILD_CONFIG_H
#define XIOM_KTX2_BUILD_CONFIG_H

#define KHRONOS_STATIC 1
#define LIBKTX 1
#define KTX_FEATURE_WRITE 1
#define KTX_FEATURE_KTX1 1
#define KTX_FEATURE_KTX2 1

/* Wave-B licence carve-out: the Ericsson ETC software unpacker is not
 * vendored; ktxint.h's SUPPORT_SOFTWARE_ETC_UNPACK default (1) is
 * overridden here before it is seen. */
#define SUPPORT_SOFTWARE_ETC_UNPACK 0

/* Basis transcoder configuration (upstream: BASISD_SUPPORT_FXT1=0 for
 * libktx; KTX2_ZSTD=0 for the ktx target). SSE/OpenCL kernels are off:
 * the xiom C++ invocation passes no per-TU ISA flags. */
#define BASISD_SUPPORT_KTX2 1
#define BASISD_SUPPORT_KTX2_ZSTD 0
#define BASISD_SUPPORT_FXT1 0
#define BASISU_SUPPORT_SSE 0
#define BASISU_SUPPORT_OPENCL 0

#endif /* XIOM_KTX2_BUILD_CONFIG_H */
"""

VERSION_HEADER = """\
/*
// [API version]
@par API Version
v4.0
// [API version]
// [Code version]
%s
// [Code version]
*/
#define LIBKTX_VERSION %s
#define LIBKTX_DEFAULT_VERSION v4.0.__default__
""" % (LIBKTX_VERSION, LIBKTX_VERSION)

INCLUDE_RE = re.compile(
    r'^([ \t]*#[ \t]*include[ \t]*)([<"])([^">]+)([>"])'
    r'([ \t]*(?://.*|/\*.*\*/)?[ \t]*)$')


def die(msg):
    sys.stderr.write("vendor_ktx: %s\n" % msg)
    raise SystemExit(1)


def blob(upstream, path):
    """Canonical LF bytes of <path> at the clone's HEAD (object store)."""
    return subprocess.check_output(
        ["git", "-C", upstream, "cat-file", "blob", "HEAD:" + path])


def mirror_list(upstream):
    rels = list(MIRROR_FILES)
    for pattern in MIRROR_GLOBS:
        hits = sorted(glob.glob(os.path.join(upstream, *pattern.split("/"))))
        for h in hits:
            rel = os.path.relpath(h, upstream).replace(os.sep, "/")
            if rel not in rels:
                rels.append(rel)
    return [r for r in rels if r not in MIRROR_EXCLUDE]


def resolve_target(mirror_root, rel_file, inc, angled):
    """Resolve an include directive inside rel_file against the vendored tree.

    Returns the mirror-relative path of the target (or the directive's own
    same-directory meaning for quoted includes), or None when the target is
    not vendored. Angle includes never search the including file's directory
    (clang semantics), so they must resolve through the search list.
    """
    file_dir = posixpath.dirname(rel_file)
    if not angled:
        cand = posixpath.normpath(posixpath.join(file_dir, inc))
        if os.path.isfile(os.path.join(mirror_root, cand.replace("/", os.sep))):
            return cand
    for d in SEARCH_DIRS:
        cand = posixpath.normpath(posixpath.join(d, inc))
        if os.path.isfile(os.path.join(mirror_root, cand.replace("/", os.sep))):
            return cand
    return None


def rewrite_includes(mirror_root, rel_file, text):
    out_lines = []
    changed = 0
    for line in text.split("\n"):
        m = INCLUDE_RE.match(line)
        if not m:
            out_lines.append(line)
            continue
        prefix, opener, inc, _closer, trailing = m.groups()
        angled = opener == "<"
        target = resolve_target(mirror_root, rel_file, inc, angled)
        if target is None and posixpath.basename(inc) in SPECIAL_RESOLVE:
            # SPECIAL_RESOLVE paths are package-root-relative; the file's
            # directory is mirror-root-relative.
            rel = posixpath.relpath(
                SPECIAL_RESOLVE[posixpath.basename(inc)],
                posixpath.join(MIRROR_ROOT, posixpath.dirname(rel_file)))
            out_lines.append('%s"%s"%s' % (prefix, rel, trailing))
            changed += 1
            continue
        if target is None:
            out_lines.append(line)
            continue
        same_dir = posixpath.normpath(
            posixpath.join(posixpath.dirname(rel_file), inc))
        if not angled and target == same_dir:
            out_lines.append(line)
            continue
        rel = posixpath.relpath(target, posixpath.dirname(rel_file))
        out_lines.append('%s"%s"%s' % (prefix, rel, trailing))
        changed += 1
    return "\n".join(out_lines), changed


def prologue_for(rel_file):
    # CONFIG_HEADER_REL and rel_file are both relative to the mirror root.
    rel = posixpath.relpath(CONFIG_HEADER_REL, posixpath.dirname(rel_file))
    return ('/* xiom.ktx2: generated build configuration (tools/vendor_ktx.py). */\n'
            '#include "%s"\n' % rel)


def walk_files(root):
    files = []
    for dirpath, _dirs, names in os.walk(root):
        for n in names:
            files.append(os.path.join(dirpath, n))
    return sorted(files)


def tree_hash(mirror_root):
    digest = hashlib.sha256()
    files = walk_files(mirror_root)
    for p in files:
        rel = os.path.relpath(p, mirror_root).replace(os.sep, "/")
        digest.update(rel.encode("utf-8"))
        digest.update(b"\0")
        with open(p, "rb") as f:
            digest.update(hashlib.sha256(f.read()).digest())
    return digest.hexdigest().upper(), files


def write_manifest(mirror_root, out_path):
    rows = []
    for p in walk_files(mirror_root):
        rel = os.path.relpath(p, mirror_root).replace(os.sep, "/")
        with open(p, "rb") as f:
            data = f.read()
        rows.append((rel, len(data), hashlib.sha256(data).hexdigest().upper()))
    rows.sort()
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        for rel, size, h in rows:
            f.write("%s  %d  %s\n" % (h, size, rel))
    return len(rows)


def write_port_args(pkg_dir):
    args = []
    args += ["--c-source", "${PACKAGE_DIR}/src/ktx2_bridge.c"]
    args += ["--c-source", "${PACKAGE_DIR}/src/zstd_shim.c"]
    for rel in KTX_C_TUS:
        args += ["--c-source", "${PACKAGE_DIR}/%s/%s" % (MIRROR_ROOT, rel)]
    for rel in KTX_CXX_TUS:
        args += ["--c-source", "${PACKAGE_DIR}/%s/%s" % (MIRROR_ROOT, rel)]
    for rel in ASTC_CXX_TUS:
        args += ["--c-source", "${PACKAGE_DIR}/%s/%s" % (MIRROR_ROOT, rel)]
    args += ["--cxx-standard", "17"]
    args += ["--timeout", "1800"]
    path = os.path.join(pkg_dir, "port.args.json")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(args, f, indent=2)
        f.write("\n")
    return len(KTX_C_TUS) + len(KTX_CXX_TUS) + len(ASTC_CXX_TUS) + 2


def main(argv):
    if len(argv) >= 3 and argv[1] == "--hash":
        h, files = tree_hash(os.path.join(argv[2], MIRROR_ROOT.replace("/", os.sep)))
        print("tree files: %d" % len(files))
        print("tree sha256: %s" % h)
        return 0
    if len(argv) < 3:
        print(__doc__)
        return 2
    upstream = argv[1]
    pkg_dir = argv[2]
    skip_clean = "--skip-clean" in argv

    head = subprocess.check_output(
        ["git", "-C", upstream, "rev-parse", "HEAD"], text=True).strip()
    if head != PIN_COMMIT:
        die("upstream HEAD %s != pin %s; re-carve deliberately" % (head, PIN_COMMIT))
    print("pin verified: %s (%s)" % (head, PIN_TAG))

    mirror_root = os.path.join(pkg_dir, MIRROR_ROOT.replace("/", os.sep))
    if not skip_clean and os.path.isdir(mirror_root):
        shutil.rmtree(mirror_root)
    os.makedirs(mirror_root, exist_ok=True)

    # 1. extract canonical blobs (object store; LF already, normalized for
    #    safety), written verbatim.
    rels = mirror_list(upstream)
    for rel in rels:
        data = blob(upstream, rel).replace(b"\r\n", b"\n")
        dst = os.path.join(mirror_root, rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as f:
            f.write(data)

    # 2. rewrite includes (resolved against the now-complete mirror).
    # 3. inject the build-config prologue into the compiled TUs.
    for rel in BUILD_CONFIG_TUS + ASTC_CXX_TUS:
        if not os.path.isfile(os.path.join(mirror_root, rel.replace("/", os.sep))):
            die("compiled TU not mirrored: %s" % rel)
    rewritten = 0
    for rel in rels:
        if not rel.endswith(TEXT_EXTS):
            continue
        path = os.path.join(mirror_root, rel.replace("/", os.sep))
        with open(path, "r", encoding="utf-8", newline="") as f:
            text = f.read()
        text, n = rewrite_includes(mirror_root, rel, text)
        if n:
            rewritten += n
        if rel in BUILD_CONFIG_TUS:
            text = prologue_for(rel) + text
            n += 1
        if n:
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)

    # 4. generated files
    with open(os.path.join(mirror_root, "lib", "version.h"), "w",
              encoding="utf-8", newline="\n") as f:
        f.write(VERSION_HEADER)
    with open(os.path.join(mirror_root, CONFIG_HEADER_REL), "w",
              encoding="utf-8", newline="\n") as f:
        f.write(BUILD_CONFIG)

    # 5. manifest + port.args.json
    manifest = os.path.join(pkg_dir, "vendor", "FILES.sha256")
    count = write_manifest(mirror_root, manifest)
    tu_count = write_port_args(pkg_dir)

    h, files = tree_hash(mirror_root)
    print("mirrored files:      %d" % len(files))
    print("manifest rows:       %d (%s)" % (count, manifest))
    print("rewrite/edit ops:    %d (includes + prologues)" % rewritten)
    print("config prologues:    %d TUs" % len(BUILD_CONFIG_TUS))
    print("port.args.json TUs:  %d --c-source entries" % tu_count)
    print("tree sha256:         %s" % h)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
