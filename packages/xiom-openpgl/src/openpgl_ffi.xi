// xiom.openpgl.ffi -- confined FFI core for xiom.openpgl (G5: the ONLY module
// in the package with `extern "C"` declarations; every foreign call is
// wrapped here).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Bridge: src/pgl_bridge.cpp (our code) over the vendored Open PGL v0.7.1
// C core (upstream pin 5c50cd7a331647a69e28cc8a19ff204039cbe78d, Apache-2.0)
// and the vendored oneTBB v2021.13.0 runtime.  See PROVENANCE.md and SPEC.md.
//
// Discipline (v0.64.4):
//   * handles are bridge registry indices (Int32), never pointers (B-20/B-25);
//   * out-params are XIOM-owned buffers -- `Vec[Float32]` for geometry/PDF
//     workspaces, `Vec[UInt8]` for statistics text read byte-indexed (B-24);
//   * no bare `null` crosses (B-23): every buffer handed to C is non-empty by
//     contract and every length is checked bridge-side;
//   * no pointer arithmetic in XIOM; no foreign-pointer reads (B-20/B-24);
//   * error codes are plain negative ints (see CODE TABLE below); the typed
//     mapping lives in xiom.openpgl.
//
// Code table (keep in sync with src/pgl_bridge.cpp):
//   0 ok, -1 invalid handle, -2 invalid argument, -3 capacity too small,
//   -4 creation failed, -5 registry full, -6 upstream returned false
//   (position not covered by the trained field / distribution not ready),
//   -7 empty sample storage, -8 internal error.
//
// Sample feed layout (PGL_SAMPLE_FLOATS = 10 flats per sample):
//   [px py pz dx dy dz weight pdf distance flags]
// flags: bit 0 = EInsideVolume (routes to the volume container), bit 1 =
// EDirectLight; values 0..3.

module xiom.openpgl.ffi

pub const PGL_OK: Int = 0;
pub const PGL_ERR_INVALID_HANDLE: Int = -1;
pub const PGL_ERR_INVALID_ARG: Int = -2;
pub const PGL_ERR_CAPACITY: Int = -3;
pub const PGL_ERR_CREATE: Int = -4;
pub const PGL_ERR_REGISTRY_FULL: Int = -5;
pub const PGL_ERR_UNCOVERED: Int = -6;
pub const PGL_ERR_EMPTY_STORAGE: Int = -7;
pub const PGL_ERR_INTERNAL: Int = -8;

/// Floats per sample in the flat feed buffer.
pub const PGL_SAMPLE_FLOATS: Int = 10;

// ---------------------------------------------------------------------------
// Raw C declarations (private to this module)
// ---------------------------------------------------------------------------

extern "C" {
  fn pglb_device_new(device_type: Int32, num_threads: Int32) -> Int32;
  fn pglb_device_release(device: Int32) -> Int32;

  fn pglb_field_new(device: Int32, deterministic: Int32, max_samples_per_leaf: Int32) -> Int32;
  fn pglb_field_release(field: Int32) -> Int32;
  fn pglb_field_iteration(field: Int32) -> Int32;
  fn pglb_field_set_scene_bounds(field: Int32, lx: Float32, ly: Float32, lz: Float32,
    ux: Float32, uy: Float32, uz: Float32) -> Int32;
  fn pglb_field_get_scene_bounds(field: Int32, out6: *Float32) -> Int32;
  fn pglb_field_validate(field: Int32) -> Int32;
  fn pglb_field_update(field: Int32, storage: Int32) -> Int32;
  fn pglb_field_surface_stats(field: Int32) -> Int32;

  fn pglb_storage_new() -> Int32;
  fn pglb_storage_release(storage: Int32) -> Int32;
  fn pglb_storage_reserve(storage: Int32, surface: Int32, volume: Int32) -> Int32;
  fn pglb_storage_clear(storage: Int32) -> Int32;
  fn pglb_storage_add_samples(storage: Int32, buf: *Float32, count: Int32) -> Int32;
  fn pglb_storage_size_surface(storage: Int32) -> Int32;
  fn pglb_storage_size_volume(storage: Int32) -> Int32;

  fn pglb_surface_dist_new(field: Int32) -> Int32;
  fn pglb_surface_dist_release(dist: Int32) -> Int32;
  fn pglb_surface_dist_init(field: Int32, dist: Int32, x: Float32, y: Float32, z: Float32,
    sample1d: Float32) -> Int32;
  fn pglb_surface_dist_sample(dist: Int32, u: Float32, v: Float32, out3: *Float32) -> Int32;
  fn pglb_surface_dist_pdf(dist: Int32, dx: Float32, dy: Float32, dz: Float32) -> Float32;
  fn pglb_surface_dist_sample_pdf(dist: Int32, u: Float32, v: Float32, out3: *Float32) -> Float32;
  fn pglb_surface_dist_validate(dist: Int32) -> Int32;
  fn pglb_surface_dist_id(dist: Int32) -> Int32;

  fn pglb_stats_release(stats: Int32) -> Int32;
  fn pglb_stats_string(stats: Int32, out: *UInt8, cap: Int32) -> Int32;
  fn pglb_stats_csv_header(stats: Int32, out: *UInt8, cap: Int32) -> Int32;
  fn pglb_stats_csv(stats: Int32, out: *UInt8, cap: Int32) -> Int32;
}

