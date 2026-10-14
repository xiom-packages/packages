// xiom.nis -- C ABI bridge over the vendored NVIDIA Image Scaling SDK v1.0.3
// (MIT; see vendor/LICENSE.txt and PROVENANCE.md).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// This file is OUR code.  It is the only translation unit that includes the
// vendored SDK header (vendor/NIS/NIS_Config.h) and it exposes a small
// extern "C" surface to the xiom.nis module:
//
//   * config ABI facts (sizeof / used-field bytes),
//   * NVScalerUpdateConfig / NVSharpenUpdateConfig over an XIOM-owned byte
//     buffer: the config is built in a local NISConfig and memcpy'd out, so
//     the caller's buffer needs no alignment and XIOM never reads/writes
//     foreign memory (B-20/B-24),
//   * the NISOptimizer dispatch getters,
//   * coefficient-table copies (f32 and fp16, the four upstream tables),
//   * scalar field reads (f32/u32) from the caller's own config bytes.
//
// Nothing is linked from upstream: the SDK is header-only and the bridge
// holds no state, no pointers, and performs no allocation.  Upstream reads
// (NIS_Config.h) are the single source of the algorithm constants; SPEC.md
// section 2 pins the vendored bytes.

#include "../vendor/NIS/NIS_Config.h"

#include <cstddef>
#include <cstring>

namespace {

// NISConfig is a flat run of 4-byte scalars: 18 floats, then 8 uint32, then
// 2 more floats (NIS_Config.h; mirrored by the HLSL cbuffer in
// NIS_Main.hlsl and asserted by the conformance suite).
constexpr int kConfigFieldCount = 28;
constexpr int kConfigFloatFields = 18;
constexpr int kConfigUIntFields = 8;

constexpr int kHdrModeNone = 0;
constexpr int kHdrModeLinear = 1;
constexpr int kHdrModePQ = 2;

bool valid_hdr_mode(int hdr_mode) {
  return hdr_mode == kHdrModeNone || hdr_mode == kHdrModeLinear || hdr_mode == kHdrModePQ;
}

// The four coefficient tables (64 phases x 8 taps; f32 in coef_scale/coef_usm,
// IEEE half bits in coef_scale_fp16/coef_usm_fp16).  Selector:
//   0 = coef_scale f32, 1 = coef_usm f32, 2 = coef_scale fp16, 3 = coef_usm fp16.
const void* coefficient_table(int table, int* out_bytes) {
  switch (table) {
    case 0: *out_bytes = (int)sizeof(coef_scale);      return coef_scale;
    case 1: *out_bytes = (int)sizeof(coef_usm);        return coef_usm;
    case 2: *out_bytes = (int)sizeof(coef_scale_fp16); return coef_scale_fp16;
    case 3: *out_bytes = (int)sizeof(coef_usm_fp16);   return coef_usm_fp16;
    default: *out_bytes = 0; return nullptr;
  }
}

}  // namespace

