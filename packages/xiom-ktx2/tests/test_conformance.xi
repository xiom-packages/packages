// XIOM -- xiom.ktx2 Conformance Test Suite
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Exercises the VENDORED libktx (KTX-Software v4.4.2, commit 4d6fc70e;
// compiled via port.args.json together with the Basis transcoder/encoder,
// dfdutils, the Arm ASTC encoder and the vendored zstd) end to end:
//   * link-time resolution of all 93 public ktx.h functions (symbol table
//     taken in src/ktx2_bridge.c; count + name-lookup checks here)
//   * KTX2 write -> read round trip in memory (levels/format/bytes) and
//     with ZSTD/ZLIB supercompression
//   * named-file %TEMP% round trip and custom ktxStream + stdio streams
//   * KTX1 write/read and the KTX1 -> KTX2 conversion
//   * Basis transcode (ETC1S -> BC1/ETC1/RGBA32, UASTC -> BC7)
//   * Arm ASTC encode (4x4 LDR) + decode
//   * hash-list metadata API, string tables, GL loader probe
//   * corrupt-input typed errors
//
// Run: scripts/port.ps1 -Package xiom.ktx2 -TimeoutSec 1800

module ktx2_conformance
use xiom.io;
use xiom.test;
use xiom.ktx2;

// =========================================================================
// Helpers
// =========================================================================

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  return out;
}

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

fn bstr(b: Bool) -> Str {
  if b { return "1"; }
  return "0";
}

/// n-byte zero slot (module helper; local alias keeps call sites short).
fn bufs(n: Int) -> Vec[UInt8]
  requires: n > 0
{
  return ktx2_slot(n);
}

/// True when `buf` starts with the 12-byte KTX2 identifier.
fn is_ktx2_magic(buf: &Vec[UInt8]) -> Bool
  requires: buf.len() >= 12
{
  return buf[0] as Int == 171 && buf[1] as Int == 75 && buf[2] as Int == 84
    && buf[3] as Int == 88 && buf[4] as Int == 32 && buf[5] as Int == 50
    && buf[6] as Int == 48 && buf[7] as Int == 187 && buf[8] as Int == 13
    && buf[9] as Int == 10 && buf[10] as Int == 26 && buf[11] as Int == 10;
}

fn bytes_match(buf: &Vec[UInt8], other: &Vec[UInt8], n: Int) -> Bool
  requires: buf.len() >= n
  requires: other.len() >= n
{
  var i: Int = 0;
  while i < n {
    if buf[i] != other[i] { return false; }
    i = i + 1;
  }
  return true;
}

// =========================================================================
// SECTION 1 -- Constant surface (4 checks)
// =========================================================================

fn test_const_error_codes() -> TestResult {
  let ok = KTX_SUCCESS == 0 as Int32
    && KTX_FILE_UNEXPECTED_EOF == 7 as Int32
    && KTX_GL_ERROR == 9 as Int32
    && KTX_INVALID_OPERATION == 10 as Int32
    && KTX_UNKNOWN_FILE_FORMAT == 15 as Int32
    && KTX_UNSUPPORTED_FEATURE == 17 as Int32
    && KTX_ERROR_MAX_ENUM == 20 as Int32;
  return assert(ok, "const: KTX error codes (SUCCESS=0, EOF=7, GL=9, INVALID_OP=10, UNKNOWN=15, UNSUPPORTED=17, MAX=20)");
}

fn test_const_supercompression_and_flags() -> TestResult {
  let ok = KTX_SS_NONE == 0 as Int32
    && KTX_SS_BASIS_LZ == 1 as Int32
    && KTX_SS_ZSTD == 2 as Int32
    && KTX_SS_ZLIB == 3 as Int32
    && KTX_TEXTURE_CREATE_NO_STORAGE == 0 as Int32
    && KTX_TEXTURE_CREATE_ALLOC_STORAGE == 1 as Int32
    && KTX_TEXTURE_CREATE_LOAD_IMAGE_DATA_BIT == 1 as Int32
    && KTX_TEXTURE_CREATE_CHECK_GLTF_BASISU_BIT == 8 as Int32;
  return assert(ok, "const: supercompression (NONE/LZ/ZSTD/ZLIB) + create flags");
}

fn test_const_transcode_formats() -> TestResult {
  let ok = KTX_TTF_ETC1_RGB == 0 as Int32
    && KTX_TTF_BC1_RGB == 2 as Int32
    && KTX_TTF_BC3_RGBA == 3 as Int32
    && KTX_TTF_BC7_RGBA == 6 as Int32
    && KTX_TTF_ASTC_4x4_RGBA == 10 as Int32
    && KTX_TTF_RGBA32 == 13 as Int32
    && KTX_PACK_UASTC_LEVEL_DEFAULT == 2 as Int32;
  return assert(ok, "const: transcode formats (ETC1=0, BC1=2, BC3=3, BC7=6, ASTC=10, RGBA32=13)");
}

fn test_const_df_and_vk_formats() -> TestResult {
  let ok = KHR_DF_MODEL_RGBSDA == 1 as Int32
    && KHR_DF_MODEL_ETC1S == 163 as Int32
    && KHR_DF_MODEL_UASTC == 166 as Int32
    && KHR_DF_TRANSFER_SRGB == 2 as Int32
    && KHR_DF_PRIMARIES_BT709 == 1 as Int32
    && VK_FORMAT_R8G8B8_UNORM == 23 as Int32
    && VK_FORMAT_R8G8B8A8_UNORM == 37 as Int32
    && VK_FORMAT_BC1_RGB_UNORM_BLOCK == 131 as Int32
    && VK_FORMAT_BC7_UNORM_BLOCK == 145 as Int32
    && VK_FORMAT_ETC2_R8G8B8_UNORM_BLOCK == 147 as Int32
    && VK_FORMAT_ASTC_4x4_UNORM_BLOCK == 157 as Int32;
  return assert(ok, "const: DFD models/transfer + VK formats (RGB8=23, RGBA8=37, BC1=131, BC7=145, ETC2=147, ASTC=157)");
}

// =========================================================================
// SECTION 2 -- Declared surface (4 checks)
// =========================================================================

