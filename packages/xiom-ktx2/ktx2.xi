// XIOM -- xiom.ktx2 Bindings
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// KTX2 texture container + Basis Universal transcode bindings over the
// vendored libktx (KTX-Software v4.4.2, commit 4d6fc70e). The declared
// surface is the public ktx.h API (create/write/read KTX2 and KTX1
// textures, Basis/ASTC encode and transcode, hash-list metadata, info
// printers); tools/oracle_ktx.py generates and verifies the inventory
// (93 functions, ktx.h + KHR/khr_df.h constants).
//
// SAFE BOUNDARY (G5): `extern "C"` is confined to this module. Runtime
// access goes through the x2_* bridge (src/ktx2_bridge.c): handles live in
// caller-owned 8-byte slots, every out-parameter is a caller-owned byte
// slot read little-endian (B-11/B-16/B-17), no XIOM code casts handles to
// pointers (B-25), no reads through foreign pointers (B-20), and fallible
// results are flat structs or Result[_, Str] -- never Result[Option[_]]
// (B-26).

module xiom.ktx2

// >>> GENERATED CONSTS (tools/oracle_ktx.py emit-consts) -- do not edit by hand
// ---- (anonymous) ----
pub const KTX_TEXTURE_CREATE_NO_STORAGE: Int32 = 0 as Int32;
pub const KTX_TEXTURE_CREATE_ALLOC_STORAGE: Int32 = 1 as Int32;

// ---- _khr_df_flags_e ----
pub const KHR_DF_FLAG_ALPHA_STRAIGHT: Int32 = 0 as Int32;
pub const KHR_DF_FLAG_ALPHA_PREMULTIPLIED: Int32 = 1 as Int32;

// ---- _khr_df_khr_descriptortype_e ----
pub const KHR_DF_KHR_DESCRIPTORTYPE_BASICFORMAT: Int32 = 0 as Int32;
pub const KHR_DF_KHR_DESCRIPTORTYPE_ADDITIONAL_PLANES: Int32 = 24577 as Int32;
pub const KHR_DF_KHR_DESCRIPTORTYPE_ADDITIONAL_DIMENSIONS: Int32 = 24578 as Int32;
pub const KHR_DF_KHR_DESCRIPTORTYPE_NEEDED_FOR_WRITE_BIT: Int32 = 8192 as Int32;
pub const KHR_DF_KHR_DESCRIPTORTYPE_NEEDED_FOR_DECODE_BIT: Int32 = 16384 as Int32;
pub const KHR_DF_KHR_DESCRIPTORTYPE_MAX: Int32 = 32767 as Int32;

// ---- _khr_df_mask_e ----
pub const KHR_DF_MASK_VENDORID: Int32 = 131071 as Int32;
pub const KHR_DF_MASK_DESCRIPTORTYPE: Int32 = 32767 as Int32;
pub const KHR_DF_MASK_VERSIONNUMBER: Int32 = 65535 as Int32;
pub const KHR_DF_MASK_DESCRIPTORBLOCKSIZE: Int32 = 65535 as Int32;
pub const KHR_DF_MASK_MODEL: Int32 = 255 as Int32;
pub const KHR_DF_MASK_PRIMARIES: Int32 = 255 as Int32;
pub const KHR_DF_MASK_TRANSFER: Int32 = 255 as Int32;
pub const KHR_DF_MASK_FLAGS: Int32 = 255 as Int32;
pub const KHR_DF_MASK_TEXELBLOCKDIMENSION0: Int32 = 255 as Int32;
pub const KHR_DF_MASK_TEXELBLOCKDIMENSION1: Int32 = 255 as Int32;
pub const KHR_DF_MASK_TEXELBLOCKDIMENSION2: Int32 = 255 as Int32;
pub const KHR_DF_MASK_TEXELBLOCKDIMENSION3: Int32 = 255 as Int32;
pub const KHR_DF_MASK_BYTESPLANE0: Int32 = 255 as Int32;
pub const KHR_DF_MASK_BYTESPLANE1: Int32 = 255 as Int32;
pub const KHR_DF_MASK_BYTESPLANE2: Int32 = 255 as Int32;
pub const KHR_DF_MASK_BYTESPLANE3: Int32 = 255 as Int32;
pub const KHR_DF_MASK_BYTESPLANE4: Int32 = 255 as Int32;
pub const KHR_DF_MASK_BYTESPLANE5: Int32 = 255 as Int32;
pub const KHR_DF_MASK_BYTESPLANE6: Int32 = 255 as Int32;
pub const KHR_DF_MASK_BYTESPLANE7: Int32 = 255 as Int32;

// ---- _khr_df_model_channels_e ----
pub const KHR_DF_CHANNEL_UNSPECIFIED_0: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_UNSPECIFIED_1: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_UNSPECIFIED_2: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_UNSPECIFIED_3: Int32 = 3 as Int32;
pub const KHR_DF_CHANNEL_UNSPECIFIED_4: Int32 = 4 as Int32;
pub const KHR_DF_CHANNEL_UNSPECIFIED_5: Int32 = 5 as Int32;
pub const KHR_DF_CHANNEL_UNSPECIFIED_6: Int32 = 6 as Int32;
pub const KHR_DF_CHANNEL_UNSPECIFIED_7: Int32 = 7 as Int32;
pub const KHR_DF_CHANNEL_UNSPECIFIED_8: Int32 = 8 as Int32;
pub const KHR_DF_CHANNEL_UNSPECIFIED_9: Int32 = 9 as Int32;
pub const KHR_DF_CHANNEL_UNSPECIFIED_10: Int32 = 10 as Int32;
pub const KHR_DF_CHANNEL_UNSPECIFIED_11: Int32 = 11 as Int32;
pub const KHR_DF_CHANNEL_UNSPECIFIED_12: Int32 = 12 as Int32;
pub const KHR_DF_CHANNEL_UNSPECIFIED_13: Int32 = 13 as Int32;
pub const KHR_DF_CHANNEL_UNSPECIFIED_14: Int32 = 14 as Int32;
pub const KHR_DF_CHANNEL_UNSPECIFIED_15: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_RGBSDA_RED: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_RGBSDA_R: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_RGBSDA_GREEN: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_RGBSDA_G: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_RGBSDA_BLUE: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_RGBSDA_B: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_RGBSDA_STENCIL: Int32 = 13 as Int32;
pub const KHR_DF_CHANNEL_RGBSDA_S: Int32 = 13 as Int32;
pub const KHR_DF_CHANNEL_RGBSDA_DEPTH: Int32 = 14 as Int32;
pub const KHR_DF_CHANNEL_RGBSDA_D: Int32 = 14 as Int32;
pub const KHR_DF_CHANNEL_RGBSDA_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_RGBSDA_A: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_YUVSDA_Y: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_YUVSDA_CB: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_YUVSDA_U: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_YUVSDA_CR: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_YUVSDA_V: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_YUVSDA_STENCIL: Int32 = 13 as Int32;
pub const KHR_DF_CHANNEL_YUVSDA_S: Int32 = 13 as Int32;
pub const KHR_DF_CHANNEL_YUVSDA_DEPTH: Int32 = 14 as Int32;
pub const KHR_DF_CHANNEL_YUVSDA_D: Int32 = 14 as Int32;
pub const KHR_DF_CHANNEL_YUVSDA_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_YUVSDA_A: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_YIQSDA_Y: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_YIQSDA_I: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_YIQSDA_Q: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_YIQSDA_STENCIL: Int32 = 13 as Int32;
pub const KHR_DF_CHANNEL_YIQSDA_S: Int32 = 13 as Int32;
pub const KHR_DF_CHANNEL_YIQSDA_DEPTH: Int32 = 14 as Int32;
pub const KHR_DF_CHANNEL_YIQSDA_D: Int32 = 14 as Int32;
pub const KHR_DF_CHANNEL_YIQSDA_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_YIQSDA_A: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_LABSDA_L: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_LABSDA_A: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_LABSDA_B: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_LABSDA_STENCIL: Int32 = 13 as Int32;
pub const KHR_DF_CHANNEL_LABSDA_S: Int32 = 13 as Int32;
pub const KHR_DF_CHANNEL_LABSDA_DEPTH: Int32 = 14 as Int32;
pub const KHR_DF_CHANNEL_LABSDA_D: Int32 = 14 as Int32;
pub const KHR_DF_CHANNEL_LABSDA_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_CMYKSDA_CYAN: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_CMYKSDA_C: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_CMYKSDA_MAGENTA: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_CMYKSDA_M: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_CMYKSDA_YELLOW: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_CMYKSDA_Y: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_CMYKSDA_KEY: Int32 = 3 as Int32;
pub const KHR_DF_CHANNEL_CMYKSDA_BLACK: Int32 = 3 as Int32;
pub const KHR_DF_CHANNEL_CMYKSDA_K: Int32 = 3 as Int32;
pub const KHR_DF_CHANNEL_CMYKSDA_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_CMYKSDA_A: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_XYZW_X: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_XYZW_Y: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_XYZW_Z: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_XYZW_W: Int32 = 3 as Int32;
pub const KHR_DF_CHANNEL_HSVA_ANG_VALUE: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_HSVA_ANG_V: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_HSVA_ANG_SATURATION: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_HSVA_ANG_S: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_HSVA_ANG_HUE: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_HSVA_ANG_H: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_HSVA_ANG_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_HSVA_ANG_A: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_HSLA_ANG_LIGHTNESS: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_HSLA_ANG_L: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_HSLA_ANG_SATURATION: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_HSLA_ANG_S: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_HSLA_ANG_HUE: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_HSLA_ANG_H: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_HSLA_ANG_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_HSLA_ANG_A: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_HSVA_HEX_VALUE: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_HSVA_HEX_V: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_HSVA_HEX_SATURATION: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_HSVA_HEX_S: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_HSVA_HEX_HUE: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_HSVA_HEX_H: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_HSVA_HEX_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_HSVA_HEX_A: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_HSLA_HEX_LIGHTNESS: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_HSLA_HEX_L: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_HSLA_HEX_SATURATION: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_HSLA_HEX_S: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_HSLA_HEX_HUE: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_HSLA_HEX_H: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_HSLA_HEX_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_HSLA_HEX_A: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_YCGCOA_Y: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_YCGCOA_CG: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_YCGCOA_CO: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_YCGCOA_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_YCGCOA_A: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_CIEXYZ_X: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_CIEXYZ_Y: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_CIEXYZ_Z: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_CIEXYY_X: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_CIEXYY_YCHROMA: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_CIEXYY_YLUMA: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_DXT1A_COLOR: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_BC1A_COLOR: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_DXT1A_ALPHAPRESENT: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_DXT1A_ALPHA: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_BC1A_ALPHAPRESENT: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_BC1A_ALPHA: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_DXT2_COLOR: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_DXT3_COLOR: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_BC2_COLOR: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_DXT2_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_DXT3_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_BC2_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_DXT4_COLOR: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_DXT5_COLOR: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_BC3_COLOR: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_DXT4_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_DXT5_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_BC3_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_BC4_DATA: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_BC5_RED: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_BC5_R: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_BC5_GREEN: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_BC5_G: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_BC6H_COLOR: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_BC6H_DATA: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_BC7_DATA: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_BC7_COLOR: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_ETC1_DATA: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_ETC1_COLOR: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_ETC2_RED: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_ETC2_R: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_ETC2_GREEN: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_ETC2_G: Int32 = 1 as Int32;
pub const KHR_DF_CHANNEL_ETC2_COLOR: Int32 = 2 as Int32;
pub const KHR_DF_CHANNEL_ETC2_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_ETC2_A: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_ASTC_DATA: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_ETC1S_RGB: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_ETC1S_RRR: Int32 = 3 as Int32;
pub const KHR_DF_CHANNEL_ETC1S_GGG: Int32 = 4 as Int32;
pub const KHR_DF_CHANNEL_ETC1S_AAA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_PVRTC_DATA: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_PVRTC_COLOR: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_PVRTC2_DATA: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_PVRTC2_COLOR: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_UASTC_RGB: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_UASTC_RGBA: Int32 = 3 as Int32;
pub const KHR_DF_CHANNEL_UASTC_RRR: Int32 = 4 as Int32;
pub const KHR_DF_CHANNEL_UASTC_RRRG: Int32 = 5 as Int32;
pub const KHR_DF_CHANNEL_UASTC_RG: Int32 = 6 as Int32;
pub const KHR_DF_CHANNEL_COMMON_LUMA: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_COMMON_L: Int32 = 0 as Int32;
pub const KHR_DF_CHANNEL_COMMON_STENCIL: Int32 = 13 as Int32;
pub const KHR_DF_CHANNEL_COMMON_S: Int32 = 13 as Int32;
pub const KHR_DF_CHANNEL_COMMON_DEPTH: Int32 = 14 as Int32;
pub const KHR_DF_CHANNEL_COMMON_D: Int32 = 14 as Int32;
pub const KHR_DF_CHANNEL_COMMON_ALPHA: Int32 = 15 as Int32;
pub const KHR_DF_CHANNEL_COMMON_A: Int32 = 15 as Int32;

