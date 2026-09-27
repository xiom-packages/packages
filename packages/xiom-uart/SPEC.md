# xiom.uart -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.uart`, version `0.1.0`).
Module: `src/uart.xi` (`module xiom.uart`).
Depends on `xiom.std`; the library module imports nothing from it (tests add
`xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare`).

## Scope

A pure-XIOM (no FFI) bit-level codec for one UART byte:

- `UartConfig` -- line configuration: baud, data bits 5..9, parity
  none/even/odd/mark/space, stop bits 1/1.5/2, flow control
  none/rts_cts/xon_xoff;
- frame bit layout -- start bit, data LSB-first, parity bit, stop bits;
- `uart_encode_byte` / `uart_encode_byte_into` / `uart_encode_stream` --
  one byte to its exact frame bits, or a byte sequence to a whole stream
  with idle-high framing;
- `uart_decode_byte` / `uart_decode_byte_at` / `uart_decode_stream` --
  frame to byte from any stream position, or a whole stream to its values;
- framing-error detection -- false start, invalid bit value, parity
  mismatch, invalid stop, truncation, bad position;
- baud divisor math -- truncating and round-to-nearest divisors, line-rate
  error in ppm, an error threshold check;
- oversampling helpers -- canonical factors 4/8/16/32, mid-bit sample
  offset and tick conversions;
- bit-stream utilities -- element access, equality, idle construction;
- deterministic `Err(Str)` messages for every invalid input.

## Non-goals

- **Hardware I/O.** No controller, port, driver, interrupt, DMA or file
  access; the codec works on in-memory `Vec[UInt8]` bit streams.
- **Real-time behavior.** No symbol timing, no start-bit glitch filters, no
  framing by wall-clock time; everything is discrete bit times.
- **Flow-control signaling.** RTS/CTS and XON/XOFF are configuration codes
  only; no lines are driven and no control characters are generated.
- **Other serial formats** (IrDA, RS-485 multidrop addressing, LIN, 9-bit
  address-wakeup semantics).
- **Error flags beyond framing**: overrun, noise and break detection are
  hardware status bits and are not modeled.
- **Text or register dumps.** No hex formatting, no driver configuration
  strings.

## Bit stream model

A bit stream is a `Vec[UInt8]`; element `i` is the line level during bit
time `i`. Levels are 0 and 1; the idle line is high (1). A decoder reads a
fixed-size frame starting at a position:

- `uart_decode_byte(bits, c)` is `uart_decode_byte_at(bits, c, 0)`;
- elements after the frame are ignored, so a window may hold extra idle
  bits or the next frame;
- `uart_decode_stream` scans: leading and trailing 1 elements are idle and
  skipped, and every 0 element starts the next frame (stop bits keep the
  line high, so back-to-back frames need no idle gap).

### Frame layout

| Bit index | Field | Value |
|---|---|---|
| 0 | start bit | `0` |
| 1 .. `data_bits` | data | LSB first; bit `i` of the value at index `1 + i` |
| `data_bits + 1` | parity bit | present iff `parity != 0` |
| last `n` | stop bits | `1` repeated `n = ceil(stop_half / 2)` times |

`stop_half` is stop bits in half bit times: 2 = 1.0, 3 = 1.5, 4 = 2.0. A
bit-stream element is a whole bit time, so `n` is 1 for 1.0 and 2 for both
1.5 and 2.0 stop bits; `uart_frame_halves` reports the exact duration
(`2 * (1 + data_bits + parity) + stop_half`), which is 21 for 8N1.5 versus
22 for 8N2. The encoder and decoder agree on the two-element
representation, so 8N1.5 and 8N2 frames are byte-for-byte identical in a
stream; only the duration helper distinguishes them.

Frame length in stream elements:

| Configuration | `uart_frame_len` | `uart_frame_halves` |
|---|---|---|
| 8N1 | 10 | 20 |
| 8E1 / 8O1 / 8M1 / 8S1 | 11 | 22 |
| 8N1.5 | 11 | 21 |
| 8N2 | 11 | 22 |
| 5N1 | 7 | 14 |
| 7E2 | 11 | 22 |
| 9E2 | 13 | 26 |

### Parity

| Code | Name | Parity bit |
|---|---|---|
| 0 | none | no bit is emitted |
| 1 | even | 1 when the data has an odd number of 1 bits |
| 2 | odd | complement of even |
| 3 | mark | always 1 |
| 4 | space | always 0 |

`uart_parity_bit(parity, byte, data_bits)` considers the low `data_bits`
bits of `byte` (masked with a modulo, not a bitwise AND) and returns the
parity value for every mode; an unknown parity code behaves like none (0)
and never errors.

## Configuration model

```xi
pub type UartConfig = {
  baud: Int;       // > 0
  data_bits: Int;  // 5..9
  parity: Int;     // 0..4
  stop_half: Int;  // 2, 3, 4
  flow: Int;       // 0..2
}
```

