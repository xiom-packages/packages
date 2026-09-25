# xiom.edl

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** CMX EDL parsing and canonical emitting for a strict, documented
> subset; in-memory `Str` only.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_trim`,
> `xiom.string.builder.sb_push_str`, `xiom.string.builder.sb_to_str`,
> `xiom.string.compare.str_compare` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Overview

`xiom.edl` is a small, dependency-free codec for CMX 3600-style edit decision
lists. It parses a whole document into one flat line stream, exposes titles,
comments and events through typed accessors, and emits a canonical EDL.

The codec covers the structural subset of the format that describes an edit:

- `TITLE <text>` lines, stored and re-emitted (the first one is available
  through `edl_title`),
- comment lines beginning with `*` or `;`, stored raw (marker included) and
  preserved in document order,
- event lines `NNN <reel> <track> <transition> [duration] <src-in>
  <src-out> <rec-in> <rec-out>` with
  - event numbers exactly three digits, 001..999, strictly increasing,
  - reels of 1..8 letters/digits/underscores (`BL` is black, documented but
    not special-cased),
  - track designators `V`, `A`, `A2`, `AA`, `B`, `A3`, `A4`,
  - transitions `C` (cut, no duration), `D nnn` (dissolve, 1..999 frames)
    and `Wnnn` (wipe code 001..999, passed through),
  - timecodes `hh:mm:ss:ff` with frame bases 24, 25 or 30 and `ff` strictly
    below the base.

"Edit decision list" means exactly that here: the codec is a structural
reader/writer. It performs no frame math, no duration or continuity checks,
no drop-frame conversion, no data inspection. Drop-frame timecodes
(`hh:mm:ss;ff`) are rejected, not converted; `FCM:` headers are outside the
subset and must be stripped before parsing.

## Install / use

```
xiom pkg install xiom.edl@0.1.0
```

```xi
use xiom.edl;
```

## Quick start

```xi
use xiom.edl;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  let src = "TITLE Demo\n* first assembly\n001 AX V C 00:00:00:00 00:00:05:00 01:00:00:00 01:00:05:00\n002 BL V D 030 00:00:00:00 00:00:03:00 01:00:05:00 01:00:08:00\n";
  let r = edl_parse(src, EDL_FPS_25);
  match r {
    Ok(edl) => {
      io.println(edl_title(&edl));                 // Demo
      io.println(int_to_string(edl_event_count(&edl))); // 2
      io.println(edl_event_reel(&edl, 0));         // AX
      io.println(edl_event_track(&edl, 1));        // V
      io.println(edl_event_src_in(&edl, 0));       // 00:00:00:00
      if edl_event_transition(&edl, 1) == TR_DISSOLVE {
        io.println(int_to_string(edl_event_duration(&edl, 1))); // 30
      }
      io.println(edl_emit(&edl));                  // canonical EDL text
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## API summary

Line kinds (returned by `edl_line_kind`):

| Constant | Value | Line |
|---|---|---|
| `LK_TITLE` | 1 | `TITLE <text>` |
| `LK_COMMENT` | 2 | `* ...` or `; ...`, stored raw |
| `LK_EVENT` | 3 | one event line |

Transition kinds (returned by `edl_event_transition`):

| Constant | Value | Transition |
|---|---|---|
| `TR_CUT` | 1 | `C`, no duration |
| `TR_DISSOLVE` | 2 | `D nnn`, 1..999 frames |
| `TR_WIPE` | 3 | `Wnnn`, code 001..999 passed through |

Timecode selectors and components, and frame bases:

| Constant | Value | Meaning |
|---|---|---|
| `TC_SRC_IN` | 1 | source in point |
| `TC_SRC_OUT` | 2 | source out point |
| `TC_REC_IN` | 3 | record in point |
| `TC_REC_OUT` | 4 | record out point |
| `TCF_HH` / `TCF_MM` / `TCF_SS` / `TCF_FF` | 1 / 2 / 3 / 4 | hours / minutes / seconds / frames |
| `EDL_FPS_24` / `EDL_FPS_25` / `EDL_FPS_30` | 24 / 25 / 30 | supported frame bases |

Parse / emit:

| Function | Returns | Description |
|---|---|---|
| `edl_parse(text, fps)` | `Result[Edl, Str]` | Parse a whole document at frame base `fps` (24/25/30); LF and CRLF; `Err("edl: ...")` on malformed input. |
| `edl_emit(e)` | `Str` | Canonical emission: LF lines, single-space fields, 3-digit numbers/durations/wipe codes, `hh:mm:ss:ff` timecodes; round-trip safe. |

Line accessors (out-of-range results in parentheses):

| Function | Returns | Description |
|---|---|---|
| `edl_line_count(e)` | `Int` | Number of stored lines. |
| `edl_line_kind(e, i)` | `Int` | `LK_*` code (`-1`). |
| `edl_line_text(e, i)` | `Str` | Title text or raw comment line; `""` for events (`""`). |
| `edl_title(e)` | `Str` | Text of the first `TITLE` line (`""`). |
| `edl_title_count(e)` | `Int` | Number of `TITLE` lines. |
| `edl_comment_count(e)` | `Int` | Number of comment lines. |
| `edl_frame_base(e)` | `Int` | Frame base stored at parse time. |

Event accessors, indexed by event ordinal (`0..edl_event_count(e)-1`):

| Function | Returns | Description |
|---|---|---|
| `edl_event_count(e)` | `Int` | Number of event lines. |
| `edl_event_line(e, i)` | `Int` | Stream index of event `i` (`-1`). |
| `edl_event_number(e, i)` | `Int` | Event number 1..999 (`-1`). |
| `edl_event_reel(e, i)` | `Str` | Reel token, verbatim (`""`). |
| `edl_event_track(e, i)` | `Str` | Track token, verbatim (`""`). |
| `edl_event_transition(e, i)` | `Int` | `TR_*` code (`-1`). |
| `edl_event_duration(e, i)` | `Int` | Dissolve frames for `D`, else 0 (`-1`). |
| `edl_event_wipe(e, i)` | `Int` | Wipe code for `W`, else 0 (`-1`). |
| `edl_event_timecode_value(e, i, which)` | `Int` | Packed `hh*1000000 + mm*10000 + ss*100 + ff` (`-1`). |
| `edl_event_timecode(e, i, which)` | `Str` | Canonical `hh:mm:ss:ff` (`""`). |
| `edl_event_src_in(e, i)` | `Str` | Source in as `hh:mm:ss:ff` (`""`). |
| `edl_event_src_out(e, i)` | `Str` | Source out as `hh:mm:ss:ff` (`""`). |
| `edl_event_rec_in(e, i)` | `Str` | Record in as `hh:mm:ss:ff` (`""`). |
| `edl_event_rec_out(e, i)` | `Str` | Record out as `hh:mm:ss:ff` (`""`). |

Timecode helpers:

| Function | Returns | Description |
|---|---|---|
| `edl_timecode_part(value, part)` | `Int` | One of `hh`/`mm`/`ss`/`ff` (`TCF_*`) of a packed value (`-1`). |
| `edl_timecode(hh, mm, ss, ff)` | `Str` | Canonical text from four components, each clamped to two digits. |

`edl_line_*` accessors index the flat line stream (comments and titles
included); `edl_event_*` accessors index events only. Use
`edl_event_line(e, i)` to map an event to its stream line.

## Error model

`edl_parse` is total: it returns `Ok(Edl)` or `Err(msg)` with an `"edl: "`
prefix. The offending line is appended where shown.

| Message | Raised when |
|---|---|
| `edl: NUL byte in input` | The input contains a `0x00` byte. |
| `edl: unsupported frame base: <n>` | `fps` is not 24, 25 or 30. |
| `edl: unexpected line: <line>` | A non-blank line is not a comment, a `TITLE` line or an event (`FCM:`, lowercase keywords, stray text). |
| `edl: bad TITLE: <line>` | `TITLE` with no text. |
| `edl: bad event number: <line>` | Event number is not three digits 001..999. |
| `edl: event number out of order: <line>` | Event number is not strictly greater than the previous one (duplicates included). |
| `edl: bad reel: <line>` | Reel longer than 8 bytes or with a byte outside `A-Za-z0-9_`. |
| `edl: unknown track: <line>` | Track is not `V`, `A`, `A2`, `AA`, `B`, `A3` or `A4`. |
| `edl: bad transition: <line>` | Transition is not `C`, `D` or `W` + 3 digits with a value in 001..999. |
| `edl: missing dissolve duration: <line>` | `D` is the last token on the line. |
| `edl: bad dissolve duration: <line>` | Duration is not 1..3 digits with a value in 1..999. |
| `edl: missing field: <line>` | The event line ends before its transition-specific fields are complete. |
| `edl: bad timecode: <line>` | Timecode is not `hh:mm:ss:ff`, has `mm > 59`, `ss > 59`, or uses the drop-frame `;`. |
| `edl: frame out of range: <line>` | A timecode's `ff` is >= the frame base. |
| `edl: trailing text: <line>` | An event line has more tokens than the transition allows. |

Every accessor and `edl_emit` are total; they never return errors. `edl_emit`
does not validate: a hand-built `Edl` should keep its twelve Vecs the same
length, its `Str` fields NUL-free and its transition codes `TR_*`.

## Canonical form

```
TITLE Demo
* first assembly
001 AX V C 00:00:00:00 00:00:05:00 01:00:00:00 01:00:05:00
002 BL V D 030 00:00:00:00 00:00:03:00 01:00:05:00 01:00:08:00
003 AX A2 W001 00:00:00:00 00:00:02:00 01:00:08:00 01:00:10:00
```

Every line ends with LF; fields are separated by single spaces; event
numbers, dissolve durations and wipe codes are zero-padded to three digits;
timecodes are `hh:mm:ss:ff`. CRLF, blank lines, indentation, column
alignment and whitespace runs are normalized away.

## Limitations

- Documented subset only: `FCM:` headers, motion effects (`M` codes),
  speed/reverse/key parameters and other CMX3600 directives are outside the
  grammar and parse as errors or unknown tracks, not as pass-through.
- Drop-frame (`;`) timecodes and non-integer frame rates are rejected; the
  frame base is one of 24, 25, 30 and `ff` must be below it.
- Wipe codes are `W` + exactly three digits; dissolve durations are 1..3
  digits on input but always emit as three digits.
- No frame math: durations, offsets, continuity and record-point gaps are
  never computed or checked; `edl_timecode_part` only unpacks the stored
  components.
- Event numbers must be strictly increasing; gaps are preserved, duplicates
  and decreases are errors.
- Reels, tracks and wipe codes are opaque tokens: `BL` is documented as
  black but not special-cased.
- Whole-document only: no streaming, no editing/renumbering API, no file
  I/O, no media inspection.
- Errors carry the offending line text but no line or column numbers.

See `SPEC.md` for the exact grammar, field rules, data-model invariants, the
error catalog, the round-trip rules and the test matrix.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
