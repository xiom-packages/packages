# xiom.netstring -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.netstring`, version `0.1.0`).
Module: `src/netstring.xi` (`module xiom.netstring`).
Depends on `xiom.std`; the library module imports nothing from it (the tests
add `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare`,
`xiom.encoding.hex`).

## Scope

A pure-XIOM (no FFI) codec for DJB netstrings over in-memory `Vec[UInt8]`
buffers:

- `netstring_parse` walks a buffer of concatenated frames until it ends and
  returns a `NetstringList` index (absolute payload offset/length per frame,
  stored in parallel `Vec[Int]` fields);
- `netstring_append` / `netstring_build` write frames with computed decimal
  lengths;
- `netstring_count` / `netstring_offset` / `netstring_length` /
  `netstring_payload` read the index back;
- `netstring_digit_count` / `netstring_frame_size` report the encoded size
  of a frame with a given payload length;
- a pull cursor (`netstring_cursor_*`) consumes a buffer frame by frame for
  streaming-style callers;
- deterministic `Err(Str)` messages for malformed input and invalid access.

## Non-goals

- Sockets, files, pipes or any OS I/O: everything is an in-memory
  `Vec[UInt8]`.
- Escaping, quoting, framing into text, UTF-8 validation or any payload
  interpretation: netstring payloads are raw opaque bytes.
- Nesting: a payload that is itself a netstring stream is the caller's
  responsibility to re-parse.
- Push/callback streaming and partial-frame assembly: the cursor is a pull
  iterator over a complete buffer; it reports where a truncated tail starts
  but does not buffer bytes for the caller.
- Separator-free, newline-terminated, padded or checksummed variants; only
  the comma-terminated canonical form is implemented.
- Arbitrary-precision lengths: the declared length must fit the signed
  64-bit platform `Int`.
- Random access without parsing: `netstring_parse` scans the whole buffer.

## Grammar

```
stream      := frame*                       ; concatenated, no separator
frame       := length ":" payload ","
length      := "0" | ( %x31-39 *digit )     ; no leading zero unless "0"
digit       := %x30-39
payload     := OCTET{n}                     ; n = decimal value of length
```

Byte-level rules:

- The length field is one or more ASCII decimal digits. `"0"` is valid and
  denotes an empty payload; any other run starting with `"0"` is rejected
  (`"00:"`, `"01:"`).
- No sign (`+3:...`), no whitespace (`" 3:..."`, `"3 :..."`) and no other
  separator between the digits and the colon.
- The colon is mandatory; a digit run that reaches the end of the buffer is
  `missing colon`.
- The declared length counts payload bytes exactly. The payload may contain
  any byte value, including `:` (0x3A), `,` (0x2C), NUL (0x00) and bytes
  above 0x7F.
- The comma is mandatory after the payload, including for empty payloads:
  `"0:,"` is one frame, `"0:"` is an error.
- Parsing stops exactly when the buffer ends. An empty buffer is a valid
  stream of zero frames; any leftover bytes that cannot form a frame are an
  error, never silently ignored.

Frames in a stream: `"3:abc,0:,11:hello world,"` is three frames with
payloads `"abc"`, `""` and `"hello world"`, at payload offsets 2, 7 and 12.

## API signatures

All functions are free functions in module `xiom.netstring` (no self
methods):

```xi
pub type NetstringList = {
  payload_offsets: Vec[Int];
  payload_lengths: Vec[Int];
}

pub type NetstringCursor = {
  pos: Int;
  index: Int;
  payload_offset: Int;
  payload_length: Int;
}

pub fn netstring_parse(data: &Vec[UInt8]) -> Result[NetstringList, Str]
pub fn netstring_count(l: &NetstringList) -> Int
pub fn netstring_offset(l: &NetstringList, i: Int) -> Int
pub fn netstring_length(l: &NetstringList, i: Int) -> Int
pub fn netstring_payload(data: &Vec[UInt8], l: &NetstringList, i: Int) -> Result[Vec[UInt8], Str]

pub fn netstring_append(out: &mut Vec[UInt8], payload: &Vec[UInt8])
pub fn netstring_build(payloads: &Vec[Vec[UInt8]]) -> Vec[UInt8]
pub fn netstring_digit_count(n: Int) -> Int
pub fn netstring_frame_size(payload_len: Int) -> Int

pub fn netstring_cursor_new() -> NetstringCursor
pub fn netstring_cursor_next(data: &Vec[UInt8], c: &mut NetstringCursor) -> Result[Int, Str]
pub fn netstring_cursor_position(c: &NetstringCursor) -> Int
pub fn netstring_cursor_index(c: &NetstringCursor) -> Int
pub fn netstring_cursor_payload_offset(c: &NetstringCursor) -> Int
pub fn netstring_cursor_payload_length(c: &NetstringCursor) -> Int
```

