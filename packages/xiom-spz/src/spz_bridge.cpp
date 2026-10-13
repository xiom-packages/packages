// XIOM -- xiom.spz flat bridge over the vendored spz C++ API.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// DESIGN (docs/BINDINGS-COMPILER-FINDINGS.md discipline, toolchain v0.64.4):
//   * This is the ONE compile unit in the package with foreign-code contact
//     (G5 confinement); the XIOM modules declare only these `xspz_*` symbols.
//   * No XIOM code ever dereferences a foreign pointer (B-20/B-24): the bridge
//     copies results into XIOM-owned buffers. Float data crosses as an owned
//     `Vec[Float32]` workspace with the layout documented in SPEC.md.
//   * No pointer arithmetic in XIOM (B-17): out-params are one owned slot each;
//     metadata slots are read byte-indexed on the XIOM side.
//   * No handle casts (B-25) and no bare `null` to C (B-23): every upstream
//     entry point is wrapped here with scalars/buffers only, so XIOM never
//     materializes a pointer it must trust.
//   * Errors are flat negative codes (B-26 shapes are avoided on the XIOM
//     side). `spz::loadSpz*` signals failure with an empty cloud (or an empty
//     `PackedGaussians`); the bridge pre-validates the container header so a
//     typed code can be returned instead of a silent empty result.
//
// WORKSPACE LAYOUT (floats, n = num_points, dim = dimForDegree(sh_degree)):
//   [0, 3n)              positions (xyz)
//   [3n, 6n)             scales (log scale)
//   [6n, 10n)            rotations (xyzw)
//   [10n, 11n)           alphas (inverse logistics)
//   [11n, 14n)           colors (rgb sh0 coefficients)
//   [14n, 14n + 3*dim*n) spherical harmonics (rgb per coefficient)
//   total = 14n + 3*dim*n

#include "../vendor/spz/load-spz.h"
#include "../vendor/spz/splat-types.h"

#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>

