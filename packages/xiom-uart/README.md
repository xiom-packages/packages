# xiom.uart

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM UART line codec: line configuration (baud, 5..9 data
> bits, none/even/odd/mark/space parity, 1/1.5/2 stop bits, flow control),
> frame bit layout (start bit, data LSB-first, parity, stop bits),
> one-byte encode/decode against a bit stream with idle-high framing,
> framing-error detection (false start, invalid bit value, parity mismatch,
> invalid stop, truncation), whole-stream codecs, baud divisor math with
> fractional-error computation and oversampling helpers.
> **Deps:** `xiom.std` only. The library module is dependency-free (no
> `use` at all); the tests use `xiom.test`, `xiom.io`, `xiom.string` and
> `xiom.string.compare` from it. No FFI.

## What it is

`xiom.uart` models one UART byte at the bit level. A line configuration
(`UartConfig`) describes the symbol rate, the data width, the parity mode,
the stop-bit length and the flow-control mode. A bit stream is a
`Vec[UInt8]` whose elements are one bit time each and hold a line level:
the idle line is high (1), a frame starts with the low start bit, carries
the data least significant bit first, then the parity bit when configured,
and ends with the high stop bits.

The package encodes one data value into its exact frame bits, decodes a
frame from any position in a stream, and moves whole streams
(`uart_encode_stream` / `uart_decode_stream`) with leading, trailing and
inter-frame idle handling. Framing errors are reported deterministically as
`Err(Str)` messages. The baud helpers compute integer divisors (truncating
and round-to-nearest) and the resulting line-rate error in parts per
million; the oversampling helpers give mid-bit sample ticks for 4x, 8x, 16x
and 32x sampling.

## Frame layout

One frame is `1 + data_bits + (parity ? 1 : 0) + stop_bit_times` bit
times; stop bits occupy `ceil(stop_half / 2)` whole mark elements in a bit
stream (1.5 stop bits is two mark elements there, while `uart_frame_halves`
counts the exact 21 half bit times of 8N1.5).

| Bit | Field | Encoding |
|---|---|---|
| 0 | start bit | always `0` |
| 1 .. data_bits | data | least significant bit first |
| data_bits + 1 | parity | `0`/`1` per mode; absent when parity is none |
| last | stop bits | always `1`; 1, 1.5 or 2 bit times |

| Parameter | Values |
|---|---|
| baud | positive bits per second |
| data_bits | 5, 6, 7, 8, 9 |
| parity | 0 none, 1 even, 2 odd, 3 mark, 4 space |
| stop_half | 2 = 1.0, 3 = 1.5, 4 = 2.0 stop bits |
| flow | 0 none, 1 rts_cts, 2 xon_xoff |

## API

| Function | Returns | Description |
|---|---|---|
| `uart_parity_none()` ... `uart_parity_space()` | `Int` | Parity parameter codes 0..4. |
| `uart_flow_none()` / `uart_flow_rts_cts()` / `uart_flow_xon_xoff()` | `Int` | Flow-control codes 0..2. |
| `uart_version()` | `Str` | Module version. |
| `uart_parity_name(p)` / `uart_flow_name(f)` / `uart_stop_name(s)` | `Str` | Human-readable names, "invalid" for unknown codes. |
| `uart_default()` | `UartConfig` | 115200 8N1, no flow control. |
| `uart_config_ok(c)` | `Result[Unit, Str]` | Field validation; `Ok(())` for a usable line. |
| `uart_new(baud, db, p, sh, flow)` | `Result[UartConfig, Str]` | Build and validate a configuration. |
| `uart_config_equal(a, b)` | `Bool` | Structural equality of all five fields. |
| `uart_has_parity(c)` | `Bool` | True when a parity bit is emitted. |
| `uart_stop_bit_times(sh)` | `Int` | Whole stop elements in a bit stream: 1, 2, 2. |
| `uart_frame_len(c)` | `Int` | Bit-stream elements in one frame (8N1 = 10). |
| `uart_frame_halves(c)` | `Int` | Exact frame duration in half bit times (8N1 = 20). |
| `uart_parity_bit(p, byte, db)` | `Int` | Parity bit value for a data value. |
| `uart_byte_ok(b)` | `Bool` | 0..511 (a 9-bit data value). |
| `uart_byte_fits(c, b)` | `Bool` | Value fits the configuration's data width. |
| `uart_encode_byte(c, b)` | `Result[Vec[UInt8], Str]` | One frame bit vector. |
| `uart_encode_byte_into(out, c, b)` | `Result[Unit, Str]` | Append a frame; `out` untouched on `Err`. |
| `uart_encode_stream(c, bytes)` | `Result[Vec[UInt8], Str]` | Idle + frames + idle for a `Vec[Int]` of values. |
| `uart_decode_byte(bits, c)` | `Result[Int, Str]` | Decode the frame at index 0 (extra bits ignored). |
| `uart_decode_byte_at(bits, c, pos)` | `Result[Int, Str]` | Decode the frame starting at `pos`. |
| `uart_decode_stream(bits, c)` | `Result[Vec[Int], Str]` | Decode every frame, skipping idle 1 bits. |
| `uart_bit_get(bits, i)` | `Int` | Stream element widened to 0..255, or -1 out of range. |
| `uart_bits_equal(a, b)` | `Bool` | Element-wise bit-stream equality. |
| `uart_idle_bit()` / `uart_idle_bits(n)` | `Int` / `Vec[UInt8]` | The idle level and `n` idle elements. |
| `uart_oversample_ok(n)` | `Bool` | Canonical factors 4, 8, 16, 32. |
| `uart_sample_offset(n)` | `Int` | Mid-bit offset within a bit period (8 for 16x), -1 when `n <= 0`. |
| `uart_bit_tick(bit, n)` / `uart_mid_tick(bit, n)` | `Int` | Start and mid-bit tick of a bit time. |
| `uart_tick_bit(tick, n)` | `Int` | Bit time a tick falls in, or -1 when invalid. |
| `uart_divisor(clock, baud, n)` | `Result[Int, Str]` | Truncating divisor `clock / (n * baud)`. |
| `uart_divisor_nearest(clock, baud, n)` | `Result[Int, Str]` | Round-to-nearest divisor. |
| `uart_baud_error_ppm(clock, baud, n)` | `Result[Int, Str]` | Fractional error of the nearest divisor, in ppm. |
| `uart_baud_ok(clock, baud, n, max_ppm)` | `Bool` | Absolute error within `max_ppm`. |

