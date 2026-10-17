# SPEC: xiom.cudnn -- NVIDIA cuDNN bindings (runtime loader, nothing vendored)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.cudnn` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Target | NVIDIA cuDNN classic (graph-free) runtime API |
| Upstream | `nvidia-cudnn-cu12` **9.27.0.42** (NVIDIA proprietary EULA; **nothing vendored**) |
| Companion runtime | `nvidia-cublas-cu12` (cuDNN's declared dependency) + `nvcuda.dll` (NVIDIA display driver) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (soname set `cudnn64_9.dll` / `cudnn64_8.dll`) |
| Compiler pin | v0.64.6 |
| Stdlib range | `>=0.60.0 <1.0.0` |

## 2. G2 pin: soname + entry points + constants + sample

**Sonames (search order):** `cudnn64_9.dll` (primary), `cudnn64_8.dll`
(fallback). An explicit directory is searched as `<dir>\`,
`<dir>\bin\`, and `<dir>\nvidia\cudnn\bin\`; a path ending in `.dll`
is loaded directly. With no explicit directory the loader reads
`XIOM_CUDNN_DIR`, then `CUDNN_DIR`, then PATH. A **non-empty explicit
directory never falls back to PATH**, which makes the SKIP path
deterministic on every host.

**Pinned wheel:** `nvidia_cudnn_cu12-9.27.0.42-py3-none-win_amd64.whl`

| Item | Value |
|------|-------|
| Wheel bytes | 743,068,852 |
| Wheel SHA256 | `06E9B0026F3BAD97D2B58666330FABEC04FE1672F776661ECB0CE0029C27F142` |
| Installed header set (9 files, reference only -- not committed) | combined SHA256 `2EDFAA823755BFB62AFA0D69C38F4E1AAF7A521707953400D41EB2227E63B353` |
| Wheel `License.txt` SHA256 | `49CF79BDB35734B52FE6203013B3BD759F81E998CD32AA2C65C51DB9A88C61D2` |
| License expression | `LicenseRef-NVIDIA-Proprietary` (NVIDIA SDK EULA) |

Per-header SHA256 (sorted `name`/hash manifest used for the combined hash):

| Header | SHA256 |
|--------|--------|
| cudnn.h | `1C926A330FF35736B3B5AF7F4AC32AD8C35C72E0DBCFC952F78BED59A4E7B05C` |
| cudnn_adv.h | `527B2D3772A2E41F394489DC505D25DDC0DDAD7AA85F15D3E907D54EA7EA4754` |
| cudnn_backend.h | `99B10AD35E52C530848DCE58D29B8843EB8A80C1819D1F9E9131BAB430C76825` |
| cudnn_cnn.h | `0893193835B0CD5FC808D3DB5E22550F9C289A5026F66090B0B07B792F31AE64` |
| cudnn_gnn_ops.h | `D831C3FB49949EE3A64B563F30506CFDD490B00D62DF9C4E270BB321896B1FBF` |
| cudnn_graph.h | `526986FCC5D7EC89E407EBC054C4F16C81237D6BD17630C4A3759BE6CF7170CC` |
| cudnn_ops.h | `8428AC358370A556B773075072DA2E7290A9B93A60CD2476A277D4AF342F62AF` |
| cudnn_subquadratic_ops.h | `9B8C01398BED1F1F4264839884CA500230E8EC9C3553606DB515F0680EB94C8F` |
| cudnn_version.h | `8E0FA1A82BE651829999A599870995C52C79C5BD1E8ABE553D0413C8137B4E87` |

**Version encoding:** `CUDNN_MAJOR 9`, `CUDNN_MINOR 27`, `CUDNN_PATCHLEVEL 0`
-> `cudnnGetVersion() == 92700` on the pin. The suite accepts any positive
version and records the exact value.

**Recorded live sample (reference, not the pin):** Windows x64, NVIDIA
GeForce RTX 3070 Ti, compute capability 806 (8.6), driver API 13040
(13.4), cuDNN 92700, convolution workspace 0 bytes for the probe shape.

### Re-pin procedure

1. `pip download nvidia-cudnn-cu12==<version> --no-deps --only-binary=:all:`
   and record the wheel SHA256.
2. Re-extract `nvidia/cudnn/include/*.h`; recompute the sorted per-header
   SHA256 manifest and the combined hash; update this table, `PROVENANCE.md`,
   and `AUDIT.md`.
3. Confirm the declared exports still exist with
   `llvm-readobj --coff-exports <bin>\cudnn64_9.dll` (the 25 names in §4).
4. Re-run `scripts/port.ps1 -Package xiom.cudnn -TimeoutSec 300` twice;
   update `STATUS.json` and `README.md`.

## 3. Declared surface (essentials subset -- exact list)

The package declares **25 cuDNN entry points** plus **11 CUDA driver support
entry points**. This is the complete declared surface: no other cuDNN
symbol is claimed. Coverage is 25/25 bound and exercised (see `COVERAGE.md`).

| Group | Functions |
|-------|-----------|
| Core (4) | `cudnnGetVersion`, `cudnnCreate`, `cudnnDestroy`, `cudnnGetErrorString` |
| Tensor descriptors (4) | `cudnnCreateTensorDescriptor`, `cudnnDestroyTensorDescriptor`, `cudnnSetTensor4dDescriptor`, `cudnnGetTensor4dDescriptor` |
| Filter descriptors (3) | `cudnnCreateFilterDescriptor`, `cudnnDestroyFilterDescriptor`, `cudnnSetFilter4dDescriptor` |
| Convolution (5) | `cudnnCreateConvolutionDescriptor`, `cudnnDestroyConvolutionDescriptor`, `cudnnSetConvolution2dDescriptor`, `cudnnGetConvolutionForwardWorkspaceSize`, `cudnnConvolutionForward` |
| Activation (4) | `cudnnCreateActivationDescriptor`, `cudnnDestroyActivationDescriptor`, `cudnnSetActivationDescriptor`, `cudnnActivationForward` |
| Pooling (4) | `cudnnCreatePoolingDescriptor`, `cudnnDestroyPoolingDescriptor`, `cudnnSetPooling2dDescriptor`, `cudnnPoolingForward` |
| Softmax (1) | `cudnnSoftmaxForward` |
| CUDA driver support (11) | `cuInit`, `cuDeviceGet`, `cuDeviceGetName`, `cuDeviceGetAttribute`, `cuCtxCreate_v2`, `cuCtxDestroy_v2`, `cuMemAlloc_v2`, `cuMemFree_v2`, `cuMemcpyHtoD_v2`, `cuMemcpyDtoH_v2`, `cuCtxSynchronize` |

**Why the classic API:** the mission allows the graph-free v8-style forward
path. In the pinned 9.27 headers these entry points still exist and are
exported by `cudnn64_9.dll` (upstream marks them deprecated since 9.0, not
removed). The graph/frontend surface is deliberately out of scope for 0.1.0
(`ROADMAP.md`).

**Constants bound:** `CUDNN_STATUS_SUCCESS/NOT_INITIALIZED/BAD_PARAM/
NOT_SUPPORTED/INTERNAL_ERROR/EXECUTION_FAILED`; `CUDNN_DATA_FLOAT`;
`CUDNN_TENSOR_NCHW`; `CUDNN_CONVOLUTION`, `CUDNN_CROSS_CORRELATION`;
`CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_GEMM`; `CUDNN_ACTIVATION_RELU`;
`CUDNN_NOT_PROPAGATE_NAN`, `CUDNN_PROPAGATE_NAN`; `CUDNN_POOLING_MAX`;
`CUDNN_SOFTMAX_FAST/ACCURATE/MODE_INSTANCE/MODE_CHANNEL`.

## 4. Design and safe boundary (G5)

`cudnn.xi` is the only module with `unsafe`/`extern "C"`. It calls the
integer-only C bridge (`src/cudnn_bridge.c`), which:

- resolves every cuDNN and CUDA driver entry point with `GetProcAddress`
  (cuDNN entry points use `CUDNNWINAPI` = `__stdcall` on Windows);
- owns one CUDA context created lazily with `cuCtxCreate_v2` and one
  cuDNN handle per `cudnn_handle_create()`;
- passes opaque handles, descriptors and device addresses as `Int` and
  writes out-parameters only into **XIOM-owned** `Vec[Int]` /
  `Vec[Float32]` slots (B-20/B-11 discipline); no foreign-pointer reads and
  no raw pointer arithmetic;
- returns small negative classifier codes or the unchanged positive
  `cudnnStatus_t`.

Classification:

| Raw code | Kind | Suite |
|----------|------|-------|
| `-100` loader missing | `CUDNN_LOAD_ABSENT` | SKIP |
| `-102` `nvcuda.dll` missing, `-104` no device | `CUDNN_NO_DEVICE` | SKIP |
| `-101` required export missing | `CUDNN_LOAD_ABI` | FAIL |
| `> 0` `cudnnStatus_t` | `CUDNN_API_ERROR` | FAIL |
| `-103`, `-105`, other | `CUDNN_RUNTIME_ERROR` | FAIL |

## 5. Test contract

Suite: `tests/test_conformance.xi` -- **60 checks**:

1. deterministic SKIP: a bogus explicit directory classifies as
   `CUDNN_LOAD_ABSENT` on every host;
2. live self-contained probe (`cudnn_probe_auto`): version, tensor dims and
   NCHW strides, convolution `54/63/90/99`, ReLU of the convolution, ReLU
   clamp on `(-1,2,-3,4) -> (0,2,0,4)`, 2x2 max pool `99`, softmax
   `(1,2,3,4)` values and sum 1, module/device/capability/workspace;
3. full low-level declared surface (`check_surface`): load/version/error
   text, handle, all descriptor create/set/get/destroy calls, workspace
   query, device alloc/upload/download/sync/free, convolution forward,
   activation forward (positive and negative), pooling forward, softmax
   forward (accurate/channel and fast/instance), then teardown.

Command (cwd = package directory; the runner hook adds the C source):

```
scripts/port.ps1 -Package xiom.cudnn -TimeoutSec 300
```

With the runtime absent the suite reports one SKIP line and exits 0.

## 6. Scope and limitations

- 4D NCHW float tensors and the classic forward APIs only.
- Default CUDA stream 0; no stream/event surface in 0.1.0.
- No backward passes, no graph/frontend API, no fused ops.
- Windows x64 only; the loader is written for `cudnn64_9.dll` /
  `cudnn64_8.dll`.
- cuDNN 9 sub-libraries dynamically require `cublasLt64_12.dll`; the
  user-supplied `nvidia-cublas-cu12` package provides it. The bridge
  resolves cuDNN from an explicit directory but relies on the normal DLL
  search path (PATH) for the cuBLAS dependency.
- The `cudnn64_8.dll` fallback path is implemented but has no live run on
  this host (only 9.27.0.42 was exercised).
- 100% coverage means **100% of the declared essentials subset**, not all
  cuDNN symbols.
