// XIOM -- basis_universal Bindings
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level FFI declarations for basis_universal v2_50 (commit 9bebe167).
// basis_universal is the Basis Universal GPU texture codec: the transcoder
// converts KTX2 supercompressed payloads (ETC1S/UASTC/ASTC/XUASTC/XUBC7)
// to GPU formats (BC/ETC/PVRTC/ASTC/RGBA) at runtime, and the encoder emits
// those payloads at cook time.
//
// DECLARED SURFACE: 100% of the pinned public C API -- 81 functions:
//   - transcoder (encoder/basisu_wasm_transcoder_api.h): 68 `bt_*` functions
//   - encoder   (encoder/basisu_wasm_api.h):             13 `bu_*` functions
// plus every constant from encoder/basisu_wasm_api_common.h (BTF_*, TF_*,
// DECODE_FLAGS_*, BU_COMP_FLAGS_*, BU_QUALITY_*, BU_EFFORT_*).
//
// C++-only upstream areas excluded from the declared C surface (no C entry
// point exists at the pin; documented in PROVENANCE.md section 3):
//   - basist::ktx2_transcoder / basist::basisu_transcoder class APIs
//     (transcoder/basisu_transcoder.h): C++ classes behind the bt_* wrappers.
//   - basisu::basis_compressor / basisu::comp_params (encoder/basisu_comp.h):
//     C++ classes behind the bu_* wrappers.
//   - .basis (Basis v1) container transcoding: the bt_* C surface opens KTX2
//     only; the .basis class path (basisu_transcoder::transcode_image_level
//     on a v1 file) has no C entry at the pin.
//   - OpenCL acceleration, ASTC-input decompression in the encoder tool and
//     the DDS/EXR/TGA/PNG/QOI I/O helpers used by the CLI tool.
//
// Type mapping (fleet convention): uint64_t -> Int, uint32_t -> Int32,
// wasm_bool_t (= uint32_t) -> Int32, int -> Int32, float -> Float32.
//
// Buffer discipline (B-20/B-24): the raw `*_mem_ofs` parameters are memory
// handles; XIOM code MUST NOT pass an owned pointer through them directly.
// The `xbu_*` bridge below (src/basisu_bridge.cpp) is the only supported
// path for buffers, and it keeps every foreign pointer inside C.  XIOM reads
// results back byte-indexed from owned `Vec[UInt8]` slots only.

module xiom.basisu

// =========================================================================
// Constants -- encoder/basisu_wasm_api_common.h (verbatim values)
// =========================================================================

// Encoder quality/effort bounds.
pub const BU_QUALITY_MIN: Int32 = 1 as Int32;
pub const BU_QUALITY_MAX: Int32 = 100 as Int32;
pub const BU_EFFORT_MIN: Int32 = 0 as Int32;
pub const BU_EFFORT_MAX: Int32 = 10 as Int32;
pub const BU_EFFORT_SUPER_FAST: Int32 = 0 as Int32;
pub const BU_EFFORT_FAST: Int32 = 2 as Int32;
pub const BU_EFFORT_NORMAL: Int32 = 5 as Int32;
pub const BU_EFFORT_DEFAULT: Int32 = 2 as Int32;
pub const BU_EFFORT_SLOW: Int32 = 8 as Int32;
pub const BU_EFFORT_VERY_SLOW: Int32 = 10 as Int32;

// Encoder flags (BU_COMP_FLAGS_*).
pub const BU_COMP_FLAGS_NONE: Int32 = 0 as Int32;
pub const BU_COMP_FLAGS_USE_OPENCL: Int32 = 256 as Int32;
pub const BU_COMP_FLAGS_THREADED: Int32 = 512 as Int32;
pub const BU_COMP_FLAGS_DEBUG_OUTPUT: Int32 = 1024 as Int32;
pub const BU_COMP_FLAGS_KTX2_OUTPUT: Int32 = 2048 as Int32;
pub const BU_COMP_FLAGS_KTX2_UASTC_ZSTD: Int32 = 4096 as Int32;
pub const BU_COMP_FLAGS_SRGB: Int32 = 8192 as Int32;
pub const BU_COMP_FLAGS_GEN_MIPS_CLAMP: Int32 = 16384 as Int32;
pub const BU_COMP_FLAGS_GEN_MIPS_WRAP: Int32 = 32768 as Int32;
pub const BU_COMP_FLAGS_Y_FLIP: Int32 = 65536 as Int32;
pub const BU_COMP_FLAGS_PRINT_STATS: Int32 = 262144 as Int32;
pub const BU_COMP_FLAGS_PRINT_STATUS: Int32 = 524288 as Int32;
pub const BU_COMP_FLAGS_DEBUG_IMAGES: Int32 = 1048576 as Int32;
pub const BU_COMP_FLAGS_REC2020: Int32 = 2097152 as Int32;
pub const BU_COMP_FLAGS_VALIDATE_OUTPUT: Int32 = 4194304 as Int32;
pub const BU_COMP_FLAGS_XUASTC_LDR_FULL_ARITH: Int32 = 0 as Int32;
pub const BU_COMP_FLAGS_XUASTC_LDR_HYBRID: Int32 = 8388608 as Int32;
pub const BU_COMP_FLAGS_XUASTC_LDR_FULL_ZSTD: Int32 = 16777216 as Int32;
pub const BU_COMP_FLAGS_XUASTC_LDR_SYNTAX_SHIFT: Int32 = 23 as Int32;
pub const BU_COMP_FLAGS_XUASTC_LDR_SYNTAX_MASK: Int32 = 3 as Int32;
pub const BU_COMP_FLAGS_TEXTURE_TYPE_2D: Int32 = 0 as Int32;
pub const BU_COMP_FLAGS_TEXTURE_TYPE_2D_ARRAY: Int32 = 33554432 as Int32;
pub const BU_COMP_FLAGS_TEXTURE_TYPE_CUBEMAP_ARRAY: Int32 = 67108864 as Int32;
pub const BU_COMP_FLAGS_TEXTURE_TYPE_VIDEO_FRAMES: Int32 = 100663296 as Int32;
pub const BU_COMP_FLAGS_TEXTURE_TYPE_SHIFT: Int32 = 25 as Int32;
pub const BU_COMP_FLAGS_TEXTURE_TYPE_MASK: Int32 = 3 as Int32;
pub const BU_COMP_FLAGS_DISABLE_DEBLOCKING: Int32 = 134217728 as Int32;
pub const BU_COMP_FLAGS_FORCE_DEBLOCKING: Int32 = 268435456 as Int32;
pub const BU_COMP_FLAGS_XUBC7_BASE_ENCODER_BC7F: Int32 = 0 as Int32;
pub const BU_COMP_FLAGS_XUBC7_BASE_ENCODER_SHIFT: Int32 = 29 as Int32;
pub const BU_COMP_FLAGS_XUBC7_BASE_ENCODER_MASK: Int32 = 7 as Int32;
pub const BU_COMP_FLAGS_VERBOSE: Int32 = 787456 as Int32;

