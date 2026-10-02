# xiom.video -- Specification

Status: `incubating` (implemented, conformance-green 24/24 on compiler
v0.62.2; not published).
Manifest: `package.xi` (`xiom.video`, version `0.1.0`, category `media`).
Modules: `src/video.xi` (`xiom.video`), `src/store.xi` (`xiom.video.store`),
`src/avi.xi` (`xiom.video.avi`), `src/raw.xi` (`xiom.video.raw`),
`src/container.xi` (`xiom.video.container`).
Depends on `xiom.std`; the core module imports `xiom.string.builder`.

This document describes the byte-level formats and policies this package
actually implements. Payload bytes (video and audio frames, codec-private
data) are always opaque spans: no codec is decoded, parsed or written.

## 1. Magic sniffing

`video_sniff(data)` inspects at most the first 12 bytes:

| Result | Condition |
|---|---|
| `VIDEO_FMT_RAW` | `"XRAW"` at 0 |
| `VIDEO_FMT_OGG` | `"OggS"` at 0 |
| `VIDEO_FMT_AVI` | `"RIFF"` at 0 and `"AVI "` at 8 (needs >= 12 bytes) |
| `VIDEO_FMT_MKV` | `1A 45 DF A3` at 0 (EBML) |
| `VIDEO_FMT_MP4` | `"ftyp"` at 4 (needs >= 8 bytes) |
| `VIDEO_FMT_UNKNOWN` | anything else, including a lone `RIFF` (e.g. WAV) |

`video_format_name` maps a format to `"avi"`, `"mkv"`, `"mp4"`, `"ogg"`,
`"raw"` or `"unknown"`. Matroska/WebM, MP4 and Ogg are sniffed but have no
demuxer here: `video_demux` returns `video: unsupported format` for them.

## 2. The VideoStream store

`VideoStream` is a flat store. Header scalars: `format`, `width`, `height`,
`duration_units` (container milliseconds), `index_entries`, `index_ok`
(`VIDEO_INDEX_OK` / `_BAD` / `_NONE`), `flags`.

Tracks are nine parallel `Vec[Int]` pools, one element per track:
`trk_kind` (`VIDEO_KIND_VIDEO` = 1, `VIDEO_KIND_AUDIO` = 2,
`VIDEO_KIND_OTHER` = 3), `trk_codec` (opaque packed FourCC or format tag),
`trk_scale`/`trk_rate` (one tick is `scale/rate` seconds; both positive),
`trk_length` (declared length in ticks), `trk_width`, `trk_height`,
`trk_channels`, `trk_sample_rate` (0 when absent).

Frames are ten parallel pools plus one bytes blob: `frm_track`, `frm_pts`,
`frm_dts`, `frm_duration` (container milliseconds), `frm_key` (1 = key),
`frm_codec` (source chunk FourCC, 0 when not applicable), `frm_offset` /
`frm_size` (span of `frm_blob`), `frm_chunk_offset` (source-file offset of
the chunk, `-1` when not applicable).

Invariants enforced by construction:

- `video_add_track` / `video_add_frame(_span)` push every pool exactly once,
  so the pools cannot drift; all accessors nevertheless operate on the
  minimum length across the pools and guard indices, returning `-1` (or an
  empty `Vec`/default `VideoFrame`) out of range.
- `video_add_track` rejects a kind outside 1..3 (`video: bad track kind`),
  non-positive scale/rate (`video: bad timebase`), a negative codec
  (`video: bad codec`), negative length/width/height/channels/sample rate
  (`video: bad track field`) and more than `VIDEO_MAX_TRACKS` = 100 tracks
  (`video: too many streams`).
- `video_add_frame_span` rejects an out-of-range track
  (`video: bad track index`), negative pts/dts (`video: bad timestamp`),
  negative duration (`video: bad duration`), a negative codec
  (`video: bad codec`) and a span outside the source (`video: bad payload
  span`); `key` is normalised to 0/1. Payload bytes are copied in order.
