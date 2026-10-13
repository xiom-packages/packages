#!/usr/bin/env python3
# ============================================================================
# XIOM -- tiny TTF fixture generator for xiom.harfbuzz tests
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
# Licensed under the MIT or Apache-2.0 license, at your option.
# ============================================================================
#
# Writes `tests/fixtures/tiny.ttf`: an ORIGINAL minimal TrueType font that
# is fully under this repository's license (no third-party font is bundled;
# PROVENANCE.md records the "generated/minimal TTF" disposition).
#
# The font has 3 glyphs and is shaped deterministically by harfbuzz:
#   gid 0  .notdef   advance 500 (empty)
#   gid 1  'A' U+0041 advance 500 (triangle contour)
#   gid 2  'V' U+0056 advance 600 (triangle contour)
# Table set: head, hhea, maxp, hmtx, cmap(4), glyf, loca(short), name,
# OS/2(v1), post(v3).  No GPOS/GSUB -> advances come from hmtx exactly, so
# the shape probes have exact expected values (500 + 600 = 1100 for "AV").
#
# Usage: python tests/fixtures/make_tiny_font.py [out.ttf]
# ============================================================================

import struct
import sys

UPEM = 1000
GLYPHS = [
    ("notdef", 500, 0, None),
    # name, advance, lsb, contour points (x, y)
    ("A", 500, 50, [(50, 0), (450, 0), (250, 700)]),
    ("V", 600, 60, [(60, 700), (510, 700), (285, 0)]),
]


def be16(v):
    return struct.pack(">H", v & 0xFFFF)


def be16s(v):
    return struct.pack(">h", v)


def be32(v):
    return struct.pack(">I", v & 0xFFFFFFFF)


def checksum(data):
    pad = (-len(data)) % 4
    data = data + b"\0" * pad
    total = 0
    for i in range(0, len(data), 4):
        total = (total + struct.unpack(">I", data[i:i + 4])[0]) & 0xFFFFFFFF
    return total