// basist::basis_tex_format -- .ktx2 payload modes (BTF_*).
pub const BTF_ETC1S: Int32 = 0 as Int32;
pub const BTF_UASTC_LDR_4X4: Int32 = 1 as Int32;
pub const BTF_UASTC_HDR_4X4: Int32 = 2 as Int32;
pub const BTF_ASTC_HDR_6X6: Int32 = 3 as Int32;
pub const BTF_UASTC_HDR_6X6: Int32 = 4 as Int32;
pub const BTF_XUASTC_LDR_4X4: Int32 = 5 as Int32;
pub const BTF_XUASTC_LDR_5X4: Int32 = 6 as Int32;
pub const BTF_XUASTC_LDR_5X5: Int32 = 7 as Int32;
pub const BTF_XUASTC_LDR_6X5: Int32 = 8 as Int32;
pub const BTF_XUASTC_LDR_6X6: Int32 = 9 as Int32;
pub const BTF_XUASTC_LDR_8X5: Int32 = 10 as Int32;
pub const BTF_XUASTC_LDR_8X6: Int32 = 11 as Int32;
pub const BTF_XUASTC_LDR_10X5: Int32 = 12 as Int32;
pub const BTF_XUASTC_LDR_10X6: Int32 = 13 as Int32;
pub const BTF_XUASTC_LDR_8X8: Int32 = 14 as Int32;
pub const BTF_XUASTC_LDR_10X8: Int32 = 15 as Int32;
pub const BTF_XUASTC_LDR_10X10: Int32 = 16 as Int32;
pub const BTF_XUASTC_LDR_12X10: Int32 = 17 as Int32;
pub const BTF_XUASTC_LDR_12X12: Int32 = 18 as Int32;
pub const BTF_ASTC_LDR_4X4: Int32 = 19 as Int32;
pub const BTF_ASTC_LDR_5X4: Int32 = 20 as Int32;
pub const BTF_ASTC_LDR_5X5: Int32 = 21 as Int32;
pub const BTF_ASTC_LDR_6X5: Int32 = 22 as Int32;
pub const BTF_ASTC_LDR_6X6: Int32 = 23 as Int32;
pub const BTF_ASTC_LDR_8X5: Int32 = 24 as Int32;
pub const BTF_ASTC_LDR_8X6: Int32 = 25 as Int32;
pub const BTF_ASTC_LDR_10X5: Int32 = 26 as Int32;
pub const BTF_ASTC_LDR_10X6: Int32 = 27 as Int32;
pub const BTF_ASTC_LDR_8X8: Int32 = 28 as Int32;
pub const BTF_ASTC_LDR_10X8: Int32 = 29 as Int32;
pub const BTF_ASTC_LDR_10X10: Int32 = 30 as Int32;
pub const BTF_ASTC_LDR_12X10: Int32 = 31 as Int32;
pub const BTF_ASTC_LDR_12X12: Int32 = 32 as Int32;
pub const BTF_XUBC7: Int32 = 33 as Int32;
pub const BTF_TOTAL_FORMATS: Int32 = 34 as Int32;

