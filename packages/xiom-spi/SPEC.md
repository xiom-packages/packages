# xiom.spi -- Specification

Version: 0.1.3 (stable; published on the XIOM registry).
Module: `src/spi.xi` (`module xiom.spi`).
Depends on `xiom.std`; the library module imports nothing (the tests import
`xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
`xiom.encoding.hex`).

## Scope

A pure-XIOM (no FFI) SPI (Serial Peripheral Interface) transfer codec for a
documented subset:

- the four SPI modes 0..3 (CPOL = mode / 2, CPHA = mode % 2) with a mode
  table and names;
- a 16-entry clock prescaler table (dividers 2..65536), divider index
  lookup, resulting clock and "smallest prescaler within a frequency
  budget";
- MSB-first / LSB-first bit order, applied both to the stream and to word
  extraction;
- word sizes 4..16 bits; a transfer must contain a whole number of words
  over the continuous tx bit stream;
- active-low chip-select semantics for lines 0..7, or -1 for a 3-wire bus
  with no chip select;
- a full-duplex transfer model: a MOSI byte stream (`tx`) and a MISO byte
  stream (`rx`) that is either empty or exactly as long as `tx`;
- an event/byte stream that encodes a transfer and decodes it back, with a
  deterministic error catalog where every error carries a byte offset
  (decode) or -1 (encode input fields).

## Non-goals

- **No I/O and no FFI.** There is no GPIO, clock peripheral or DMA layer;
  nothing in this package touches hardware. Streams are in-memory
  `Vec[UInt8]` values.
- **No timing simulation.** Clock edges are not modelled cycle by cycle:
  CPOL/CPHA are validated and carried, not simulated. The event stream
  records whole bytes, not individual clock edges.
- **No slave model.** Only the master-side descriptor is modelled; there is
  no shift-register or peripheral state machine.
- **No multi-chip-select arbitration.** One transfer names at most one
  chip-select line; no CS setup/hold timing, no GPIO direction handling.
- **No word-level stream encoding.** Words are a *view* over the tx bytes
  (`spi_word_count` / `spi_word_at`); the stream stores bytes.
- **No bit-packed rx capture.** rx is captured at byte granularity; the
  codec assumes the same byte count on both wires.

## Event stream format (byte level)

A stream is a sequence of events. Every event starts with a 1-byte type
byte; multi-byte events carry scalar payload bytes, each one byte, so no
endianness is involved anywhere.

| Type | Name | Size | Payload |
|---|---|---|---|
| `0x01` | CONFIG | 4 | `mode` (0..3), `word_size` (4..16), `bit_order` (0..1) |
| `0x02` | CS_ASSERT | 2 | chip-select line 0..7 |
| `0x03` | CS_DEASSERT | 2 | chip-select line; must equal the asserted line |
| `0x04` | TX | 2 | one MOSI byte |
| `0x05` | RX | 2 | one MISO byte |
| `0x06` | END | 1 | none |
| other | -- | -- | unknown event type |

Stream layout produced by `spi_encode`:

```
CONFIG mode word_size bit_order
[CS_ASSERT cs]                      only when cs >= 0
for each i in 0..tx.len()-1:
    TX tx[i]
    [RX rx[i]]                      only when rx is non-empty
[CS_DEASSERT cs]                    only when cs >= 0
END
```

Pinned examples (all three are test vectors):

| Transfer | Stream |
|---|---|
| mode 0, cs 2, 8-bit, tx `de ad` | `01 00 08 00 02 02 04 de 04 ad 03 02 06` |
| mode 3, cs 0, 8-bit, LSB-first, tx `01 02 03` | `01 03 08 01 02 00 04 01 04 02 04 03 03 00 06` |
| mode 1, cs 3, 8-bit, tx `aa`, rx `55` | `01 01 08 00 02 03 04 aa 05 55 03 03 06` |

A stream with `cs == -1` omits both CS events and still starts with CONFIG
and ends with END, e.g. `01 00 08 00 04 ab 06` (tx `ab`, no chip select,
empty rx).

### Encoding a transfer

`spi_encode(t)`:

1. `spi_validate(t)` runs first; on failure the encode returns the same
   error with offset -1 and produces nothing.
2. CONFIG carries mode, word size and bit order verbatim as three bytes.
3. `cs >= 0` adds CS_ASSERT before the data events and CS_DEASSERT after
   them; `cs == -1` adds neither.
4. Each TX event is followed by an RX event exactly when `rx.len() > 0`
   (validation guarantees `rx.len() == tx.len()` in that case), so a tx-only
   descriptor and a captured full-duplex transfer encode differently.
5. END closes the stream; nothing follows it.

### Decoding a stream

`spi_decode(stream)` walks the events in order and returns the transfer the
stream describes. Decoding is strict: only streams produced by `spi_encode`
of a valid transfer are accepted, so `decode -> encode` reproduces every
accepted stream byte for byte.

Offset convention: an error offset is the byte the decoder was reading when
it detected the problem, or the offset of the offending field/event:

- CONFIG field errors point at the field itself: mode at offset 1, word
  size at 2, bit order at 3;
- a missing CONFIG points at offset 0;
- CS payload errors (line > 7, deassert line mismatch) point at the payload
  byte;
- end-of-transfer checks (cs left asserted, rx/tx count mismatch, tx bits
  not a whole number of words) point at the END event;
- bytes after END point at the first trailing byte;
- when the buffer ends in the middle of an event, the offset is the first
  missing byte, which can equal `stream.len()`.

## Bit-level semantics

- The tx bytes are one continuous MOSI bit sequence, clocked in byte order.
  In MSB-first order (`bit_order == 0`) the first clocked bit of each byte
  is bit 7 and the last is bit 0; in LSB-first order (`bit_order == 1`) the
  first clocked bit is bit 0 and the last is bit 7.
- The bit sequence is divided into words of `word_size` bits (4..16). A
  transfer is valid only when `8 * tx.len()` is divisible by `word_size`
  (zero bytes is trivially a whole number of words, including zero words).
- The value of a word is assembled in clock order: for MSB-first the first
  clocked bit is the word's most significant bit; for LSB-first the first
  clocked bit is the word's least significant bit.
- Worked example, tx bytes `12 34` (bits of `0x12` then `0x34`):

| View | MSB-first | LSB-first |
|---|---|---|
| four 4-bit words | 1, 2, 3, 4 | 2, 1, 4, 3 |
| one 16-bit word | 4660 (`0x1234`) | 13330 (`0x3412`) |

- rx is the parallel MISO bit stream: byte `rx[i]` is clocked during the
  same eight clock cycles as `tx[i]`. The stream stores the pairing at byte
  granularity (RX after TX), not bit by bit.

## Chip-select semantics

- Line numbers are 0..7; the codec does not interpret them beyond the
  number.
- Lines are active-low: an asserted line is driven to level 0 and an idle
  line to level 1 (`spi_cs_assert_level()` = 0, `spi_cs_idle_level()` = 1,
  `spi_cs_line_level(cs, asserted)` returns the level).
- `cs == -1` means "no chip select" (a 3-wire bus): no CS events are
  encoded, and `spi_cs_name(-1)` is `"none"`.
- A stream must assert and deassert the same line; a CS_DEASSERT without a
  preceding CS_ASSERT, a mismatched line, or an END while the line is still
  asserted are all errors.

## Clock prescaler table

`spi_prescaler_table()` returns 16 Int entries: index `i` holds `2^(i+1)`,
so entry 0 = 2, entry 1 = 4, ..., entry 15 = 65536. Clock selection:

- `spi_clock_divider(index)` = table entry, or -1 outside 0..15;
- `spi_divider_index(divider)` = index of an exact power of two in
  2..65536, or -1;
- `spi_clock_hz(bus_hz, index)` = `bus_hz / divider`, integer division
  (floor), or -1 when `bus_hz <= 0` or the index is outside 0..15;
- `spi_prescaler_for(bus_hz, max_hz)` = the smallest index whose clock is
  at most `max_hz` (the first index whose divider makes
  `bus_hz / divider <= max_hz`), or -1 when `bus_hz <= 0`, `max_hz <= 0` or
  even the largest divider is still too fast.

There is no divider-1 bypass: a bus clock can only be divided down.

## Types

```xi
pub type SpiConfig = { mode: Int; word_size: Int; bit_order: Int; }
pub type SpiTransfer = { config: SpiConfig; cs: Int; tx: Vec[UInt8]; rx: Vec[UInt8]; }
pub type SpiError = { offset: Int; message: Str; }
```

Field meanings: `mode` 0..3; `word_size` 4..16 bits; `bit_order` 0 MSB-first
or 1 LSB-first; `cs` -1 or 0..7; `tx` MOSI bytes; `rx` MISO bytes (empty or
`rx.len() == tx.len()`); `offset` a stream byte offset or -1; `message` a
stable `"spi: ..."` text.

## API contract

All functions are free functions in module `xiom.spi`; there are no methods
and no state. Every fallible function validates in the order listed and
returns `Err` without a partial result; error text and offsets are stable.

```xi
pub fn spi_mode_valid(mode: Int) -> Bool
pub fn spi_cpol(mode: Int) -> Int
pub fn spi_cpha(mode: Int) -> Int
pub fn spi_mode_of(cpol: Int, cpha: Int) -> Int
pub fn spi_mode_name(mode: Int) -> Str
pub fn spi_mode_table() -> Vec[Int]
pub fn spi_bit_order_valid(order: Int) -> Bool
pub fn spi_bit_order_name(order: Int) -> Str
pub fn spi_word_size_valid(word_size: Int) -> Bool
pub fn spi_word_mask(word_size: Int) -> Int
pub fn spi_cs_valid(cs: Int) -> Bool
pub fn spi_cs_name(cs: Int) -> Str
pub fn spi_cs_line_level(cs: Int, asserted: Bool) -> Int
pub fn spi_cs_assert_level() -> Int
pub fn spi_cs_idle_level() -> Int
pub fn spi_prescaler_count() -> Int
pub fn spi_prescaler_table() -> Vec[Int]
pub fn spi_clock_divider(index: Int) -> Int
pub fn spi_divider_index(divider: Int) -> Int
pub fn spi_clock_hz(bus_hz: Int, index: Int) -> Int
pub fn spi_prescaler_for(bus_hz: Int, max_hz: Int) -> Int
pub fn spi_event_name(event: Int) -> Str
pub fn spi_event_size(event: Int) -> Int
pub fn spi_validate(t: &SpiTransfer) -> Result[Unit, SpiError]
pub fn spi_config_new(mode: Int, word_size: Int, bit_order: Int) -> Result[SpiConfig, SpiError]
pub fn spi_transfer_new(cfg: &SpiConfig, cs: Int, tx: &Vec[UInt8], rx: &Vec[UInt8]) -> Result[SpiTransfer, SpiError]
pub fn spi_transfer(mode: Int, cs: Int, tx: &Vec[UInt8]) -> Result[SpiTransfer, SpiError]
pub fn spi_encode(t: &SpiTransfer) -> Result[Vec[UInt8], SpiError]
pub fn spi_decode(stream: &Vec[UInt8]) -> Result[SpiTransfer, SpiError]
pub fn spi_transfer_mode(t: &SpiTransfer) -> Int
pub fn spi_transfer_word_size(t: &SpiTransfer) -> Int
pub fn spi_transfer_bit_order(t: &SpiTransfer) -> Int
pub fn spi_transfer_cs(t: &SpiTransfer) -> Int
pub fn spi_tx_len(t: &SpiTransfer) -> Int
pub fn spi_rx_len(t: &SpiTransfer) -> Int
pub fn spi_is_full_duplex(t: &SpiTransfer) -> Bool
pub fn spi_word_count(t: &SpiTransfer) -> Int
pub fn spi_word_at(t: &SpiTransfer, index: Int) -> Int
pub fn spi_equal(a: &SpiTransfer, b: &SpiTransfer) -> Bool
```

### Semantics and validation order

`spi_mode_valid(mode)`
: 0..3. `spi_cpol` = `mode / 2`, `spi_cpha` = `mode % 2`, each -1 for an
  invalid mode. `spi_mode_of(cpol, cpha)` = `cpol * 2 + cpha` for 0/1 inputs
  and -1 otherwise. `spi_mode_table()` is always `[0,0, 0,1, 1,0, 1,1]`.

`spi_bit_order_valid` / `spi_bit_order_name`
: 0 or 1; names `"MSB-first"`, `"LSB-first"`, else `"invalid"`.

`spi_word_size_valid` / `spi_word_mask`
: 4..16; mask `2^word_size - 1` (15, 255, 4095, 65535 at the test points),
  else -1.

`spi_cs_valid` / `spi_cs_name` / `spi_cs_line_level`
: -1 or 0..7; `"none"`, `"cs0"`..`"cs7"`, else `"invalid"`; line level 0
  asserted / 1 idle, -1 for no line or invalid.

`spi_validate(t)`
: 1. mode outside 0..3 -> `spi: invalid mode`;
  2. word size outside 4..16 -> `spi: invalid word size`;
  3. bit order outside 0..1 -> `spi: invalid bit order`;
  4. `cs` outside -1..7 -> `spi: invalid chip select`;
  5. non-empty `rx` with `rx.len() != tx.len()` -> `spi: length mismatch`;
  6. `8 * tx.len()` not divisible by the word size -> `spi: length
  mismatch`.
  All with offset -1.

`spi_config_new(mode, word_size, bit_order)`
: Steps 1-3 of `spi_validate`, offset -1; returns the config.

`spi_transfer_new(cfg, cs, tx, rx)`
: Copies both byte vectors, builds the transfer, runs `spi_validate` and
  returns the transfer or its error unchanged (offset -1).

`spi_transfer(mode, cs, tx)`
: The 8-bit MSB-first, empty-rx convenience form of `spi_transfer_new`:
  config `{ mode; word_size: 8; bit_order: 0 }`.

`spi_encode(t)`
: Validates, then emits the event stream (section above). Errors carry the
  validation error unchanged (offset -1); nothing is produced on Err.

`spi_decode(stream)`
: Strict event walk. Check order and offsets:
  1. empty -> `spi: truncated stream` at 0;
  2. first byte not 0x01 -> `spi: missing config` at 0;
  3. fewer than 4 bytes -> `spi: truncated stream` at `stream.len()`;
  4. mode > 3 -> `spi: invalid mode` at 1;
  5. word size outside 4..16 -> `spi: invalid word size` at 2;
  6. bit order > 1 -> `spi: invalid bit order` at 3;
  7. optional CS_ASSERT (2 bytes; line > 7 -> `spi: invalid chip select` at
  the line byte);
  8. event loop: TX (0x04) and RX (0x05) accumulate bytes, with
  `spi: length mismatch` at an RX that has no preceding unpaired TX;
  CS_DEASSERT (0x03) must match the asserted line
  (`spi: chip select not asserted` / `spi: chip select mismatch`) and
  no data events may follow it (`spi: unexpected event`); a second
  CONFIG/CS_ASSERT is `spi: unexpected event`; any other type is
  `spi: unknown event`; a truncated event reports the first missing byte;
  9. at END: `spi: cs left asserted` when the line is still asserted,
  `spi: length mismatch` when rx is non-empty and shorter than tx or when
  `8 * tx.len()` is not divisible by the word size;
  10. bytes after END -> `spi: trailing bytes` at the first trailing byte.

`spi_transfer_mode` / `spi_transfer_word_size` / `spi_transfer_bit_order` /
`spi_transfer_cs` / `spi_tx_len` / `spi_rx_len` / `spi_is_full_duplex`
: Field accessors. `spi_is_full_duplex` requires `tx.len() > 0` and
  `rx.len() == tx.len()`.

`spi_word_count(t)`
: `8 * tx.len() / word_size`, exact for a validated transfer; -1 when the
  word size is invalid or the bit count is not a whole number of words.

`spi_word_at(t, index)`
: Value of word `index` (0-based) assembled in clock order (see Bit-level
  semantics); -1 for an invalid word size, a negative index, or a word
  beyond the tx bit stream.

`spi_equal(a, b)`
: Structural equality over mode, word size, bit order, chip-select line and
  both byte streams.

## Error string catalog

| Error text | Raised when | Offset |
|---|---|---|
| `spi: truncated stream` | Buffer ends before a needed byte (or before END) | first missing byte (can equal `stream.len()`) |
| `spi: missing config` | Stream does not start with 0x01 | 0 |
| `spi: invalid mode` | Mode outside 0..3 | 1 (decode) / -1 (encode) |
| `spi: invalid word size` | Word size outside 4..16 | 2 (decode) / -1 (encode) |
| `spi: invalid bit order` | Bit order outside 0..1 | 3 (decode) / -1 (encode) |
| `spi: invalid chip select` | `cs` outside -1..7 (encode) or CS line > 7 (decode) | line byte (decode) / -1 (encode) |
| `spi: length mismatch` | Non-empty rx with `rx.len() != tx.len()`, extra RX, or tx bits not a whole number of words | -1 (validate/encode), RX offset or END offset (decode) |
| `spi: unknown event` | Event type outside 0x01..0x06 | type byte |
| `spi: unexpected event` | Known event in an illegal position (second CONFIG/CS_ASSERT, data after CS_DEASSERT) | type byte |
| `spi: chip select not asserted` | CS_DEASSERT without a preceding CS_ASSERT | type byte |
| `spi: chip select mismatch` | CS_DEASSERT line differs from the asserted line | line byte |
| `spi: cs left asserted` | END while the chip-select line is still asserted | END offset |
| `spi: trailing bytes` | Bytes after the END event | first trailing byte |

## Complexity

| Operation | Time | Space |
|---|---|---|
| mode / bit order / word size / cs helpers | O(1) | O(1) |
| `spi_prescaler_table` / `spi_clock_divider` / `spi_divider_index` | O(1) (16 steps) | O(16) |
| `spi_clock_hz` / `spi_prescaler_for` | O(1) | O(1) |
| `spi_validate` | O(1) | O(1) |
| `spi_config_new` / `spi_transfer` / `spi_transfer_new` | O(tx.len() + rx.len()) | O(tx.len() + rx.len()) |
| `spi_encode` | O(tx.len()) | O(tx.len()) |
| `spi_decode` | O(stream.len()) | O(tx.len() + rx.len()) |
| `spi_word_count` | O(1) | O(1) |
| `spi_word_at` | O(word_size) | O(1) |
| accessors / `spi_equal` | O(1) / O(tx.len() + rx.len()) | O(1) |

## Test plan

`tests/test_conformance.xi` (`module spi_tests`, 22 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Coverage (all buffers built in-test):

1. modes: validity, CPOL/CPHA for 0..3, inverse `spi_mode_of`, invalid
   inputs;
2. mode names and the 8-entry mode table against `spi_cpol`/`spi_cpha`;
3. bit order validity and names;
4. word sizes 4..16 and masks 15/255/4095/65535, invalid sizes;
5. chip select: lines -1..7, names, active-low levels, assert/idle levels;
6. prescaler table: 16 entries, `2^(i+1)`, index round-trip through
   `spi_divider_index`, invalid index/divider;
7. clock: 16 MHz at indexes 0..3 and 15 (244 Hz), invalid bus and index;
8. `spi_prescaler_for`: exact boundaries at 5 MHz, 8 MHz, 2 MHz, 300 Hz
   (index 15), 100 Hz (impossible -> -1);
9. event names and sizes for 0x01..0x06 and unknown types;
10. pinned tx-only stream `01 00 08 00 02 02 04 de 04 ad 03 02 06`, decode
    field by field plus `spi_equal`;
11. pinned LSB-first stream
    `01 03 08 01 02 00 04 01 04 02 04 03 03 00 06`, decode plus
    `spi_equal`;
12. 4-bit word extraction of `12 34`: MSB-first 1,2,3,4 and LSB-first
    2,1,4,3, plus out-of-range indexes -> -1;
13. 16-bit word extraction of `12 34`: MSB-first 4660, LSB-first 13330;
14. word-size divisibility (12 bits / 3 bytes and 5 bits / 5 bytes accepted;
    12 bits / 2 bytes and 5 bits / 1 byte -> length mismatch) and rx/tx
    length rules (empty rx accepted, `rx.len() == tx.len()` accepted,
    mismatch -> length mismatch);
15. decode header errors: empty, missing config, truncations at 1/2/3,
    invalid mode at 1, invalid word sizes at 2, invalid bit order at 3;
16. event-level errors: unknown event, repeated CONFIG, truncated
    CS_ASSERT, CS line 8, CS_DEASSERT without assert, RX before TX, all at
    their documented offsets;
17. cs pairing and end checks: CS line mismatch, cs left asserted, rx count
    mismatch, tx bits not a whole number of words, trailing bytes, data
    after CS_DEASSERT, second CS_ASSERT;
18. accepted streams: 3-wire (no CS), empty transfer, config+CS-only
    transfer and full-duplex `tx aa / rx 55`, each decoded field by field
    and re-encoded byte-for-byte;
19. encode/validate error catalog with offset -1 for every input error,
    plus `spi_transfer` with an invalid mode and chip select;
20. `spi_config_new`: accepted fields and the three invalid cases;
21. round-trips over 4 modes x 2 bit orders x 3 word sizes (8/4/16) on an
    8-byte buffer, plus a 12-bit full-duplex round-trip;
22. determinism: two encodes agree byte for byte, two decodes agree field
    for field, and the decoded transfer equals the original.

Fixtures are hex strings decoded with `xiom.encoding.hex` and explicit
`Vec[UInt8]` builders; no `Str` value is compared with `==` (BUG 17
discipline); error messages go through
`xiom.string.compare.str_compare`.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.spi
```

Last verified: compiler 0.64.0,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Known limitations

- No transport, timing, peripheral state machine or slave model (see
  Non-goals).
- The event stream records bytes, not clock edges; CPOL/CPHA are carried
  and validated but not simulated.
- rx is byte-granular; bit-level MISO capture and byte-count mismatch on
  the wire are out of scope.
- No divider-1 bypass: the finest divider is 2.
- Chip-select setup/hold timing, active-high lines and multiple
  simultaneously asserted lines are out of scope.
- Every decode error offset follows the documented convention; callers
  should treat offsets as diagnostics, not as recovery positions.
- `spi_decode` accepts exactly the streams `spi_encode` produces (plus
  equivalent streams with the same canonical layout); hand-built streams
  that reorder events are rejected as `spi: unexpected event`.

## Compiler / stdlib notes for v0.64.0

- Free functions only: no methods, no lambdas, no `Vec[fn]` dispatch, no
  `Vec[StructType]`.
- `Ok`/`Err` construction is confined to the tiny leaf helpers
  (`_ok_cfg`/`_err_cfg`, `_ok_transfer`/`_err_transfer`,
  `_ok_bytes`/`_err_bytes`, `_ok_unit`/`_err_unit`), because constructing
  Results directly inside other functions miscompiles in this compiler.
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF` before
  entering Int arithmetic; UInt8 values are never compared against Int
  constants >= 128 without widening.
- `&struct.field` is never passed as a `&Vec[UInt8]` parameter (that yields
  an empty vector in v0.64.0); fields are bound to typed locals first.
- All shifts are written as multiplication/division by powers of two and
  all bit tests use `% 2` on non-negative Ints (no shift or bitwise AND on
  potentially large values, per the xiom.can/xiom.modbus experience).
- The package declares no `extern "C"` blocks (no FFI).
- During this port, four `Vec<...>` mixed-bracket typos in the library and
  two in the tests compiled silently and were caught only by a
  `Vec<`/`Result<` grep (trap 14); both files audit clean now.
- Known v0.64.0 runtime-checker trap (seen in batch #37): an `ensures:`
  clause that reads a `Result` `Vec` payload length (`result.value.len()`)
  on a function whose `Ok` builder loops and returns through `_ok_bytes`
  was evaluated nondeterministically (the same compiled binary alternated
  clean runs and `contract violated: ensures`). `spi_encode` avoids this
  by carrying per-field config guard clauses instead of an Ok-length
  clause; a standalone micro-reproduction confirmed the nondeterminism.

## Contracts (batch #37 hardening pass, 2026-10-07)

Runtime-checkable `ensures:` clauses added to `src/spi.xi` in the batch #37
hardening pass (compiler v0.64.0; `package.xi` is bumped by the coordinator
at integration). 74 clauses over all 39 public entry points, all `ensures:`
(no `requires:`), so the accepted-input domain is unchanged. Two consecutive
`& .\scripts\port.ps1 -Package xiom.spi -TimeoutSec 60` runs ended
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)` with the clauses
active (4.64 s and 4.82 s); no clause trapped and none was dropped except
the one described below. Guards read structured parameters
(`t.config.mode`/`word_size`/`bit_order`), never `Result` payload fields;
every constant is an inline literal (no module consts, no cross-calls).
`spi_word_count`'s identity is claimed only under `result != -1`;
`spi_word_at` claims only the 0..65535 word bound; `spi_decode`'s Ok clause
reads the input `stream.len()`, not the decoded payload.

Dropped: the planned `spi_encode` clause `result is Ok =>
result.value.len() >= 5` failed the port three times at the same location
(`contract violated: ensures at 683:12`). A standalone reproduction showed
the v0.64.0 runtime evaluator reading that payload length
nondeterministically (the same compiled binary alternated exit 0/1 across
runs), so the clause was dropped and `spi_encode`'s config guard was
re-expressed as three per-field guards (mode / word size / bit order),
keeping the clause count and the guard family.

`xiom-verify src/spi.xi --check` (Z3 bundled with v0.64.0) reported
**14 proven / 0 violated / 85 unknown / 42 errors**; z3 then rejected the
generated SMT (emitter bugs such as `unknown constant _byte`/`_err_*`/
`_copy_bytes`, `unknown constant mode`, `invalid function application`), so
the tool itself reports "not a proof failure of the code under test". The
14 proven obligations are not attributed per clause here; all 74 clauses
are therefore marked **runtime-checked only** (no Z3 claim) and every one
is enforced by the v0.64.0 runtime evaluator when the conformance suite
runs.

| Entry point | Clause(s) added | Class |
|---|---|---|
| `spi_mode_valid` | `result == (mode >= 0 && mode <= 3)` | runtime-checked |
| `spi_cpol` | `!(mode >= 0 && mode <= 3) => result == -1`; `(mode >= 0 && mode <= 3) => result >= 0 && result <= 1` | runtime-checked |
| `spi_cpha` | `!(mode >= 0 && mode <= 3) => result == -1`; `(mode >= 0 && mode <= 3) => result >= 0 && result <= 1` | runtime-checked |
| `spi_mode_of` | `(cpol < 0 \|\| cpol > 1 \|\| cpha < 0 \|\| cpha > 1) => result == -1`; `(cpol >= 0 && cpol <= 1 && cpha >= 0 && cpha <= 1) => result == cpol * 2 + cpha` | runtime-checked |
| `spi_mode_name` | `!(mode >= 0 && mode <= 3) => result.len() == 12`; `result.len() >= 12` | runtime-checked |
| `spi_mode_table` | `result.len() == 8` | runtime-checked |
| `spi_bit_order_valid` | `result == (order == 0 \|\| order == 1)` | runtime-checked |
| `spi_bit_order_name` | `(order == 0 \|\| order == 1) => result.len() == 9`; `!(order == 0 \|\| order == 1) => result.len() == 7` | runtime-checked |
| `spi_word_size_valid` | `result == (word_size >= 4 && word_size <= 16)` | runtime-checked |
| `spi_word_mask` | `!(word_size >= 4 && word_size <= 16) => result == -1`; `result != -1 => result >= 15 && result <= 65535` | runtime-checked |
| `spi_cs_valid` | `result == (cs >= -1 && cs <= 7)` | runtime-checked |
| `spi_cs_name` | `cs >= 0 && cs <= 7 => result.len() == 3`; `cs == -1 => result.len() == 4`; `!(cs >= -1 && cs <= 7) => result.len() == 7` | runtime-checked |
| `spi_cs_line_level` | `(!(cs >= -1 && cs <= 7) \|\| cs == -1) => result == -1`; `asserted && cs >= 0 && cs <= 7 => result == 0`; `!asserted && cs >= 0 && cs <= 7 => result == 1` | runtime-checked |
| `spi_cs_assert_level` | `result == 0` | runtime-checked |
| `spi_cs_idle_level` | `result == 1` | runtime-checked |
| `spi_prescaler_count` | `result == 16` | runtime-checked |
| `spi_prescaler_table` | `result.len() == 16` | runtime-checked |
| `spi_clock_divider` | `index < 0 \|\| index >= 16 => result == -1`; `index == 0 => result == 2`; `index == 15 => result == 65536` | runtime-checked |
| `spi_divider_index` | `divider == 2 => result == 0`; `divider == 65536 => result == 15`; `result >= -1 && result <= 15` | runtime-checked |
| `spi_clock_hz` | `(bus_hz <= 0 \|\| index < 0 \|\| index >= 16) => result == -1`; `result != -1 => result >= 0 && result <= bus_hz` | runtime-checked |
| `spi_prescaler_for` | `(bus_hz <= 0 \|\| max_hz <= 0) => result == -1`; `result >= -1 && result <= 15` | runtime-checked |
| `spi_event_name` | `event >= 1 && event <= 6 => result.len() >= 2`; `event == 6 => result.len() == 3`; `!(event >= 1 && event <= 6) => result.len() == 7` | runtime-checked |
| `spi_event_size` | `event == 1 => result == 4`; `event == 6 => result == 1`; `!(event >= 1 && event <= 6) => result == -1` | runtime-checked |
| `spi_validate` | `!(t.config.mode >= 0 && t.config.mode <= 3) => result is Err`; `!(t.config.word_size >= 4 && t.config.word_size <= 16) => result is Err`; `!(t.config.bit_order == 0 \|\| t.config.bit_order == 1) => result is Err` | runtime-checked |
| `spi_config_new` | `!(mode >= 0 && mode <= 3) => result is Err`; `!(word_size >= 4 && word_size <= 16) => result is Err`; `!(bit_order == 0 \|\| bit_order == 1) => result is Err` | runtime-checked |
| `spi_transfer_new` | `!(cfg.mode >= 0 && cfg.mode <= 3) => result is Err`; `!(cfg.word_size >= 4 && cfg.word_size <= 16) => result is Err`; `!(cfg.bit_order == 0 \|\| cfg.bit_order == 1) => result is Err`; `!(cs >= -1 && cs <= 7) => result is Err` | runtime-checked |
| `spi_transfer` | `!(mode >= 0 && mode <= 3) => result is Err`; `!(cs >= -1 && cs <= 7) => result is Err`; `result is Ok => cs >= -1 && cs <= 7` | runtime-checked |
| `spi_encode` | `!(t.config.mode >= 0 && t.config.mode <= 3) => result is Err`; `!(t.config.word_size >= 4 && t.config.word_size <= 16) => result is Err`; `!(t.config.bit_order == 0 \|\| t.config.bit_order == 1) => result is Err` (planned Ok-length clause dropped, see above) | runtime-checked |
| `spi_decode` | `stream.len() == 0 => result is Err`; `result is Ok => stream.len() >= 5` | runtime-checked |
| `spi_transfer_mode` | `result == t.config.mode` | runtime-checked |
| `spi_transfer_word_size` | `result == t.config.word_size` | runtime-checked |
| `spi_transfer_bit_order` | `result == t.config.bit_order` | runtime-checked |
| `spi_transfer_cs` | `result == t.cs` | runtime-checked |
| `spi_tx_len` | `result == t.tx.len()` | runtime-checked |
| `spi_rx_len` | `result == t.rx.len()` | runtime-checked |
| `spi_is_full_duplex` | `result == (t.tx.len() > 0 && t.rx.len() == t.tx.len())` | runtime-checked |
| `spi_word_count` | `!(t.config.word_size >= 4 && t.config.word_size <= 16) => result == -1`; `result != -1 => result * t.config.word_size == t.tx.len() * 8` | runtime-checked |
| `spi_word_at` | `!(t.config.word_size >= 4 && t.config.word_size <= 16) => result == -1`; `index < 0 => result == -1`; `result != -1 => result >= 0 && result <= 65535` | runtime-checked |
| `spi_equal` | `result => (a.config.mode == b.config.mode && a.cs == b.cs && a.tx.len() == b.tx.len() && a.rx.len() == b.rx.len())` | runtime-checked |

Deliberately not claimed: no `Ok` payload field is read anywhere (no
struct-payload field reads); the encode output length floor is not claimed
(clause dropped, see above); `spi_word_count` does not claim its converse
for `-1`; `spi_word_at` does not claim which words are `0` or `-1` beyond
the bound; `spi_equal` does not claim the word-size/bit-order conjuncts; and
no clause calls another `xiom.spi` function (all conditions are inline).