// ---------------------------------------------------------------------------
// Confined wrappers (small unsafe blocks; plain scalars out)
// ---------------------------------------------------------------------------

/// Create a CPU device (this port: device_type 4 only, num_threads 0 = all);
/// returns a handle or a negative code.  Complexity: O(threads).
pub fn device_new(device_type: Int, num_threads: Int) -> Int32
  requires: true
{
  unsafe { return pglb_device_new(device_type as Int32, num_threads as Int32); }
}

/// Release a device; returns the code.  Complexity: O(1).
pub fn device_release(device: Int) -> Int32
  requires: true
{
  unsafe { return pglb_device_release(device as Int32); }
}

/// Create a guiding field; returns a handle or a negative code.
/// Complexity: O(1).
pub fn field_new(device: Int, deterministic: Int, max_samples_per_leaf: Int) -> Int32
  requires: true
{
  unsafe { return pglb_field_new(device as Int32, deterministic as Int32, max_samples_per_leaf as Int32); }
}

/// Release a field; returns the code.  Complexity: O(1).
pub fn field_release(field: Int) -> Int32
  requires: true
{
  unsafe { return pglb_field_release(field as Int32); }
}

/// Training iterations applied to the field (>= 0) or a negative code.
/// Complexity: O(1).
pub fn field_iteration(field: Int) -> Int32
  requires: true
{
  unsafe { return pglb_field_iteration(field as Int32); }
}

/// Set the scene bounds; returns the code.  Complexity: O(1).
pub fn field_set_scene_bounds(field: Int, lx: Float32, ly: Float32, lz: Float32,
    ux: Float32, uy: Float32, uz: Float32) -> Int32
  requires: true
{
  unsafe { return pglb_field_set_scene_bounds(field as Int32, lx, ly, lz, ux, uy, uz); }
}

/// Read the scene bounds into `out6` (lx ly lz ux uy uz); returns the code.
/// Complexity: O(1).
pub fn field_get_scene_bounds(field: Int, out6: &mut Vec[Float32]) -> Int32
  requires: out6.len() >= 6
{
  unsafe { return pglb_field_get_scene_bounds(field as Int32, out6.as_mut_ptr()); }
}

/// 1 when the field passes upstream validation, else 0 or a negative code.
/// Complexity: O(field).
pub fn field_validate(field: Int) -> Int32
  requires: true
{
  unsafe { return pglb_field_validate(field as Int32); }
}

/// One training iteration; returns the code.  Complexity: O(samples).
pub fn field_update(field: Int, storage: Int) -> Int32
  requires: true
{
  unsafe { return pglb_field_update(field as Int32, storage as Int32); }
}

/// Surface statistics snapshot handle or a negative code.
/// Complexity: O(field).
pub fn field_surface_stats(field: Int) -> Int32
  requires: true
{
  unsafe { return pglb_field_surface_stats(field as Int32); }
}

/// Create an empty sample storage; returns a handle or a negative code.
/// Complexity: O(1).
pub fn storage_new() -> Int32
  requires: true
{
  unsafe { return pglb_storage_new(); }
}

/// Release a sample storage; returns the code.  Complexity: O(1).
pub fn storage_release(storage: Int) -> Int32
  requires: true
{
  unsafe { return pglb_storage_release(storage as Int32); }
}

/// Reserve surface/volume sample capacity; returns the code.
/// Complexity: O(capacity).
pub fn storage_reserve(storage: Int, surface: Int, volume: Int) -> Int32
  requires: true
{
  unsafe { return pglb_storage_reserve(storage as Int32, surface as Int32, volume as Int32); }
}

/// Drop every sample; returns the code.  Complexity: O(samples).
pub fn storage_clear(storage: Int) -> Int32
  requires: true
{
  unsafe { return pglb_storage_clear(storage as Int32); }
}

