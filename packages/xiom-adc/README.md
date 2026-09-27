# xiom.adc

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) ADC conversion and configuration codecs:
> integer scaling to microvolts/millivolts, channel/mux and gain selection,
> reference selection, single-ended vs differential handling, sample-rate
> tables, averaging/oversampling helpers and an ADS1x15-style 16-bit config
> register codec.
> **Deps:** `xiom.std` only. The library module imports `xiom.convert`; the
> tests also use `xiom.test`, `xiom.io`, `xiom.string.compare` and
> `xiom.encoding.hex`.

## What it is

`xiom.adc` turns ADC conversion elements into values and byte vectors and
back, with integer math only (voltages are microvolts and nanovolts; there
is no float type anywhere):

- **Resolution and scale** -- 8..24 bits, unipolar full scale `2^bits - 1`,
  differential full-scale magnitude `2^(bits-1)`, gain validation;
- **Integer raw-to-voltage scaling** -- `vref_uv * raw / full-scale / gain`
  in microvolts, a millivolt view, the inverse `uv_to_raw` with a
  full-scale bound, and the per-LSB size in nanovolts;
- **Single-ended vs differential** -- mode constants and names, unsigned
  scaling and a two's complement path (`-2^(bits-1) .. 2^(bits-1)-1`
  interpreted over `-vref/gain .. +vref/gain`);
- **Channel and mux selection** -- the ADS1x15 multiplexer: four
  differential pairs and four single-ended inputs, with labels and
  validation rejecting pairs the hardware does not have;
- **Gain and reference selection** -- an integer gain factor, an internal
  2.048 V reference and a caller-supplied external reference in uV;
- **Sample-rate table** -- the ADS1115 (8/16/32/64/128/250/475/860 SPS) and
  ADS1015 (128/250/490/920/1600/2400/3300/3300 SPS) data-rate codes, with
  reverse lookup;
- **Averaging and oversampling** -- one-pass sum, truncated mean,
  half-away-from-zero rounded mean, min/max/sum statistics, and the
  extra-bits computation for power-of-two oversampling factors;
- **ADS1x15 config register** -- encode/decode of the 16-bit
  OS/MUX/PGA/MODE/DR/COMP_MODE/COMP_POL/COMP_LAT/COMP_QUE bitfield to and
  from the word and its two big-endian wire bytes, with a stable validation
  catalog and the documented power-on default `0x8583`.

Everything is a free function over `Int`, `Bool` and `Vec[UInt8]`, plus
two small struct types (`Ads1x15Config`, `AdcStats`). There is no I/O, no
triggering, no timing and no device state: the codec only scales, selects,
formats and validates. The error model is a deterministic `Err(Str)`
catalog (see `SPEC.md`); an `Err` never carries a half-built result.

## Install / use

```
xiom pkg install xiom.adc@0.1.0     # consumer
xiom pkg publish                    # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Quick start

```xi
use xiom.adc;
use xiom.io;

// Single-ended 16-bit code on the internal 2.048 V reference, gain 1:
let uv = adc_raw_to_uv(32767, 16, ADC_INTERNAL_REF_UV, 1);            // 1023984 uV
let mv = adc_raw_to_millivolts(32767, 16, ADC_INTERNAL_REF_UV, 1);    // 1023 mV

// Differential two's complement code (most negative code = -vref/gain):
let suv = adc_raw_to_uv_signed(-32768, 16, ADC_INTERNAL_REF_UV, 1);   // -2048000 uV
let raw = adc_uv_to_raw(1024000, 16, ADC_INTERNAL_REF_UV, 1);         // 32767

// Per-LSB size, kept integer as nanovolts:
let lsb = adc_lsb_nanovolts(16, ADC_INTERNAL_REF_UV, 1);              // 31250 nV

// Channel selection and labels:
let m = ads_mux_single(0);        // Ok(4): single-ended AIN0
let d = ads_mux_differential(2, 3); // Ok(3): AIN2-AIN3

// ADS1015/ADS1115 sample rate and PGA tables:
let sps1115 = ads_data_rate_sps(4, true);      // 128
let sps1015 = ads_data_rate_index(3300, false); // 6
let fsr = ads_pga_fsr_uv(2, true);             // 2048000 (uV, +/-2.048 V)

// Averaging / oversampling:
var samples = Vec[Int].new();
samples.push(1020);
samples.push(1030);
samples.push(1010);
let mean = adc_mean_rounded(&samples);          // 1020
let extra = adc_oversample_bits(16, 4);         // 18

// ADS1x15 configuration register:
let cfg = ads1x15_default_config();
let w = ads1x15_config_encode_word(&cfg);       // 34179 = 0x8583
let bytes = ads1x15_config_encode(&cfg);        // { 0x85, 0x83 }