// ---- _khr_df_model_e ----
pub const KHR_DF_MODEL_UNSPECIFIED: Int32 = 0 as Int32;
pub const KHR_DF_MODEL_RGBSDA: Int32 = 1 as Int32;
pub const KHR_DF_MODEL_YUVSDA: Int32 = 2 as Int32;
pub const KHR_DF_MODEL_YIQSDA: Int32 = 3 as Int32;
pub const KHR_DF_MODEL_LABSDA: Int32 = 4 as Int32;
pub const KHR_DF_MODEL_CMYKA: Int32 = 5 as Int32;
pub const KHR_DF_MODEL_XYZW: Int32 = 6 as Int32;
pub const KHR_DF_MODEL_HSVA_ANG: Int32 = 7 as Int32;
pub const KHR_DF_MODEL_HSLA_ANG: Int32 = 8 as Int32;
pub const KHR_DF_MODEL_HSVA_HEX: Int32 = 9 as Int32;
pub const KHR_DF_MODEL_HSLA_HEX: Int32 = 10 as Int32;
pub const KHR_DF_MODEL_YCGCOA: Int32 = 11 as Int32;
pub const KHR_DF_MODEL_YCCBCCRC: Int32 = 12 as Int32;
pub const KHR_DF_MODEL_ICTCP: Int32 = 13 as Int32;
pub const KHR_DF_MODEL_CIEXYZ: Int32 = 14 as Int32;
pub const KHR_DF_MODEL_CIEXYY: Int32 = 15 as Int32;
pub const KHR_DF_MODEL_DXT1A: Int32 = 128 as Int32;
pub const KHR_DF_MODEL_BC1A: Int32 = 128 as Int32;
pub const KHR_DF_MODEL_DXT2: Int32 = 129 as Int32;
pub const KHR_DF_MODEL_DXT3: Int32 = 129 as Int32;
pub const KHR_DF_MODEL_BC2: Int32 = 129 as Int32;
pub const KHR_DF_MODEL_DXT4: Int32 = 130 as Int32;
pub const KHR_DF_MODEL_DXT5: Int32 = 130 as Int32;
pub const KHR_DF_MODEL_BC3: Int32 = 130 as Int32;
pub const KHR_DF_MODEL_ATI1N: Int32 = 131 as Int32;
pub const KHR_DF_MODEL_DXT5A: Int32 = 131 as Int32;
pub const KHR_DF_MODEL_BC4: Int32 = 131 as Int32;
pub const KHR_DF_MODEL_ATI2N_XY: Int32 = 132 as Int32;
pub const KHR_DF_MODEL_DXN: Int32 = 132 as Int32;
pub const KHR_DF_MODEL_BC5: Int32 = 132 as Int32;
pub const KHR_DF_MODEL_BC6H: Int32 = 133 as Int32;
pub const KHR_DF_MODEL_BC7: Int32 = 134 as Int32;
pub const KHR_DF_MODEL_ETC1: Int32 = 160 as Int32;
pub const KHR_DF_MODEL_ETC2: Int32 = 161 as Int32;
pub const KHR_DF_MODEL_ASTC: Int32 = 162 as Int32;
pub const KHR_DF_MODEL_ETC1S: Int32 = 163 as Int32;
pub const KHR_DF_MODEL_PVRTC: Int32 = 164 as Int32;
pub const KHR_DF_MODEL_PVRTC2: Int32 = 165 as Int32;
pub const KHR_DF_MODEL_UASTC: Int32 = 166 as Int32;
pub const KHR_DF_MODEL_MAX: Int32 = 255 as Int32;

// ---- _khr_df_primaries_e ----
pub const KHR_DF_PRIMARIES_UNSPECIFIED: Int32 = 0 as Int32;
pub const KHR_DF_PRIMARIES_BT709: Int32 = 1 as Int32;
pub const KHR_DF_PRIMARIES_SRGB: Int32 = 1 as Int32;
pub const KHR_DF_PRIMARIES_BT601_EBU: Int32 = 2 as Int32;
pub const KHR_DF_PRIMARIES_BT601_SMPTE: Int32 = 3 as Int32;
pub const KHR_DF_PRIMARIES_BT2020: Int32 = 4 as Int32;
pub const KHR_DF_PRIMARIES_BT2100: Int32 = 4 as Int32;
pub const KHR_DF_PRIMARIES_CIEXYZ: Int32 = 5 as Int32;
pub const KHR_DF_PRIMARIES_ACES: Int32 = 6 as Int32;
pub const KHR_DF_PRIMARIES_ACESCC: Int32 = 7 as Int32;
pub const KHR_DF_PRIMARIES_NTSC1953: Int32 = 8 as Int32;
pub const KHR_DF_PRIMARIES_PAL525: Int32 = 9 as Int32;
pub const KHR_DF_PRIMARIES_DISPLAYP3: Int32 = 10 as Int32;
pub const KHR_DF_PRIMARIES_ADOBERGB: Int32 = 11 as Int32;
pub const KHR_DF_PRIMARIES_MAX: Int32 = 255 as Int32;

// ---- _khr_df_sample_datatype_qualifiers_e ----
pub const KHR_DF_SAMPLE_DATATYPE_LINEAR: Int32 = 16 as Int32;
pub const KHR_DF_SAMPLE_DATATYPE_EXPONENT: Int32 = 32 as Int32;
pub const KHR_DF_SAMPLE_DATATYPE_SIGNED: Int32 = 64 as Int32;
pub const KHR_DF_SAMPLE_DATATYPE_FLOAT: Int32 = 128 as Int32;

// ---- _khr_df_samplemask_e ----
pub const KHR_DF_SAMPLEMASK_BITOFFSET: Int32 = 65535 as Int32;
pub const KHR_DF_SAMPLEMASK_BITLENGTH: Int32 = 255 as Int32;
pub const KHR_DF_SAMPLEMASK_CHANNELID: Int32 = 15 as Int32;
pub const KHR_DF_SAMPLEMASK_QUALIFIERS: Int32 = 240 as Int32;
pub const KHR_DF_SAMPLEMASK_SAMPLEPOSITION0: Int32 = 255 as Int32;
pub const KHR_DF_SAMPLEMASK_SAMPLEPOSITION1: Int32 = 255 as Int32;
pub const KHR_DF_SAMPLEMASK_SAMPLEPOSITION2: Int32 = 255 as Int32;
pub const KHR_DF_SAMPLEMASK_SAMPLEPOSITION3: Int32 = 255 as Int32;
pub const KHR_DF_SAMPLEMASK_SAMPLEPOSITION_ALL: Int32 = -1 as Int32;
pub const KHR_DF_SAMPLEMASK_SAMPLELOWER: Int32 = -1 as Int32;
pub const KHR_DF_SAMPLEMASK_SAMPLEUPPER: Int32 = -1 as Int32;

// ---- _khr_df_sampleshift_e ----
pub const KHR_DF_SAMPLESHIFT_BITOFFSET: Int32 = 0 as Int32;
pub const KHR_DF_SAMPLESHIFT_BITLENGTH: Int32 = 16 as Int32;
pub const KHR_DF_SAMPLESHIFT_CHANNELID: Int32 = 24 as Int32;
pub const KHR_DF_SAMPLESHIFT_QUALIFIERS: Int32 = 24 as Int32;
pub const KHR_DF_SAMPLESHIFT_SAMPLEPOSITION0: Int32 = 0 as Int32;
pub const KHR_DF_SAMPLESHIFT_SAMPLEPOSITION1: Int32 = 8 as Int32;
pub const KHR_DF_SAMPLESHIFT_SAMPLEPOSITION2: Int32 = 16 as Int32;
pub const KHR_DF_SAMPLESHIFT_SAMPLEPOSITION3: Int32 = 24 as Int32;
pub const KHR_DF_SAMPLESHIFT_SAMPLEPOSITION_ALL: Int32 = 0 as Int32;
pub const KHR_DF_SAMPLESHIFT_SAMPLELOWER: Int32 = 0 as Int32;
pub const KHR_DF_SAMPLESHIFT_SAMPLEUPPER: Int32 = 0 as Int32;

// ---- _khr_df_sampleword_e ----
pub const KHR_DF_SAMPLEWORD_BITOFFSET: Int32 = 0 as Int32;
pub const KHR_DF_SAMPLEWORD_BITLENGTH: Int32 = 0 as Int32;
pub const KHR_DF_SAMPLEWORD_CHANNELID: Int32 = 0 as Int32;
pub const KHR_DF_SAMPLEWORD_QUALIFIERS: Int32 = 0 as Int32;
pub const KHR_DF_SAMPLEWORD_SAMPLEPOSITION0: Int32 = 1 as Int32;
pub const KHR_DF_SAMPLEWORD_SAMPLEPOSITION1: Int32 = 1 as Int32;
pub const KHR_DF_SAMPLEWORD_SAMPLEPOSITION2: Int32 = 1 as Int32;
pub const KHR_DF_SAMPLEWORD_SAMPLEPOSITION3: Int32 = 1 as Int32;
pub const KHR_DF_SAMPLEWORD_SAMPLEPOSITION_ALL: Int32 = 1 as Int32;
pub const KHR_DF_SAMPLEWORD_SAMPLELOWER: Int32 = 2 as Int32;
pub const KHR_DF_SAMPLEWORD_SAMPLEUPPER: Int32 = 3 as Int32;

// ---- _khr_df_shift_e ----
pub const KHR_DF_SHIFT_VENDORID: Int32 = 0 as Int32;
pub const KHR_DF_SHIFT_DESCRIPTORTYPE: Int32 = 17 as Int32;
pub const KHR_DF_SHIFT_VERSIONNUMBER: Int32 = 0 as Int32;
pub const KHR_DF_SHIFT_DESCRIPTORBLOCKSIZE: Int32 = 16 as Int32;
pub const KHR_DF_SHIFT_MODEL: Int32 = 0 as Int32;
pub const KHR_DF_SHIFT_PRIMARIES: Int32 = 8 as Int32;
pub const KHR_DF_SHIFT_TRANSFER: Int32 = 16 as Int32;
pub const KHR_DF_SHIFT_FLAGS: Int32 = 24 as Int32;
pub const KHR_DF_SHIFT_TEXELBLOCKDIMENSION0: Int32 = 0 as Int32;
pub const KHR_DF_SHIFT_TEXELBLOCKDIMENSION1: Int32 = 8 as Int32;
pub const KHR_DF_SHIFT_TEXELBLOCKDIMENSION2: Int32 = 16 as Int32;
pub const KHR_DF_SHIFT_TEXELBLOCKDIMENSION3: Int32 = 24 as Int32;
pub const KHR_DF_SHIFT_BYTESPLANE0: Int32 = 0 as Int32;
pub const KHR_DF_SHIFT_BYTESPLANE1: Int32 = 8 as Int32;
pub const KHR_DF_SHIFT_BYTESPLANE2: Int32 = 16 as Int32;
pub const KHR_DF_SHIFT_BYTESPLANE3: Int32 = 24 as Int32;
pub const KHR_DF_SHIFT_BYTESPLANE4: Int32 = 0 as Int32;
pub const KHR_DF_SHIFT_BYTESPLANE5: Int32 = 8 as Int32;
pub const KHR_DF_SHIFT_BYTESPLANE6: Int32 = 16 as Int32;
pub const KHR_DF_SHIFT_BYTESPLANE7: Int32 = 24 as Int32;