/// Feed `count` samples from an XIOM-owned flat buffer (PGL_SAMPLE_FLOATS
/// floats each); returns the code.  Complexity: O(count).
pub fn storage_add_samples(storage: Int, buf: &mut Vec[Float32], count: Int) -> Int32
  requires: count >= 0
  requires: count == 0 || buf.len() >= count * PGL_SAMPLE_FLOATS
{
  unsafe { return pglb_storage_add_samples(storage as Int32, buf.as_mut_ptr(), count as Int32); }
}

/// Surface sample count (>= 0) or a negative code.  Complexity: O(1).
pub fn storage_size_surface(storage: Int) -> Int32
  requires: true
{
  unsafe { return pglb_storage_size_surface(storage as Int32); }
}

/// Volume sample count (>= 0) or a negative code.  Complexity: O(1).
pub fn storage_size_volume(storage: Int) -> Int32
  requires: true
{
  unsafe { return pglb_storage_size_volume(storage as Int32); }
}

/// Allocate a field-owned surface sampling distribution; returns a handle or
/// a negative code.  Complexity: O(1).
pub fn surface_dist_new(field: Int) -> Int32
  requires: true
{
  unsafe { return pglb_surface_dist_new(field as Int32); }
}

/// Release a sampling distribution; returns the code.  Complexity: O(1).
pub fn surface_dist_release(dist: Int) -> Int32
  requires: true
{
  unsafe { return pglb_surface_dist_release(dist as Int32); }
}

/// Initialize the distribution at a surface position; 0 on success, -6 when
/// the position is not covered by the trained field.  Complexity: O(log n).
pub fn surface_dist_init(field: Int, dist: Int, x: Float32, y: Float32, z: Float32,
    sample1d: Float32) -> Int32
  requires: true
{
  unsafe { return pglb_surface_dist_init(field as Int32, dist as Int32, x, y, z, sample1d); }
}

/// Sample a direction for the 2D point (u, v) into `out3`; returns the code.
/// Complexity: O(components).
pub fn surface_dist_sample(dist: Int, u: Float32, v: Float32, out3: &mut Vec[Float32]) -> Int32
  requires: out3.len() >= 3
{
  unsafe { return pglb_surface_dist_sample(dist as Int32, u, v, out3.as_mut_ptr()); }
}

/// PDF of a direction (negative only when the handle/argument is bad).
/// Complexity: O(components).
pub fn surface_dist_pdf(dist: Int, dx: Float32, dy: Float32, dz: Float32) -> Float32
  requires: true
{
  unsafe { return pglb_surface_dist_pdf(dist as Int32, dx, dy, dz); }
}

/// Sample direction + PDF in one call (writes `out3`); returns the PDF.
/// Complexity: O(components).
pub fn surface_dist_sample_pdf(dist: Int, u: Float32, v: Float32,
    out3: &mut Vec[Float32]) -> Float32
  requires: out3.len() >= 3
{
  unsafe { return pglb_surface_dist_sample_pdf(dist as Int32, u, v, out3.as_mut_ptr()); }
}

/// 1 when the distribution passes upstream validation, else 0 or a negative
/// code.  Complexity: O(components).
pub fn surface_dist_validate(dist: Int) -> Int32
  requires: true
{
  unsafe { return pglb_surface_dist_validate(dist as Int32); }
}

/// Upstream distribution id (>= 0) or a negative code.  Complexity: O(1).
pub fn surface_dist_id(dist: Int) -> Int32
  requires: true
{
  unsafe { return pglb_surface_dist_id(dist as Int32); }
}

/// Release a statistics snapshot; returns the code.  Complexity: O(1).
pub fn stats_release(stats: Int) -> Int32
  requires: true
{
  unsafe { return pglb_stats_release(stats as Int32); }
}

/// Copy the statistics text into `out` (NUL included); returns the text
/// length or -3 when `cap` is too small.  Complexity: O(text).
pub fn stats_string(stats: Int, out: &mut Vec[UInt8], cap: Int) -> Int32
  requires: cap >= 0
  requires: out.len() >= cap
{
  unsafe { return pglb_stats_string(stats as Int32, out.as_mut_ptr(), cap as Int32); }
}

/// Copy the statistics CSV header into `out`; returns the length or -3.
/// Complexity: O(text).
pub fn stats_csv_header(stats: Int, out: &mut Vec[UInt8], cap: Int) -> Int32
  requires: cap >= 0
  requires: out.len() >= cap
{
  unsafe { return pglb_stats_csv_header(stats as Int32, out.as_mut_ptr(), cap as Int32); }
}

/// Copy the statistics CSV row into `out`; returns the length or -3.
/// Complexity: O(text).
pub fn stats_csv(stats: Int, out: &mut Vec[UInt8], cap: Int) -> Int32
  requires: cap >= 0
  requires: out.len() >= cap
{
  unsafe { return pglb_stats_csv(stats as Int32, out.as_mut_ptr(), cap as Int32); }
}
