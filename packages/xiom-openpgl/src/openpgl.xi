// XIOM -- xiom.openpgl: Intel Open Path Guiding Library (Open PGL v0.7.1)
// bindings for XIOM.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Public safe API over the vendored Open PGL C core (upstream pin
// 5c50cd7a331647a69e28cc8a19ff204039cbe78d = tag v0.7.1, Apache-2.0).  This
// module contains no `unsafe`: every foreign call goes through the confined
// FFI core in `xiom.openpgl.ffi` (G5).  See SPEC.md for the declared-surface
// table and PROVENANCE.md for the pin, the vendoring transforms and the
// generated-tree hash.
//
// Model (caller flow, upstream canonical order):
//   device_create -> field_create
//   storage_create -> storage_reserve -> storage_add_samples (xN)
//   field_train (xN iterations)  ->  sampling_distribution_*  ->  statistics_*
// Every fallible call returns Result[_, PglError] with a typed code
// (PGL_ERR_*) and a stable message; the codes mirror src/pgl_bridge.cpp.
//
// Owned-buffer interop: sample feeds and result read-backs cross as
// XIOM-owned `Vec[Float32]` buffers (PGL_SAMPLE_FLOATS per sample); field
// statistics cross as an XIOM-owned `Vec[UInt8]` slot and are read
// byte-indexed.  No pointer ever round-trips through XIOM.

module xiom.openpgl

use xiom.openpgl.ffi;
use xiom.string.builder;

// --- error codes (mirror src/pgl_bridge.cpp; keep in sync) ------------------

pub const PGL_OK: Int = 0;
pub const PGL_ERR_INVALID_HANDLE: Int = -1;
pub const PGL_ERR_INVALID_ARG: Int = -2;
pub const PGL_ERR_CAPACITY: Int = -3;
pub const PGL_ERR_CREATE: Int = -4;
pub const PGL_ERR_REGISTRY_FULL: Int = -5;
pub const PGL_ERR_UNCOVERED: Int = -6;
pub const PGL_ERR_EMPTY_STORAGE: Int = -7;
pub const PGL_ERR_INTERNAL: Int = -8;

// --- sample feed layout -------------------------------------------------------

/// Floats per sample in the flat feed buffer.
pub const PGL_SAMPLE_FLOATS: Int = 10;

/// Sample flags: surface sample (routed to the surface container).
pub const PGL_FLAG_SURFACE: Int = 0;

/// Sample flags: inside a volume (bit 0; routed to the volume container).
pub const PGL_FLAG_INSIDE_VOLUME: Int = 1;

/// Sample flags: direct-light sample (bit 1).
pub const PGL_FLAG_DIRECT_LIGHT: Int = 2;

/// Sample flags: volume + direct light.
pub const PGL_FLAG_INSIDE_VOLUME_DIRECT_LIGHT: Int = 3;

/// Device types accepted by `device_create`.
pub const PGL_DEVICE_CPU_4: Int = 4;
pub const PGL_DEVICE_CPU_8: Int = 8;

// --- types --------------------------------------------------------------------

/// Typed error: stable `code` (PGL_ERR_*) + message.
pub type PglError = {
  code: Int;
  message: Str;
}

pub fn PglError.new(code: Int, message: Str) -> PglError {
  return PglError{ code: code; message: message };
}

/// A live guiding device; `handle` is a bridge registry index, never a raw
/// pointer.  Stale after `device_destroy`.
pub type PglDevice = {
  handle: Int;
  device_type: Int;
}

/// A live guiding field.  Stale after `field_destroy`; release every derived
/// sampling distribution and statistics snapshot first.
pub type PglField = {
  handle: Int;
  deterministic: Bool;
  max_samples_per_leaf: Int;
}

/// A live sample storage.  Stale after `storage_destroy`.
pub type PglSampleStorage = {
  handle: Int;
}

/// A live surface sampling distribution owned by a field.  Stale after
/// `sampling_distribution_destroy`.
pub type PglSurfaceSamplingDistribution = {
  handle: Int;
}

/// A statistics snapshot of a field.  Stale after `statistics_destroy`.
pub type PglStatistics = {
  handle: Int;
}

/// A 3-component vector (position / direction), single precision.
pub type PglVec3 = {
  x: Float32;
  y: Float32;
  z: Float32;
}

