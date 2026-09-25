# xiom.vtt

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** a strict, in-memory WebVTT (W3C "Web Video Text Tracks") codec:
> signature line, header metadata, cue identifiers, settings pass-through,
> raw NOTE/STYLE/REGION blocks, timestamps, and cue building.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.str_slice`,
> `xiom.string.byte_at`, `xiom.string.str_contains`,
> `xiom.string.str_starts_with` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.vtt` parses a WebVTT document held in memory as a `Str` into a flat
`Vtt` track, and serializes it back with canonical timestamps. It validates
the documented subset strictly, keeps payload bytes exact, and round-trips
canonical documents `parse -> format -> parse`.

What it handles:

- the `WEBVTT` signature line, optionally followed by space/tab and trailing
  text (kept verbatim);
- header metadata lines (everything before the first blank line);
- blank-line separated cue blocks with an optional cue identifier line,
  a timing line with optional settings passed through verbatim, and zero or
  more payload lines;
- `NOTE`, `STYLE` and `REGION` blocks, preserved as raw text and re-emitted
  in document order.

It intentionally does **not** render captions, parse HTML/CSS, interpret cue
settings, or enforce region/voice semantics -- see Limitations.

## Install / use

```
xiom pkg install xiom.vtt@0.1.0     # consumer
xiom pkg publish                    # maintainer (needs XIOM_REGISTRY_TOKEN)
```

Quick start:

```xi
use xiom.vtt;
use xiom.io;

fn main() -> Int {
  let r = vtt_parse("WEBVTT\n\nintro\n00:00:01.000 --> 00:00:02.500\nHello\nWorld\n");
  if !r.is_ok {
    io.println(r.error);
    return 1;
  }
  let track = r.value;
  io.println(vtt_cue_text(&track, 0));       // Hello (LF) World
  io.println(vtt_timestamp_format(3723456)); // 01:02:03.456

  let r2 = vtt_cue_add(&track, "", 3000, 4000, "align:start", "More");
  if r2.is_ok {
    let built = r2.value;
    io.println(vtt_format(&built));
  }
  return 0;
}
```

## API

| Function | Returns | Description |
|---|---|---|
| `vtt_parse(text)` | `Result[Vtt, Str]` | Parse a whole WebVTT document. |
| `vtt_format(v)` | `Str` | Canonical serialization (`HH:MM:SS.mmm`, LF, one blank line between blocks). |
| `vtt_signature(v)` | `Str` | The stored signature line, verbatim. |
| `vtt_header_count(v)` | `Int` | Number of header metadata lines. |
| `vtt_header(v, i)` | `Str` | Header metadata line `i`; `""` out of range. |
| `vtt_cue_count(v)` | `Int` | Number of cues. |
| `vtt_cue_id(v, i)` | `Str` | Cue identifier; `""` when absent or out of range. |
| `vtt_cue_start_ms(v, i)` | `Int` | Cue start in milliseconds; `-1` out of range. |
| `vtt_cue_end_ms(v, i)` | `Int` | Cue end in milliseconds; `-1` out of range. |
| `vtt_cue_settings(v, i)` | `Str` | Verbatim settings text; `""` when absent. |
| `vtt_cue_line_count(v, i)` | `Int` | Payload lines of cue `i` (may be 0). |
| `vtt_cue_line(v, i, j)` | `Str` | Payload line `j` of cue `i`; `""` out of range. |
| `vtt_cue_text(v, i)` | `Str` | Payload lines joined with `"\n"`. |
| `vtt_block_count(v)` | `Int` | Number of raw NOTE/STYLE/REGION blocks. |
| `vtt_block_text(v, i)` | `Str` | Raw block text (lines joined with `"\n"`). |
| `vtt_block_kind(v, i)` | `Str` | `"NOTE"`, `"STYLE"` or `"REGION"`. |
| `vtt_timestamp_parse(t)` | `Result[Int, Str]` | Parse one timestamp to milliseconds. |
| `vtt_timestamp_format(ms)` | `Str` | Canonical timestamp text for `ms`. |
| `vtt_new()` | `Vtt` | Empty track with the default `WEBVTT` signature. |
| `vtt_cue_add(v, id, start_ms, end_ms, settings, text)` | `Result[Vtt, Str]` | Copy of `v` with one cue appended. |

## Timestamp rules

Accepted forms (byte-exact, no surrounding whitespace):

```
hh:mm:ss.mmm     hours exactly two digits 00..99, minutes/seconds 00..59,
mm:ss.mmm        hours omitted (treated as 00), milliseconds exactly 3 digits
```

The separator must be `"."`; a comma is rejected. Whole milliseconds are
`hh*3600000 + mm*60000 + ss*1000 + mmm`. The parser rejects a cue whose end
is before its start (equal times are allowed); the formatter always writes
the long form with canonical zero-padding. These rules and every error class
are pinned by the conformance suite and stated in full in `SPEC.md`.

## Error model

All failures are `Err(message)` with a `"vtt: "` prefix and no line numbers.
Parsing:

| Message | Raised when |
|---|---|
| `vtt: missing signature` | Empty input, or the first line is not a valid `WEBVTT` signature line. |
| `vtt: cue without timing` | A block is neither NOTE/STYLE/REGION nor contains a `-->` timing line. |
| `vtt: payload before timing` | The first `-->` line is the third or later line of its block. |
| `vtt: bad timestamp shape` | A timestamp does not match an accepted form (length, separators, digits). |
| `vtt: timestamp out of range` | Minutes or seconds exceed 59. |
| `vtt: end before start` | Both timestamps parse and the end is earlier than the start. |

Cue building adds `vtt: negative time`, `vtt: bad cue identifier`,
`vtt: bad settings` and `vtt: blank payload line`.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.vtt
```

Expected tail: 23 `[PASS]` lines, `xiom.vtt: all tests passed`, then
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Whole document only**: no streaming, no incremental parsing.
- **No interpretation**: cue settings and identifiers are stored and
  re-emitted verbatim; no alignment/position semantics, no HTML/CSS parsing,
  no region or voice-span handling.
- **Strict timestamps**: hours are exactly two digits on read, the separator
  must be `.`, and values at or above 100 hours format fine but fail to
  parse (so they do not round-trip).
- **Blank lines are structural**: a blank line always ends a block, so a cue
  payload cannot contain one; whitespace-only lines are payload text, not
  separators.
- **No BOM handling**: a leading UTF-8 BOM makes the signature check fail.
- **Raw blocks are opaque**: NOTE/STYLE/REGION position and content are
  preserved without validation.
- **Builder scope**: `vtt_new`/`vtt_cue_add` build cues only; header metadata
  must come from a parsed document.
- Errors carry no line/column numbers.

See `SPEC.md` for the full grammar, decisions, error catalog and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
