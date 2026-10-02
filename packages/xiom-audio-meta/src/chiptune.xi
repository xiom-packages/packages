// XIOM -- xiom.audio_meta.chiptune: chiptune magic registry and detection
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: a deterministic, documented subset of the chiptune/tracker format
// registry: 40 entries, each a magic byte sequence at a fixed offset plus
// display metadata (id, extension, description). `chiptune_detect` scans
// the table in index order and returns the first match, so results are
// fully deterministic even when two magics could overlap. No file is ever
// rewritten or rendered.
//
// Table construction is an explicit index-dispatched builder rather than a
// module-level table: `Vec[Str]`/`Vec[StructType]` globals are off-limits
// (porter trap A) and indexed fn-pointer dispatch miscompiles (trap 5), so
// `_ch_entry_lo`/`_ch_entry_hi` return fresh structs and every caller uses
// the same source of truth. Byte pushes are explicit (`m.push(26 as UInt8)`)
// for control and high bytes, avoiding literal escape truncation (trap 15)
// and multi-byte UTF-8 encodings for values >= 0x80.
//
// See SPEC.md for the registry table and the detection semantics.

module xiom.audio_meta.chiptune

use xiom.string.builder;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// One registry entry.
///
/// `magic` is the byte sequence that must appear at `magic_offset`; an
/// entry counts as a match when the buffer holds `magic_offset + magic.len()`
/// bytes and every magic byte agrees. Out-of-range queries return an empty
/// entry: id/extension/description "", `magic_offset` 0 and an empty magic,
/// which never matches.
pub type ChiptuneEntry = {
  id: Str;
  extension: Str;
  description: Str;
  magic_offset: Int;
  magic: Vec[UInt8];
}

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _ch_byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// The empty sentinel entry (see ChiptuneEntry).
fn _ch_empty_entry() -> ChiptuneEntry {
  return ChiptuneEntry{
    id: "";
    extension: "";
    description: "";
    magic_offset: 0;
    magic: Vec[UInt8].new();
  };
}