// basist::transcoder_texture_format -- transcode targets (TF_*).
pub const TF_ETC1_RGB: Int32 = 0 as Int32;
pub const TF_ETC2_RGBA: Int32 = 1 as Int32;
pub const TF_BC1_RGB: Int32 = 2 as Int32;
pub const TF_BC3_RGBA: Int32 = 3 as Int32;
pub const TF_BC4_R: Int32 = 4 as Int32;
pub const TF_BC5_RG: Int32 = 5 as Int32;
pub const TF_BC7_RGBA: Int32 = 6 as Int32;
pub const TF_PVRTC1_4_RGB: Int32 = 8 as Int32;
pub const TF_PVRTC1_4_RGBA: Int32 = 9 as Int32;
pub const TF_ASTC_LDR_4X4_RGBA: Int32 = 10 as Int32;
pub const TF_ATC_RGB: Int32 = 11 as Int32;
pub const TF_ATC_RGBA: Int32 = 12 as Int32;
pub const TF_RGBA32: Int32 = 13 as Int32;
pub const TF_RGB565: Int32 = 14 as Int32;
pub const TF_BGR565: Int32 = 15 as Int32;
pub const TF_RGBA4444: Int32 = 16 as Int32;
pub const TF_FXT1_RGB: Int32 = 17 as Int32;
pub const TF_PVRTC2_4_RGB: Int32 = 18 as Int32;
pub const TF_PVRTC2_4_RGBA: Int32 = 19 as Int32;
pub const TF_ETC2_EAC_R11: Int32 = 20 as Int32;
pub const TF_ETC2_EAC_RG11: Int32 = 21 as Int32;
pub const TF_BC6H: Int32 = 22 as Int32;
pub const TF_ASTC_HDR_4X4_RGBA: Int32 = 23 as Int32;
pub const TF_RGB_HALF: Int32 = 24 as Int32;
pub const TF_RGBA_HALF: Int32 = 25 as Int32;
pub const TF_RGB_9E5: Int32 = 26 as Int32;
pub const TF_ASTC_HDR_6X6_RGBA: Int32 = 27 as Int32;
pub const TF_ASTC_LDR_5X4_RGBA: Int32 = 28 as Int32;
pub const TF_ASTC_LDR_5X5_RGBA: Int32 = 29 as Int32;
pub const TF_ASTC_LDR_6X5_RGBA: Int32 = 30 as Int32;
pub const TF_ASTC_LDR_6X6_RGBA: Int32 = 31 as Int32;
pub const TF_ASTC_LDR_8X5_RGBA: Int32 = 32 as Int32;
pub const TF_ASTC_LDR_8X6_RGBA: Int32 = 33 as Int32;
pub const TF_ASTC_LDR_10X5_RGBA: Int32 = 34 as Int32;
pub const TF_ASTC_LDR_10X6_RGBA: Int32 = 35 as Int32;
pub const TF_ASTC_LDR_8X8_RGBA: Int32 = 36 as Int32;
pub const TF_ASTC_LDR_10X8_RGBA: Int32 = 37 as Int32;
pub const TF_ASTC_LDR_10X10_RGBA: Int32 = 38 as Int32;
pub const TF_ASTC_LDR_12X10_RGBA: Int32 = 39 as Int32;
pub const TF_ASTC_LDR_12X12_RGBA: Int32 = 40 as Int32;
pub const TF_TOTAL_TEXTURE_FORMATS: Int32 = 41 as Int32;

// basist::basisu_decode_flags -- transcode decode flags (logically OR'd).
pub const DECODE_FLAGS_PVRTC_DECODE_TO_NEXT_POW2: Int32 = 2 as Int32;
pub const DECODE_FLAGS_TRANSCODE_ALPHA_DATA_TO_OPAQUE_FORMATS: Int32 = 4 as Int32;
pub const DECODE_FLAGS_BC1_FORBID_THREE_COLOR_BLOCKS: Int32 = 8 as Int32;
pub const DECODE_FLAGS_OUTPUT_HAS_ALPHA_INDICES: Int32 = 16 as Int32;
pub const DECODE_FLAGS_HIGH_QUALITY: Int32 = 32 as Int32;
pub const DECODE_FLAGS_NO_ETC1S_CHROMA_FILTERING: Int32 = 64 as Int32;
pub const DECODE_FLAGS_NO_DEBLOCK_FILTERING: Int32 = 128 as Int32;
pub const DECODE_FLAGS_FORCE_DEBLOCK_FILTERING: Int32 = 512 as Int32;
pub const DECODE_FLAGS_XUASTC_LDR_DISABLE_FAST_BC7_TRANSCODING: Int32 = 1024 as Int32;

// =========================================================================
// FFI: extern "C" declarations -- full pinned public C API surface
// =========================================================================

