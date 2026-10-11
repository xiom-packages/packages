# COVERAGE: xiom.dxc -- 100% dxcapi.h COM surface

Measured 2026-10-12 (xiom.dxc 0.3.0, compiler v0.64.3, DXC
1.9.0.5347 / Vulkan SDK 1.4.350.0).

## 1. Oracle vs bound vs runtime

| Layer | Count | Evidence |
|-------|-------|----------|
| Oracle interfaces (`IDxc*`) | **27** | `tools/gen_dxc.py` parses `C:\VulkanSDK\1.4.350.0\Include\dxc\dxcapi.h` (54,624 bytes, SHA256 `FF3CA20C5FF948D7B1050C4B96D1EE42A9ECC054724DC4DAFBEF50CC04FD1CDE`) |
| Oracle methods (pure virtual, IUnknown excluded) | **128** | same parse; per-interface inventory in `docs/DXC-INVENTORY.md` |
| Oracle CLSIDs / IIDs / free functions | 12 named (11 unique; `CLSID_DxcUtils` aliases `CLSID_DxcLibrary`) / 27 / 2 | same parse |
| Bound in the bridge | **128** | `xdxb_method_count()` counts the compiled bound-method table; the suite prints `bound=128/128` |
| Bound wrappers (XIOM) | **128** + loader/instance helpers | 13 generated modules; every method has one `extern "C"` stub and one typed wrapper |
| Runtime-resolved free functions | **2/2** (`DxcCreateInstance`, `DxcCreateInstance2`) | `dxc_resolved_free_functions()` after `dxc_load()`; missing `DxcCreateInstance` would fail the load (rc 2) |

`bound=N/N` is a runtime property of the **compiled bridge**: the table holds
`{name, interface, function pointer}` for every declared method
(`IDxcUtils::CreateBlobFromPinned`, ...), so a dropped stub breaks the count,
the per-interface buckets, and the link.

### Per-interface counts (all bound; runtime lane as noted)

| Interface | Methods | XIOM module | Runtime evidence |
|-----------|--------:|-------------|------------------|
| IDxcBlob | 2 | gen_blob | **functional**: GetBufferSize + GetBufferPointer (owned-slot copy, byte-indexed) |
| IDxcBlobEncoding | 1 | gen_blob | **functional**: GetEncoding (known=1, page=65001) |
| IDxcBlobWide | 2 | gen_blob | bound |
| IDxcBlobUtf8 | 2 | gen_blob | bound |
| IDxcIncludeHandler | 1 | gen_handler | **functional**: LoadSource (missing include -> clean failure) |
| IDxcCompilerArgs | 5 | gen_handler | class factory 1/1 (create) |
| IDxcLibrary | 10 | gen_legacy | class factory 1/1 (create) |
| IDxcOperationResult | 3 | gen_legacy | **functional**: GetStatus (S_OK and failure) |
| IDxcCompiler | 3 | gen_legacy | bound (superseded by IDxcCompiler3) |
| IDxcCompiler2 | 1 | gen_legacy | bound |
| IDxcLinker | 2 | gen_legacy | class factory 1/1 (create) |
| IDxcUtils | 13 | gen_utils | **functional**: CreateBlobFromPinned, CreateDefaultIncludeHandler |
| IDxcResult | 5 | gen_result | **functional**: GetOutput (x2), GetNumOutputs, HasOutput, PrimaryOutput |
| IDxcExtraOutputs | 2 | gen_result | bound |
| IDxcCompiler3 | 2 | gen_compiler3 | **functional**: Compile (vs_6_0), Disassemble |
| IDxcValidator | 1 | gen_validator | class factory 1/1 (create); `Validate` needs `dxil.dll` (absent on host) |
| IDxcValidator2 | 1 | gen_validator | bound; same `dxil.dll` note |
| IDxcContainerBuilder | 4 | gen_container | class factory 1/1 (create) |
| IDxcAssembler | 1 | gen_container | class factory 1/1 (create) |
| IDxcContainerReflection | 6 | gen_container | **functional**: Load, GetPartCount, FindFirstPartKind('DXIL') |
| IDxcOptimizerPass | 5 | gen_optimizer | bound |
| IDxcOptimizer | 3 | gen_optimizer | class factory 1/1 (create) |
| IDxcVersionInfo | 2 | gen_validator | **functional**: GetVersion (major 1), GetFlags |
| IDxcVersionInfo2 | 1 | gen_validator | bound |
| IDxcVersionInfo3 | 1 | gen_validator | bound |
| IDxcPdbUtils | 24 | gen_pdb | bound |
| IDxcPdbUtils2 | 25 | gen_pdb2 | class factory 1/1 (create) |