// ---- _khr_df_transfer_e ----
pub const KHR_DF_TRANSFER_UNSPECIFIED: Int32 = 0 as Int32;
pub const KHR_DF_TRANSFER_LINEAR: Int32 = 1 as Int32;
pub const KHR_DF_TRANSFER_SRGB: Int32 = 2 as Int32;
pub const KHR_DF_TRANSFER_SRGB_EOTF: Int32 = 2 as Int32;
pub const KHR_DF_TRANSFER_SCRGB: Int32 = 2 as Int32;
pub const KHR_DF_TRANSFER_SCRGB_EOTF: Int32 = 2 as Int32;
pub const KHR_DF_TRANSFER_ITU: Int32 = 3 as Int32;
pub const KHR_DF_TRANSFER_ITU_OETF: Int32 = 3 as Int32;
pub const KHR_DF_TRANSFER_BT601: Int32 = 3 as Int32;
pub const KHR_DF_TRANSFER_BT601_OETF: Int32 = 3 as Int32;
pub const KHR_DF_TRANSFER_BT709: Int32 = 3 as Int32;
pub const KHR_DF_TRANSFER_BT709_OETF: Int32 = 3 as Int32;
pub const KHR_DF_TRANSFER_BT2020: Int32 = 3 as Int32;
pub const KHR_DF_TRANSFER_BT2020_OETF: Int32 = 3 as Int32;
pub const KHR_DF_TRANSFER_SMTPE170M: Int32 = 3 as Int32;
pub const KHR_DF_TRANSFER_SMTPE170M_OETF: Int32 = 3 as Int32;
pub const KHR_DF_TRANSFER_SMTPE170M_EOTF: Int32 = 3 as Int32;
pub const KHR_DF_TRANSFER_NTSC: Int32 = 4 as Int32;
pub const KHR_DF_TRANSFER_NTSC_EOTF: Int32 = 4 as Int32;
pub const KHR_DF_TRANSFER_SLOG: Int32 = 5 as Int32;
pub const KHR_DF_TRANSFER_SLOG_OETF: Int32 = 5 as Int32;
pub const KHR_DF_TRANSFER_SLOG2: Int32 = 6 as Int32;
pub const KHR_DF_TRANSFER_SLOG2_OETF: Int32 = 6 as Int32;
pub const KHR_DF_TRANSFER_BT1886: Int32 = 7 as Int32;
pub const KHR_DF_TRANSFER_BT1886_EOTF: Int32 = 7 as Int32;
pub const KHR_DF_TRANSFER_HLG_OETF: Int32 = 8 as Int32;
pub const KHR_DF_TRANSFER_HLG_EOTF: Int32 = 9 as Int32;
pub const KHR_DF_TRANSFER_PQ_EOTF: Int32 = 10 as Int32;
pub const KHR_DF_TRANSFER_PQ_OETF: Int32 = 11 as Int32;
pub const KHR_DF_TRANSFER_DCIP3: Int32 = 12 as Int32;
pub const KHR_DF_TRANSFER_DCIP3_EOTF: Int32 = 12 as Int32;
pub const KHR_DF_TRANSFER_PAL_OETF: Int32 = 13 as Int32;
pub const KHR_DF_TRANSFER_PAL625_EOTF: Int32 = 14 as Int32;
pub const KHR_DF_TRANSFER_ST240: Int32 = 15 as Int32;
pub const KHR_DF_TRANSFER_ST240_OETF: Int32 = 15 as Int32;
pub const KHR_DF_TRANSFER_ST240_EOTF: Int32 = 15 as Int32;
pub const KHR_DF_TRANSFER_ACESCC: Int32 = 16 as Int32;
pub const KHR_DF_TRANSFER_ACESCC_OETF: Int32 = 16 as Int32;
pub const KHR_DF_TRANSFER_ACESCCT: Int32 = 17 as Int32;
pub const KHR_DF_TRANSFER_ACESCCT_OETF: Int32 = 17 as Int32;
pub const KHR_DF_TRANSFER_ADOBERGB: Int32 = 18 as Int32;
pub const KHR_DF_TRANSFER_ADOBERGB_EOTF: Int32 = 18 as Int32;
pub const KHR_DF_TRANSFER_HLG_UNNORMALIZED_OETF: Int32 = 19 as Int32;
pub const KHR_DF_TRANSFER_MAX: Int32 = 255 as Int32;

// ---- _khr_df_vendorid_e ----
pub const KHR_DF_VENDORID_KHRONOS: Int32 = 0 as Int32;
pub const KHR_DF_VENDORID_MAX: Int32 = 131071 as Int32;

// ---- _khr_df_versionnumber_e ----
pub const KHR_DF_VERSIONNUMBER_1_0: Int32 = 0 as Int32;
pub const KHR_DF_VERSIONNUMBER_1_1: Int32 = 0 as Int32;
pub const KHR_DF_VERSIONNUMBER_1_2: Int32 = 1 as Int32;
pub const KHR_DF_VERSIONNUMBER_1_3: Int32 = 2 as Int32;
pub const KHR_DF_VERSIONNUMBER_1_4: Int32 = 2 as Int32;
pub const KHR_DF_VERSIONNUMBER_LATEST: Int32 = 2 as Int32;
pub const KHR_DF_VERSIONNUMBER_MAX: Int32 = 65535 as Int32;

// ---- _khr_word_e ----
pub const KHR_DF_WORD_VENDORID: Int32 = 0 as Int32;
pub const KHR_DF_WORD_DESCRIPTORTYPE: Int32 = 0 as Int32;
pub const KHR_DF_WORD_VERSIONNUMBER: Int32 = 1 as Int32;
pub const KHR_DF_WORD_DESCRIPTORBLOCKSIZE: Int32 = 1 as Int32;
pub const KHR_DF_WORD_MODEL: Int32 = 2 as Int32;
pub const KHR_DF_WORD_PRIMARIES: Int32 = 2 as Int32;
pub const KHR_DF_WORD_TRANSFER: Int32 = 2 as Int32;
pub const KHR_DF_WORD_FLAGS: Int32 = 2 as Int32;
pub const KHR_DF_WORD_TEXELBLOCKDIMENSION0: Int32 = 3 as Int32;
pub const KHR_DF_WORD_TEXELBLOCKDIMENSION1: Int32 = 3 as Int32;
pub const KHR_DF_WORD_TEXELBLOCKDIMENSION2: Int32 = 3 as Int32;
pub const KHR_DF_WORD_TEXELBLOCKDIMENSION3: Int32 = 3 as Int32;
pub const KHR_DF_WORD_BYTESPLANE0: Int32 = 4 as Int32;
pub const KHR_DF_WORD_BYTESPLANE1: Int32 = 4 as Int32;
pub const KHR_DF_WORD_BYTESPLANE2: Int32 = 4 as Int32;
pub const KHR_DF_WORD_BYTESPLANE3: Int32 = 4 as Int32;
pub const KHR_DF_WORD_BYTESPLANE4: Int32 = 5 as Int32;
pub const KHR_DF_WORD_BYTESPLANE5: Int32 = 5 as Int32;
pub const KHR_DF_WORD_BYTESPLANE6: Int32 = 5 as Int32;
pub const KHR_DF_WORD_BYTESPLANE7: Int32 = 5 as Int32;
pub const KHR_DF_WORD_SAMPLESTART: Int32 = 6 as Int32;
pub const KHR_DF_WORD_SAMPLEWORDS: Int32 = 4 as Int32;

// ---- class_id ----
pub const ktxTexture1_c: Int32 = 1 as Int32;
pub const ktxTexture2_c: Int32 = 2 as Int32;

// ---- ktxOrientationX ----
pub const KTX_ORIENT_X_LEFT: Int32 = 108 as Int32;
pub const KTX_ORIENT_X_RIGHT: Int32 = 114 as Int32;

// ---- ktxOrientationY ----
pub const KTX_ORIENT_Y_UP: Int32 = 117 as Int32;
pub const KTX_ORIENT_Y_DOWN: Int32 = 100 as Int32;

// ---- ktxOrientationZ ----
pub const KTX_ORIENT_Z_IN: Int32 = 105 as Int32;
pub const KTX_ORIENT_Z_OUT: Int32 = 111 as Int32;

// ---- ktxSupercmpScheme ----
pub const KTX_SS_NONE: Int32 = 0 as Int32;
pub const KTX_SS_BASIS_LZ: Int32 = 1 as Int32;
pub const KTX_SS_ZSTD: Int32 = 2 as Int32;
pub const KTX_SS_ZLIB: Int32 = 3 as Int32;
pub const KTX_SS_BEGIN_RANGE: Int32 = 0 as Int32;
pub const KTX_SS_END_RANGE: Int32 = 3 as Int32;
pub const KTX_SS_BEGIN_VENDOR_RANGE: Int32 = 65536 as Int32;
pub const KTX_SS_END_VENDOR_RANGE: Int32 = 131071 as Int32;
pub const KTX_SS_BEGIN_RESERVED: Int32 = 131072 as Int32;

// ---- ktxTextureCreateFlagBits ----
pub const KTX_TEXTURE_CREATE_NO_FLAGS: Int32 = 0 as Int32;
pub const KTX_TEXTURE_CREATE_LOAD_IMAGE_DATA_BIT: Int32 = 1 as Int32;
pub const KTX_TEXTURE_CREATE_RAW_KVDATA_BIT: Int32 = 2 as Int32;
pub const KTX_TEXTURE_CREATE_SKIP_KVDATA_BIT: Int32 = 4 as Int32;
pub const KTX_TEXTURE_CREATE_CHECK_GLTF_BASISU_BIT: Int32 = 8 as Int32;

// ---- ktx_error_code_e ----
pub const KTX_SUCCESS: Int32 = 0 as Int32;
pub const KTX_FILE_DATA_ERROR: Int32 = 1 as Int32;
pub const KTX_FILE_ISPIPE: Int32 = 2 as Int32;
pub const KTX_FILE_OPEN_FAILED: Int32 = 3 as Int32;
pub const KTX_FILE_OVERFLOW: Int32 = 4 as Int32;
pub const KTX_FILE_READ_ERROR: Int32 = 5 as Int32;
pub const KTX_FILE_SEEK_ERROR: Int32 = 6 as Int32;
pub const KTX_FILE_UNEXPECTED_EOF: Int32 = 7 as Int32;
pub const KTX_FILE_WRITE_ERROR: Int32 = 8 as Int32;
pub const KTX_GL_ERROR: Int32 = 9 as Int32;
pub const KTX_INVALID_OPERATION: Int32 = 10 as Int32;
pub const KTX_INVALID_VALUE: Int32 = 11 as Int32;
pub const KTX_NOT_FOUND: Int32 = 12 as Int32;
pub const KTX_OUT_OF_MEMORY: Int32 = 13 as Int32;
pub const KTX_TRANSCODE_FAILED: Int32 = 14 as Int32;
pub const KTX_UNKNOWN_FILE_FORMAT: Int32 = 15 as Int32;
pub const KTX_UNSUPPORTED_TEXTURE_TYPE: Int32 = 16 as Int32;
pub const KTX_UNSUPPORTED_FEATURE: Int32 = 17 as Int32;
pub const KTX_LIBRARY_NOT_LINKED: Int32 = 18 as Int32;
pub const KTX_DECOMPRESS_LENGTH_ERROR: Int32 = 19 as Int32;
pub const KTX_DECOMPRESS_CHECKSUM_ERROR: Int32 = 20 as Int32;
pub const KTX_ERROR_MAX_ENUM: Int32 = 20 as Int32;

