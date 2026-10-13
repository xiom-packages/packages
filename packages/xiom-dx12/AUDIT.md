# AUDIT: xiom.dx12

## Status (2026-10-13)

**0.4.0 -- command recording added on the stable 0.3.1 baseline** (gate
evidence in `SPEC.md` sec. 7). The full D3D12 + DXGI + d3d12video surface
(0.3.0, published as `eco-v0.1.168`; promoted stable as 0.3.1,
`eco-v0.1.169`): 90 D3D12 interfaces -> 358 wrappers + 19 typed shims +
1162 consts + 9 free functions; 43 DXGI interfaces -> 163 wrappers + 246
consts + 6 free functions; 30 video interfaces -> 190 wrappers + 661
consts + 10 typed shims; 434 struct shapes (2238 size+offset consts).
0.4.0 adds allocator/list lifecycle, submission
(`dx12_execute_one`), and fence signal/wait (`dx12_fence_wait`).  Suite
**42/42 x2** on v0.64.4 (live device / WARP / swapchain / video /
recording witnesses + error paths); trap-14 byte-level grep clean.

| Item | State |
|------|-------|
| Compiler | v0.64.4 |
| Pin | DirectX-Headers @ `461ef513` (`d3d12.h` SHA256 `AFA193D3...`); DXGI: Windows SDK 10.0.26100.0 headers; IIDs + vtable slots in `SPEC.md` sec. 2 |
| Link model | none; the bridge resolves `d3d12.dll`/`dxgi.dll` via `LoadLibraryA`/`GetProcAddress` (`--link user32` only for the swapchain's hidden window) |
| Build | `port.args.json`: 8 `--c-source` bridges (probe + calls + structs for D3D12/DXGI/video) + `--link user32` |
| FFI confinement | all `unsafe`/`extern` in `dx12.xi`/`dxgi.xi`/`video.xi` + the generated wrapper modules; the C bridges are plain C |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 42/42 x2** on an NVIDIA RTX 3070 Ti (foundation + generated surface + struct metadata + DXGI + video + command recording + error paths), plus deterministic SKIP classification |

## Design notes

- The COM ABI is hand-declared in C (no `d3d12.h`/`dxgi.h` include),
  following the `xiom.dxc` precedent: GUIDs, vtable slot indices and call
  signatures are pinned in `SPEC.md` sec. 2 and verified against the
  pinned headers.
- `xd12_unload`/`xd12_dxgi_unload` release held objects + library
  handles; the suite runs probe -> unload without residue.
- The Agility SDK is deliberately NOT a build or runtime dependency: the
  OS runtime is the target; a newer Agility runtime is a pinned
  test-runtime option only (never the declaration source).
- **0.4.0 recording:** COM object parameters are typed `Int` in the
  generated surface (C side `void*`) because `Int as *UInt8` is not
  value-preserving on v0.64.4 (**B-25**, B-20 family; repro
  `docs/repro/bindings-pilot/ptr-cast/`).  The `Int` path is exact --
  witnessed in-suite by the handle-fidelity check.  `dx12_fence_wait`
  takes the fence as `Int` and casts in C.

## Known limitations

- Windows x64 only; the OS runtime may predate newer D3D12 features (the
  Agility test-runtime option is documented in `PROVENANCE.md`).
- 97 struct shapes (anonymous unions / bitfields / function-pointer
  members) are not emitted as metadata; they are listed in
  `docs/struct_meta_manifest.json` and built byte-indexed by callers
  (`dx12_poke_u32/u64`).
- Command recording core shipped in 0.4.0; recording conveniences
  (resource barriers, bundles, command signatures) are the next
  candidates on ask.
- Compiler workarounds carried (accepted, expiry = next compiler pin for
  B-23/B-24/B-25): B-23 -- `null` literal -> C garbage, use
  `dx12_null_ptr()`; B-24 -- owned-slot reads must be byte-indexed,
  pointer-edged flows via C return values; B-25 -- handles cross as `Int`
  params or int64 C-helper args, never `x as *UInt8`; B-22 -- the 3
  callback-param methods take a raw handler address (XIOM handlers cannot
  cross to C yet).