def build_glyf_loca():
    glyf = b""
    offsets = []
    for _, _, _, pts in GLYPHS:
        offsets.append(len(glyf))
        if pts is None:
            continue
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        g = be16s(1)                              # numberOfContours
        g += be16s(min(xs)) + be16s(min(ys)) + be16s(max(xs)) + be16s(max(ys))
        g += be16(2)                              # endPtsOfContours[0]
        g += be16(0)                              # instructionLength
        g += bytes([0x01, 0x01, 0x01])            # on-curve flags
        # x deltas
        prev = 0
        for x in xs:
            g += be16s(x - prev)
            prev = x
        prev = 0
        for y in ys:
            g += be16s(y - prev)
            prev = y
        pad = (-len(g)) % 4
        g += b"\0" * pad
        glyf += g
    offsets.append(len(glyf))
    # short loca (offsets / 2); even offsets guaranteed by 4-byte padding
    loca = b"".join(be16(o // 2) for o in offsets)
    return glyf, loca


def build_head(num_tables):
    # magic + flags/macStyle, unitsPerEm 1000, bbox 0,0,610,700
    data = be32(0x00010000)          # version
    data += be32(0x00010000)         # fontRevision
    data += be32(0)                  # checkSumAdjustment (patched later)
    data += be32(0x5F0F3CF5)         # magicNumber
    data += be16(0x000B)             # flags
    data += be16(1000)               # unitsPerEm
    data += struct.pack(">q", 0)     # created
    data += struct.pack(">q", 0)     # modified
    data += be16s(0) + be16s(0) + be16s(610) + be16s(700)   # bbox
    data += be16(0)                  # macStyle
    data += be16(8)                  # lowestRecPPEM
    data += be16s(2)                 # fontDirectionHint
    data += be16s(0)                 # indexToLocFormat (short)
    data += be16s(0)                 # glyphDataFormat
    return data


def build_hhea(num_hmetrics):
    data = be32(0x00010000)          # version
    data += be16s(800)               # ascender
    data += be16s(-200)              # descender
    data += be16s(0)                 # lineGap
    data += be16(600)                # advanceWidthMax
    data += be16s(0)                 # minLeftSideBearing
    data += be16s(60)                # minRightSideBearing
    data += be16s(510)               # xMaxExtent
    data += be16s(1)                 # caretSlopeRise
    data += be16s(0)                 # caretSlopeRun
    data += be16s(0)                 # caretOffset
    data += be16s(0) * 4             # reserved
    data += be16s(0)                 # metricDataFormat
    data += be16(num_hmetrics)       # numberOfHMetrics
    return data


def build_maxp(num_glyphs):
    data = be32(0x00010000)          # version 1.0
    data += be16(num_glyphs)
    data += be16(3)                  # maxPoints
    data += be16(1)                  # maxContours
    data += be16(0)                  # maxCompositePoints
    data += be16(0)                  # maxCompositeContours
    data += be16(2)                  # maxZones
    data += be16(0)                  # maxTwilightPoints
    data += be16(0)                  # maxStorage
    data += be16(0)                  # maxFunctionDefs
    data += be16(0)                  # maxInstructionDefs
    data += be16(0)                  # maxStackElements
    data += be16(0)                  # maxSizeOfInstructions
    data += be16(0)                  # maxComponentElements
    data += be16(0)                  # maxComponentDepth
    return data


def build_hmtx():
    return b"".join(be16(a) + be16s(lsb) for _, a, lsb, _ in GLYPHS)


def build_cmap():
    segs = [(0x0041, 0x0041, (1 - 0x0041) & 0xFFFF),
            (0x0056, 0x0056, (2 - 0x0056) & 0xFFFF),
            (0xFFFF, 0xFFFF, 1)]
    seg_count = len(segs)
    import math
    exp = int(math.log(seg_count, 2))
    search_range = 2 * (2 ** exp)
    entry_selector = exp
    range_shift = seg_count * 2 - search_range
    sub = be16(4)                                  # format
    sub += be16(16 + 8 * seg_count)                # length
    sub += be16(0)                                 # language
    sub += be16(seg_count * 2)
    sub += be16(search_range) + be16(entry_selector) + be16(range_shift)
    for s, e, _ in segs:
        sub += be16(e)
    sub += be16(0)                                 # reservedPad
    for s, e, _ in segs:
        sub += be16(s)
    for s, e, d in segs:
        sub += be16(d)
    for s, e, d in segs:
        sub += be16(0)                             # idRangeOffset
    # cmap table header: version 0, one (3,1) BMP subtable at offset 12
    cmap = be16(0) + be16(1) + be16(3) + be16(1) + be32(12) + sub
    return cmap


def u16be_string(s):
    return s.encode("utf-16-be")


def build_name():
    recs = [(1, "XIOM Tiny"), (6, "XIOMTiny-Regular")]
    strings = b""
    offsets = []
    for _, s in recs:
        offsets.append(len(strings))
        strings += u16be_string(s)
    count = len(recs)
    header = be16(0) + be16(count) + be16(6 + 12 * count)
    records = b""
    for i, (nid, _) in enumerate(recs):
        records += be16(3) + be16(1) + be16(0x0409) + be16(nid)
        records += be16(len(u16be_string(recs[i][1]))) + be16(offsets[i])
    return header + records + strings


def build_os2():
    data = be16(1)                   # version 1 (86 bytes; v2+ needs 96)
    data += be16s(550)               # xAvgCharWidth
    data += be16(400)                # usWeightClass
    data += be16(5)                  # usWidthClass
    data += be16(0)                  # fsType
    data += be16s(650) + be16s(150)  # ySubscriptXSize/YSize
    data += be16s(0) + be16s(0)      # ySubscriptX/YOffset
    data += be16s(650) + be16s(150)  # ySuperscriptXSize/YSize
    data += be16s(0) + be16s(0)      # ySuperscriptX/YOffset
    data += be16s(50)                # yStrikeoutSize
    data += be16s(250)               # yStrikeoutPosition
    data += be16s(0)                 # sFamilyClass
    data += bytes(10)                # panose
    data += be32(0x00000001)         # ulUnicodeRange1 (Basic Latin)
    data += be32(0) + be32(0) + be32(0)
    data += b"XIOM"                  # achVendID
    data += be16(0x0040)             # fsSelection (REGULAR)
    data += be16(0x0041)             # usFirstCharIndex
    data += be16(0x0056)             # usLastCharIndex
    data += be16s(800)               # sTypoAscender
    data += be16s(-200)              # sTypoDescender
    data += be16s(0)                 # sTypoLineGap
    data += be16(800)                # usWinAscent
    data += be16(200)                # usWinDescent
    data += be32(0x00000001)         # ulCodePageRange1 (Latin 1)
    data += be32(0)                  # ulCodePageRange2
    return data


def build_post():
    data = be32(0x00030000)          # version 3.0 (no glyph names)
    data += be32(0)                  # italicAngle
    data += be16s(-100)              # underlinePosition
    data += be16s(50)                # underlineThickness
    data += be32(0)                  # isFixedPitch
    data += be32(0) + be32(0) + be32(0) + be32(0)   # memory
    return data


def build_font():
    glyf, loca = build_glyf_loca()
    tables = {
        "cmap": build_cmap(),
        "glyf": glyf,
        "head": build_head(10),
        "hhea": build_hhea(len(GLYPHS)),
        "hmtx": build_hmtx(),
        "loca": loca,
        "maxp": build_maxp(len(GLYPHS)),
        "name": build_name(),
        "OS/2": build_os2(),
        "post": build_post(),
    }
    tags = sorted(tables.keys())
    num = len(tags)
    import math
    exp = int(math.log(num, 2))
    search_range = 16 * (2 ** exp)
    entry_selector = exp
    range_shift = num * 16 - search_range
    header = be32(0x00010000) + be16(num) + be16(search_range)
    header += be16(entry_selector) + be16(range_shift)
    directory = b""
    offset = 12 + 16 * num
    body = b""
    entries = {}
    for tag in tags:
        data = tables[tag]
        entries[tag] = (offset, checksum(data), len(data))
        directory += tag.encode("ascii") + be32(entries[tag][1])
        directory += be32(offset) + be32(len(data))
        body += data + b"\0" * ((-len(data)) % 4)
        offset += len(data) + ((-len(data)) % 4)
    font = header + directory + body
    # patch head.checkSumAdjustment
    head_off = entries["head"][0]
    total = checksum(font)
    adj = (0xB1B0AFBA - total) & 0xFFFFFFFF
    font = font[:head_off + 8] + be32(adj) + font[head_off + 12:]
    return font


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "tests/fixtures/tiny.ttf"
    data = build_font()
    with open(out, "wb") as f:
        f.write(data)
    print("wrote %s (%d bytes)" % (out, len(data)))


if __name__ == "__main__":
    main()
