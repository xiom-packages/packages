# xiom.wasm

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) WebAssembly binary *structure* reader:
> magic/version detection, unsigned LEB128 u32 decoding, section walking
> and export-name extraction. It understands the container, not the code.
> **Deps:** `xiom.std` only (`xiom.string.builder`; tests add `xiom.test`,
> `xiom.io`, `xiom.string`, `xiom.string.compare`, `xiom.encoding.hex`).

## What it is

`xiom.wasm` reads the outer structure of a WebAssembly binary module
(`.wasm`): the 8-byte magic + version header, the unsigned LEB128 varints
that size every section, the section table itself (id, payload offset,
payload size) and the UTF-8 export names of the export section. It is a
structural reader for tooling -- inventory, inspection, dispatch on
exported entry points -- not a validator and not a runtime.

Every function returns deterministic `Result` values with `wasm: `-prefixed
error strings; nothing panics on truncated or malformed input (see
`SPEC.md` for the byte-level rules and the full error catalog).

## API

| Function | Returns | Description |
|---|---|---|
| `wasm_is_module(data)` | `Bool` | True when `data` starts with magic `00 61 73 6D` + version `01 00 00 00`. |
| `wasm_leb_u32(data, off)` | `Result[(Int, Int), Str]` | Unsigned LEB128 u32 at `off`: `(value, offset_after)`, max 5 bytes. |
| `wasm_section_name(id)` | `Str` | `custom`/`type`/`import`/`function`/`table`/`memory`/`global`/`export`/`start`/`element`/`code`/`data`/`datacount`, else `unknown`. |
| `wasm_parse_sections(data)` | `Result[WasmSections, Str]` | Walks every section after the header; parallel id/offset/size vectors. |
| `wasm_export_names(data)` | `Result[Vec[Str], Str]` | Names of the export section (section 7), in entry order. |

`pub type WasmSections = { ids: Vec[Int]; offsets: Vec[Int]; sizes: Vec[Int]; }`
where `offsets[i]` is the absolute offset of the first payload byte (after
the size LEB128) and `sizes[i]` is the declared payload size.

Errors: `Err("wasm: truncated header")`, `Err("wasm: bad magic")`,
`Err("wasm: bad version")`, `Err("wasm: truncated leb128")`,
`Err("wasm: leb128 overflow")`, `Err("wasm: negative offset")`,
`Err("wasm: truncated section")`, `Err("wasm: truncated export")`,
`Err("wasm: trailing export bytes")`, `Err("wasm: nul in export name")`
(see SPEC.md).

## Usage

```xi
use xiom.wasm;
use xiom.io;

let bytes = /* a .wasm module as Vec[UInt8] */;
if wasm_is_module(&bytes) {
  let secs = wasm_parse_sections(&bytes);
  match secs {
    Ok(s) => { io.println("sections: " + xiom.convert.int_to_string(s.ids.len())); },
    Err(e) => { io.println("bad module: " + e); },
  }
  let names = wasm_export_names(&bytes);
  match names {
    Ok(n) => {
      var i = 0;
      while i < n.len() {
        let name: Str = n[i];
        io.println("export: " + name);
        i = i + 1;
      }
    },
    Err(e) => { io.println("bad exports: " + e); },
  }
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.wasm
```

Expected: the section-4 namespace check passes, 22 `[PASS]` lines, and a
final `port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Structure-only.** No validation: type indices, instruction bytes,
  section ordering, section uniqueness, count-vs-content agreement and
  the function/code correspondence are NOT checked. Unknown section ids,
  duplicate ids, zero-size payloads and non-minimal LEB128 encodings are
  accepted.
- **No codegen and no interpretation.** Function bodies are opaque bytes.
- **Export names only.** `wasm_export_names` consumes each entry's kind
  byte and index LEB128 but returns neither; import names and custom
  section names are not parsed. The payload's entry count is authoritative:
  bytes left after the declared count are rejected
  (`wasm: trailing export bytes`), and a name containing a `0x00` byte is
  rejected (`wasm: nul in export name`) because the platform `Str` is
  NUL-terminated.
- **First export section wins.** A second section 7 is ignored
  (structure-only; the spec allows at most one).
- **No UTF-8 validation.** Export-name bytes are copied into `Str`
  verbatim, matching the `xiom.encoding.hex`/`xiom.msgpack` precedent.
- Whole modules must fit in memory (`Vec[UInt8]`); no streaming reader.
- u32 values are returned in signed 64-bit `Int` and never overflow
  (max 4294967295).

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
