// XIOM -- xiom.audio_meta: MIDI SMF and ProTracker MOD metadata parsers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: structural metadata only. No audio is rendered, no samples are
// decoded and no pattern data is transformed. The sibling modules
// xiom.audio_meta.trackers (XM/S3M/IT/NSF) and xiom.audio_meta.chiptune
// (magic registry) complete the package.
//
// v0.62.2 porter discipline shaping this module:
//   * Ok/Err construction is confined to the leaf helpers below (trap 6).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF` (trap 3).
//   * Strs built from file bytes only cover validatable byte ranges: the
//     `_am_printable_prefix` helper stops at NUL (which cannot live in a Str)
//     and at any non-printable byte, so no NUL ever reaches sb_to_str (15).
//   * parallel Vecs are push-mirrored and every accessor guards lengths; the
//     MOD order vector and the MIDI counters are never indexed unguarded.
//   * varlen reads are bounded to 4 bytes and every event walk checks its
//     track end before each read (D).
//   * `Vec[Str]` and `Vec[StructType]` never appear; MidiInfo/ModInfo carry
//     scalars plus one Vec[Int] (the MOD order list).
// See SPEC.md for byte layouts, the accepted MOD signature subset and the
// error catalog.

module xiom.audio_meta

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Parsed Standard MIDI File header plus aggregate track metadata.
///
/// `format` is 0, 1 or 2; `ntrks` is the declared track count and every
/// declared track chunk must be present. `division` is the raw 16-bit field:
/// when `smpte` is false, `ppq` = division (ticks per quarter note) and the
/// SMPTE fields are 0; when `smpte` is true the high byte is a negative
/// frames-per-second value (`smpte_fps`, e.g. 0xE8 -> -24) and `smpte_tpf`
/// is ticks per frame, while `ppq` is 0.
///
/// Track aggregates span all tracks: `total_events`, `channel_events`,
/// `meta_events`, `sysex_events`, `note_ons` (note-on with velocity > 0),
/// `end_of_tracks` (FF 2F meta events) and `ticks` (sum of all delta times).
/// `first_tempo_us` is the first FF 51 (3-byte) tempo in microseconds per
/// quarter note, or 0 when absent; `track_name` is the first FF 03 meta text
/// truncated at the first NUL/non-printable byte ("" when absent).
pub type MidiInfo = {
  format: Int;
  ntrks: Int;
  division: Int;
  smpte: Bool;
  ppq: Int;
  smpte_fps: Int;
  smpte_tpf: Int;
  total_events: Int;
  channel_events: Int;
  meta_events: Int;
  sysex_events: Int;
  note_ons: Int;
  end_of_tracks: Int;
  ticks: Int;
  first_tempo_us: Int;
  track_name: Str;
}

/// Parsed ProTracker-style module header plus pattern statistics.
///
/// `title` is the 20-byte name truncated at the first NUL/non-printable byte.
/// `signature` is the 4-character tag at offset 1080 and `channels` the
/// channel count of the accepted subset (see SPEC.md). `song_length` and
/// `restart` are the two header bytes; `order` holds the `song_length`
/// entries (never more than 128) and `patterns` is `max(order) + 1`, capped
/// at 128 by the order-entry check.
///
/// Sample statistics cover the 31 sample headers: `sample_count` counts
/// samples with a nonzero length, `sample_bytes` sums `length * 2` (8-bit
/// sample data). Pattern statistics cover every cell of every counted
/// pattern: `cells` is the cell count, `notes` counts cells with a nonzero
/// period and `instruments` counts cells with a nonzero sample number.
pub type ModInfo = {
  title: Str;
  signature: Str;
  channels: Int;
  song_length: Int;
  restart: Int;
  patterns: Int;
  order: Vec[Int];
  sample_count: Int;
  sample_bytes: Int;
  cells: Int;
  notes: Int;
  instruments: Int;
}

// --------------------------------------------------
//  Internal types
// --------------------------------------------------

// One decoded MIDI variable-length quantity.
type Varlen = {
  value: Int;
  size: Int;
}

// Aggregates collected while walking one MTrk chunk.
type TrkStats = {
  events: Int;
  channel: Int;
  meta: Int;
  sysex: Int;
  notes: Int;
  eots: Int;
  ticks: Int;
  tempo: Int;
  name: Str;
}

