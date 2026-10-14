# ROADMAP -- xiom.openpgl

Current: **0.1.0** -- sample-storage trained surface guiding field; CPU_4
device; direction sampling + PDF queries; field statistics; deterministic
training; typed errors.  x2 green on the pinned v0.64.4 toolchain.

Planned, in rough order:

1. **0.2.0 -- path segment storage feed.** Bind `pathsegmentstorage.h`
   (16 symbols): reserve, add segment/sample, propagate, validate,
   calculatePixelEstimate.  This is the canonical renderer feed (the
   current sample-storage feed is the same `SampleContainer` on the
   inside).  Needs a deterministic path-segment fixture in the suite.
2. **0.2.x -- volume sampling distribution.** Bind the volume query half
   (PDF/sample/validate/id + field-side create/init/release, 16 symbols
   incl. the fluence/inscattered-radiance pairs) and extend the suite with
   a volume-sample feed (flag bit 0) plus volume PDF checks.
3. **CPU_8 (AVX2) device.** Blocked on the toolchain exposing `-m` flags
   to `--c-source` (or clang applying `target` attributes to lambdas);
   see SPEC.md section 5.  Until then `device_create(8, ...)` is a typed
   error by declaration.
4. **Field persistence.** `pglFieldStoreToFile` /
   `pglDeviceNewFieldFromFile` and `pglSampleStorage*` file I/O
   (path-based; needs the XIOM side to hand a path as an owned byte buffer
   and the bridge to build a std::string from it).
5. **Surface distribution extras.** Cosine-product application and the
   radiance/irradiance integrator pair (`...IncomingRadiance`,
   `...OutgoingRadiance`, `...Irradiance`), plus `pglSurfaceSamplingGetRegion`.
6. **Merge/compare utilities** for sample storage and fields (useful for
   distributed training).

Non-goals for this package: image-space guiding buffer (upstream optional
feature, needs tinyexr/OIDN) and the Open PGL C++ wrapper headers
(`include/openpgl/cpp/`, vendored but not compiled).
