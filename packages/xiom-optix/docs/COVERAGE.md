# COVERAGE: xiom.optix 0.1.0

Target: OptiX 9.1 host API, `OPTIX_ABI_VERSION` 118, via the user's
`nvoptix.dll`.  "Live" = exercised on the RTX 3070 Ti / driver 616.92 host in
the conformance suite; "declared" = typed API present but the happy path
needs a valid user PTX (SDK-gated).

## Essentials

| # | Essential | XIOM API | Bridge slots | Evidence |
|---|-----------|----------|--------------|----------|
| 1 | Context create | `optix_context_create` | 2 (ctx create) | live |
| 2 | Context destroy | `optix_context_destroy` | 3 (ctx destroy) | live |
| 3 | Context validate | `optix_context_validate` | 4 (get property), 9 (cache get) | live |
| 4 | Device context options | `OptixContextOptions` | 2, 6, 7 | live (validation/log/cache-enable; location wired) |
| 5 | Module load | `optix_module_load` | 12 (module create) | live error path (invalid PTX, native 7200 + log); success declared |
| 6 | Raygen group | `optix_program_group_create(..., kind=0)` | 24 | declared (needs PTX) |
| 7 | Miss group | `optix_program_group_create(..., kind=1)` | 24 | live (null-miss form) |
| 8 | Hitgroup | `optix_program_group_create(..., kind=2)` | 24 | declared (needs PTX) |
| 9 | Group destroy | `optix_program_group_destroy` | 25 | live |
| 10 | SBT build | `optix_sbt_build` | 48 (pack header), CUDA HtoD | live (miss record + device readback) |
| 11 | SBT record size/count/read | `optix_sbt_get_*`, `optix_sbt_read_record` | CUDA DtoH | live |
| 12 | Pipeline create | `optix_pipeline_create` | 27 | live validation error (raygen-less, native 7001 + log); success declared |
| 13 | Pipeline destroy | `optix_pipeline_destroy` | 28 | live (guard) |
| 14 | Launch params buffer | `optix_params_create/write/read/destroy` | CUDA alloc/copy | live (64-byte round trip) |
| 15 | Launch | `optix_launch` | 49 | declared (needs a raygen pipeline) |
| 16 | Typed errors + SKIP | `OptixError`, `optix_error_is_skip` | 0/1 error text | live + SKIP run |
| 17 | Probe / classification | `optix_probe`, `optix_probe_named` | 0-4, CUDA | live + deterministic absent path |

## Constants and helpers

- `OPTIX_ABI_PIN = 118`, SBT header 32 B, alignment 16 B.
- Program-group kinds 0/1/2 map to OptiX `0x2421/0x2422/0x2424`.
- `optix_sbt_record_size_for` mirrors the bridge's floor/round-up math.
- `optix_error_kind_name`, `optix_error_is_skip`, `optix_last_error_message`,
  `optix_last_native_code`.

## Not in 0.1.0

Acceleration structures, denoiser, callables/exceptions, multi-record SBT
arrays, external CUDA contexts/streams, Linux, older-ABI negotiation.  See
`ROADMAP.md`.
