# xiom.dac

> **Status:** `incubating` -- conformance-tested (20/20); published at `v0.1.1` on the XIOM registry.
> **Scope:** pure-XIOM (no FFI, no bus I/O, no device state) DAC command and
> register codecs: MCP4725 and MCP4728 I2C frames, MCP4921/MCP4922 SPI frames,
> and integer code-to-microvolt scaling for all three families.
> **Deps:** `xiom.std` only. The library module imports `xiom.convert`
> (`int_to_string` for error messages); the tests also use `xiom.test`,
> `xiom.io`, `xiom.string.compare` and `xiom.encoding.hex`.

## What it is

`xiom.dac` turns DAC write operations into byte vectors and back, with
integer math only (voltages are microvolts; there is no float type anywhere):

- **MCP4725** (single 12-bit I2C DAC with EEPROM): the address byte for
  0x60..0x67, the fast write frame (2 data bytes), the write-DAC-register
  frame (command 010, 4 bytes), the write-DAC+EEPROM frame (command 011),
  the read address byte, the power-down table (normal / 1 kOhm / 100 kOhm /
  500 kOhm to ground), a frame decoder and the VDD-referenced scaling.
- **MCP4728** (quad 12-bit I2C DAC with EEPROM): the address byte with its
  programmable A2 A1 A0 bits, the multi-write frame (command 010, W1 W0 = 00:
  channel select + VREF/PD/GX + 12-bit code + UDAC), the single-write frame
  (W1 W0 = 11, also writes that channel's EEPROM), the fast 3-byte frame, the
  sequential write mode (W1 W0 = 10) in decode, the reference rules (internal
  2.048 V with gain 1x/2x, or external VDD with gain forced to 1x by the
  silicon), a decoder and the code-to-microvolt scaling.
- **MCP4921/MCP4922** (single/dual 12-bit SPI DAC): the 16-bit frame
  `A/B BUF GA SHDN D11..D0` (two bytes, MSB first), channel select for the
  4922, buffered/unbuffered reference input, 1x/2x gain (GA = 1 is 1x,
  GA = 0 is 2x), the SHDN bit (1 = output active; the hardware SHDN pin is
  active low), a decoder, the single-channel restriction of the MCP4921 and
  the external-reference scaling.
- **Voltage conversion**: `vref_uv * code * gain / 2^bits` with a single
  truncating division; 0 maps to 0 V and code 2^bits-1 maps to full scale
  minus one LSB. The generic helper accepts 8..24-bit resolutions; every
  family wrapper is pinned to 12 bits.
- **Accessors and validation**: family names, resolution bits, full scale,
  power-down names, safe frame-byte reads, decoded frames, and deterministic
  `Err(Str)` messages that carry the offending value and, for decoders, the
  byte offset.

There is no I2C/SPI transport, no triggering, no timing and no device state:
the codec only packs, unpacks, validates and scales. Assembling a full bus
transaction (START/STOP, ACK, CS toggling, LDAC) is the transport's job.

## Quick start

```xi
use xiom.dac;
use xiom.io;

// MCP4725 at 7-bit address 0x62 (98), code 2748 (0xABC), normal power:
let fast = mcp4725_fast_frame(98, 2748, DAC_PD_NORMAL);        // Ok({ 0xC4, 0x0A, 0xBC })
let normal = mcp4725_write_dac_frame(98, 2748, DAC_PD_NORMAL); // Ok({ 0xC4, 0x40, 0xAB, 0xC0 })
let saved = mcp4725_write_eeprom_frame(98, 2748, DAC_PD_1K_GND); // Ok({ 0xC4, 0x62, 0xAB, 0xC0 })
let rd = mcp4725_read_address_byte(98);                        // Ok(197 = 0xC5)
let uv = mcp4725_code_to_uv(2048, 3300000);                    // Ok(1650000 uV)

// Decode a captured frame (payload bytes, address byte included):
let frame = mcp4725_decode(&fast_bytes);   // Ok(Mcp4725Frame{ address: 98; mode: 0; pd: 0; code: 2748; })

// MCP4728 (address 0x60 = 96), channel C, code 2048, internal 2.048 V
// reference, gain 2x, UDAC upload, multi-write:
let quad = mcp4728_multi_write_frame(96, MCP4728_CH_C, 2048, MCP4728_VREF_INTERNAL, DAC_PD_NORMAL, MCP4728_GAIN_2X, MCP4728_UDAC_UPDATE);
// Ok({ 0xC0, 0x44, 0x98, 0x00 })
let q_uv = mcp4728_code_to_uv(2048, MCP4728_VREF_INTERNAL, MCP4728_GAIN_2X, 0); // Ok(2048000 uV)

// MCP4922: DAC B, code 291 (0x123), buffered reference, 1x gain, active:
let spi = mcp4922_frame(MCP492X_CH_B, 291, MCP492X_BUF_BUFFERED, MCP492X_GAIN_1X, MCP492X_SHDN_ACTIVE);
// Ok({ 0xF1, 0x23 })
let s_uv = mcp492x_code_to_uv(2048, 2048000, MCP492X_GAIN_2X); // Ok(2048000 uV)
```

## API

All functions are free functions in module `xiom.dac`.

### Generic and accessors

| Function | Returns | Description |
|---|---|---|
| `dac_family_name(family)` | `Str` | `"mcp4725"`, `"mcp4728"`, `"mcp4921"`, `"mcp4922"`, `"unknown"`. |
| `dac_resolution_bits(family)` | `Int` | 12 for every family, -1 for an unknown selector. |
| `dac_full_scale(family)` | `Int` | 4095 or -1. |
| `dac_power_down_name(pd)` | `Str` | `"normal"`, `"1k gnd"`, `"100k gnd"`, `"500k gnd"`, `"unknown"`. |
| `dac_frame_byte(data, index)` | `Int` | Byte widened to 0..255, or -1 out of range. |
| `dac_code_to_uv(code, bits, vref_uv, gain)` | `Result[Int, Str]` | `vref*code*gain/2^bits`, bits 8..24. |

### MCP4725

| Function | Returns | Description |
|---|---|---|
| `mcp4725_address_byte(address, read)` | `Result[Int, Str]` | Wire byte `address*2 + R/W`, addresses 96..103. |
| `mcp4725_read_address_byte(address)` | `Result[Int, Str]` | Read-direction address byte. |
| `mcp4725_fast_frame(address, code, pd)` | `Result[Vec[UInt8], Str]` | 3-byte fast frame. |
| `mcp4725_write_dac_frame(address, code, pd)` | `Result[Vec[UInt8], Str]` | 4-byte command 010 frame. |
| `mcp4725_write_eeprom_frame(address, code, pd)` | `Result[Vec[UInt8], Str]` | 4-byte command 011 frame. |
| `mcp4725_decode(data)` | `Result[Mcp4725Frame, Str]` | Decode 3- or 4-byte frames. |
| `mcp4725_power_down_name(pd)` | `Str` | Power-down table name. |
| `mcp4725_resolution_bits()` | `Int` | 12. |
| `mcp4725_full_scale()` | `Int` | 4095. |
| `mcp4725_code_to_uv(code, vdd_uv)` | `Result[Int, Str]` | `vdd*code/4096` in microvolts. |

### MCP4728

| Function | Returns | Description |
|---|---|---|
| `mcp4728_address_byte(address, read)` | `Result[Int, Str]` | Wire byte, addresses 96..103. |
| `mcp4728_address_from_bits(a2, a1, a0)` | `Result[Int, Str]` | `0x60 + a2*4 + a1*2 + a0`. |
| `mcp4728_channel_name(channel)` | `Str` | `"A"`..`"D"` or `"unknown"`. |
| `mcp4728_multi_write_frame(address, channel, code, vref, pd, gain, udac)` | `Result[Vec[UInt8], Str]` | 4-byte command 010/W1W0=00 frame. |
| `mcp4728_single_write_frame(address, channel, code, vref, pd, gain, udac)` | `Result[Vec[UInt8], Str]` | 4-byte command 010/W1W0=11 frame (EEPROM). |
| `mcp4728_fast_frame(address, code, pd)` | `Result[Vec[UInt8], Str]` | 3-byte fast frame. |
| `mcp4728_decode(data)` | `Result[Mcp4728Frame, Str]` | Decode 3- or 4-byte frames. |
| `mcp4728_reference_uv(vref, vdd_uv)` | `Result[Int, Str]` | 2048000 (internal) or VDD. |
| `mcp4728_effective_gain(vref, gain)` | `Result[Int, Str]` | 1 or 2; external VDD forces 1. |
| `mcp4728_code_to_uv(code, vref, gain, vdd_uv)` | `Result[Int, Str]` | Per-channel microvolts. |
| `mcp4728_power_down_name(pd)` | `Str` | Power-down table name. |
| `mcp4728_resolution_bits()` | `Int` | 12. |
| `mcp4728_full_scale()` | `Int` | 4095. |

### MCP4921 / MCP4922

| Function | Returns | Description |
|---|---|---|
| `mcp4922_frame(channel, code, buf, gain, shdn)` | `Result[Vec[UInt8], Str]` | 2-byte SPI frame, channel A/B. |
| `mcp4921_frame(code, buf, gain, shdn)` | `Result[Vec[UInt8], Str]` | 2-byte SPI frame, channel A. |
| `mcp492x_decode(data)` | `Result[Mcp492xFrame, Str]` | Decode a 2-byte frame. |
| `mcp4921_decode(data)` | `Result[Mcp492xFrame, Str]` | Decode and reject DAC B. |
| `mcp492x_channel_name(channel)` | `Str` | `"A"`, `"B"`, `"unknown"`. |
| `mcp492x_ga_bit(gain)` | `Int` | 1 for 1x, 0 for 2x, -1 otherwise. |
| `mcp492x_shutdown_bit(shutdown)` | `Int` | 0 when shut down, 1 when active. |
| `mcp492x_resolution_bits()` | `Int` | 12. |
| `mcp492x_full_scale()` | `Int` | 4095. |
| `mcp492x_code_to_uv(code, vref_uv, gain)` | `Result[Int, Str]` | External-reference microvolts. |

### Constants

```xi
pub const DAC_BITS_MIN: Int = 8;
pub const DAC_BITS_MAX: Int = 24;
pub const DAC_FAMILY_MCP4725: Int = 0;   // .. DAC_FAMILY_MCP4922 = 3
pub const DAC_PD_NORMAL: Int = 0;        // .. DAC_PD_500K_GND = 3
pub const MCP4725_ADDRESS_BASE: Int = 96;    pub const MCP4725_ADDRESS_MAX: Int = 103;
pub const MCP4725_RESOLUTION_BITS: Int = 12; pub const MCP4725_FULL_SCALE: Int = 4095;
pub const MCP4725_CMD_FAST: Int = 0; pub const MCP4725_CMD_WRITE_DAC: Int = 2;
pub const MCP4725_CMD_WRITE_EEPROM: Int = 3;
pub const MCP4728_ADDRESS_BASE: Int = 96; pub const MCP4728_ADDRESS_MAX: Int = 103;
pub const MCP4728_RESOLUTION_BITS: Int = 12; pub const MCP4728_FULL_SCALE: Int = 4095;
pub const MCP4728_CH_A: Int = 0; ... pub const MCP4728_CH_D: Int = 3;
pub const MCP4728_MODE_MULTI: Int = 0; ... pub const MCP4728_MODE_FAST: Int = 3;
pub const MCP4728_VREF_EXTERNAL: Int = 0; pub const MCP4728_VREF_INTERNAL: Int = 1;
pub const MCP4728_INTERNAL_REF_UV: Int = 2048000;
pub const MCP4728_GAIN_1X: Int = 0; pub const MCP4728_GAIN_2X: Int = 1;
pub const MCP4728_UDAC_UPDATE: Int = 0; pub const MCP4728_UDAC_HOLD: Int = 1;
pub const MCP492X_RESOLUTION_BITS: Int = 12; pub const MCP492X_FULL_SCALE: Int = 4095;
pub const MCP492X_CH_A: Int = 0; pub const MCP492X_CH_B: Int = 1;
pub const MCP492X_GAIN_1X: Int = 1; pub const MCP492X_GAIN_2X: Int = 2;
pub const MCP492X_GA_BIT_1X: Int = 1; pub const MCP492X_GA_BIT_2X: Int = 0;
pub const MCP492X_BUF_UNBUFFERED: Int = 0; pub const MCP492X_BUF_BUFFERED: Int = 1;
pub const MCP492X_SHDN_HIGH_Z: Int = 0; pub const MCP492X_SHDN_ACTIVE: Int = 1;
```

### Types

```xi
pub type Mcp4725Frame = { address: Int; mode: Int; pd: Int; code: Int; }
pub type Mcp4728Frame = {
  address: Int; mode: Int; channel: Int; code: Int;
  vref: Int; pd: Int; gain: Int; udac: Int;
}
pub type Mcp492xFrame = { channel: Int; buf: Int; gain: Int; shdn: Int; code: Int; }
```

## Error model

Every fallible function returns `Result[T, Str]` with a stable, lowercase
message. Family prefixes are `dac.mcp4725:`, `dac.mcp4728:`, `dac.mcp4921:`,
`dac.mcp4922:`, `dac.mcp492x:` (shared SPI decoder) and `dac:` (generic
scaling). Decoder errors carry the byte offset, for example
`"dac.mcp4725: byte 1 command 5 is not 2 (write DAC) or 3 (write DAC+EEPROM)"`
or `"dac.mcp4725: byte 0 address 95 out of range 96..103"`. Validation is
ordered (address, channel, code, reference, power-down, gain, UDAC) and `Err`
never carries a partial frame. See `SPEC.md` for the full catalog.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.dac
```

Expected: the namespace check passes, 20 `[PASS]` lines, and a final
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`. Pinned values include
the MCP4725 fast frame `C4 0A BC`, the write-DAC frame `C4 40 AB C0`, the
MCP4728 multi-write channel matrix `40 42 44 46`, the MCP4922 frame
`F1 23` and the scaled anchors `4095 -> 4998779 uV` (5 V reference) and
`4095 @ gain 2 -> 4095000 uV` (2.048 V reference). See `SPEC.md` for the full
matrix.

## Limitations

- **No transport.** START/STOP/ACK, CS/LDAC/SHDN pin toggling, timing and
  readback of the MCP4725/MCP4728 read commands are the caller's job.
- **Integer truncation.** Every conversion multiplies first and divides once,
  truncating toward zero; full scale is `vref * (2^bits-1) / 2^bits`, one LSB
  below `vref`. Values are documented and pinned, not rounded.
- **Datasheet layouts only.** The dedicated MCP4728 "Write I2C Address Bits"
  command (C2 C1 C0 = 011) and the reference/PD/gain-only update commands
  (100/101/110) are not implemented; the address byte itself supports the
  programmable A2 A1 A0 bits.
- **No electrical modeling.** Settling time, EEPROM write time (up to 50 ms
  during which the part ignores commands), reference accuracy and noise are
  out of scope.
- **Gain validation where the silicon constrains it.** MCP4728 accepts the GX
  bit only when the internal reference is selected; with the external VDD
  reference `mcp4728_effective_gain` reports the forced 1x the silicon uses.
- No FFI, no `extern "C"` blocks, no unsafe code, no floats.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
