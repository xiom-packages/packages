# xiom.spi

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) SPI transfer codec: modes (CPOL/CPHA),
> clock prescaler table, MSB/LSB-first bit order, 4..16-bit word sizes,
> active-low chip-select semantics, a full-duplex MOSI/MISO transfer model
> and an event/byte stream that encodes and decodes a transfer.
> **Deps:** `xiom.std` only. The library module imports nothing; the tests
> use `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
> `xiom.encoding.hex`.

## What it is

`xiom.spi` turns SPI transfer descriptions into a self-describing byte
stream and back. There is no I/O, no timing and no hidden state: the codec
only formats, validates and decodes bytes.

- **Modes** -- mode 0..3 with CPOL = mode / 2 and CPHA = mode % 2, plus the
  8-entry mode table and names;
- **Prescaler** -- a 16-entry divider table (2, 4, ... 65536), divider
  index lookup, resulting clock, and the smallest prescaler that keeps a
  bus at or below a target frequency;
- **Bit order** -- MSB-first (0) or LSB-first (1), used both by the stream
  and by the word extraction helper;
- **Word sizes** -- 4..16 bits; a transfer must contain a whole number of
  words over its continuous tx bit stream;
- **Chip select** -- an active-low line 0..7, or -1 for a 3-wire bus with
  no chip select; assert/deassert are explicit stream events;
- **Full duplex** -- every transfer carries a MOSI byte stream (`tx`) and a
  MISO byte stream (`rx`); `rx` is either empty (MISO not captured) or
  exactly as long as `tx`;
- **Event stream codec** -- `spi_encode`/`spi_decode` with a deterministic
  error catalog; decode errors carry the byte offset where decoding failed,
  encode errors carry offset -1 (the failure is in an input field).

The stream is a sequence of events, each starting with a 1-byte type:
CONFIG (mode, word size, bit order), CS_ASSERT, TX, RX, CS_DEASSERT, END.
All payloads are single bytes, so no endianness is involved anywhere.

## Install / use

```
xiom pkg install xiom.spi@0.1.0     # consumer
xiom pkg publish                    # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Quick start

```xi
use xiom.spi;
use xiom.io;
use xiom.encoding.hex;

// A tx-only transfer: mode 0, chip select 2, 8-bit MSB-first words.
let tx = ...;                            // Vec[UInt8]
let t = spi_transfer(0, 2, &tx);
if t.is_ok {
  let x: SpiTransfer = t.value;
  let e = spi_encode(&x);
  if e.is_ok {
    let stream: Vec[UInt8] = e.value;
    io.println(hex.hex_encode(&stream));
    // tx = de ad gives:
    // 01 00 08 00 02 02 04 de 04 ad 03 02 06
  }
}

// Decode any produced stream back into the full transfer.
let d = spi_decode(&stream_bytes);
if d.is_ok {
  let back: SpiTransfer = d.value;       // mode, cs, word size, bit order, tx, rx
}
```

Full configuration and a full-duplex capture:

```xi
let cfg = SpiConfig{ mode: 1; word_size: 12; bit_order: 1; };
let rx_seen = ...;                       // MISO bytes, same length as tx
let r = spi_transfer_new(&cfg, 3, &tx, &rx_seen);
if r.is_ok {
  let x: SpiTransfer = r.value;
  let words = spi_word_count(&x);        // number of 12-bit words
  let w0 = spi_word_at(&x, 0);           // first word value, LSB-first
}

// Clock plan: 16 MHz bus, at most 5 MHz -> prescaler index 1 (divider 4).
let idx = spi_prescaler_for(16000000, 5000000);   // 1
let hz = spi_clock_hz(16000000, idx);             // 4000000
```

## API

All functions are free functions in module `xiom.spi`. Every fallible
function returns `Result[T, SpiError]`; on `Err` nothing is produced.

### Modes, bit order, word size, chip select

| Function | Returns | Description |
|---|---|---|
| `spi_mode_valid(mode)` | `Bool` | True for 0..3. |
| `spi_cpol(mode)` / `spi_cpha(mode)` | `Int` | CPOL = mode/2, CPHA = mode%2; -1 when invalid. |
| `spi_mode_of(cpol, cpha)` | `Int` | `cpol*2 + cpha` for 0/1 inputs; -1 otherwise. |
| `spi_mode_name(mode)` | `Str` | `"CPOL=0 CPHA=0"` ... `"invalid mode"`. |
| `spi_mode_table()` | `Vec[Int]` | Always `[0,0, 0,1, 1,0, 1,1]`. |
| `spi_bit_order_valid(order)` | `Bool` | True for 0 (MSB-first) and 1 (LSB-first). |
| `spi_bit_order_name(order)` | `Str` | `"MSB-first"`, `"LSB-first"`, `"invalid"`. |
| `spi_word_size_valid(word_size)` | `Bool` | True for 4..16. |
| `spi_word_mask(word_size)` | `Int` | `2^word_size - 1`; -1 when invalid. |
| `spi_cs_valid(cs)` | `Bool` | True for -1 (none) and 0..7. |
| `spi_cs_name(cs)` | `Str` | `"none"`, `"cs0"`..`"cs7"`, `"invalid"`. |
| `spi_cs_line_level(cs, asserted)` | `Int` | 0 asserted / 1 idle (active-low); -1 for no line. |
| `spi_cs_assert_level()` / `spi_cs_idle_level()` | `Int` | 0 / 1. |

### Prescaler and clock