// ---- ktx_pack_astc_block_dimension_e ----
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_4x4: Int32 = 0 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_5x4: Int32 = 1 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_5x5: Int32 = 2 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_6x5: Int32 = 3 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_6x6: Int32 = 4 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_8x5: Int32 = 5 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_8x6: Int32 = 6 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_10x5: Int32 = 7 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_10x6: Int32 = 8 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_8x8: Int32 = 9 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_10x8: Int32 = 10 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_10x10: Int32 = 11 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_12x10: Int32 = 12 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_12x12: Int32 = 13 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_3x3x3: Int32 = 14 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_4x3x3: Int32 = 15 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_4x4x3: Int32 = 16 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_4x4x4: Int32 = 17 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_5x4x4: Int32 = 18 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_5x5x4: Int32 = 19 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_5x5x5: Int32 = 20 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_6x5x5: Int32 = 21 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_6x6x5: Int32 = 22 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_6x6x6: Int32 = 23 as Int32;
pub const KTX_PACK_ASTC_BLOCK_DIMENSION_MAX: Int32 = 23 as Int32;

// ---- ktx_pack_astc_encoder_mode_e ----
pub const KTX_PACK_ASTC_ENCODER_MODE_DEFAULT: Int32 = 0 as Int32;
pub const KTX_PACK_ASTC_ENCODER_MODE_LDR: Int32 = 1 as Int32;
pub const KTX_PACK_ASTC_ENCODER_MODE_HDR: Int32 = 2 as Int32;
pub const KTX_PACK_ASTC_ENCODER_MODE_MAX: Int32 = 2 as Int32;

// ---- ktx_pack_astc_quality_levels_e ----
pub const KTX_PACK_ASTC_QUALITY_LEVEL_FASTEST: Int32 = 0 as Int32;
pub const KTX_PACK_ASTC_QUALITY_LEVEL_FAST: Int32 = 10 as Int32;
pub const KTX_PACK_ASTC_QUALITY_LEVEL_MEDIUM: Int32 = 60 as Int32;
pub const KTX_PACK_ASTC_QUALITY_LEVEL_THOROUGH: Int32 = 98 as Int32;
pub const KTX_PACK_ASTC_QUALITY_LEVEL_EXHAUSTIVE: Int32 = 100 as Int32;
pub const KTX_PACK_ASTC_QUALITY_LEVEL_MAX: Int32 = 100 as Int32;

// ---- ktx_pack_uastc_flag_bits_e ----
pub const KTX_PACK_UASTC_LEVEL_FASTEST: Int32 = 0 as Int32;
pub const KTX_PACK_UASTC_LEVEL_FASTER: Int32 = 1 as Int32;
pub const KTX_PACK_UASTC_LEVEL_DEFAULT: Int32 = 2 as Int32;
pub const KTX_PACK_UASTC_LEVEL_SLOWER: Int32 = 3 as Int32;
pub const KTX_PACK_UASTC_LEVEL_VERYSLOW: Int32 = 4 as Int32;
pub const KTX_PACK_UASTC_MAX_LEVEL: Int32 = 4 as Int32;
pub const KTX_PACK_UASTC_LEVEL_MASK: Int32 = 15 as Int32;
pub const KTX_PACK_UASTC_FAVOR_UASTC_ERROR: Int32 = 8 as Int32;
pub const KTX_PACK_UASTC_FAVOR_BC7_ERROR: Int32 = 16 as Int32;
pub const KTX_PACK_UASTC_ETC1_FASTER_HINTS: Int32 = 64 as Int32;
pub const KTX_PACK_UASTC_ETC1_FASTEST_HINTS: Int32 = 128 as Int32;
pub const KTX_PACK_UASTC__ETC1_DISABLE_FLIP_AND_INDIVIDUAL: Int32 = 256 as Int32;

// ---- ktx_transcode_flag_bits_e ----
pub const KTX_TF_PVRTC_DECODE_TO_NEXT_POW2: Int32 = 2 as Int32;
pub const KTX_TF_TRANSCODE_ALPHA_DATA_TO_OPAQUE_FORMATS: Int32 = 4 as Int32;
pub const KTX_TF_HIGH_QUALITY: Int32 = 32 as Int32;

// ---- ktx_transcode_fmt_e ----
pub const KTX_TTF_ETC1_RGB: Int32 = 0 as Int32;
pub const KTX_TTF_ETC2_RGBA: Int32 = 1 as Int32;
pub const KTX_TTF_BC1_RGB: Int32 = 2 as Int32;
pub const KTX_TTF_BC3_RGBA: Int32 = 3 as Int32;
pub const KTX_TTF_BC4_R: Int32 = 4 as Int32;
pub const KTX_TTF_BC5_RG: Int32 = 5 as Int32;
pub const KTX_TTF_BC7_RGBA: Int32 = 6 as Int32;
pub const KTX_TTF_PVRTC1_4_RGB: Int32 = 8 as Int32;
pub const KTX_TTF_PVRTC1_4_RGBA: Int32 = 9 as Int32;
pub const KTX_TTF_ASTC_4x4_RGBA: Int32 = 10 as Int32;
pub const KTX_TTF_PVRTC2_4_RGB: Int32 = 18 as Int32;
pub const KTX_TTF_PVRTC2_4_RGBA: Int32 = 19 as Int32;
pub const KTX_TTF_ETC2_EAC_R11: Int32 = 20 as Int32;
pub const KTX_TTF_ETC2_EAC_RG11: Int32 = 21 as Int32;
pub const KTX_TTF_RGBA32: Int32 = 13 as Int32;
pub const KTX_TTF_RGB565: Int32 = 14 as Int32;
pub const KTX_TTF_BGR565: Int32 = 15 as Int32;
pub const KTX_TTF_RGBA4444: Int32 = 16 as Int32;
pub const KTX_TTF_ETC: Int32 = 22 as Int32;
pub const KTX_TTF_BC1_OR_3: Int32 = 23 as Int32;
pub const KTX_TTF_NOSELECTION: Int32 = 2147483647 as Int32;
pub const KTX_TF_ETC1: Int32 = 0 as Int32;
pub const KTX_TF_ETC2: Int32 = 22 as Int32;
pub const KTX_TF_BC1: Int32 = 2 as Int32;
pub const KTX_TF_BC3: Int32 = 3 as Int32;
pub const KTX_TF_BC4: Int32 = 4 as Int32;
pub const KTX_TF_BC5: Int32 = 5 as Int32;
pub const KTX_TTF_BC7_M6_RGB: Int32 = 6 as Int32;
pub const KTX_TTF_BC7_M5_RGBA: Int32 = 6 as Int32;
pub const KTX_TF_BC7_M6_OPAQUE_ONLY: Int32 = 6 as Int32;
pub const KTX_TF_PVRTC1_4_OPAQUE_ONLY: Int32 = 8 as Int32;

// ---- streamType ----
pub const eStreamTypeFile: Int32 = 1 as Int32;
pub const eStreamTypeMemory: Int32 = 2 as Int32;
pub const eStreamTypeCustom: Int32 = 3 as Int32;

// ---- numeric macros ----
pub const KTX_ENDIAN_REF: Int32 = 67305985 as Int32;
pub const KTX_ENDIAN_REF_REV: Int32 = 16909060 as Int32;
pub const KTX_FACESLICE_WHOLE_LEVEL: Int32 = -1 as Int32;
pub const KTX_GL_UNPACK_ALIGNMENT: Int32 = 4 as Int32;
pub const KTX_HEADER_SIZE: Int32 = 64 as Int32;

// ---- VK format subset (lib/vkformat_enum.h) ----
pub const VK_FORMAT_R8G8B8_UNORM: Int32 = 23 as Int32;
pub const VK_FORMAT_R8G8B8A8_UNORM: Int32 = 37 as Int32;
pub const VK_FORMAT_BC1_RGB_UNORM_BLOCK: Int32 = 131 as Int32;
pub const VK_FORMAT_BC3_UNORM_BLOCK: Int32 = 137 as Int32;
pub const VK_FORMAT_BC7_UNORM_BLOCK: Int32 = 145 as Int32;
pub const VK_FORMAT_ETC2_R8G8B8_UNORM_BLOCK: Int32 = 147 as Int32;
pub const VK_FORMAT_ASTC_4x4_UNORM_BLOCK: Int32 = 157 as Int32;
// <<< GENERATED CONSTS

// =========================================================================
// Raw C declarations -- 100% of the pinned public ktx.h surface (93
// functions). These mirror the C signatures for surface coverage and
// documentation; runtime calls go through the x2_* bridge below.
// =========================================================================

