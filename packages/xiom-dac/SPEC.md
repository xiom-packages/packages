# xiom.dac -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.dac`, version `0.1.0`).
Module: `src/dac.xi` (`module xiom.dac`).
Depends on `xiom.std`; the library module imports `xiom.convert`
(`int_to_string`); the tests also import `xiom.test`, `xiom.io`,
`xiom.string.compare` and `xiom.encoding.hex`.

## Scope

A pure-XIOM (no FFI, no bus I/O, no device state) codec for the deterministic
write path of three DAC families:

- **MCP4725** -- single 12-bit I2C DAC with EEPROM: address byte, fast write,
  write DAC register (010), write DAC + EEPROM (011), read address byte,
  power-down table, frame decode and VDD-referenced scaling.
- **MCP4728** -- quad 12-bit I2C DAC with EEPROM: address byte with
  programmable A2 A1 A0, multi-write (010, W1 W0 = 00), single write
  (W1 W0 = 11, EEPROM), fast write (3 bytes), sequential write recognized in
  decode (W1 W0 = 10), reference rules (internal 2.048 V with 1x/2x gain,
  external VDD forced to 1x by the silicon), frame decode and scaling.
- **MCP4921/MCP4922** -- single/dual 12-bit SPI DAC: 16-bit frame
  `A/B BUF GA SHDN D11..D0` (MSB first), channel select, buffered/unbuffered
  reference input, 1x/2x gain, SHDN bit with the active-low hardware note,
  frame decode, MCP4921 DAC B rejection and external-reference scaling.
- **Integer scaling** -- `vref_uv * code * gain / 2^bits`, one truncating
  division, 8..24-bit generic envelope and 12-bit family wrappers.
- **Validation** -- deterministic `Err(Str)` messages with the offending
  value, byte offsets in decoder errors, and no partial results.

## Non-goals

- **No bus I/O.** No I2C START/STOP/ACK, no SPI clocking, no CS/LDAC/SHDN pin
  handling, no register readback (the MCP4725/MCP4728 read commands are
  represented only by their address byte).
- **No device state or timing.** EEPROM write duration, settling time, power
  sequencing and RDY/BSY polling are out of scope.
- **Not every MCP4728 command.** The dedicated "Write I2C Address Bits"
  command (C2 C1 C0 = 011) and the VREF-only (100), PD-only (101) and
  gain-only (110) update commands are not implemented; single, multi, fast
  and sequential modes are.
- **No float math and no `Vec[Float64]`.** Microvolts are integers.
- **No calibration or electrical modeling.** Offset/gain error, noise,
  reference tolerance and temperature behavior are not modeled.
- **No other DAC families.** The register formats are the three documented
  families above.

## Byte-level layouts (as implemented)

Every frame starts with the I2C address byte or, for SPI, is the 16-bit word
itself. Bits are numbered MSB first on the wire.

### MCP4725 (reference = VDD)

Address byte: `1100 A2 A1 A0 R/W` -> `address * 2 + read` for 7-bit addresses
0x60..0x67 (96..103); the factory device code is 1100 with A2 A1 = 00 and A0
strapped.

