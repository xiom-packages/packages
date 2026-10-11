#!/usr/bin/env python3
"""Embed the committed SPIR-V fixture as a deterministic XIOM fragment.

Reads tools/shaders/min.frag.spv (assembled from the committed
tools/shaders/min.frag.spvasm with the Vulkan SDK's spirv-as) and writes
tools/gen/20_fixtures.xifrag, then re-assembles the package's single XIOM
module (spirv_cross.xi) from all tools/gen/*.xifrag fragments.

The fragment provides:

    pub const MIN_FRAG_SPV_WORDS: Int = <words>;
    pub const MIN_FRAG_SPV_BYTES: Int = <bytes>;
    pub fn min_frag_spv() -> Vec[UInt8]  -- little-endian SPIR-V bytes in an
                                            XIOM-owned Vec[UInt8]

Byte-indexed construction only (B-11..B-20 layout hygiene): the words are
unpacked with shift/mask into UInt8 pushes.

Usage: python tools/embed_spv_xiom.py
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import gen_spirv_cross  # noqa: E402  (committed sibling generator)

SPV = os.path.join(HERE, "shaders", "min.frag.spv")
OUT = os.path.join(HERE, "gen", "20_fixtures.xifrag")


def main():
    data = io.open(SPV, "rb").read()
    if len(data) % 4 != 0:
        raise SystemExit("SPIR-V size is not a multiple of 4")
    words = [int.from_bytes(data[i:i + 4], "little")
             for i in range(0, len(data), 4)]

    lines = []
    lines.append("// " + gen_spirv_cross.GEN_TAG)
    lines.append("// SPIR-V fixture: tools/shaders/min.frag.spvasm -> min.frag.spv")
    lines.append("// (assembled with spirv-as from Vulkan SDK 1.4.350.0;")
    lines.append("// validated with spirv-val).")
    lines.append("")
    lines.append("/// SPIR-V word count of the embedded fragment shader.")
    lines.append("pub const MIN_FRAG_SPV_WORDS: Int = %d;" % len(words))
    lines.append("")
    lines.append("/// Little-endian byte count of the embedded fragment shader.")
    lines.append("pub const MIN_FRAG_SPV_BYTES: Int = %d;" % len(data))
    lines.append("")
    lines.append("fn push_u32_le(s: &mut Vec[UInt8], w: Int)")
    lines.append("  requires: w >= 0")
    lines.append("  requires: w <= 0xFFFFFFFF")
    lines.append("{")
    lines.append("  s.push((w & 0xFF) as UInt8);")
    lines.append("  s.push(((w >> 8) & 0xFF) as UInt8);")
    lines.append("  s.push(((w >> 16) & 0xFF) as UInt8);")
    lines.append("  s.push(((w >> 24) & 0xFF) as UInt8);")
    lines.append("}")
    lines.append("")
    lines.append("/// The fixture: a SPIR-V 1.0 fragment shader with one stage input,")
    lines.append("/// one stage output and one uniform buffer (3 reflected resources);")
    lines.append('/// GLSL cross-compile output contains "void main".')
    lines.append("/// Complexity: O(words).")
    lines.append("pub fn min_frag_spv() -> Vec[UInt8]")
    lines.append("  requires: true")
    lines.append("{")
    lines.append("  var s: Vec[UInt8] = Vec[UInt8].new();")
    for w in words:
        lines.append("  push_u32_le(&mut s, 0x%08X);" % w)
    lines.append("  return s;")
    lines.append("}")
    lines.append("")

    with io.open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))
    gen_spirv_cross.combine(PKG)
    print("wrote %s (%d words, %d bytes); reassembled spirv_cross.xi"
          % (OUT, len(words), len(data)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
