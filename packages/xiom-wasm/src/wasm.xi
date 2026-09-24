// XIOM -- xiom.wasm: WebAssembly binary module structure reader
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Structure-only reader for the WebAssembly binary format: magic/version
// detection, unsigned LEB128 u32 decoding, section walking and export-name
// extraction. It validates container boundaries, not module validity: no
// type checking, no instruction decoding, no stub validation, no codegen.
// See SPEC.md for the byte-level rules, the section table, the error
// catalog and the documented limitations.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every raw byte widens through `(x as Int) & 0xFF`; a bare `as Int`
//     on a UInt8 carrying bit patterns above bit 30 miscompiles (see the
//     packet and msgpack precedents).
//   * `_parse_exports` returns Result[Vec[Str], Str] but never constructs
//     Ok/Err itself; it delegates to the _ok_names/_err_names leaf helpers.
//   * Str materialization uses xiom.string.builder.sb_to_str: one
//     allocation, bytes copied verbatim (no UTF-8 validation). Because the
//     platform Str is NUL-terminated, an embedded 0x00 byte in an export
//     name is rejected instead of silently truncating.
//   * no function mixes a `&local` call with a later `&mut local` call
//     (advisory E001); every helper here takes `&Vec[UInt8]`.

module xiom.wasm

use xiom.string.builder;