`uart_default()` is 115200 8N1 with no flow control.

## API contract

All functions are free functions in module `xiom.uart` (no self methods):

```xi
pub type UartConfig = {
  baud: Int;
  data_bits: Int;
  parity: Int;
  stop_half: Int;
  flow: Int;
}

pub fn uart_parity_none() -> Int
pub fn uart_parity_even() -> Int
pub fn uart_parity_odd() -> Int
pub fn uart_parity_mark() -> Int
pub fn uart_parity_space() -> Int
pub fn uart_flow_none() -> Int
pub fn uart_flow_rts_cts() -> Int
pub fn uart_flow_xon_xoff() -> Int
pub fn uart_version() -> Str
pub fn uart_parity_name(parity: Int) -> Str
pub fn uart_flow_name(flow: Int) -> Str
pub fn uart_stop_name(stop_half: Int) -> Str
pub fn uart_default() -> UartConfig
pub fn uart_config_equal(a: &UartConfig, b: &UartConfig) -> Bool
pub fn uart_config_ok(c: &UartConfig) -> Result[Unit, Str]
pub fn uart_new(baud: Int, data_bits: Int, parity: Int, stop_half: Int, flow: Int) -> Result[UartConfig, Str]
pub fn uart_has_parity(c: &UartConfig) -> Bool
pub fn uart_stop_bit_times(stop_half: Int) -> Int
pub fn uart_frame_len(c: &UartConfig) -> Int
pub fn uart_frame_halves(c: &UartConfig) -> Int
pub fn uart_parity_bit(parity: Int, byte: Int, data_bits: Int) -> Int
pub fn uart_byte_ok(byte: Int) -> Bool
pub fn uart_byte_fits(c: &UartConfig, byte: Int) -> Bool
pub fn uart_encode_byte_into(out: &mut Vec[UInt8], c: &UartConfig, byte: Int) -> Result[Unit, Str]
pub fn uart_encode_byte(c: &UartConfig, byte: Int) -> Result[Vec[UInt8], Str]
pub fn uart_encode_stream(c: &UartConfig, bytes: &Vec[Int]) -> Result[Vec[UInt8], Str]
pub fn uart_decode_byte_at(bits: &Vec[UInt8], c: &UartConfig, pos: Int) -> Result[Int, Str]
pub fn uart_decode_byte(bits: &Vec[UInt8], c: &UartConfig) -> Result[Int, Str]
pub fn uart_decode_stream(bits: &Vec[UInt8], c: &UartConfig) -> Result[Vec[Int], Str]
pub fn uart_bit_get(bits: &Vec[UInt8], i: Int) -> Int
pub fn uart_bits_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool
pub fn uart_idle_bit() -> Int
pub fn uart_idle_bits(count: Int) -> Vec[UInt8]
pub fn uart_oversample_ok(oversample: Int) -> Bool
pub fn uart_sample_offset(oversample: Int) -> Int
pub fn uart_bit_tick(bit: Int, oversample: Int) -> Int
pub fn uart_mid_tick(bit: Int, oversample: Int) -> Int
pub fn uart_tick_bit(tick: Int, oversample: Int) -> Int
pub fn uart_divisor(clock_hz: Int, baud: Int, oversample: Int) -> Result[Int, Str]
pub fn uart_divisor_nearest(clock_hz: Int, baud: Int, oversample: Int) -> Result[Int, Str]
pub fn uart_baud_error_ppm(clock_hz: Int, baud: Int, oversample: Int) -> Result[Int, Str]
pub fn uart_baud_ok(clock_hz: Int, baud: Int, oversample: Int, max_ppm: Int) -> Bool
```

### Notes per function

`uart_stop_bit_times(stop_half)`
: `(stop_half + 1) / 2`: 1 for 1.0, 2 for both 1.5 and 2.0. Half bit times
  cannot appear in a whole-bit stream; `uart_frame_halves` keeps the exact
  count.

`uart_frame_len(c)`
: `1 + data_bits + (parity != 0 ? 1 : 0) + uart_stop_bit_times(stop_half)`.

`uart_frame_halves(c)`
: `2 * (1 + data_bits + (parity != 0 ? 1 : 0)) + stop_half`.

`uart_byte_ok(byte)`
: `0 <= byte <= 511` (the widest value a 9-data-bit frame carries).

`uart_byte_fits(c, byte)`
: `uart_byte_ok(byte)` and `byte <= 2^data_bits - 1`. Meaningful for a
  valid configuration.

`uart_encode_byte_into(out, c, byte)`
: Validates `c` with `uart_config_ok`, then the byte: `byte < 0` is
  `uart: byte out of range`, `byte > 2^data_bits - 1` is `uart: byte
  exceeds data bits`. On success appends the frame: `0`, data LSB-first,
  the parity bit when configured, then `uart_stop_bit_times` mark elements.
  On `Err`, `out` is byte-for-byte unchanged (atomic failure).

