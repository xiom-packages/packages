# COVERAGE -- xiom.cudnn 0.1.0

Declared surface = **25 cuDNN entry points + 11 CUDA driver support entry
points**. All 36 are bound in `cudnn.xi` / `src/cudnn_bridge.c` and
exercised by `tests/test_conformance.xi` (live leg). There is no undeclared
cuDNN symbol and no declared-but-unexercised symbol.

## cuDNN entry points (25/25)

| # | cuDNN entry point | XIOM wrapper | Bridge | Test evidence |
|---|-------------------|--------------|--------|---------------|
| 1 | `cudnnGetVersion` | `cudnn_version`, `cudnn_load` | `cn_version` | version 92700 |
| 2 | `cudnnCreate` | `cudnn_handle_create` | `cn_handle_create` | handle created |
| 3 | `cudnnDestroy` | `cudnn_handle_destroy` | `cn_handle_destroy` | destroy PASS |
| 4 | `cudnnGetErrorString` | `cudnn_error_text` | `cn_status_string` | non-empty SUCCESS text |
| 5 | `cudnnCreateTensorDescriptor` | `cudnn_tensor_create` | `cn_tensor_create` | 4 descriptors created |
| 6 | `cudnnDestroyTensorDescriptor` | `cudnn_tensor_destroy` | `cn_tensor_destroy` | 4 destroys PASS |
| 7 | `cudnnSetTensor4dDescriptor` | `cudnn_tensor_set_4d` | `cn_tensor_set4d` | x/y/pool/softmax set |
| 8 | `cudnnGetTensor4dDescriptor` | `cudnn_tensor_get_4d` | `cn_tensor_get4d` | dims 1/1/4/4, strides 16/16/4/1 |
| 9 | `cudnnCreateFilterDescriptor` | `cudnn_filter_create` | `cn_filter_create` | created |
| 10 | `cudnnDestroyFilterDescriptor` | `cudnn_filter_destroy` | `cn_filter_destroy` | destroy PASS |
| 11 | `cudnnSetFilter4dDescriptor` | `cudnn_filter_set_4d` | `cn_filter_set4d` | 1x1x3x3 PASS |
| 12 | `cudnnCreateConvolutionDescriptor` | `cudnn_convolution_create` | `cn_conv_create` | created |
| 13 | `cudnnDestroyConvolutionDescriptor` | `cudnn_convolution_destroy` | `cn_conv_destroy` | destroy PASS |
| 14 | `cudnnSetConvolution2dDescriptor` | `cudnn_convolution_set_2d` | `cn_conv_set2d` | pad 0 stride 1 dil 1 |
| 15 | `cudnnGetConvolutionForwardWorkspaceSize` | `cudnn_convolution_workspace_size` | `cn_conv_workspace_size` | 0 bytes for implicit GEMM |
| 16 | `cudnnConvolutionForward` | `cudnn_convolution_forward` | `cn_conv_forward` | 54/63/90/99 |
| 17 | `cudnnCreateActivationDescriptor` | `cudnn_activation_create` | `cn_act_create` | created |
| 18 | `cudnnDestroyActivationDescriptor` | `cudnn_activation_destroy` | `cn_act_destroy` | destroy PASS |
| 19 | `cudnnSetActivationDescriptor` | `cudnn_activation_set` | `cn_act_set` | ReLU / not-propagate |
| 20 | `cudnnActivationForward` | `cudnn_activation_forward` | `cn_act_forward` | identity + clamp checks |
| 21 | `cudnnCreatePoolingDescriptor` | `cudnn_pooling_create` | `cn_pool_create` | created |
| 22 | `cudnnDestroyPoolingDescriptor` | `cudnn_pooling_destroy` | `cn_pool_destroy` | destroy PASS |
| 23 | `cudnnSetPooling2dDescriptor` | `cudnn_pooling_set_2d` | `cn_pool_set2d` | max 2x2 stride 2 |
| 24 | `cudnnPoolingForward` | `cudnn_pooling_forward` | `cn_pool_forward` | max = 99 |
| 25 | `cudnnSoftmaxForward` | `cudnn_softmax_forward` | `cn_softmax_forward` | accurate/channel + fast/instance |

## CUDA driver support (11/11)

| # | Entry point | Bridge use | Test evidence |
|---|-------------|------------|---------------|
| 1 | `cuInit` | context bring-up | live probe |
| 2 | `cuDeviceGet` | device 0 | live probe |
| 3 | `cuDeviceGetName` | device name | reported |
| 4 | `cuDeviceGetAttribute` | cc major/minor | cc 806 |
| 5 | `cuCtxCreate_v2` | one context | live probe |
| 6 | `cuCtxDestroy_v2` | `cudnn_shutdown` | teardown |
| 7 | `cuMemAlloc_v2` | `cudnn_device_alloc` | 9 allocations |
| 8 | `cuMemFree_v2` | `cudnn_device_free` | 9+ frees |
| 9 | `cuMemcpyHtoD_v2` | `cudnn_device_upload` | x/w/neg/softmax |
| 10 | `cuMemcpyDtoH_v2` | `cudnn_device_download` | conv/ReLU/pool/softmax |
| 11 | `cuCtxSynchronize` | `cudnn_device_sync` | PASS |

## Probe values (live RTX 3070 Ti, cuDNN 9.27.0.42)

| Check | Expected | Observed |
|-------|----------|----------|
| version | 92700 | 92700 |
| tensor dims | 1,1,4,4 | 1,1,4,4 |
| NCHW strides | 16,16,4,1 | 16,16,4,1 |
| convolution | 54,63,90,99 | 54,63,90,99 |
| ReLU(conv) | 54,63,90,99 | 54,63,90,99 |
| ReLU(-1,2,-3,4) | 0,2,0,4 | 0,2,0,4 |
| 2x2 max pool | 99 | 99 |
| softmax(1,2,3,4) | 0.0320586, 0.0871443, 0.2368828, 0.6439143 | match |
| softmax sum | 1.0 | 1.0 |
| workspace | 0 | 0 |
| compute capability | 8.6 | 806 |

## Totals

- cuDNN declared/bound/exercised: **25/25/25**.
- CUDA support declared/bound/exercised: **11/11/11**.
- Constants bound: 19 (see `SPEC.md` ??3).
- Suite checks: **60** (`[PASS]` markers; `scripts/port.ps1` x2).
- Vendored NVIDIA bytes: **0**.
- G2 pin: wheel `06E9B002...`, headers combined `2EDFAA82...`,
  license text `49CF79BD...` (details in `SPEC.md` / `PROVENANCE.md`).

## File ledger (committed)

`package.xi`, `cudnn.xi`, `src/cudnn_bridge.c`, `tests/test_conformance.xi`,
`port.args.json`, `.gitignore`, `README.md`, `SPEC.md`, `PROVENANCE.md`,
`AUDIT.md`, `COVERAGE.md`, `ROADMAP.md`, `STATUS.json`.
