# xiom-parser-fw

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Framework for building recursive-descent and precedence-climbing parsers.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `token` | Token representation and classification |
| `grammar` | Grammar rule declarations and production helpers |
| `parser` | Core recursive-descent parsing engine |
| `precedence` | Precedence-climbing and Pratt binding-power resolution |
| `recovery` | Error recovery and panic-mode resynchronization |
| `parse_tree` | Parse-tree node model produced by the engine |