Factory summary from the suite: **9/9 convenience CLSIDs create via
`DxcCreateInstance`** (compiler-args, library, linker, validator, assembler,
container-reflection, optimizer, container-builder, pdb-utils) on top of the
compiler/utils pair.

## 2. Interfaces/methods not usable through the shipped DLL

COM methods are **vtable slots, not exports**, so "exported by the DLL" is
verified by (a) constructing the object and (b) calling the method. Findings on
this DLL (`C:\VulkanSDK\1.4.350.0\Bin\dxcompiler.dll`, 21,565,880 bytes,
FileVersion 1.9.0.5347, SHA256 `6E990D20...`):

- **No interface declared in the pinned oracle (`dxcapi.h`) was found
  unimplemented**: all 9 creatable classes construct successfully, and every
  exercised method returned a real result (see table above).
- **`CLSID_DxcDiaDataSource`** is the one oracle CLSID without an interface IID
  in `dxcapi.h` (its `IDiaDataSource` IID lives in DIA SDK headers). It is
  bound in the CLSID table and reachable through the generic
  `dxc_create_instance(clsid, iid)`; no convenience creator exists because the
  IID is not part of the oracle.
- **Methods requiring data we cannot fabricate in CI** are bound but not
  functionally exercised, and are listed as such: PDB pipelines
  (`IDxcPdbUtils*`, needs a full PDB), reflection consumers
  (`IDxcUtils::CreateReflection` / `GetPDBContents`, need a reflection IID
  consumer), `IDxcValidator::Validate` (needs the `dxil.dll` signing companion,
  not shipped in the SDK `Bin`), `DxcCreateInstance2` and the `IMalloc`-taking
  methods (`SetMalloc`, `MoveToBlob` — no IMalloc implementation on the XIOM
  side), `IDxcOptimizer::RunOptimizer` (needs a pass module),
  `IDxcLinker::Link` (needs library blobs), `IDxcAssembler` (needs LLVM
  bitcode input).
- `GetStringPointer` / `GetStringLength` on `IDxcBlobWide` / `IDxcBlobUtf8` are
  bound with owned-slot copies (UTF-16→UTF-8 converted bridge-side); exercised
  indirectly through `GetStringLength`-free paths only.

### Sibling public headers (upstream `include/dxc/`) — explicit non-goals

The pinned scope is `dxcapi.h` (the runtime API). The upstream source at the
pinned commit also ships sibling headers; a census probe (`DxcCreateInstance`
with `IID_IUnknown`, 2026-10-12, same DLL) records what the shipped factory
actually implements, so the boundary is proven, not assumed:

| Sibling header (not bound) | Declared surface | `DxcCreateInstance` probe |
|----------------------------|------------------|---------------------------|
| `dxctools.h` | `IDxcRewriter`, `IDxcRewriter2` (+`CLSID_DxcRewriter`) | **`S_OK` — creatable** (follow-up slice candidate) |
| `dxcisense.h` | 15 `CROSS_PLATFORM_UUIDOF` (IDxcCursor/Diagnostic/File/Inclusion/IntelliSense/Index/SourceLocation/SourceRange/...) | **`S_OK` — creatable** (follow-up slice candidate) |
| `dxcpix.h` | PIX debugger interfaces (`CLSID_DxcPixDxilDebugger`) | `0x80040154 REGDB_E_CLASSNOTREG` — not in this DLL |
| `dxcdxrfallbackcompiler.h` | DXR fallback (`CLSID_DxcDxrFallbackCompiler`, own `DxcCreateDxrFallbackCompiler` entry) | `0x80040154`; export **missing** in this DLL |
| `dxcerrors.h` | error-code macros only | n/a |
| `dxcapi.internal.h` | internal extensions (not public) | n/a |

These are **not skipped work**: the pinned oracle is `dxcapi.h` (SPEC §2), and
the census exists so the owner can open a follow-up slice for the two
creatable sibling classes if "public API" is meant to cover them.

## 3. Commands (reproducible)