extern "C" {
  fn ktxLoadOpenGL(pfnGLGetProcAddress: Int) -> Int32;

  fn ktxTexture_CreateFromStdioStream(stdioStream: Int, createFlags: Int32, newTex: Int) -> Int32;
  fn ktxTexture_CreateFromNamedFile(filename: *UInt8, createFlags: Int32, newTex: Int) -> Int32;
  fn ktxTexture_CreateFromMemory(bytes: *UInt8, size: Int, createFlags: Int32, newTex: Int) -> Int32;
  fn ktxTexture_CreateFromStream(stream: Int, createFlags: Int32, newTex: Int) -> Int32;

  fn ktxTexture_GetData(This: Int) -> *UInt8;
  fn ktxTexture_GetRowPitch(This: Int, level: Int32) -> Int32;
  fn ktxTexture_GetElementSize(This: Int) -> Int32;
  fn ktxTexture_GetDataSize(This: Int) -> Int;
  fn ktxTexture_GLUpload(This: Int, pTexture: Int, pTarget: Int, pGlerror: Int) -> Int32;
  fn ktxTexture_IterateLevelFaces(This: Int, iterCb: Int, userdata: Int) -> Int32;

  fn ktxTexture1_Create(createInfo: Int, storageAllocation: Int32, newTex: Int) -> Int32;
  fn ktxTexture1_CreateFromStdioStream(stdioStream: Int, createFlags: Int32, newTex: Int) -> Int32;
  fn ktxTexture1_CreateFromNamedFile(filename: *UInt8, createFlags: Int32, newTex: Int) -> Int32;
  fn ktxTexture1_CreateFromMemory(bytes: *UInt8, size: Int, createFlags: Int32, newTex: Int) -> Int32;
  fn ktxTexture1_CreateFromStream(stream: Int, createFlags: Int32, newTex: Int) -> Int32;
  fn ktxTexture1_Destroy(This: Int);
  fn ktxTexture1_NeedsTranscoding(This: Int) -> Int32;
  fn ktxTexture1_LoadImageData(This: Int, pBuffer: *UInt8, bufSize: Int) -> Int32;
  fn ktxTexture1_WriteToStdioStream(This: Int, dstsstr: Int) -> Int32;
  fn ktxTexture1_WriteToNamedFile(This: Int, dstname: *UInt8) -> Int32;
  fn ktxTexture1_WriteToMemory(This: Int, bytes: Int, size: Int) -> Int32;
  fn ktxTexture1_WriteToStream(This: Int, dststr: Int) -> Int32;
  fn ktxTexture1_WriteKTX2ToStdioStream(This: Int, dstsstr: Int) -> Int32;
  fn ktxTexture1_WriteKTX2ToNamedFile(This: Int, dstname: *UInt8) -> Int32;
  fn ktxTexture1_WriteKTX2ToMemory(This: Int, bytes: Int, size: Int) -> Int32;
  fn ktxTexture1_WriteKTX2ToStream(This: Int, dststr: Int) -> Int32;

  fn ktxTexture2_Create(createInfo: Int, storageAllocation: Int32, newTex: Int) -> Int32;
  fn ktxTexture2_CreateCopy(orig: Int, newTex: Int) -> Int32;
  fn ktxTexture2_CreateFromStdioStream(stdioStream: Int, createFlags: Int32, newTex: Int) -> Int32;
  fn ktxTexture2_CreateFromNamedFile(filename: *UInt8, createFlags: Int32, newTex: Int) -> Int32;
  fn ktxTexture2_CreateFromMemory(bytes: *UInt8, size: Int, createFlags: Int32, newTex: Int) -> Int32;
  fn ktxTexture2_CreateFromStream(stream: Int, createFlags: Int32, newTex: Int) -> Int32;
  fn ktxTexture2_Destroy(This: Int);
  fn ktxTexture2_CompressBasis(This: Int, quality: Int32) -> Int32;
  fn ktxTexture2_DeflateZstd(This: Int, level: Int32) -> Int32;
  fn ktxTexture2_DeflateZLIB(This: Int, level: Int32) -> Int32;
  fn ktxTexture2_GetComponentInfo(This: Int, numComponents: Int, componentByteLength: Int);
  fn ktxTexture2_GetImageOffset(This: Int, level: Int32, layer: Int32, faceSlice: Int32, pOffset: Int) -> Int32;
  fn ktxTexture2_GetNumComponents(This: Int) -> Int32;
  fn ktxTexture2_GetTransferFunction_e(This: Int) -> Int32;
  fn ktxTexture2_GetOETF_e(This: Int) -> Int32;
  fn ktxTexture2_GetOETF(This: Int) -> Int32;
  fn ktxTexture2_GetColorModel_e(This: Int) -> Int32;
  fn ktxTexture2_GetPremultipliedAlpha(This: Int) -> Int32;
  fn ktxTexture2_GetPrimaries_e(This: Int) -> Int32;
  fn ktxTexture2_NeedsTranscoding(This: Int) -> Int32;
  fn ktxTexture2_SetTransferFunction(This: Int, tf: Int32) -> Int32;
  fn ktxTexture2_SetOETF(This: Int, oetf: Int32) -> Int32;
  fn ktxTexture2_SetPrimaries(This: Int, primaries: Int32) -> Int32;
  fn ktxTexture2_LoadImageData(This: Int, pBuffer: *UInt8, bufSize: Int) -> Int32;
  fn ktxTexture2_LoadDeflatedImageData(This: Int, pBuffer: *UInt8, bufSize: Int) -> Int32;
  fn ktxTexture2_WriteToStdioStream(This: Int, dstsstr: Int) -> Int32;
  fn ktxTexture2_WriteToNamedFile(This: Int, dstname: *UInt8) -> Int32;
  fn ktxTexture2_WriteToMemory(This: Int, bytes: Int, size: Int) -> Int32;
  fn ktxTexture2_WriteToStream(This: Int, dststr: Int) -> Int32;
  fn ktxTexture2_CompressAstcEx(This: Int, params: Int) -> Int32;
  fn ktxTexture2_CompressAstc(This: Int, quality: Int32) -> Int32;
  fn ktxTexture2_DecodeAstc(This: Int) -> Int32;
  fn ktxTexture2_CompressBasisEx(This: Int, params: Int) -> Int32;
  fn ktxTexture2_TranscodeBasis(This: Int, fmt: Int32, transcodeFlags: Int32) -> Int32;

  fn ktxErrorString(error: Int32) -> *UInt8;
  fn ktxSupercompressionSchemeString(scheme: Int32) -> *UInt8;
  fn ktxTranscodeFormatString(format: Int32) -> *UInt8;

  fn ktxHashList_Create(ppHl: Int) -> Int32;
  fn ktxHashList_CreateCopy(ppHl: Int, orig: Int) -> Int32;
  fn ktxHashList_Construct(pHl: Int);
  fn ktxHashList_ConstructCopy(pHl: Int, orig: Int);
  fn ktxHashList_Destroy(head: Int);
  fn ktxHashList_Destruct(head: Int);
  fn ktxHashList_AddKVPair(pHead: Int, key: *UInt8, valueLen: Int32, value: Int) -> Int32;
  fn ktxHashList_DeleteEntry(pHead: Int, pEntry: Int) -> Int32;
  fn ktxHashList_DeleteKVPair(pHead: Int, key: *UInt8) -> Int32;
  fn ktxHashList_FindEntry(pHead: Int, key: *UInt8, ppEntry: Int) -> Int32;
  fn ktxHashList_FindValue(pHead: Int, key: *UInt8, pValueLen: Int, pValue: Int) -> Int32;
  fn ktxHashList_Next(entry: Int) -> Int;
  fn ktxHashList_Sort(pHead: Int) -> Int32;
  fn ktxHashList_Serialize(pHead: Int, kvdLen: Int, kvd: Int) -> Int32;
  fn ktxHashList_Deserialize(pHead: Int, kvdLen: Int32, kvd: Int) -> Int32;
  fn ktxHashListEntry_GetKey(This: Int, pKeyLen: Int, ppKey: Int) -> Int32;
  fn ktxHashListEntry_GetValue(This: Int, pValueLen: Int, ppValue: Int) -> Int32;

  fn ktxPrintInfoForStdioStream(stdioStream: Int) -> Int32;
  fn ktxPrintInfoForNamedFile(filename: *UInt8) -> Int32;
  fn ktxPrintInfoForMemory(bytes: *UInt8, size: Int) -> Int32;
  fn ktxPrintKTX1InfoTextForStream(stream: Int) -> Int32;
  fn ktxPrintKTX2InfoTextForMemory(bytes: *UInt8, size: Int) -> Int32;
  fn ktxPrintKTX2InfoTextForNamedFile(filename: *UInt8) -> Int32;
  fn ktxPrintKTX2InfoTextForStdioStream(stdioStream: Int) -> Int32;
  fn ktxPrintKTX2InfoTextForStream(stream: Int) -> Int32;
  fn ktxPrintKTX2InfoJSONForMemory(bytes: *UInt8, size: Int, base_indent: Int32, indent_width: Int32, minified: Int32) -> Int32;
  fn ktxPrintKTX2InfoJSONForNamedFile(filename: *UInt8, base_indent: Int32, indent_width: Int32, minified: Int32) -> Int32;
  fn ktxPrintKTX2InfoJSONForStdioStream(stdioStream: Int, base_indent: Int32, indent_width: Int32, minified: Int32) -> Int32;
  fn ktxPrintKTX2InfoJSONForStream(stream: Int, base_indent: Int32, indent_width: Int32, minified: Int32) -> Int32;
}

// =========================================================================
// x2_* bridge (src/ktx2_bridge.c) -- the runtime path. Handles travel in
// caller-owned 8-byte slots; all other outputs are caller-owned byte slots
// read back little-endian.
// =========================================================================

extern "C" {
  fn x2_symbol_count() -> Int32;
  fn x2_symbol_name(index: Int32, dst: *UInt8, capacity: Int32) -> Int32;
  fn x2_symbol_lookup(name: *UInt8, name_len: Int32) -> Int32;

  fn x2_texture_create(kind: Int32, vk_format: Int32, gl_internalformat: Int32,
                       width: Int32, height: Int32, depth: Int32,
                       levels: Int32, layers: Int32, faces: Int32,
                       is_array: Int32, generate_mipmaps: Int32,
                       handle: *UInt8) -> Int32;
  fn x2_texture_destroy(kind: Int32, handle: *UInt8) -> Int32;
  fn x2_texture1_set_gl(handle: *UInt8, gl_format: Int32, gl_type: Int32) -> Int32;
  fn x2_set_image(handle: *UInt8, kind: Int32, level: Int32, layer: Int32,
                  face_slice: Int32, src: *UInt8, src_len: Int32) -> Int32;
  fn x2_write_memory(handle: *UInt8, kind: Int32, dst: *UInt8,
                     capacity: Int32, out_len: *UInt8) -> Int32;
  fn x2_read_info(src: *UInt8, src_len: Int32, out: *UInt8) -> Int32;
  fn x2_read_level(src: *UInt8, src_len: Int32, level: Int32, dst: *UInt8,
                   capacity: Int32, out_len: *UInt8) -> Int32;

  fn x2_roundtrip_probe(mode: Int32, width: Int32, height: Int32,
                        out: *UInt8, generated: *UInt8, generated_capacity: Int32,
                        image: *UInt8, image_len: Int32,
                        expected: *UInt8, expected_len: Int32) -> Int32;
  fn x2_named_file_probe(out: *UInt8, image: *UInt8, image_len: Int32,
                         path_out: *UInt8, path_capacity: Int32) -> Int32;
  fn x2_deflated_probe(mode: Int32, out: *UInt8, raw: *UInt8,
                       raw_capacity: Int32, inflated: *UInt8,
                       inflated_capacity: Int32, image: *UInt8,
                       image_len: Int32) -> Int32;
  fn x2_ktx1_probe(out: *UInt8, image: *UInt8, image_len: Int32,
                   ktx1_bytes: *UInt8, ktx1_capacity: Int32,
                   ktx2_bytes: *UInt8, ktx2_capacity: Int32,
                   probe_buf: *UInt8, probe_capacity: Int32) -> Int32;
  fn x2_stream_probe(out: *UInt8, payload: *UInt8, payload_capacity: Int32,
                     image: *UInt8, image_len: Int32) -> Int32;
  fn x2_basis_probe(mode: Int32, out: *UInt8, payload: *UInt8,
                    payload_capacity: Int32, image: *UInt8,
                    image_len: Int32) -> Int32;
  fn x2_astc_probe(out: *UInt8, payload: *UInt8, payload_capacity: Int32,
                   image: *UInt8, image_len: Int32, decoded: *UInt8,
                   decoded_capacity: Int32) -> Int32;
  fn x2_hashlist_probe(out: *UInt8) -> Int32;
  fn x2_c_string(selector: Int32, arg: Int32, dst: *UInt8, capacity: Int32,
                 out_len: *UInt8) -> Int32;
  fn x2_gl_probe(out: *UInt8) -> Int32;
  fn x2_corrupt_probe(src: *UInt8, src_len: Int32, out: *UInt8) -> Int32;
}

// =========================================================================
// Slot helpers (little-endian reads over caller-owned buffers).
// =========================================================================

/// Allocate an n-byte caller-owned slot (zero-filled) for the probe
/// interfaces (records, handle tokens, string targets).
/// Complexity: O(n).
pub fn ktx2_slot(n: Int) -> Vec[UInt8]
  requires: n > 0
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

/// Read a little-endian u32 at `off` from an owned slot.
/// Complexity: O(1).
pub fn ktx2_u32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let b0 = buf[off] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