fn test_symbol_count() -> TestResult {
  let n = ktx2_symbol_count();
  return assert(n == 93, "surface: symbol table holds all 93 declared ktx.h functions (got " + int_to_str(n) + ")");
}

fn test_symbol_lookup_representative() -> TestResult {
  let a = ktx2_symbol_lookup("ktxTexture2_TranscodeBasis");
  let b = ktx2_symbol_lookup("ktxTexture2_CompressBasisEx");
  let c = ktx2_symbol_lookup("ktxTexture2_WriteToMemory");
  let d = ktx2_symbol_lookup("ktxErrorString");
  let e = ktx2_symbol_lookup("ktxHashList_Serialize");
  let f = ktx2_symbol_lookup("ktxPrintKTX2InfoJSONForMemory");
  let g = ktx2_symbol_lookup("ktxTexture1_WriteKTX2ToMemory");
  let h = ktx2_symbol_lookup("ktxLoadOpenGL");
  let ok = a >= 0 && b >= 0 && c >= 0 && d >= 0 && e >= 0 && f >= 0
        && g >= 0 && h >= 0 && a != b && c != d && e != f && g != h;
  return assert(ok, "surface: representative lookups resolve distinct indexes (transcode/basis/write/error/hash/json/ktx1/gl)");
}

fn test_symbol_names_roundtrip() -> TestResult {
  let n = ktx2_symbol_count();
  var buf = bufs(64);
  var ok = true;
  var i: Int = 0;
  while i < n {
    let len = ktx2_symbol_name(i, &mut buf);
    if len <= 0 { ok = false; }
    else {
      var nv: Vec[UInt8] = Vec[UInt8].new();
      var j: Int = 0;
      while j < len {
        nv.push(buf[j]);
        j = j + 1;
      }
      let name = Str::from_utf8(nv);
      if ktx2_symbol_lookup(name) != i { ok = false; }
    }
    i = i + 1;
  }
  return assert(ok, "surface: all 93 names copy out and round-trip through exact lookup");
}

fn test_symbol_lookup_absent() -> TestResult {
  let a = ktx2_symbol_lookup("ktxTexture2_NotAFunction");
  let b = ktx2_symbol_lookup("ktxTexture2_WriteToMemoryX");
  return assert(a == -1 && b == -1, "surface: unknown names return -1");
}

// =========================================================================
// SECTION 3 -- KTX2 in-memory round trip (8 checks)
// =========================================================================

fn test_ktx2_write_read() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var generated = bufs(4096);
  var slot = bufs(128);
  let rt = ktx2_roundtrip(0, &mut image, &mut generated, &mut slot);
  match rt {
    Err(rc) => { return assert(false, "roundtrip: probe setup failed (KTX " + int_to_str(rc) + ")"); },
    Ok(r) => {
      let ok = r.write_rc == 0 && r.write_len > 64 && r.read_rc == 0
            && r.class_id == 2 && r.vk_format == 23 && r.num_levels == 1
            && r.data_size == 48;
      return assert(ok, "roundtrip: write_rc=0 len=" + int_to_str(r.write_len)
        + " read_rc=" + int_to_str(r.read_rc) + " class=2 vk=23 levels=1 dataSize=48");
    }
  }
}

fn test_ktx2_level_bytes() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var generated = bufs(4096);
  var slot = bufs(128);
  let rt = ktx2_roundtrip(0, &mut image, &mut generated, &mut slot);
  match rt {
    Err(rc) => { return assert(false, "level bytes: setup failed (KTX " + int_to_str(rc) + ")"); },
    Ok(r) => {
      var decoded = bufs(64);
      var created = bufs(128);
      let info = ktx2_read_info(&mut generated, &mut created);
      match info {
        Err(rc) => { return assert(false, "level bytes: re-read failed (KTX " + int_to_str(rc) + ")"); },
        Ok(_i) => {
          let ok = r.level0_len == 48 && !r.level0_mismatch;
          return assert(ok, "roundtrip: level 0 is 48 bytes and matches the source pixels byte-for-byte");
        }
      }
    }
  }
}

fn test_ktx2_identifier() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var generated = bufs(4096);
  var slot = bufs(128);
  let rt = ktx2_roundtrip(0, &mut image, &mut generated, &mut slot);
  match rt {
    Err(_rc) => { return assert(false, "identifier: setup failed"); },
    Ok(_r) => {
      return assert(is_ktx2_magic(&generated), "roundtrip: serialized bytes start with the 12-byte KTX2 identifier");
    }
  }
}

fn test_ktx2_info_fields() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var generated = bufs(4096);
  var slot = bufs(128);
  let rt = ktx2_roundtrip(0, &mut image, &mut generated, &mut slot);
  match rt {
    Err(_rc) => { return assert(false, "info: setup failed"); },
    Ok(_r) => {
      var rec = bufs(128);
      let info = ktx2_read_info(&mut generated, &mut rec);
      match info {
        Err(rc) => { return assert(false, "info: parse failed (KTX " + int_to_str(rc) + ")"); },
        Ok(i) => {
          let ok = i.class_id == 2 && i.vk_format == 23 && i.base_width == 4
            && i.base_height == 4 && i.base_depth == 1 && i.num_levels == 1
            && i.num_faces == 1 && i.num_layers == 1 && !i.is_array
            && !i.is_cubemap && !i.is_compressed && i.supercompression == 0
            && i.num_components == 3 && !i.needs_transcoding
            && i.data_size == 48 && i.component_byte_length == 1
            && i.format_code == 23;
          return assert(ok, "info: KTX2 4x4 RGB8 record (class="
            + int_to_str(i.class_id) + " vk=" + int_to_str(i.vk_format)
            + " dims=" + int_to_str(i.base_width) + "x" + int_to_str(i.base_height)
            + "x" + int_to_str(i.base_depth) + " levels=" + int_to_str(i.num_levels)
            + " faces=" + int_to_str(i.num_faces) + " layers=" + int_to_str(i.num_layers)
            + " scheme=" + int_to_str(i.supercompression) + " comps=" + int_to_str(i.num_components)
            + " cblen=" + int_to_str(i.component_byte_length)
            + " dataSize=" + int_to_str(i.data_size) + ")");
        }
      }
    }
  }
}

