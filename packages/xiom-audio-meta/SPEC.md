# xiom.audio-meta -- Specification

Status: `incubating` (implemented, harness-green with compiler 0.62.2; not
published).
Manifest: `package.xi` (`xiom.audio-meta`, version `0.1.0`).
Modules: `xiom.audio_meta` (`src/audio_meta.xi`),
`xiom.audio_meta.trackers` (`src/trackers.xi`),
`xiom.audio_meta.chiptune` (`src/chiptune.xi`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`).
No FFI: the package declares no `extern "C"` blocks.

## Scope

Pure-XIOM structural metadata parsers for chiptune/tracker formats:

- `midi_parse` / `midi_is_valid` -- Standard MIDI File header, track walk,
  varlen, channel/meta/sysex events, aggregate counters;
- `mod_parse` / `mod_is_valid` -- ProTracker 31-instrument header, accepted
  signature subset, order table, sample and pattern-cell statistics;
- `xm_parse` / `xm_is_valid` -- FastTracker II header, order table, pattern
  geometry, instrument/sample walk;
- `s3m_parse` / `s3m_is_valid` -- Scream Tracker 3 header, order table,
  paragraph pattern pointers, pattern geometry;
- `it_parse` / `it_is_valid` -- Impulse Tracker header, order table,
  instrument/sample/pattern pointers, pattern geometry;
- `nsf_parse` / `nsf_is_valid` -- 128-byte NSF header;
- `chiptune_count` / `chiptune_entry` / `chiptune_detect` /
  `chiptune_detect_id` -- a 40-entry magic registry.

## Non-goals

- Audio rendering, synthesis, resampling, mixing or playback of any kind.
- Sample/instrument decoding: PCM bytes, envelopes, loop points and
  waveform data are never interpreted.
- Pattern unpacking or event decoding (the packed pattern payload is skipped
  by its declared size).
- Playback semantics: tempo/BPM are reported as stored; timing is not
  simulated.
- File repair, conversion between formats, streaming I/O and payloads above
  the addressable `Int` range. The API works on in-memory `Vec[UInt8]`.

## Text field policy

All names/titles/text fields are exposed as **printable-ASCII prefixes**:
byte extraction stops at the first `0x00` (which cannot live in a `Str`) or
at the first byte outside `0x20..0x7E`, and returns `""` when the first byte
already stops the scan. This is the only byte-to-`Str` path in the package,
so `sb_to_str` never receives a NUL. Trailing padding (spaces or NULs) is
therefore not included unless it is printable and precedes the stop byte;
callers that need raw bytes should use the source buffer.

## MIDI (Standard MIDI File)

### Header

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 4 | `MThd` | ASCII magic. |
| 4 | 4 | header length, big-endian | >= 6 and must fit (`8 + len <= data.len()`); extra bytes are skipped. |
| 8 | 2 | format | 0, 1 or 2. |
| 10 | 2 | ntrks | >= 1; exactly this many `MTrk` chunks must follow. |
| 12 | 2 | division | see below. |

Division: bit 15 clear -> ticks per quarter note, must be nonzero. Bit 15
set -> SMPTE: high byte is a negative frames-per-second value (two's
complement, e.g. `0xE8` -> -24), low byte is ticks per frame; both must be
nonzero. Format/track-count consistency (format 0 having one track, format 1
sharing time) is not enforced.

### Tracks

Each track is `MTrk` + u32 length + exactly that many event bytes. The walk
must land exactly on the end of the chunk; after the last declared track the
buffer must be fully consumed.

Event grammar: `delta varlen` then one of

| Status | Form | Data bytes |
|---|---|---|
| `0x8n`..`0xEn` | channel message | 2 (`0xCn`, `0xDn`: 1) |
| running status | data bytes only, using the previous channel status | as above |
| `0xFF` | meta: type byte, varlen length, payload | payload length |
| `0xF0` / `0xF7` | sysex: varlen length, payload | payload length |

Varlen quantities are at most 4 bytes (a continued 4th byte is an error).
Meta and sysex events clear running status, as SMF requires. Status bytes
`0xF1`..`0xF6` and `0xF8`..`0xFE` are rejected.

Interpreted meta events: `0x51` length 3 (first tempo in microseconds per
quarter note), `0x03` (first track name), `0x2F` (end of track, counted).
Everything else is counted but not interpreted. Note-on is status high
nibble 9 with a nonzero velocity byte.

### Error catalog

| Error | Condition |
|---|---|
| `midi: empty input` | zero-length buffer. |
| `midi: truncated header` | `< 14` bytes, or header length runs past the buffer. |
| `midi: bad MThd magic` | bytes 0..3 are not `MThd`. |
| `midi: short header chunk` | declared header length `< 6`. |
| `midi: bad format` | format `> 2`. |
| `midi: zero tracks` | ntrks `0`. |
| `midi: bad division` | zero division, or SMPTE fps/tpf zero. |
| `midi: missing track chunk` | fewer than ntrks `MTrk` chunks. |
| `midi: track chunk overrun` | declared track length runs past the buffer. |
| `midi: truncated event` | delta/status/meta/sysex read runs past the track end. |
| `midi: bad varlen` | 4 continuation bytes without a terminator. |
| `midi: bad running status` | data byte before any channel status. |
| `midi: bad status` | reserved system status byte. |
| `midi: trailing data` | bytes remain after the last declared track. |

## MOD (ProTracker / Startrekker)

Header offsets (decimal):

| Offset | Size | Field |
|---|---|---|
| 0 | 20 | title (text policy) |
| 20 | 31 x 30 | sample headers: name 22, length u16be, finetune, volume, loop start u16be, loop length u16be |
| 950 | 1 | song length (1..128) |
| 951 | 1 | restart position |
| 952 | 128 | order table; only the first `song_length` entries are used, each `<= 127` |
| 1080 | 4 | signature |
| 1084 | ... | pattern data |

Accepted signature subset -> channels:

| Signature | Channels |
|---|---|
| `M.K.`, `M!K!`, `M&K!`, `N.T.`, `FLT4`, `4CHN` | 4 |
| `6CHN` | 6 |
| `8CHN`, `FLT8`, `CD81`, `OKTA` | 8 |
| `16CN` | 16 |
| `32CN` | 32 |

`patterns = max(order[0..song_length-1]) + 1`; the buffer must hold
`1084 + patterns * 64 * channels * 4` bytes. Trailing bytes after the last
pattern are allowed. Pattern statistics scan every cell of every counted
pattern: a cell is 4 bytes (`b0`, `b1`, `b2`, `b3`); period =
`(b0 & 0x0F) * 256 + b1`; sample number = `(b0 & 0xF0) | (b2 >> 4)`. Sample
statistics: `sample_count` counts lengths `> 0`, `sample_bytes` sums
`length * 2` (8-bit sample data).

### Error catalog

| Error | Condition |
|---|---|
| `mod: empty input` | zero-length buffer. |
| `mod: truncated header` | `< 1084` bytes. |
| `mod: bad signature` | signature not in the table. |
| `mod: zero song length` | song length `0`. |
| `mod: bad song length` | song length `> 128`. |
| `mod: bad order entry` | used order entry `> 127`. |
| `mod: truncated pattern data` | buffer smaller than `1084 + patterns * 64 * channels * 4`. |

## XM (FastTracker II)

Fixed header:

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 17 | `Extended Module: ` | ASCII magic. |
| 17 | 20 | module name | text policy. |
| 37 | 1 | `0x1A` marker | must match. |
| 38 | 20 | tracker name | text policy. |
| 58 | 2 | version (LE) | `0x0102`..`0x0104`. |
| 60 | 4 | header size (LE) | >= 276 and must fit. |
| 64 | 2 | song length | 1..256. |
| 66 | 2 | restart position | `<= 255`. |
| 68 | 2 | channels | 1..64. |
| 70 | 2 | patterns | 1..256. |
| 72 | 2 | instruments | `<= 128`. |
| 74 | 2 | flags | reported as stored. |
| 76 | 2 | tempo | 1..31. |
| 78 | 2 | BPM | `>= 32`. |
| 80 | 256 | order table | first `song_length` entries `< patterns`. |

Pattern data starts at `60 + header_size`. Every pattern header is u32
length (>= 9, must fit), u8 packing type (0..1), u16 rows (1..256), u16
packed size. The data size is: `packed size` when packing type is 1 and the
packed size is nonzero, otherwise `rows * channels * 5` (unpacked patterns
and packed patterns with a zero packed size). The data is skipped, not
decoded.

Instruments follow the patterns. Each instrument is a u32 header size
(>= 29, includes its own 4 bytes, must fit), a 22-byte name, a type byte and
a u16 sample count at header offset 27 (`<= 128`). After the header come the
sample headers: each 40 bytes (u32 length, u32 loop start, u32 loop length,
volume, finetune, type, panning, relative note, reserved, 22-byte name),
followed by its sample data: `length` bytes, or `length * 2` when type bit 4
(16-bit) is set. The buffer must end exactly after the last instrument.

### Error catalog

| Error | Condition |
|---|---|
| `xm: empty input` | zero-length buffer. |
| `xm: truncated header` | `< 60` bytes, or `60 + header size` runs past the buffer. |
| `xm: bad magic` | not `Extended Module: `. |
| `xm: missing 0x1A marker` | byte 37 is not `0x1A`. |
| `xm: bad version` | version outside `0x0102`..`0x0104`. |
| `xm: bad header size` | declared size `< 276`. |
| `xm: bad song length` | 0 or `> 256`. |
| `xm: bad restart position` | `> 255`. |
| `xm: bad channel count` | 0 or `> 64`. |
| `xm: bad pattern count` | 0 or `> 256`. |
| `xm: bad instrument count` | `> 128`. |
| `xm: bad tempo` | 0 or `> 31`. |
| `xm: bad bpm` | `< 32`. |
| `xm: bad order entry` | order entry `>= patterns`. |
| `xm: truncated pattern header` | fewer than 9 bytes, or declared length runs past the buffer. |
| `xm: bad pattern header size` | pattern header length `< 9`. |
| `xm: bad pattern packing` | packing type `> 1`. |
| `xm: bad pattern rows` | 0 or `> 256`. |
| `xm: truncated pattern data` | computed data size runs past the buffer. |
| `xm: truncated instrument` | fewer than 29 bytes, or declared size runs past the buffer. |
| `xm: bad instrument size` | declared size `< 29`. |
| `xm: bad sample count` | sample count `> 128`. |
| `xm: truncated sample header` | fewer than 40 bytes for a sample header. |
| `xm: truncated sample data` | sample data size runs past the buffer. |
| `xm: trailing data` | bytes remain after the last instrument. |

## S3M (Scream Tracker 3)

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 28 | song name | text policy. |
| 28 | 1 | `0x1A` marker | must match. |
| 29 | 1 | file type | `0x10`. |
| 30 | 2 | reserved | ignored. |
| 32 | 2 | ordnum (LE) | 1..256. |
| 34 | 2 | insnum (LE) | `<= 256`. |
| 36 | 2 | patnum (LE) | `<= 256`. |
| 38 | 2 | flags (LE) | reported. |
| 40 | 2 | created-with version (LE) | reported. |
| 42 | 2 | file format info (LE) | reported. |
| 44 | 4 | `SCRM` | ASCII magic. |
| 48 | 1 | global volume | reported. |
| 49 | 1 | initial speed | must be `>= 1`. |
| 50 | 1 | initial tempo | must be `>= 32`. |
| 51 | 1 | master volume | reported. |
| 52 | 1 | ultraclick | ignored. |
| 53 | 1 | default pan | ignored. |
| 54 | 8 | reserved | ignored. |
| 62 | 32 | channel settings | ignored. |
| 94 | ordnum | order table | raw bytes (255 end, 254 skip). |
| 94+ordnum | 2*insnum | instrument paragraph pointers | not resolved. |
| ... | 2*patnum | pattern paragraph pointers | see below. |

A nonzero pattern pointer `p` resolves to byte offset `p * 16`; the u16
packed length there includes the 2-byte header and must fit, and the u16 row
count at `offset + 2` must be 1..1024. A null pointer means an empty default
pattern (64 rows, packed size 0).

### Error catalog

| Error | Condition |
|---|---|
| `s3m: empty input` | zero-length buffer. |
| `s3m: truncated header` | `< 94` bytes. |
| `s3m: missing 0x1A marker` | byte 28 is not `0x1A`. |
| `s3m: bad file type` | byte 29 is not `0x10`. |
| `s3m: bad SCRM magic` | bytes 44..47 are not `SCRM`. |
| `s3m: bad order count` | ordnum 0 or `> 256`. |
| `s3m: bad table count` | insnum or patnum `> 256`. |
| `s3m: bad initial speed` | speed 0. |
| `s3m: bad initial tempo` | tempo `< 32`. |
| `s3m: truncated tables` | buffer smaller than `94 + ordnum + 2*insnum + 2*patnum`. |
| `s3m: bad pattern pointer` | pointer resolves out of range, packed length `< 2` or runs past the buffer. |
| `s3m: bad pattern rows` | row count 0 or `> 1024`. |

## IT (Impulse Tracker)

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 4 | `IMPM` | ASCII magic. |
| 4 | 26 | song name | text policy. |
| 30 | 2 | highlight | ignored. |
| 32 | 2 | ordnum (LE) | 1..256. |
| 34 | 2 | insnum (LE) | pointer table only. |
| 36 | 2 | smpnum (LE) | pointer table only. |
| 38 | 2 | patnum (LE) | pointer table only. |
| 40 | 2 | cwtv (LE) | reported. |
| 42 | 2 | cmwt (LE) | reported. |
| 44 | 2 | flags (LE) | reported. |
| 46 | 2 | special (LE) | reported. |
| 48 | 1 | global volume | `<= 128`. |
| 49 | 1 | mix volume | `<= 128`. |
| 50 | 1 | initial speed | `>= 1`. |
| 51 | 1 | initial tempo | `>= 32`. |
| 52 | 1 | pan separation | ignored. |
| 53 | 1 | pitch wheel depth | ignored. |
| 54 | 2 | message length (LE) | reported. |
| 56 | 4 | message offset (LE) | ignored. |
| 60 | 4 | reserved | ignored. |
| 64 | 64 | channel pan | ignored. |
| 128 | 64 | channel volume | ignored. |
| 192 | ordnum | order table | entries 254/255 pass; others must be `< patnum`. |
| 192+ordnum | 4*insnum | instrument offsets | not resolved. |
| ... | 4*smpnum | sample offsets | not resolved. |
| ... | 4*patnum | pattern offsets | see below. |

A nonzero pattern offset `p` must have 8 bytes available; the u32 length
there (header included) must fit, and the u16 row count at `p + 4` must be
1..1024. A null pointer means an empty default pattern (64 rows, packed size
0).

### Error catalog

| Error | Condition |
|---|---|
| `it: empty input` | zero-length buffer. |
| `it: truncated header` | `< 192` bytes. |
| `it: bad IMPM magic` | bytes 0..3 are not `IMPM`. |
| `it: bad order count` | ordnum 0 or `> 256`. |
| `it: bad global volume` | global volume `> 128`. |
| `it: bad mix volume` | mix volume `> 128`. |
| `it: bad initial speed` | speed 0. |
| `it: bad initial tempo` | tempo `< 32`. |
| `it: truncated tables` | buffer smaller than `192 + ordnum + 4*(insnum+smpnum+patnum)`. |
| `it: bad order entry` | entry is neither 254/255 nor `< patnum`. |
| `it: bad pattern pointer` | fewer than 8 bytes at the pointer, or declared length runs past the buffer. |
| `it: bad pattern rows` | row count 0 or `> 1024`. |

## NSF (NES Sound Format)

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 4 | `NESM` | ASCII magic. |
| 4 | 1 | `0x1A` marker | must match. |
| 5 | 1 | version | 1..2. |
| 6 | 1 | total songs | `>= 1`. |
| 7 | 1 | starting song | `< total songs`. |
| 8 | 2 | load address (LE) | reported. |
| 10 | 2 | init address (LE) | reported. |
| 12 | 2 | play address (LE) | reported. |
| 14 | 32 | song name | text policy. |
| 46 | 32 | artist | text policy. |
| 78 | 32 | copyright | text policy. |
| 110 | 2 | NTSC speed (LE) | reported. |
| 112 | 8 | bank-switch bytes | reported as 8 integers. |
| 120 | 2 | PAL speed (LE) | reported. |
| 122 | 1 | PAL/NTSC flag | reported. |
| 123 | 1 | chip flags | reported. |
| 124 | 4 | reserved | ignored. |
| 128 | ... | PRG payload | opaque; size reported as `data_size`. |

### Error catalog

| Error | Condition |
|---|---|
| `nsf: empty input` | zero-length buffer. |
| `nsf: truncated header` | `< 128` bytes. |
| `nsf: bad NESM magic` | magic mismatch or marker byte 4 is not `0x1A`. |
| `nsf: bad version` | version outside 1..2. |
| `nsf: zero songs` | total songs 0. |
| `nsf: bad starting song` | starting song `>=` total songs. |

## Chiptune registry

40 entries, tried in ascending index order; the first entry whose magic
appears at its declared offset wins. An entry matches only when the buffer
holds `offset + magic.len()` bytes. Out-of-range `chiptune_entry` queries
return an empty sentinel (id/extension/description `""`, offset 0, empty
magic) that never matches.

The table below is the exact registry (index, id, extension, magic at
offset, description). `+1A` denotes a trailing `0x1A` byte; `+FE` a trailing
`0xFE` byte (high bytes are pushed explicitly as integers, never through a
`Str` literal).

| # | id | ext | magic | off | description |
|---|---|---|---|---|---|
| 0 | nsf | nsf | `NESM`+1A | 0 | NES Sound Format |
| 1 | mod | mod | `M.K.` | 1080 | ProTracker 31-instrument module |
| 2 | xm | xm | `Extended Module: ` | 0 | FastTracker II module |
| 3 | s3m | s3m | `SCRM` | 44 | Scream Tracker 3 module |
| 4 | it | it | `IMPM` | 0 | Impulse Tracker module |
| 5 | mid | mid | `MThd` | 0 | Standard MIDI File |
| 6 | rmi | rmi | `RMID` | 8 | RIFF MIDI file |
| 7 | mus | mus | `MUS`+1A | 0 | Doom MUS sequence |
| 8 | cmf | cmf | `CTMF` | 0 | Creative Music Format |
| 9 | xmi | xmi | `XDIR` | 8 | Extended MIDI (FORM/XDIR) |
| 10 | hmp | hmp | `HMIMIDIP` | 0 | HMI MIDI file |
| 11 | sid | sid | `PSID` | 0 | PlaySID SID tune |
| 12 | rsid | sid | `RSID` | 0 | Real SID tune |
| 13 | gbs | gbs | `GBS` | 0 | Game Boy sound |
| 14 | spc | spc | `SNES-SPC700 Sound File Data` | 0 | SNES SPC700 dump |
| 15 | gym | gym | `GYMX` | 0 | Genesis GYM log |
| 16 | vgm | vgm | `Vgm ` | 0 | Video Game Music log |
| 17 | hes | hes | `HESM` | 0 | PC Engine HES |
| 18 | kss | kss | `KSS` | 0 | MSX KSS |
| 19 | sap | sap | `SAP` | 0 | Atari SAP |
| 20 | ay | ay | `ZXAYEMUL` | 0 | ZX Spectrum AY |
| 21 | stm | stm | `!Scream!` | 20 | Scream Tracker 2 module |
| 22 | mtm | mtm | `MTM` | 0 | MultiTracker module |
| 23 | far | far | `FAR`+FE | 0 | Farandole Composer module |
| 24 | ult | ult | `MAS_UTrack_V00` | 0 | UltraTracker module |
| 25 | 669 | 669 | `if` | 0 | Composer 669 module |
| 26 | dbm | dbm | `DBM0` | 0 | DigiBooster Pro module |
| 27 | mt2 | mt2 | `MT20` | 0 | MadTracker 2 module |
| 28 | rad | rad | `RAD by REALiTY!!` | 0 | Reality AdLib Tracker module |
| 29 | hvl | hvl | `HVL` | 0 | Hively Tracker module |
| 30 | ahx | ahx | `THX` | 0 | Abyss Highest eXperience tune |
| 31 | mptm | mptm | `MPTM` | 0 | OpenMPT module |
| 32 | okta | okt | `OKTA` | 1080 | Oktalyzer module |
| 33 | flt4 | mod | `FLT4` | 1080 | StarTrekker 4-channel module |
| 34 | 4chn | mod | `4CHN` | 1080 | 4-channel MOD |
| 35 | 6chn | mod | `6CHN` | 1080 | 6-channel MOD |
| 36 | 8chn | mod | `8CHN` | 1080 | 8-channel MOD |
| 37 | 16cn | mod | `16CN` | 1080 | 16-channel MOD |
| 38 | 32cn | mod | `32CN` | 1080 | 32-channel MOD |
| 39 | sc68 | sc68 | `SC68` | 0 | Atari SC68 tune |

Detection is magic-only metadata classification; it is not proof that the
rest of the file parses with the corresponding `*_parse` function.

## Complexity

All parsers are single-pass over the input: MIDI `O(data.len())` (each event
byte visited once), MOD `O(patterns * 64 * channels)`, XM/S3M/IT
`O(data.len())` (declared spans skipped, never scanned), NSF `O(1)` beyond
copying the 8 bank bytes, detection
`O(chiptune_count * max_magic_length)`.

## Test matrix

`tests/test_conformance.xi` (module `audio_meta_tests`) runs 25 checks with
inline fixtures only:

| # | Check |
|---|---|
| t1 | MIDI minimal format-0 header fields + SMPTE division |
| t2 | MIDI full event set aggregates (meta/channel/running/sysex) |
| t3 | MIDI varlen delta boundaries (0/127/128/16383/16384) |
| t4 | MIDI header errors: empty, short, magic, chunk length |
| t5 | MIDI event/stream errors (10 cases) |
| t6 | MOD 4-channel header and statistics |
| t7 | MOD 6-channel signature and pattern geometry |
| t8 | MOD error catalog |
| t9 | XM header fields |
| t10 | XM pattern/instrument geometry + sample walk |
| t11 | XM header error catalog |
| t12 | XM pattern/instrument error catalog |
| t13 | S3M header, orders and null patterns |
| t14 | S3M paragraph pattern pointer |
| t15 | S3M error catalog |
| t16 | IT header and null pattern |
| t17 | IT pattern pointer geometry |
| t18 | IT error catalog |
| t19 | NSF header fields |
| t20 | NSF error catalog |
| t21 | chiptune registry metadata and sentinels |
| t22 | chiptune registry full magic round-trip (all 40 entries) |
| t23 | chiptune detection on module headers |
| t24 | chiptune rejection and detect_id |
| t25 | per-format is_valid wrappers and cross-format rejection |
