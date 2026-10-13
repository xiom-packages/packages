# ROADMAP: xiom.spz

## Phase 1 -- shipped in 0.1.0 (2026-10-13, compiler v0.64.4)

- vendored spz v3.0.0 (5bf2945d, MIT) + zlib 1.3.1 + zstd 1.5.7 amalgamation;
- flat C bridge over the full public surface (read/unpack/pack/PLY/legacy
  gzip/serialize, cloud methods, math helpers);
- 100% declared-surface coverage (docs/COVERAGE.md, fail-closed generator);
- conformance suite 74/74 x2: v4/v3/v2 round trips with documented
  tolerances, quantizer byte pins, six typed corrupt-input classes, file and
  PLY round trips.

## Phase 2 -- candidates (not scheduled)

- **Extension support** (`SPZ_BUILD_EXTENSIONS` + `splat-extensions.h`) if a
  consumer needs Adobe safe-orbit-camera metadata; requires vendoring the
  `extensions/cc` tree and extending the coverage inventory.
- **Streaming decode**: the format is a single compressed blob; a
  sequential API (`spz_stream_begin/pull/end`) would give consumers a pull
  model without materializing the whole workspace -- new bridge state, needs
  the handle-lifecycle discipline.
- **Packed-handle reuse**: `spz_packed_gaussian*` re-parses the container per
  call (stateless by design).  If cook tools need many `at(i)` calls, add an
  opaque bridge handle (create/free pair) sized over `PackedGaussians`.
- **PLY extra elements**: expose `PlyExtraElement` metadata rows when a
  consumer needs to round-trip non-vertex PLY data.
- **Native surface extension**: once `xiom.spz` consumers exist, consider
  splat-set operations (merge/sort) as a separate pure-XIOM package rather
  than growing the binding.