fn test_ktx2_row_pitch_and_iterate() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var generated = bufs(4096);
  var slot = bufs(128);
  let rt = ktx2_roundtrip(0, &mut image, &mut generated, &mut slot);
  match rt {
    Err(_rc) => { return assert(false, "iterate: setup failed"); },
    Ok(r) => {
      let ok = r.row_pitch == 12 && r.element_size == 3
            && r.iter_rc == 0 && r.iter_images == 1 && r.iter_bytes == 48
            && r.iter_first_byte == 0;
      return assert(ok, "roundtrip: rowPitch=12 elemSize=3; IterateLevelFaces visits 1 image of 48 bytes (first byte 0)");
    }
  }
}

fn test_ktx2_create_copy_and_color() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var generated = bufs(4096);
  var slot = bufs(128);
  let rt = ktx2_roundtrip(0, &mut image, &mut generated, &mut slot);
  match rt {
    Err(_rc) => { return assert(false, "copy: setup failed"); },
    Ok(r) => {
      let ok = r.copy_rc == 0 && r.copy_levels == 1
            && r.tf_e == 1 && r.oetf_e == 1 && r.oetf == r.tf_e
            && r.color_model == 1 && !r.premultiplied
            && r.set_tf_rc == 0 && r.set_oetf_rc == 0 && r.set_primaries_rc == 0
            && r.num_components == 3;
      return assert(ok, "roundtrip: CreateCopy (rc=" + int_to_str(r.copy_rc)
        + " levels=" + int_to_str(r.copy_levels) + "); model=" + int_to_str(r.color_model)
        + " tf_e=" + int_to_str(r.tf_e) + " oetf_e=" + int_to_str(r.oetf_e)
        + " oetf=" + int_to_str(r.oetf) + " premult=" + bstr(r.premultiplied)
        + " SetTransferFunction=" + int_to_str(r.set_tf_rc)
        + " SetOETF=" + int_to_str(r.set_oetf_rc)
        + " SetPrimaries=" + int_to_str(r.set_primaries_rc)
        + " comps=" + int_to_str(r.num_components));
    }
  }
}

fn test_ktx2_zstd_roundtrip() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var generated = bufs(4096);
  var slot = bufs(128);
  let rt = ktx2_roundtrip(1, &mut image, &mut generated, &mut slot);
  match rt {
    Err(rc) => { return assert(false, "zstd: setup failed (KTX " + int_to_str(rc) + ")"); },
    Ok(r) => {
      let ok = r.write_rc == 0 && r.supercompression == 2 && r.read_rc == 0
            && r.data_size == 48 && !r.level0_mismatch;
      return assert(ok, "zstd: DeflateZstd scheme=" + int_to_str(r.supercompression)
        + " write_rc=" + int_to_str(r.write_rc) + " read_rc=" + int_to_str(r.read_rc)
        + " dataSize=" + int_to_str(r.data_size)
        + " mismatch=" + bstr(r.level0_mismatch));
    }
  }
}

fn test_ktx2_zlib_roundtrip() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var generated = bufs(4096);
  var slot = bufs(128);
  let rt = ktx2_roundtrip(2, &mut image, &mut generated, &mut slot);
  match rt {
    Err(rc) => { return assert(false, "zlib: setup failed (KTX " + int_to_str(rc) + ")"); },
    Ok(r) => {
      let ok = r.write_rc == 0 && r.supercompression == 3 && r.read_rc == 0
            && r.data_size == 48 && !r.level0_mismatch;
      return assert(ok, "zlib: DeflateZLIB scheme=" + int_to_str(r.supercompression)
        + " write_rc=" + int_to_str(r.write_rc) + " read_rc=" + int_to_str(r.read_rc)
        + " dataSize=" + int_to_str(r.data_size)
        + " mismatch=" + bstr(r.level0_mismatch));
    }
  }
}

fn test_deflated_load_zstd() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var raw = bufs(4096);
  var inflated = bufs(4096);
  var slot = bufs(96);
  let probe = ktx2_deflated_probe(0, &mut image, &mut raw, &mut inflated, &mut slot);
  match probe {
    Err(rc) => { return assert(false, "deflated zstd: probe failed (KTX " + int_to_str(rc) + ")"); },
    Ok(d) => {
      let ok = d.deflate_rc == 0 && d.write_rc == 0 && d.scheme == 2
            && d.raw_load_rc == 0 && d.raw_match && d.pdata_null
            && d.inflate_read_rc == 0 && !d.inflated_mismatch
            && d.data_size_after == d.deflated_size && d.removed;
      return assert(ok, "deflated: ZSTD scheme=" + int_to_str(d.scheme)
        + " deflated=" + int_to_str(d.deflated_size)
        + " rawLoad=" + int_to_str(d.raw_load_rc) + " rawMatch=" + bstr(d.raw_match)
        + " rawHead=" + int_to_str(d.raw_head) + " loadedHead=" + int_to_str(d.loaded_head)
        + " firstBad=" + int_to_str(d.mismatch_index) + " rawB=" + int_to_str(d.mismatch_raw_byte)
        + " loadedB=" + int_to_str(d.mismatch_loaded_byte)
        + " pDataNull=" + bstr(d.pdata_null)
        + " freshInflateRead=" + int_to_str(d.inflate_read_rc)
        + " mismatch=" + bstr(d.inflated_mismatch)
        + " dataSizeAfter=" + int_to_str(d.data_size_after)
        + " fileBytes=" + int_to_str(d.file_bytes) + " removed=" + bstr(d.removed));
    }
  }
}