`uart_encode_byte(c, byte)`
: `uart_encode_byte_into` into a fresh vector; the result has
  `uart_frame_len(c)` elements.

`uart_encode_stream(c, bytes)`
: Validates `c` and every value first (same catalog), then writes exactly
  one idle-high element, one frame per value back to back, and one
  idle-high element. An empty sequence encodes to two idle elements.

`uart_decode_byte_at(bits, c, pos)`
: Decodes the frame starting at `pos`, ignoring elements after it. Values
  are returned in `0 .. 2^data_bits - 1`.

`uart_decode_stream(bits, c)`
: Skips idle 1 elements, decodes a frame at every 0 element, and skips
  trailing idle; returns the values in order. Every 0 element must start a
  complete valid frame.

`uart_bit_get(bits, i)`
: Widened element value, or -1 when `i < 0` or `i >= bits.len()`.

`uart_oversample_ok(oversample)`
: True exactly for 4, 8, 16 and 32.

`uart_sample_offset(oversample)`
: `oversample / 2` (mid-bit sample point; 8 at the standard 16x), or -1
  when `oversample <= 0`.

`uart_bit_tick(bit, oversample)` / `uart_mid_tick(bit, oversample)`
: `bit * oversample` and `bit * oversample + uart_sample_offset(...)`.

`uart_tick_bit(tick, oversample)`
: `tick / oversample` truncated, or -1 when `tick < 0` or
  `oversample <= 0`.

`uart_divisor(clock_hz, baud, oversample)`
: `clock_hz / (oversample * baud)` truncated; the resulting line rate is
  at or above `baud`.

`uart_divisor_nearest(clock_hz, baud, oversample)`
: `(clock_hz + den / 2) / den` with `den = oversample * baud`; this is the
  divisor with the smallest rate error.

`uart_baud_error_ppm(clock_hz, baud, oversample)`
: `(clock_hz - baud * oversample * d) * 1000000 / (baud * oversample * d)`
  with `d` the nearest divisor, truncated toward zero: positive when the
  divisor runs fast, negative when it runs slow. For
  `uart_divisor` (truncating) the error is never negative.

`uart_baud_ok(clock_hz, baud, oversample, max_ppm)`
: `|uart_baud_error_ppm(...)| <= max_ppm`; false for invalid inputs or
  `max_ppm < 0`.

## Validation and decode order

`uart_config_ok` (and every constructor/encoder that validates first)
checks in exactly this order and reports the first failure:

1. `baud <= 0` -> `uart: invalid baud`;
2. `data_bits < 5 || data_bits > 9` -> `uart: invalid data bits`;
3. `parity < 0 || parity > 4` -> `uart: invalid parity`;
4. `stop_half < 2 || stop_half > 4` -> `uart: invalid stop bits`;
5. `flow < 0 || flow > 2` -> `uart: invalid flow control`.

`uart_encode_byte_into` continues after the configuration with:

6. `byte < 0` -> `uart: byte out of range`;
7. `byte > 2^data_bits - 1` -> `uart: byte exceeds data bits`.

`uart_decode_byte_at` checks in exactly this order:

1. configuration (above);
2. `pos < 0` -> `uart: bad position`;
3. `pos + uart_frame_len(c) > bits.len()` -> `uart: truncated frame`;
4. any frame element above 1 -> `uart: invalid bit value`;
5. start bit not 0 -> `uart: false start bit`;
6. parity mode with received bit != `uart_parity_bit(...)` -> `uart: parity mismatch` (mark and space are compared like any computed bit);
7. any stop element not 1 -> `uart: invalid stop bit`.

`uart_decode_stream` checks the configuration, then scans: an element
above 1 anywhere (including idle positions) is `uart: invalid bit value`,
otherwise each 0 element is decoded with the order above.

## Error string catalog

| Condition | Error text |
|---|---|
| `baud <= 0` | `uart: invalid baud` |
| `data_bits` outside 5..9 | `uart: invalid data bits` |
| `parity` outside 0..4 | `uart: invalid parity` |
| `stop_half` outside 2..4 | `uart: invalid stop bits` |
| `flow` outside 0..2 | `uart: invalid flow control` |
| encode value `< 0` | `uart: byte out of range` |
| encode value `> 2^data_bits - 1` | `uart: byte exceeds data bits` |
| decode `pos < 0` | `uart: bad position` |
| frame beyond the end of the stream | `uart: truncated frame` |
| stream element above 1 | `uart: invalid bit value` |
| start element not 0 | `uart: false start bit` |
| received parity bit differs | `uart: parity mismatch` |
| stop element not 1 | `uart: invalid stop bit` |
| `clock_hz <= 0` | `uart: invalid clock` |
| `baud <= 0` in a baud function | `uart: invalid baud` |
| oversampling not 4/8/16/32 | `uart: invalid oversampling` |
| divisor would be 0 | `uart: clock too slow` |

