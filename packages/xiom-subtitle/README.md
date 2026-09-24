# xiom.subtitle

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** SRT and WebVTT subtitle parsing, formatting, and shifting.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string` and
> `xiom.string.compare`). Tests additionally use `xiom.test` and `xiom.io`.

## Scope

`xiom.subtitle` parses and writes the two dominant plain-text caption
formats, SubRip (SRT) and WebVTT, into a single in-memory model: a
`Subtitle` is three parallel per-cue arrays (`starts`, `ends` in
milliseconds; `texts` with embedded `\n` line breaks). It also shifts a
whole track in time with clamping at zero. The module contains no FFI, no
file I/O and no dependency beyond `xiom.string` helpers.

## API

| Function | Returns | Description |
|---|---|---|
| `srt_parse(text)` | `Result[Subtitle, Str]` | Parse an SRT document; LF and CRLF; strict sequential 1-based indices; one or more text lines per cue. |
| `srt_format(s)` | `Str` | Write SRT: cues re-numbered from 1, `,` timestamps, LF, blank line between cues. |
| `vtt_parse(text)` | `Result[Subtitle, Str]` | Parse WebVTT: `WEBVTT` header required, NOTE blocks skipped, `.` (and `,`) timestamps, cue settings ignored. |
| `vtt_format(s)` | `Str` | Write WebVTT: `WEBVTT` header, blank line, cues without indices, `.` timestamps. |
| `subtitle_shift(s, delta_ms)` | `Subtitle` | Shift every cue by `delta_ms`; both times clamp at 0. |
| `subtitle_cue_count(s)` | `Int` | Number of cues. |
| `subtitle_start_ms(s, i)` | `Int` | Cue start in ms; `-1` out of range. |
| `subtitle_end_ms(s, i)` | `Int` | Cue end in ms; `-1` out of range. |
| `subtitle_text(s, i)` | `Str` | Cue text (lines joined with `\n`); `""` out of range. |
| `subtitle_total_duration_ms(s)` | `Int` | Maximum cue end (0 for an empty track). |

## Usage

```xi
use xiom.subtitle;
use xiom.io;

fn main() -> Int {
  let text = "1\n00:00:01,000 --> 00:00:02,000\nHello\n";
  let r = srt_parse(text);
  if r.is_ok {
    let s = r.value;
    io.println(subtitle_text(&s, 0));        // Hello
    let later = subtitle_shift(&s, 1500);
    io.println(srt_format(&later));          // cue moved to 00:00:02,500
  } else {
    io.println(r.error);
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.subtitle
```

Expected tail: 20 `[PASS]` lines, `xiom.subtitle: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- SRT (SubRip) and WebVTT only; no ASS/SSA, MicroDVD, TTML or binary formats.
- Cue indices are strict: SRT blocks must be numbered `1..n` in order; a
  wrong or non-numeric index is an error.
- Timestamps must be the 12-byte `HH:MM:SS,mmm` / `HH:MM:SS.mmm` form with
  minutes and seconds `0..59` and hours `00..99`; SRT also accepts `.`, VTT
  also accepts `,`.
- Blocks are separated by blank lines; a whitespace-only line is text, not a
  separator, and blocks without a separator merge into one cue's text.
- WebVTT cue identifiers and `STYLE`/`REGION` blocks are not supported; cue
  settings are ignored on read and never written.
- A leading UTF-8 BOM is not stripped, and a lone `\r` is not a line ending.
- Text is treated as a UTF-8 byte buffer and round-trips byte-exact.

See `SPEC.md` for the grammar, timestamp grammar, error catalog and test
plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