fn test_deflated_load_zlib() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var raw = bufs(4096);
  var inflated = bufs(4096);
  var slot = bufs(96);
  let probe = ktx2_deflated_probe(1, &mut image, &mut raw, &mut inflated, &mut slot);
  match probe {
    Err(rc) => { return assert(false, "deflated zlib: probe failed (KTX " + int_to_str(rc) + ")"); },
    Ok(d) => {
      let ok = d.deflate_rc == 0 && d.write_rc == 0 && d.scheme == 3
            && d.raw_load_rc == 0 && d.raw_match && d.pdata_null
            && d.inflate_read_rc == 0 && !d.inflated_mismatch
            && d.data_size_after == d.deflated_size && d.removed;
      return assert(ok, "deflated: ZLIB scheme=" + int_to_str(d.scheme)
        + " deflated=" + int_to_str(d.deflated_size)
        + " rawLoad=" + int_to_str(d.raw_load_rc) + " rawMatch=" + bstr(d.raw_match)
        + " pDataNull=" + bstr(d.pdata_null)
        + " freshInflateRead=" + int_to_str(d.inflate_read_rc)
        + " mismatch=" + bstr(d.inflated_mismatch)
        + " dataSizeAfter=" + int_to_str(d.data_size_after)
        + " fileBytes=" + int_to_str(d.file_bytes) + " removed=" + bstr(d.removed));
    }
  }
}

fn test_lifecycle_primitives() -> TestResult {
  var handle = bufs(8);
  var image = ktx2_test_image_rgb8();
  let spec = Ktx2TextureSpec{
    kind: 2, vk_format: 23, gl_internal_format: 0,
    width: 4, height: 4, depth: 1, levels: 1, layers: 1, faces: 1,
    is_array: false, generate_mipmaps: false
  };
  let created = ktx2_create(spec, &mut handle);
  if created.is_err {
    return assert(false, "lifecycle: ktx2_create (handle slot)");
  }
  let populated = !ktx2_handle_is_null(&handle);
  let set = ktx2_set_image(&mut handle, 2, 0, 0, 0, &mut image);
  var payload = bufs(4096);
  var len_slot = bufs(8);
  let written = ktx2_write_memory(&mut handle, 2, &mut payload, &mut len_slot);
  let destroy1 = ktx2_destroy(2, &mut handle);
  let empty_after = ktx2_handle_is_null(&handle);
  let destroy2 = ktx2_destroy(2, &mut handle);
  var lvl = bufs(64);
  let read_back = ktx2_read_level(&mut payload, 0, &mut lvl, &mut len_slot);
  let bytes_ok = bytes_match(&lvl, &image, 48);
  let ok = populated && set.is_ok && written.is_ok && destroy1.is_ok
        && empty_after && destroy2.is_err && read_back.is_ok && bytes_ok;
  return assert(ok, "lifecycle: create/set/write/read-level/destroy via owned handle slots; double destroy typed error; bytes match");
}

// =========================================================================
// SECTION 4 -- Named file (2 checks)
// =========================================================================

fn test_named_file_roundtrip() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var slot = bufs(64);
  var path_buf = bufs(512);
  let probe = ktx2_named_file_probe(&mut image, &mut slot, &mut path_buf);
  match probe {
    Err(rc) => { return assert(false, "named file: probe failed (KTX " + int_to_str(rc) + ")"); },
    Ok(p) => {
      let ok = p.create_rc == 0 && p.write_rc == 0 && p.read_rc == 0
            && p.class_id == 2 && p.data_size == 48 && p.file_bytes > 64
            && p.removed && p.path_len > 0;
      return assert(ok, "named file: %TEMP% WriteToNamedFile -> CreateFromNamedFile (class=2 dataSize=48 bytes="
        + int_to_str(p.file_bytes) + ", temp file removed)");
    }
  }
}

fn test_named_file_cleanup() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var slot = bufs(64);
  var path_buf = bufs(512);
  let probe = ktx2_named_file_probe(&mut image, &mut slot, &mut path_buf);
  match probe {
    Err(_rc) => { return assert(false, "named file cleanup: probe failed"); },
    Ok(p) => {
      return assert(p.removed, "named file: probe removes its temp file (no leftovers)");
    }
  }
}

// =========================================================================
// SECTION 5 -- KTX1 + conversion (3 checks)
// =========================================================================

fn test_ktx1_roundtrip() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var k1 = bufs(4096);
  var k2 = bufs(4096);
  var probe_buf = bufs(48);
  var slot = bufs(96);
  let probe = ktx2_ktx1_probe(&mut image, &mut k1, &mut k2, &mut probe_buf, &mut slot);
  match probe {
    Err(rc) => { return assert(false, "ktx1: probe failed (KTX " + int_to_str(rc) + ")"); },
    Ok(p) => {
      let ok = p.create_rc == 0 && p.set_rc == 0 && p.write_rc == 0
            && p.write_len > 64 && p.read_rc == 0 && p.class_id == 1
            && p.data_size == 48 && p.load_rc == 0 && !p.cmp_mismatch;
      return assert(ok, "ktx1: create/write/read + LoadImageData round trip (class=1 dataSize=48 bytes match)");
    }
  }
}

fn test_ktx1_gl_fields() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var k1 = bufs(4096);
  var k2 = bufs(4096);
  var probe_buf = bufs(48);
  var slot = bufs(96);
  let probe = ktx2_ktx1_probe(&mut image, &mut k1, &mut k2, &mut probe_buf, &mut slot);
  match probe {
    Err(_rc) => { return assert(false, "ktx1 gl: probe failed"); },
    Ok(p) => {
      let ok = p.gl_internalformat == 32849 && p.gl_format == 6407
            && p.gl_type == 5121 && !p.needs_transcoding;
      return assert(ok, "ktx1: GL_RGB8/GL_RGB/GL_UNSIGNED_BYTE carried; NeedsTranscoding=false");
    }
  }
}

fn test_ktx1_to_ktx2_conversion() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var k1 = bufs(4096);
  var k2 = bufs(4096);
  var probe_buf = bufs(48);
  var slot = bufs(96);
  let probe = ktx2_ktx1_probe(&mut image, &mut k1, &mut k2, &mut probe_buf, &mut slot);
  match probe {
    Err(_rc) => { return assert(false, "ktx1->ktx2: probe failed"); },
    Ok(p) => {
      let ok = p.ktx2_rc == 0 && p.ktx2_len > 64 && is_ktx2_magic(&k2)
            && p.ktx2_read_rc == 0 && p.ktx2_super == 0
            && p.ktx2_level0_len == 48 && !p.cmp_mismatch
            && bytes_match(&probe_buf, &image, 48);
      return assert(ok, "ktx1->ktx2: WriteKTX2ToMemory emits a parseable KTX2 (identifier, scheme 0, level0 48 bytes)");
    }
  }
}

