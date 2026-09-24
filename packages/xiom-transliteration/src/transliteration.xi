// XIOM -- xiom.transliteration: UTF-8 to ASCII transliteration
// Port task: replace the xiom.transliteration placeholder with a real, tested,
// pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// What is covered (see SPEC.md for the exact decode rules, the table format
// and the test plan):
//   * translit_is_ascii: true when every byte of the input is < 0x80;
//   * translit_to_ascii: decode UTF-8 codepoints and map them through a
//     curated codepoint -> replacement table:
//       - Latin-1 Supplement letters (U+00C0-U+00FF),
//       - Latin Extended-A (U+0100-U+017F, complete block),
//       - Greek (U+0386-U+03CE letters and accented forms),
//       - Cyrillic (U+0400-U+045F core block, selected extensions,
//         U+0490/U+0491),
//       - punctuation U+2013/2014, U+2018/2019, U+201C/201D, U+2026,
//       - NBSP (U+00A0) -> one ASCII space;
//     ASCII bytes pass through unchanged; codepoints with no table entry are
//     dropped (documented, see README "Limitations");
//   * translit_slug: translit_to_ascii, lowercase, non-alphanumeric runs ->
//     one '-', trim leading/trailing '-', "" when nothing survives.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * The table is two parallel Vecs (Vec[Int] keys + Vec[Str] values, same
//     index) because Vec[StructType] is not usable; the values are only ever
//     read into typed locals and never compared with `==` (BUG 17).
//   * Guard predicates work in Int space (`(byte as Int) & 0xFF`) so no UInt8
//     comparison against a literal >= 128 is ever performed.
//   * Output is accumulated in a Vec[UInt8] and materialized once with
//     xiom.string.builder.sb_to_str (one allocation per result).
//
// Infallible by design: both functions return Str; dropped codepoints and
// invalid bytes are never reported.

module xiom.transliteration

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Byte constants (Int space)
// --------------------------------------------------

const _TL_NBSP: Int = 0x00A0;

const _TL_EN_DASH: Int = 0x2013;
const _TL_EM_DASH: Int = 0x2014;
const _TL_LQUOTE: Int = 0x2018;
const _TL_RQUOTE: Int = 0x2019;
const _TL_LDQUOTE: Int = 0x201C;
const _TL_RDQUOTE: Int = 0x201D;
const _TL_ELLIPSIS: Int = 0x2026;

const _TL_SPACE: Int = 0x20;
const _TL_DASH: Int = 0x2D;

// --------------------------------------------------
//  UTF-8 decoding (RFC 3629, manual)
// --------------------------------------------------

// Sequence length in bytes from a lead byte: 0xxxxxxx -> 1, 110xxxxx -> 2,
// 1110xxxx -> 3, 11110xxx -> 4; any other byte (including a stray
// continuation byte 10xxxxxx) counts as 1 so the caller passes it through.
fn _tl_seq_len(b0: Int) -> Int {
  if b0 < 0x80 {
    return 1;
  }
  if (b0 & 0xE0) == 0xC0 {
    return 2;
  }
  if (b0 & 0xF0) == 0xE0 {
    return 3;
  }
  if (b0 & 0xF8) == 0xF0 {
    return 4;
  }
  return 1;
}

