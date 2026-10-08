# xiom.lzfse

Apple LZFSE (de)compression bindings for XIOM. The upstream `lzfse-1.0`
library sources (BSD-3-Clause) are vendored in `vendor/` and compiled into
the test binary -- no system library, no runtime DLL.

> **Status:** `incubating` -- suite green x2 on the pin (v0.64.1): 7/7 with a
> real ratio (4096 -> 182 bytes) and byte-identical round-trips up to 64 KB.
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.lzfse;

fn main() {
  var data: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 4096 {
    data.push(42 as UInt8);
    i = i + 1;
  }
  let packed = lzfse_encode(&mut data, 8192);
  if !packed.is_ok {
    io.println("encode failed: " + packed.error);
    return;
  }
  var p: Vec[UInt8] = packed.value;
  io.println("encoded to " + to_string(p.len()) + " bytes");
  let restored = lzfse_decode(&mut p, 4096);
  if restored.is_ok {
    io.println("restored " + to_string(restored.value.len()) + " bytes");
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Scratch | `lzfse_encode_scratch_required`, `lzfse_decode_scratch_required` |
| Codec | `lzfse_encode(src, dst_capacity)`, `lzfse_decode(src, dst_capacity)` |

Both fallible calls return `Result[Vec[UInt8], Str]`. Inputs are
`&mut Vec[UInt8]`; scratch buffers are allocated per call from the library's
reported sizes. LZFSE frames have no queryable content size, so decode takes
the output capacity (chunked decode is a Phase 2 roadmap item).

## Build note

`port.args.json` passes the seven vendored library sources as `--c-source`
entries (no `--link`). Full provenance + re-pin: `SPEC.md` §2.

## Tests

```
scripts/port.ps1 -Package xiom.lzfse
```

Expected: 7 `[PASS]`, exit 0. Streaming/scratch reuse are Phase 2
(`ROADMAP.md`).
