// XIOM -- xiom.midi: Standard MIDI File structure reader
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.midi placeholder.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: structure and event walking only. The module reads the 14-byte
// "MThd" header (format, track count, division), walks the "MTrk" track
// chunks that follow it, decodes MIDI variable-length quantities (VLQ) and
// counts events in a track, including channel messages with running status,
// meta events and sysex events. It does not play anything: no timing
// resolution, no tempo maps, no note pairing, no file I/O. See SPEC.md for
// the byte-level layout tables, the VLQ rules, the event length table, the
// error catalog and the documented limitations.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every raw byte widens through `(x as Int) & 0xFF`; a bare `as Int` on
//     a UInt8 carrying bit patterns above bit 30 miscompiles (see the wasm,
//     msgpack and packet precedents).
//   * all multi-byte integers are big-endian and are read with arithmetic
//     (multiplication/addition), never byte-order tricks.
//   * _walk_events returns Result[(Int, Int), Str] but never constructs
//     Ok/Err itself; it delegates to the _ok_pair/_err_pair leaf helpers.
//   * Vec reads are bound to typed locals (let off: Int = tracks.offsets[i])
//     before any comparison or arithmetic.

module xiom.midi

/// Parsed track-chunk table: parallel vectors in file order, one entry per
/// "MTrk" chunk. `offsets[i]` is the absolute file offset of the first
/// payload byte (the byte after the 8-byte chunk header); `lengths[i]` is
/// the declared payload length in bytes. Fields are implementation details;
/// callers must go through the free functions below.
pub type MidiTracks = {
  offsets: Vec[Int];
  lengths: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok((v0, v1)) for Result[(Int, Int), Str].
fn _ok_pair(v0: Int, v1: Int) -> Result[(Int, Int), Str] {
  return Ok((v0, v1));
}

// Err(m) for Result[(Int, Int), Str].
fn _err_pair(m: Str) -> Result[(Int, Int), Str] {
  return Err(m);
}

// Ok(t) for Result[MidiTracks, Str].
fn _ok_tracks(t: MidiTracks) -> Result[MidiTracks, Str] {
  return Ok(t);
}

// Err(m) for Result[MidiTracks, Str].
fn _err_tracks(m: Str) -> Result[MidiTracks, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to 0..255. The caller must guarantee
// 0 <= pos < data.len().
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned big-endian u16 at `pos`; the caller guarantees the bounds.
fn _be_u16(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 256 + _byte(data, pos + 1);
}

// Unsigned big-endian u32 at `pos`; the caller guarantees the bounds.
fn _be_u32(data: &Vec[UInt8], pos: Int) -> Int {
  var v: Int = 0;
  var i = 0;
  while i < 4 {
    v = v * 256 + _byte(data, pos + i);
    i = i + 1;
  }
  return v;
}

// True when the four bytes at `pos` equal the ASCII codes a, b, c, d.
// The caller guarantees the bounds.
fn _tag_is(data: &Vec[UInt8], pos: Int, a: Int, b: Int, c: Int, d: Int) -> Bool {
  if _byte(data, pos) != a { return false; }
  if _byte(data, pos + 1) != b { return false; }
  if _byte(data, pos + 2) != c { return false; }
  if _byte(data, pos + 3) != d { return false; }
  return true;
}

// Header classification. 0 = complete, well-formed 14-byte "MThd" header;
// 1 = shorter than 14 bytes; 2 = bad magic; 3 = "MThd" length field != 6.
fn _header_kind(data: &Vec[UInt8]) -> Int {
  if data.len() < 14 {
    return 1;
  }
  if !_tag_is(data, 0, 77, 84, 104, 100) {
    return 2;
  }
  if _be_u32(data, 4) != 6 {
    return 3;
  }
  return 0;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// True when `data` starts with the 4-byte MIDI file magic "MThd"
/// (77 84 104 100). Only the tag is checked: a bare 4-byte prefix returns
/// true, trailing bytes are not inspected and the rest of the header is not
/// validated. False for fewer than 4 bytes.
pub fn midi_is_file(data: &Vec[UInt8]) -> Bool {
  if data.len() < 4 {
    return false;
  }
  return _tag_is(data, 0, 77, 84, 104, 100);
}

/// Format field of the "MThd" header: 0 (single track), 1 (one or more
/// simultaneous tracks) or 2 (one or more independent sequences).
/// Err("midi: truncated header") for fewer than 14 bytes,
/// Err("midi: bad MThd magic") for a wrong tag,
/// Err("midi: bad header length") when the declared chunk length is not 6,
/// Err("midi: invalid format") when the stored value is above 2.
pub fn midi_format(data: &Vec[UInt8]) -> Result[Int, Str] {
  let k = _header_kind(data);
  if k == 1 {
    return _err_int("midi: truncated header");
  }
  if k == 2 {
    return _err_int("midi: bad MThd magic");
  }
  if k == 3 {
    return _err_int("midi: bad header length");
  }
  let f = _be_u16(data, 8);
  if f > 2 {
    return _err_int("midi: invalid format");
  }
  return _ok_int(f);
}

/// Track count field of the "MThd" header (0..65535). This is the value
/// declared by the header; `midi_track_chunks` additionally walks the file
/// and reports Err("midi: track count mismatch") when the number of "MTrk"
/// chunks differs. Header errors are the same catalog as `midi_format`.
pub fn midi_track_count(data: &Vec[UInt8]) -> Result[Int, Str] {
  let k = _header_kind(data);
  if k == 1 {
    return _err_int("midi: truncated header");
  }
  if k == 2 {
    return _err_int("midi: bad MThd magic");
  }
  if k == 3 {
    return _err_int("midi: bad header length");
  }
  return _ok_int(_be_u16(data, 10));
}

/// Division field of the "MThd" header, returned signed (the field is a
/// signed 16-bit big-endian value):
///   * 1..32767 -- positive: ticks per quarter note (metrical time);
///   * negative (high bit set, e.g. 0xE728 -> -6360) -- SMPTE time: the
///     high byte is a negative frames-per-second code (-24, -25, -29 or
///     -30) and the low byte is ticks per frame.
/// Header errors are the same catalog as `midi_format`.
pub fn midi_division(data: &Vec[UInt8]) -> Result[Int, Str] {
  let k = _header_kind(data);
  if k == 1 {
    return _err_int("midi: truncated header");
  }
  if k == 2 {
    return _err_int("midi: bad MThd magic");
  }
  if k == 3 {
    return _err_int("midi: bad header length");
  }
  let raw = _be_u16(data, 12);
  if raw >= 32768 {
    return _ok_int(raw - 65536);
  }
  return _ok_int(raw);
}

/// Decode one MIDI variable-length quantity at `off`: at most 4 bytes,
/// most-significant 7-bit group first, bit 7 of each byte is the
/// continuation flag, so the value range is 0..0x0FFFFFFF (268435455).
/// Ok((value, next_offset)) on success; `next_offset` points just past the
/// last consumed byte and is <= data.len().
/// Err("midi: negative offset") for `off < 0`;
/// Err("midi: truncated varlen") when the encoding starts at `off` but runs
/// past the end of `data`; Err("midi: overlong varlen") when four bytes all
/// carry the continuation flag. Non-minimal encodings (leading 0x80 groups)
/// are accepted, matching the usual MIDI readers.
pub fn midi_varlen(data: &Vec[UInt8], off: Int) -> Result[(Int, Int), Str] {
  if off < 0 {
    return _err_pair("midi: negative offset");
  }
  var result: Int = 0;
  var pos = off;
  var i = 0;
  while i < 4 {
    if pos >= data.len() {
      return _err_pair("midi: truncated varlen");
    }
    let b = _byte(data, pos);
    result = result * 128 + (b & 0x7F);
    pos = pos + 1;
    if b < 128 {
      return _ok_pair(result, pos);
    }
    i = i + 1;
  }
  return _err_pair("midi: overlong varlen");
}

/// Walk every "MTrk" chunk after the 14-byte header. Each chunk is
/// `"MTrk" + u32 big-endian length + payload`; the payload must fit inside
/// `data`. Returns the parallel offset/length vectors in file order (see
/// MidiTracks). The number of chunks must equal the header track count.
///
/// Errors: the header catalog from `midi_format`;
/// Err("midi: truncated track chunk") when fewer than 8 bytes remain where
/// a chunk header is expected; Err("midi: bad track magic") for a tag other
/// than "MTrk"; Err("midi: track chunk out of range") when the declared
/// length extends past the end of `data`;
/// Err("midi: track count mismatch") when the walked count differs from the
/// header field. Zero-length chunks and zero declared tracks are valid.
pub fn midi_track_chunks(data: &Vec<UInt8>) -> Result[MidiTracks, Str] {
  let k = _header_kind(data);
  if k == 1 {
    return _err_tracks("midi: truncated header");
  }
  if k == 2 {
    return _err_tracks("midi: bad MThd magic");
  }
  if k == 3 {
    return _err_tracks("midi: bad header length");
  }
  let declared = _be_u16(data, 10);
  var offsets = Vec[Int].new();
  var lengths = Vec[Int].new();
  let total = data.len();
  var pos = 14;
  while pos < total {
    if total - pos < 8 {
      return _err_tracks("midi: truncated track chunk");
    }
    if !_tag_is(data, pos, 77, 84, 114, 107) {
      return _err_tracks("midi: bad track magic");
    }
    let len = _be_u32(data, pos + 4);
    if len > total - (pos + 8) {
      return _err_tracks("midi: track chunk out of range");
    }
    offsets.push(pos + 8);
    lengths.push(len);
    pos = pos + 8 + len;
  }
  if offsets.len() != declared {
    return _err_tracks("midi: track count mismatch");
  }
  return _ok_tracks(MidiTracks{ offsets: offsets; lengths: lengths; });
}

// Walk the events of one track and tally either the event count (mode 0:
// returns (count, 0)) or the note events (mode 1: returns (note_on,
// note_off)). The track table and the index are validated first; the walk
// is bounded by the declared chunk length, so any event that would read
// past the track end is Err("midi: truncated event").
fn _walk_events(data: &Vec[UInt8], track_index: Int, mode: Int) -> Result[(Int, Int), Str] {
  let tr = midi_track_chunks(data);
  if !tr.is_ok {
    return _err_pair(tr.error);
  }
  let tracks = tr.value;
  if track_index < 0 || track_index >= tracks.lengths.len() {
    return _err_pair("midi: track index out of range");
  }
  let start: Int = tracks.offsets[track_index];
  let len: Int = tracks.lengths[track_index];
  let end = start + len;
  var pos = start;
  var count = 0;
  var on = 0;
  var off = 0;
  var running: Int = -1;
  var stopped = false;
  while pos < end && !stopped {
    // Delta time: a VLQ read that crosses the track end is truncated.
    let dr = midi_varlen(data, pos);
    if !dr.is_ok {
      return _err_pair("midi: truncated event");
    }
    let dnext: Int = dr.value.1;
    if dnext > end {
      return _err_pair("midi: truncated event");
    }
    pos = dnext;
    if pos >= end {
      return _err_pair("midi: truncated event");
    }
    // Status byte; running status: a data byte (< 0x80) reuses the last
    // channel status. Sysex and meta events clear running status.
    let b = _byte(data, pos);
    var status = 0;
    if b >= 128 {
      status = b;
      pos = pos + 1;
    } else {
      if running < 0 {
        return _err_pair("midi: missing running status");
      }
      status = running;
    }
    if status >= 128 && status <= 239 {
      // Channel message: 8n/9n/An/Bn/En carry 2 data bytes, Cn/Dn carry 1.
      let kind = status & 0xF0;
      var need = 2;
      if kind == 192 || kind == 208 {
        need = 1;
      }
      if pos + need > end {
        return _err_pair("midi: truncated event");
      }
      if status == 144 || status == 128 {
        // 9n with velocity > 0 is a note-on; 9n with velocity 0 and 8n are
        // note-offs.
        let d2 = _byte(data, pos + 1);
        if status == 144 && d2 > 0 {
          on = on + 1;
        } else {
          off = off + 1;
        }
      }
      pos = pos + need;
      running = status;
      count = count + 1;
    } elif status == 240 || status == 247 {
      // Sysex: F0/F7 + VLQ length + payload.
      let lr = midi_varlen(data, pos);
      if !lr.is_ok {
        return _err_pair("midi: truncated event");
      }
      let lnext: Int = lr.value.1;
      let llen: Int = lr.value.0;
      if lnext > end {
        return _err_pair("midi: truncated event");
      }
      if lnext + llen > end {
        return _err_pair("midi: truncated event");
      }
      pos = lnext + llen;
      running = -1;
      count = count + 1;
    } elif status == 255 {
      // Meta event: FF + type byte + VLQ length + payload.
      if pos >= end {
        return _err_pair("midi: truncated event");
      }
      let mtype = _byte(data, pos);
      pos = pos + 1;
      let mr = midi_varlen(data, pos);
      if !mr.is_ok {
        return _err_pair("midi: truncated event");
      }
      let mnext: Int = mr.value.1;
      let mlen: Int = mr.value.0;
      if mnext > end {
        return _err_pair("midi: truncated event");
      }
      if mnext + mlen > end {
        return _err_pair("midi: truncated event");
      }
      if mtype == 47 && mlen != 0 {
        return _err_pair("midi: bad end of track");
      }
      pos = mnext + mlen;
      running = -1;
      count = count + 1;
      if mtype == 47 {
        // End of Track (FF 2F 00): counted, then the walk stops; bytes
        // after it inside the chunk are not inspected.
        stopped = true;
      }
    } else {
      return _err_pair("midi: bad status byte");
    }
  }
  if mode == 0 {
    return _ok_pair(count, 0);
  }
  return _ok_pair(on, off);
}

/// Number of events in track `track_index` (0-based, file order). The event
/// stream is decoded exactly as described for `midi_note_events`, including
/// running status; the End of Track meta event (FF 2F 00) is parsed,
/// counted, and then stops the walk, so trailing bytes inside the chunk are
/// not counted. A track with no End of Track is counted up to its declared
/// end. Errors: the header/chunk catalog, including
/// Err("midi: track index out of range") for an index outside
/// 0..track_count-1, and Err("midi: truncated event") for any event read
/// that would cross the track end.
pub fn midi_track_event_count(data: &Vec[UInt8], track_index: Int) -> Result[Int, Str] {
  let r = _walk_events(data, track_index, 0);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let ev: Int = r.value.0;
  return _ok_int(ev);
}

/// Note-event counts of track `track_index`: Ok((note_on_count,
/// note_off_count)). Note-off messages (8n) and note-on messages (9n) with
/// velocity 0 both count as note-offs; note-on messages with velocity 1..127
/// count as note-ons. Parsing stops at the End of Track meta event
/// (FF 2F 00), exactly like `midi_track_event_count`, so bytes after it are
/// not counted. Errors: the header/chunk catalog plus
/// Err("midi: track index out of range") and
/// Err("midi: truncated event").
pub fn midi_note_events(data: &Vec[UInt8], track_index: Int) -> Result[(Int, Int), Str] {
  return _walk_events(data, track_index, 1);
}