// Decode one UTF-8 codepoint at byte offset `pos` of `s`.
// Returns the codepoint (>= 0), or -1 when the bytes at `pos` do not form a
// valid sequence. Invalid covers: truncated sequences, a non-continuation
// byte where 10xxxxxx is required, overlong encodings, surrogates
// U+D800-U+DFFF, and codepoints above U+10FFFF. The caller advances by one
// byte on -1 ("invalid sequences pass through one byte at a time").
fn _tl_decode(s: Str, pos: Int) -> Int {
  let n = s.len();
  let b0: Int = (string.byte_at(s, pos) as Int) & 0xFF;
  if b0 < 0x80 {
    return b0;
  }
  if (b0 & 0xE0) == 0xC0 {
    if pos + 2 > n {
      return -1;
    }
    let b1: Int = (string.byte_at(s, pos + 1) as Int) & 0xFF;
    if (b1 & 0xC0) != 0x80 {
      return -1;
    }
    let cp: Int = ((b0 & 0x1F) << 6) | (b1 & 0x3F);
    if cp < 0x80 {
      return -1;
    }
    return cp;
  }
  if (b0 & 0xF0) == 0xE0 {
    if pos + 3 > n {
      return -1;
    }
    let b1: Int = (string.byte_at(s, pos + 1) as Int) & 0xFF;
    let b2: Int = (string.byte_at(s, pos + 2) as Int) & 0xFF;
    if (b1 & 0xC0) != 0x80 {
      return -1;
    }
    if (b2 & 0xC0) != 0x80 {
      return -1;
    }
    let cp: Int = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F);
    if cp < 0x800 {
      return -1;
    }
    if cp >= 0xD800 && cp <= 0xDFFF {
      return -1;
    }
    return cp;
  }
  if (b0 & 0xF8) == 0xF0 {
    if pos + 4 > n {
      return -1;
    }
    let b1: Int = (string.byte_at(s, pos + 1) as Int) & 0xFF;
    let b2: Int = (string.byte_at(s, pos + 2) as Int) & 0xFF;
    let b3: Int = (string.byte_at(s, pos + 3) as Int) & 0xFF;
    if (b1 & 0xC0) != 0x80 {
      return -1;
    }
    if (b2 & 0xC0) != 0x80 {
      return -1;
    }
    if (b3 & 0xC0) != 0x80 {
      return -1;
    }
    let cp: Int = ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F);
    if cp < 0x10000 {
      return -1;
    }
    if cp > 0x10FFFF {
      return -1;
    }
    return cp;
  }
  return -1;
}

// --------------------------------------------------
//  Transliteration table
// --------------------------------------------------