// Registry entries 0..19.
fn _ch_entry_lo(i: Int) -> ChiptuneEntry {
  if i == 0 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "NESM");
    m.push(26 as UInt8);
    return ChiptuneEntry{ id: "nsf"; extension: "nsf"; description: "NES Sound Format"; magic_offset: 0; magic: m; };
  }
  if i == 1 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "M.K.");
    return ChiptuneEntry{ id: "mod"; extension: "mod"; description: "ProTracker 31-instrument module"; magic_offset: 1080; magic: m; };
  }
  if i == 2 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "Extended Module: ");
    return ChiptuneEntry{ id: "xm"; extension: "xm"; description: "FastTracker II module"; magic_offset: 0; magic: m; };
  }
  if i == 3 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "SCRM");
    return ChiptuneEntry{ id: "s3m"; extension: "s3m"; description: "Scream Tracker 3 module"; magic_offset: 44; magic: m; };
  }
  if i == 4 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "IMPM");
    return ChiptuneEntry{ id: "it"; extension: "it"; description: "Impulse Tracker module"; magic_offset: 0; magic: m; };
  }
  if i == 5 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "MThd");
    return ChiptuneEntry{ id: "mid"; extension: "mid"; description: "Standard MIDI File"; magic_offset: 0; magic: m; };
  }
  if i == 6 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "RMID");
    return ChiptuneEntry{ id: "rmi"; extension: "rmi"; description: "RIFF MIDI file"; magic_offset: 8; magic: m; };
  }
  if i == 7 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "MUS");
    m.push(26 as UInt8);
    return ChiptuneEntry{ id: "mus"; extension: "mus"; description: "Doom MUS sequence"; magic_offset: 0; magic: m; };
  }
  if i == 8 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "CTMF");
    return ChiptuneEntry{ id: "cmf"; extension: "cmf"; description: "Creative Music Format"; magic_offset: 0; magic: m; };
  }
  if i == 9 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "XDIR");
    return ChiptuneEntry{ id: "xmi"; extension: "xmi"; description: "Extended MIDI (FORM/XDIR)"; magic_offset: 8; magic: m; };
  }
  if i == 10 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "HMIMIDIP");
    return ChiptuneEntry{ id: "hmp"; extension: "hmp"; description: "HMI MIDI file"; magic_offset: 0; magic: m; };
  }
  if i == 11 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "PSID");
    return ChiptuneEntry{ id: "sid"; extension: "sid"; description: "PlaySID SID tune"; magic_offset: 0; magic: m; };
  }
  if i == 12 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "RSID");
    return ChiptuneEntry{ id: "rsid"; extension: "sid"; description: "Real SID tune"; magic_offset: 0; magic: m; };
  }
  if i == 13 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "GBS");
    return ChiptuneEntry{ id: "gbs"; extension: "gbs"; description: "Game Boy sound"; magic_offset: 0; magic: m; };
  }
  if i == 14 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "SNES-SPC700 Sound File Data");
    return ChiptuneEntry{ id: "spc"; extension: "spc"; description: "SNES SPC700 dump"; magic_offset: 0; magic: m; };
  }
  if i == 15 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "GYMX");
    return ChiptuneEntry{ id: "gym"; extension: "gym"; description: "Genesis GYM log"; magic_offset: 0; magic: m; };
  }
  if i == 16 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "Vgm ");
    return ChiptuneEntry{ id: "vgm"; extension: "vgm"; description: "Video Game Music log"; magic_offset: 0; magic: m; };
  }
  if i == 17 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "HESM");
    return ChiptuneEntry{ id: "hes"; extension: "hes"; description: "PC Engine HES"; magic_offset: 0; magic: m; };
  }
  if i == 18 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "KSS");
    return ChiptuneEntry{ id: "kss"; extension: "kss"; description: "MSX KSS"; magic_offset: 0; magic: m; };
  }
  if i == 19 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "SAP");
    return ChiptuneEntry{ id: "sap"; extension: "sap"; description: "Atari SAP"; magic_offset: 0; magic: m; };
  }
  return _ch_empty_entry();
}