```powershell
# regenerate all artifacts from the pinned header (deterministic)
python packages\xiom-dxc\tools\gen_dxc.py `
  --header "C:\VulkanSDK\1.4.350.0\Include\dxc\dxcapi.h" --package-dir packages\xiom-dxc
python packages\xiom-dxc\tools\gen_dxc.py ... --check   # exits 1 on any drift

# conformance suite (compiles src/dxc_probe.c + src/dxc_bridge.cpp)
& scripts\port.ps1 -Package xiom.dxc -TimeoutSec 900     # x2: PASS 20/20
```

Suite output (2026-10-12, DLL present):

```
bound=128/128
[PASS] surface: bridge table == dxcapi.h oracle methods (bound=128/128)
[PASS] surface: per-interface buckets match the oracle (27 interfaces, 128 methods)
[PASS] surface: every table entry carries its `Iface::Method` name
[PASS] surface: IID (27) + CLSID (12) tables and the 2 free functions are bound
[PASS] skip-path: absent compiler classified as DXC_LOAD_ABSENT (SKIP)
[PASS] probe: ps_6_0 'main' -> DXIL object (2532 bytes)
[PASS] runtime: DxcCreateInstance + DxcCreateInstance2 resolved at runtime
[PASS] runtime: IDxcUtils + IDxcCompiler3 created via DxcCreateInstance
[PASS] utils: CreateBlobFromPinned + GetEncoding round trip (utf8 pinned source)
[PASS] compile: IDxcCompiler3::Compile(vs_6_0, -E main) produced an IDxcResult
[PASS] compile: GetStatus == S_OK
[PASS] result: GetNumOutputs >= 2, HasOutput(OBJECT) == 1, PrimaryOutput() == DXC_OUT_OBJECT
[PASS] compile: DXC_OUT_OBJECT blob (2684 bytes) starts with 'DXBC' (byte-indexed)
[PASS] compile: bad HLSL -> nonzero status + non-empty DXC_OUT_ERRORS blob
[PASS] version: QueryInterface(IDxcVersionInfo) -> GetVersion major == 1
[PASS] factory: 9/9 CLSIDs create via DxcCreateInstance
[PASS] container: reflection Load + GetPartCount + FindFirstPartKind('DXIL')
[PASS] disasm: Disassemble(container) -> DXC_OUT_DISASSEMBLY blob with size > 0
[PASS] handler: default include handler resolves and reports missing files as failure
[PASS] lifecycle: AddRef/Release on IDxcCompiler3
```

SKIP-green: with `dxcompiler.dll` absent the runtime section reports `SKIP`
(single PASS) while the DLL-independent surface checks (`bound=N/N`,
per-interface buckets, tables, names) still run; absent-compiler classification
is exercised on every host via a bogus soname.

## 4. Generated ABI + discipline (B-11..B-20)

- `src/dxc_abi.h` (generated): local C++ ABI — `GUID` layout, one vtable
  struct per interface with the **full flattened slot order** (IUnknown +
  base chain + declared methods; a derived interface missing the IUnknown
  prefix shifts every slot — this was caught by the runtime probe), plus
  `DxcBuffer`/`DxcDefine`/`DxcArgPair` layouts. No DXC/SDK headers at build.
- `src/dxc_bridge.cpp` (generated, 2,155 lines): `LoadLibraryA` +
  `GetProcAddress("DxcCreateInstance"/"DxcCreateInstance2")`; one
  `extern "C"` stub per method. Scalar ABI: objects cross as opaque `Int`
  handles; every out-param is written into an **XIOM-owned byte slot** as a
  little-endian scalar (4/8 B) or an owned copy (bytes/UTF-8) — XIOM never
  reads through a foreign pointer. String inputs are UTF-8 from XIOM and are
  converted bridge-side (surrogate-pair aware); COM-allocated out strings are
  copied out and freed via runtime-resolved `CoTaskMemFree`/`SysFreeString`
  (no import libraries).
- Generated XIOM wrappers take caller-owned `&mut Vec[UInt8]` slots and pass
  `.as_mut_ptr()` inside the wrapper; reads are byte-indexed
  (`dxc_rd_u32`/`dxc_rd_u64`) — no pointer arithmetic and no
  `ffi.ptr_write_*` at offsets on the XIOM side.
- Wrapper modules are family-split by interface (max 268 lines); the bridge
  table, vtable indices and counts are all generator-derived, and
  `--check` fails on any drift from the pinned header.