extern "C" {
  // --- Transcoder C API: encoder/basisu_wasm_transcoder_api.h (68) ---

  // High level
  fn bt_get_version() -> Int32;
  fn bt_enable_debug_printf(flag: Int32);
  fn bt_init();
  fn bt_alloc(size: Int) -> Int;
  fn bt_free(mem_ofs: Int);

  // basis_tex_format helpers
  fn bt_basis_tex_format_is_xuastc_ldr(basis_tex_fmt_u32: Int32) -> Int32;
  fn bt_basis_tex_format_is_astc_ldr(basis_tex_fmt_u32: Int32) -> Int32;
  fn bt_basis_tex_format_is_xubc7(basis_tex_fmt_u32: Int32) -> Int32;
  fn bt_basis_tex_format_get_block_width(basis_tex_fmt_u32: Int32) -> Int32;
  fn bt_basis_tex_format_get_block_height(basis_tex_fmt_u32: Int32) -> Int32;
  fn bt_basis_tex_format_is_hdr(basis_tex_format_u32: Int32) -> Int32;
  fn bt_basis_tex_format_is_ldr(basis_tex_format_u32: Int32) -> Int32;

  // transcoder_texture_format helpers
  fn bt_basis_get_bytes_per_block_or_pixel(transcoder_texture_format_u32: Int32) -> Int32;
  fn bt_basis_transcoder_format_has_alpha(transcoder_texture_format_u32: Int32) -> Int32;
  fn bt_basis_transcoder_format_is_hdr(transcoder_texture_format_u32: Int32) -> Int32;
  fn bt_basis_transcoder_format_is_ldr(transcoder_texture_format_u32: Int32) -> Int32;
  fn bt_basis_transcoder_texture_format_is_astc(transcoder_texture_format_u32: Int32) -> Int32;
  fn bt_basis_transcoder_format_is_uncompressed(transcoder_texture_format_u32: Int32) -> Int32;
  fn bt_basis_get_uncompressed_bytes_per_pixel(transcoder_texture_format_u32: Int32) -> Int32;
  fn bt_basis_get_block_width(transcoder_texture_format_u32: Int32) -> Int32;
  fn bt_basis_get_block_height(transcoder_texture_format_u32: Int32) -> Int32;
  fn bt_basis_get_transcoder_texture_format_from_basis_tex_format(basis_tex_format_u32: Int32) -> Int32;
  fn bt_basis_is_format_supported(transcoder_texture_format_u32: Int32, basis_tex_format_u32: Int32) -> Int32;
  fn bt_basis_compute_transcoded_image_size_in_bytes(transcoder_texture_format_u32: Int32, orig_width: Int32, orig_height: Int32) -> Int32;

  // KTX2 lifecycle and metadata
  fn bt_ktx2_open(data_mem_ofs: Int, data_len: Int32) -> Int;
  fn bt_ktx2_close(handle: Int);
  fn bt_ktx2_get_width(handle: Int) -> Int32;
  fn bt_ktx2_get_height(handle: Int) -> Int32;
  fn bt_ktx2_get_levels(handle: Int) -> Int32;
  fn bt_ktx2_get_faces(handle: Int) -> Int32;
  fn bt_ktx2_get_layers(handle: Int) -> Int32;
  fn bt_ktx2_get_basis_tex_format(handle: Int) -> Int32;
  fn bt_ktx2_is_etc1s(handle: Int) -> Int32;
  fn bt_ktx2_is_uastc_ldr_4x4(handle: Int) -> Int32;
  fn bt_ktx2_is_hdr(handle: Int) -> Int32;
  fn bt_ktx2_is_hdr_4x4(handle: Int) -> Int32;
  fn bt_ktx2_is_hdr_6x6(handle: Int) -> Int32;
  fn bt_ktx2_is_ldr(handle: Int) -> Int32;
  fn bt_ktx2_is_astc_ldr(handle: Int) -> Int32;
  fn bt_ktx2_is_xuastc_ldr(handle: Int) -> Int32;
  fn bt_ktx2_is_xubc7(handle: Int) -> Int32;
  fn bt_ktx2_get_block_width(handle: Int) -> Int32;
  fn bt_ktx2_get_block_height(handle: Int) -> Int32;
  fn bt_ktx2_get_deblocking_filter_index(handle: Int) -> Int32;
  fn bt_ktx2_has_alpha(handle: Int) -> Int32;
  fn bt_ktx2_get_dfd_color_model(handle: Int) -> Int32;
  fn bt_ktx2_get_dfd_color_primaries(handle: Int) -> Int32;
  fn bt_ktx2_get_dfd_transfer_func(handle: Int) -> Int32;
  fn bt_ktx2_is_srgb(handle: Int) -> Int32;
  fn bt_ktx2_get_dfd_flags(handle: Int) -> Int32;
  fn bt_ktx2_get_dfd_total_samples(handle: Int) -> Int32;
  fn bt_ktx2_get_dfd_channel_id0(handle: Int) -> Int32;
  fn bt_ktx2_get_dfd_channel_id1(handle: Int) -> Int32;
  fn bt_ktx2_is_video(handle: Int) -> Int32;
  fn bt_ktx2_get_ldr_hdr_upconversion_nit_multiplier(handle: Int) -> Float32;

  // KTX2 per-level metadata
  fn bt_ktx2_get_level_orig_width(handle: Int, level_index: Int32, layer_index: Int32, face_index: Int32) -> Int32;
  fn bt_ktx2_get_level_orig_height(handle: Int, level_index: Int32, layer_index: Int32, face_index: Int32) -> Int32;
  fn bt_ktx2_get_level_actual_width(handle: Int, level_index: Int32, layer_index: Int32, face_index: Int32) -> Int32;
  fn bt_ktx2_get_level_actual_height(handle: Int, level_index: Int32, layer_index: Int32, face_index: Int32) -> Int32;
  fn bt_ktx2_get_level_num_blocks_x(handle: Int, level_index: Int32, layer_index: Int32, face_index: Int32) -> Int32;
  fn bt_ktx2_get_level_num_blocks_y(handle: Int, level_index: Int32, layer_index: Int32, face_index: Int32) -> Int32;
  fn bt_ktx2_get_level_total_blocks(handle: Int, level_index: Int32, layer_index: Int32, face_index: Int32) -> Int32;
  fn bt_ktx2_get_level_alpha_flag(handle: Int, level_index: Int32, layer_index: Int32, face_index: Int32) -> Int32;
  fn bt_ktx2_get_level_iframe_flag(handle: Int, level_index: Int32, layer_index: Int32, face_index: Int32) -> Int32;

  // KTX2 transcoding
  fn bt_ktx2_start_transcoding(handle: Int) -> Int32;
  fn bt_ktx2_create_transcode_state() -> Int;
  fn bt_ktx2_destroy_transcode_state(handle: Int);
  fn bt_ktx2_transcode_image_level(ktx2_handle: Int, level_index: Int32, layer_index: Int32, face_index: Int32, output_block_mem_ofs: Int, output_blocks_buf_size_in_blocks_or_pixels: Int32, transcoder_texture_format_u32: Int32, decode_flags: Int32, output_row_pitch_in_blocks_or_pixels: Int32, output_rows_in_pixels: Int32, channel0: Int32, channel1: Int32, state_handle: Int) -> Int32;

  // --- Encoder C API: encoder/basisu_wasm_api.h (13) ---

  fn bu_get_version() -> Int32;
  fn bu_enable_debug_printf(flag: Int32);
  fn bu_init();
  fn bu_alloc(size: Int) -> Int;
  fn bu_free(ofs: Int);
  fn bu_new_comp_params() -> Int;
  fn bu_delete_comp_params(params_ofs: Int) -> Int32;
  fn bu_comp_params_get_comp_data_size(params_ofs: Int) -> Int;
  fn bu_comp_params_get_comp_data_ofs(params_ofs: Int) -> Int;
  fn bu_comp_params_clear(params_ofs: Int) -> Int32;
  fn bu_comp_params_set_image_rgba32(params_ofs: Int, image_index: Int32, img_data_ofs: Int, width: Int32, height: Int32, pitch_in_bytes: Int32) -> Int32;
  fn bu_comp_params_set_image_float_rgba(params_ofs: Int, image_index: Int32, img_data_ofs: Int, width: Int32, height: Int32, pitch_in_bytes: Int32) -> Int32;
  fn bu_compress_texture(params_ofs: Int, desired_basis_tex_format: Int32, quality_level: Int32, effort_level: Int32, flags_and_quality: Int, low_level_uastc_rdo_or_dct_quality: Float32) -> Int32;
}

