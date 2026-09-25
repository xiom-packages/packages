# xiom.hl7

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** an HL7 v2.x pipe-delimited message codec: segment splitting, MSH
> separator declaration, fields, repetitions, components and subcomponents,
> plus a segment/field builder with separator-aware escaping. In-memory `Str`
> only.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_starts_with`,
> `xiom.string.builder.sb_push_str`, `xiom.string.builder.sb_push_int`,
> `xiom.string.builder.sb_to_str` and `xiom.string.compare.str_compare`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Overview

`xiom.hl7` turns a raw HL7 v2 message into a flat, offset-based `Message`: one
entry per segment plus a shared `Vec[Str]` of raw field texts, with parallel
offset and length vectors (`seg_names` / `seg_off` / `seg_len` / `fields`).
`Vec[StructType]` is not usable in this compiler, so segments are deliberately
stored flat instead of as a vector of segment structs.

MSH gets the special treatment the standard requires: the byte after `MSH` is
the field separator (MSH.1) and the four bytes that follow are the encoding
characters (MSH.2: component `^`, repetition `~`, escape `\`, subcomponent
`&`). Every other segment is split with that declared separator, so a message
that uses a different dialect (for example `MSH*%~\$*...`) parses with its own
separators.

The codec answers "what is the structure?" and nothing more: it does not
decode escape sequences, interpret data types (dates, codes, numbers) or
validate EHR profiles -- see Limitations.

## Install / use

```
xiom pkg install xiom.hl7@0.1.0
```

or copy `src/hl7.xi` into a project and `use xiom.hl7;`.

## Quick start

```xi
use xiom.hl7;
use xiom.io;