extern "C" {

// sizeof(NISConfig): 112 bytes of fields rounded up to the 256-byte alignment
// (what the upstream samples use for the GPU constant-buffer size).
int nis_bridge_config_size() {
  return (int)sizeof(NISConfig);
}

// Bytes of the struct actually written by the update functions (fields only).
int nis_bridge_config_used_size() {
  return (int)(offsetof(NISConfig, reserved1) + sizeof(float));
}

// Build an NVScaler (upscale+sharpen) config into `out` (>= config_size
// bytes, XIOM-owned).  Returns 1 on upstream success (params accepted),
// 0 otherwise (out-of-range scale, zero viewport, bad HDR mode, null out).
int nis_bridge_scaler_update(unsigned char* out, float sharpness,
                             unsigned int ivp_x, unsigned int ivp_y,
                             unsigned int ivp_w, unsigned int ivp_h,
                             unsigned int it_w, unsigned int it_h,
                             unsigned int ovp_x, unsigned int ovp_y,
                             unsigned int ovp_w, unsigned int ovp_h,
                             unsigned int ot_w, unsigned int ot_h,
                             int hdr_mode) {
  if (out == nullptr || !valid_hdr_mode(hdr_mode)) {
    return 0;
  }
  NISConfig cfg{};
  const bool ok = NVScalerUpdateConfig(cfg, sharpness,
                                       ivp_x, ivp_y, ivp_w, ivp_h,
                                       it_w, it_h,
                                       ovp_x, ovp_y, ovp_w, ovp_h,
                                       ot_w, ot_h,
                                       (NISHDRMode)hdr_mode);
  std::memcpy(out, &cfg, sizeof(NISConfig));
  return ok ? 1 : 0;
}

// Build an NVSharpen (sharpen-only) config into `out`.  Semantics mirror
// NVSharpenUpdateConfig: the output viewport equals the input viewport
// (scale 1.0).  Returns 1/0 like above.
int nis_bridge_sharpen_update(unsigned char* out, float sharpness,
                              unsigned int ivp_x, unsigned int ivp_y,
                              unsigned int ivp_w, unsigned int ivp_h,
                              unsigned int it_w, unsigned int it_h,
                              unsigned int ovp_x, unsigned int ovp_y,
                              int hdr_mode) {
  if (out == nullptr || !valid_hdr_mode(hdr_mode)) {
    return 0;
  }
  NISConfig cfg{};
  const bool ok = NVSharpenUpdateConfig(cfg, sharpness,
                                        ivp_x, ivp_y, ivp_w, ivp_h,
                                        it_w, it_h,
                                        ovp_x, ovp_y,
                                        (NISHDRMode)hdr_mode);
  std::memcpy(out, &cfg, sizeof(NISConfig));
  return ok ? 1 : 0;
}

// NISOptimizer dispatch values.  arch: 0 = NVIDIA_Generic, 1 = AMD_Generic,
// 2 = Intel_Generic, 3 = NVIDIA_Generic_fp16 (NISGPUArchitecture).
unsigned int nis_bridge_optimal_block_width(int is_upscaling, int arch) {
  NISOptimizer opt(is_upscaling != 0, (NISGPUArchitecture)arch);
  return opt.GetOptimalBlockWidth();
}

unsigned int nis_bridge_optimal_block_height(int is_upscaling, int arch) {
  NISOptimizer opt(is_upscaling != 0, (NISGPUArchitecture)arch);
  return opt.GetOptimalBlockHeight();
}

unsigned int nis_bridge_optimal_thread_group_size(int is_upscaling, int arch) {
  NISOptimizer opt(is_upscaling != 0, (NISGPUArchitecture)arch);
  return opt.GetOptimalThreadGroupSize();
}

// Copy one coefficient table into `out` (out_cap bytes).  Returns the number
// of bytes written, or -1 when the selector or the capacity is invalid.
int nis_bridge_copy_coefficients(int table, unsigned char* out, int out_cap) {
  if (out == nullptr || out_cap < 0) {
    return -1;
  }
  int bytes = 0;
  const void* src = coefficient_table(table, &bytes);
  if (src == nullptr || out_cap < bytes) {
    return -1;
  }
  std::memcpy(out, src, (size_t)bytes);
  return bytes;
}

// Read field `field` (0..27) of the caller's config bytes as f32.
// Fields 0..17 and 26..27 are floats; others read as 0.0f.
float nis_bridge_config_f32(const unsigned char* bytes, int field) {
  if (bytes == nullptr || field < 0 || field >= kConfigFieldCount) {
    return 0.0f;
  }
  const bool is_float = field < kConfigFloatFields || field >= kConfigFloatFields + kConfigUIntFields;
  if (!is_float) {
    return 0.0f;
  }
  float v = 0.0f;
  std::memcpy(&v, bytes + (size_t)field * 4u, sizeof(v));
  return v;
}

// Read field `field` (0..27) of the caller's config bytes as u32.
// Fields 18..25 are uint32; all other fields read as 0.
unsigned int nis_bridge_config_u32(const unsigned char* bytes, int field) {
  if (bytes == nullptr || field < kConfigFloatFields ||
      field >= kConfigFloatFields + kConfigUIntFields) {
    return 0u;
  }
  unsigned int v = 0u;
  std::memcpy(&v, bytes + (size_t)field * 4u, sizeof(v));
  return v;
}

// Read the f32 at `byte_offset` of any caller-owned byte buffer (the
// coefficient tables land in XIOM-owned Vec[UInt8] buffers).
float nis_bridge_buf_f32(const unsigned char* bytes, int byte_offset) {
  if (bytes == nullptr || byte_offset < 0 || (byte_offset % 4) != 0) {
    return 0.0f;
  }
  float v = 0.0f;
  std::memcpy(&v, bytes + (size_t)byte_offset, sizeof(v));
  return v;
}

}  // extern "C"