Fast write, 3 bytes (C2 C1 = 00, C0 don't care; EEPROM untouched):

| Byte | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|
| 0 | 1 | 1 | 0 | 0 | A2 | A1 | A0 | 0 |
| 1 | 0 | 0 | PD1 | PD0 | D11 | D10 | D9 | D8 |
| 2 | D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0 |

Write DAC register, 4 bytes (C2 C1 C0 = 010; X = don't care):

| Byte | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|
| 0 | 1 | 1 | 0 | 0 | A2 | A1 | A0 | 0 |
| 1 | 0 | 1 | 0 | X | X | PD1 | PD0 | X |
| 2 | D11 | D10 | D9 | D8 | D7 | D6 | D5 | D4 |
| 3 | D3 | D2 | D1 | D0 | X | X | X | X |

Write DAC + EEPROM, 4 bytes: identical with C2 C1 C0 = 011 (second byte base
0x60 + PD). Read command: the address byte with R/W = 1; the part then clocks
out six bytes (status, DAC register and EEPROM), which this codec does not
decode.

### MCP4728 (quad, optional internal 2.048 V reference)

Address byte: `1100 A2 A1 A0 R/W`, A2 A1 A0 programmable, factory default 000
-> 0x60. `mcp4728_address_from_bits(a2, a1, a0) = 0x60 + a2*4 + a1*2 + a0`.

Multi-write, 4 bytes (C2 C1 C0 = 010, W1 W0 = 00; EEPROM untouched):

| Byte | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|
| 0 | 1 | 1 | 0 | 0 | A2 | A1 | A0 | 0 |
| 1 | 0 | 1 | 0 | 0 | 0 | DAC1 | DAC0 | UDAC |
| 2 | VREF | PD1 | PD0 | GX | D11 | D10 | D9 | D8 |
| 3 | D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0 |

DAC1 DAC0: 00 A, 01 B, 10 C, 11 D. UDAC 0 uploads the selected channel, 1
holds. VREF 1 selects the internal 2.048 V reference, 0 selects VDD. GX 0 is
1x and 1 is 2x (internal reference only; with VREF = VDD the silicon ignores
GX and uses 1x).

Single write + EEPROM, 4 bytes: identical layout with W1 W0 = 11, so byte 1
is `010 11 DAC1 DAC0 UDAC` (base 0x58).

Sequential write + EEPROM (recognized in decode, W1 W0 = 10, base 0x50):
same 3-byte group repeated for the channels from the starting channel to D;
`mcp4728_single_write_frame`/`multi_write_frame` cover the single- and
multi-channel forms.

Fast write, 3 bytes (C2 C1 = 00, C0 don't care; channel group A..D sequential,
no VREF/gain/UDAC):

| Byte | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|
| 0 | 1 | 1 | 0 | 0 | A2 | A1 | A0 | 0 |
| 1 | X | X | PD1 | PD0 | D11 | D10 | D9 | D8 |
| 2 | D7 | D6 | D5 | D4 | D3 | D2 | D1 | D0 |

### MCP4921/MCP4922 (SPI, external reference)

One 16-bit write word, two bytes MSB first, latched on the CS rising edge:

| Bit | 15 | 14 | 13 | 12 | 11..0 |
|---|---|---|---|---|---|
| Field | A/B | BUF | GA | SHDN | D11..D0 |
| Value | 1 = DAC B (4922), 0 = DAC A | 1 = buffered, 0 = unbuffered | 1 = 1x, 0 = 2x | 1 = output active, 0 = high impedance | 12-bit code |

The hardware SHDN and LDAC pins are active low; the register SHDN bit is
active high (1 keeps the output on). The MCP4921 has only DAC A; the SHDN
register bit still exists but the pin is only brought out on the MCP4922.

## Voltage model

All three families are 12-bit and use the datasheet transfer function

```
vout_uv = vref_uv * code * gain / 2^bits
```

with the product formed first and a single division that truncates toward
zero. The divisor is `2^bits` (4096), not `2^bits - 1`, so code 4095 maps to
`vref * 4095/4096` -- full scale minus one LSB. The generic helper accepts
8..24-bit resolutions with the same divisor.

- MCP4725: reference is VDD; `mcp4725_code_to_uv(code, vdd_uv)`.
- MCP4728: internal 2.048 V (gain 1x or 2x) or external VDD (gain forced to
  1x); `mcp4728_code_to_uv(code, vref, gain, vdd_uv)`.
- MCP4921/MCP4922: external reference input, gain 1x or 2x;
  `mcp492x_code_to_uv(code, vref_uv, gain)`.

Overflow safety: the largest product is a multi-volt reference (a few 1e6 uV)
times a 24-bit code (1.7e7) times a small gain, far inside the 64-bit `Int`
range.

## Types

```xi
pub type Mcp4725Frame = { address: Int; mode: Int; pd: Int; code: Int; }
pub type Mcp4728Frame = {
  address: Int; mode: Int; channel: Int; code: Int;
  vref: Int; pd: Int; gain: Int; udac: Int;
}
pub type Mcp492xFrame = { channel: Int; buf: Int; gain: Int; shdn: Int; code: Int; }
```

`Mcp4728Frame` fields not carried by a fast frame (channel, vref, gain, udac)
decode to -1. `Mcp492xFrame.gain` is the decoded multiplier (GA = 1 -> 1,
GA = 0 -> 2); the raw bits are recoverable with `mcp492x_ga_bit`.

## API contract

All functions are free functions in module `xiom.dac`; there are no methods
and no state. Every fallible function validates in the order listed and
returns `Err` without a partial result; error text is stable.

```xi
pub fn dac_family_name(family: Int) -> Str
pub fn dac_resolution_bits(family: Int) -> Int
pub fn dac_full_scale(family: Int) -> Int
pub fn dac_power_down_name(pd: Int) -> Str
pub fn dac_frame_byte(data: &Vec[UInt8], index: Int) -> Int
pub fn dac_code_to_uv(code: Int, bits: Int, vref_uv: Int, gain: Int) -> Result[Int, Str]

pub fn mcp4725_address_byte(address: Int, read: Bool) -> Result[Int, Str]
pub fn mcp4725_read_address_byte(address: Int) -> Result[Int, Str]
pub fn mcp4725_fast_frame(address: Int, code: Int, pd: Int) -> Result[Vec[UInt8], Str]
pub fn mcp4725_write_dac_frame(address: Int, code: Int, pd: Int) -> Result[Vec[UInt8], Str]
pub fn mcp4725_write_eeprom_frame(address: Int, code: Int, pd: Int) -> Result[Vec[UInt8], Str]
pub fn mcp4725_decode(data: &Vec[UInt8]) -> Result[Mcp4725Frame, Str]
pub fn mcp4725_power_down_name(pd: Int) -> Str
pub fn mcp4725_resolution_bits() -> Int
pub fn mcp4725_full_scale() -> Int
pub fn mcp4725_code_to_uv(code: Int, vdd_uv: Int) -> Result[Int, Str]

pub fn mcp4728_address_byte(address: Int, read: Bool) -> Result[Int, Str]
pub fn mcp4728_address_from_bits(a2: Int, a1: Int, a0: Int) -> Result[Int, Str]
pub fn mcp4728_channel_name(channel: Int) -> Str
pub fn mcp4728_multi_write_frame(address: Int, channel: Int, code: Int, vref: Int, pd: Int, gain: Int, udac: Int) -> Result[Vec[UInt8], Str]
pub fn mcp4728_single_write_frame(address: Int, channel: Int, code: Int, vref: Int, pd: Int, gain: Int, udac: Int) -> Result[Vec[UInt8], Str]
pub fn mcp4728_fast_frame(address: Int, code: Int, pd: Int) -> Result[Vec[UInt8], Str]
pub fn mcp4728_decode(data: &Vec[UInt8]) -> Result[Mcp4728Frame, Str]
pub fn mcp4728_reference_uv(vref: Int, vdd_uv: Int) -> Result[Int, Str]
pub fn mcp4728_effective_gain(vref: Int, gain: Int) -> Result[Int, Str]
pub fn mcp4728_code_to_uv(code: Int, vref: Int, gain: Int, vdd_uv: Int) -> Result[Int, Str]
pub fn mcp4728_power_down_name(pd: Int) -> Str
pub fn mcp4728_resolution_bits() -> Int
pub fn mcp4728_full_scale() -> Int

pub fn mcp4922_frame(channel: Int, code: Int, buf: Int, gain: Int, shdn: Int) -> Result[Vec[UInt8], Str]
pub fn mcp4921_frame(code: Int, buf: Int, gain: Int, shdn: Int) -> Result[Vec[UInt8], Str]
pub fn mcp492x_decode(data: &Vec[UInt8]) -> Result[Mcp492xFrame, Str]
pub fn mcp4921_decode(data: &Vec[UInt8]) -> Result[Mcp492xFrame, Str]
pub fn mcp492x_channel_name(channel: Int) -> Str
pub fn mcp492x_ga_bit(gain: Int) -> Int
pub fn mcp492x_shutdown_bit(shutdown: Bool) -> Int
pub fn mcp492x_resolution_bits() -> Int
pub fn mcp492x_full_scale() -> Int
pub fn mcp492x_code_to_uv(code: Int, vref_uv: Int, gain: Int) -> Result[Int, Str]
```

### Semantics and validation order

`dac_family_name` / `dac_resolution_bits` / `dac_full_scale` /
`dac_power_down_name` / `dac_frame_byte` / `*_channel_name` /
`*_power_down_name` / `mcp492x_ga_bit` / `mcp492x_shutdown_bit` /
`*_resolution_bits` / `*_full_scale`
: Pure lookups, never fail. Unknown selectors return `"unknown"` or -1;
`dac_frame_byte` returns -1 outside the buffer.

`dac_code_to_uv(code, bits, vref_uv, gain)`
: 1. bits outside 8..24 -> resolution error; 2. `vref_uv <= 0` -> vref
  error; 3. `gain < 1` -> gain error; 4. code outside `0..2^bits-1` -> code
  error; 5. `vref*code*gain/2^bits`.

`mcp4725_address_byte(address, read)` / `mcp4725_read_address_byte(address)`
: Address must be 96..103; result `address*2 + R/W`.

`mcp4725_fast_frame(address, code, pd)` /
`mcp4725_write_dac_frame` / `mcp4725_write_eeprom_frame`
: 1. address 96..103; 2. code 0..4095; 3. pd 0..3. Then the layouts above.
  Nothing is written on Err.

`mcp4725_decode(data)`
: 3 bytes -> fast frame; 4 bytes -> command must be 010 or 011; anything else
  -> length error. Byte 0 must be a write address in 96..103; don't-care bits
  are ignored.

`mcp4728_address_byte` / `mcp4728_address_from_bits`
: Address 96..103 (byte) or each bit 0/1 in the order a2, a1, a0.

`mcp4728_multi_write_frame` / `mcp4728_single_write_frame`
: 1. address 96..103; 2. channel 0..3; 3. code 0..4095; 4. vref 0/1;
  5. pd 0..3; 6. gain (GX) 0/1; 7. udac 0/1. Then the layout above with
  command base 0x40 (multi) or 0x58 (single).

`mcp4728_fast_frame`
: 1. address; 2. code; 3. pd. Then the 3-byte layout with X X = 00.

`mcp4728_decode(data)`
: 3 bytes -> fast frame (channel/vref/gain/udac = -1); 4 bytes -> command
  type must be 010, W1 W0 = 00/10/11 (01 reserved). Byte 0 must be a write
  address.

`mcp4728_reference_uv(vref, vdd_uv)`
: vref 1 -> 2048000 (VDD ignored); vref 0 -> `vdd_uv` when positive; bad
  selector -> selector error.

`mcp4728_effective_gain(vref, gain)`
: vref 1 -> 1 + gain (1 or 2); vref 0 -> 1 (GX ignored by the silicon); bad
  selector or GX -> error.

`mcp4728_code_to_uv(code, vref, gain, vdd_uv)`
: 1. code 0..4095; 2. reference; 3. effective gain; 4.
  `ref_uv * code * gain / 4096`.

`mcp4922_frame(channel, code, buf, gain, shdn)`
: 1. channel 0/1; 2. code 0..4095; 3. buf 0/1; 4. gain 1/2; 5. shdn 0/1.
  Word = `channel*32768 + buf*16384 + ga*8192 + shdn*4096 + code` with
  `ga = 1` for gain 1 and `ga = 0` for gain 2; bytes are MSB first.

`mcp4921_frame(code, buf, gain, shdn)`
: The same validation with the channel fixed to DAC A and the
  `dac.mcp4921:` message prefix.

`mcp492x_decode(data)`
: Exactly 2 bytes; fields extracted as above; `gain` decoded from GA.

`mcp4921_decode(data)`
: `mcp492x_decode` plus rejection of the channel-B bit.

`mcp492x_code_to_uv(code, vref_uv, gain)`
: 1. code 0..4095; 2. gain 1/2; 3. `vref_uv > 0`; 4.
  `vref_uv * code * gain / 4096`.

## Error string catalog

| Condition | Error text |
|---|---|
| Generic resolution outside 8..24 | `dac: resolution N out of range 8..24` |
| Generic non-positive reference | `dac: vref N uV must be positive` |
| Generic gain below 1 | `dac: gain N must be at least 1` |
| Generic code out of range | `dac: code N out of range 0..M` |
| MCP4725/4728 address out of range | `dac.mcp4725: address N out of range 96..103` (same for `dac.mcp4728`) |
| MCP4725 code out of range | `dac.mcp4725: code N out of range 0..4095` |
| MCP4725 power-down out of range | `dac.mcp4725: power-down N out of range 0..3` |
| MCP4725 frame length | `dac.mcp4725: frame length N is not 3 (fast) or 4 (normal)` |
| MCP4725 decode read address | `dac.mcp4725: byte 0 is a read address byte (r/w is 1)` |
| MCP4725 decode address | `dac.mcp4725: byte 0 address N out of range 96..103` |
| MCP4725 decode command | `dac.mcp4725: byte 1 command N is not 2 (write DAC) or 3 (write DAC+EEPROM)` |
| MCP4728 channel out of range | `dac.mcp4728: channel N is not 0 (A) .. 3 (D)` |
| MCP4728 code out of range | `dac.mcp4728: code N out of range 0..4095` |
| MCP4728 one-bit field | `dac.mcp4728: vref N is not 0 or 1` (same for `gain`, `udac`, `a0`, `a1`, `a2`) |
| MCP4728 power-down out of range | `dac.mcp4728: power-down N out of range 0..3` |
| MCP4728 external reference | `dac.mcp4728: external vref N uV must be positive` |
| MCP4728 reference selector | `dac.mcp4728: vref N is not 0 (external) or 1 (internal)` |
| MCP4728 gain selector | `dac.mcp4728: gain N is not 0 (1x) or 1 (2x)` |
| MCP4728 frame length | `dac.mcp4728: frame length N is not 3 (fast) or 4 (normal)` |
| MCP4728 decode read address | `dac.mcp4728: byte 0 is a read address byte (r/w is 1)` |
| MCP4728 decode address | `dac.mcp4728: byte 0 address N out of range 96..103` |
| MCP4728 decode command | `dac.mcp4728: byte 1 command N is not 2 (010)` |
| MCP4728 reserved write function | `dac.mcp4728: byte 1 write function 01 is reserved` |
| MCP4922 channel out of range | `dac.mcp4922: channel N is not 0 (DAC A) or 1 (DAC B)` |
| MCP492x code out of range | `dac.mcp4921: code N out of range 0..4095` (`dac.mcp4922:` for the dual part) |
| MCP492x BUF bit | `dac.mcp4921: buf N is not 0 (unbuffered) or 1 (buffered)` |
| MCP492x gain | `dac.mcp4921: gain N is not 1 (1x) or 2 (2x)` |
| MCP492x SHDN bit | `dac.mcp4921: shdn N is not 0 (high-Z) or 1 (active)` |
| MCP492x frame length | `dac.mcp492x: frame needs 2 bytes, have N` |
| MCP4921 DAC B present | `dac.mcp4921: channel B is not present on the single-channel part` |
| MCP492x voltage gain | `dac.mcp492x: gain N is not 1 (1x) or 2 (2x)` |
| MCP492x voltage reference | `dac.mcp492x: vref N uV must be positive` |

Encoder errors use every prefix verbatim (`dac.mcp4922:` for the dual frame
function, `dac.mcp4921:` for the single one); the shared SPI decoder uses
`dac.mcp492x:`.

## Complexity

| Operation | Time | Space |
|---|---|---|
| All encoders, decoders, validators, accessors and scalers | O(1) | O(1) |
| `dac_frame_byte` | O(1) | O(1) |

## Constants

```xi
pub const DAC_BITS_MIN: Int = 8;
pub const DAC_BITS_MAX: Int = 24;
pub const DAC_FAMILY_MCP4725: Int = 0;
pub const DAC_FAMILY_MCP4728: Int = 1;
pub const DAC_FAMILY_MCP4921: Int = 2;
pub const DAC_FAMILY_MCP4922: Int = 3;
pub const DAC_PD_NORMAL: Int = 0;
pub const DAC_PD_1K_GND: Int = 1;
pub const DAC_PD_100K_GND: Int = 2;
pub const DAC_PD_500K_GND: Int = 3;
pub const MCP4725_ADDRESS_BASE: Int = 96;
pub const MCP4725_ADDRESS_MAX: Int = 103;
pub const MCP4725_RESOLUTION_BITS: Int = 12;
pub const MCP4725_FULL_SCALE: Int = 4095;
pub const MCP4725_CMD_FAST: Int = 0;
pub const MCP4725_CMD_WRITE_DAC: Int = 2;
pub const MCP4725_CMD_WRITE_EEPROM: Int = 3;
pub const MCP4728_ADDRESS_BASE: Int = 96;
pub const MCP4728_ADDRESS_MAX: Int = 103;
pub const MCP4728_RESOLUTION_BITS: Int = 12;
pub const MCP4728_FULL_SCALE: Int = 4095;
pub const MCP4728_CH_A: Int = 0;   // .. MCP4728_CH_D = 3
pub const MCP4728_MODE_MULTI: Int = 0;
pub const MCP4728_MODE_SEQUENTIAL: Int = 1;
pub const MCP4728_MODE_SINGLE: Int = 2;
pub const MCP4728_MODE_FAST: Int = 3;
pub const MCP4728_VREF_EXTERNAL: Int = 0;
pub const MCP4728_VREF_INTERNAL: Int = 1;
pub const MCP4728_INTERNAL_REF_UV: Int = 2048000;
pub const MCP4728_GAIN_1X: Int = 0;
pub const MCP4728_GAIN_2X: Int = 1;
pub const MCP4728_UDAC_UPDATE: Int = 0;
pub const MCP4728_UDAC_HOLD: Int = 1;
pub const MCP492X_RESOLUTION_BITS: Int = 12;
pub const MCP492X_FULL_SCALE: Int = 4095;
pub const MCP492X_CH_A: Int = 0;
pub const MCP492X_CH_B: Int = 1;
pub const MCP492X_GAIN_1X: Int = 1;
pub const MCP492X_GAIN_2X: Int = 2;
pub const MCP492X_GA_BIT_1X: Int = 1;
pub const MCP492X_GA_BIT_2X: Int = 0;
pub const MCP492X_BUF_UNBUFFERED: Int = 0;
pub const MCP492X_BUF_BUFFERED: Int = 1;
pub const MCP492X_SHDN_HIGH_Z: Int = 0;
pub const MCP492X_SHDN_ACTIVE: Int = 1;
```

## Test plan

`tests/test_conformance.xi` (`module dac_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. MCP4725 address: wire bytes for 0x60/0x67 with both directions, read
   helper, range errors, constants;
2. fast frame goldens `C4 0A BC`, `C4 1F FF`, `C0 00 00`, `CE 3A BC`,
   `CE 2A BC` and the 3-byte length;
3. fast decode field-by-field for three pinned frames;
4. write-DAC goldens `C4 40 AB C0`, `C4 44 AB C0`, `C0 42 FF F0` and decode;
5. write-DAC+EEPROM goldens `C4 62 AB C0`, `CE 66 00 00`, decode and error
   propagation;
6. validation matrix: code/pd/address errors, first-error order, decode
   length, bad command byte, read address byte, address offset;
7. power-down names and the PD1/PD0 bit packing `00/10/20/30`;
8. MCP4725 voltage: 0, 1650000, 4998779, 1220 uV anchors and range errors;
9. MCP4728 address bits 96..103, a0/a1/a2 errors, wire bytes, channel names;
10. multi-write quad matrix `40 42 44 46` with decode of channels A and D;
11. multi-write field packing `C0 47 FF FF`, external-reference `C0 40 08 00`,
    `CE 44 A1 23` and decode of each field;
12. single write `C0 5A B1 23`, sequential `50`, fast `C0 2A BC` and the
    fast-frame -1 channel/vref/gain/udac markers;
13. validation matrix for channel/code/vref/pd/gain/udac, decode lengths,
    command 0, reserved write function 01, read address byte;
14. MCP4728 references: internal 2048000 (VDD ignored), external VDD, gain
    forcing, `1024000` / `4095000` / `4998779` uV anchors;
15. MCP4922 golden matrix `3123 / 1123 / 2123 / 7123 / B123 / 9123 / A123 /
    F123 / FFFF / 0000`;
16. MCP492x decode fields, MCP4921 frame `5123`, DAC B rejection, length
    errors;
17. validation matrix for channel/code/buf/gain/shdn under both
    `dac.mcp4922:` and `dac.mcp4921:` prefixes, GA/SHDN helpers and names;
18. MCP492x voltage anchors `4095000`, `1024000`, `4998779`, `1000` uV and
    the code/gain/vref errors;
19. generic scaling anchors `4980468` (8-bit), `2047968` (16-bit), `4095000`,
    `2999267` (gain 3), `9960937` (gain 2), family accessors and
    `dac_frame_byte`;
20. determinism: encode/decode/re-encode over codes {0,1,2048,4095} x PD
    {0..3} for MCP4725, the full 16-combination MCP4922 matrix, the MCP4728
    channel loop and a repeated MCP4921 frame.

Fixtures: hex literals come from `xiom.encoding.hex`; frame builders are
called directly in-test. No `Str` value is compared with `==` (BUG 17
discipline); labels and error messages go through
`xiom.string.compare.str_compare`. All `Vec` element reads are bound to typed
locals and `Vec[UInt8]` bytes are widened with `& 0xFF`.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.dac
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Known limitations

- No transport, no timing, no device state and no readback decode (see
  Non-goals).
- The MCP4728 address-write command (011) and the VREF/PD/gain-only update
  commands (100/101/110) are not implemented; fast, multi, single and
  sequential write are.
- Integer truncation means full scale is one LSB below the reference; callers
  needing exact rational arithmetic should keep the code and scale later.
- The generic scaler accepts 8..24-bit resolutions; only 12-bit family
  wrappers exist.
- EEPROM write timing and the RDY/BSY busy window are documented but not
  modeled; the caller must not send commands for up to 50 ms after a single
  or EEPROM write.
- No FFI, no `extern "C"` blocks, no unsafe code, no floats.

## Compiler / stdlib notes for v0.61.3

- Free functions only: no methods, no lambdas, no `Vec[fn]` dispatch, no
  `Vec[StructType]`.
- `Ok`/`Err` construction is confined to the tiny leaf helpers
  (`_ok_unit`/`_err_unit`, `_ok_int`/`_err_int`, `_ok_bytes`/`_err_bytes`,
  `_ok_4725`/`_err_4725`, `_ok_4728`/`_err_4728`, `_ok_492x`/`_err_492x`),
  because constructing Results directly inside other functions miscompiles.
- No `Str` comparison happens in the library module; the tests compare
  labels and messages through `xiom.string.compare.str_compare` after the
  values are bound to typed locals (BUG 17).
- `&struct.field` is never passed as a `&Vec[UInt8]` parameter (that yields
  an empty vector); frame buffers are bound to typed locals first.
- Every `Vec[UInt8]` byte read is widened with `(x as Int) & 0xFF` before
  entering Int arithmetic.
- Bit composition and extraction use multiplication, division and modulo by
  powers of two, never a shift on a value that could carry the sign bit;
  division truncates toward zero.
- Dynamic error strings are built with `xiom.convert.int_to_string` (the
  `xiom.convert` module, imported as `convert`).
- Encoders return their frames by value; there are no `&mut` out-parameters
  (`&mut Int` write-through is miscompiled).
- The package declares no `extern "C"` blocks (no FFI).
