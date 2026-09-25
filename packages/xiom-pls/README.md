# xiom.pls

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** PLS playlist parsing and canonical emitting; in-memory `Str`
> only.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_trim`,
> `xiom.string.str_starts_with`, `xiom.string.compare.str_compare`,
> `xiom.string.builder.sb_push_str`, `xiom.string.builder.sb_push_int`,
> `xiom.string.builder.sb_to_str` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Overview

`xiom.pls` is a small, dependency-free codec for the PLS playlist format as
produced by Winamp and a long tail of media players, library managers and
conversion tools. It parses a whole document into a flat `Pls` value, exposes
the entries through 1-based accessors (`FileN` semantics), preserves unknown
keys verbatim, and emits a canonical document with `NumberOfEntries`
recomputed from the actual entries.

The codec covers this documented subset:

- an optional `[playlist]` section header (case-insensitive),
- an optional `Version=2` line (any other declared version is rejected),
- an optional `NumberOfEntries=N` line that bounds every indexed key,
- indexed keys `FileN=path` (required for every entry), `TitleN=title`
  (optional) and `LengthN=seconds` (optional; `-1` is the documented
  unknown / live-stream sentinel),
- every other key preserved in document order as an unknown key,
- blank lines skipped, CRLF normalized, keys and values trimmed of SP/TAB,
  key names matched case-insensitively.

It performs no playback and no file or URL validation: paths are opaque text
that survives a round trip unchanged.

## Install / use

```
xiom pkg install xiom.pls@0.1.0
```

```xi
use xiom.pls;
```

## Quick start

```xi
use xiom.pls;
use xiom.io;

fn main() -> Int {
  let text = "[playlist]\nVersion=2\nNumberOfEntries=1\n"
           + "File1=tracks/example.mp3\nTitle1=Example Song\nLength1=212\n";
  let r = pls_parse(text);
  match r {
    Ok(p) => {
      io.println(pls_file(&p, 1));    // tracks/example.mp3
      io.println(pls_title(&p, 1));   // Example Song
      if pls_length(&p, 1) == 212 { io.println("212 s"); }
      io.println(pls_emit(&p));       // canonical PLS
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## API summary

Entry accessors are **1-based** (entry `i` is the PLS `FileN`..`File1..N`
index); unknown-key accessors are 0-based in document order.

| Function | Returns | Description |
|---|---|---|
| `pls_parse(text)` | `Result[Pls, Str]` | Parse a whole PLS document; LF or CRLF; `Err("pls: ...")` on malformed input. |
| `pls_emit(p)` | `Str` | Canonical emission: `[playlist]`, `Version=2`, recomputed `NumberOfEntries`, entries, then unknown keys; LF-terminated. |
| `pls_entry_count(p)` | `Int` | Number of entries (`FileN` count). |
| `pls_has_header(p)` | `Bool` | True when the input contained a `[playlist]` line. |
| `pls_file(p, i)` | `Str` | Path of entry `i` (1-based, verbatim after trimming); `""` out of range. |
| `pls_title(p, i)` | `Str` | Title of entry `i`; `""` when absent or out of range. |
| `pls_length(p, i)` | `Int` | Whole seconds; `-1` when unknown / no `LengthN` / out of range. |
| `pls_unknown_count(p)` | `Int` | Number of preserved unknown keys. |
| `pls_unknown_key(p, j)` | `Str` | Name of unknown key `j` (0-based, document order); `""` out of range. |
| `pls_unknown_value(p, j)` | `Str` | Value of unknown key `j`; `""` out of range. |

## Error model

`pls_parse` is total: it returns `Ok(Pls)` or `Err(msg)` with a `"pls: "`
prefix. There are exactly twelve messages:

| Message | Raised when |
|---|---|
| `pls: malformed section header: <line>` | A line starting with `[` is not `[name]` with a non-empty name. |
| `pls: unknown section: <line>` | A well-formed section declares a name other than `playlist` (case-insensitive). |
| `pls: missing '=' in line: <line>` | A non-blank, non-section line has no `=`. |
| `pls: empty key in line: <line>` | The key before `=` is empty or whitespace-only. |
| `pls: bad index in key: <key>` | A `file*`/`title*`/`length*` key has a non-numeric, empty, zero or 19+-digit index. |
| `pls: index out of range: <key>` | An indexed key exceeds the declared `NumberOfEntries`, or the 1000000-entry cap. |
| `pls: bad NumberOfEntries: <value>` | `NumberOfEntries` is not 1..18 ASCII digits (0 is valid). |
| `pls: too many entries: <value>` | `NumberOfEntries` exceeds 1000000. |
| `pls: bad version: <value>` | `Version` is not 1..18 ASCII digits. |
| `pls: unsupported version: <value>` | `Version` parses but is not 2. |
| `pls: bad length in key <key>: <value>` | `LengthN` is neither `-1` nor a non-negative 1..18-digit integer. |
| `pls: missing File<index>` | No non-empty `FileN` exists for an index in 1..count. |

Structural per-line errors fire in document order; the cross-line checks
(index range against `NumberOfEntries`, missing `FileN`) run after the whole
document is scanned and are independent of where `NumberOfEntries` appears.

## Limitations

- No file existence, path normalization or URL validation; a path is opaque
  text (only non-empty is enforced, and that is reported as "missing FileN").
- No playback and no semantics for extended keys; unknown keys are preserved
  but never interpreted.
- Keys beginning with `file`, `title` or `length` (case-insensitive) are a
  reserved namespace: such a key must carry a decimal index, so an unrelated
  key such as `Filesystem` is rejected rather than preserved.
- Only the `[playlist]` section is accepted; `[playlist]` is optional and
  decorative, but any other section name is an error.
- Integer seconds only; `-1` means unknown/live stream and is treated as
  equivalent to an absent `LengthN`. Values with 19 or more digits are
  rejected.
- Values with leading/trailing SP/TAB or an embedded LF are trimmed/lost on
  round trip; the format has no escaping.
- At most 1,000,000 entries; larger inferred or declared counts are errors.
- A declared `Version` other than 2 is rejected rather than interpreted.
- Whole-document only; no streaming API, no editing API, no file I/O.
- Blank-line and CRLF layout are not preserved; `[playlist]`, `Version=2`
  and a recomputed `NumberOfEntries` are always emitted, and unknown keys
  move after the entries.

See `SPEC.md` for the exact grammar, decisions, error catalog, round-trip
rules and test matrix. License: MIT OR Apache-2.0 (see the repository root
`LICENSE`).
