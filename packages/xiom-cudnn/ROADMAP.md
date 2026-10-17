# ROADMAP: xiom.cudnn

## 0.1.0 -- essentials (this release)

- Multi-soname runtime loader (`cudnn64_9.dll`, `cudnn64_8.dll`) with
  SKIP-safe classification; explicit directory / `XIOM_CUDNN_DIR` /
  `CUDNN_DIR` / PATH search.
- Core handle + version + error text.
- 4D tensor, filter, convolution, activation and pooling descriptors
  (create/set/get/destroy).
- Classic graph-free forward path: `cudnnConvolutionForward` with a
  workspace query, `cudnnActivationForward` (ReLU), `cudnnPoolingForward`,
  `cudnnSoftmaxForward`.
- CUDA driver device-memory support for the operation surface.
- Self-contained known-shape conv+ReLU/pool/softmax live probe.
- 25/25 declared cuDNN entry points bound and exercised.

## 0.2.0 -- operational depth

- Stream/event surface (`cudnnSetStream` + an XIOM stream handle).
- N-dimensional descriptors (`cudnnSetTensorNdDescriptor`,
  `cudnnGetTensorNdDescriptor`, N-D filter/convolution/pooling).
- More activations (sigmoid/tanh/ELU/clipped ReLU/swish) and pooling modes
  (average include/exclude padding, deterministic max).
- Log-softmax + softmax fast/instance combinations in the public API.
- fp16/bf16 data types (`CUDNN_DATA_HALF`, `CUDNN_DATA_BFLOAT16`).

## 0.3.0 -- graph/frontend route

- Evaluate the cuDNN 9 graph API (`cudnn_backend.h` / `cudnn_graph.h`) as a
  separate module family; keep the classic surface as the SKIP-safe floor.
- Fused conv+bias+activation and residual paths if the graph route lands.

## Later

- Linux loader (`libcudnn.so.9` / `.so.8`) and a Linux live leg.
- Backward passes (data/filter) and training helpers.
- Heuristic/engine selection instead of the fixed implicit-GEMM algorithm.
- Optional direct `nvidia-cudnn-cu12` pip discovery helper (never vendored).

## Out of scope

- Shipping NVIDIA binaries/headers.
- A full 1:1 transcription of every cuDNN symbol (thousands); the package
  claims only the declared essentials subset.