/// Scene bounds (lower / upper corner).
pub type PglBounds = {
  lx: Float32;
  ly: Float32;
  lz: Float32;
  ux: Float32;
  uy: Float32;
  uz: Float32;
}

/// One sample+PDF pair: the direction produced for a 2D sample and its PDF.
pub type PglSamplePdf = {
  direction: PglVec3;
  pdf: Float32;
}

// --- error mapping ------------------------------------------------------------

fn pgl_field_err(code: Int, what: Str) -> PglError {
  if code == PGL_ERR_INVALID_HANDLE {
    return PglError.new(code, "xiom.openpgl: " + what + ": invalid or stale handle");
  }
  if code == PGL_ERR_INVALID_ARG {
    return PglError.new(code, "xiom.openpgl: " + what + ": invalid argument");
  }
  if code == PGL_ERR_CAPACITY {
    return PglError.new(code, "xiom.openpgl: " + what + ": buffer capacity too small");
  }
  if code == PGL_ERR_CREATE {
    return PglError.new(code, "xiom.openpgl: " + what + ": upstream creation failed");
  }
  if code == PGL_ERR_REGISTRY_FULL {
    return PglError.new(code, "xiom.openpgl: " + what + ": handle registry full");
  }
  if code == PGL_ERR_UNCOVERED {
    return PglError.new(code, "xiom.openpgl: " + what + ": position not covered by the trained field");
  }
  if code == PGL_ERR_EMPTY_STORAGE {
    return PglError.new(code, "xiom.openpgl: " + what + ": sample storage is empty");
  }
  return PglError.new(code, "xiom.openpgl: " + what + ": internal error");
}

// --- owned-buffer helpers ------------------------------------------------------

/// Zero-filled byte slot (`n` bytes) owned by XIOM.  Complexity: O(n).
pub fn blank_bytes(n: Int) -> Vec[UInt8]
  requires: n >= 0
{
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

/// Zero-filled float slot (`n` elements) owned by XIOM.  Complexity: O(n).
pub fn blank_floats(n: Int) -> Vec[Float32]
  requires: n >= 0
{
  var v: Vec[Float32] = Vec[Float32].new();
  var i: Int = 0;
  while i < n {
    v.push(0.0);
    i = i + 1;
  }
  return v;
}

/// Append one sample row (PGL_SAMPLE_FLOATS floats) to an XIOM-owned feed
/// buffer: position, direction, weight, pdf, distance, flags.
/// Complexity: O(1).
pub fn sample_push(buf: &mut Vec[Float32], px: Float32, py: Float32, pz: Float32,
    dx: Float32, dy: Float32, dz: Float32, weight: Float32, pdf: Float32,
    distance: Float32, flags: Int)
  requires: flags >= 0
  requires: flags <= 3
{
  buf.push(px);
  buf.push(py);
  buf.push(pz);
  buf.push(dx);
  buf.push(dy);
  buf.push(dz);
  buf.push(weight);
  buf.push(pdf);
  buf.push(distance);
  buf.push(flags as Float32);
}

// --- device --------------------------------------------------------------------

/// Create a CPU device.  This port builds the 4-wide kernels at the x86-64
/// SSE2 baseline: `device_type` must be PGL_DEVICE_CPU_4 (the AVX2 CPU_8
/// device is declared but not compiled — see SPEC.md section 1).
/// `num_threads` 0 uses all hardware threads (pass 1 for bit-reproducible
/// training runs).  Complexity: O(threads).
pub fn device_create(device_type: Int, num_threads: Int) -> Result[PglDevice, PglError]
  requires: num_threads >= 0
{
  if device_type != PGL_DEVICE_CPU_4 {
    return Err(PglError.new(PGL_ERR_INVALID_ARG,
      "xiom.openpgl: device_create: only device_type 4 (CPU_4) is built by this port"));
  }
  let rc = ffi.device_new(device_type, num_threads) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "device_create"));
  }
  return Ok(PglDevice{ handle: rc; device_type: device_type });
}

/// Release a device; the value is stale afterwards.  Complexity: O(1).
pub fn device_destroy(device: PglDevice) -> Result[Int, PglError]
  requires: true
{
  let rc = ffi.device_release(device.handle) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "device_destroy"));
  }
  return Ok(rc);
}

// --- field ---------------------------------------------------------------------