// Single-shot AIN0 single-ended, +/-4.096 V, 860 SPS, comparator off:
let shot = Ads1x15Config{ os: ADS_OS_START; mux: ADS_MUX_SINGLE_0; pga: 1; mode: ADS_MODE_SINGLE_SHOT; dr: 7; comp_mode: ADS_COMP_TRADITIONAL; comp_pol: ADS_COMP_ACTIVE_LOW; comp_lat: ADS_COMP_NONLATCHING; comp_que: ADS_COMP_QUE_DISABLE; };
// ads1x15_config_encode_word(&shot) == 50147 = 0xC3E3
```

## API

All functions are free functions in module `xiom.adc`.

### Scaling and selection

| Function | Returns | Description |
|---|---|---|
| `adc_validate_resolution(bits)` | `Result[Unit, Str]` | Resolution must be 8..24. |
| `adc_full_scale(bits)` | `Int` | Unipolar full scale `2^bits - 1`, or -1. |
| `adc_diff_full_scale(bits)` | `Int` | Differential magnitude `2^(bits-1)`, or -1. |
| `adc_validate_gain(gain)` | `Result[Unit, Str]` | Gain must be >= 1. |
| `adc_reference_uv(sel, external_uv)` | `Result[Int, Str]` | Internal 2.048 V or external uV. |
| `adc_reference_name(sel)` | `Str` | `"internal"`, `"external"`, `"unknown"`. |
| `adc_validate_mode(mode)` | `Result[Unit, Str]` | 0 single-ended or 1 differential. |
| `adc_mode_name(mode)` | `Str` | `"single-ended"`, `"differential"`, `"unknown"`. |
| `adc_raw_to_uv(raw, bits, vref_uv, gain)` | `Result[Int, Str]` | `vref*raw/full-scale/gain` in uV. |
| `adc_raw_to_millivolts(raw, bits, vref_uv, gain)` | `Result[Int, Str]` | The uV result / 1000 (truncating). |
| `adc_lsb_nanovolts(bits, vref_uv, gain)` | `Result[Int, Str]` | One LSB in nV. |
| `adc_twos_complement(raw, bits)` | `Result[Int, Str]` | Interpret a raw code as signed. |
| `adc_raw_to_uv_signed(raw, bits, vref_uv, gain)` | `Result[Int, Str]` | Differential signed uV. |
| `adc_raw_to_millivolts_signed(raw, bits, vref_uv, gain)` | `Result[Int, Str]` | Differential signed mV. |
| `adc_uv_to_raw(uv, bits, vref_uv, gain)` | `Result[Int, Str]` | Inverse, bounded by `vref/gain`. |

### Averaging and oversampling

| Function | Returns | Description |
|---|---|---|
| `adc_sum(samples)` | `Int` | Raw sum (0 for an empty block). |
| `adc_mean(samples)` | `Result[Int, Str]` | Truncated mean. |
| `adc_mean_rounded(samples)` | `Result[Int, Str]` | Mean rounded half away from zero. |
| `adc_stats(samples)` | `Result[AdcStats, Str]` | count/min/max/sum in one pass. |
| `adc_oversample_shift(factor)` | `Int` | `log2(factor)` or -1. |
| `adc_oversample_bits(resolution, factor)` | `Result[Int, Str]` | `resolution + log2(factor)`, capped at 24. |

### ADS1x15

| Function | Returns | Description |
|---|---|---|
| `ads_mux_single(channel)` | `Result[Int, Str]` | Channel 0..3 -> MUX 4..7. |
| `ads_mux_differential(pos, neg)` | `Result[Int, Str]` | One of the four hardware pairs -> MUX 0..3. |
| `ads_mux_label(mux)` | `Str` | `"AIN0-AIN1"`..`"AIN3"` or `"unknown"`. |
| `ads_mux_is_single_ended(mux)` | `Bool` | True for MUX 4..7. |
| `ads_channel_label(channel)` | `Str` | `"AIN0"`..`"AIN3"` or `"unknown"`. |
| `ads_pga_fsr_uv(index, is_ads1115)` | `Int` | Full-scale range in uV, or -1. |
| `ads_pga_index(fsr_uv, is_ads1115)` | `Int` | Lowest matching PGA index, or -1. |
| `ads_data_rate_sps(index, is_ads1115)` | `Int` | Samples per second, or -1. |
| `ads_data_rate_index(sps, is_ads1115)` | `Int` | Lowest matching DR index, or -1. |
| `ads1x15_default_config()` | `Ads1x15Config` | The 0x8583 power-on default. |
| `ads1x15_config_encode_word(cfg)` | `Result[Int, Str]` | The 16-bit configuration word. |
| `ads1x15_config_encode(cfg)` | `Result[Vec[UInt8], Str]` | Two big-endian wire bytes. |
| `ads1x15_config_decode_word(word)` | `Result[Ads1x15Config, Str]` | Fields from the word. |
| `ads1x15_config_decode(data)` | `Result[Ads1x15Config, Str]` | Fields from the first two bytes. |

### Constants and types

```xi
pub const ADC_RES_MIN: Int = 8;
pub const ADC_RES_MAX: Int = 24;
pub const ADC_SINGLE_ENDED: Int = 0;
pub const ADC_DIFFERENTIAL: Int = 1;
pub const ADC_REF_INTERNAL: Int = 0;
pub const ADC_REF_EXTERNAL: Int = 1;
pub const ADC_INTERNAL_REF_UV: Int = 2048000;