// --------------------------------------------------
//  Result constructors (leaf helpers; see module header)
// --------------------------------------------------

fn _am_ok_midi(v: MidiInfo) -> Result[MidiInfo, Str] {
  return Ok(v);
}

fn _am_err_midi(m: Str) -> Result[MidiInfo, Str] {
  return Err(m);
}

fn _am_ok_mod(v: ModInfo) -> Result[ModInfo, Str] {
  return Ok(v);
}

fn _am_err_mod(m: Str) -> Result[ModInfo, Str] {
  return Err(m);
}

fn _am_ok_vl(v: Varlen) -> Result[Varlen, Str] {
  return Ok(v);
}

fn _am_err_vl(m: Str) -> Result[Varlen, Str] {
  return Err(m);
}

fn _am_ok_trk(v: TrkStats) -> Result[TrkStats, Str] {
  return Ok(v);
}

fn _am_err_trk(m: Str) -> Result[TrkStats, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _am_byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned big-endian u16 at `pos`; callers guarantee the bounds.
fn _am_be16(data: &Vec[UInt8], pos: Int) -> Int {
  return _am_byte(data, pos) * 256 + _am_byte(data, pos + 1);
}

// Unsigned big-endian u32 at `pos`; callers guarantee the bounds.
fn _am_be32(data: &Vec[UInt8], pos: Int) -> Int {
  var v: Int = 0;
  var i = 0;
  while i < 4 {
    v = v * 256 + _am_byte(data, pos + i);
    i = i + 1;
  }
  return v;
}

// True when the four bytes at `pos` equal the ASCII codes a, b, c, d.
fn _am_tag4(data: &Vec[UInt8], pos: Int, a: Int, b: Int, c: Int, d: Int) -> Bool {
  if _am_byte(data, pos) != a { return false; }
  if _am_byte(data, pos + 1) != b { return false; }
  if _am_byte(data, pos + 2) != c { return false; }
  if _am_byte(data, pos + 3) != d { return false; }
  return true;
}

// True when the `n` bytes at `pos` are all printable ASCII (0x20..0x7E).
fn _am_printable_range(data: &Vec[UInt8], pos: Int, n: Int) -> Bool {
  var i = 0;
  while i < n {
    let b = _am_byte(data, pos + i);
    if b < 32 { return false; }
    if b > 126 { return false; }
    i = i + 1;
  }
  return true;
}

// Build a Str from the printable ASCII prefix of the `n` bytes at `pos`:
// stops at the first NUL or non-printable byte ("" when that is the first
// byte). This is the only byte-to-Str path in this module, so a NUL can
// never reach sb_to_str and trip its length contract (trap 15).
fn _am_printable_prefix(data: &Vec[UInt8], pos: Int, n: Int) -> Str {
  var m = 0;
  var stop = false;
  while m < n && !stop {
    let b = _am_byte(data, pos + m);
    if b == 0 {
      stop = true;
    } elif b < 32 {
      stop = true;
    } elif b > 126 {
      stop = true;
    } else {
      m = m + 1;
    }
  }
  if m == 0 {
    return "";
  }
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < m {
    builder.sb_push_byte(&mut sb, _am_byte(data, pos + i) as UInt8);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Build a 4-character Str from the bytes at `pos`; "" when any byte is not
// printable ASCII.
fn _am_str4(data: &Vec[UInt8], pos: Int) -> Str {
  if !_am_printable_range(data, pos, 4) {
    return "";
  }
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < 4 {
    builder.sb_push_byte(&mut sb, _am_byte(data, pos + i) as UInt8);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  MIDI: variable-length quantities
// --------------------------------------------------

// Decode the MIDI variable-length quantity at `pos`, never reading at or
// past `end`. At most four bytes are consumed; a continued 4th byte is an
// error (SMF varlen fields are capped at 28 bits).
fn _am_varlen(data: &Vec[UInt8], pos: Int, end: Int) -> Result[Varlen, Str] {
  var v = 0;
  var i = 0;
  while i < 4 {
    if pos + i >= end {
      return _am_err_vl("midi: truncated event");
    }
    let b = _am_byte(data, pos + i);
    v = v * 128 + (b % 128);
    if b < 128 {
      return _am_ok_vl(Varlen{ value: v; size: i + 1; });
    }
    i = i + 1;
  }
  return _am_err_vl("midi: bad varlen");
}

// --------------------------------------------------
//  MIDI: one track walk
// --------------------------------------------------

// Walk the events of one MTrk payload [start, end). Running status is
// carried across events and cleared by meta and sysex events, as SMF
// requires. Every read is bounds-checked against `end`; the walk must land
// exactly on `end`.
fn _am_parse_track(data: &Vec[UInt8], start: Int, end: Int) -> Result[TrkStats, Str] {
  var p = start;
  var running = 0;
  var events = 0;
  var channel = 0;
  var meta = 0;
  var sysex = 0;
  var notes = 0;
  var eots = 0;
  var ticks = 0;
  var tempo = 0;
  var name = "";
  while p < end {
    let vr = _am_varlen(data, p, end);
    if !vr.is_ok {
      return _am_err_trk(vr.error);
    }
    let vv = vr.value;
    p = p + vv.size;
    ticks = ticks + vv.value;
    if p >= end {
      return _am_err_trk("midi: truncated event");
    }
    let b = _am_byte(data, p);
    var status = b;
    if b < 128 {
      if running == 0 {
        return _am_err_trk("midi: bad running status");
      }
      status = running;
    } else {
      p = p + 1;
      if b <= 239 {
        running = b;
      }
    }
    if status == 255 {
      // Meta event: FF type varlen(len) payload.
      if p >= end {
        return _am_err_trk("midi: truncated event");
      }
      let mt = _am_byte(data, p);
      p = p + 1;
      let lr = _am_varlen(data, p, end);
      if !lr.is_ok {
        return _am_err_trk(lr.error);
      }
      let lv = lr.value;
      p = p + lv.size;
      if lv.value > end - p {
        return _am_err_trk("midi: truncated event");
      }
      meta = meta + 1;
      if mt == 47 {
        eots = eots + 1;
      }
      if mt == 81 && lv.value == 3 {
        if tempo == 0 {
          tempo = _am_byte(data, p) * 65536 + _am_byte(data, p + 1) * 256 + _am_byte(data, p + 2);
        }
      }
      if mt == 3 {
        if name.len() == 0 {
          name = _am_printable_prefix(data, p, lv.value);
        }
      }
      p = p + lv.value;
      events = events + 1;
      running = 0;
    } elif status == 240 || status == 247 {
      // System exclusive: F0/F7 varlen(len) payload (payload not interpreted).
      let lr = _am_varlen(data, p, end);
      if !lr.is_ok {
        return _am_err_trk(lr.error);
      }
      let lv = lr.value;
      p = p + lv.size;
      if lv.value > end - p {
        return _am_err_trk("midi: truncated event");
      }
      p = p + lv.value;
      sysex = sysex + 1;
      events = events + 1;
      running = 0;
    } elif status >= 128 && status <= 239 {
      let hi = status / 16;
      var dcount = 2;
      if hi == 12 || hi == 13 {
        dcount = 1;
      }
      if end - p < dcount {
        return _am_err_trk("midi: truncated event");
      }
      channel = channel + 1;
      if hi == 9 {
        if _am_byte(data, p + 1) != 0 {
          notes = notes + 1;
        }
      }
      p = p + dcount;
      events = events + 1;
    } else {
      return _am_err_trk("midi: bad status");
    }
  }
  if p != end {
    return _am_err_trk("midi: track chunk overrun");
  }
  return _am_ok_trk(TrkStats{
    events: events;
    channel: channel;
    meta: meta;
    sysex: sysex;
    notes: notes;
    eots: eots;
    ticks: ticks;
    tempo: tempo;
    name: name;
  });
}

// --------------------------------------------------
//  Public API: MIDI
// --------------------------------------------------

/// Parse a Standard MIDI File header and validate every declared track.
///
/// Checks, in order (first failure wins): non-empty buffer; the 14-byte
/// minimum "MThd" + u32 length + 6-byte core; a header chunk length >= 6
/// that fits; format 0..2; at least one track; a nonzero division (and a
/// nonzero ticks-per-frame for SMPTE divisions); then exactly `ntrks` MTrk
/// chunks whose declared payloads fit, walked event by event to their exact
/// end (varlen deltas/lengths capped at 4 bytes, valid status bytes only,
/// running status only after a channel status, no reads past the track end).
/// The file must end exactly after the last track.
///
/// See SPEC.md for the full error catalog. Success returns the header fields
/// plus per-track aggregate counters.
/// Complexity: O(data.len()).
pub fn midi_parse(data: &Vec[UInt8]) -> Result[MidiInfo, Str] {
  let n = data.len();
  if n == 0 {
    return _am_err_midi("midi: empty input");
  }
  if n < 14 {
    return _am_err_midi("midi: truncated header");
  }
  if !_am_tag4(data, 0, 77, 84, 104, 100) {
    return _am_err_midi("midi: bad MThd magic");
  }
  let hlen = _am_be32(data, 4);
  if hlen < 6 {
    return _am_err_midi("midi: short header chunk");
  }
  if hlen > n - 8 {
    return _am_err_midi("midi: truncated header");
  }
  let format = _am_be16(data, 8);
  if format > 2 {
    return _am_err_midi("midi: bad format");
  }
  let ntrks = _am_be16(data, 10);
  if ntrks < 1 {
    return _am_err_midi("midi: zero tracks");
  }
  let division = _am_be16(data, 12);
  var smpte = false;
  var ppq = division;
  var fps = 0;
  var tpf = 0;
  if division >= 32768 {
    smpte = true;
    ppq = 0;
    fps = _am_byte(data, 12);
    if fps >= 128 {
      fps = fps - 256;
    }
    tpf = _am_byte(data, 13);
    if fps == 0 || tpf == 0 {
      return _am_err_midi("midi: bad division");
    }
  } else {
    if division == 0 {
      return _am_err_midi("midi: bad division");
    }
  }
  var pos = 8 + hlen;
  var total = 0;
  var chans = 0;
  var metas = 0;
  var syxs = 0;
  var note_ons = 0;
  var eots = 0;
  var ticks = 0;
  var tempo = 0;
  var tname = "";
  var t = 0;
  while t < ntrks {
    if n - pos < 8 {
      return _am_err_midi("midi: missing track chunk");
    }
    if !_am_tag4(data, pos, 77, 84, 114, 107) {
      return _am_err_midi("midi: missing track chunk");
    }
    let tlen = _am_be32(data, pos + 4);
    if tlen > n - pos - 8 {
      return _am_err_midi("midi: track chunk overrun");
    }
    let end = pos + 8 + tlen;
    let tr = _am_parse_track(data, pos + 8, end);
    if !tr.is_ok {
      return _am_err_midi(tr.error);
    }
    let ts = tr.value;
    total = total + ts.events;
    chans = chans + ts.channel;
    metas = metas + ts.meta;
    syxs = syxs + ts.sysex;
    note_ons = note_ons + ts.notes;
    eots = eots + ts.eots;
    ticks = ticks + ts.ticks;
    if tempo == 0 {
      tempo = ts.tempo;
    }
    if tname.len() == 0 {
      tname = ts.name;
    }
    pos = end;
    t = t + 1;
  }
  if pos != n {
    return _am_err_midi("midi: trailing data");
  }
  let info = MidiInfo{
    format: format;
    ntrks: ntrks;
    division: division;
    smpte: smpte;
    ppq: ppq;
    smpte_fps: fps;
    smpte_tpf: tpf;
    total_events: total;
    channel_events: chans;
    meta_events: metas;
    sysex_events: syxs;
    note_ons: note_ons;
    end_of_tracks: eots;
    ticks: ticks;
    first_tempo_us: tempo;
    track_name: tname;
  };
  return _am_ok_midi(info);
}

/// True when midi_parse succeeds. Complexity: O(data.len()).
pub fn midi_is_valid(data: &Vec[UInt8]) -> Bool {
  let r = midi_parse(data);
  return r.is_ok;
}

// --------------------------------------------------
//  MOD: signature subset
// --------------------------------------------------

// Channel count for the accepted signature subset, 0 when unrecognized.
// See SPEC.md for the table. Comparisons use string.str_compare (BUG 17:
// `==` on non-literal Str values is not reliable).
fn _am_mod_channels(sig: Str) -> Int {
  if string.str_compare(sig, "M.K.") == 0 { return 4; }
  if string.str_compare(sig, "M!K!") == 0 { return 4; }
  if string.str_compare(sig, "M&K!") == 0 { return 4; }
  if string.str_compare(sig, "N.T.") == 0 { return 4; }
  if string.str_compare(sig, "FLT4") == 0 { return 4; }
  if string.str_compare(sig, "4CHN") == 0 { return 4; }
  if string.str_compare(sig, "6CHN") == 0 { return 6; }
  if string.str_compare(sig, "8CHN") == 0 { return 8; }
  if string.str_compare(sig, "FLT8") == 0 { return 8; }
  if string.str_compare(sig, "CD81") == 0 { return 8; }
  if string.str_compare(sig, "OKTA") == 0 { return 8; }
  if string.str_compare(sig, "16CN") == 0 { return 16; }
  if string.str_compare(sig, "32CN") == 0 { return 32; }
  return 0;
}

// --------------------------------------------------
//  Public API: MOD
// --------------------------------------------------

/// Parse a ProTracker-style 31-instrument module header and count pattern
/// cells.
///
/// Checks, in order (first failure wins): non-empty buffer; at least the
/// 1084-byte header; a recognized 4-character signature at offset 1080
/// (see SPEC.md); a song length of 1..128; every one of the `song_length`
/// order entries at 952 <= 127. `patterns` is then `max(order) + 1` and the
/// buffer must hold `1084 + patterns * 64 * channels * 4` bytes (trailing
/// bytes beyond the pattern data are allowed). Sample and pattern statistics
/// are computed without decoding anything.
///
/// See SPEC.md for the layout table and the error catalog.
/// Complexity: O(patterns * 64 * channels).
pub fn mod_parse(data: &Vec[UInt8]) -> Result[ModInfo, Str] {
  let n = data.len();
  if n == 0 {
    return _am_err_mod("mod: empty input");
  }
  if n < 1084 {
    return _am_err_mod("mod: truncated header");
  }
  let sig = _am_str4(data, 1080);
  let channels = _am_mod_channels(sig);
  if channels == 0 {
    return _am_err_mod("mod: bad signature");
  }
  let song_len = _am_byte(data, 950);
  if song_len == 0 {
    return _am_err_mod("mod: zero song length");
  }
  if song_len > 128 {
    return _am_err_mod("mod: bad song length");
  }
  var orders = Vec[Int].new();
  var maxp = 0;
  var i = 0;
  while i < song_len {
    let o = _am_byte(data, 952 + i);
    if o > 127 {
      return _am_err_mod("mod: bad order entry");
    }
    orders.push(o);
    if o > maxp {
      maxp = o;
    }
    i = i + 1;
  }
  let patterns = maxp + 1;
  let pat_size = 64 * channels * 4;
  let need = 1084 + patterns * pat_size;
  if n < need {
    return _am_err_mod("mod: truncated pattern data");
  }
  var sample_count = 0;
  var sample_bytes = 0;
  var s = 0;
  while s < 31 {
    let base = 20 + s * 30;
    let slen = _am_be16(data, base + 22);
    if slen > 0 {
      sample_count = sample_count + 1;
      sample_bytes = sample_bytes + slen * 2;
    }
    s = s + 1;
  }
  var cells = 0;
  var notes = 0;
  var instr = 0;
  var p = 1084;
  var pi = 0;
  while pi < patterns {
    var row = 0;
    while row < 64 {
      var c = 0;
      while c < channels {
        let cell = p + (row * channels + c) * 4;
        let b0 = _am_byte(data, cell);
        let b2 = _am_byte(data, cell + 2);
        let period = (b0 % 16) * 256 + _am_byte(data, cell + 1);
        let ins = (b0 / 16) * 16 + b2 / 16;
        if period != 0 {
          notes = notes + 1;
        }
        if ins != 0 {
          instr = instr + 1;
        }
        cells = cells + 1;
        c = c + 1;
      }
      row = row + 1;
    }
    p = p + pat_size;
    pi = pi + 1;
  }
  let info = ModInfo{
    title: _am_printable_prefix(data, 0, 20);
    signature: sig;
    channels: channels;
    song_length: song_len;
    restart: _am_byte(data, 951);
    patterns: patterns;
    order: orders;
    sample_count: sample_count;
    sample_bytes: sample_bytes;
    cells: cells;
    notes: notes;
    instruments: instr;
  };
  return _am_ok_mod(info);
}

/// True when mod_parse succeeds. Complexity: O(patterns * 64 * channels).
pub fn mod_is_valid(data: &Vec[UInt8]) -> Bool {
  let r = mod_parse(data);
  return r.is_ok;
}
