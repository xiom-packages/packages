# xiom.uuid

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) canonical UUID formatting, parsing,
> validation and v4 construction from caller-supplied randomness.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`; tests add
> `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
> `xiom.encoding.hex`).

## What it is

`xiom.uuid` is a small, dependency-light UUID module for the canonical
RFC 4122 textual form. Formatting and parsing work on raw 16-byte vectors;
validation wraps the parser. There is deliberately **no randomness source
inside the package**: `uuid_v4_from` takes 16 bytes from the caller, so
results are deterministic and unit-testable, and the caller decides which
RNG (or fixed test vector) supplies the entropy. Time-based versions
(v1/v6/v7) are out of scope.

## API

| Function | Returns | Description |
|---|---|---|
| `uuid_format(bytes)` | `Result[Str, Str]` | Exactly 16 bytes => lowercase `8-4-4-4-12` text; wrong length => `Err`. |
| `uuid_parse(s)` | `Result[Vec[UInt8], Str]` | 36 bytes, hyphens at 8/13/18/23, hex case-insensitive; no braces/urn. |
| `uuid_is_valid(s)` | `Bool` | True exactly when `uuid_parse` succeeds. |
| `uuid_v4_from(rand)` | `Result[Str, Str]` | 16 caller bytes => v4 text; sets version nibble (byte 6 high = 4) and variant bits (byte 8 top two = 10). |
| `uuid_version(s)` | `Result[Int, Str]` | Version nibble `(byte 6 >> 4) & 0x0F` of a valid UUID. |
| `uuid_variant_ok(s)` | `Result[Bool, Str]` | True when byte 8 carries the RFC 4122 variant bits (`10xxxxxx`). |

Error catalog (every message starts with `uuid: `):

| Message | Raised by |
|---|---|
| `uuid: expected 16 bytes` | `uuid_format`, `uuid_v4_from` |
| `uuid: expected 36 characters` | `uuid_parse` |
| `uuid: invalid hyphen placement` | `uuid_parse` |
| `uuid: invalid hex digit` | `uuid_parse` |
| `uuid: invalid UUID` | `uuid_version`, `uuid_variant_ok` |

## Usage

```xi
use xiom.uuid;
use xiom.io;

// The caller owns the randomness: pass any 16 bytes, e.g. from a CSPRNG.
// This example uses a fixed vector so the output is reproducible.
var rand = Vec[UInt8].new();
var i = 0;
while i < 16 {
  rand.push((i * 17 + 3) as UInt8);
  i = i + 1;
}

let id = uuid_v4_from(&rand);
if id.is_ok {
  io.println(id.value);                     // 03142536-4758-497a-8b9c-adbecfe0f102
  io.println(uuid_is_valid(id.value));      // true
}

// Parse and inspect any canonical UUID.
let parsed = uuid_parse("550e8400-e29b-41d4-a716-446655440000");
if parsed.is_ok {
  io.println(parsed.value.len());           // 16
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.uuid
```

Expected: the section-4 namespace check passes, 18 `[PASS]` lines, and a
final `port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No RNG inside.** `uuid_v4_from` masks and formats the caller's 16
  bytes; it never generates entropy. Callers that need unpredictable IDs
  must supply bytes from a cryptographic source.
- **Canonical form only.** Braces (`{...}`), the URN form
  (`urn:uuid:...`), uppercase-only inputs (accepted on parse, emitted
  lowercase), base64/hex-without-hyphens encodings and Microsoft GUID
  mixed-endian layouts are not supported.
- **v4 (random) only.** No v1/v6/v7 time or node logic, no time-based
  monotonicity, no variant/version rewriting beyond the v4 bit rules.
- **Structural validation, not semantic.** `uuid_parse` proves the shape
  and the hex digits; any version nibble `0..15` parses (`uuid_version`
  reports it), and non-RFC variant bits are reported by
  `uuid_variant_ok` rather than rejected by the parser.
- **In-memory only.** All functions take in-memory `Vec[UInt8]`/`Str`
  values; there is no streaming or file API, no FFI.
- Pure XIOM: no registry integration, no allocations beyond the returned
  value.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