pub const ADS_MUX_DIFF_0_1: Int = 0;
pub const ADS_MUX_DIFF_0_3: Int = 1;
pub const ADS_MUX_DIFF_1_3: Int = 2;
pub const ADS_MUX_DIFF_2_3: Int = 3;
pub const ADS_MUX_SINGLE_0: Int = 4;
pub const ADS_MUX_SINGLE_1: Int = 5;
pub const ADS_MUX_SINGLE_2: Int = 6;
pub const ADS_MUX_SINGLE_3: Int = 7;

pub const ADS_MODE_CONTINUOUS: Int = 0;
pub const ADS_MODE_SINGLE_SHOT: Int = 1;
pub const ADS_OS_IDLE: Int = 0;
pub const ADS_OS_START: Int = 1;

pub const ADS_COMP_TRADITIONAL: Int = 0;
pub const ADS_COMP_WINDOW: Int = 1;
pub const ADS_COMP_ACTIVE_LOW: Int = 0;
pub const ADS_COMP_ACTIVE_HIGH: Int = 1;
pub const ADS_COMP_NONLATCHING: Int = 0;
pub const ADS_COMP_LATCHING: Int = 1;
pub const ADS_COMP_QUE_ONE: Int = 0;
pub const ADS_COMP_QUE_TWO: Int = 1;
pub const ADS_COMP_QUE_FOUR: Int = 2;
pub const ADS_COMP_QUE_DISABLE: Int = 3;

pub type Ads1x15Config = {
  os: Int; mux: Int; pga: Int; mode: Int; dr: Int;
  comp_mode: Int; comp_pol: Int; comp_lat: Int; comp_que: Int;
}
pub type AdcStats = { count: Int; min: Int; max: Int; sum: Int; }
```

## Error model

Every fallible function returns `Result[T, Str]` with a stable, lowercase
`adc:` / `adc.ads1x15:` message. Boundary errors carry the offending value
(for example "adc: raw 4096 out of range 0..4095" or "adc.ads1x15: config
needs 2 bytes, have 1"). The config encoder validates fields in register
order OS, MUX, PGA, MODE, DR, COMP_MODE, COMP_POL, COMP_LAT, COMP_QUE and
`Err` never carries a partial buffer. See `SPEC.md` for the full catalog.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.adc
```

Expected: the namespace check passes, 18 `[PASS]` lines, and a final
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`. Pinned values
include the ADS1x15 default word `0x8583` (bytes `85 83`), the golden
configs `0xC3E3` (single-shot AIN0, 4.096 V, 860 SPS) and `0x301D`
(window comparator, continuous), the signed-scale anchors
`32767 -> 2047937 uV` and `-32768 -> -2048000 uV`, and the truncated
round-trip tolerance of 1 LSB. See `SPEC.md` for the full matrix.

## Limitations

- **No bus I/O, no triggering, no device state, no timing.** The codec
  formats registers and scales codes; writing the config register, starting
  a conversion and reading the result register are the transport's job.
- **Integer results.** All divisions truncate toward zero, so forward and
  inverse conversions can differ by up to 1 LSB; the round-trip test allows
  that. Callers needing exact rational arithmetic should keep uV.
- **Scale conventions.** Unipolar scaling uses `2^bits - 1` (the task
  formula); differential scaling uses `2^(bits-1)`, the magnitude of the
  most negative code, which matches the datasheet full-scale mapping.
- **Gain validation is minimal.** Any positive integer is accepted;
  power-of-two PGA gains are the usual case but not enforced.
- **Oversampling helpers are arithmetic only.** `adc_oversample_bits`
  assumes a power-of-two factor and enforces the 8..24 bit envelope; it
  does not model the noise budget. `adc_mean` works for any block size.
- **Table duplicates resolve low.** The ADS1015 0.512 V range is PGA 4 and
  the ADS1015 3300 SPS rate is DR 6 on reverse lookup.
- **ADS1x15 config format only.** No conversion-result register decode, no
  comparator threshold registers and no other ADC families.
- No FFI, no `extern "C"` blocks, no unsafe code, no floats.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
