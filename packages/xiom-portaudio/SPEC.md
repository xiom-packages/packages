# xiom-portaudio — SPEC
**Phase**: 5 (Nice-to-Have) | **Priority**: Low
**Status**: Implemented | **Depends on**: xiom.ffi
PortAudio — cross-platform audio I/O. System-installed. Day effort.

## Implementation Status

- `portaudio.xi` — 25 extern C FFI declarations, 9 format constants, 30 error constants, 5 flag constants, 21 safe wrapper functions, `PaStream` type alias
- `tests/test_conformance.xi` — 38 conformance tests (constants, lifecycle, device query, version, error text, stream state, sleep, API presence, types, edge cases)
- `ROADMAP.md` — Phase 2 plans (C bridge, buffer marshaling, structs, callbacks, integration tests)