// --- Error codes (mirrored in src/spz.xi; keep in sync) --------------------
//  0 success
// -1 bad arguments (null buffer / size mismatch)
// -2 not an SPZ file (bad magic)
// -3 unsupported header version
// -4 decompression failed (zstd / gzip / stream sizes)
// -5 truncated input
// -6 malformed header (point count, sh degree, stream count, TOC)
// -7 output capacity is too small (needed count in the slot when provided)
// -8 internal error (allocation / serialization)
namespace {
constexpr int32_t kErrBadArgs = -1;
constexpr int32_t kErrMagic = -2;
constexpr int32_t kErrVersion = -3;
constexpr int32_t kErrDecompress = -4;
constexpr int32_t kErrTruncated = -5;
constexpr int32_t kErrBadHeader = -6;
constexpr int32_t kErrCapacity = -7;
constexpr int32_t kErrInternal = -8;

// Sane upper bound for a point count derived from an untrusted header; a
// corrupt 0x7FFFFFFF count must fail closed instead of attempting a 100+ GB
// allocation inside upstream's resize().
constexpr uint32_t kMaxPoints = 50000000u;

constexpr int32_t kCoordUnspecified = 0;
constexpr int32_t kCoordMax = 8;

int32_t dim_for_degree(int32_t degree) {
  switch (degree) {
    case 0: return 0;
    case 1: return 3;
    case 2: return 8;
    case 3: return 15;
    case 4: return 24;
    default: return -1;
  }
}

void write_u64_le(uint8_t *p, uint64_t v) {
  for (int i = 0; i < 8; ++i) p[i] = static_cast<uint8_t>((v >> (8 * i)) & 0xff);
}

int32_t clamp_coord(int32_t c) {
  if (c < kCoordUnspecified || c > kCoordMax) return kCoordUnspecified;
  return c;
}

// Pre-validate the container so failures carry a typed code. Mirrors the
// acceptance logic in load-spz.cc (NGSP header + legacy gzip sniff).
int32_t validate_container(const uint8_t *data, int64_t size) {
  if (data == nullptr && size != 0) return kErrBadArgs;
  if (size < 4) return kErrTruncated;
  uint32_t magic = 0;
  std::memcpy(&magic, data, sizeof(magic));
  if (magic == spz::NGSP_MAGIC) {
    if (size < 32) return kErrTruncated;
    uint32_t version = 0;
    std::memcpy(&version, data + 4, 4);
    if (version < static_cast<uint32_t>(spz::MIN_ZSTD_SPZ_HEADER_VERSION) ||
        version > static_cast<uint32_t>(spz::LATEST_SPZ_HEADER_VERSION)) {
      return kErrVersion;
    }
    uint32_t num_points = 0;
    std::memcpy(&num_points, data + 8, 4);
    if (num_points == 0 || num_points > kMaxPoints) return kErrBadHeader;
    const uint8_t sh_degree = data[12];
    if (dim_for_degree(static_cast<int32_t>(sh_degree)) < 0) return kErrBadHeader;
    const uint8_t num_streams = data[15];
    if (num_streams < 1 || num_streams > 6) return kErrBadHeader;
    uint32_t toc = 0;
    std::memcpy(&toc, data + 16, 4);
    if (toc < 32) return kErrBadHeader;
    const uint64_t toc_end = static_cast<uint64_t>(toc) + static_cast<uint64_t>(num_streams) * 16u;
    if (toc_end > static_cast<uint64_t>(size)) return kErrTruncated;
    return 0;
  }
  if (size >= 2 && data[0] == 0x1f && data[1] == 0x8b) {
    // Legacy gzip single-stream container (versions 1-3).
    return 0;
  }
  return kErrMagic;
}

// Load + validate; returns 0 and a non-empty PackedGaussians on success.
int32_t load_packed_checked(const uint8_t *data, int64_t size, spz::PackedGaussians *out) {
  const int32_t valid = validate_container(data, size);
  if (valid != 0) return valid;
  if (size > 0 && data == nullptr) return kErrBadArgs;
  spz::PackedGaussians packed = spz::loadSpzPacked(data, static_cast<size_t>(size));
  if (packed.numPoints <= 0) return kErrDecompress;
  *out = packed;
  return 0;
}

int64_t work_floats(int64_t num_points, int64_t sh_degree) {
  const int32_t dim = dim_for_degree(static_cast<int32_t>(sh_degree));
  if (num_points < 0 || dim < 0) return -1;
  return 14 * num_points + 3 * static_cast<int64_t>(dim) * num_points;
}

bool read_work(const float *work, int64_t work_cap, int64_t num_points, int64_t sh_degree,
               spz::GaussianCloud *cloud) {
  const int64_t need = work_floats(num_points, sh_degree);
  if (need < 0 || work == nullptr || work_cap < need) return false;
  const int64_t o_scales = 3 * num_points;
  const int64_t o_rot = 6 * num_points;
  const int64_t o_alpha = 10 * num_points;
  const int64_t o_color = 11 * num_points;
  const int64_t o_sh = 14 * num_points;
  cloud->numPoints = static_cast<int32_t>(num_points);
  cloud->shDegree = static_cast<int32_t>(sh_degree);
  cloud->positions.assign(work, work + o_scales);
  cloud->scales.assign(work + o_scales, work + o_rot);
  cloud->rotations.assign(work + o_rot, work + o_alpha);
  cloud->alphas.assign(work + o_alpha, work + o_color);
  cloud->colors.assign(work + o_color, work + o_sh);
  cloud->sh.assign(work + o_sh, work + need);
  return true;
}

int64_t write_work(const spz::GaussianCloud &cloud, float *work, int64_t work_cap,
                   int64_t *out_num_points, int64_t *out_sh_degree) {
  const int64_t n = cloud.numPoints;
  const int64_t need = work_floats(n, cloud.shDegree);
  if (need < 0) return kErrInternal;
  if (out_num_points != nullptr) *out_num_points = n;
  if (out_sh_degree != nullptr) *out_sh_degree = cloud.shDegree;
  if (work == nullptr || work_cap < need) return kErrCapacity;
  const int64_t o_scales = 3 * n;
  const int64_t o_rot = 6 * n;
  const int64_t o_alpha = 10 * n;
  const int64_t o_color = 11 * n;
  const int64_t o_sh = 14 * n;
  std::memcpy(work, cloud.positions.data(), static_cast<size_t>(o_scales) * sizeof(float));
  std::memcpy(work + o_scales, cloud.scales.data(), static_cast<size_t>(o_scales) * sizeof(float));
  std::memcpy(work + o_rot, cloud.rotations.data(),
              static_cast<size_t>(o_alpha - o_rot) * sizeof(float));
  std::memcpy(work + o_alpha, cloud.alphas.data(),
              static_cast<size_t>(o_color - o_alpha) * sizeof(float));
  std::memcpy(work + o_color, cloud.colors.data(),
              static_cast<size_t>(o_sh - o_color) * sizeof(float));
  std::memcpy(work + o_sh, cloud.sh.data(), cloud.sh.size() * sizeof(float));
  return 0;
}

int64_t copy_bytes(const std::vector<uint8_t> &src, uint8_t *out, int64_t cap) {
  const int64_t need = static_cast<int64_t>(src.size());
  if (need > 0 && (out == nullptr || cap < need)) return need;
  if (need > 0) std::memcpy(out, src.data(), static_cast<size_t>(need));
  return need;
}

spz::PackOptions pack_options(int64_t version, int64_t from_coord, int64_t sh1_bits,
                              int64_t sh_rest_bits) {
  spz::PackOptions o;
  o.version = static_cast<uint32_t>(version);
  o.from = static_cast<spz::CoordinateSystem>(clamp_coord(static_cast<int32_t>(from_coord)));
  o.sh1Bits = static_cast<uint8_t>(sh1_bits);
  o.shRestBits = static_cast<uint8_t>(sh_rest_bits);
  return o;
}

int32_t fill_meta_slot(const spz::PackedGaussians &packed, uint8_t *slot8) {
  if (slot8 != nullptr) {
    write_u64_le(slot8 + 0, static_cast<uint64_t>(packed.version));
    write_u64_le(slot8 + 8, static_cast<uint64_t>(static_cast<uint32_t>(packed.numPoints)));
    write_u64_le(slot8 + 16, static_cast<uint64_t>(static_cast<uint32_t>(packed.shDegree)));
    write_u64_le(slot8 + 24, static_cast<uint64_t>(static_cast<uint32_t>(packed.fractionalBits)));
    write_u64_le(slot8 + 32, packed.antialiased ? 1u : 0u);
    write_u64_le(slot8 + 40, packed.usesQuaternionSmallestThree ? 1u : 0u);
    write_u64_le(slot8 + 48, packed.usesFloat16() ? 1u : 0u);
    write_u64_le(slot8 + 56, 0u);
  }
  return 0;
}

std::string path_string(const uint8_t *path) {
  if (path == nullptr) return std::string();
  return std::string(reinterpret_cast<const char *>(path));
}
}  // namespace

