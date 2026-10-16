# xiom.brotli

Real RFC 7932 brotli (de)compression bindings for XIOM. The upstream
**google/brotli v1.2.0 C sources** (MIT) are vendored in `vendor/brotli/`
(one documented mechanical include rewrite, see `PROVENANCE.md`) and
compiled into the test binary -- no system library, no runtime DLL.

> **Status:** `incubating` -- suite green **26/26 x2** on the pin (v0.64.5):
> quality 0..11 round trips, 8 upstream golden vectors byte-identical,
> chunked streaming decode/encode, typed corrupt/truncated errors, and the
> RFC 9110 `Content-Encoding: br` helpers.
> **Lane:** bindings (`keywords: ["binding"]`).
> **Published:** `0.1.0` in `eco-v0.1.189` (sha256 `f37f3a39...`; PULSE top-tier: real RFC 7932 `Content-Encoding: br`).
> **Published:** `0.1.0` in `eco-v0.1.189` (sha256 `f37f3a39...`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.brotli;

fn main() {
  var body: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 4096 {
    body.push(65 as UInt8);
    i = i + 1;
  }
  // one-shot: quality 5, window 22, generic mode
  let packed = brotli_compress(&mut body, 5, 22, 0);
  if !packed.is_ok {
    io.println("compress failed: " + packed.error);
    return;
  }
  var wire: Vec[UInt8] = packed.value;
  io.println("Content-Encoding: " + brotli_content_encoding()
    + " (" + to_string(wire.len()) + " bytes)");

  let restored = brotli_decompress_auto(&mut wire);
  if restored.is_ok {
    io.println("restored " + to_string(restored.value.len()) + " bytes");
  }
}
```

## Streaming

```xiom
use xiom.io;
use xiom.brotli;

// decode a stream in pieces (input never overconsumed; output chunked)
let d = brotli_decoder_new();
var src: Vec[UInt8] = compressed_bytes;   // some earlier-produced stream
var out: Vec[UInt8] = Vec[UInt8].new();
var offset: Int = 0;
var done: Int = 0;
while done == 0 {
  let p = brotli_decoder_push(d, &mut src, offset, &mut out, 65536);
  if !p.is_ok { done = 1; }              // typed error
  else {
    var prog: BrotliDecodeProgress = p.value;
    offset = offset + prog.consumed;
    if prog.result == BROTLI_DECODER_RESULT_SUCCESS { done = 1; }
    elif prog.result == BROTLI_DECODER_RESULT_ERROR {
      io.println(brotli_decoder_error_string(brotli_decoder_error_code(d)));
      done = 1;
    }
  }
}
brotli_decoder_destroy(d);
```

The encoder mirrors it: `brotli_encoder_new(quality, lgwin, mode)` ->
`brotli_encoder_push(..., BROTLI_OPERATION_PROCESS/FINISH, ...)` ->
`brotli_encoder_take_output` (or push directly into an output buffer) ->
`brotli_encoder_is_finished`.

## API

| Area | Functions |
|------|-----------|
| Version | `brotli_version`, `brotli_decoder_version`, `brotli_encoder_version` |
| One-shot encode | `brotli_compress(src, quality, lgwin, mode)`, `brotli_compress_bound` |
| One-shot decode | `brotli_decompress_oneshot(src, capacity)` (literal upstream one-shot), `brotli_decompress(src, capacity)`, `brotli_decompress_auto(src)` |
| Streaming decode | `brotli_decoder_new`, `brotli_decoder_push`, `brotli_decoder_destroy`, `brotli_decoder_error_code`, `brotli_decoder_error_string` |
| Streaming encode | `brotli_encoder_new`, `brotli_encoder_push`, `brotli_encoder_take_output`, `brotli_encoder_is_finished`, `brotli_encoder_set_parameter`, `brotli_encoder_destroy` |
| HTTP | `brotli_content_encoding` ("br"), `brotli_is_content_encoding` |
| Constants | `BROTLI_DECODER_RESULT_*`, `BROTLI_DECODER_ERROR_*` (all 30), `BROTLI_MODE_*`, `BROTLI_PARAM_*` (all 10), `BROTLI_OPERATION_*`, ranges/defaults |
| Types | `BrotliDecodeProgress`, `BrotliEncodeProgress` |

All fallible calls return `Result[_, Str]` with typed errors
(`brotli.decoder: ...` / `brotli.encoder: ...`); decoder failures carry the
real upstream error code and `BrotliDecoderErrorString` text. Handles are
opaque `Int` values; 0 is never a valid session. The declared surface (16
upstream functions) and the error catalog are pinned in `SPEC.md`.

## Build note

`port.args.json` compiles `src/brotli_bridge.c` + the 35 vendored upstream
translation units (the upstream CMake default set) in one link invocation at
`--opt-level 0` (port-time speed; correctness-independent). Full provenance,
the include-rewrite rule and the re-pin procedure: `SPEC.md` section 2 and
`PROVENANCE.md`.

## Tests

```
scripts/port.ps1 -Package xiom.brotli -TimeoutSec 2400
```

Expected: 26 `[PASS]`, exit 0 (version pin 1.2.0, quality sweep, upstream
vectors, streaming, typed errors, HTTP helpers). Dictionaries, decoder
parameters, metadata callbacks and Large-Window streams are phase 2
(`ROADMAP.md`).
