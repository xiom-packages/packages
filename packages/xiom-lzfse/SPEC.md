# SPEC: xiom.lzfse -- LZFSE bindings (vendored Apple sources)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.lzfse` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | LZFSE -- https://github.com/lzfse/lzfse (Apple Inc.) |
| Upstream version pinned | tag **`lzfse-1.0`** |
| Upstream license | BSD-3-Clause (`vendor/LICENSE`, Apple) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (no platform-specific XIOM code) |
| Compiler pin | v0.64.1 |

## 2. Vendored path (G2 pin)

The upstream library sources are vendored **verbatim** into `vendor/` and
compiled into the test binary via `--c-source` (seven entries in
`port.args.json`, matching upstream's `add_library` source list); there is no
system library, no runtime DLL, and no build script.

### Archive provenance

| Artifact | Value |
|----------|-------|
| Download | https://github.com/lzfse/lzfse/archive/refs/tags/lzfse-1.0.tar.gz |
| Size / SHA256 | 50,694 bytes / `CF85F373F09E9177C0B21DBFBB427EFAEDC02D035D2AADE65EB58A3CBF9AD267` |

### Vendored files (SHA256)

| File | Bytes | SHA256 |
|------|-------|--------|
| `LICENSE` | 1,514 | `2A20082C2219EDBBDB2E862A0566BA4F762A564ADE7C04B09250AE4464BC4B32` |
| `lzfse.h` | 5,679 | `A71A29096C022AC4B42AF79A8B014538B93CC00BD30295F51AD8B49F3F65A304` |
| `lzfse_internal.h` | 25,264 | `D08DC29D5440775DE279D36783729131329DF10CFFD43EC6EFF7DCFCEEF9F570` |
| `lzfse_fse.h` | 24,556 | `4E5C2228A4BB5E5F3FAF4639D5688BC7CAA5CF0C0F3A971ADA4FBE3631F3A533` |
| `lzfse_fse.c` | 7,945 | `A97E309975487AF269456A4E87EF516AEDAF82CE469E37971FD5676F9CD5956B` |
| `lzfse_encode_tables.h` | 15,250 | `628319241E7FF7B95E1BD9F02C0DCD38A92E48C3EF0662BEB31E50D2E65F70A9` |
| `lzfse_tunables.h` | 3,516 | `99D435CA45B32BA0CC273A2862BA714762610513EED469BC590BB092EA476B36` |
| `lzfse_encode.c` | 7,132 | `0FC987CE4BDF7676EB3707C174A09E23B2EDB4987938FA0C92150CDC46558387` |
| `lzfse_encode_base.c` | 27,437 | `AD69AF28E09D5A4E40912BFBE67FB4C570A1E3186C7621DCA15B72C41830E34E` |
| `lzfse_decode.c` | 3,163 | `4211F54B19B9E75ADFE9C1C3797E24ECDE16620D0C48A30E5BAB2E57FB1A8E0F` |
| `lzfse_decode_base.c` | 24,921 | `721B4061E4E655F0940B7CABCF506356C152716526E630981CAF0E708D2F73D9` |
| `lzvn_encode_base.h` | 4,999 | `9525055FBCF2A4057727EAB2092F1382D8A25E75DCF9CFA32A7AE2CECF0EC282` |
| `lzvn_encode_base.c` | 21,367 | `6ABF10E82E46E0AE7F2ED1CB07A8636D28AE4E72F93E5A7DFF5C4831F6E76A07` |
| `lzvn_decode_base.h` | 2,696 | `D4C13BBF13B3616C1B1472E80B117857F1339A29A48006E5AAD450BCD6204C09` |
| `lzvn_decode_base.c` | 22,090 | `434647C83D4F3ED95C11465C5A3EC46F992EC94843928138039EA40BE623957D` |

`lzfse_main.c` (CLI) is intentionally not vendored. `.gitattributes` pins
`vendor/** -text` so the byte hashes survive fresh checkouts.

### Re-pin procedure

1. Download the new tag archive; verify the archive hash.
2. Replace `vendor/` from the upstream `src/` library list (`add_library` in
   `CMakeLists.txt`); update the table and the version rows in `README.md`/
   `AUDIT.md` in the same commit.
3. Re-run `scripts/port.ps1 -Package xiom.lzfse` (x2) and record the matrix.

## 3. Design and safe boundary (G5)

`lzfse.xi` is the only module with `extern "C"`: raw declarations plus safe
wrappers (`lzfse_encode_scratch_required`, `lzfse_decode_scratch_required`,
`lzfse_encode`, `lzfse_decode`). Buffers are XIOM-owned `Vec[UInt8]`
(`&mut` inputs for `as_mut_ptr`); scratch is allocated per call at the size
the library reports (684,384 bytes encode / 47,368 bytes decode on this
build). The LZFSE stream carries no queryable content size, so `lzfse_decode`
takes the output capacity; chunked/streaming decode is Phase 2.

## 4. Test matrix (recorded 2026-10-08, compiler v0.64.1)

| Configuration | Command | Result |
|---------------|---------|--------|
| Vendored sources | `scripts/port.ps1 -Package xiom.lzfse` | **PASS 7/7 x2** -- scratch sizes, 4096 -> 182 bytes, round-trip identity, 65536-byte round-trip identity, 1024-byte incompressible round-trip identity, invalid stream rejected |

No SKIP path exists (the library is compiled in); the runner hook resolves
`${PACKAGE_DIR}` for all seven `--c-source` entries.

## 5. Scope

One-shot encode/decode only. The pre-pilot module (`lzfse.xi` + stub
`src/lzfse_safe.xi`) was a placeholder set; it is preserved in git history.
Streaming/chunked decode, scratch reuse and a LZVN-only path are Phase 2
(`ROADMAP.md`).