/// Parsed section table: parallel vectors in file order, one entry per
/// section. `ids[i]` is the raw section id byte (0..255, recorded
/// verbatim); `offsets[i]` is the absolute offset of the first payload byte
/// (the byte after the size LEB128); `sizes[i]` is the declared payload
/// size in bytes. Fields are implementation details; callers must go
/// through the free functions below.
pub type WasmSections = {
  ids: Vec[Int];
  offsets: Vec[Int];
  sizes: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[(Int, Int), Str].
fn _ok_pair(v: (Int, Int)) -> Result[(Int, Int), Str] {
  return Ok(v);
}

// Err(m) for Result[(Int, Int), Str].
fn _err_pair(m: Str) -> Result[(Int, Int), Str] {
  return Err(m);
}

// Ok(v) for Result[WasmSections, Str].
fn _ok_sections(v: WasmSections) -> Result[WasmSections, Str] {
  return Ok(v);
}

// Err(m) for Result[WasmSections, Str].
fn _err_sections(m: Str) -> Result[WasmSections, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Str], Str].
fn _ok_names(v: Vec[Str]) -> Result[Vec[Str], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Str], Str].
fn _err_names(m: Str) -> Result[Vec[Str], Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte `off` widened to 0..255. The caller must guarantee 0 <= off < len.
fn _byte(data: &Vec[UInt8], off: Int) -> Int {
  return (data[off] as Int) & 0xFF;
}

// Header classification: 0 = magic + version 1 ok, 1 = shorter than the
// complete 8-byte header, 2 = bad magic, 3 = bad version.
fn _header_kind(data: &Vec[UInt8]) -> Int {
  if data.len() < 4 {
    return 1;
  }
  if _byte(data, 0) != 0x00 || _byte(data, 1) != 0x61 || _byte(data, 2) != 0x73 || _byte(data, 3) != 0x6D {
    return 2;
  }
  if data.len() < 8 {
    return 1;
  }
  if _byte(data, 4) != 0x01 || _byte(data, 5) != 0x00 || _byte(data, 6) != 0x00 || _byte(data, 7) != 0x00 {
    return 3;
  }
  return 0;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// True when `data` starts with the WebAssembly magic `00 61 73 6D` and
/// version `01 00 00 00`. Trailing bytes (sections) are not inspected, so
/// any valid module and any valid prefix of one is accepted. False for
/// fewer than 8 bytes, a wrong magic, or a version other than 1.
pub fn wasm_is_module(data: &Vec[UInt8]) -> Bool {
  return _header_kind(data) == 0;
}

/// Decode an unsigned LEB128 u32 at `off`: at most 5 bytes, little-endian
/// 7-bit groups, bit 7 is the continuation flag.
/// Ok((value, offset_after)) on success; the returned value is in
/// `0..4294967295` and `offset_after` points just past the last consumed
/// byte (<= data.len()). Err("wasm: truncated leb128") when the encoding
/// starts at `off` but runs past the end of `data`;
/// Err("wasm: leb128 overflow") when a 5th byte continues the sequence or
/// carries payload bits above bit 31; Err("wasm: negative offset") for
/// `off < 0`. Non-minimal encodings are accepted (structure-only).
pub fn wasm_leb_u32(data: &Vec[UInt8], off: Int) -> Result[(Int, Int), Str] {
  if off < 0 {
    return _err_pair("wasm: negative offset");
  }
  let total = data.len();
  var result: Int = 0;
  var shift = 0;
  var pos = off;
  var i = 0;
  while i < 5 {
    if pos >= total {
      return _err_pair("wasm: truncated leb128");
    }
    let b = _byte(data, pos);
    if i == 4 {
      // A u32 fits in 5 groups only when the last group uses 4 payload
      // bits; any continuation flag here would request a 6th byte.
      if (b & 0xF0) != 0 {
        return _err_pair("wasm: leb128 overflow");
      }
    }
    result = result | ((b & 0x7F) << shift);
    pos = pos + 1;
    if (b & 0x80) == 0 {
      return _ok_pair((result, pos));
    }
    shift = shift + 7;
    i = i + 1;
  }
  return _err_pair("wasm: leb128 overflow");
}

/// Canonical name of a section id: 0 custom, 1 type, 2 import, 3 function,
/// 4 table, 5 memory, 6 global, 7 export, 8 start, 9 element, 10 code,
/// 11 data, 12 datacount; "unknown" for any other id.
pub fn wasm_section_name(id: Int) -> Str {
  if id == 0 { return "custom"; }
  if id == 1 { return "type"; }
  if id == 2 { return "import"; }
  if id == 3 { return "function"; }
  if id == 4 { return "table"; }
  if id == 5 { return "memory"; }
  if id == 6 { return "global"; }
  if id == 7 { return "export"; }
  if id == 8 { return "start"; }
  if id == 9 { return "element"; }
  if id == 10 { return "code"; }
  if id == 11 { return "data"; }
  if id == 12 { return "datacount"; }
  return "unknown";
}

/// Walk every section after the 8-byte header. Each section is `id byte +
/// size LEB128 (u32) + payload`; the payload must fit inside `data`.
/// Returns the parallel id/offset/size vectors in file order (see
/// WasmSections). The header must be valid:
/// Err("wasm: truncated header") for fewer than 8 bytes,
/// Err("wasm: bad magic") / Err("wasm: bad version") for a wrong header.
/// A section whose size LEB128 is malformed propagates
/// "wasm: truncated leb128" / "wasm: leb128 overflow"; a declared payload
/// that extends past the end of `data` yields
/// Err("wasm: truncated section"). Section ids are recorded verbatim
/// (0..255): unknown ids, zero-size payloads and duplicate ids are all
/// accepted (structure-only; ordering and uniqueness are not validated).
pub fn wasm_parse_sections(data: &Vec[UInt8]) -> Result[WasmSections, Str] {
  let kind = _header_kind(data);
  if kind == 1 {
    return _err_sections("wasm: truncated header");
  }
  if kind == 2 {
    return _err_sections("wasm: bad magic");
  }
  if kind == 3 {
    return _err_sections("wasm: bad version");
  }
  var ids = Vec[Int].new();
  var offsets = Vec[Int].new();
  var sizes = Vec[Int].new();
  let total = data.len();
  var pos = 8;
  while pos < total {
    let id = _byte(data, pos);
    pos = pos + 1;
    let sr = wasm_leb_u32(data, pos);
    match sr {
      Ok(pair) => {
        let size: Int = pair.0;
        let after: Int = pair.1;
        if size > total - after {
          return _err_sections("wasm: truncated section");
        }
        ids.push(id);
        offsets.push(after);
        sizes.push(size);
        pos = after + size;
      },
      Err(e) => {
        return _err_sections(e);
      },
    }
  }
  return _ok_sections(WasmSections{ ids: ids; offsets: offsets; sizes: sizes; });
}

// Parse one export section payload [start, end): `count LEB + entries`,
// where an entry is `name (len LEB + UTF-8 bytes) + kind byte + index
// LEB`. Exactly `count` entries are parsed; only the names are collected,
// in order. The caller guarantees 0 <= start <= end <= data.len().
// An empty payload is Ok(empty). An entry that runs past `end` is
// Err("wasm: truncated export"); bytes left after the declared entry
// count are Err("wasm: trailing export bytes"); a name byte 0x00 is
// Err("wasm: nul in export name") because the platform Str is
// NUL-terminated; malformed LEB128 inside the payload propagates
// "wasm: truncated leb128" / "wasm: leb128 overflow".
fn _parse_exports(data: &Vec[UInt8], start: Int, end: Int) -> Result[Vec[Str], Str] {
  var names = Vec[Str].new();
  if start >= end {
    return _ok_names(names);
  }
  let cr = wasm_leb_u32(data, start);
  match cr {
    Ok(cpair) => {
      let count: Int = cpair.0;
      let after: Int = cpair.1;
      if after > end {
        return _err_names("wasm: truncated export");
      }
      var pos = after;
      var i = 0;
      while i < count {
        if pos >= end {
          return _err_names("wasm: truncated export");
        }
        let nr = wasm_leb_u32(data, pos);
        match nr {
          Ok(pair) => {
            let name_start: Int = pair.1;
            let name_len: Int = pair.0;
            if name_start > end {
              return _err_names("wasm: truncated export");
            }
            if name_len > end - name_start {
              return _err_names("wasm: truncated export");
            }
            var sb = Vec[UInt8].new();
            var j = 0;
            while j < name_len {
              if ((data[name_start + j] as Int) & 0xFF) == 0 {
                return _err_names("wasm: nul in export name");
              }
              sb.push(data[name_start + j]);
              j = j + 1;
            }
            names.push(builder.sb_to_str(&sb));
            let entry_end: Int = name_start + name_len;
            if entry_end + 1 >= end {
              return _err_names("wasm: truncated export");
            }
            // The kind byte is consumed but not validated; only the index
            // LEB must be structurally complete inside this payload.
            let ir = wasm_leb_u32(data, entry_end + 1);
            match ir {
              Ok(ipair) => {
                if ipair.1 > end {
                  return _err_names("wasm: truncated export");
                }
                pos = ipair.1;
              },
              Err(e2) => {
                return _err_names(e2);
              },
            }
          },
          Err(e) => {
            return _err_names(e);
          },
        }
        i = i + 1;
      }
      if pos != end {
        return _err_names("wasm: trailing export bytes");
      }
    },
    Err(e) => {
      return _err_names(e);
    },
  }
  return _ok_names(names);
}

/// Export names of section 7, in entry order. The first section with id 7
/// is used; when no export section exists the result is an empty vector.
/// The payload is `count LEB + entries`; exactly `count` entries are read
/// and any leftover payload bytes are an error. Each entry's name is a
/// length-prefixed byte string copied verbatim into a fresh Str (no UTF-8
/// validation); its kind byte and index LEB128 are consumed but not
/// returned. Errors propagate from wasm_parse_sections
/// ("wasm: truncated header" / "wasm: bad magic" / "wasm: bad version" /
/// "wasm: truncated section" / LEB128 errors) and from the entry walk
/// ("wasm: truncated export", "wasm: trailing export bytes",
/// "wasm: nul in export name").
pub fn wasm_export_names(data: &Vec[UInt8]) -> Result[Vec[Str], Str] {
  let secs = wasm_parse_sections(data);
  if !secs.is_ok {
    return _err_names(secs.error);
  }
  let s = secs.value;
  var i = 0;
  while i < s.ids.len() {
    let id: Int = s.ids[i];
    if id == 7 {
      let start: Int = s.offsets[i];
      let size: Int = s.sizes[i];
      return _parse_exports(data, start, start + size);
    }
    i = i + 1;
  }
  var empty = Vec[Str].new();
  return _ok_names(empty);
}