/// Read a little-endian u64 at `off` from an owned slot.
/// Complexity: O(1).
pub fn ktx2_u64(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 8
{
  let lo = ktx2_u32(buf, off);
  let hi = ktx2_u32(buf, off + 4);
  return lo | (hi << 32);
}

// =========================================================================
// Fixtures (deterministic test images and buffers).
// =========================================================================

/// 4x4 RGB8 test image (48 bytes): pixel (x,y) = (16*x, 16*y, 128).
/// Complexity: O(w*h).
pub fn ktx2_test_image_rgb8() -> Vec[UInt8]
  requires: true
{
  var img: Vec[UInt8] = Vec[UInt8].new();
  var y: Int = 0;
  while y < 4 {
    var x: Int = 0;
    while x < 4 {
      img.push((x * 16) as UInt8);
      img.push((y * 16) as UInt8);
      img.push(128 as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  return img;
}

/// 4x4 RGBA8 test image (64 bytes): pixel (x,y) = (16*x, 16*y, 128, 255).
/// Complexity: O(w*h).
pub fn ktx2_test_image_rgba8() -> Vec[UInt8]
  requires: true
{
  var img: Vec[UInt8] = Vec[UInt8].new();
  var y: Int = 0;
  while y < 4 {
    var x: Int = 0;
    while x < 4 {
      img.push((x * 16) as UInt8);
      img.push((y * 16) as UInt8);
      img.push(128 as UInt8);
      img.push(255 as UInt8);
      x = x + 1;
    }
    y = y + 1;
  }
  return img;
}

// =========================================================================
// Texture lifecycle (owned handle slots; no XIOM-side pointer casts).
// =========================================================================

pub type Ktx2TextureSpec = {
  kind: Int;                 // 1 = ktxTexture1, 2 = ktxTexture2
  vk_format: Int;            // ktxTexture2: VkFormat; ktxTexture1: ignored
  gl_internal_format: Int;   // ktxTexture1: glInternalformat
  width: Int;
  height: Int;
  depth: Int;                // 1 for 2D (libktx requires >= 1)
  levels: Int;
  layers: Int;               // 1 for non-array textures
  faces: Int;                // 1 or 6
  is_array: Bool;
  generate_mipmaps: Bool;
}

/// Create an empty texture. On success the 8-byte `handle` slot holds the
/// opaque pointer (kept as an opaque token; never interpreted by XIOM).
/// Complexity: O(levels).
pub fn ktx2_create(spec: Ktx2TextureSpec, handle: &mut Vec[UInt8]) -> Result[Unit, Int]
  requires: spec.kind == 1 || spec.kind == 2
  requires: spec.width >= 1
  requires: spec.height >= 1
  requires: spec.levels >= 1
  requires: spec.faces == 1 || spec.faces == 6
  requires: handle.len() >= 8
{
  var depth = spec.depth;
  if depth < 1 { depth = 1; }
  var layers = spec.layers;
  if layers < 1 { layers = 1; }
  var is_array_i = 0;
  if spec.is_array { is_array_i = 1; }
  var gen_mips_i = 0;
  if spec.generate_mipmaps { gen_mips_i = 1; }
  unsafe {
    let rc = x2_texture_create(spec.kind as Int32, spec.vk_format as Int32,
                               spec.gl_internal_format as Int32,
                               spec.width as Int32, spec.height as Int32,
                               depth as Int32, spec.levels as Int32,
                               layers as Int32, spec.faces as Int32,
                               is_array_i as Int32, gen_mips_i as Int32,
                               handle.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(rc);
    }
    return Ok(());
  }
}

/// Destroy a texture and zero its handle slot (double destroy returns Err).
/// Complexity: O(1).
pub fn ktx2_destroy(kind: Int, handle: &mut Vec[UInt8]) -> Result[Unit, Int]
  requires: kind == 1 || kind == 2
  requires: handle.len() >= 8
{
  unsafe {
    let rc = x2_texture_destroy(kind as Int32, handle.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(rc);
    }
    return Ok(());
  }
}

/// Set the KTX1 GL format trim (glFormat/glType) after ktx2_create(kind=1).
/// Complexity: O(1).
pub fn ktx2_texture1_set_gl(handle: &mut Vec[UInt8], gl_format: Int, gl_type: Int) -> Result[Unit, Int]
  requires: handle.len() >= 8
{
  unsafe {
    let rc = x2_texture1_set_gl(handle.as_mut_ptr(), gl_format as Int32,
                                gl_type as Int32) as Int;
    if rc != 0 {
      return Err(rc);
    }
    return Ok(());
  }
}

/// Write one image (level/layer/faceSlice) from an owned buffer.
/// Complexity: O(image).
pub fn ktx2_set_image(handle: &mut Vec[UInt8], kind: Int, level: Int,
                      layer: Int, face_slice: Int, src: &mut Vec[UInt8]) -> Result[Unit, Int]
  requires: kind == 1 || kind == 2
  requires: handle.len() >= 8
  requires: src.len() > 0
{
  unsafe {
    let rc = x2_set_image(handle.as_mut_ptr(), kind as Int32, level as Int32,
                          layer as Int32, face_slice as Int32, src.as_mut_ptr(),
                          src.len() as Int32) as Int;
    if rc != 0 {
      return Err(rc);
    }
    return Ok(());
  }
}

/// Serialize the texture into `dst` (KTX1 or KTX2 per `kind`). Ok carries
/// the byte count written; Err carries the KTX status (a too-small `dst`
/// yields KTX_FILE_OVERFLOW with the needed size in `len_slot`, u64 LE).
/// Complexity: O(texture).
pub fn ktx2_write_memory(handle: &mut Vec[UInt8], kind: Int, dst: &mut Vec[UInt8], len_slot: &mut Vec[UInt8]) -> Result[Int, Int]
  requires: kind == 1 || kind == 2
  requires: handle.len() >= 8
  requires: dst.len() > 0
  requires: len_slot.len() >= 8
{
  unsafe {
    let rc = x2_write_memory(handle.as_mut_ptr(), kind as Int32,
                             dst.as_mut_ptr(), dst.len() as Int32,
                             len_slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(rc);
    }
    return Ok(ktx2_u64(len_slot, 0));
  }
}

/// Copy one level's image bytes out of a serialized KTX1/KTX2 buffer into
/// `dst`; Ok carries the byte count, Err the KTX status.
/// Complexity: O(level).
pub fn ktx2_read_level(src: &mut Vec[UInt8], level: Int, dst: &mut Vec[UInt8], len_slot: &mut Vec[UInt8]) -> Result[Int, Int]
  requires: src.len() > 0
  requires: dst.len() > 0
  requires: len_slot.len() >= 8
{
  unsafe {
    let rc = x2_read_level(src.as_mut_ptr(), src.len() as Int32,
                           level as Int32, dst.as_mut_ptr(),
                           dst.len() as Int32, len_slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(rc);
    }
    return Ok(ktx2_u64(len_slot, 0));
  }
}

/// True when an 8-byte handle slot holds no texture (all bytes zero).
/// Complexity: O(1).
pub fn ktx2_handle_is_null(handle: &Vec[UInt8]) -> Bool
  requires: handle.len() >= 8
{
  return (handle[0] as Int) == 0 and (handle[1] as Int) == 0
    and (handle[2] as Int) == 0 and (handle[3] as Int) == 0
    and (handle[4] as Int) == 0 and (handle[5] as Int) == 0
    and (handle[6] as Int) == 0 and (handle[7] as Int) == 0;
}

// =========================================================================
// Surface probes.
// =========================================================================

/// Number of functions in the declared-surface symbol table (93 at the pin).
/// Complexity: O(1).
pub fn ktx2_symbol_count() -> Int
  requires: true
{
  return unsafe { x2_symbol_count() as Int };
}

/// Name of the i-th symbol (into `buf`, NUL terminated); -1 out of range.
/// Complexity: O(1).
pub fn ktx2_symbol_name(index: Int, buf: &mut Vec[UInt8]) -> Int
  requires: index >= 0
  requires: buf.len() >= 64
{
  return unsafe { x2_symbol_name(index as Int32, buf.as_mut_ptr(), buf.len() as Int32) as Int };
}

/// Index of an exact symbol name in the declared-surface table; -1 absent.
/// Complexity: O(93).
pub fn ktx2_symbol_lookup(name: Str) -> Int
  requires: name.len() > 0
{
  return unsafe {
    x2_symbol_lookup(name.c_str(), name.len() as Int32) as Int
  };
}

pub type Ktx2Info = {
  status: Int;
  class_id: Int;
  vk_format: Int;
  base_width: Int;
  base_height: Int;
  base_depth: Int;
  num_levels: Int;
  num_layers: Int;
  num_faces: Int;
  is_array: Bool;
  is_cubemap: Bool;
  is_compressed: Bool;
  generate_mipmaps: Bool;
  supercompression: Int;
  num_components: Int;
  needs_transcoding: Bool;
  data_size: Int;
  component_byte_length: Int;
  format_code: Int;
  gl_format: Int;
  gl_type: Int;
}

fn ktx2_info_from_slot(slot: &Vec[UInt8], status: Int) -> Ktx2Info
  requires: slot.len() >= 128
{
  return Ktx2Info{
    status: status,
    class_id: ktx2_u32(slot, 0),
    vk_format: ktx2_u32(slot, 4),
    base_width: ktx2_u32(slot, 8),
    base_height: ktx2_u32(slot, 12),
    base_depth: ktx2_u32(slot, 16),
    num_levels: ktx2_u32(slot, 20),
    num_layers: ktx2_u32(slot, 24),
    num_faces: ktx2_u32(slot, 28),
    is_array: ktx2_u32(slot, 32) != 0,
    is_cubemap: ktx2_u32(slot, 36) != 0,
    is_compressed: ktx2_u32(slot, 40) != 0,
    generate_mipmaps: ktx2_u32(slot, 44) != 0,
    supercompression: ktx2_u32(slot, 48),
    num_components: ktx2_u32(slot, 52),
    needs_transcoding: ktx2_u32(slot, 56) != 0,
    data_size: ktx2_u64(slot, 72),
    component_byte_length: ktx2_u32(slot, 80),
    format_code: ktx2_u32(slot, 84),
    gl_format: ktx2_u32(slot, 88),
    gl_type: ktx2_u32(slot, 92)
  };
}

/// Parse a KTX1/KTX2 buffer and return the info record. Ok only when the
/// buffer parses; Err carries the KTX status for corrupt input.
/// Complexity: O(header + kv).
pub fn ktx2_read_info(src: &mut Vec[UInt8], slot: &mut Vec[UInt8]) -> Result[Ktx2Info, Int]
  requires: src.len() > 0
  requires: slot.len() >= 128
{
  unsafe {
    let rc = x2_read_info(src.as_mut_ptr(), src.len() as Int32, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(rc);
    }
    return Ok(ktx2_info_from_slot(slot, rc));
  }
}

pub type Ktx2Roundtrip = {
  write_rc: Int;
  write_len: Int;
  read_rc: Int;
  class_id: Int;
  vk_format: Int;
  num_levels: Int;
  data_size: Int;
  level0_len: Int;
  level0_mismatch: Bool;
  iter_rc: Int;
  iter_images: Int;
  iter_bytes: Int;
  iter_first_byte: Int;
  supercompression: Int;
  deflate_hint: Int;
  row_pitch: Int;
  element_size: Int;
  copy_rc: Int;
  copy_levels: Int;
  tf_e: Int;
  oetf_e: Int;
  oetf: Int;
  color_model: Int;
  premultiplied: Bool;
  primaries_e: Int;
  set_tf_rc: Int;
  set_oetf_rc: Int;
  set_primaries_rc: Int;
  num_components: Int;
}

fn ktx2_roundtrip_from_slot(slot: &Vec[UInt8], top: Int) -> Ktx2Roundtrip
  requires: slot.len() >= 128
{
  return Ktx2Roundtrip{
    write_rc: ktx2_u32(slot, 0),
    write_len: ktx2_u32(slot, 4),
    read_rc: ktx2_u32(slot, 8),
    class_id: ktx2_u32(slot, 12),
    vk_format: ktx2_u32(slot, 16),
    num_levels: ktx2_u32(slot, 20),
    data_size: ktx2_u64(slot, 24),
    level0_len: ktx2_u32(slot, 32),
    level0_mismatch: ktx2_u32(slot, 36) != 0,
    iter_rc: ktx2_u32(slot, 40),
    iter_images: ktx2_u32(slot, 44),
    iter_bytes: ktx2_u64(slot, 48),
    iter_first_byte: ktx2_u32(slot, 56),
    supercompression: ktx2_u32(slot, 60),
    deflate_hint: ktx2_u32(slot, 64),
    row_pitch: ktx2_u32(slot, 72),
    element_size: ktx2_u32(slot, 76),
    copy_rc: ktx2_u32(slot, 80),
    copy_levels: ktx2_u32(slot, 84),
    tf_e: ktx2_u32(slot, 88),
    oetf_e: ktx2_u32(slot, 92),
    oetf: ktx2_u32(slot, 96),
    color_model: ktx2_u32(slot, 100),
    premultiplied: ktx2_u32(slot, 104) != 0,
    primaries_e: ktx2_u32(slot, 108),
    set_tf_rc: ktx2_u32(slot, 112),
    set_oetf_rc: ktx2_u32(slot, 116),
    set_primaries_rc: ktx2_u32(slot, 120),
    num_components: ktx2_u32(slot, 124)
  };
}

/// In-memory KTX2 write/read round trip. mode 0 = plain, 1 = ZSTD
/// supercompression, 2 = ZLIB supercompression. `image` is the source
/// pixels; `generated` (>= write_len) receives the serialized KTX2 bytes;
/// `slot` (128 bytes) is the probe record. Top-level Err is a KTX status
/// for a setup/overflow failure; per-step codes are in the result fields.
/// Complexity: O(pixels).
pub fn ktx2_roundtrip(mode: Int, image: &mut Vec[UInt8], generated: &mut Vec[UInt8], slot: &mut Vec[UInt8]) -> Result[Ktx2Roundtrip, Int]
  requires: mode >= 0
  requires: mode <= 2
  requires: image.len() == 48
  requires: generated.len() >= 4096
  requires: slot.len() >= 128
{
  unsafe {
    let rc = x2_roundtrip_probe(mode as Int32, 4 as Int32, 4 as Int32,
                                slot.as_mut_ptr(), generated.as_mut_ptr(),
                                generated.len() as Int32,
                                image.as_mut_ptr(), image.len() as Int32,
                                image.as_mut_ptr(), image.len() as Int32) as Int;
    if rc != 0 {
      return Err(rc);
    }
    return Ok(ktx2_roundtrip_from_slot(slot, rc));
  }
}

pub type Ktx2Deflated = {
  deflate_rc: Int;
  write_rc: Int;
  scheme: Int;
  deflated_size: Int;
  raw_load_rc: Int;
  raw_match: Bool;
  pdata_null: Bool;
  raw_head: Int;
  inflate_read_rc: Int;
  inflated_mismatch: Bool;
  data_size_after: Int;
  is_compressed: Bool;
  file_bytes: Int;
  removed: Bool;
  loaded_head: Int;
  mismatch_index: Int;
  mismatch_raw_byte: Int;
  mismatch_loaded_byte: Int;
}

/// Deflated-image load path (file-stream textures only, the upstream
/// precondition for ktxTexture2_LoadDeflatedImageData): deflate -> write to
/// %TEMP% -> fresh read #1 LoadDeflatedImageData (compare against the
/// captured deflated bytes; the call consumes the stream) -> fresh read #2
/// with LOAD_IMAGE_DATA (compare inflated pixels). mode 0 = ZSTD, 1 = ZLIB.
/// `raw` receives the captured deflated bytes; `inflated` (>= 4 KiB) is the
/// deflated-load target. The temp file is removed.
/// Complexity: O(pixels).
pub fn ktx2_deflated_probe(mode: Int, image: &mut Vec[UInt8], raw: &mut Vec[UInt8], inflated: &mut Vec[UInt8], slot: &mut Vec[UInt8]) -> Result[Ktx2Deflated, Int]
  requires: mode >= 0
  requires: mode <= 1
  requires: image.len() == 48
  requires: raw.len() >= 4096
  requires: inflated.len() >= 4096
  requires: slot.len() >= 96
{
  unsafe {
    let rc = x2_deflated_probe(mode as Int32, slot.as_mut_ptr(),
                               raw.as_mut_ptr(), raw.len() as Int32,
                               inflated.as_mut_ptr(), inflated.len() as Int32,
                               image.as_mut_ptr(), image.len() as Int32) as Int;
    if rc != 0 {
      return Err(rc);
    }
    return Ok(Ktx2Deflated{
      deflate_rc: ktx2_u32(slot, 0),
      write_rc: ktx2_u32(slot, 4),
      scheme: ktx2_u32(slot, 8),
      deflated_size: ktx2_u32(slot, 12),
      raw_load_rc: ktx2_u32(slot, 16),
      raw_match: ktx2_u32(slot, 20) == 0,
      pdata_null: ktx2_u32(slot, 24) != 0,
      raw_head: ktx2_u32(slot, 28),
      inflate_read_rc: ktx2_u32(slot, 32),
      inflated_mismatch: ktx2_u32(slot, 36) != 0,
      data_size_after: ktx2_u64(slot, 40),
      is_compressed: ktx2_u32(slot, 48) != 0,
      file_bytes: ktx2_u32(slot, 52),
      removed: ktx2_u32(slot, 56) != 0,
      loaded_head: ktx2_u32(slot, 60),
      mismatch_index: ktx2_u32(slot, 64),
      mismatch_raw_byte: ktx2_u32(slot, 68),
      mismatch_loaded_byte: ktx2_u32(slot, 72)
    });
  }
}

pub type Ktx2NamedFile = {
  create_rc: Int;
  write_rc: Int;
  read_rc: Int;
  class_id: Int;
  data_size: Int;
  file_bytes: Int;
  removed: Bool;
  path_len: Int;
}

/// WriteToNamedFile / CreateFromNamedFile round trip in %TEMP%.
/// Complexity: O(pixels).
pub fn ktx2_named_file_probe(image: &mut Vec[UInt8], slot: &mut Vec[UInt8], path_buf: &mut Vec[UInt8]) -> Result[Ktx2NamedFile, Int]
  requires: image.len() == 48
  requires: slot.len() >= 64
  requires: path_buf.len() >= 512
{
  unsafe {
    let rc = x2_named_file_probe(slot.as_mut_ptr(), image.as_mut_ptr(),
                                 image.len() as Int32, path_buf.as_mut_ptr(),
                                 path_buf.len() as Int32) as Int;
    if rc != 0 {
      return Err(rc);
    }
    return Ok(Ktx2NamedFile{
      create_rc: ktx2_u32(slot, 0),
      write_rc: ktx2_u32(slot, 4),
      read_rc: ktx2_u32(slot, 8),
      class_id: ktx2_u32(slot, 12),
      data_size: ktx2_u64(slot, 16),
      file_bytes: ktx2_u32(slot, 24),
      removed: ktx2_u32(slot, 28) != 0,
      path_len: ktx2_u32(slot, 32)
    });
  }
}

pub type Ktx2Ktx1 = {
  create_rc: Int;
  set_rc: Int;
  write_rc: Int;
  write_len: Int;
  ktx2_rc: Int;
  ktx2_len: Int;
  read_rc: Int;
  class_id: Int;
  data_size: Int;
  load_rc: Int;
  cmp_mismatch: Bool;
  needs_transcoding: Bool;
  gl_internalformat: Int;
  gl_format: Int;
  gl_type: Int;
  ktx2_read_rc: Int;
  ktx2_super: Int;
  ktx2_vkformat: Int;
  ktx2_level0_len: Int;
}

/// KTX1 create/write/read round trip plus ktxTexture1_WriteKTX2ToMemory
/// conversion. `ktx1_bytes`/`ktx2_bytes` receive the serializations,
/// `probe_buf` (>= 48 bytes) receives the loaded image bytes.
/// Complexity: O(pixels).
pub fn ktx2_ktx1_probe(image: &mut Vec[UInt8], ktx1_bytes: &mut Vec[UInt8], ktx2_bytes: &mut Vec[UInt8], probe_buf: &mut Vec[UInt8], slot: &mut Vec[UInt8]) -> Result[Ktx2Ktx1, Int]
  requires: image.len() == 48
  requires: ktx1_bytes.len() >= 4096
  requires: ktx2_bytes.len() >= 4096
  requires: probe_buf.len() >= 48
  requires: slot.len() >= 96
{
  unsafe {
    let rc = x2_ktx1_probe(slot.as_mut_ptr(), image.as_mut_ptr(),
                           image.len() as Int32,
                           ktx1_bytes.as_mut_ptr(), ktx1_bytes.len() as Int32,
                           ktx2_bytes.as_mut_ptr(), ktx2_bytes.len() as Int32,
                           probe_buf.as_mut_ptr(), probe_buf.len() as Int32) as Int;
    if rc != 0 {
      return Err(rc);
    }
    return Ok(Ktx2Ktx1{
      create_rc: ktx2_u32(slot, 0),
      set_rc: ktx2_u32(slot, 4),
      write_rc: ktx2_u32(slot, 8),
      write_len: ktx2_u32(slot, 12),
      ktx2_rc: ktx2_u32(slot, 16),
      ktx2_len: ktx2_u32(slot, 20),
      read_rc: ktx2_u32(slot, 24),
      class_id: ktx2_u32(slot, 28),
      data_size: ktx2_u64(slot, 32),
      load_rc: ktx2_u32(slot, 40),
      cmp_mismatch: ktx2_u32(slot, 44) != 0,
      needs_transcoding: ktx2_u32(slot, 48) != 0,
      gl_internalformat: ktx2_u32(slot, 52),
      gl_format: ktx2_u32(slot, 56),
      gl_type: ktx2_u32(slot, 60),
      ktx2_read_rc: ktx2_u32(slot, 64),
      ktx2_super: ktx2_u32(slot, 68),
      ktx2_vkformat: ktx2_u32(slot, 72),
      ktx2_level0_len: ktx2_u32(slot, 76)
    });
  }
}

pub type Ktx2Stream = {
  wstream_rc: Int;
  wstream_len: Int;
  rstream_rc: Int;
  rstream_class: Int;
  rstream_data_size: Int;
  rstream_mismatch: Bool;
  stdio_write_rc: Int;
  stdio_base_read_rc: Int;
  stdio_class: Int;
  stdio2_read_rc: Int;
  stdio2_data_size: Int;
  stdio_rewind_ok: Bool;
  ktx1_wstream_rc: Int;
  ktx1_wstream_len: Int;
  ktx1_rstream_rc: Int;
  ktx1_class: Int;
  ktx1_ktx2stream_rc: Int;
  ktx1_ktx2stream_len: Int;
  ktx2_from_ktx1stream_rc: Int;
  ktx2_from_ktx1_data_size: Int;
  stream_getsize: Int;
}

/// ktxStream (custom memory stream) + tmpfile stdio round trips for KTX2
/// and KTX1, including the KTX1->KTX2 stream conversion.
/// Complexity: O(pixels).
pub fn ktx2_stream_probe(image: &mut Vec[UInt8], payload: &mut Vec[UInt8], slot: &mut Vec[UInt8]) -> Result[Ktx2Stream, Int]
  requires: image.len() == 48
  requires: payload.len() >= 4096
  requires: slot.len() >= 96
{
  unsafe {
    let rc = x2_stream_probe(slot.as_mut_ptr(), payload.as_mut_ptr(),
                             payload.len() as Int32, image.as_mut_ptr(),
                             image.len() as Int32) as Int;
    if rc != 0 {
      return Err(rc);
    }
    return Ok(Ktx2Stream{
      wstream_rc: ktx2_u32(slot, 0),
      wstream_len: ktx2_u32(slot, 4),
      rstream_rc: ktx2_u32(slot, 8),
      rstream_class: ktx2_u32(slot, 12),
      rstream_data_size: ktx2_u64(slot, 16),
      rstream_mismatch: ktx2_u32(slot, 24) != 0,
      stdio_write_rc: ktx2_u32(slot, 28),
      stdio_base_read_rc: ktx2_u32(slot, 32),
      stdio_class: ktx2_u32(slot, 36),
      stdio2_read_rc: ktx2_u32(slot, 40),
      stdio2_data_size: ktx2_u64(slot, 44),
      stdio_rewind_ok: ktx2_u32(slot, 52) != 0,
      ktx1_wstream_rc: ktx2_u32(slot, 56),
      ktx1_wstream_len: ktx2_u32(slot, 60),
      ktx1_rstream_rc: ktx2_u32(slot, 64),
      ktx1_class: ktx2_u32(slot, 68),
      ktx1_ktx2stream_rc: ktx2_u32(slot, 72),
      ktx1_ktx2stream_len: ktx2_u32(slot, 76),
      ktx2_from_ktx1stream_rc: ktx2_u32(slot, 80),
      ktx2_from_ktx1_data_size: ktx2_u64(slot, 84),
      stream_getsize: ktx2_u32(slot, 92)
    });
  }
}

pub type Ktx2Basis = {
  encode_rc: Int;
  needs_transcoding: Bool;
  transcode_rc: Int;
  vk_format_after: Int;
  super_after: Int;
  data_size_after: Int;
  num_levels: Int;
  write2_rc: Int;
  write2_len: Int;
  level0_size: Int;
  num_components: Int;
  transcode2_rc: Int;
  super_final: Int;
  is_compressed: Bool;
  payload_vk_format: Int;
}

/// Basis encode + transcode probe. mode 0: ETC1S -> BC1_RGB, 1: UASTC ->
/// BC7_RGBA, 2: ETC1S -> ETC1_RGB, 3: ETC1S -> RGBA32. `payload`
/// (>= 4096) receives the serialized transcoded KTX2 for modes 0/1.
/// Complexity: O(pixels) at encode.
pub fn ktx2_basis_probe(mode: Int, image: &mut Vec[UInt8], payload: &mut Vec[UInt8], slot: &mut Vec[UInt8]) -> Result[Ktx2Basis, Int]
  requires: mode >= 0
  requires: mode <= 3
  requires: image.len() == 48
  requires: payload.len() >= 4096
  requires: slot.len() >= 128
{
  unsafe {
    let rc = x2_basis_probe(mode as Int32, slot.as_mut_ptr(),
                            payload.as_mut_ptr(), payload.len() as Int32,
                            image.as_mut_ptr(), image.len() as Int32) as Int;
    if rc != 0 {
      return Err(rc);
    }
    return Ok(Ktx2Basis{
      encode_rc: ktx2_u32(slot, 0),
      needs_transcoding: ktx2_u32(slot, 4) != 0,
      transcode_rc: ktx2_u32(slot, 8),
      vk_format_after: ktx2_u32(slot, 12),
      super_after: ktx2_u32(slot, 16),
      data_size_after: ktx2_u64(slot, 20),
      num_levels: ktx2_u32(slot, 28),
      write2_rc: ktx2_u32(slot, 32),
      write2_len: ktx2_u32(slot, 36),
      level0_size: ktx2_u32(slot, 40),
      num_components: ktx2_u32(slot, 44),
      transcode2_rc: ktx2_u32(slot, 48),
      super_final: ktx2_u32(slot, 52),
      is_compressed: ktx2_u32(slot, 56) != 0,
      payload_vk_format: ktx2_u32(slot, 60)
    });
  }
}

pub type Ktx2Astc = {
  compress_rc: Int;
  vk_after_compress: Int;
  is_compressed: Bool;
  data_size_after_compress: Int;
  decode_rc: Int;
  vk_after_decode: Int;
  data_size_after_decode: Int;
  level0_after_compress: Int;
  level0_after_decode: Int;
  write_rc: Int;
  write_len: Int;
  block_dim: Int;
  quality: Int;
  decoded_len: Int;
  decode_matches_input: Bool;
}

/// ASTC encode (4x4 LDR, fastest) + decode round trip on a 4x4 RGBA8
/// image. `payload` receives the serialized compressed KTX2, `decoded`
/// (>= 64) the decoded pixels.
/// Complexity: O(pixels) at encode.
pub fn ktx2_astc_probe(image: &mut Vec[UInt8], payload: &mut Vec[UInt8], decoded: &mut Vec[UInt8], slot: &mut Vec[UInt8]) -> Result[Ktx2Astc, Int]
  requires: image.len() == 64
  requires: payload.len() >= 4096
  requires: decoded.len() >= 64
  requires: slot.len() >= 64
{
  unsafe {
    let rc = x2_astc_probe(slot.as_mut_ptr(), payload.as_mut_ptr(),
                           payload.len() as Int32, image.as_mut_ptr(),
                           image.len() as Int32, decoded.as_mut_ptr(),
                           decoded.len() as Int32) as Int;
    if rc != 0 {
      return Err(rc);
    }
    return Ok(Ktx2Astc{
      compress_rc: ktx2_u32(slot, 0),
      vk_after_compress: ktx2_u32(slot, 4),
      is_compressed: ktx2_u32(slot, 8) != 0,
      data_size_after_compress: ktx2_u32(slot, 12),
      decode_rc: ktx2_u32(slot, 16),
      vk_after_decode: ktx2_u32(slot, 20),
      data_size_after_decode: ktx2_u32(slot, 24),
      level0_after_compress: ktx2_u32(slot, 28),
      level0_after_decode: ktx2_u32(slot, 32),
      write_rc: ktx2_u32(slot, 36),
      write_len: ktx2_u32(slot, 40),
      block_dim: ktx2_u32(slot, 44),
      quality: ktx2_u32(slot, 48),
      decoded_len: ktx2_u32(slot, 52),
      decode_matches_input: ktx2_u32(slot, 56) != 0
    });
  }
}

pub type Ktx2Hashlist = {
  create_rc: Int;
  add_rc: Int;
  find_rc: Int;
  value_len: Int;
  value0: Int;
  value1: Int;
  value2: Int;
  value3: Int;
  next_count: Int;
  sort_rc: Int;
  ser_rc: Int;
  ser_len: Int;
  deser_rc: Int;
  find2_rc: Int;
  value2_len: Int;
  value20: Int;
  value21: Int;
  value22: Int;
  value23: Int;
  getkey_rc: Int;
  key_len: Int;
  key0: Int;
  key1: Int;
  key2: Int;
  key3: Int;
  getval_rc: Int;
  delete_rc: Int;
  destroy_rc: Int;
  delete_entry_rc: Int;
  copy_rc: Int;
  copy_entries: Int;
  construct_ok: Int;
  destruct_ok: Int;
}

/// Hash-list metadata API exercise (create/add/find/next/sort/serialize/
/// deserialize/entry getters/delete/destroy/construct/destruct/copy).
/// Complexity: O(entries).
pub fn ktx2_hashlist_probe(slot: &mut Vec[UInt8]) -> Result[Ktx2Hashlist, Int]
  requires: slot.len() >= 96
{
  unsafe {
    let rc = x2_hashlist_probe(slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(rc);
    }
    return Ok(Ktx2Hashlist{
      create_rc: ktx2_u32(slot, 0),
      add_rc: ktx2_u32(slot, 4),
      find_rc: ktx2_u32(slot, 8),
      value_len: ktx2_u32(slot, 12),
      value0: slot[16] as Int,
      value1: slot[17] as Int,
      value2: slot[18] as Int,
      value3: slot[19] as Int,
      next_count: ktx2_u32(slot, 20),
      sort_rc: ktx2_u32(slot, 24),
      ser_rc: ktx2_u32(slot, 28),
      ser_len: ktx2_u32(slot, 32),
      deser_rc: ktx2_u32(slot, 36),
      find2_rc: ktx2_u32(slot, 40),
      value2_len: ktx2_u32(slot, 44),
      value20: slot[48] as Int,
      value21: slot[49] as Int,
      value22: slot[50] as Int,
      value23: slot[51] as Int,
      getkey_rc: ktx2_u32(slot, 52),
      key_len: ktx2_u32(slot, 56),
      key0: slot[60] as Int,
      key1: slot[61] as Int,
      key2: slot[62] as Int,
      key3: slot[63] as Int,
      getval_rc: ktx2_u32(slot, 64),
      delete_rc: ktx2_u32(slot, 68),
      destroy_rc: ktx2_u32(slot, 72),
      delete_entry_rc: ktx2_u32(slot, 76),
      copy_rc: ktx2_u32(slot, 80),
      copy_entries: ktx2_u32(slot, 84),
      construct_ok: ktx2_u32(slot, 88),
      destruct_ok: ktx2_u32(slot, 92)
    });
  }
}

/// Copy a libktx static string into an owned buffer: selector 0 =
/// ktxErrorString(code), 1 = ktxSupercompressionSchemeString(scheme),
/// 2 = ktxTranscodeFormatString(fmt). Ok carries the copied byte count
/// (excluding NUL).
/// Complexity: O(len).
pub fn ktx2_c_string(selector: Int, arg: Int, dst: &mut Vec[UInt8], slot: &mut Vec[UInt8]) -> Result[Int, Int]
  requires: selector >= 0
  requires: selector <= 2
  requires: dst.len() >= 128
  requires: slot.len() >= 8
{
  unsafe {
    let rc = x2_c_string(selector as Int32, arg as Int32, dst.as_mut_ptr(),
                         dst.len() as Int32, slot.as_mut_ptr()) as Int;
    if rc != 0 {
      return Err(rc);
    }
    return Ok(ktx2_u64(slot, 0));
  }
}

pub type Ktx2Gl = {
  load_rc: Int;
  upload_rc: Int;
  gl_error: Int;
  texture: Int;
  target: Int;
  class_id: Int;
}

/// ktxLoadOpenGL(NULL) plus a GL upload attempt. In a console process there
/// is no current GL context, so the upload returns a typed KTX error
/// (KTX_GL_ERROR) rather than succeeding. Complexity: O(load).
pub fn ktx2_gl_probe(slot: &mut Vec[UInt8]) -> Ktx2Gl
  requires: slot.len() >= 32
{
  unsafe {
    let rc = x2_gl_probe(slot.as_mut_ptr()) as Int;
    return Ktx2Gl{
      load_rc: rc,
      upload_rc: ktx2_u32(slot, 4),
      gl_error: ktx2_u32(slot, 8),
      texture: ktx2_u32(slot, 12),
      target: ktx2_u32(slot, 16),
      class_id: ktx2_u32(slot, 20)
    };
  }
}

pub type Ktx2Corrupt = {
  status: Int;
  class_id: Int;
  data_size: Int;
  num_levels: Int;
}

/// Parse a (possibly corrupt) KTX buffer; `status` carries the KTX status
/// (0 on success). Complexity: O(buffer).
pub fn ktx2_corrupt_probe(src: &mut Vec[UInt8], slot: &mut Vec[UInt8]) -> Ktx2Corrupt
  requires: src.len() >= 0
  requires: slot.len() >= 32
{
  unsafe {
    let rc = x2_corrupt_probe(src.as_mut_ptr(), src.len() as Int32,
                              slot.as_mut_ptr()) as Int;
    return Ktx2Corrupt{
      status: rc,
      class_id: ktx2_u32(slot, 4),
      data_size: ktx2_u32(slot, 8),
      num_levels: ktx2_u32(slot, 12)
    };
  }
}