// Fill the codepoint -> replacement table into two parallel vectors.
// INVARIANT: every keys.push is immediately followed by the matching
// vals.push, so keys[i] and vals[i] always describe the same mapping.
// Coverage: 62 Latin-1 Supplement letters, 128 Latin Extended-A codepoints
// (U+0100-U+017F complete), 69 Greek codepoints (U+0386-U+03CE),
// 92 Cyrillic codepoints (U+0400-U+045F core block plus selected
// extensions and U+0490/U+0491), and 8 punctuation/NBSP codepoints
// (359 entries total, all keys distinct).
fn _tl_fill(keys: &mut Vec[Int], vals: &mut Vec[Str]) {
  // Latin-1 Supplement, uppercase letters (U+00C0-U+00DF).
  keys.push(0x00C0); vals.push("A");
  keys.push(0x00C1); vals.push("A");
  keys.push(0x00C2); vals.push("A");
  keys.push(0x00C3); vals.push("A");
  keys.push(0x00C4); vals.push("A");
  keys.push(0x00C5); vals.push("A");
  keys.push(0x00C6); vals.push("AE");
  keys.push(0x00C7); vals.push("C");
  keys.push(0x00C8); vals.push("E");
  keys.push(0x00C9); vals.push("E");
  keys.push(0x00CA); vals.push("E");
  keys.push(0x00CB); vals.push("E");
  keys.push(0x00CC); vals.push("I");
  keys.push(0x00CD); vals.push("I");
  keys.push(0x00CE); vals.push("I");
  keys.push(0x00CF); vals.push("I");
  keys.push(0x00D0); vals.push("D");
  keys.push(0x00D1); vals.push("N");
  keys.push(0x00D2); vals.push("O");
  keys.push(0x00D3); vals.push("O");
  keys.push(0x00D4); vals.push("O");
  keys.push(0x00D5); vals.push("O");
  keys.push(0x00D6); vals.push("O");
  keys.push(0x00D8); vals.push("O");
  keys.push(0x00D9); vals.push("U");
  keys.push(0x00DA); vals.push("U");
  keys.push(0x00DB); vals.push("U");
  keys.push(0x00DC); vals.push("U");
  keys.push(0x00DD); vals.push("Y");
  keys.push(0x00DE); vals.push("Th");
  keys.push(0x00DF); vals.push("ss");
  // Latin-1 Supplement, lowercase letters (U+00E0-U+00FF).
  keys.push(0x00E0); vals.push("a");
  keys.push(0x00E1); vals.push("a");
  keys.push(0x00E2); vals.push("a");
  keys.push(0x00E3); vals.push("a");
  keys.push(0x00E4); vals.push("a");
  keys.push(0x00E5); vals.push("a");
  keys.push(0x00E6); vals.push("ae");
  keys.push(0x00E7); vals.push("c");
  keys.push(0x00E8); vals.push("e");
  keys.push(0x00E9); vals.push("e");
  keys.push(0x00EA); vals.push("e");
  keys.push(0x00EB); vals.push("e");
  keys.push(0x00EC); vals.push("i");
  keys.push(0x00ED); vals.push("i");
  keys.push(0x00EE); vals.push("i");
  keys.push(0x00EF); vals.push("i");
  keys.push(0x00F0); vals.push("d");
  keys.push(0x00F1); vals.push("n");
  keys.push(0x00F2); vals.push("o");
  keys.push(0x00F3); vals.push("o");
  keys.push(0x00F4); vals.push("o");
  keys.push(0x00F5); vals.push("o");
  keys.push(0x00F6); vals.push("o");
  keys.push(0x00F8); vals.push("o");
  keys.push(0x00F9); vals.push("u");
  keys.push(0x00FA); vals.push("u");
  keys.push(0x00FB); vals.push("u");
  keys.push(0x00FC); vals.push("u");
  keys.push(0x00FD); vals.push("y");
  keys.push(0x00FE); vals.push("th");
  keys.push(0x00FF); vals.push("y");
  // Latin Extended-A (U+0100-U+017F, complete block).
  keys.push(0x0100); vals.push("A");
  keys.push(0x0101); vals.push("a");
  keys.push(0x0102); vals.push("A");
  keys.push(0x0103); vals.push("a");
  keys.push(0x0104); vals.push("A");
  keys.push(0x0105); vals.push("a");
  keys.push(0x0106); vals.push("C");
  keys.push(0x0107); vals.push("c");
  keys.push(0x0108); vals.push("C");
  keys.push(0x0109); vals.push("c");
  keys.push(0x010A); vals.push("C");
  keys.push(0x010B); vals.push("c");
  keys.push(0x010C); vals.push("C");
  keys.push(0x010D); vals.push("c");
  keys.push(0x010E); vals.push("D");
  keys.push(0x010F); vals.push("d");
  keys.push(0x0110); vals.push("D");
  keys.push(0x0111); vals.push("d");
  keys.push(0x0112); vals.push("E");
  keys.push(0x0113); vals.push("e");
  keys.push(0x0114); vals.push("E");
  keys.push(0x0115); vals.push("e");
  keys.push(0x0116); vals.push("E");
  keys.push(0x0117); vals.push("e");
  keys.push(0x0118); vals.push("E");
  keys.push(0x0119); vals.push("e");
  keys.push(0x011A); vals.push("E");
  keys.push(0x011B); vals.push("e");
  keys.push(0x011C); vals.push("G");
  keys.push(0x011D); vals.push("g");
  keys.push(0x011E); vals.push("G");
  keys.push(0x011F); vals.push("g");
  keys.push(0x0120); vals.push("G");
  keys.push(0x0121); vals.push("g");
  keys.push(0x0122); vals.push("G");
  keys.push(0x0123); vals.push("g");
  keys.push(0x0124); vals.push("H");
  keys.push(0x0125); vals.push("h");
  keys.push(0x0126); vals.push("H");
  keys.push(0x0127); vals.push("h");
  keys.push(0x0128); vals.push("I");
  keys.push(0x0129); vals.push("i");
  keys.push(0x012A); vals.push("I");
  keys.push(0x012B); vals.push("i");
  keys.push(0x012C); vals.push("I");
  keys.push(0x012D); vals.push("i");
  keys.push(0x012E); vals.push("I");
  keys.push(0x012F); vals.push("i");
  keys.push(0x0130); vals.push("I");
  keys.push(0x0131); vals.push("i");
  keys.push(0x0132); vals.push("IJ");
  keys.push(0x0133); vals.push("ij");
  keys.push(0x0134); vals.push("J");
  keys.push(0x0135); vals.push("j");
  keys.push(0x0136); vals.push("K");
  keys.push(0x0137); vals.push("k");
  keys.push(0x0138); vals.push("k");
  keys.push(0x0139); vals.push("L");
  keys.push(0x013A); vals.push("l");
  keys.push(0x013B); vals.push("L");
  keys.push(0x013C); vals.push("l");
  keys.push(0x013D); vals.push("L");
  keys.push(0x013E); vals.push("l");
  keys.push(0x013F); vals.push("L");
  keys.push(0x0140); vals.push("l");
  keys.push(0x0141); vals.push("L");
  keys.push(0x0142); vals.push("l");
  keys.push(0x0143); vals.push("N");
  keys.push(0x0144); vals.push("n");
  keys.push(0x0145); vals.push("N");
  keys.push(0x0146); vals.push("n");
  keys.push(0x0147); vals.push("N");
  keys.push(0x0148); vals.push("n");
  keys.push(0x0149); vals.push("n");
  keys.push(0x014A); vals.push("N");
  keys.push(0x014B); vals.push("n");
  keys.push(0x014C); vals.push("O");
  keys.push(0x014D); vals.push("o");
  keys.push(0x014E); vals.push("O");
  keys.push(0x014F); vals.push("o");
  keys.push(0x0150); vals.push("O");
  keys.push(0x0151); vals.push("o");
  keys.push(0x0152); vals.push("OE");
  keys.push(0x0153); vals.push("oe");
  keys.push(0x0154); vals.push("R");
  keys.push(0x0155); vals.push("r");
  keys.push(0x0156); vals.push("R");
  keys.push(0x0157); vals.push("r");
  keys.push(0x0158); vals.push("R");
  keys.push(0x0159); vals.push("r");
  keys.push(0x015A); vals.push("S");
  keys.push(0x015B); vals.push("s");
  keys.push(0x015C); vals.push("S");
  keys.push(0x015D); vals.push("s");
  keys.push(0x015E); vals.push("S");
  keys.push(0x015F); vals.push("s");
  keys.push(0x0160); vals.push("S");
  keys.push(0x0161); vals.push("s");
  keys.push(0x0162); vals.push("T");
  keys.push(0x0163); vals.push("t");
  keys.push(0x0164); vals.push("T");
  keys.push(0x0165); vals.push("t");
  keys.push(0x0166); vals.push("T");
  keys.push(0x0167); vals.push("t");
  keys.push(0x0168); vals.push("U");
  keys.push(0x0169); vals.push("u");
  keys.push(0x016A); vals.push("U");
  keys.push(0x016B); vals.push("u");
  keys.push(0x016C); vals.push("U");
  keys.push(0x016D); vals.push("u");
  keys.push(0x016E); vals.push("U");
  keys.push(0x016F); vals.push("u");
  keys.push(0x0170); vals.push("U");
  keys.push(0x0171); vals.push("u");
  keys.push(0x0172); vals.push("U");
  keys.push(0x0173); vals.push("u");
  keys.push(0x0174); vals.push("W");
  keys.push(0x0175); vals.push("w");
  keys.push(0x0176); vals.push("Y");
  keys.push(0x0177); vals.push("y");
  keys.push(0x0178); vals.push("Y");
  keys.push(0x0179); vals.push("Z");
  keys.push(0x017A); vals.push("z");
  keys.push(0x017B); vals.push("Z");
  keys.push(0x017C); vals.push("z");
  keys.push(0x017D); vals.push("Z");
  keys.push(0x017E); vals.push("z");
  keys.push(0x017F); vals.push("s");
  // Greek: accented capitals, capitals, accented lowercase, lowercase.
  keys.push(0x0386); vals.push("A");
  keys.push(0x0388); vals.push("E");
  keys.push(0x0389); vals.push("E");
  keys.push(0x038A); vals.push("I");
  keys.push(0x038C); vals.push("O");
  keys.push(0x038E); vals.push("Y");
  keys.push(0x038F); vals.push("O");
  keys.push(0x0390); vals.push("i");
  keys.push(0x0391); vals.push("A");
  keys.push(0x0392); vals.push("B");
  keys.push(0x0393); vals.push("G");
  keys.push(0x0394); vals.push("D");
  keys.push(0x0395); vals.push("E");
  keys.push(0x0396); vals.push("Z");
  keys.push(0x0397); vals.push("E");
  keys.push(0x0398); vals.push("Th");
  keys.push(0x0399); vals.push("I");
  keys.push(0x039A); vals.push("K");
  keys.push(0x039B); vals.push("L");
  keys.push(0x039C); vals.push("M");
  keys.push(0x039D); vals.push("N");
  keys.push(0x039E); vals.push("X");
  keys.push(0x039F); vals.push("O");
  keys.push(0x03A0); vals.push("P");
  keys.push(0x03A1); vals.push("R");
  keys.push(0x03A3); vals.push("S");
  keys.push(0x03A4); vals.push("T");
  keys.push(0x03A5); vals.push("Y");
  keys.push(0x03A6); vals.push("Ph");
  keys.push(0x03A7); vals.push("Ch");
  keys.push(0x03A8); vals.push("Ps");
  keys.push(0x03A9); vals.push("O");
  keys.push(0x03AA); vals.push("I");
  keys.push(0x03AB); vals.push("Y");
  keys.push(0x03AC); vals.push("a");
  keys.push(0x03AD); vals.push("e");
  keys.push(0x03AE); vals.push("e");
  keys.push(0x03AF); vals.push("i");
  keys.push(0x03B0); vals.push("y");
  keys.push(0x03B1); vals.push("a");
  keys.push(0x03B2); vals.push("b");
  keys.push(0x03B3); vals.push("g");
  keys.push(0x03B4); vals.push("d");
  keys.push(0x03B5); vals.push("e");
  keys.push(0x03B6); vals.push("z");
  keys.push(0x03B7); vals.push("e");
  keys.push(0x03B8); vals.push("th");
  keys.push(0x03B9); vals.push("i");
  keys.push(0x03BA); vals.push("k");
  keys.push(0x03BB); vals.push("l");
  keys.push(0x03BC); vals.push("m");
  keys.push(0x03BD); vals.push("n");
  keys.push(0x03BE); vals.push("x");
  keys.push(0x03BF); vals.push("o");
  keys.push(0x03C0); vals.push("p");
  keys.push(0x03C1); vals.push("r");
  keys.push(0x03C2); vals.push("s");
  keys.push(0x03C3); vals.push("s");
  keys.push(0x03C4); vals.push("t");
  keys.push(0x03C5); vals.push("y");
  keys.push(0x03C6); vals.push("ph");
  keys.push(0x03C7); vals.push("ch");
  keys.push(0x03C8); vals.push("ps");
  keys.push(0x03C9); vals.push("o");
  keys.push(0x03CA); vals.push("i");
  keys.push(0x03CB); vals.push("y");
  keys.push(0x03CC); vals.push("o");
  keys.push(0x03CD); vals.push("y");
  keys.push(0x03CE); vals.push("o");
  // Cyrillic: extensions, capitals U+0410-U+042F, lowercase U+0430-U+044F,
  // lowercase extensions, Ukrainian U+0490/U+0491. Hard and soft signs map
  // to "" (omitted), which behaves as a drop.
  keys.push(0x0401); vals.push("Yo");
  keys.push(0x0402); vals.push("Dj");
  keys.push(0x0403); vals.push("Gj");
  keys.push(0x0404); vals.push("Ye");
  keys.push(0x0406); vals.push("I");
  keys.push(0x0407); vals.push("Yi");
  keys.push(0x0408); vals.push("J");
  keys.push(0x0409); vals.push("Lj");
  keys.push(0x040A); vals.push("Nj");
  keys.push(0x040B); vals.push("C");
  keys.push(0x040C); vals.push("Kj");
  keys.push(0x040E); vals.push("U");
  keys.push(0x040F); vals.push("Dz");
  keys.push(0x0410); vals.push("A");
  keys.push(0x0411); vals.push("B");
  keys.push(0x0412); vals.push("V");
  keys.push(0x0413); vals.push("G");
  keys.push(0x0414); vals.push("D");
  keys.push(0x0415); vals.push("E");
  keys.push(0x0416); vals.push("Zh");
  keys.push(0x0417); vals.push("Z");
  keys.push(0x0418); vals.push("I");
  keys.push(0x0419); vals.push("Y");
  keys.push(0x041A); vals.push("K");
  keys.push(0x041B); vals.push("L");
  keys.push(0x041C); vals.push("M");
  keys.push(0x041D); vals.push("N");
  keys.push(0x041E); vals.push("O");
  keys.push(0x041F); vals.push("P");
  keys.push(0x0420); vals.push("R");
  keys.push(0x0421); vals.push("S");
  keys.push(0x0422); vals.push("T");
  keys.push(0x0423); vals.push("U");
  keys.push(0x0424); vals.push("F");
  keys.push(0x0425); vals.push("Kh");
  keys.push(0x0426); vals.push("Ts");
  keys.push(0x0427); vals.push("Ch");
  keys.push(0x0428); vals.push("Sh");
  keys.push(0x0429); vals.push("Shch");
  keys.push(0x042A); vals.push("");
  keys.push(0x042B); vals.push("Y");
  keys.push(0x042C); vals.push("");
  keys.push(0x042D); vals.push("E");
  keys.push(0x042E); vals.push("Yu");
  keys.push(0x042F); vals.push("Ya");
  keys.push(0x0430); vals.push("a");
  keys.push(0x0431); vals.push("b");
  keys.push(0x0432); vals.push("v");
  keys.push(0x0433); vals.push("g");
  keys.push(0x0434); vals.push("d");
  keys.push(0x0435); vals.push("e");
  keys.push(0x0436); vals.push("zh");
  keys.push(0x0437); vals.push("z");
  keys.push(0x0438); vals.push("i");
  keys.push(0x0439); vals.push("y");
  keys.push(0x043A); vals.push("k");
  keys.push(0x043B); vals.push("l");
  keys.push(0x043C); vals.push("m");
  keys.push(0x043D); vals.push("n");
  keys.push(0x043E); vals.push("o");
  keys.push(0x043F); vals.push("p");
  keys.push(0x0440); vals.push("r");
  keys.push(0x0441); vals.push("s");
  keys.push(0x0442); vals.push("t");
  keys.push(0x0443); vals.push("u");
  keys.push(0x0444); vals.push("f");
  keys.push(0x0445); vals.push("kh");
  keys.push(0x0446); vals.push("ts");
  keys.push(0x0447); vals.push("ch");
  keys.push(0x0448); vals.push("sh");
  keys.push(0x0449); vals.push("shch");
  keys.push(0x044A); vals.push("");
  keys.push(0x044B); vals.push("y");
  keys.push(0x044C); vals.push("");
  keys.push(0x044D); vals.push("e");
  keys.push(0x044E); vals.push("yu");
  keys.push(0x044F); vals.push("ya");
  keys.push(0x0451); vals.push("yo");
  keys.push(0x0452); vals.push("dj");
  keys.push(0x0453); vals.push("gj");
  keys.push(0x0454); vals.push("ye");
  keys.push(0x0456); vals.push("i");
  keys.push(0x0457); vals.push("yi");
  keys.push(0x0458); vals.push("j");
  keys.push(0x0459); vals.push("lj");
  keys.push(0x045A); vals.push("nj");
  keys.push(0x045B); vals.push("c");
  keys.push(0x045C); vals.push("kj");
  keys.push(0x045E); vals.push("u");
  keys.push(0x045F); vals.push("dz");
  keys.push(0x0490); vals.push("G");
  keys.push(0x0491); vals.push("g");
  // Punctuation and NBSP.
  keys.push(_TL_NBSP); vals.push(" ");
  keys.push(_TL_EN_DASH); vals.push("-");
  keys.push(_TL_EM_DASH); vals.push("-");
  keys.push(_TL_LQUOTE); vals.push("'");
  keys.push(_TL_RQUOTE); vals.push("'");
  keys.push(_TL_LDQUOTE); vals.push("\"");
  keys.push(_TL_RDQUOTE); vals.push("\"");
  keys.push(_TL_ELLIPSIS); vals.push("...");
}

