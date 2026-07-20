# xiom-onnx — SPEC

**Phase**: 1 (Core Foundation) | **Priority**: HIGH
**Status**: SPEC only — no implementation yet
**Depends on**: xiom.ffi (stdlib), xiom-libtorch (optional, for execution)

## What it wraps
ONNX Runtime — cross-framework ML model inference engine.
Load models from PyTorch, TensorFlow, scikit-learn, etc.

## Dependencies

| What | How | Size |
|------|-----|------|
| ONNX Runtime | System-installed. `winget install onnxruntime`, `apt install libonnxruntime-dev` | ~15MB |
| C compiler | For building bridge .obj | — |

## Bundling strategy
**System-installed only.** ONNX Runtime is available via package managers.

## API surface

```xiom
module xiom.onnx

// Session
pub fn session_new(model_path: Str) -> Result[Session, Str]
pub fn session_free(s: Session)

// Inference
pub fn session_run(s: &Session, inputs: Map[Str, Tensor]) -> Result[Map[Str, Tensor], Str]

// Metadata
pub fn session_input_count(s: &Session) -> Int
pub fn session_output_count(s: &Session) -> Int
pub fn session_input_name(s: &Session, idx: Int) -> Str
pub fn session_output_name(s: &Session, idx: Int) -> Str

// Providers
pub fn available_providers() -> Vec[Str]  // ["CPU", "CUDA", "TensorRT", ...]
pub fn session_set_providers(s: &mut Session, providers: Vec[Str])
```

## Contract coverage target
- Model file: `requires: io.file_exists(path)`
- Session: `requires: s != 0`
- Providers: validate against available_providers()

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | Session create, run, free. CPU only. | Day |
| 2 | CUDA/TensorRT providers, metadata queries | Day |
| 3 | Custom ops, I/O binding, execution providers | Weekend |