- There is no `Vec[StructType]`, no `Vec[Str]` and no `Float64` anywhere.

## 3. Timebase and frame math

A timebase `(num, den)` means one tick is `num/den` seconds. All timebase
numbers must be positive; otherwise `video_rescale` returns 0 (no division
by zero).

```
video_rescale(ts, sn, sd, dn, dd) =
  round_half_away_from_zero( ts * sn * dd / (sd * dn) )
```

The rounding is computed with truncated division plus a remainder check, so
it is correct for negative `ts` (`-1` tick of 1/2000 s rescaled to
milliseconds is `-1`, not `0`). Container timestamps are integer
milliseconds (timebase 1/1000). Other helpers:

- `video_units_to_ms(ts, sn, sd)` = rescale to 1/1000.
- `video_ms_to_units(ms, dn, dd)` = rescale from 1/1000.
- `video_tick_ms(sn, sd)` = duration of one tick in ms.
- `video_frame_duration_ms(fps_num, fps_den)` = one frame at that rate.
- `video_frame_new(track, pts, dts, duration, keyframe)` normalises
  `keyframe` to 0/1; `video_frame_valid` requires track/pts/dts/duration
  non-negative; `video_frame_end` returns `pts + duration`.
- `video_format_time(ts, sn, sd)` renders `"HH:MM:SS.mmm"` (negative input
  clamps to zero, hours above 99 print in full).

Overflow is not checked: values are expected to stay in the signed 64-bit
range (test-scale payloads and timestamps).

## 4. Raw elementary-stream format (`XRAW`)

The proof elementary-stream container is little-endian:

```
"XRAW" u8 version(1) u8 track_count u16 reserved(0)
track_count * 36-byte entries:
  kind u32, codec u32, scale u32, rate u32, length u32,
  width u32, height u32, channels u32, sample_rate u32
records until EOF:
  track u32, pts u32, dts u32, duration u32,
  flags u32 (bit 0 = keyframe), size u32, payload[size]
```

`raw_mux` writes the header, the track table from the store and one record
per frame in store order. `raw_demux` validates the magic, the version (must
be 1) and the track table bounds; each record's `track` must be below the
track count and the payload must fit. A buffer that ends inside a record
header or payload is `video: truncated record`. A zero-length payload is
legal. The container duration is the maximum of the per-track declared
durations and the last frame's end.

## 5. RIFF/AVI subset

### 5.1 Layout written by `avi_mux`

```
"RIFF" u32le (size - 8) "AVI "
  LIST hdrl
    avih  (56 bytes: micros/frame, 0, 0, AVIF_HASINDEX, total frames,
           0, stream count, 0, width, height, 4 * 0)
    LIST strl  (one per track, in track order)
      strh  (56 bytes: handler fcc, codec fcc, flags 0, priority 0,
             language 0, initial frames 0, scale, rate, start 0, length,
             suggested buffer (= largest frame on that track), quality 0,
             sample size 0, rcFrame 0,0,w,h)
      strf  (video/other: 40-byte BITMAPINFOHEADER with biSize 40,
             width, height, planes 1, bit count 24, compression = codec,
             remaining fields 0; audio: 18-byte WAVEFORMATEX with
             wFormatTag = codec, channels, sample rate, avg bytes/sec =
             rate*channels*2, block align = channels*2, bits 16, cbSize 0)
  LIST movi
    one chunk per frame in store order:
      "<nn>dc" video, "<nn>wb" audio, "<nn>tx" other
      (nn = two decimal digits of the track index)
      u32le size + payload, padded with one 0x00 byte when odd
  idx1  (16 bytes per frame: chunk id, flags (0x10 = keyframe),
         offset relative to the 'movi' FourCC, size)
```

The file is deterministic: the same store always produces identical bytes.

### 5.2 Parsing policy (`avi_demux`)

- The RIFF size must be `>= 4` and `declared + 8 <= data.len()`; parsing is
  bounded by `min(declared + 8, buffer end)`.
