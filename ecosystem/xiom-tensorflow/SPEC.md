# xiom-tensorflow — SPEC

**Phase**: 1 (Core Foundation) | **Priority**: HIGH
**Status**: SPEC only — no implementation yet
**Depends on**: xiom.ffi (stdlib)

## What it wraps
TensorFlow C++ API — Google's ML framework.
Alternative to PyTorch/LibTorch. Larger ecosystem, TF Serving, TF Lite.

## Dependencies

| What | How | Size |
|------|-----|------|
| TensorFlow C library | Download from tensorflow.org. Set `TF_DIR`. | ~500MB |
| CUDA Toolkit (optional) | System-installed for GPU | ~3GB |
| C++ compiler | For building bridge | — |

## Bundling strategy
**System-installed only.** Never bundle (500MB+).

## API surface

```xiom
module xiom.tensorflow

// Session + Graph
pub fn session_new() -> Result[Session, Str]
pub fn session_close(s: Session)
pub fn graph_new() -> Result[Graph, Str]
pub fn graph_free(g: Graph)

// Tensors
pub fn tensor_new(shape: Vec[Int], dtype: DType) -> Result[Tensor, Str]
pub fn tensor_from_data(data: &Vec[Float32], shape: Vec[Int]) -> Result[Tensor, Str]
pub fn tensor_free(t: Tensor)

// Operations
pub fn op_placeholder(g: &Graph, dtype: DType, shape: Vec[Int]) -> Result[Operation, Str]
pub fn op_const(g: &Graph, t: &Tensor) -> Result[Operation, Str]
pub fn op_add(g: &Graph, a: &Operation, b: &Operation) -> Result[Operation, Str]
pub fn op_matmul(g: &Graph, a: &Operation, b: &Operation) -> Result[Operation, Str]
pub fn op_relu(g: &Graph, input: &Operation) -> Result[Operation, Str]

// Execution
pub fn session_run(s: &Session, feeds: Map[Operation, Tensor], fetches: Vec[Operation]) -> Result[Vec[Tensor], Str]

// Model loading
pub fn saved_model_load(path: Str) -> Result[SavedModel, Str]
pub fn saved_model_run(m: &SavedModel, inputs: Map[Str, Tensor]) -> Result[Map[Str, Tensor], Str]

// GPU
pub fn gpu_available() -> Bool
pub fn gpu_device_count() -> Int
```

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | Session, graph, basic ops, tensor create/run | Weekend |
| 2 | SavedModel loading, full op set | Weekend |
| 3 | TF Lite, GPU delegation, TF Serving client | Week |