Functions without an error channel: the code/name helpers,
`uart_default`, `uart_config_equal`, `uart_has_parity`,
`uart_stop_bit_times`, `uart_frame_len`, `uart_frame_halves`,
`uart_parity_bit`, `uart_byte_ok`, `uart_byte_fits`, `uart_bit_get`,
`uart_bits_equal`, the idle helpers, the oversampling helpers and
`uart_baud_ok` (which reports invalid input as `false`).

## Complexity

| Operation | Complexity |
|---|---|
| code/name helpers, `uart_default`, `uart_config_equal`, `uart_config_ok`, `uart_new` | O(1) |
| `uart_has_parity`, `uart_stop_bit_times`, `uart_frame_len`, `uart_frame_halves` | O(1) |
| `uart_parity_bit`, `uart_byte_ok`, `uart_byte_fits` | O(data_bits) / O(1) |
| `uart_encode_byte_into`, `uart_encode_byte`, `uart_decode_byte_at`, `uart_decode_byte` | O(data_bits) |
| `uart_encode_stream`, `uart_decode_stream` | O(bytes.len() * data_bits) / O(bits.len()) |
| `uart_bit_get`, `uart_idle_bit`, the oversampling helpers, the baud helpers | O(1) |
| `uart_bits_equal`, `uart_idle_bits` | O(length) / O(count) |

## Test plan

`tests/test_conformance.xi` (`module uart_tests`, 21 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Synthetic bit streams are built in-test from
digit strings. Coverage:

1. parameter codes, names and version pinned;
2. `uart_default` and `uart_new` build the pinned configurations;
3. configuration errors reported in the documented order;
4. frame length and half-time geometry pinned (8N1, 8E1, 8N1.5, 8N2,
   5N1, 9E2);
5. parity bits follow the even/odd/mark/space rules, including 7- and
   9-bit masking;
6. 8N1 frames pinned: start bit, data LSB-first, one stop bit;
7. parity, stop-bit, 5/7/9 data-bit layouts pinned;
8. byte range and configuration errors pinned, `uart_byte_ok` /
   `uart_byte_fits`;
9. `uart_encode_byte_into` appends exactly and is atomic on `Err`;
10. decode extracts the byte, ignores bits after the frame, decodes at a
    non-zero position;
11. framing errors: truncation (frame, empty, past-end, lone start),
    false start, invalid bit value (data and stop positions), bad
    position, configuration error;
12. parity mismatch and invalid stop bits detected (even, 2-stop, mark,
    space);
13. 9-bit and 5-bit data values decode exactly;
14. encode -> decode round-trips every value for nine configurations
    (about 2,200 values);
15. stream encode pins idle + two frames + idle and decodes back;
16. a 256-value stream round-trips through encode_stream/decode_stream;
17. stream codecs validate every frame and report the first error;
18. idle-only and back-to-back streams decode; an empty sequence encodes
    to idle;
19. bit accessors, idle helpers and bit equality pinned;
20. oversampling factors and sample ticks pinned;
21. baud divisors, ppm error and `uart_baud_ok` pinned, including every
    baud error path.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.uart
```

Last verified: compiler 0.61.3,
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Bit-level codec only: no hardware, no timing, no flow-control signaling.
- 1.5 and 2.0 stop bits are byte-identical in a whole-bit stream; the
  exact duration is available from `uart_frame_halves`.
- No break, overrun or noise modeling.
- `uart_encode_stream` writes one leading and one trailing idle element;
  longer idle periods are the caller's to insert.
- Values are not silently truncated to `data_bits`; a too-wide value is an
  error.
- `uart_decode_stream` requires each 0 element to begin a complete valid
  frame; a glitch 0 with no room for a frame is `uart: truncated frame`.
- `UartConfig` is a plain value type; the module is not thread-safe.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers `_ok_*` /
  `_err_*` (constructing Results directly inside other functions
  miscompiles in this compiler).
- Every `Vec[UInt8]` element read is widened with `(x as Int) & 0xFF` and
  bound to a typed local before use.
- `&struct.field` is never passed directly to a `&Vec[...]` parameter (it
  lowers to an empty vector); a field is bound to a local first.
- Bit indexing is done with `_pow2` multiplication and modulo/division
  rather than shifts; the only bitwise operation in the module is the
  documented `& 0xFF` widening mask.
- Str values in the tests are compared through
  `xiom.string.compare.str_compare` (BUG 17: `==` on a Str read from a
  `Vec` lowers to a pointer comparison).
- The package declares no `extern "C"` blocks (no FFI).