// =========================================================================
// Bridge surface (src/basisu_bridge.cpp) -- the only buffer-crossing path
// =========================================================================

extern "C" {
  fn xbu_alloc_probe(o_bt_ok: *UInt8, o_bu_ok: *UInt8) -> Int32;
  fn xbu_encode_probe(img: *UInt8, w: Int32, h: Int32, basis_fmt: Int32, flags: Int32, quality: Int32, effort: Int32, out: *UInt8, out_cap: Int32, o_size: *UInt8, o_copy_ok: *UInt8) -> Int32;
  fn xbu_info_probe(ktx2: *UInt8, len: Int32, slots: *UInt8, slots_bytes: Int32) -> Int32;
  fn xbu_level_probe(ktx2: *UInt8, len: Int32, level: Int32, slots: *UInt8, slots_bytes: Int32) -> Int32;
  fn xbu_transcode_probe(ktx2: *UInt8, len: Int32, level: Int32, fmt: Int32, out: *UInt8, out_cap: Int32, o_size: *UInt8, o_flags: *UInt8) -> Int32;
  fn xbu_open_probe(data: *UInt8, len: Int32) -> Int32;
}

// =========================================================================
// Owned-slot helpers (4-byte little-endian reads; B-11/B-16/B-17)
// =========================================================================

