# xiom.dtb

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM Flattened Device Tree (DTB) parsing, validation and
> canonical version-17 emission.
> **Deps:** `xiom.std` only. The library module uses `xiom.string` and
> `xiom.string.builder`; the tests add `xiom.test`, `xiom.io`,
> `xiom.string.compare` and `xiom.encoding.hex`. No FFI.

## What it is

`xiom.dtb` decodes the binary Flattened Device Tree blobs that firmware
(bootloaders, U-Boot, EDK2, ...) hands to an operating system kernel. A
blob is a 40-byte big-endian header, a memory reservation block, a
structure block token stream and a NUL-terminated strings table.
`dtb_parse` validates all of it and returns a `Dtb` flat store: nodes are
held as parallel vectors (name span, depth, parent index) and properties
as parallel vectors (owner node, strings-block name offset, value span in
the source buffer). Nothing is re-encoded during parsing; accessors read
the names and values straight out of the buffer you pass in.

`dtb_emit` walks the store and writes the canonical version-17 blob:
blocks in canonical order, FDT_NOPs dropped, zero padding, and the strings
block rebuilt by first use of each property name. Parsing a canonical blob
and emitting it again is byte-identical.

Version 17 is the documented target; version 16 is accepted on input (the
`size_dt_struct` header field only exists from v17, so the v16 structure
block size is derived as `off_dt_strings - off_dt_struct`), and emitter
output is always v17.

## API

| Function | Returns | Description |
|---|---|---|
| `dtb_parse(data)` | `Result[Dtb, Str]` | Validate a blob and build the flat store. |
| `dtb_emit(data, d)` | `Result[Vec[UInt8], Str]` | Write the canonical v17 blob (`data` is the parse buffer). |
| `dtb_total_size(d)` | `Int` | Header `totalsize`. |
| `dtb_version(d)` | `Int` | Header `version` (16 or 17). |
| `dtb_last_comp_version(d)` | `Int` | Header `last_comp_version`. |
| `dtb_boot_cpuid_phys(d)` | `Int` | Header `boot_cpuid_phys`. |
| `dtb_strings_size(d)` | `Int` | Strings-block size in bytes. |
| `dtb_mem_rsv_count(d)` | `Int` | Reservation entries (terminator excluded). |
| `dtb_mem_rsv_address(d, i)` | `Int` | Reservation address as a 64-bit bit pattern; `-1` out of range. |
| `dtb_mem_rsv_size(d, i)` | `Int` | Reservation size as a 64-bit bit pattern; `-1` out of range. |
| `dtb_node_count(d)` | `Int` | Number of nodes. |
| `dtb_node_depth(d, i)` | `Int` | Node depth (root 0); `-1` out of range. |
| `dtb_node_parent(d, i)` | `Int` | Parent index (`-1` for the root and out of range). |
| `dtb_root_name(data, d)` | `Str` | Root node name (`""` when the store is empty). |
| `dtb_node_name(data, d, i)` | `Result[Str, Str]` | Node name. |
| `dtb_prop_count(d)` | `Int` | Number of properties. |
| `dtb_prop_node(d, i)` | `Int` | Owning node of property `i`; `-1` out of range. |
| `dtb_prop_value_len(d, i)` | `Int` | Value length; `-1` out of range. |
| `dtb_prop_name(data, d, i)` | `Result[Str, Str]` | Property name. |
| `dtb_prop_value(data, d, i)` | `Result[Vec[UInt8], Str]` | Copy of the value bytes. |
| `dtb_find_property(data, d, node, name)` | `Int` | First property of `node` with that name; `-1` when absent. |
| `dtb_find_node(data, d, path)` | `Int` | Resolve `"/soc@0/uart@1000"`; `-1` when it does not resolve. |

Errors: see the catalog in SPEC.md (`dtb: header truncated`,
`dtb: bad magic`, `dtb: totalsize out of range`,
`dtb: unsupported version`, `dtb: bad last_comp_version`,
`dtb: struct block out of range`, `dtb: strings block out of range`,
`dtb: memory reservation block out of range`,
`dtb: unterminated memory reservation block`, `dtb: unterminated node name`,
`dtb: multiple root nodes`, `dtb: missing root node`,
`dtb: unbalanced end node`, `dtb: unbalanced node nesting`,
`dtb: property outside node`, `dtb: property value out of range`,
`dtb: property name offset out of range`, `dtb: unterminated property name`,
`dtb: unknown token`, `dtb: truncated structure block`,
`dtb: invalid tree`, `dtb: node index out of range`,
`dtb: property index out of range`, `dtb: property value out of bounds`).

## Usage

```xi
use xiom.dtb;
use xiom.io;
use xiom.convert;

// blob: Vec[UInt8] holding a device tree handed over by firmware.
let pr = dtb_parse(&blob);
match pr {
  Ok(d) => {
    io.println("nodes: " + convert.int_to_string(dtb_node_count(&d)));
    io.println("root: " + dtb_root_name(&blob, &d));

    let uart = dtb_find_node(&blob, &d, "/soc@0/uart@1000");
    if uart >= 0 {
      let reg = dtb_find_property(&blob, &d, uart, "reg");
      if reg >= 0 {
        io.println("reg bytes: " + convert.int_to_string(dtb_prop_value_len(&d, reg)));
      }
    }

    // Canonical v17 bytes: identical to the input when the input was
    // already canonical.
    let er = dtb_emit(&blob, &d);
    if er.is_ok {
      io.println("canonical size: " + convert.int_to_string(er.value.len()));
    }
  },
  Err(e) => { io.println("dtb error: " + e); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.dtb
```

Expected: the section-4 namespace check passes, 18 `[PASS]` lines, and a
final `port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Read and canonicalize only.** There is no API to build a blob from
  scratch: the emitter re-serializes a store produced by `dtb_parse`.
- **No phandle resolution, overlays or `/chosen` semantics.** A property
  value is an opaque byte span; `phandle`/`linux,phandle` values are not
  cross-referenced and overlay (`-@`) metadata is not interpreted.
- **No DTS text parsing.** Source `.dts`/`.dtsi` files are out of scope.
- **Version 16 input only as a compatibility alias.** The full 40-byte
  header is still required; the v16 structure-block size is derived from
  the block offsets and the `size_dt_struct` field at offset 36 is
  ignored. A genuine v16 blob with a 36-byte header is out of scope.
- **Lenient on padding.** Nonzero name/value padding bytes parse fine;
  `dtb_emit` always writes zeros, so re-emission of such a blob is not
  byte-identical (it is canonical).
- **Lenient after FDT_END.** Bytes between FDT_END and the declared end of
  the structure block, and bytes after `totalsize`, are ignored.
- **No block-overlap detection.** Offsets and sizes are bounds-checked
  against `totalsize`, but the memory reservation, structure and strings
  blocks may legally (if uselessly) overlap.
- **`Dtb` borrows nothing but needs its buffer.** Node names, property
  values and property names are spans into the buffer passed to
  `dtb_parse`; accessors and `dtb_emit` need that same buffer alive.
- Not thread-safe; `Dtb` is a plain value type built from parallel vectors.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