// =========================================================================
// SECTION 6 -- Streams + stdio (3 checks)
// =========================================================================

fn test_stream_ktx2_roundtrip() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var payload = bufs(65536);
  var slot = bufs(96);
  let probe = ktx2_stream_probe(&mut image, &mut payload, &mut slot);
  match probe {
    Err(rc) => { return assert(false, "stream: probe failed (KTX " + int_to_str(rc) + ")"); },
    Ok(p) => {
      let ok = p.wstream_rc == 0 && p.wstream_len > 64 && p.rstream_rc == 0
            && p.rstream_class == 2 && p.rstream_data_size == 48
            && !p.rstream_mismatch && p.stream_getsize == p.wstream_len;
      return assert(ok, "stream: ktxTexture2_WriteToStream -> ktxTexture_CreateFromStream (class=2 dataSize=48, getsize="
        + int_to_str(p.stream_getsize) + ")");
    }
  }
}

fn test_stream_stdio_roundtrip() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var payload = bufs(65536);
  var slot = bufs(96);
  let probe = ktx2_stream_probe(&mut image, &mut payload, &mut slot);
  match probe {
    Err(_rc) => { return assert(false, "stdio: probe failed"); },
    Ok(p) => {
      let ok = p.stdio_write_rc == 0 && p.stdio_rewind_ok
            && p.stdio_base_read_rc == 0 && p.stdio_class == 2
            && p.stdio2_read_rc == 0 && p.stdio2_data_size == 48;
      return assert(ok, "stdio: WriteToStdioStream -> CreateFromStdioStream (base + typed) both read class=2 dataSize=48");
    }
  }
}

fn test_stream_ktx1_paths() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var payload = bufs(65536);
  var slot = bufs(96);
  let probe = ktx2_stream_probe(&mut image, &mut payload, &mut slot);
  match probe {
    Err(_rc) => { return assert(false, "ktx1 stream: probe failed"); },
    Ok(p) => {
      let ok = p.ktx1_wstream_rc == 0 && p.ktx1_wstream_len > 64
            && p.ktx1_rstream_rc == 0 && p.ktx1_class == 1
            && p.ktx1_ktx2stream_rc == 0 && p.ktx1_ktx2stream_len > 64
            && p.ktx2_from_ktx1stream_rc == 0 && p.ktx2_from_ktx1_data_size == 48;
      return assert(ok, "stream: KTX1 WriteToStream rc=" + int_to_str(p.ktx1_wstream_rc)
        + " len=" + int_to_str(p.ktx1_wstream_len)
        + "; CreateFromStream rc=" + int_to_str(p.ktx1_rstream_rc)
        + " class=" + int_to_str(p.ktx1_class)
        + "; WriteKTX2ToStream rc=" + int_to_str(p.ktx1_ktx2stream_rc)
        + " len=" + int_to_str(p.ktx1_ktx2stream_len)
        + "; KTX2 read rc=" + int_to_str(p.ktx2_from_ktx1stream_rc)
        + " dataSize=" + int_to_str(p.ktx2_from_ktx1_data_size));
    }
  }
}

// =========================================================================
// SECTION 7 -- Basis transcode (4 checks)
// =========================================================================

fn test_basis_etc1s_to_bc1() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var payload = bufs(4096);
  var slot = bufs(128);
  let probe = ktx2_basis_probe(0, &mut image, &mut payload, &mut slot);
  match probe {
    Err(rc) => { return assert(false, "basis ETC1S->BC1: probe failed (KTX " + int_to_str(rc) + ")"); },
    Ok(p) => {
      let ok = p.encode_rc == 0 && p.needs_transcoding && p.num_components == 1
            && p.transcode_rc == 0 && p.vk_format_after == 131
            && p.super_final == 0 && p.is_compressed && p.level0_size == 8
            && p.transcode2_rc != 0 && p.write2_rc == 0 && p.write2_len > 64
            && p.payload_vk_format == 131;
      return assert(ok, "basis ETC1S->BC1: encode_rc=" + int_to_str(p.encode_rc)
        + " needsTranscode=" + bstr(p.needs_transcoding)
        + " comps=" + int_to_str(p.num_components) + " (BC1 DFD = 1 color channel)"
        + " transcode_rc=" + int_to_str(p.transcode_rc)
        + " vk=" + int_to_str(p.vk_format_after)
        + " super=" + int_to_str(p.super_final)
        + " level0=" + int_to_str(p.level0_size)
        + " isCompressed=" + bstr(p.is_compressed)
        + " transcode2_rc=" + int_to_str(p.transcode2_rc)
        + " write2_rc=" + int_to_str(p.write2_rc)
        + " write2_len=" + int_to_str(p.write2_len)
        + " payloadVk=" + int_to_str(p.payload_vk_format));
    }
  }
}

fn test_basis_uastc_to_bc7() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var payload = bufs(4096);
  var slot = bufs(128);
  let probe = ktx2_basis_probe(1, &mut image, &mut payload, &mut slot);
  match probe {
    Err(rc) => { return assert(false, "basis UASTC->BC7: probe failed (KTX " + int_to_str(rc) + ")"); },
    Ok(p) => {
      let ok = p.encode_rc == 0 && p.needs_transcoding
            && p.transcode_rc == 0 && p.vk_format_after == 145
            && p.level0_size == 16 && p.is_compressed && p.write2_rc == 0;
      return assert(ok, "basis: UASTC encode (CompressBasisEx, level default) -> TranscodeBasis(BC7_RGBA) vk=145 level0=16");
    }
  }
}

fn test_basis_etc1s_to_etc1() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var payload = bufs(4096);
  var slot = bufs(128);
  let probe = ktx2_basis_probe(2, &mut image, &mut payload, &mut slot);
  match probe {
    Err(rc) => { return assert(false, "basis ETC1S->ETC1: probe failed (KTX " + int_to_str(rc) + ")"); },
    Ok(p) => {
      let ok = p.encode_rc == 0 && p.transcode_rc == 0
            && p.vk_format_after == 147 && p.level0_size == 8;
      return assert(ok, "basis: ETC1S -> TranscodeBasis(ETC1_RGB) vk=147 level0=8 (basisu ETC1 writer, no etcdec)");
    }
  }
}