/// Create a guiding field on `device`: KD-tree spatial structure +
/// parallax-aware VMM directional distribution.  `deterministic` freezes the
/// training decisions that would otherwise draw from the stochastic sampler;
/// `max_samples_per_leaf` bounds per-leaf training cost.  Complexity: O(1).
pub fn field_create(device: PglDevice, deterministic: Bool, max_samples_per_leaf: Int) -> Result[PglField, PglError]
  requires: max_samples_per_leaf > 0
{
  var det: Int = 0;
  if deterministic { det = 1; }
  let rc = ffi.field_new(device.handle, det, max_samples_per_leaf) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "field_create"));
  }
  return Ok(PglField{
    handle: rc;
    deterministic: deterministic;
    max_samples_per_leaf: max_samples_per_leaf;
  });
}

/// Release a field; the value is stale afterwards.  Complexity: O(field).
pub fn field_destroy(field: PglField) -> Result[Int, PglError]
  requires: true
{
  let rc = ffi.field_release(field.handle) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "field_destroy"));
  }
  return Ok(rc);
}

/// Number of training iterations applied so far.  Complexity: O(1).
pub fn field_iteration(field: PglField) -> Result[Int, PglError]
  requires: true
{
  let rc = ffi.field_iteration(field.handle) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "field_iteration"));
  }
  return Ok(rc);
}

/// A field needs at least one training iteration before distributions can be
/// initialized; true when `pglFieldValidate` passes.  Complexity: O(field).
pub fn field_validate(field: PglField) -> Result[Bool, PglError]
  requires: true
{
  let rc = ffi.field_validate(field.handle) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "field_validate"));
  }
  return Ok(rc == 1);
}

/// Set the scene bounds explicitly; the field enlarges them slightly on the
/// surface path (upstream behaviour).  Complexity: O(1).
pub fn field_set_scene_bounds(field: PglField, lx: Float32, ly: Float32, lz: Float32,
    ux: Float32, uy: Float32, uz: Float32) -> Result[Int, PglError]
  requires: true
{
  let rc = ffi.field_set_scene_bounds(field.handle, lx, ly, lz, ux, uy, uz) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "field_set_scene_bounds"));
  }
  return Ok(rc);
}

/// Read the scene bounds into an owned record (`Vec[Float32]` slot crossing).
/// Complexity: O(1).
pub fn field_scene_bounds(field: PglField) -> Result[PglBounds, PglError]
  requires: true
{
  var slot: Vec[Float32] = blank_floats(6);
  let rc = ffi.field_get_scene_bounds(field.handle, &mut slot) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "field_scene_bounds"));
  }
  return Ok(PglBounds{
    lx: slot[0]; ly: slot[1]; lz: slot[2];
    ux: slot[3]; uy: slot[4]; uz: slot[5];
  });
}

/// Run one training iteration over the storage contents; returns the new
/// iteration count.  Complexity: O(samples * log samples).
pub fn field_train(field: PglField, storage: PglSampleStorage) -> Result[Int, PglError]
  requires: true
{
  let rc = ffi.field_update(field.handle, storage.handle) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "field_train"));
  }
  let it = field_iteration(field);
  if !it.is_ok {
    return Err(it.error);
  }
  return it;
}

// --- sample storage --------------------------------------------------------------

/// Create an empty sample storage.  Complexity: O(1).
pub fn storage_create() -> Result[PglSampleStorage, PglError]
  requires: true
{
  let rc = ffi.storage_new() as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "storage_create"));
  }
  return Ok(PglSampleStorage{ handle: rc });
}

/// Release a sample storage; the value is stale afterwards.  Complexity: O(1).
pub fn storage_destroy(storage: PglSampleStorage) -> Result[Int, PglError]
  requires: true
{
  let rc = ffi.storage_release(storage.handle) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "storage_destroy"));
  }
  return Ok(rc);
}

/// Reserve surface and volume sample capacity (the "init" step of the
/// upstream storage lifecycle).  Complexity: O(capacity).
pub fn storage_reserve(storage: PglSampleStorage, surface: Int, volume: Int) -> Result[Int, PglError]
  requires: surface >= 0
  requires: volume >= 0
{
  let rc = ffi.storage_reserve(storage.handle, surface, volume) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "storage_reserve"));
  }
  return Ok(rc);
}

/// Drop every sample.  Complexity: O(samples).
pub fn storage_clear(storage: PglSampleStorage) -> Result[Int, PglError]
  requires: true
{
  let rc = ffi.storage_clear(storage.handle) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "storage_clear"));
  }
  return Ok(rc);
}