fn main() -> Int {
  let text = "MSH|^~\\&|SENDAPP|SENDFAC|RECVAPP|RECVFAC|20260101||ADT^A01|MSG1|P|2.5.1\rPID|1||12345||DOE^JOHN\r";
  let r = hl7_parse(text);
  match r {
    Ok(m) => {
      match hl7_seg_name(&m, 1) {
        Some(n) => { io.println(n); },             // PID
        None => {},
      }
      match hl7_comp(&m, 1, 5, 1, 1) {
        Some(family) => { io.println(family); },   // DOE
        None => {},
      }
      io.println(hl7_write(&m));                   // byte-exact round trip
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

Building a message (every builder call returns `""` on success, or an
`"hl7: ..."` error message):

```xi
use xiom.hl7;
use xiom.io;

fn main() -> Int {
  var b = hl7_builder_new();
  let s0 = hl7_builder_segment(&mut b, "MSH");            // MSH must be first
  let f0 = hl7_builder_field(&mut b, "SENDAPP");          // becomes MSH.3
  let s1 = hl7_builder_segment(&mut b, "PID");
  let f1 = hl7_builder_field_structured(&mut b, "DOE^JOHN");  // "^" is structure
  let f2 = hl7_builder_field(&mut b, "data | with separators"); // escaped data
  if s0.len() == 0 && f0.len() == 0 && s1.len() == 0 && f1.len() == 0 && f2.len() == 0 {
    io.println(hl7_write(&b));
    // MSH|^~\&|SENDAPP\rPID|DOE^JOHN|data \F\ with separators\r
  }
  return 0;
}
```

## API summary

| Function | Returns | Description |
|---|---|---|
| `hl7_parse(text)` | `Result[Message, Str]` | Parse a whole message; `Err("hl7: ...")` on structural errors. |
| `hl7_seg_count(m)` | `Int` | Number of segments. |
| `hl7_seg_name(m, i)` | `Option[Str]` | Name of segment `i` (zero-based); `None` out of range. |
| `hl7_seg_index(m, name)` | `Option[Int]` | First segment named `name` (byte-exact); `None` when absent. |
| `hl7_seg_field_count(m, i)` | `Int` | Stored field count of segment `i`; `0` out of range. MSH counts fields 1-2. |
| `hl7_field_sep(m)` | `Str` | The field separator from MSH.1. |
| `hl7_encoding(m)` | `Str` | The four encoding characters from MSH.2. |
| `hl7_field(m, i, f)` | `Option[Str]` | Raw text of field `f` (1-based); `None` out of range. |
| `hl7_rep_count(m, i, f)` | `Int` | Number of `~`-separated repetitions of a field. |
| `hl7_rep(m, i, f, r)` | `Option[Str]` | Repetition `r` (1-based). |
| `hl7_comp_count(m, i, f, r)` | `Int` | Number of `^`-separated components of a repetition. |
| `hl7_comp(m, i, f, r, c)` | `Option[Str]` | Component `c` (1-based). |
| `hl7_sub_count(m, i, f, r, c)` | `Int` | Number of `&`-separated subcomponents of a component. |
| `hl7_sub(m, i, f, r, c, s)` | `Option[Str]` | Subcomponent `s` (1-based). |
| `hl7_write(m)` | `Str` | Serialize a message; CR after every segment, verbatim field text. |
| `hl7_builder_new()` | `Message` | Empty builder with `\|^~\&`. |
| `hl7_builder_with_separators(field_sep, encoding)` | `Result[Message, Str]` | Empty builder with validated custom separators. |
| `hl7_builder_segment(m, name)` | `Str` | Open a segment; `""` on success. |
| `hl7_builder_field(m, value)` | `Str` | Append a data field, escaping all five separators; `""` on success. |
| `hl7_builder_field_structured(m, value)` | `Str` | Append a wire-level field: only the field separator and escape char are escaped; `""` on success. |

All indices are zero-based except HL7 field/repetition/component/subcomponent
numbers, which are 1-based exactly as in the standard (`PID.5.1` is
`hl7_comp(&m, pid_index, 5, 1, 1)`). Parsing and writing are O(total text
length); the accessors are O(1) or O(part length).

## Error model

Every failure is `Err(msg)` with a deterministic message starting with
`"hl7: "`, and every builder call returns the message directly (`""` = ok):

| Message | Trigger |
|---|---|
| `hl7: empty message` | input with no non-terminator bytes (including `""` and `"\r"`) |
| `hl7: missing MSH segment` | first segment is not `MSH` (case-sensitive), or a builder opens a non-MSH segment first |
| `hl7: malformed MSH segment: too short` | MSH line shorter than 4 bytes |
| `hl7: malformed MSH segment: expected 4 encoding characters, got N` | MSH.2 is not exactly four bytes |
| `hl7: malformed MSH segment: MSH must be the first segment` | builder opens MSH after another segment |
| `hl7: invalid separator` | a separator is outside `!`..`~`, is alphanumeric, is duplicated, or equals the field separator |
| `hl7: empty segment name` | an empty segment line, a line starting with the field separator, or an empty builder segment name |
| `hl7: no open segment` | builder field appended before any `hl7_builder_segment` |
| `hl7: field contains a line terminator` | builder field value contains CR or LF |

## Limitations

- **Structure only**: escape sequences (`\F\`, `\S\`, `\R\`, `\E\`, `\T\`,
  `\X..\`, ...) are returned as written and never decoded; `hl7_field` and
  friends return raw wire text.
- **No transport**: MLLP framing, batch headers (FHS/BHS) and network I/O are
  out of scope; only in-memory `Str` codec functions are provided.
- **No data types**: dates, coded values, numbers and names stay `Str`; no
  EHR/segment profile validation.
- **No field-count consistency check**: HL7 marks trailing fields optional, so
  segments of the same type may carry different field counts; the codec stores
  and reports the actual count per segment.
- **MSH first, one message at a time**: a message with a later MSH segment is
  accepted as an ordinary duplicate segment on parse, but the builder only
  allows MSH as the first segment.
- **Writer dialect**: `hl7_write` always emits CR terminators including a final
  one, so LF-terminated input is normalized; MSH.1/MSH.2 are emitted from the
  stored separators.
- **Builder escaping**: `hl7_builder_field` escapes data values for all five
  separators; `hl7_builder_field_structured` keeps `^`, `~` and `&` as
  structure and escapes only the field separator and the escape character.
  There is no API to mutate a field after it has been appended.

See `SPEC.md` for the exact grammar, storage invariants, error catalog and
test matrix. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