fn test_basis_etc1s_to_rgba32() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var payload = bufs(4096);
  var slot = bufs(128);
  let probe = ktx2_basis_probe(3, &mut image, &mut payload, &mut slot);
  match probe {
    Err(rc) => { return assert(false, "basis ETC1S->RGBA32: probe failed (KTX " + int_to_str(rc) + ")"); },
    Ok(p) => {
      let ok = p.encode_rc == 0 && p.transcode_rc == 0
            && p.vk_format_after == 37 && p.level0_size == 64;
      return assert(ok, "basis: ETC1S -> TranscodeBasis(RGBA32) vk=37 level0=64 (decoded, uncompressed)");
    }
  }
}

// =========================================================================
// SECTION 8 -- ASTC (2 checks)
// =========================================================================

fn test_astc_compress() -> TestResult {
  var image = ktx2_test_image_rgba8();
  var payload = bufs(4096);
  var decoded = bufs(64);
  var slot = bufs(64);
  let probe = ktx2_astc_probe(&mut image, &mut payload, &mut decoded, &mut slot);
  match probe {
    Err(rc) => { return assert(false, "astc: probe failed (KTX " + int_to_str(rc) + ")"); },
    Ok(p) => {
      let ok = p.compress_rc == 0 && p.vk_after_compress == 157
            && p.is_compressed && p.data_size_after_compress == 16
            && p.level0_after_compress == 16 && p.write_rc == 0
            && p.write_len > 64 && p.block_dim == 0 && p.quality == 0;
      return assert(ok, "astc: CompressAstcEx (4x4 LDR fastest) vk=157, 16 bytes for 4x4, serializes");
    }
  }
}

fn test_astc_decode() -> TestResult {
  var image = ktx2_test_image_rgba8();
  var payload = bufs(4096);
  var decoded = bufs(64);
  var slot = bufs(64);
  let probe = ktx2_astc_probe(&mut image, &mut payload, &mut decoded, &mut slot);
  match probe {
    Err(_rc) => { return assert(false, "astc decode: probe failed"); },
    Ok(p) => {
      let ok = p.decode_rc == 0 && p.vk_after_decode == 37
            && p.data_size_after_decode == 64 && p.level0_after_decode == 64
            && p.decoded_len == 64;
      return assert(ok, "astc: DecodeAstc returns 64 bytes RGBA8 (vk=37); lossy, so exact pixel match is not asserted");
    }
  }
}

// =========================================================================
// SECTION 9 -- Hash list (2 checks)
// =========================================================================

fn test_hashlist_core() -> TestResult {
  var slot = bufs(96);
  let probe = ktx2_hashlist_probe(&mut slot);
  match probe {
    Err(rc) => { return assert(false, "hashlist: probe failed (KTX " + int_to_str(rc) + ")"); },
    Ok(h) => {
      let ok = h.create_rc == 0 && h.add_rc == 0 && h.find_rc == 0
            && h.value_len == 9 && h.value0 == 118 && h.value1 == 97
            && h.value2 == 108 && h.value3 == 117
            && h.next_count == 2 && h.sort_rc == 0 && h.ser_rc == 0
            && h.ser_len > 0;
      return assert(ok, "hashlist: Create/AddKVPair x2/FindValue('value-one')/Next=2/Sort/Serialize");
    }
  }
}

fn test_hashlist_serialize_and_lifecycle() -> TestResult {
  var slot = bufs(96);
  let probe = ktx2_hashlist_probe(&mut slot);
  match probe {
    Err(_rc) => { return assert(false, "hashlist2: probe failed"); },
    Ok(h) => {
      let ok = h.deser_rc == 0 && h.find2_rc == 0 && h.value2_len == 9
            && h.value20 == 118 && h.value21 == 97
            && h.getkey_rc == 0 && h.key_len == 11
            && h.key0 == 120 && h.key1 == 105 && h.key2 == 111 && h.key3 == 109
            && h.getval_rc == 0 && h.delete_rc == 0 && h.delete_entry_rc == 0
            && h.destroy_rc == 0 && h.copy_rc == 0 && h.copy_entries == 1
            && h.construct_ok == 0 && h.destruct_ok == 1;
      return assert(ok, "hashlist: deser=" + int_to_str(h.deser_rc)
        + " find2=" + int_to_str(h.find2_rc) + " value2Len=" + int_to_str(h.value2_len)
        + " value2[0..3]=" + int_to_str(h.value20) + "," + int_to_str(h.value21)
        + "," + int_to_str(h.value22) + "," + int_to_str(h.value23)
        + " getkey=" + int_to_str(h.getkey_rc) + " keyLen=" + int_to_str(h.key_len)
        + " (stores the NUL) key[0..3]=" + int_to_str(h.key0) + "," + int_to_str(h.key1)
        + "," + int_to_str(h.key2) + "," + int_to_str(h.key3)
        + " getval=" + int_to_str(h.getval_rc) + " deleteKV=" + int_to_str(h.delete_rc)
        + " deleteEntry=" + int_to_str(h.delete_entry_rc)
        + " destroy=" + int_to_str(h.destroy_rc) + " copy=" + int_to_str(h.copy_rc)
        + " copyEntries=" + int_to_str(h.copy_entries)
        + " addStack=" + int_to_str(h.construct_ok));
    }
  }
}

// =========================================================================
// SECTION 10 -- Strings + GL (2 checks)
// =========================================================================