/// Feed `count` rows (PGL_SAMPLE_FLOATS floats each) from an XIOM-owned
/// buffer.  The bridge validates every row before any of them enters the
/// storage (all-or-nothing); returns the number of samples added.
/// Complexity: O(count).
pub fn storage_add_samples(storage: PglSampleStorage, buf: &mut Vec[Float32], count: Int) -> Result[Int, PglError]
  requires: count >= 0
  requires: count == 0 || buf.len() >= count * PGL_SAMPLE_FLOATS
{
  let rc = ffi.storage_add_samples(storage.handle, buf, count) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "storage_add_samples"));
  }
  return Ok(count);
}

/// Number of surface samples in the storage.  Complexity: O(1).
pub fn storage_size_surface(storage: PglSampleStorage) -> Result[Int, PglError]
  requires: true
{
  let rc = ffi.storage_size_surface(storage.handle) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "storage_size_surface"));
  }
  return Ok(rc);
}

/// Number of volume samples in the storage.  Complexity: O(1).
pub fn storage_size_volume(storage: PglSampleStorage) -> Result[Int, PglError]
  requires: true
{
  let rc = ffi.storage_size_volume(storage.handle) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "storage_size_volume"));
  }
  return Ok(rc);
}

// --- surface sampling distribution ------------------------------------------------

/// Allocate a field-owned surface sampling distribution.
/// Complexity: O(1).
pub fn sampling_distribution_create(field: PglField) -> Result[PglSurfaceSamplingDistribution, PglError]
  requires: true
{
  let rc = ffi.surface_dist_new(field.handle) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "sampling_distribution_create"));
  }
  return Ok(PglSurfaceSamplingDistribution{ handle: rc });
}

/// Release a distribution; the value is stale afterwards.  Complexity: O(1).
pub fn sampling_distribution_destroy(dist: PglSurfaceSamplingDistribution) -> Result[Int, PglError]
  requires: true
{
  let rc = ffi.surface_dist_release(dist.handle) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "sampling_distribution_destroy"));
  }
  return Ok(rc);
}

/// Initialize the distribution for a surface position; `sample1d` feeds the
/// deterministic region lookup (0.5 selects the exact leaf).  Fails with
/// PGL_ERR_UNCOVERED when the position is outside the trained region.
/// Complexity: O(log n).
pub fn sampling_distribution_init(field: PglField, dist: PglSurfaceSamplingDistribution,
    position: PglVec3, sample1d: Float32) -> Result[Int, PglError]
  requires: true
{
  let rc = ffi.surface_dist_init(field.handle, dist.handle, position.x, position.y,
    position.z, sample1d) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "sampling_distribution_init"));
  }
  return Ok(rc);
}

/// Sample one direction for the 2D point (u, v) in [0, 1)^2.
/// Complexity: O(components).
pub fn sampling_distribution_sample(dist: PglSurfaceSamplingDistribution,
    u: Float32, v: Float32) -> Result[PglVec3, PglError]
  requires: true
{
  var out: Vec[Float32] = blank_floats(3);
  let rc = ffi.surface_dist_sample(dist.handle, u, v, &mut out) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "sampling_distribution_sample"));
  }
  return Ok(PglVec3{ x: out[0]; y: out[1]; z: out[2] });
}

/// PDF of `direction` under the initialized distribution.
/// Complexity: O(components).
pub fn sampling_distribution_pdf(dist: PglSurfaceSamplingDistribution,
    direction: PglVec3) -> Result[Float32, PglError]
  requires: true
{
  let pdf = ffi.surface_dist_pdf(dist.handle, direction.x, direction.y, direction.z);
  if pdf < 0.0 {
    return Err(PglError.new(PGL_ERR_INVALID_HANDLE, "xiom.openpgl: sampling_distribution_pdf: invalid or stale handle"));
  }
  return Ok(pdf);
}