- Top-level chunks are walked strictly forward. Unknown chunks and unknown
  LIST types are skipped by their declared size; a chunk whose body crosses
  its parent is `video: truncated chunk`.
- `hdrl` must be present (`video: missing header list`) and must contain one
  `avih` (`video: missing main header`) and at least one `strl`
  (`video: missing stream header`). `avih` must be at least 40 bytes
  (`video: truncated main header`); when its dwStreams is non-zero it must
  equal the number of parsed streams (`video: bad stream count`).
- Inside `strl`, `strh` must come before `strf` (`video: bad stream
  order`), `strh` needs its fixed 56 bytes (`video: truncated stream
  header`), a video/other `strf` needs 40 bytes and an audio `strf` 16 bytes
  (`video: truncated stream format`). `strh` gives the handler
  (`vids`/`auds`/anything else), codec `fccHandler`, scale, rate and length;
  `strf` gives width/height/compression (video) or format tag, channels and
  sample rate (audio). A zero `fccHandler` falls back to the `strf` codec
  tag.
- Inside `movi`, chunk ids whose first two bytes are decimal digits are
  parsed: `dc`/`db` (video), `wb` (audio) and `tx` (other) record a frame;
  any other chunk is skipped. A recorded stream number outside the track
  table is `video: bad stream number`. Frames get `frm_codec` = chunk id,
  `frm_chunk_offset` = chunk header offset, and `pts = dts =`
  `video_units_to_ms(stream frame index, scale, rate)` with `duration =
  video_tick_ms(scale, rate)` (AVI chunks carry no timestamps; timing is
  derived from chunk order and the stream timebase).
- `idx1` is checked against the parsed frames. Its size must be a multiple
  of 16 (`video: bad index size`). Each entry's `dwOffset` is resolved as
  `'movi' FourCC offset + dwOffset` (the first chunk after the `movi` type
  field is 4) and must match a parsed frame with the same chunk id and size;
  `0x10` in the flags sets that frame's keyframe bit. If every entry matches
  and the entry count equals the frame count, `index_ok` is
  `VIDEO_INDEX_OK`; any mismatch makes it `VIDEO_INDEX_BAD` (parsing still
  succeeds); no `idx1` leaves `VIDEO_INDEX_NONE` and every key flag 0.
- More than 100 streams is `video: too many streams`; a store with no track
  is `video: no streams` (both are writer-side checks as well).

`avi_mux` fails with `video: no streams` for an empty store,
`video: too many streams` above 100 tracks and `video: bad frame track` for
an inconsistent frame.

## 6. Dispatch

`video_demux(data)`:

| Input | Result |
|---|---|
| < 4 bytes | `Err("video: truncated header")` |
| AVI | `avi_demux` |
| XRAW | `raw_demux` |
| mkv/mp4/ogg magic | `Err("video: unsupported format")` |
| anything else | `Err("video: unknown format")` |

`video_mux(s, format)` accepts `VIDEO_FMT_AVI` and `VIDEO_FMT_RAW`; any
other format is `Err("video: unsupported format")`. `video_mux_avi` and
`video_mux_raw` are the direct aliases.

## 7. Error catalog

All messages are prefixed `video: `.