fn test_string_tables() -> TestResult {
  var dst = bufs(128);
  var slot = bufs(8);
  let e0 = ktx2_c_string(0, 0, &mut dst, &mut slot);
  var e0_len = -1;
  var e0_b0 = -1;
  var e0_b1 = -1;
  match e0 {
    Err(rc) => { return assert(false, "strings: ktxErrorString failed (KTX " + int_to_str(rc) + ")"); },
    Ok(l) => {
      e0_len = l;
      e0_b0 = dst[0] as Int;
      e0_b1 = dst[1] as Int;
    }
  }
  let e1 = ktx2_c_string(1, 2, &mut dst, &mut slot);
  var e1_len = -1;
  var e1_b0 = -1;
  match e1 {
    Err(_rc) => { return assert(false, "strings: supercompression string failed"); },
    Ok(l) => {
      e1_len = l;
      e1_b0 = dst[0] as Int;
    }
  }
  let e2 = ktx2_c_string(2, 6, &mut dst, &mut slot);
  var e2_len = -1;
  var e2_b0 = -1;
  var e2_b1 = -1;
  var e2_b2 = -1;
  match e2 {
    Err(_rc) => { return assert(false, "strings: transcode format string failed"); },
    Ok(l) => {
      e2_len = l;
      e2_b0 = dst[0] as Int;
      e2_b1 = dst[1] as Int;
      e2_b2 = dst[2] as Int;
    }
  }
  let ok = e0_len == 20 && e0_b0 == 79 && e0_b1 == 112
        && e1_len == 11 && e1_b0 == 75
        && e2_len == 8 && e2_b0 == 66 && e2_b1 == 67 && e2_b2 == 55;
  return assert(ok, "strings: errLen=" + int_to_str(e0_len)
    + " err[0..1]=" + int_to_str(e0_b0) + "," + int_to_str(e0_b1)
    + " (Operation succeeded.); schemeLen=" + int_to_str(e1_len)
    + " scheme[0]=" + int_to_str(e1_b0) + " (KTX_SS_ZSTD); fmtLen="
    + int_to_str(e2_len) + " fmt[0..2]=" + int_to_str(e2_b0) + ","
    + int_to_str(e2_b1) + "," + int_to_str(e2_b2) + " (BC7_RGBA)");
}

fn test_gl_probe() -> TestResult {
  var slot = bufs(32);
  let g = ktx2_gl_probe(&mut slot);
  // ktxLoadOpenGL(NULL) only succeeds when the process has already loaded an
  // OpenGL library (GetModuleHandleEx, no LoadLibrary). A console test
  // process has not, so the upstream contract yields KTX_LIBRARY_NOT_LINKED
  // and no upload is attempted (0xFFFFFFFF sentinel).
  let ok = g.load_rc == 18 && g.upload_rc == 4294967295 && g.texture == 0
        && g.class_id == 0;
  return assert(ok, "gl: ktxLoadOpenGL(NULL) rc=" + int_to_str(g.load_rc)
    + " (loader not loaded -> KTX_LIBRARY_NOT_LINKED=18); upload not attempted="
    + bstr(g.upload_rc == 4294967295) + " texture=" + int_to_str(g.texture));
}

// =========================================================================
// SECTION 11 -- Corrupt input (4 checks)
// =========================================================================

fn test_corrupt_short_buffer() -> TestResult {
  var short_buf = bufs(4);
  var slot = bufs(32);
  let c = ktx2_corrupt_probe(&mut short_buf, &mut slot);
  let ok = c.status != 0;
  return assert(ok, "corrupt: 4-byte buffer rejected with a typed status (KTX " + int_to_str(c.status) + ")");
}

fn test_corrupt_bad_magic() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var generated = bufs(4096);
  var slot = bufs(128);
  let rt = ktx2_roundtrip(0, &mut image, &mut generated, &mut slot);
  match rt {
    Err(_rc) => { return assert(false, "corrupt magic: setup failed"); },
    Ok(_r) => {
      var bad = bufs(4096);
      var i: Int = 0;
      while i < generated.len() {
        bad[i] = generated[i];
        i = i + 1;
      }
      bad[0] = 0 as UInt8; /* break the identifier */
      var rec = bufs(32);
      let c = ktx2_corrupt_probe(&mut bad, &mut rec);
      let ok = c.status == 15 || c.status == 1 || c.status == 7;
      return assert(ok, "corrupt: broken identifier rejected (KTX " + int_to_str(c.status) + ", expected 15/1/7)");
    }
  }
}

fn test_corrupt_truncated() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var generated = bufs(4096);
  var slot = bufs(128);
  let rt = ktx2_roundtrip(0, &mut image, &mut generated, &mut slot);
  match rt {
    Err(_rc) => { return assert(false, "corrupt truncated: setup failed"); },
    Ok(r) => {
      var half = bufs(4096);
      let n = r.write_len / 2;
      var i: Int = 0;
      while i < n {
        half[i] = generated[i];
        i = i + 1;
      }
      var rec = bufs(32);
      var trunc = bufs(n);
      var j: Int = 0;
      while j < n {
        trunc[j] = half[j];
        j = j + 1;
      }
      let c = ktx2_corrupt_probe(&mut trunc, &mut rec);
      let ok = c.status != 0;
      return assert(ok, "corrupt: file truncated to half rejected (KTX " + int_to_str(c.status) + ")");
    }
  }
}

fn test_corrupt_version_byte() -> TestResult {
  var image = ktx2_test_image_rgb8();
  var generated = bufs(4096);
  var slot = bufs(128);
  let rt = ktx2_roundtrip(0, &mut image, &mut generated, &mut slot);
  match rt {
    Err(_rc) => { return assert(false, "corrupt version: setup failed"); },
    Ok(_r) => {
      var bad = bufs(4096);
      var i: Int = 0;
      while i < generated.len() {
        bad[i] = generated[i];
        i = i + 1;
      }
      bad[5] = 49 as UInt8; /* '2' -> '1': KTX1 magic, incompatible body */
      var rec = bufs(32);
      let c = ktx2_corrupt_probe(&mut bad, &mut rec);
      let ok = c.status != 0;
      return assert(ok, "corrupt: KTX1-identifier variant of a KTX2 body rejected (KTX " + int_to_str(c.status) + ")");
    }
  }
}

// =========================================================================
// Runner
// =========================================================================