| Function | Returns | Description |
|---|---|---|
| `spi_prescaler_count()` | `Int` | 16. |
| `spi_prescaler_table()` | `Vec[Int]` | Index i -> 2^(i+1): 2 .. 65536. |
| `spi_clock_divider(index)` | `Int` | Table entry; -1 outside 0..15. |
| `spi_divider_index(divider)` | `Int` | Index of an exact power of two; -1 otherwise. |
| `spi_clock_hz(bus_hz, index)` | `Int` | `bus_hz / divider` (floor); -1 for bad input. |
| `spi_prescaler_for(bus_hz, max_hz)` | `Int` | Smallest index with clock <= max_hz; -1 if impossible. |

### Event stream codec

| Function | Returns | Description |
|---|---|---|
| `spi_event_name(event)` | `Str` | `"CONFIG"`, `"CS_ASSERT"`, `"CS_DEASSERT"`, `"TX"`, `"RX"`, `"END"`, `"unknown"`. |
| `spi_event_size(event)` | `Int` | 4, 2 or 1 bytes; -1 for unknown. |
| `spi_transfer(mode, cs, tx)` | `Result[SpiTransfer, SpiError]` | 8-bit MSB-first, tx-only convenience constructor. |
| `spi_transfer_new(cfg, cs, tx, rx)` | `Result[SpiTransfer, SpiError]` | Copies both streams; validates. |
| `spi_config_new(mode, word_size, bit_order)` | `Result[SpiConfig, SpiError]` | Validated config. |
| `spi_validate(t)` | `Result[Unit, SpiError]` | Full transfer validation. |
| `spi_encode(t)` | `Result[Vec[UInt8], SpiError]` | Transfer -> event stream. |
| `spi_decode(stream)` | `Result[SpiTransfer, SpiError]` | Event stream -> transfer, strict. |
| `spi_equal(a, b)` | `Bool` | Structural equality. |

### Accessors and word view

| Function | Returns | Description |
|---|---|---|
| `spi_transfer_mode(t)` / `spi_transfer_word_size(t)` / `spi_transfer_bit_order(t)` / `spi_transfer_cs(t)` | `Int` | Config fields. |
| `spi_tx_len(t)` / `spi_rx_len(t)` | `Int` | Byte stream lengths. |
| `spi_is_full_duplex(t)` | `Bool` | `tx.len() > 0` and `rx.len() == tx.len()`. |
| `spi_word_count(t)` | `Int` | `8 * tx.len() / word_size`; -1 when not whole. |
| `spi_word_at(t, index)` | `Int` | Word value in clock order; -1 out of range. |

### Types

```xi
pub type SpiConfig = { mode: Int; word_size: Int; bit_order: Int; }
pub type SpiTransfer = { config: SpiConfig; cs: Int; tx: Vec[UInt8]; rx: Vec[UInt8]; }
pub type SpiError = { offset: Int; message: Str; }
```

## Bit-level semantics

The tx bytes are one continuous MOSI bit sequence. MSB-first clocks bit 7
of each byte first; LSB-first clocks bit 0 first. The sequence is divided
into `word_size`-bit words; the first clocked bit of a word is its most
significant bit for MSB-first and its least significant bit for LSB-first.
For tx bytes `12 34`:

| View | MSB-first | LSB-first |
|---|---|---|
| four 4-bit words | 1, 2, 3, 4 | 2, 1, 4, 3 |
| one 16-bit word | 4660 (`0x1234`) | 13330 (`0x3412`) |

`rx[i]` is clocked during the same eight cycles as `tx[i]`; the stream
pairs them at byte granularity (RX event after its TX event).

## Error model

Every error is `SpiError{ offset; message }` with a stable lowercase
`spi:` message. Decode offsets point at the byte being read or the
offending field/event (a truncation points at the first missing byte, which
can equal `stream.len()`); validation/encode offsets are -1.

| Error text | Raised when |
|---|---|
| `spi: truncated stream` | Buffer ends before a needed byte (or before END). |
| `spi: missing config` | Stream does not start with the CONFIG event (0x01). |
| `spi: invalid mode` | Mode outside 0..3 (decode at offset 1). |
| `spi: invalid word size` | Word size outside 4..16 (decode at offset 2). |
| `spi: invalid bit order` | Bit order outside 0..1 (decode at offset 3). |
| `spi: invalid chip select` | `cs` outside -1..7 (encode) or CS line > 7 (decode). |
| `spi: length mismatch` | Non-empty rx with `rx.len() != tx.len()`, extra RX, or tx bits not a whole number of words. |
| `spi: unknown event` | Event type outside 0x01..0x06. |
| `spi: unexpected event` | Known event in an illegal position (second CONFIG/CS_ASSERT, data after CS_DEASSERT). |
| `spi: chip select not asserted` | CS_DEASSERT without a preceding CS_ASSERT. |
| `spi: chip select mismatch` | CS_DEASSERT line differs from the asserted line. |
| `spi: cs left asserted` | END while the chip-select line is still asserted. |
| `spi: trailing bytes` | Bytes after the END event. |

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.spi
```

Expected: the namespace check passes, 22 `[PASS]` lines, and a final
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`. See `SPEC.md` for
the byte-level format, the full error catalog and the test matrix.

## Limitations

- **No I/O, no FFI, no hardware.** Streams are in-memory `Vec[UInt8]`
  values; nothing here drives a bus.
- **No timing simulation.** CPOL/CPHA are validated and carried, not
  simulated edge by edge; the stream records bytes, not clock cycles.
- **No slave/peripheral model.** Master-side descriptors only.
- **No divider-1 bypass.** The finest prescaler is 2.
- **Byte-granular rx.** MISO is captured per byte; bit-level capture is out
  of scope.
- **One chip select per transfer.** No setup/hold timing, no active-high
  lines, no multi-line arbitration.
- **Strict decode.** Only canonical streams (as produced by `spi_encode`)
  are accepted; reordered events are `spi: unexpected event`.
- No FFI, no `extern "C"` blocks, no unsafe code.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