| Message | Raised when |
|---|---|
| `truncated header` | buffer too short for the sniff/readers or the raw header/track table |
| `unsupported format` | mkv/mp4/ogg demux or a mux format other than avi/raw |
| `unknown format` | magic matched nothing |
| `bad fourcc` | `video_fourcc_to_str` saw a byte outside 0x20..0x7E |
| `bad track kind` | track kind outside 1..3 |
| `bad timebase` | scale or rate <= 0 |
| `bad track field` | negative length/width/height/channels/sample rate |
| `bad codec` | negative codec tag |
| `too many streams` | more than 100 tracks (builder or muxer) |
| `bad track index` | frame references a track that does not exist |
| `bad timestamp` | negative pts or dts |
| `bad duration` | negative duration |
| `bad payload span` | span outside the source buffer |
| `not a raw stream` / `bad raw version` | XRAW magic/version mismatch |
| `truncated record` | raw record header or payload crosses the buffer |
| `not avi` | RIFF magic present but form type is not `AVI ` |
| `bad riff size` | declared RIFF size < 4 or crossing the buffer |
| `truncated chunk` | a chunk header/body crosses its parent |
| `missing header list` / `missing main header` / `missing stream header` / `missing stream format` | hdrl, avih, strl or strf absent |
| `bad stream order` | `strf` before `strh` |
| `bad stream count` | avih dwStreams differs from the parsed stream count |
| `truncated main header` / `truncated stream header` / `truncated stream format` | avih/strh/strf shorter than required |
| `bad stream number` | movi chunk names a stream outside the track table |
| `bad index size` | idx1 size is not a multiple of 16 |
| `bad frame track` | muxer saw a frame with a negative track |
| `no streams` | AVI muxer given a store with no track |

## 8. Limits

- At most 100 tracks; chunk stream numbers use two decimal digits.
- Timestamps and sizes are stored as unsigned 32-bit little-endian in raw
  and as unsigned 32-bit fields in AVI; negative timestamps are rejected by
  the builder.
- One-shot parsing only; payloads are copied into memory and never
  interpreted.
- The AVI index cross-check is O(frames * entries); everything else is
  linear in the buffer size.

## 9. Test plan (`tests/test_conformance.xi`, 24 checks)

1. Sniffing (`avi`/`mkv`/`mp4`/`ogg`/`raw`/`unknown`, RIFF-WAV, short and
   junk buffers) and the format-name mapping.
2. FourCC decode: printable tables (`movi`, `00dc`) and NUL/control
   rejection.
3. Timebase rescale: fps durations, half-away-from-zero rounding, negative
   timestamps, invalid timebases, conversion helpers.
4. Frame model: field normalisation, validity, `video_frame_end`.
5. `video_format_time` cases and clamping.
6. Raw round-trip: tracks, frames, timestamps, key flags, payload bytes,
   derived track/frame counts and duration.
7. Raw determinism and the empty stream.
8. Raw error cases: magic, version, truncated header/record, oversized
   payload, bad track, zero-length payload.
9. AVI writer structure: RIFF/AVI magic, size field, hdrl/avih/strl/movi/
   idx1 presence and per-kind chunk ids.
10. AVI round-trip: headers, tracks, frames, derived pts/duration, idx1 ok,
    key flags and chunk offsets.
11. AVI index mismatch: parse succeeds, `index_ok` becomes BAD.
12. AVI without idx1: `index_ok` NONE, no key flags.
13. AVI container errors: short buffer, not-avi, bad riff size, truncated
    chunk, missing header list.
14. AVI header errors: missing strl/strf, bad stream order/count, truncated
    avih/strh/strf.
15. AVI movi/index errors: bad stream number and bad index size, keyframe
    flags from idx1.
16. Mux validation: AVI needs a stream; raw allows an empty stream.
17. Dispatch: raw/avi parse; mkv/mp4/ogg are unsupported; unknown magic and
    short buffers; unsupported mux format.
18. Builder validation: kinds, timebases, codecs, fields, timestamps,
    durations, spans and normalised key flags.
19. Empty-store accessor guards and setter behaviour.
20. Duration math: track durations across timebases, tick sizes,
    conversions.
21. Binary fidelity: NUL/0x80/0xFF payloads and odd sizes through both
    containers.
22. Chunk ids: per-track digits and dc/wb/tx types (`00dc`, `01wb`,
    `02tx`).
23. AVI mux determinism: identical bytes and parsed snapshots.
24. Mux dispatch aliases agree with `video_mux`.

Run:

```powershell
.\scripts\port.ps1 -Package xiom-video -TimeoutSec 60
```