fn basisu_slot4() -> Vec[UInt8]
  requires: true
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 4 {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn basisu_slots(n: Int) -> Vec[UInt8]
  requires: n > 0
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n * 4 {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn basisu_read_u32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let b0 = buf[off] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

fn basisu_i2s(n: Int) -> Str
  requires: n >= 0
{
  if n == 0 { return "0"; }
  var val = n;
  var buf = "";
  while val > 0 {
    let digit = val % 10;
    val = val / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  return buf;
}

// =========================================================================
// Public flat result shapes (B-26: no Result[Option[T]])
// =========================================================================

pub type BasisuVersions = {
  transcoder_lib: Int;
  encoder_lib: Int;
}

pub type BasisuAllocProbe = {
  transcoder_ok: Bool;
  encoder_ok: Bool;
}

pub type BasisuFormatReport = {
  bytes_per_block_rgba32: Int;
  bytes_per_block_bc1: Int;
  bytes_per_block_astc4: Int;
  uncompressed_bpp_rgba32: Int;
  has_alpha_bc1: Bool;
  has_alpha_bc3: Bool;
  is_astc_4x4: Bool;
  is_astc_bc1: Bool;
  is_hdr_bc6h: Bool;
  is_ldr_bc1: Bool;
  is_uncompressed_rgba32: Bool;
  size_bc1_32x32: Int;
  size_astc4_32x32: Int;
  fmt_from_uastc: Int;
  fmt_from_etc1s: Int;
  supp_bc1_uastc: Bool;
  supp_bc3_uastc: Bool;
  supp_astc_uastc: Bool;
  supp_rgba32_uastc: Bool;
  block_w_bc1: Int;
  block_h_bc1: Int;
  basis_xuastc_8x5: Bool;
  basis_astc_4x4: Bool;
  basis_hdr_6x6: Bool;
  basis_ldr_uastc: Bool;
  basis_xubc7: Bool;
  basis_block_w_xuastc_8x5: Int;
  basis_block_h_xuastc_8x5: Int;
}

pub type BasisuKtx2Info = {
  open: Bool;
  width: Int;
  height: Int;
  levels: Int;
  faces: Int;
  layers: Int;
  basis_tex_format: Int;
  is_etc1s: Bool;
  is_uastc_ldr_4x4: Bool;
  is_ldr: Bool;
  is_hdr: Bool;
  is_hdr_4x4: Bool;
  is_hdr_6x6: Bool;
  is_astc_ldr: Bool;
  is_xuastc_ldr: Bool;
  is_xubc7: Bool;
  is_srgb: Bool;
  has_alpha: Bool;
  is_video: Bool;
  block_width: Int;
  block_height: Int;
  deblocking_filter_index: Int;
  dfd_color_model: Int;
  dfd_color_primaries: Int;
  dfd_transfer_func: Int;
  dfd_flags: Int;
  dfd_total_samples: Int;
  dfd_channel_id0: Int;
  dfd_channel_id1: Int;
  upconversion_nit_milli: Int;
  start_transcoding_ok: Bool;
}

pub type BasisuLevelInfo = {
  ok: Bool;
  orig_width: Int;
  orig_height: Int;
  actual_width: Int;
  actual_height: Int;
  blocks_x: Int;
  blocks_y: Int;
  total_blocks: Int;
  alpha_flag: Bool;
  iframe_flag: Bool;
}

pub type BasisuEncodeResult = {
  size: Int;
  copy_ok: Bool;
}

pub type BasisuTranscodeResult = {
  size: Int;
  opened: Bool;
  started: Bool;
  transcoded: Bool;
}

// =========================================================================
// Safe API
// =========================================================================

/// One-time library init for encoder + transcoder; also disables the
/// upstream debug printf (matches the canonical example_capi.c sequence).
/// Idempotent upstream (g_library_initialized guard). Complexity: O(1).
pub fn basisu_init()
  requires: true
{
  unsafe {
    bu_init();
    bt_init();
    bt_enable_debug_printf(0 as Int32);
    bu_enable_debug_printf(0 as Int32);
  }
}

/// Packed library versions. v2_50 -> 250 for both transcoder and encoder.
/// Complexity: O(1).
pub fn basisu_versions() -> BasisuVersions
  requires: true
{
  unsafe {
    return BasisuVersions{
      transcoder_lib: bt_get_version() as Int,
      encoder_lib: bu_get_version() as Int
    };
  }
}

/// bt_alloc/bu_alloc -> write -> read -> free round trip (all inside C; the
/// C-owned regions never reach XIOM). Complexity: O(1).
pub fn basisu_alloc_probe() -> BasisuAllocProbe
  requires: true
{
  unsafe {
    var ft = basisu_slot4();
    var fe = basisu_slot4();
    xbu_alloc_probe(ft.as_mut_ptr(), fe.as_mut_ptr());
    return BasisuAllocProbe{
      transcoder_ok: basisu_read_u32(&ft, 0) != 0,
      encoder_ok: basisu_read_u32(&fe, 0) != 0
    };
  }
}

/// Exercise every basis_tex_format / transcoder_texture_format helper on
/// fixed reference formats. Infallible scalar calls (no buffers).
/// Complexity: O(1).
pub fn basisu_format_report() -> BasisuFormatReport
  requires: true
{
  unsafe {
    return BasisuFormatReport{
      bytes_per_block_rgba32: bt_basis_get_bytes_per_block_or_pixel(TF_RGBA32) as Int,
      bytes_per_block_bc1: bt_basis_get_bytes_per_block_or_pixel(TF_BC1_RGB) as Int,
      bytes_per_block_astc4: bt_basis_get_bytes_per_block_or_pixel(TF_ASTC_LDR_4X4_RGBA) as Int,
      uncompressed_bpp_rgba32: bt_basis_get_uncompressed_bytes_per_pixel(TF_RGBA32) as Int,
      has_alpha_bc1: bt_basis_transcoder_format_has_alpha(TF_BC1_RGB) != 0,
      has_alpha_bc3: bt_basis_transcoder_format_has_alpha(TF_BC3_RGBA) != 0,
      is_astc_4x4: bt_basis_transcoder_texture_format_is_astc(TF_ASTC_LDR_4X4_RGBA) != 0,
      is_astc_bc1: bt_basis_transcoder_texture_format_is_astc(TF_BC1_RGB) != 0,
      is_hdr_bc6h: bt_basis_transcoder_format_is_hdr(TF_BC6H) != 0,
      is_ldr_bc1: bt_basis_transcoder_format_is_ldr(TF_BC1_RGB) != 0,
      is_uncompressed_rgba32: bt_basis_transcoder_format_is_uncompressed(TF_RGBA32) != 0,
      size_bc1_32x32: bt_basis_compute_transcoded_image_size_in_bytes(TF_BC1_RGB, 32 as Int32, 32 as Int32) as Int,
      size_astc4_32x32: bt_basis_compute_transcoded_image_size_in_bytes(TF_ASTC_LDR_4X4_RGBA, 32 as Int32, 32 as Int32) as Int,
      fmt_from_uastc: bt_basis_get_transcoder_texture_format_from_basis_tex_format(BTF_UASTC_LDR_4X4) as Int,
      fmt_from_etc1s: bt_basis_get_transcoder_texture_format_from_basis_tex_format(BTF_ETC1S) as Int,
      supp_bc1_uastc: bt_basis_is_format_supported(TF_BC1_RGB, BTF_UASTC_LDR_4X4) != 0,
      supp_bc3_uastc: bt_basis_is_format_supported(TF_BC3_RGBA, BTF_UASTC_LDR_4X4) != 0,
      supp_astc_uastc: bt_basis_is_format_supported(TF_ASTC_LDR_4X4_RGBA, BTF_UASTC_LDR_4X4) != 0,
      supp_rgba32_uastc: bt_basis_is_format_supported(TF_RGBA32, BTF_UASTC_LDR_4X4) != 0,
      block_w_bc1: bt_basis_get_block_width(TF_BC1_RGB) as Int,
      block_h_bc1: bt_basis_get_block_height(TF_BC1_RGB) as Int,
      basis_xuastc_8x5: bt_basis_tex_format_is_xuastc_ldr(BTF_XUASTC_LDR_8X5) != 0,
      basis_astc_4x4: bt_basis_tex_format_is_astc_ldr(BTF_ASTC_LDR_4X4) != 0,
      basis_hdr_6x6: bt_basis_tex_format_is_hdr(BTF_ASTC_HDR_6X6) != 0,
      basis_ldr_uastc: bt_basis_tex_format_is_ldr(BTF_UASTC_LDR_4X4) != 0,
      basis_xubc7: bt_basis_tex_format_is_xubc7(BTF_XUBC7) != 0,
      basis_block_w_xuastc_8x5: bt_basis_tex_format_get_block_width(BTF_XUASTC_LDR_8X5) as Int,
      basis_block_h_xuastc_8x5: bt_basis_tex_format_get_block_height(BTF_XUASTC_LDR_8X5) as Int
    };
  }
}

/// Encode an owned RGBA32 image (w*h*4 bytes) to a KTX2 payload via the bu_*
/// C API into `out`. Returns the payload byte length. Ok.error is a typed
/// message for encoder failures. Complexity: O(pixels) + encode cost.
pub fn basisu_encode_ktx2(img: &mut Vec[UInt8], w: Int, h: Int, basis_fmt: Int32, flags: Int32, quality: Int32, effort: Int32, out: &mut Vec[UInt8]) -> Result[BasisuEncodeResult, Str]
  requires: w > 0
  requires: h > 0
  requires: img.len() >= w * h * 4
  requires: out.len() > 0
{
  unsafe {
    var fs = basisu_slot4();
    var fc = basisu_slot4();
    let rc = xbu_encode_probe(img.as_mut_ptr(), w as Int32, h as Int32, basis_fmt, flags, quality, effort, out.as_mut_ptr(), out.len() as Int32, fs.as_mut_ptr(), fc.as_mut_ptr()) as Int;
    if rc == 1 { return Err("basisu: bu_new_comp_params failed"); }
    if rc == 2 { return Err("basisu: bu_comp_params_set_image_rgba32 rejected the image"); }
    if rc == 3 { return Err("basisu: bu_compress_texture failed (format=" + basisu_i2s(basis_fmt as Int) + ")"); }
    if rc == 4 { return Err("basisu: compressor returned an empty payload"); }
    if rc == 5 { return Err("basisu: output buffer too small"); }
    if rc == 6 { return Err("basisu: invalid encode arguments"); }
    if rc != 0 { return Err("basisu: encode bridge rc=" + basisu_i2s(rc)); }
    let size = basisu_read_u32(&fs, 0);
    let copied = basisu_read_u32(&fc, 0) != 0;
    if !copied { return Err("basisu: compressed payload copy failed"); }
    return Ok(BasisuEncodeResult{ size: size, copy_ok: copied });
  }
}

/// KTX2 metadata for an owned payload prefix of `len` bytes. Err states:
/// invalid/truncated payload (open failed) or bridge error.
/// Complexity: O(1).
pub fn basisu_ktx2_info(data: &mut Vec[UInt8], len: Int) -> Result[BasisuKtx2Info, Str]
  requires: len >= 0
  requires: data.len() >= len
{
  unsafe {
    var s = basisu_slots(32);
    let rc = xbu_info_probe(data.as_mut_ptr(), len as Int32, s.as_mut_ptr(), 128 as Int32) as Int;
    if rc != 0 { return Err("basisu: info bridge rc=" + basisu_i2s(rc)); }
    let open = basisu_read_u32(&s, 0) != 0;
    if !open { return Err("basisu: invalid or truncated KTX2 payload"); }
    return Ok(BasisuKtx2Info{
      open: true,
      width: basisu_read_u32(&s, 4),
      height: basisu_read_u32(&s, 8),
      levels: basisu_read_u32(&s, 12),
      faces: basisu_read_u32(&s, 16),
      layers: basisu_read_u32(&s, 20),
      basis_tex_format: basisu_read_u32(&s, 24),
      is_etc1s: basisu_read_u32(&s, 28) != 0,
      is_uastc_ldr_4x4: basisu_read_u32(&s, 32) != 0,
      is_ldr: basisu_read_u32(&s, 36) != 0,
      is_hdr: basisu_read_u32(&s, 40) != 0,
      is_hdr_4x4: basisu_read_u32(&s, 44) != 0,
      is_hdr_6x6: basisu_read_u32(&s, 48) != 0,
      is_astc_ldr: basisu_read_u32(&s, 52) != 0,
      is_xuastc_ldr: basisu_read_u32(&s, 56) != 0,
      is_xubc7: basisu_read_u32(&s, 60) != 0,
      is_srgb: basisu_read_u32(&s, 64) != 0,
      has_alpha: basisu_read_u32(&s, 68) != 0,
      is_video: basisu_read_u32(&s, 72) != 0,
      block_width: basisu_read_u32(&s, 76),
      block_height: basisu_read_u32(&s, 80),
      deblocking_filter_index: basisu_read_u32(&s, 84),
      dfd_color_model: basisu_read_u32(&s, 88),
      dfd_color_primaries: basisu_read_u32(&s, 92),
      dfd_transfer_func: basisu_read_u32(&s, 96),
      dfd_flags: basisu_read_u32(&s, 100),
      dfd_total_samples: basisu_read_u32(&s, 104),
      dfd_channel_id0: basisu_read_u32(&s, 108),
      dfd_channel_id1: basisu_read_u32(&s, 112),
      upconversion_nit_milli: basisu_read_u32(&s, 116),
      start_transcoding_ok: basisu_read_u32(&s, 120) != 0
    });
  }
}

/// Per-level metadata (orig/actual dims, block counts, flags) for a KTX2
/// payload prefix. Err on invalid payload or start_transcoding failure.
/// Complexity: O(1).
pub fn basisu_ktx2_level_info(data: &mut Vec[UInt8], len: Int, level: Int) -> Result[BasisuLevelInfo, Str]
  requires: len >= 0
  requires: level >= 0
  requires: data.len() >= len
{
  unsafe {
    var s = basisu_slots(10);
    let rc = xbu_level_probe(data.as_mut_ptr(), len as Int32, level as Int32, s.as_mut_ptr(), 40 as Int32) as Int;
    if rc == 1 { return Err("basisu: invalid or truncated KTX2 payload"); }
    if rc == 3 { return Err("basisu: start_transcoding failed"); }
    if rc != 0 { return Err("basisu: level bridge rc=" + basisu_i2s(rc)); }
    let ok = basisu_read_u32(&s, 0) != 0;
    if !ok { return Err("basisu: level " + basisu_i2s(level) + " info unavailable"); }
    return Ok(BasisuLevelInfo{
      ok: true,
      orig_width: basisu_read_u32(&s, 4),
      orig_height: basisu_read_u32(&s, 8),
      actual_width: basisu_read_u32(&s, 12),
      actual_height: basisu_read_u32(&s, 16),
      blocks_x: basisu_read_u32(&s, 20),
      blocks_y: basisu_read_u32(&s, 24),
      total_blocks: basisu_read_u32(&s, 28),
      alpha_flag: basisu_read_u32(&s, 32) != 0,
      iframe_flag: basisu_read_u32(&s, 36) != 0
    });
  }
}

/// Transcode one level of an owned KTX2 payload prefix to `fmt` into the
/// owned `out` buffer (caller sizes it; Err reports the required size).
/// Complexity: O(blocks) + transcode cost.
pub fn basisu_transcode(data: &mut Vec[UInt8], len: Int, level: Int, fmt: Int32, out: &mut Vec[UInt8]) -> Result[BasisuTranscodeResult, Str]
  requires: len >= 0
  requires: level >= 0
  requires: data.len() >= len
  requires: out.len() > 0
{
  unsafe {
    var fs = basisu_slot4();
    var ff = basisu_slot4();
    let rc = xbu_transcode_probe(data.as_mut_ptr(), len as Int32, level as Int32, fmt, out.as_mut_ptr(), out.len() as Int32, fs.as_mut_ptr(), ff.as_mut_ptr()) as Int;
    if rc == 1 { return Err("basisu: invalid or truncated KTX2 payload"); }
    if rc == 2 { return Err("basisu: transcode bridge rejected its arguments"); }
    if rc == 3 {
      let need = basisu_read_u32(&fs, 0);
      return Err("basisu: output buffer too small (need " + basisu_i2s(need) + " bytes)");
    }
    if rc == 4 { return Err("basisu: start_transcoding failed"); }
    if rc != 0 { return Err("basisu: transcode bridge rc=" + basisu_i2s(rc)); }
    let flags = basisu_read_u32(&ff, 0);
    let transcoded = (flags & 4) != 0;
    if !transcoded {
      if (flags & 2) == 0 { return Err("basisu: start_transcoding failed"); }
      return Err("basisu: transcode_image_level failed");
    }
    return Ok(BasisuTranscodeResult{
      size: basisu_read_u32(&fs, 0),
      opened: (flags & 1) != 0,
      started: (flags & 2) != 0,
      transcoded: transcoded
    });
  }
}

/// Open/close probe over an arbitrary owned prefix: Bool = a KTX2 payload
/// was accepted (then closed). Corrupt input returns false.
/// Complexity: O(1).
pub fn basisu_can_open(data: &mut Vec[UInt8], len: Int) -> Bool
  requires: len >= 0
  requires: data.len() >= len
{
  return unsafe { xbu_open_probe(data.as_mut_ptr(), len as Int32) != 0 };
}
