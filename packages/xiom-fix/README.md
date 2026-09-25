# xiom.fix

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** a FIX tag=value message codec: SOH framing, flat tag/value spans,
> ordered duplicates, BodyLength and CheckSum validation, canonical emit. In
> memory `Str` only.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.builder.sb_push_byte`,
> `xiom.string.builder.sb_push_int`, `xiom.string.builder.sb_push_str` and
> `xiom.string.builder.sb_to_str`). Tests additionally use `xiom.test`,
> `xiom.io`, `xiom.convert` and `xiom.string.compare`.

## Overview

`xiom.fix` parses one in-memory FIX message -- fields separated by SOH
(`0x01`), each field written `tag=value` -- into a flat, offset-based
`FixMessage`: one entry per field in a tag vector, with parallel value spans
into the original text (`tags` / `starts` / `ends`). `Vec[StructType]` is not
usable in this compiler, so the message is deliberately stored flat instead of
as a vector of field structs.

The codec enforces the framing rules that make a FIX message a message:

- tag `8` (BeginString) is the first field and is non-empty,
- tag `9` (BodyLength) is the second field and equals the exact byte count
  between the SOH that follows tag 9 and the start of `10=`,
- a non-empty tag `35` (MsgType) field is required,
- tag `10` (CheckSum) is the last field and equals the sum of every byte
  before `10=` modulo 256, written as exactly three digits.

Duplicate tags are preserved in wire order and available through first/last
lookups. `fix_emit` writes the canonical frame back out, recomputing tags 9
and 10 from the stored fields, so a parsed message round-trips byte-exact.

The codec answers "is this a well-framed FIX message, and what are its
fields?" and nothing more: it does not expand repeating groups, validate
field types against a data dictionary, or implement any session protocol --
see Limitations.

## Install / use

```
xiom pkg install xiom.fix@0.1.0
```

or copy `src/fix.xi` into a project and `use xiom.fix;`.

## Quick start

```xi
use xiom.fix;
use xiom.io;

fn main() -> Int {
  let text = "8=FIX.4.2\x019=5\x0135=D\x0110=181\x01";
  let r = fix_parse(text);
  match r {
    Ok(m) => {
      io.println("tags: " + fix_msg_type(&m));      // D
      match fix_value(&m, 35) {
        Some(v) => { io.println(v); },              // D
        None => {},
      }
      let out = fix_emit(&m);
      if out.is_ok {
        let canon: Str = out.value;
        io.println(canon);                          // canonical, byte-exact
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## API summary

| Function | Returns | Description |
|---|---|---|
| `fix_parse(text)` | `Result[FixMessage, Str]` | Parse and validate one message; `Err("fix: ...")` on any framing error. |
| `fix_tag_count(m)` | `Int` | Number of stored fields, duplicates counted (tags 8, 9, 10 included). |
| `fix_value(m, tag)` | `Option[Str]` | First value stored under `tag`, in wire order; `None` when absent. |
| `fix_value_last(m, tag)` | `Option[Str]` | Last value stored under `tag`, in wire order; `None` when absent. |
| `fix_msg_type(m)` | `Str` | Value of the first tag 35 field, or `""` when no such field is stored. |
| `fix_emit(m)` | `Result[Str, Str]` | Canonical wire text with tags 9 and 10 recomputed. |

`FixMessage` exposes its storage fields directly: `raw` (the exact input
text), `tags`, `starts`, `ends` (index-aligned value spans into `raw`),
`body_length` and `checksum` (the validated values of tags 9 and 10).

## Error model

Every parse failure is `Err(msg)` with a deterministic message starting with
`"fix: "`, quoting the failing offset or numbers where useful:

| Message | Trigger |
|---|---|
| `fix: empty message` | the input is `""` |
| `fix: missing SOH terminator at offset N` | a field other than tag 10 reaches end of input without SOH |
| `fix: missing '=' in field at offset N` | no `=` before the field's SOH |
| `fix: non-digit tag at offset N` | empty tag or a non-digit byte in the tag |
| `fix: invalid tag 0 at offset N` | the tag parses to 0 |
| `fix: tag out of range at offset N` | more than 9 tag digits |
| `fix: first field must be tag 8 (BeginString)` | field 0 is not tag 8 |
| `fix: second field must be tag 9 (BodyLength)` | field 1 is not tag 9 |
| `fix: duplicate tag 8` / `fix: duplicate tag 9` | a later field repeats tag 8 or 9 |
| `fix: empty BeginString` | the tag 8 value is empty |
| `fix: empty MsgType` | the tag 35 value is empty |
| `fix: missing tag 35 (MsgType)` | the frame ends without a tag 35 field |
| `fix: missing tag 10 (CheckSum)` | the input ends without a tag 10 field |
| `fix: trailing bytes after checksum at offset N` | bytes follow the tag-10 field (a repeated tag 10 lands here too) |
| `fix: BodyLength is not a non-negative integer` | tag 9 is empty, non-digit, or wider than 9 digits |
| `fix: BodyLength mismatch: declared N actual M` | tag 9 differs from the body byte count |
| `fix: invalid CheckSum at offset N` | tag 10 is not exactly three digits in `000`-`255` |
| `fix: CheckSum mismatch: declared N computed M` | tag 10 is well formed but wrong |

`fix_emit` only fails on a hand-built message whose vectors disagree
(`fix: cannot emit: field vectors are not aligned`, `... invalid tag`,
`... field span out of range`, `... value contains a reserved byte`,
`... duplicate tag 8`, `fix: cannot emit without tag 8 (BeginString)`). A
message produced by `fix_parse` always emits successfully.

## Limitations

- **Framing only**: no repeating-group expansion, no data-dictionary or
  field-type validation, no FIXML, no encryption, no session protocol.
- **No field reordering**: stored order is wire order; `fix_emit` only moves
  the recomputed tags 9 and 10 into their canonical positions.
- **Single message**: one message per call; no batch/framing protocols
  (FIXT session headers are ordinary fields to this codec).
- **Values are opaque bytes**: empty values are allowed (except BeginString
  and MsgType) and are returned as `Some("")`. The first `=` splits tag and
  value; any further `=` bytes are tolerated inside the value but are outside
  the documented producer subset.
- **ASCII promise**: fixtures and the documented value subset are
  high-bit-free ASCII; scanning is byte-wise, so other bytes pass through
  values unchanged.
- **Reserved bytes**: values must not contain SOH (that is the separator) or
  NUL (`fix_emit` rejects both when copying a value).
- **Tag canonicalization**: leading zeros in a tag are accepted on parse
  (`008` is tag 8) and never re-emitted; `fix_emit` writes plain decimals.
- **Final SOH optional**: a tag-10 field may end at end of input; canonical
  emit always terminates it with SOH, so such an input is not byte-exact on
  round-trip.

See `SPEC.md` for the exact grammar, validation order, error catalog and the
test matrix.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.fix
```

Expected tail: 20 `[PASS]` lines, `xiom.fix: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