fn main() -> Int {
  io.println("==================================================");
  io.println("  xiom.ktx2 conformance suite");
  io.println("  vendored: KTX-Software v4.4.2 (commit 4d6fc70e) -- libktx + Basis + ASTC");
  io.println("==================================================");

  var total: Int = 0;
  var failed: Int = 0;

  io.println("");
  io.println("-- SECTION 1: constants (4) --");
  let s10 = test_const_error_codes();                 total = total + 1; failed = failed + report(s10.passed, s10.name);
  let s11 = test_const_supercompression_and_flags();  total = total + 1; failed = failed + report(s11.passed, s11.name);
  let s12 = test_const_transcode_formats();           total = total + 1; failed = failed + report(s12.passed, s12.name);
  let s13 = test_const_df_and_vk_formats();           total = total + 1; failed = failed + report(s13.passed, s13.name);

  io.println("");
  io.println("-- SECTION 2: declared surface (4) --");
  let s20 = test_symbol_count();              total = total + 1; failed = failed + report(s20.passed, s20.name);
  let s21 = test_symbol_lookup_representative(); total = total + 1; failed = failed + report(s21.passed, s21.name);
  let s22 = test_symbol_names_roundtrip();    total = total + 1; failed = failed + report(s22.passed, s22.name);
  let s23 = test_symbol_lookup_absent();      total = total + 1; failed = failed + report(s23.passed, s23.name);

  io.println("");
  io.println("-- SECTION 3: KTX2 in-memory round trip (11) --");
  let s30 = test_ktx2_write_read();             total = total + 1; failed = failed + report(s30.passed, s30.name);
  let s31 = test_ktx2_level_bytes();            total = total + 1; failed = failed + report(s31.passed, s31.name);
  let s32 = test_ktx2_identifier();             total = total + 1; failed = failed + report(s32.passed, s32.name);
  let s33 = test_ktx2_info_fields();            total = total + 1; failed = failed + report(s33.passed, s33.name);
  let s34 = test_ktx2_row_pitch_and_iterate();  total = total + 1; failed = failed + report(s34.passed, s34.name);
  let s35 = test_ktx2_create_copy_and_color();  total = total + 1; failed = failed + report(s35.passed, s35.name);
  let s36 = test_ktx2_zstd_roundtrip();         total = total + 1; failed = failed + report(s36.passed, s36.name);
  let s37 = test_ktx2_zlib_roundtrip();         total = total + 1; failed = failed + report(s37.passed, s37.name);
  let s38 = test_lifecycle_primitives();        total = total + 1; failed = failed + report(s38.passed, s38.name);
  let s39 = test_deflated_load_zstd();          total = total + 1; failed = failed + report(s39.passed, s39.name);
  let s3a = test_deflated_load_zlib();          total = total + 1; failed = failed + report(s3a.passed, s3a.name);

  io.println("");
  io.println("-- SECTION 4: named file (2) --");
  let s40 = test_named_file_roundtrip();  total = total + 1; failed = failed + report(s40.passed, s40.name);
  let s41 = test_named_file_cleanup();    total = total + 1; failed = failed + report(s41.passed, s41.name);

  io.println("");
  io.println("-- SECTION 5: KTX1 + conversion (3) --");
  let s50 = test_ktx1_roundtrip();             total = total + 1; failed = failed + report(s50.passed, s50.name);
  let s51 = test_ktx1_gl_fields();             total = total + 1; failed = failed + report(s51.passed, s51.name);
  let s52 = test_ktx1_to_ktx2_conversion();    total = total + 1; failed = failed + report(s52.passed, s52.name);

  io.println("");
  io.println("-- SECTION 6: streams + stdio (3) --");
  let s60 = test_stream_ktx2_roundtrip();   total = total + 1; failed = failed + report(s60.passed, s60.name);
  let s61 = test_stream_stdio_roundtrip();  total = total + 1; failed = failed + report(s61.passed, s61.name);
  let s62 = test_stream_ktx1_paths();       total = total + 1; failed = failed + report(s62.passed, s62.name);

  io.println("");
  io.println("-- SECTION 7: Basis transcode (4) --");
  let s70 = test_basis_etc1s_to_bc1();      total = total + 1; failed = failed + report(s70.passed, s70.name);
  let s71 = test_basis_uastc_to_bc7();      total = total + 1; failed = failed + report(s71.passed, s71.name);
  let s72 = test_basis_etc1s_to_etc1();     total = total + 1; failed = failed + report(s72.passed, s72.name);
  let s73 = test_basis_etc1s_to_rgba32();   total = total + 1; failed = failed + report(s73.passed, s73.name);

  io.println("");
  io.println("-- SECTION 8: ASTC (2) --");
  let s80 = test_astc_compress();  total = total + 1; failed = failed + report(s80.passed, s80.name);
  let s81 = test_astc_decode();    total = total + 1; failed = failed + report(s81.passed, s81.name);

  io.println("");
  io.println("-- SECTION 9: hash list (2) --");
  let s90 = test_hashlist_core();                  total = total + 1; failed = failed + report(s90.passed, s90.name);
  let s91 = test_hashlist_serialize_and_lifecycle(); total = total + 1; failed = failed + report(s91.passed, s91.name);

  io.println("");
  io.println("-- SECTION 10: strings + GL (2) --");
  let sa0 = test_string_tables();  total = total + 1; failed = failed + report(sa0.passed, sa0.name);
  let sa1 = test_gl_probe();       total = total + 1; failed = failed + report(sa1.passed, sa1.name);

  io.println("");
  io.println("-- SECTION 11: corrupt input (4) --");
  let sb0 = test_corrupt_short_buffer();   total = total + 1; failed = failed + report(sb0.passed, sb0.name);
  let sb1 = test_corrupt_bad_magic();      total = total + 1; failed = failed + report(sb1.passed, sb1.name);
  let sb2 = test_corrupt_truncated();      total = total + 1; failed = failed + report(sb2.passed, sb2.name);
  let sb3 = test_corrupt_version_byte();   total = total + 1; failed = failed + report(sb3.passed, sb3.name);

  io.println("");
  io.println("==================================================");
  if failed == 0 {
    io.println("  ALL " + int_to_str(total) + " TESTS PASSED");
    io.println("  Vendored: libktx 4.4.2 + Basis transcoder/encoder + Arm ASTC + zstd");
    io.println("  Declared surface: 93/93 ktx.h functions linked");
    return 0;
  }
  io.println("  TESTS:  " + int_to_str(total));
  io.println("  FAILED: " + int_to_str(failed));
  return 1;
}