## Semantics

`netstring_parse(data)`
: Walks frames from offset 0. An empty buffer yields `Ok` with zero frames.
  On `Err` nothing is returned (no partial list). Offsets are absolute
  indices into `data`; an empty payload is valid and has an offset pointing
  at its (empty) span, immediately after the colon.

`netstring_count(l)`
: Number of frames; `0` for an empty list.

`netstring_offset(l, i)` / `netstring_length(l, i)`
: `-1` when `i < 0` or `i >= netstring_count(l)`; no error channel.

`netstring_payload(data, l, i)`
: `Err("netstring: index out of range")` for a bad `i`; otherwise the
  recorded span is bounds-checked against `data` (`offset < 0`,
  `length < 0`, `offset > data.len()`, or `length > data.len() - offset`
  are all rejected) and the bytes are copied into a fresh vector. The check
  is overflow-safe: it never computes `offset + length` before comparing.

`netstring_append(out, payload)`
: Appends the decimal length, `:`, the payload bytes and `,`. Infallible:
  every `Vec` length has a decimal form and no validation can fail, so
  there is no `Result` and no error message on the build side. Appending to
  a non-empty buffer concatenates frames.

`netstring_build(payloads)`
: Calls `netstring_append` for every vector in order; an empty input yields
  an empty vector. Equivalent to appending each payload by hand.

`netstring_digit_count(n)`
: `1` for `0..9`, `2` for `10..99`, and so on; `-1` when `n < 0`.

`netstring_frame_size(payload_len)`
: `netstring_digit_count(payload_len) + 2 + payload_len` (digit digits,
  colon, payload, comma); `-1` when `payload_len < 0`.

`netstring_cursor_new()`
: `{ pos: 0, index: 0, payload_offset: -1, payload_length: -1 }`.

`netstring_cursor_next(data, c)`
: Parses one frame at `c.pos` using the same rules as `netstring_parse`.
  On success it sets `payload_offset`/`payload_length` to that frame's
  payload span, advances `pos` to the byte after the trailing comma,
  increments `index`, and returns `Ok(i)` where `i` is the 0-based index of
  the frame just consumed (`0, 1, 2, ...`). When `pos >= data.len()` (or
  `pos < 0`, treated as exhausted) it returns `Ok(-1)` and leaves the cursor
  unchanged. On `Err` the cursor is completely unchanged (atomic failure),
  so a consumer that hit a truncated tail can retry the same frame after
  more bytes arrive. The error message is one of the six parse-catalog
  strings.

`NetstringCursor.pos` after a successful `next` is the start of the next
frame and equals `data.len()` when the buffer is fully consumed; it marks
where an incomplete tail begins. The cursor stores no reference to `data`;
the same buffer must be passed to every `next` call (or one holding at
least up to `pos`).

## Error string catalog

Parse errors, produced by `netstring_parse` and `netstring_cursor_next`:

| # | Condition | Error text |
|---|---|---|
| 1 | Frame start is neither an ASCII digit nor `':'` | `netstring: trailing garbage` |
| 2 | Zero length digits (a `':'` where the length starts) | `netstring: bad length digits` |
| 3 | Leading zero followed by another digit (`00:`, `01:`) | `netstring: bad length digits` |
| 4 | Digit run followed by a byte other than `':'` | `netstring: bad length digits` |
| 5 | Length value above `INT64_MAX` | `netstring: length overflow` |
| 6 | Digit run reaches the end of the buffer | `netstring: missing colon` |
| 7 | Declared length exceeds the remaining bytes after `':'` | `netstring: payload too short` |
| 8 | The buffer ends after the payload, or the byte at `payload_start + length` is not `','` | `netstring: missing comma` |

Check order is strict and deterministic; the first failing condition wins:

1. frame start: non-digit and not `':'` -> rule 1;
2. scan the whole digit run, tracking `digits`, leading zero and overflow;
   `digits == 0` -> rule 2; leading zero with `digits > 1` -> rule 3;
   overflow -> rule 5;
3. digit run at buffer end -> rule 6; otherwise the next byte must be `':'`
   or rule 4 applies;
4. remaining bytes after `':'` shorter than the declared length -> rule 7;
5. byte at `payload_start + length` missing or not `','` -> rule 8.

Overflow is detected while the digit run is scanned (with the standard
`n > (INT64_MAX - d) / 10` test) and reported before any colon/comma check,
so a 20-digit length is `length overflow` whether or not a colon follows.
`INT64_MAX` itself does not overflow; a frame declaring `INT64_MAX` bytes
fails later as `payload too short`.

Access errors, produced by `netstring_payload`:

| Condition | Error text |
|---|---|
| `i < 0` or `i >= netstring_count(l)` | `netstring: index out of range` |
| Recorded span negative or beyond `data.len()` | `netstring: payload out of bounds` |

