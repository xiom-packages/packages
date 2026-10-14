// XIOM -- xiom.openpgl reviewable bridge over the vendored Open PGL v0.7.1 core.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// This file is ORIGINAL to the xiom.openpgl package (not upstream code).  It
// is the only place where Open PGL objects live: every XIOM-facing entry point
// takes integer handles and XIOM-owned buffers, never a raw foreign pointer
// (B-20/B-23/B-24/B-25 discipline -- see SPEC.md section 4):
//
//   * handles are registry indices; the C++ objects stay bridge-side and are
//     never cast to/from integers;
//   * no XIOM call passes bare null: outputs go into XIOM-owned Vec buffers
//     (`as_mut_ptr`), inputs arrive as const pointers of the same buffers;
//   * XIOM never dereferences a foreign pointer; the bridge copies foreign
//     data (PGLString, pgl_vec3f) into XIOM-owned buffers itself;
//   * sample feed layout is a flat float stream (PGLB_SAMPLE_FLOATS = 10):
//     [px py pz dx dy dz weight pdf distance flags]; flags bit 0
//     (EInsideVolume) selects the volume sample container, exactly like the
//     upstream PGLSampleData::flags.
//
// Error codes (keep in sync with src/openpgl.xi):
//   0 ok, -1 invalid handle, -2 invalid argument, -3 capacity too small,
//   -4 creation failed, -5 registry full, -6 upstream returned false
//   (position not covered by the trained field / distribution not ready),
//   -7 empty sample storage, -8 internal error.
//
// Build: compiled at port time through --c-source (see port.args.json); the
// vendored core rides the same link line as the per-TU wrappers.

#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>

#include "../vendor/openpgl/include/openpgl/openpgl.h"

namespace
{

constexpr int PGLB_MAX_HANDLES = 64;

// A tiny fixed-capacity registry; handles are slot indices (never pointers).
template <typename T>
struct Registry
{
    T *slots[PGLB_MAX_HANDLES];
    bool used[PGLB_MAX_HANDLES];

    Registry() : slots(), used()
    {
        for (int i = 0; i < PGLB_MAX_HANDLES; ++i)
        {
            slots[i] = nullptr;
            used[i] = false;
        }
    }

    int add(T *obj)
    {
        if (obj == nullptr)
        {
            return -4;
        }
        for (int i = 0; i < PGLB_MAX_HANDLES; ++i)
        {
            if (!used[i])
            {
                slots[i] = obj;
                used[i] = true;
                return i;
            }
        }
        return -5;
    }

    T *get(int handle) const
    {
        if (handle < 0 || handle >= PGLB_MAX_HANDLES || !used[handle])
        {
            return nullptr;
        }
        return slots[handle];
    }

    T *take(int handle)
    {
        T *obj = get(handle);
        if (obj != nullptr)
        {
            used[handle] = false;
            slots[handle] = nullptr;
        }
        return obj;
    }
};

Registry<Device> g_devices;
Registry<Field> g_fields;
Registry<SampleStorage> g_storages;
Registry<SurfaceSamplingDistribution> g_surfaceDists;
Registry<FieldStatistics> g_stats;

bool finite3(float x, float y, float z)
{
    return std::isfinite(x) && std::isfinite(y) && std::isfinite(z);
}

}  // namespace

