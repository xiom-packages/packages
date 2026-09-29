# xiom.onnx

> **Status:** `incubating` -- not yet conformance-tested; not yet published to the XIOM registry.
> **Scope:** ONNX model format parsing, export and execution.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `parser` | ONNX model graph parsing. |
| `exporter` | Model export to ONNX. |
| `runtime` | ONNX graph execution runtime. |
| `opset` | Operator set registry. |
| `convert` | Format conversion helpers. |