`netstring_append`, `netstring_build`, `netstring_digit_count`,
`netstring_frame_size`, the cursor constructor/accessors and
`netstring_offset`/`netstring_length` never fail: they either produce a
value or report `-1` (for negative sizes and out-of-range indices).

## Complexity

| Operation | Complexity |
|---|---|
| `netstring_parse` | O(data.len()) |
| `netstring_count` / `netstring_offset` / `netstring_length` | O(1) |
| `netstring_payload` | O(payload length) |
| `netstring_append` / `netstring_build` | O(payload bytes) |
| `netstring_digit_count` / `netstring_frame_size` | O(digits) |
| `netstring_cursor_next` | O(frame length) |
| cursor accessors | O(1) |

## Test plan

`tests/test_conformance.xi` (`module netstring_tests`, 21 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. empty buffer parses to zero frames; accessors and `netstring_payload`
   report out of range;
2. empty frame `0:,` pins payload offset 2 and length 0;
3. simple frame `5:hello,` parses with an exact payload slice;
4. raw payload bytes: `:` and `,` inside the payload, plus high bytes
   (`00 ff 80`);
5. multi-frame stream `3:abc,0:,11:hello world,` pins all three offsets
   (2/8/12) and lengths (3/0/11);
6. `netstring_append` writes exact bytes with computed lengths, including
   the 9-digit/1-digit and 10-digit/2-digit cases;
7. `netstring_build` equals per-frame appends and parses back (payloads
   including high bytes and an empty one);
8. `netstring_digit_count` and `netstring_frame_size` tables
   (0/9/10/99/100/999/1000/10^9, negative -> -1);
9. 9-byte and 10-byte payloads parse with 1- and 2-digit length fields;
10. `bad length digits`: empty digit run, `01:`, `00:`, digit run followed
    by a non-colon byte, and the same after a valid frame;
11. `trailing garbage`: `x:`, a stray comma, a leading space, `+3:`, and
    junk after a valid frame;
12. `missing colon`: digit runs that reach the buffer end, including
    `INT64_MAX` as digits;
13. `payload too short`: declared lengths beyond the remaining bytes,
    including `INT64_MAX:`;
14. `missing comma`: end of buffer after the payload, wrong byte at the
    comma position, empty payload without comma;
15. `length overflow`: 20-digit length, `INT64_MAX + 1`, an over-long run
    without a colon, and `2^64`;
16. cursor order and exhaustion: indices 0/1/2, payload offsets/lengths,
    positions 6/9/17, `Ok(-1)` at the end with the cursor unchanged;
17. cursor error atomicity: `payload too short` mid-stream and
    `trailing garbage` at the start leave `pos`/`index`/payload accessors
    unchanged;
18. cursor resumability: a truncated second frame errors, then a cursor
    rebuilt at the recorded position consumes the frame once the buffer
    holds the full `4:defg,`;
19. a 300-byte payload (full 0..255 pattern) round-trips with a 3-digit
    length; `netstring_frame_size(300) == 305`;
20. exact payload slices for two frames; bad index and a short source
    buffer are the two documented `netstring_payload` errors;
21. parse -> rebuild reproduces the original 24 bytes exactly.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.netstring
```

Last verified: compiler 0.61.3,
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Known limitations

- In-memory `Vec[UInt8]` only: no sockets, files, pipes or incremental
  buffer assembly. The cursor reports the incomplete-tail offset but does
  not retain bytes.
- Raw payload bytes only: no escaping/quoting, no UTF-8 validation, no
  nesting, no checksum/compression.
- Strict canonical framing: no leading zeros, mandatory colon and comma,
  no padding, no alternate delimiters.
- The declared length is bounded by the signed 64-bit `Int`; larger lengths
  are `length overflow`.
- `NetstringList` stores offsets into the parse buffer;
  `netstring_payload` requires a buffer that still holds the recorded span.
- The cursor is a plain value: copying it copies the position, and it holds
  no reference to the data.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_list`/`_err_list`/`_ok_bytes`/`_err_bytes`/`_ok_int`/`_err_int`/
  `_ok_frame`/`_err_frame` (constructing Results directly in other
  functions miscompiles in this compiler).
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF` before
  entering Int arithmetic or comparisons; no `UInt8` value is compared as a
  signed byte.
- The length accumulator uses the same overflow test as
  `xiom.bencode`'s string parser: it never computes `n * 10 + d` before
  proving it fits.
- `netstring_payload` bounds-checks with `len > data.len() - off` (after
  checking `off > data.len()`), so no addition can overflow.
- Str values in the tests are compared through
  `xiom.string.compare.str_compare` (BUG 17: `==` on a Str read from a
  `Vec` lowers to a pointer comparison).
- The package declares no `extern "C"` blocks (no FFI).
