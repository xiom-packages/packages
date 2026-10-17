# Audit -- xiom.tensorrt 0.1.0

Date: 2026-10-17. Verdict: **PASS**, live-verified.

## Environment

| Item | Value |
|---|---|
| Host | Windows x64, NVIDIA GeForce RTX 3070 Ti, compute capability 8.6 |
| Driver / CUDA UMD | 616.92 / 13.4 |
| TensorRT runtime | 10.16.1.11 (`nvinfer_10.dll`), SHA-256 `ED0D4536...A493` |
| TensorRT headers (reference only) | `NVIDIA/TensorRT` `v10.16`, commit `52399f55...` |
| Compiler | XIOM v0.64.6 |
| Runtime directory | `E:\repos\tensorrt\wheel\tensorrt_libs` via `XIOM_TENSORRT_DIR` |

## Test evidence

Command:

```powershell
$env:XIOM_TENSORRT_DIR = "E:\repos\tensorrt\wheel\tensorrt_libs"
.\scripts\port.ps1 -Package xiom.tensorrt -TimeoutSec 300
```

- Live run 1: **55 passed / 0 failed** (`port: PASS`).
- Live run 2: **55 passed / 0 failed** (`port: PASS`).
- SKIP run without `XIOM_TENSORRT_DIR`: **2 passed / 0 failed**, output
  `[PASS] skip-path ...`, `[SKIP] probe: LoadLibrary failed ...`,
  `live leg SKIP (runtime absent)`.
- Build time per live run: a few seconds; plan size ~16.5-18.1 KB.
- End-to-end result: identity/Mul-by-2 network produced exactly
  `2, 4, 6, 8` from input `1, 2, 3, 4` via `enqueueV3`.

Coverage map:

| Surface | Check(s) |
|---|---|
| Loader / version | probe default + bogus-name SKIP, 3/3 symbols, 10.16.1, `enqueueV3` mode |
| Logger | create, INFO/VERBOSE round trip, message count, last message |
| Builder | create, FP16/INT8/TF32 platform queries |
| Network | addInput [1,4], constant, PROD, output rename/mark, counts/accessors |
| Config | DEBUG flag set/clear, workspace default+256 MiB, tactic round trip |
| Serialize | plan size/data, save, load, size equality |
| Runtime | create, deserialize from host memory, deserialize from file plan |
| Engine | 2 IO tensors, names, dtype, mode, location, [1,4] shapes |
| Context | all-dims, setInputShape, address set/get |
| Execution | device alloc, H2D, enqueueV3, sync, D2H, exact result |
| Cleanup | ordered destroys, module unload |

## ABI review findings (fixed during bring-up)

1. **Large by-value returns.** `Dims` is 72 bytes. The MSVC x64 member-function
   ABI uses RCX = `this`, RDX = hidden return slot. A naive `Dims (*)(void*)`
   free-function call swaps the registers and crashes. The bridge declares
   `void (*)(void*, Dims*, ...)` for `getDimensions` and `getTensorShape`.
2. **`Weights` layout.** The 10.16 struct is `{type, values, count}`, not
   `{values, type, count}`. Getting this wrong made `addConstant` return null.
3. **Constant weight lifetime.** TensorRT holds weights by reference until
   build. The bridge stores the Float32 vector in the network entry before
   calling `addConstant`; a local vector would dangle.
4. **Config flag API.** 10.16 has `setFlag(flag)` and `clearFlag(flag)` as
   separate void methods, plus `getFlag(flag)`. The bridge dispatches the XIOM
   boolean form to set/clear.
5. **Runtime vtable.** The blob/size `deserializeCudaEngine` overload is slot
   3, not slot 2 (the stream-reader overload occupies slot 2).
6. **CUDA context order.** TensorRT uses the current context. `trt_cuda_init`
   retains and activates the primary context, and the bridge re-activates it
   before builder/deserialize/context/enqueue calls.

## Known limitations / risks

- **ABI pin is exact (10.16.x).** The bridge rejects other majors/minors with
  `TRT_VERSION_UNSUPPORTED`. A future 10.17 runtime needs a re-pin and a fresh
  slot-map verification (SPEC §9). This is deliberate: guessing a vtable is
  worse than failing loudly.
- **Windows x64 only.** No Linux `.so` path in 0.1.0.
- **8.x not enabled.** `enqueueV2` / `buildEngineWithConfig` are documented as
  the fallback plan, not implemented.
- **No ONNX parser.** Networks are built through the definition API.
- **Single-threaded handles.** No per-handle locking beyond the logger mutex.
- **Bulk IO record workaround.** The first implementation returned
  `Vec[TrtTensorInfo]` (record containing a `Vec[Int]`), but the current XIOM
  codegen corrupted the record fields (name/dtype/mode/dims). The shipped
  helper returns `Vec[Str]` names; per-name accessors are verified and cover
  the shape/metadata queries. Tracked in ROADMAP 0.1.x.
- **SKIP classification is generous on CUDA init.** `TRT_CUDA_FAILED` during
  `trt_cuda_init` is treated as SKIP (the runtime/host may be absent). A genuine
  driver failure after init still fails the affected check.
- **No hard version check of the header minor at run time beyond 10.16.** The
  headers are not consulted at run time; the vtable map is the contract.

## Repository hygiene

- No NVIDIA binary/header/import library is committed.
- `PROVENANCE.md` records the license check, artifact hashes, and acquisition
  gate.
- `trt-test.plan` is a local artifact covered by `.gitignore`.
- The package compiles and passes the deterministic SKIP check on hosts without
  TensorRT or a CUDA device.

## Recommendation

Ship as incubating 0.1.0. Live evidence is strong (55/55 twice, exact numeric
result, both plan-deserialization paths). Re-pin only with the procedure in
SPEC §9.