// Linear scan: the replacement for `cp`, or "" when `cp` has no entry.
// The value is copied into a typed local (`let v: Str = vals[i];`) before it
// is returned; it is never compared with `==` (BUG 17).
fn _tl_lookup(keys: &Vec[Int], vals: &Vec[Str], cp: Int) -> Str {
  let n = keys.len();
  var i = 0;
  while i < n {
    let k: Int = keys[i];
    if k == cp {
      let v: Str = vals[i];
      return v;
    }
    i = i + 1;
  }
  return "";
}

// True for [0-9a-z] (the slug input is already lowercased).
fn _tl_is_slug_alnum(b: Int) -> Bool {
  if b >= 48 && b <= 57 {
    return true;
  }
  return b >= 97 && b <= 122;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// True when every byte of `s` is an ASCII byte (< 0x80).
/// Params: s - the text to inspect.
/// Returns: true when no byte of s is >= 0x80; the empty string is ASCII.
/// Invalid UTF-8 input is not ASCII unless all of its bytes are < 0x80.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn translit_is_ascii(s: Str) -> Bool {
  let n = s.len();
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b >= 128 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Transliterate `s` to ASCII.
/// Params: s - the text to transliterate (UTF-8).
/// Returns: s with every valid UTF-8 codepoint mapped through the table
/// (Latin diacritics -> base letters, Greek/Cyrillic -> Latin, selected
/// punctuation and NBSP -> ASCII); ASCII bytes pass through unchanged; a
/// codepoint with no table entry is dropped; bytes that do not form a valid
/// UTF-8 sequence pass through one byte at a time, byte-exact.
/// Error case: none; unmapped codepoints and invalid bytes are silently
/// dropped or preserved, never reported.
/// Complexity: O(s.len() * table) -- the table is built once per call and
/// scanned linearly per non-ASCII codepoint.
pub fn translit_to_ascii(s: Str) -> Str {
  var keys = Vec[Int].new();
  var vals = Vec[Str].new();
  _tl_fill(&mut keys, &mut vals);
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b0: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b0 < 0x80 {
      out.push(b0 as UInt8);
      i = i + 1;
    } else {
      let clen: Int = _tl_seq_len(b0);
      let cp: Int = _tl_decode(s, i);
      if cp < 0 {
        out.push(b0 as UInt8);
        i = i + 1;
      } else {
        let repl: Str = _tl_lookup(&keys, &vals, cp);
        if repl.len() > 0 {
          builder.sb_push_str(&mut out, repl);
        }
        i = i + clen;
      }
    }
  }
  return builder.sb_to_str(&out);
}

/// Convert `s` to a lowercase ASCII slug.
/// Params: s - the text to slugify.
/// Returns: translit_to_ascii(s), lowercased, with every run of
/// non-alphanumeric bytes replaced by a single '-' and leading/trailing '-'
/// trimmed; "" when no alphanumeric survives.
/// Error case: none.
/// Complexity: O(s.len() * table) (delegates to translit_to_ascii).
pub fn translit_slug(s: Str) -> Str {
  let ascii: Str = translit_to_ascii(s);
  let lower: Str = string.str_lower(ascii);
  var out = Vec[UInt8].new();
  let n = lower.len();
  var pending_dash = false;
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(lower, i) as Int) & 0xFF;
    if _tl_is_slug_alnum(b) {
      if pending_dash && out.len() > 0 {
        out.push(_TL_DASH as UInt8);
      }
      pending_dash = false;
      out.push(b as UInt8);
    } else {
      pending_dash = true;
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}