extern "C"
{

// ---- device ----------------------------------------------------------------

/// Create a CPU device.  `device_type` must be 4: this port builds the
/// 4-wide kernels at the x86-64 SSE2 baseline and does not compile the
/// AVX2 (CPU_8) device — see SPEC.md section 1 for why.  `num_threads` 0
/// means all hardware threads.  Returns a handle or a code.
int pglb_device_new(int device_type, int num_threads)
{
    if (device_type != 4)
    {
        return -2;
    }
    if (num_threads < 0)
    {
        return -2;
    }
    try
    {
        PGLDevice device = pglNewDevice(PGL_DEVICE_TYPE_CPU_4, static_cast<size_t>(num_threads));
        return g_devices.add(device);
    }
    catch (...)
    {
        return -8;
    }
}

/// Release a device; the handle is stale afterwards.
int pglb_device_release(int device)
{
    Device *obj = g_devices.take(device);
    if (obj == nullptr)
    {
        return -1;
    }
    try
    {
        pglReleaseDevice(obj);
    }
    catch (...)
    {
        return -8;
    }
    return 0;
}

// ---- field -----------------------------------------------------------------

/// Create a guiding field: KD-tree spatial structure + parallax-aware VMM
/// directional distribution (PGL defaults), `deterministic` freezes the
/// RNG-dependent training decisions, `max_samples_per_leaf` bounds the leaf
/// training cost.  Returns a handle or a code.
int pglb_field_new(int device, int deterministic, int max_samples_per_leaf)
{
    Device *dev = g_devices.get(device);
    if (dev == nullptr)
    {
        return -1;
    }
    if ((deterministic != 0 && deterministic != 1) || max_samples_per_leaf <= 0)
    {
        return -2;
    }
    try
    {
        PGLFieldArguments args;
        pglFieldArgumentsSetDefaults(args, PGL_SPATIAL_STRUCTURE_KDTREE,
                                     PGL_DIRECTIONAL_DISTRIBUTION_PARALLAX_AWARE_VMM,
                                     deterministic != 0,
                                     static_cast<size_t>(max_samples_per_leaf));
        PGLField field = pglDeviceNewField(dev, args);
        return g_fields.add(field);
    }
    catch (...)
    {
        return -8;
    }
}

/// Release a field; release every derived sampling distribution first.
int pglb_field_release(int field)
{
    Field *obj = g_fields.take(field);
    if (obj == nullptr)
    {
        return -1;
    }
    try
    {
        pglReleaseField(obj);
    }
    catch (...)
    {
        return -8;
    }
    return 0;
}

/// Number of pglFieldUpdate calls applied so far (0 = untrained).
int pglb_field_iteration(int field)
{
    Field *obj = g_fields.get(field);
    if (obj == nullptr)
    {
        return -1;
    }
    try
    {
        return static_cast<int>(pglFieldGetIteration(obj));
    }
    catch (...)
    {
        return -8;
    }
}

/// Set the scene bounds (lower xyz, upper xyz); the field enlarges them
/// slightly on the surface path, exactly like upstream setSceneBounds.
int pglb_field_set_scene_bounds(int field, float lx, float ly, float lz, float ux, float uy, float uz)
{
    Field *obj = g_fields.get(field);
    if (obj == nullptr)
    {
        return -1;
    }
    if (!finite3(lx, ly, lz) || !finite3(ux, uy, uz) || lx > ux || ly > uy || lz > uz)
    {
        return -2;
    }
    try
    {
        pgl_box3f bounds;
        bounds.lower.x = lx;
        bounds.lower.y = ly;
        bounds.lower.z = lz;
        bounds.upper.x = ux;
        bounds.upper.y = uy;
        bounds.upper.z = uz;
        pglFieldSetSceneBounds(obj, bounds);
    }
    catch (...)
    {
        return -8;
    }
    return 0;
}

/// Read the scene bounds into `out6` (lx ly lz ux uy uz).
int pglb_field_get_scene_bounds(int field, float *out6)
{
    Field *obj = g_fields.get(field);
    if (obj == nullptr)
    {
        return -1;
    }
    if (out6 == nullptr)
    {
        return -2;
    }
    try
    {
        pgl_box3f bounds = pglFieldGetSceneBounds(obj);
        out6[0] = bounds.lower.x;
        out6[1] = bounds.lower.y;
        out6[2] = bounds.lower.z;
        out6[3] = bounds.upper.x;
        out6[4] = bounds.upper.y;
        out6[5] = bounds.upper.z;
    }
    catch (...)
    {
        return -8;
    }
    return 0;
}

/// 1 when the field passes upstream internal validation, else 0.
int pglb_field_validate(int field)
{
    Field *obj = g_fields.get(field);
    if (obj == nullptr)
    {
        return -1;
    }
    try
    {
        return pglFieldValidate(obj) ? 1 : 0;
    }
    catch (...)
    {
        return -8;
    }
}

/// One training iteration over the sample storage contents.  The storage must
/// hold at least one sample; the container routing follows the sample flags
/// bit 0.  Returns 0 or a code.
int pglb_field_update(int field, int storage)
{
    Field *f = g_fields.get(field);
    SampleStorage *s = g_storages.get(storage);
    if (f == nullptr || s == nullptr)
    {
        return -1;
    }
    try
    {
        if (pglSampleStorageGetSizeSurface(s) + pglSampleStorageGetSizeVolume(s) == 0)
        {
            return -7;
        }
        pglFieldUpdate(f, s);
    }
    catch (...)
    {
        return -8;
    }
    return 0;
}

/// Fresh surface statistics snapshot of the field (release with
/// pglb_stats_release); returns a handle or a code.
int pglb_field_surface_stats(int field)
{
    Field *obj = g_fields.get(field);
    if (obj == nullptr)
    {
        return -1;
    }
    try
    {
        PGLFieldStatistics stats = pglFieldGetSurfaceStatistics(obj);
        return g_stats.add(stats);
    }
    catch (...)
    {
        return -8;
    }
}

// ---- sample storage --------------------------------------------------------

/// Create an empty sample storage.  Returns a handle or a code.
int pglb_storage_new()
{
    try
    {
        return g_storages.add(pglNewSampleStorage());
    }
    catch (...)
    {
        return -8;
    }
}

/// Release a sample storage; the handle is stale afterwards.
int pglb_storage_release(int storage)
{
    SampleStorage *obj = g_storages.take(storage);
    if (obj == nullptr)
    {
        return -1;
    }
    try
    {
        pglReleaseSampleStorage(obj);
    }
    catch (...)
    {
        return -8;
    }
    return 0;
}

/// Reserve capacity for `surface` surface and `volume` volume samples.
int pglb_storage_reserve(int storage, int surface, int volume)
{
    SampleStorage *obj = g_storages.get(storage);
    if (obj == nullptr)
    {
        return -1;
    }
    if (surface < 0 || volume < 0)
    {
        return -2;
    }
    try
    {
        pglSampleStorageReserve(obj, static_cast<size_t>(surface), static_cast<size_t>(volume));
    }
    catch (...)
    {
        return -8;
    }
    return 0;
}

/// Drop every sample (surface + volume + invalid).
int pglb_storage_clear(int storage)
{
    SampleStorage *obj = g_storages.get(storage);
    if (obj == nullptr)
    {
        return -1;
    }
    try
    {
        pglSampleStorageClear(obj);
    }
    catch (...)
    {
        return -8;
    }
    return 0;
}

/// Feed `count` samples from an XIOM-owned float buffer (PGLB_SAMPLE_FLOATS
/// floats per sample).  Values are validated against the upstream
/// SampleData contract (finite, weight >= 0, pdf > 0, distance > 0, flags
/// 0..3) before any sample enters the storage; the first invalid sample
/// rejects the whole call (nothing is added).
int pglb_storage_add_samples(int storage, const float *buf, int count)
{
    SampleStorage *obj = g_storages.get(storage);
    if (obj == nullptr)
    {
        return -1;
    }
    if (count < 0 || (count > 0 && buf == nullptr))
    {
        return -2;
    }
    if (count == 0)
    {
        return 0;
    }
    try
    {
        std::vector<PGLSampleData> samples;
        samples.reserve(static_cast<size_t>(count));
        for (int i = 0; i < count; ++i)
        {
            const float *p = buf + static_cast<size_t>(i) * 10u;
            PGLSampleData s;
            s.position = {p[0], p[1], p[2]};
            s.direction = {p[3], p[4], p[5]};
            s.weight = p[6];
            s.pdf = p[7];
            s.distance = p[8];
            const float flags_f = p[9];
            if (!finite3(p[0], p[1], p[2]) || !finite3(p[3], p[4], p[5]))
            {
                return -2;
            }
            if (!std::isfinite(s.weight) || s.weight < 0.0f)
            {
                return -2;
            }
            if (!std::isfinite(s.pdf) || !(s.pdf > 0.0f))
            {
                return -2;
            }
            if (!std::isfinite(s.distance) || !(s.distance > 0.0f))
            {
                return -2;
            }
            if (!std::isfinite(flags_f) || flags_f < 0.0f || flags_f > 3.0f ||
                flags_f != std::floor(flags_f))
            {
                return -2;
            }
            s.flags = static_cast<uint32_t>(flags_f);
            samples.push_back(s);
        }
        pglSampleStorageAddSamples(obj, samples.data(), samples.size());
    }
    catch (...)
    {
        return -8;
    }
    return 0;
}

/// Number of surface samples in the storage.
int pglb_storage_size_surface(int storage)
{
    SampleStorage *obj = g_storages.get(storage);
    if (obj == nullptr)
    {
        return -1;
    }
    try
    {
        return static_cast<int>(pglSampleStorageGetSizeSurface(obj));
    }
    catch (...)
    {
        return -8;
    }
}

/// Number of volume samples in the storage.
int pglb_storage_size_volume(int storage)
{
    SampleStorage *obj = g_storages.get(storage);
    if (obj == nullptr)
    {
        return -1;
    }
    try
    {
        return static_cast<int>(pglSampleStorageGetSizeVolume(obj));
    }
    catch (...)
    {
        return -8;
    }
}

// ---- surface sampling distribution ----------------------------------------

/// Allocate a surface sampling distribution owned by the field.
int pglb_surface_dist_new(int field)
{
    Field *obj = g_fields.get(field);
    if (obj == nullptr)
    {
        return -1;
    }
    try
    {
        return g_surfaceDists.add(pglFieldNewSurfaceSamplingDistribution(obj));
    }
    catch (...)
    {
        return -8;
    }
}

/// Release a sampling distribution; the handle is stale afterwards.
int pglb_surface_dist_release(int dist)
{
    SurfaceSamplingDistribution *obj = g_surfaceDists.take(dist);
    if (obj == nullptr)
    {
        return -1;
    }
    try
    {
        pglReleaseSurfaceSamplingDistribution(obj);
    }
    catch (...)
    {
        return -8;
    }
    return 0;
}

/// Initialize the distribution for a surface position; `sample1d` feeds the
/// deterministic region lookup (0.5 for the exact leaf).  Returns 0 when the
/// position is covered by the trained field, -6 when it is not.
int pglb_surface_dist_init(int field, int dist, float x, float y, float z, float sample1d)
{
    Field *f = g_fields.get(field);
    SurfaceSamplingDistribution *d = g_surfaceDists.get(dist);
    if (f == nullptr || d == nullptr)
    {
        return -1;
    }
    if (!finite3(x, y, z) || !std::isfinite(sample1d))
    {
        return -2;
    }
    try
    {
        pgl_point3f pos = {x, y, z};
        float s = sample1d;
        return pglFieldInitSurfaceSamplingDistribution(f, d, pos, &s) ? 0 : -6;
    }
    catch (...)
    {
        return -8;
    }
}

/// Sample a direction from the initialized distribution for the 2D sample
/// (u, v) in [0, 1)^2; writes the three direction components into `out3`.
int pglb_surface_dist_sample(int dist, float u, float v, float *out3)
{
    SurfaceSamplingDistribution *d = g_surfaceDists.get(dist);
    if (d == nullptr)
    {
        return -1;
    }
    if (out3 == nullptr || !std::isfinite(u) || !std::isfinite(v))
    {
        return -2;
    }
    try
    {
        pgl_point2f s = {u, v};
        pgl_vec3f dir = pglSurfaceSamplingDistributionSample(d, s);
        out3[0] = dir.x;
        out3[1] = dir.y;
        out3[2] = dir.z;
    }
    catch (...)
    {
        return -8;
    }
    return 0;
}

/// PDF of `direction` under the initialized distribution; -1.0f on a bad
/// handle or argument (a PDF is never negative).
float pglb_surface_dist_pdf(int dist, float dx, float dy, float dz)
{
    SurfaceSamplingDistribution *d = g_surfaceDists.get(dist);
    if (d == nullptr)
    {
        return -1.0f;
    }
    if (!finite3(dx, dy, dz))
    {
        return -1.0f;
    }
    try
    {
        pgl_vec3f dir = {dx, dy, dz};
        return pglSurfaceSamplingDistributionPDF(d, dir);
    }
    catch (...)
    {
        return -1.0f;
    }
}

/// Sample + PDF in one call; writes the direction into `out3`, returns the
/// PDF (-1.0f on a bad handle or argument).
float pglb_surface_dist_sample_pdf(int dist, float u, float v, float *out3)
{
    SurfaceSamplingDistribution *d = g_surfaceDists.get(dist);
    if (d == nullptr)
    {
        return -1.0f;
    }
    if (out3 == nullptr || !std::isfinite(u) || !std::isfinite(v))
    {
        return -1.0f;
    }
    try
    {
        pgl_point2f s = {u, v};
        pgl_vec3f dir;
        const float pdf = pglSurfaceSamplingDistributionSamplePDF(d, s, dir);
        out3[0] = dir.x;
        out3[1] = dir.y;
        out3[2] = dir.z;
        return pdf;
    }
    catch (...)
    {
        return -1.0f;
    }
}

/// 1 when the initialized distribution passes upstream validation, else 0.
int pglb_surface_dist_validate(int dist)
{
    SurfaceSamplingDistribution *d = g_surfaceDists.get(dist);
    if (d == nullptr)
    {
        return -1;
    }
    try
    {
        return pglSurfaceSamplingDistributionValidate(d) ? 1 : 0;
    }
    catch (...)
    {
        return -8;
    }
}

/// Upstream distribution id (>= 0) or a code.
int pglb_surface_dist_id(int dist)
{
    SurfaceSamplingDistribution *d = g_surfaceDists.get(dist);
    if (d == nullptr)
    {
        return -1;
    }
    try
    {
        return static_cast<int>(pglSurfaceSamplingDistributionGetId(d));
    }
    catch (...)
    {
        return -8;
    }
}

// ---- field statistics ------------------------------------------------------

/// Release a statistics snapshot; the handle is stale afterwards.
int pglb_stats_release(int stats)
{
    FieldStatistics *obj = g_stats.take(stats);
    if (obj == nullptr)
    {
        return -1;
    }
    try
    {
        pglReleaseFieldStatistics(obj);
    }
    catch (...)
    {
        return -8;
    }
    return 0;
}

// Copy one PGLString (owned by the C API) into `out` (XIOM-owned) and release
// the C copy.  Returns the text length (bytes, NUL excluded) on success, -3
// when `cap` is smaller than m_size, -8 on internal failure.
static int pglb_copy_pglstring(PGLString str, uint8_t *out, int cap)
{
    if (out == nullptr || cap < 0)
    {
        pglReleaseString(str);
        return -2;
    }
    const int needed = static_cast<int>(str.m_size);
    int rc = 0;
    if (cap < needed)
    {
        rc = -3;
    }
    else
    {
        std::memcpy(out, str.m_str, static_cast<size_t>(needed));
        rc = needed - 1;  // m_size includes the terminating NUL
    }
    pglReleaseString(str);
    return rc;
}

/// Human-readable statistics text into `out` (NUL included in the copy).
int pglb_stats_string(int stats, uint8_t *out, int cap)
{
    FieldStatistics *obj = g_stats.get(stats);
    if (obj == nullptr)
    {
        return -1;
    }
    try
    {
        return pglb_copy_pglstring(pglFieldStatisticsToString(obj), out, cap);
    }
    catch (...)
    {
        return -8;
    }
}

/// CSV header for the statistics table into `out`.
int pglb_stats_csv_header(int stats, uint8_t *out, int cap)
{
    FieldStatistics *obj = g_stats.get(stats);
    if (obj == nullptr)
    {
        return -1;
    }
    try
    {
        return pglb_copy_pglstring(pglFieldStatisticsHeaderCSVString(obj), out, cap);
    }
    catch (...)
    {
        return -8;
    }
}

/// CSV row for the statistics table into `out`.
int pglb_stats_csv(int stats, uint8_t *out, int cap)
{
    FieldStatistics *obj = g_stats.get(stats);
    if (obj == nullptr)
    {
        return -1;
    }
    try
    {
        return pglb_copy_pglstring(pglFieldStatisticsToCSVString(obj), out, cap);
    }
    catch (...)
    {
        return -8;
    }
}

}  // extern "C"