/// Sample + PDF in one call (upstream `...SamplePDF`).
/// Complexity: O(components).
pub fn sampling_distribution_sample_pdf(dist: PglSurfaceSamplingDistribution,
    u: Float32, v: Float32) -> Result[PglSamplePdf, PglError]
  requires: true
{
  var out: Vec[Float32] = blank_floats(3);
  let pdf = ffi.surface_dist_sample_pdf(dist.handle, u, v, &mut out);
  if pdf < 0.0 {
    return Err(PglError.new(PGL_ERR_INVALID_HANDLE, "xiom.openpgl: sampling_distribution_sample_pdf: invalid or stale handle"));
  }
  return Ok(PglSamplePdf{
    direction: PglVec3{ x: out[0]; y: out[1]; z: out[2] };
    pdf: pdf;
  });
}

/// True when the initialized distribution passes upstream validation.
/// Complexity: O(components).
pub fn sampling_distribution_validate(dist: PglSurfaceSamplingDistribution) -> Result[Bool, PglError]
  requires: true
{
  let rc = ffi.surface_dist_validate(dist.handle) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "sampling_distribution_validate"));
  }
  return Ok(rc == 1);
}

/// Upstream region/distribution id (>= 0).  Complexity: O(1).
pub fn sampling_distribution_id(dist: PglSurfaceSamplingDistribution) -> Result[Int, PglError]
  requires: true
{
  let rc = ffi.surface_dist_id(dist.handle) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "sampling_distribution_id"));
  }
  return Ok(rc);
}

// --- field statistics --------------------------------------------------------------

/// Take a statistics snapshot of the field's surface structure.
/// Complexity: O(field).
pub fn statistics_snapshot(field: PglField) -> Result[PglStatistics, PglError]
  requires: true
{
  let rc = ffi.field_surface_stats(field.handle) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "statistics_snapshot"));
  }
  return Ok(PglStatistics{ handle: rc });
}

/// Release a statistics snapshot; the value is stale afterwards.
/// Complexity: O(1).
pub fn statistics_destroy(stats: PglStatistics) -> Result[Int, PglError]
  requires: true
{
  let rc = ffi.stats_release(stats.handle) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "statistics_destroy"));
  }
  return Ok(rc);
}

// Byte-indexed copy of the first `len` bytes of an owned slot into a Str.
fn bytes_to_str(slot: &Vec[UInt8], len: Int) -> Str
  requires: len >= 0
  requires: len <= slot.len()
{
  var sb: Vec[UInt8] = builder.sb_new();
  var i: Int = 0;
  while i < len {
    builder.sb_push_byte(&mut sb, slot[i]);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

fn stats_text_common(stats: PglStatistics, which: Int, what: Str) -> Result[Str, PglError]
  requires: true
{
  let cap: Int = 65536;
  var slot: Vec[UInt8] = blank_bytes(cap);
  var rc: Int = 0;
  if which == 0 {
    rc = ffi.stats_string(stats.handle, &mut slot, cap) as Int;
  } elif which == 1 {
    rc = ffi.stats_csv_header(stats.handle, &mut slot, cap) as Int;
  } else {
    rc = ffi.stats_csv(stats.handle, &mut slot, cap) as Int;
  }
  if rc < 0 {
    return Err(pgl_field_err(rc, what));
  }
  return Ok(bytes_to_str(slot, rc));
}

/// Human-readable statistics text (owned Str built from an owned byte slot).
/// Complexity: O(field + text).
pub fn statistics_text(stats: PglStatistics) -> Result[Str, PglError]
  requires: true
{
  return stats_text_common(stats, 0, "statistics_text");
}

/// CSV header of the statistics table.  Complexity: O(field + text).
pub fn statistics_csv_header(stats: PglStatistics) -> Result[Str, PglError]
  requires: true
{
  return stats_text_common(stats, 1, "statistics_csv_header");
}

/// CSV row of the statistics table.  Complexity: O(field + text).
pub fn statistics_csv(stats: PglStatistics) -> Result[Str, PglError]
  requires: true
{
  return stats_text_common(stats, 2, "statistics_csv");
}

/// Raw owned-slot variant: copy the statistics text into `out` up to `cap`
/// bytes; returns the text length (NUL excluded in the copy) or a typed
/// PGL_ERR_CAPACITY when `cap` is too small.  Complexity: O(text).
pub fn statistics_text_into(stats: PglStatistics, out: &mut Vec[UInt8], cap: Int) -> Result[Int, PglError]
  requires: cap >= 0
  requires: out.len() >= cap
{
  let rc = ffi.stats_string(stats.handle, out, cap) as Int;
  if rc < 0 {
    return Err(pgl_field_err(rc, "statistics_text_into"));
  }
  return Ok(rc);
}