## Error model

Every failure is `Err(Str)` with a deterministic `uart: ` message; the full
catalog and the exact check order live in SPEC.md.

| Condition | Error text |
|---|---|
| `baud <= 0` | `uart: invalid baud` |
| `data_bits` outside 5..9 | `uart: invalid data bits` |
| `parity` outside 0..4 | `uart: invalid parity` |
| `stop_half` outside 2..4 | `uart: invalid stop bits` |
| `flow` outside 0..2 | `uart: invalid flow control` |
| Encode value below 0 | `uart: byte out of range` |
| Encode value above `2^data_bits - 1` | `uart: byte exceeds data bits` |
| Decode `pos < 0` | `uart: bad position` |
| Frame does not fit the stream | `uart: truncated frame` |
| Stream element above 1 | `uart: invalid bit value` |
| Start bit is 1 (or an idle 1 where a frame is decoded) | `uart: false start bit` |
| Received parity differs from the computed bit | `uart: parity mismatch` |
| Any stop bit is 0 | `uart: invalid stop bit` |
| `clock_hz <= 0` | `uart: invalid clock` |
| Oversampling factor not 4, 8, 16 or 32 | `uart: invalid oversampling` |
| `clock / (oversample * baud)` would be 0 | `uart: clock too slow` |

`uart_encode_byte_into` validates before writing, so an `Err` leaves `out`
exactly as it was. Decode checks truncation before bit values, and bit
values before the start bit, parity and stop bits.

## Usage

```xi
use xiom.uart;
use xiom.io;

// Decode a hand-built 8N1 'A' (0x41): start 0, data LSB-first, stop 1.
let line = uart_default();
var frame = Vec[UInt8].new();
frame.push(0 as UInt8);   // start bit
frame.push(1 as UInt8);   // data bit 0
frame.push(0 as UInt8);   // data bit 1
frame.push(0 as UInt8);
frame.push(0 as UInt8);
frame.push(0 as UInt8);
frame.push(0 as UInt8);
frame.push(1 as UInt8);   // data bit 6
frame.push(0 as UInt8);   // data bit 7
frame.push(1 as UInt8);   // stop bit
let d = uart_decode_byte(&frame, &line);
if d.is_ok {
  if d.value == 65 {
    io.println("decoded 0x41");
  }
}

// Baud math: 16 MHz / (16 * 115200) rounds to 9 with -35493 ppm error.
let div = uart_divisor_nearest(16000000, 115200, 16);
if div.is_ok {
  let ppm = uart_baud_error_ppm(16000000, 115200, 16);
  if ppm.is_ok {
    if ppm.value < 0 {
      io.println("divisor runs below the requested baud");
    }
  }
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.uart
```

Expected: the section-4 namespace check passes, 21 `[PASS]` lines, and a
final `port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Bit-level codec only.** The package never touches a UART controller, a
  port, a driver or a file; it converts between `UartConfig` values, bit
  streams and data values. Timing, interrupts, FIFOs and flow-control
  signaling are modeled as configuration fields, not performed.
- **1.5 stop bits in a whole-bit stream.** A stream element is one whole
  bit time, so a 1.5-stop frame occupies two mark elements; the exact
  duration (21 half bit times for 8N1.5) is reported by `uart_frame_halves`
  and the encoder/decoder are symmetric about the two-element
  representation. A real 1.5-stop receiver would only sample one full stop
  bit; accepting or truncating the half element is the driver's concern.
- **No break, idle-gap or error-flag modeling** beyond the documented
  framing errors; overrun, noise and break conditions are hardware signals
  and are not modeled.
- **Flow control is configuration only** (`none`, `rts_cts`, `xon_xoff`);
  no RTS/CTS lines are driven and no XON/XOFF characters are generated.
- `uart_encode_stream` writes exactly one leading and one trailing idle bit
  time; longer idle periods are the caller's to insert (they decode fine as
  leading, trailing or inter-frame idle).
- Values are not auto-truncated: a byte wider than `data_bits` is an error,
  not silently masked.
- Not thread-safe; `UartConfig` is a plain value type with no interior
  state.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