extern "C" {

// --- meta / constants -------------------------------------------------------

int32_t xspz_constants(uint8_t *out8) {
  if (out8 == nullptr) return kErrBadArgs;
  const int64_t values[8] = {
      spz::LATEST_SPZ_HEADER_VERSION,
      spz::MIN_ZSTD_SPZ_HEADER_VERSION,
      spz::MIN_SMALLEST_THREE_QUATERNIONS_VERSION,
      spz::SH_MAX_DEGREE,
      spz::SH_MAX_COEFFS,
      spz::DEFAULT_SH1_BITS,
      spz::DEFAULT_SH_REST_BITS,
      static_cast<int32_t>(spz::NGSP_MAGIC),
  };
  for (int i = 0; i < 8; ++i) write_u64_le(out8 + i * 8, static_cast<uint64_t>(values[i]));
  return 0;
}

int32_t xspz_has_extension_support() { return spz::hasExtensionSupport() ? 1 : 0; }

int32_t xspz_coordinate_values(uint8_t *out9) {
  if (out9 == nullptr) return kErrBadArgs;
  for (int i = 0; i <= kCoordMax; ++i) {
    write_u64_le(out9 + i * 8, static_cast<uint64_t>(i));
  }
  return 0;
}

int32_t xspz_axes_match(int32_t a, int32_t b, uint8_t *out3) {
  if (out3 == nullptr) return kErrBadArgs;
  const std::array<bool, 3> m = spz::axesMatch(
      static_cast<spz::CoordinateSystem>(clamp_coord(a)),
      static_cast<spz::CoordinateSystem>(clamp_coord(b)));
  for (int i = 0; i < 3; ++i) write_u64_le(out3 + i * 8, m[i] ? 1u : 0u);
  return 0;
}

int32_t xspz_coordinate_converter(int32_t from, int32_t to, float *out30) {
  if (out30 == nullptr) return kErrBadArgs;
  const spz::CoordinateConverter c = spz::coordinateConverter(
      static_cast<spz::CoordinateSystem>(clamp_coord(from)),
      static_cast<spz::CoordinateSystem>(clamp_coord(to)));
  for (int i = 0; i < 3; ++i) out30[i] = c.flipP[i];
  for (int i = 0; i < 3; ++i) out30[3 + i] = c.flipQ[i];
  for (int i = 0; i < 24; ++i) out30[6 + i] = c.flipSh[i];
  return 0;
}

// --- pack / unpack ----------------------------------------------------------

// Returns the number of bytes required (>= 0; copied into `out` when
// out_cap >= required) or a negative error code.
int64_t xspz_pack(const float *work, int64_t work_cap, int64_t num_points, int64_t sh_degree,
                  int64_t antialiased, int64_t version, int64_t from_coord, int64_t sh1_bits,
                  int64_t sh_rest_bits, uint8_t *out, int64_t out_cap) {
  const int64_t need_in = work_floats(num_points, sh_degree);
  if (need_in < 0 || num_points <= 0) return kErrBadArgs;
  if (version < 1 || version > spz::LATEST_SPZ_HEADER_VERSION) return kErrVersion;
  if (sh1_bits < 1 || sh1_bits > 8 || sh_rest_bits < 1 || sh_rest_bits > 8) return kErrBadArgs;
  spz::GaussianCloud cloud;
  if (!read_work(work, work_cap, num_points, sh_degree, &cloud)) return kErrBadArgs;
  cloud.antialiased = antialiased != 0;
  spz::PackOptions o = pack_options(version, from_coord, sh1_bits, sh_rest_bits);
  std::vector<uint8_t> bytes;
  if (!spz::saveSpz(cloud, o, &bytes)) return kErrInternal;
  return copy_bytes(bytes, out, out_cap);
}

// Metadata for a container (version, numPoints, shDegree, fractionalBits,
// antialiased, usesQuaternionSmallestThree, usesFloat16, reserved).
int32_t xspz_load_packed(const uint8_t *data, int64_t size, uint8_t *slot8) {
  spz::PackedGaussians packed;
  const int32_t rc = load_packed_checked(data, size, &packed);
  if (rc != 0) return rc;
  return fill_meta_slot(packed, slot8);
}

// Full unpack into the flat workspace; slot4 receives
// (numPoints, shDegree, antialiased, version).
int32_t xspz_unpack(const uint8_t *data, int64_t size, int64_t to_coord, uint8_t *slot4,
                    float *work, int64_t work_cap) {
  spz::PackedGaussians packed;
  const int32_t rc = load_packed_checked(data, size, &packed);
  if (rc != 0) return rc;
  spz::UnpackOptions o;
  o.to = static_cast<spz::CoordinateSystem>(clamp_coord(static_cast<int32_t>(to_coord)));
  const spz::GaussianCloud cloud = spz::loadSpz(data, static_cast<size_t>(size), o);
  if (cloud.numPoints <= 0) return kErrDecompress;
  int64_t n = 0;
  int64_t degree = 0;
  const int64_t wrc = write_work(cloud, work, work_cap, &n, &degree);
  if (slot4 != nullptr) {
    uint8_t *p = slot4;
    write_u64_le(p + 0, static_cast<uint64_t>(n));
    write_u64_le(p + 8, static_cast<uint64_t>(degree));
    write_u64_le(p + 16, cloud.antialiased ? 1u : 0u);
    write_u64_le(p + 24, 0u);  // reserved
  }
  return static_cast<int32_t>(wrc == 0 ? 0 : wrc);
}

// --- packed accessors -------------------------------------------------------

// 92 raw bytes of PackedGaussian::at(index) (layout pinned by static_assert).
int32_t xspz_packed_gaussian(const uint8_t *data, int64_t size, int64_t index, uint8_t *out92,
                             int64_t out_cap) {
  spz::PackedGaussians packed;
  const int32_t rc = load_packed_checked(data, size, &packed);
  if (rc != 0) return rc;
  if (index < 0 || index >= packed.numPoints) return kErrBadArgs;
  if (out92 == nullptr || out_cap < 92) return kErrCapacity;
  static_assert(sizeof(spz::PackedGaussian) == 92,
                "PackedGaussian layout changed upstream; update the bridge and SPEC");
  const spz::PackedGaussian g = packed.at(static_cast<int32_t>(index));
  std::memcpy(out92, &g, sizeof(g));
  return 0;
}

// Flattened PackedGaussian::unpack -> 86 floats:
// position(3), rotation(4), scale(3), color(3), alpha(1), shR(24), shG(24), shB(24).
int32_t xspz_packed_gaussian_unpack(const uint8_t *data, int64_t size, int64_t index,
                                    int64_t to_coord, float *out86, int64_t out_cap) {
  spz::PackedGaussians packed;
  const int32_t rc = load_packed_checked(data, size, &packed);
  if (rc != 0) return rc;
  if (index < 0 || index >= packed.numPoints) return kErrBadArgs;
  if (out86 == nullptr || out_cap < 86) return kErrCapacity;
  static_assert(sizeof(spz::UnpackedGaussian) == 86 * sizeof(float),
                "UnpackedGaussian layout changed upstream; update the bridge and SPEC");
  const spz::CoordinateConverter c = spz::coordinateConverter(
      spz::CoordinateSystem::RUB,
      static_cast<spz::CoordinateSystem>(clamp_coord(static_cast<int32_t>(to_coord))));
  const spz::UnpackedGaussian u = packed.unpack(static_cast<int32_t>(index), c);
  int32_t k = 0;
  for (int i = 0; i < 3; ++i) out86[k++] = u.position[i];
  for (int i = 0; i < 4; ++i) out86[k++] = u.rotation[i];
  for (int i = 0; i < 3; ++i) out86[k++] = u.scale[i];
  for (int i = 0; i < 3; ++i) out86[k++] = u.color[i];
  out86[k++] = u.alpha;
  for (int i = 0; i < spz::SH_MAX_COEFFS; ++i) out86[k++] = u.shR[i];
  for (int i = 0; i < spz::SH_MAX_COEFFS; ++i) out86[k++] = u.shG[i];
  for (int i = 0; i < spz::SH_MAX_COEFFS; ++i) out86[k++] = u.shB[i];
  return 0;
}

// --- file in/out ------------------------------------------------------------

int32_t xspz_save_file(const uint8_t *path, const float *work, int64_t work_cap,
                       int64_t num_points, int64_t sh_degree, int64_t antialiased,
                       int64_t version, int64_t from_coord, int64_t sh1_bits,
                       int64_t sh_rest_bits) {
  if (path == nullptr) return kErrBadArgs;
  const int64_t need_in = work_floats(num_points, sh_degree);
  if (need_in < 0 || num_points <= 0) return kErrBadArgs;
  if (version < 1 || version > spz::LATEST_SPZ_HEADER_VERSION) return kErrVersion;
  spz::GaussianCloud cloud;
  if (!read_work(work, work_cap, num_points, sh_degree, &cloud)) return kErrBadArgs;
  cloud.antialiased = antialiased != 0;
  const spz::PackOptions o = pack_options(version, from_coord, sh1_bits, sh_rest_bits);
  if (!spz::saveSpz(cloud, o, path_string(path))) return kErrInternal;
  return 0;
}

int32_t xspz_load_file(const uint8_t *path, int64_t to_coord, uint8_t *slot4, float *work,
                       int64_t work_cap) {
  if (path == nullptr) return kErrBadArgs;
  spz::UnpackOptions o;
  o.to = static_cast<spz::CoordinateSystem>(clamp_coord(static_cast<int32_t>(to_coord)));
  const spz::GaussianCloud cloud = spz::loadSpz(path_string(path), o);
  if (cloud.numPoints <= 0) return kErrDecompress;
  int64_t n = 0;
  int64_t degree = 0;
  const int64_t wrc = write_work(cloud, work, work_cap, &n, &degree);
  if (slot4 != nullptr) {
    uint8_t *p = slot4;
    write_u64_le(p + 0, static_cast<uint64_t>(n));
    write_u64_le(p + 8, static_cast<uint64_t>(degree));
    write_u64_le(p + 16, cloud.antialiased ? 1u : 0u);
    write_u64_le(p + 24, 0u);
  }
  return static_cast<int32_t>(wrc == 0 ? 0 : wrc);
}

int32_t xspz_save_ply(const uint8_t *path, const float *work, int64_t work_cap,
                      int64_t num_points, int64_t sh_degree, int64_t antialiased,
                      int64_t version, int64_t from_coord, int64_t sh1_bits,
                      int64_t sh_rest_bits) {
  if (path == nullptr) return kErrBadArgs;
  const int64_t need_in = work_floats(num_points, sh_degree);
  if (need_in < 0 || num_points <= 0) return kErrBadArgs;
  spz::GaussianCloud cloud;
  if (!read_work(work, work_cap, num_points, sh_degree, &cloud)) return kErrBadArgs;
  cloud.antialiased = antialiased != 0;
  const spz::PackOptions o = pack_options(version, from_coord, sh1_bits, sh_rest_bits);
  if (!spz::saveSplatToPly(cloud, o, path_string(path))) return kErrInternal;
  return 0;
}

int32_t xspz_load_ply(const uint8_t *path, int64_t to_coord, uint8_t *slot4, float *work,
                      int64_t work_cap) {
  if (path == nullptr) return kErrBadArgs;
  spz::UnpackOptions o;
  o.to = static_cast<spz::CoordinateSystem>(clamp_coord(static_cast<int32_t>(to_coord)));
  const spz::GaussianCloud cloud = spz::loadSplatFromPly(path_string(path), o);
  if (cloud.numPoints <= 0) return kErrDecompress;
  int64_t n = 0;
  int64_t degree = 0;
  const int64_t wrc = write_work(cloud, work, work_cap, &n, &degree);
  if (slot4 != nullptr) {
    uint8_t *p = slot4;
    write_u64_le(p + 0, static_cast<uint64_t>(n));
    write_u64_le(p + 8, static_cast<uint64_t>(degree));
    write_u64_le(p + 16, cloud.antialiased ? 1u : 0u);
    write_u64_le(p + 24, 0u);
  }
  return static_cast<int32_t>(wrc == 0 ? 0 : wrc);
}

// --- serialize / gzip -------------------------------------------------------

int64_t xspz_serialize_packed(const uint8_t *data, int64_t size, uint8_t *out, int64_t out_cap) {
  spz::PackedGaussians packed;
  const int32_t rc = load_packed_checked(data, size, &packed);
  if (rc != 0) return rc;
  std::ostringstream ss;
  spz::serializePackedGaussians(packed, &ss);
  const std::string s = ss.str();
  const std::vector<uint8_t> bytes(s.begin(), s.end());
  return copy_bytes(bytes, out, out_cap);
}

int64_t xspz_compress_gzipped(const uint8_t *data, int64_t size, uint8_t *out, int64_t out_cap) {
  if (size < 0 || (size > 0 && data == nullptr)) return kErrBadArgs;
  std::vector<uint8_t> bytes;
  if (!spz::compressGzipped(data, static_cast<size_t>(size), &bytes)) return kErrInternal;
  return copy_bytes(bytes, out, out_cap);
}

// --- GaussianCloud methods --------------------------------------------------

// GaussianCloud::data() -- copies the six float buffers (counts + payload)
// into `out_work`; returns 0 or a negative code.
int32_t xspz_cloud_data(const float *work, int64_t work_cap, int64_t num_points,
                        int64_t sh_degree, int64_t antialiased, float *out_work,
                        int64_t out_cap) {
  spz::GaussianCloud cloud;
  if (!read_work(work, work_cap, num_points, sh_degree, &cloud)) return kErrBadArgs;
  cloud.antialiased = antialiased != 0;
  const GaussianCloudData d = cloud.data();
  const int64_t total = static_cast<int64_t>(d.positions.count) +
                        static_cast<int64_t>(d.scales.count) +
                        static_cast<int64_t>(d.rotations.count) +
                        static_cast<int64_t>(d.alphas.count) +
                        static_cast<int64_t>(d.colors.count) + static_cast<int64_t>(d.sh.count);
  if (out_work == nullptr || out_cap < total) {
    delete[] d.positions.data;
    delete[] d.scales.data;
    delete[] d.rotations.data;
    delete[] d.alphas.data;
    delete[] d.colors.data;
    delete[] d.sh.data;
    return kErrCapacity;
  }
  const SpzFloatBuffer bufs[6] = {d.positions, d.scales, d.rotations,
                                       d.alphas, d.colors, d.sh};
  float *cursor = out_work;
  for (int b = 0; b < 6; ++b) {
    if (bufs[b].count > 0) std::memcpy(cursor, bufs[b].data, bufs[b].count * sizeof(float));
    cursor += bufs[b].count;
  }
  delete[] d.positions.data;
  delete[] d.scales.data;
  delete[] d.rotations.data;
  delete[] d.alphas.data;
  delete[] d.colors.data;
  delete[] d.sh.data;
  return 0;
}

// GaussianCloud::convertCoordinates(from, to), in place over the workspace.
int32_t xspz_cloud_convert(float *work, int64_t work_cap, int64_t num_points, int64_t sh_degree,
                           int64_t from_coord, int64_t to_coord) {
  spz::GaussianCloud cloud;
  if (!read_work(work, work_cap, num_points, sh_degree, &cloud)) return kErrBadArgs;
  cloud.convertCoordinates(static_cast<spz::CoordinateSystem>(clamp_coord(static_cast<int32_t>(from_coord))),
                           static_cast<spz::CoordinateSystem>(clamp_coord(static_cast<int32_t>(to_coord))));
  return static_cast<int32_t>(write_work(cloud, work, work_cap, nullptr, nullptr));
}

// GaussianCloud::rotate180DegAboutX(), in place over the workspace.
int32_t xspz_cloud_rotate180(float *work, int64_t work_cap, int64_t num_points,
                             int64_t sh_degree) {
  spz::GaussianCloud cloud;
  if (!read_work(work, work_cap, num_points, sh_degree, &cloud)) return kErrBadArgs;
  cloud.rotate180DegAboutX();
  return static_cast<int32_t>(write_work(cloud, work, work_cap, nullptr, nullptr));
}

// GaussianCloud::medianVolume() over the workspace scales stream.
float xspz_median_volume(const float *work, int64_t work_cap, int64_t num_points,
                         int64_t sh_degree) {
  spz::GaussianCloud cloud;
  if (!read_work(work, work_cap, num_points, sh_degree, &cloud)) return 0.0f;
  return cloud.medianVolume();
}

// --- math helpers -----------------------------------------------------------

int32_t xspz_math_half_to_float(int64_t half16, float *out1) {
  if (out1 == nullptr) return kErrBadArgs;
  *out1 = spz::halfToFloat(static_cast<spz::Half>(static_cast<uint16_t>(half16 & 0xffff)));
  return 0;
}

int64_t xspz_math_float_to_half(float f) {
  return static_cast<int32_t>(spz::floatToHalf(f));
}

int32_t xspz_math_norm3(float x, float y, float z, float *out1) {
  if (out1 == nullptr) return kErrBadArgs;
  *out1 = spz::norm(spz::Vec3f{x, y, z});
  return 0;
}

int32_t xspz_math_norm4(float x, float y, float z, float w, float *out1) {
  if (out1 == nullptr) return kErrBadArgs;
  *out1 = spz::norm(spz::Quat4f{w, x, y, z});
  return 0;
}

int32_t xspz_math_normalized3(float x, float y, float z, float *out3) {
  if (out3 == nullptr) return kErrBadArgs;
  const spz::Vec3f v = spz::normalized(spz::Vec3f{x, y, z});
  for (int i = 0; i < 3; ++i) out3[i] = v[i];
  return 0;
}

int32_t xspz_math_normalized4(float x, float y, float z, float w, float *out4) {
  if (out4 == nullptr) return kErrBadArgs;
  const spz::Quat4f q = spz::normalized(spz::Quat4f{w, x, y, z});
  for (int i = 0; i < 4; ++i) out4[i] = q[i];
  return 0;
}

int32_t xspz_math_axis_angle_quat(float x, float y, float z, float *out4) {
  if (out4 == nullptr) return kErrBadArgs;
  const spz::Quat4f q = spz::axisAngleQuat(spz::Vec3f{x, y, z});
  for (int i = 0; i < 4; ++i) out4[i] = q[i];
  return 0;
}

int32_t xspz_math_vec3f(float x, float y, float z, float *out3) {
  if (out3 == nullptr) return kErrBadArgs;
  const float data[3] = {x, y, z};
  const spz::Vec3f v = spz::vec3f(data);
  for (int i = 0; i < 3; ++i) out3[i] = v[i];
  return 0;
}

int32_t xspz_math_quat4f(float x, float y, float z, float w, float *out4) {
  if (out4 == nullptr) return kErrBadArgs;
  const float data[4] = {x, y, z, w};
  const spz::Quat4f q = spz::quat4f(data);
  for (int i = 0; i < 4; ++i) out4[i] = q[i];
  return 0;
}

int32_t xspz_math_dot3(float ax, float ay, float az, float bx, float by, float bz, float *out1) {
  if (out1 == nullptr) return kErrBadArgs;
  *out1 = spz::dot(spz::Vec3f{ax, ay, az}, spz::Vec3f{bx, by, bz});
  return 0;
}

int32_t xspz_math_squared_norm3(float x, float y, float z, float *out1) {
  if (out1 == nullptr) return kErrBadArgs;
  *out1 = spz::squaredNorm(spz::Vec3f{x, y, z});
  return 0;
}

int32_t xspz_math_times_qv(float qw, float qx, float qy, float qz, float vx, float vy, float vz,
                           float *out3) {
  if (out3 == nullptr) return kErrBadArgs;
  const spz::Vec3f v = spz::times(spz::Quat4f{qw, qx, qy, qz}, spz::Vec3f{vx, vy, vz});
  for (int i = 0; i < 3; ++i) out3[i] = v[i];
  return 0;
}

int32_t xspz_math_times_qq(float aw, float ax, float ay, float az, float bw, float bx, float by,
                           float bz, float *out4) {
  if (out4 == nullptr) return kErrBadArgs;
  const spz::Quat4f q = spz::times(spz::Quat4f{aw, ax, ay, az}, spz::Quat4f{bw, bx, by, bz});
  for (int i = 0; i < 4; ++i) out4[i] = q[i];
  return 0;
}

int32_t xspz_math_times_qs(float qw, float qx, float qy, float qz, float s, float *out4) {
  if (out4 == nullptr) return kErrBadArgs;
  const spz::Quat4f q = spz::times(spz::Quat4f{qw, qx, qy, qz}, s);
  for (int i = 0; i < 4; ++i) out4[i] = q[i];
  return 0;
}

int32_t xspz_math_plus_qq(float aw, float ax, float ay, float az, float bw, float bx, float by,
                          float bz, float *out4) {
  if (out4 == nullptr) return kErrBadArgs;
  const spz::Quat4f q = spz::plus(spz::Quat4f{aw, ax, ay, az}, spz::Quat4f{bw, bx, by, bz});
  for (int i = 0; i < 4; ++i) out4[i] = q[i];
  return 0;
}

int32_t xspz_math_times_vs(float x, float y, float z, float s, float *out3) {
  if (out3 == nullptr) return kErrBadArgs;
  const spz::Vec3f v = spz::times(spz::Vec3f{x, y, z}, s);
  for (int i = 0; i < 3; ++i) out3[i] = v[i];
  return 0;
}

int32_t xspz_math_plus_vv(float ax, float ay, float az, float bx, float by, float bz, float *out3) {
  if (out3 == nullptr) return kErrBadArgs;
  const spz::Vec3f v = spz::plus(spz::Vec3f{ax, ay, az}, spz::Vec3f{bx, by, bz});
  for (int i = 0; i < 3; ++i) out3[i] = v[i];
  return 0;
}

int32_t xspz_math_times_vv(float ax, float ay, float az, float bx, float by, float bz, float *out3) {
  if (out3 == nullptr) return kErrBadArgs;
  const spz::Vec3f v = spz::times(spz::Vec3f{ax, ay, az}, spz::Vec3f{bx, by, bz});
  for (int i = 0; i < 3; ++i) out3[i] = v[i];
  return 0;
}

// copyFloatBuffer(const std::vector<float>&) -> owned out buffer.
int32_t xspz_math_copy_float_buffer(const float *src, int64_t count, float *out, int64_t out_cap) {
  if (count < 0 || (count > 0 && src == nullptr)) return kErrBadArgs;
  const std::vector<float> v(src, src + count);
  const SpzFloatBuffer b = spz::copyFloatBuffer(v);
  int32_t rc = 0;
  if (b.count > 0 && (out == nullptr || out_cap < static_cast<int64_t>(b.count))) {
    rc = kErrCapacity;
  } else if (b.count > 0) {
    std::memcpy(out, b.data, b.count * sizeof(float));
  }
  delete[] b.data;
  return rc;
}

}  // extern "C"