// Registry entries 20..39.
fn _ch_entry_hi(i: Int) -> ChiptuneEntry {
  if i == 0 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "ZXAYEMUL");
    return ChiptuneEntry{ id: "ay"; extension: "ay"; description: "ZX Spectrum AY"; magic_offset: 0; magic: m; };
  }
  if i == 1 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "!Scream!");
    return ChiptuneEntry{ id: "stm"; extension: "stm"; description: "Scream Tracker 2 module"; magic_offset: 20; magic: m; };
  }
  if i == 2 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "MTM");
    return ChiptuneEntry{ id: "mtm"; extension: "mtm"; description: "MultiTracker module"; magic_offset: 0; magic: m; };
  }
  if i == 3 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "FAR");
    m.push(254 as UInt8);
    return ChiptuneEntry{ id: "far"; extension: "far"; description: "Farandole Composer module"; magic_offset: 0; magic: m; };
  }
  if i == 4 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "MAS_UTrack_V00");
    return ChiptuneEntry{ id: "ult"; extension: "ult"; description: "UltraTracker module"; magic_offset: 0; magic: m; };
  }
  if i == 5 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "if");
    return ChiptuneEntry{ id: "669"; extension: "669"; description: "Composer 669 module"; magic_offset: 0; magic: m; };
  }
  if i == 6 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "DBM0");
    return ChiptuneEntry{ id: "dbm"; extension: "dbm"; description: "DigiBooster Pro module"; magic_offset: 0; magic: m; };
  }
  if i == 7 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "MT20");
    return ChiptuneEntry{ id: "mt2"; extension: "mt2"; description: "MadTracker 2 module"; magic_offset: 0; magic: m; };
  }
  if i == 8 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "RAD by REALiTY!!");
    return ChiptuneEntry{ id: "rad"; extension: "rad"; description: "Reality AdLib Tracker module"; magic_offset: 0; magic: m; };
  }
  if i == 9 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "HVL");
    return ChiptuneEntry{ id: "hvl"; extension: "hvl"; description: "Hively Tracker module"; magic_offset: 0; magic: m; };
  }
  if i == 10 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "THX");
    return ChiptuneEntry{ id: "ahx"; extension: "ahx"; description: "Abyss Highest eXperience tune"; magic_offset: 0; magic: m; };
  }
  if i == 11 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "MPTM");
    return ChiptuneEntry{ id: "mptm"; extension: "mptm"; description: "OpenMPT module"; magic_offset: 0; magic: m; };
  }
  if i == 12 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "OKTA");
    return ChiptuneEntry{ id: "okta"; extension: "okt"; description: "Oktalyzer module"; magic_offset: 1080; magic: m; };
  }
  if i == 13 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "FLT4");
    return ChiptuneEntry{ id: "flt4"; extension: "mod"; description: "StarTrekker 4-channel module"; magic_offset: 1080; magic: m; };
  }
  if i == 14 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "4CHN");
    return ChiptuneEntry{ id: "4chn"; extension: "mod"; description: "4-channel MOD"; magic_offset: 1080; magic: m; };
  }
  if i == 15 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "6CHN");
    return ChiptuneEntry{ id: "6chn"; extension: "mod"; description: "6-channel MOD"; magic_offset: 1080; magic: m; };
  }
  if i == 16 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "8CHN");
    return ChiptuneEntry{ id: "8chn"; extension: "mod"; description: "8-channel MOD"; magic_offset: 1080; magic: m; };
  }
  if i == 17 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "16CN");
    return ChiptuneEntry{ id: "16cn"; extension: "mod"; description: "16-channel MOD"; magic_offset: 1080; magic: m; };
  }
  if i == 18 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "32CN");
    return ChiptuneEntry{ id: "32cn"; extension: "mod"; description: "32-channel MOD"; magic_offset: 1080; magic: m; };
  }
  if i == 19 {
    var m = Vec[UInt8].new();
    builder.sb_push_str(&mut m, "SC68");
    return ChiptuneEntry{ id: "sc68"; extension: "sc68"; description: "Atari SC68 tune"; magic_offset: 0; magic: m; };
  }
  return _ch_empty_entry();
}

// Fresh registry entry `i` in 0..39; out-of-range yields the empty sentinel.
fn _ch_build_entry(i: Int) -> ChiptuneEntry {
  if i < 0 {
    return _ch_empty_entry();
  }
  if i < 20 {
    return _ch_entry_lo(i);
  }
  if i < 40 {
    return _ch_entry_hi(i - 20);
  }
  return _ch_empty_entry();
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Number of registry entries (40). Complexity: O(1).
pub fn chiptune_count() -> Int {
  return 40;
}

/// Registry entry `i`; the empty sentinel entry when `i` is out of range
/// (`i < 0` or `i >= chiptune_count()`). Complexity: O(1).
pub fn chiptune_entry(i: Int) -> ChiptuneEntry {
  return _ch_build_entry(i);
}

/// Index of the first registry entry whose magic appears at its declared
/// offset in `data`, or -1 when none does. Entries are tried in index order,
/// so the result is deterministic. Complexity: O(count * max magic length).
pub fn chiptune_detect(data: &Vec[UInt8]) -> Int {
  let n = data.len();
  var i = 0;
  while i < chiptune_count() {
    let e = _ch_build_entry(i);
    let off = e.magic_offset;
    let m = e.magic.len();
    if m > 0 && off >= 0 && off + m <= n {
      var hit = true;
      var k = 0;
      while k < m {
        if _ch_byte(data, off + k) != ((e.magic[k] as Int) & 0xFF) {
          hit = false;
        }
        k = k + 1;
      }
      if hit {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Id of the first matching registry entry, or "" when nothing matches.
/// Complexity: O(count * max magic length).
pub fn chiptune_detect_id(data: &Vec[UInt8]) -> Str {
  let idx = chiptune_detect(data);
  if idx < 0 {
    return "";
  }
  let e = _ch_build_entry(idx);
  return e.id;
}
