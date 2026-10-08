# xiom.adc -- Specification

Version: 0.1.2 (stable; published on the XIOM registry).
Module: `src/adc.xi` (`module xiom.adc`).
Depends on `xiom.std`; the library module imports `xiom.convert`
(`int_to_string`); the tests also import `xiom.test`, `xiom.io`,
`xiom.string.compare` and `xiom.encoding.hex`.

## Scope

A pure-XIOM (no FFI) codec for the deterministic, integer-only layer of
analog-to-digital conversion:

- **Resolution and scale** -- 8..24 bit resolution with the unipolar full
  scale `2^bits - 1` and the differential full-scale magnitude
  `2^(bits-1)`, plus gain validation.
- **Channel / mux selection** -- the ADS1x15 input multiplexer: four
  differential pairs (AIN0-AIN1, AIN0-AIN3, AIN1-AIN3, AIN2-AIN3) and four
  single-ended inputs (AIN0..AIN3), with labels and validation.
- **Gain and reference selection** -- an integer gain factor, an internal
  2.048 V reference selector and an external reference in microvolts.
- **Single-ended vs differential** -- mode constants and names, unsigned
  scaling for single-ended codes and two's complement scaling for
  differential codes (including raw-code interpretation).
- **Sample-rate table** -- the ADS1115 (8..860 SPS) and ADS1015 (128..3300
  SPS) data-rate tables with forward and reverse index lookup.
- **Raw-to-millivolts scaling with integer math** --
  `vref_uv * raw / full-scale / gain` in microvolts, a millivolt view, the
  inverse `uv_to_raw`, and the per-LSB size in nanovolts.
- **Averaging / oversampling helpers** -- one-pass sum, truncated mean,
  half-away-from-zero rounded mean, min/max/sum statistics and the
  extra-bits computation for power-of-two oversampling factors.
- **ADS1x15-style 16-bit config register** -- encode/decode of the
  OS/MUX/PGA/MODE/DR/COMP_MODE/COMP_POL/COMP_LAT/COMP_QUE fields to and from
  the 16-bit word and its two big-endian wire bytes, with a stable
  validation catalog and the documented power-on default `0x8583`.
- A deterministic `Err(Str)` error catalog for malformed input and invalid
  fields.

## Non-goals

- **No bus I/O.** No I2C start/stop/ACK, no register writes, no conversion
  triggering, no readback. Everything is `Int` and `Vec[UInt8]` in memory.
- **No device state.** No conversion-result register, no busy polling, no
  comparator state, no driver.
- **No timing.** No conversion time, no sample scheduling, no clock
  configuration; the data-rate table is a value table, not a timer.
- **No float math and no `Vec[Float64]`.** Voltages are integer microvolts
  and nanovolts; results truncate (see below).
- **No calibration.** Offset/gain calibration coefficients, temperature
  compensation and noise analysis are out of scope.
- **No other ADCs.** The register codec is the ADS1x15 16-bit format; other
  vendors' register layouts are not modeled.
- **No electrical/datasheet modeling** beyond the documented tables (input
  range, reference values and data-rate codes).

## Integer scaling model

All scaling is integer microvolts with plain division that truncates toward
zero (verified on v0.61.3: `-7 / 2 = -3`). Each division truncates, so the
chain `vref_uv * raw / scale / gain` performs one truncation per division.

- **Unipolar (single-ended)**: codes `0..2^bits-1` map to
  `0..vref_uv/gain`; `uv = vref_uv * raw / (2^bits - 1) / gain`.
  At `raw = 2^bits-1`, `gain = 1` the result is exactly `vref_uv`.
- **Differential**: codes are `bits`-wide two's complement, interpreted
  over `-2^(bits-1) .. 2^(bits-1)-1`; the scale is the magnitude of the
  most negative code, so codes map to `-vref/gain .. +vref/gain`:
  `uv = vref_uv * signed / 2^(bits-1) / gain`. The most negative code
  (`-2^(bits-1)`) maps exactly to `-vref_uv/gain`.
- **Inverse**: `raw = uv * gain * (2^bits - 1) / vref_uv`, defined for
  `0 <= uv <= vref_uv / gain`; the maximum voltage maps to the maximum code.
- **LSB size**: `nv = vref_uv * 1000 / (2^bits - 1) / gain` (nanovolts).
  Example: 16-bit, 2.048 V, gain 1 -> 31250 nV = 31.25 uV.
- **Two's complement**: `adc_twos_complement(raw, bits)` accepts only a
  valid bit pattern `0..2^bits-1` and returns `raw - 2^bits` when the top
  bit is set; out-of-range input is rejected, never wrapped.

Overflow safety: the largest supported factor is `vref_uv * raw` with a
reference of a few volts and a 24-bit code (about 1e14) and the inverse
`uv * gain * fs` (about 1e16), both far inside the 64-bit `Int` range.

## Averaging and oversampling

- `adc_sum` -- the raw sum of a block (0 for an empty block).
- `adc_mean` -- `sum / count`, truncating toward zero.
- `adc_mean_rounded` -- `q = sum / count`, `r = sum % count`, and
  `|r| * 2 >= count` bumps `q` by one in the sign direction of `r`
  (half away from zero; `[100, 101] -> 101`, `[-7, -8] -> -8`).
- `adc_stats` -- `count`, `min`, `max`, `sum` in one pass.
- `adc_oversample_shift` -- `log2(factor)` for a power-of-two factor,
  else -1.
- `adc_oversample_bits` -- `resolution + log2(factor)`, validated to stay
  within 8..24. Averaging `4^n` samples yields `n` extra bits under ideal
  conditions; the helper computes the arithmetic, not the noise budget.

## ADS1x15 bit/byte-level description

### Configuration register layout

16 bits, transmitted most significant byte first.

| Bit(s) | Field | Values |
|---|---|---|
| 15 | OS | 0 no effect / not converting, 1 start single conversion |
| 14..12 | MUX | 0 `AIN0-AIN1`, 1 `AIN0-AIN3`, 2 `AIN1-AIN3`, 3 `AIN2-AIN3`, 4 `AIN0`, 5 `AIN1`, 6 `AIN2`, 7 `AIN3` |
| 11..9 | PGA | full-scale range index (table below) |
| 8 | MODE | 0 continuous, 1 single-shot (power-down) |
| 7..5 | DR | data-rate index (table below) |
| 4 | COMP_MODE | 0 traditional, 1 window |
| 3 | COMP_POL | 0 active low, 1 active high |
| 2 | COMP_LAT | 0 non-latching, 1 latching |
| 1..0 | COMP_QUE | 0 one conversion, 1 two, 2 four, 3 comparator disabled |

Word composition:

```
word = os*32768 + mux*4096 + pga*512 + mode*256 + dr*32
     + comp_mode*16 + comp_pol*8 + comp_lat*4 + comp_que
```

Encode emits `{ word / 256, word % 256 }` (big-endian); decode reads byte 0
as the high byte and ignores any further bytes.

### Power-on default

`ads1x15_default_config()` fields: OS 1, MUX 0 (AIN0-AIN1), PGA 2
(+/-2.048 V), MODE 1 (single-shot), DR 4 (128 SPS), COMP_MODE 0, COMP_POL 0,
COMP_LAT 0, COMP_QUE 3 (disabled) -> word `34179` = `0x8583` = bytes
`85 83`.

### MUX settings

| MUX | Inputs | Constant |
|---|---|---|
| 0 | AIN0 - AIN1 | `ADS_MUX_DIFF_0_1` |
| 1 | AIN0 - AIN3 | `ADS_MUX_DIFF_0_3` |
| 2 | AIN1 - AIN3 | `ADS_MUX_DIFF_1_3` |
| 3 | AIN2 - AIN3 | `ADS_MUX_DIFF_2_3` |
| 4 | AIN0 (single-ended) | `ADS_MUX_SINGLE_0` |
| 5 | AIN1 (single-ended) | `ADS_MUX_SINGLE_1` |
| 6 | AIN2 (single-ended) | `ADS_MUX_SINGLE_2` |
| 7 | AIN3 (single-ended) | `ADS_MUX_SINGLE_3` |

Only the four listed differential pairs exist on the hardware; any other
pair (including a reversed pair) is rejected. Labels: `"AIN0-AIN1"`,
`"AIN0-AIN3"`, `"AIN1-AIN3"`, `"AIN2-AIN3"`, `"AIN0"`, `"AIN1"`, `"AIN2"`,
`"AIN3"`, `"unknown"`.

### PGA full-scale ranges (uV)

| Index | ADS1115 | ADS1015 |
|---|---|---|
| 0 | +/-6144000 | +/-6144000 |
| 1 | +/-4096000 | +/-4096000 |
| 2 | +/-2048000 | +/-2048000 |
| 3 | +/-1024000 | +/-1024000 |
| 4 | +/-512000 | +/-512000 |
| 5 | +/-256000 | +/-512000 |
| 6 | +/-256000 | +/-512000 |
| 7 | +/-256000 | +/-512000 |

Reverse lookup `ads_pga_index` returns the lowest matching index
(`512000` -> 4 on both parts, `256000` -> 5 on the ADS1115).

### Data-rate codes (samples per second)

| Index | ADS1115 | ADS1015 |
|---|---|---|
| 0 | 8 | 128 |
| 1 | 16 | 250 |
| 2 | 32 | 490 |
| 3 | 64 | 920 |
| 4 | 128 | 1600 |
| 5 | 250 | 2400 |
| 6 | 475 | 3300 |
| 7 | 860 | 3300 |

Reverse lookup returns the lowest matching index; the ADS1015 3300 SPS rate
is available at index 6 and 7 and resolves to 6.

## Types

```xi
pub type Ads1x15Config = {
  os: Int; mux: Int; pga: Int; mode: Int; dr: Int;
  comp_mode: Int; comp_pol: Int; comp_lat: Int; comp_que: Int;
}
pub type AdcStats = { count: Int; min: Int; max: Int; sum: Int; }
```

Each `Ads1x15Config` member holds the raw bitfield value (not a decoded
voltage); `AdcStats.sum` is the raw sum so callers can chain
`adc_mean_of_sum`-style arithmetic themselves.

## API contract

All functions are free functions in module `xiom.adc`; there are no methods
and no state. Every fallible function validates in the order listed and
returns `Err` without a partial result; error text is stable.

```xi
pub fn adc_validate_resolution(bits: Int) -> Result[Unit, Str]
pub fn adc_full_scale(bits: Int) -> Int
pub fn adc_diff_full_scale(bits: Int) -> Int
pub fn adc_validate_gain(gain: Int) -> Result[Unit, Str]
pub fn adc_reference_uv(sel: Int, external_uv: Int) -> Result[Int, Str]
pub fn adc_reference_name(sel: Int) -> Str
pub fn adc_validate_mode(mode: Int) -> Result[Unit, Str]
pub fn adc_mode_name(mode: Int) -> Str
pub fn adc_raw_to_uv(raw: Int, bits: Int, vref_uv: Int, gain: Int) -> Result[Int, Str]
pub fn adc_raw_to_millivolts(raw: Int, bits: Int, vref_uv: Int, gain: Int) -> Result[Int, Str]
pub fn adc_lsb_nanovolts(bits: Int, vref_uv: Int, gain: Int) -> Result[Int, Str]
pub fn adc_twos_complement(raw: Int, bits: Int) -> Result[Int, Str]
pub fn adc_raw_to_uv_signed(raw: Int, bits: Int, vref_uv: Int, gain: Int) -> Result[Int, Str]
pub fn adc_raw_to_millivolts_signed(raw: Int, bits: Int, vref_uv: Int, gain: Int) -> Result[Int, Str]
pub fn adc_uv_to_raw(uv: Int, bits: Int, vref_uv: Int, gain: Int) -> Result[Int, Str]
pub fn adc_sum(samples: &Vec[Int]) -> Int
pub fn adc_mean(samples: &Vec[Int]) -> Result[Int, Str]
pub fn adc_mean_rounded(samples: &Vec[Int]) -> Result[Int, Str]
pub fn adc_stats(samples: &Vec[Int]) -> Result[AdcStats, Str]
pub fn adc_oversample_shift(factor: Int) -> Int
pub fn adc_oversample_bits(resolution: Int, factor: Int) -> Result[Int, Str]
pub fn ads_mux_single(channel: Int) -> Result[Int, Str]
pub fn ads_mux_differential(pos: Int, neg: Int) -> Result[Int, Str]
pub fn ads_mux_label(mux: Int) -> Str
pub fn ads_mux_is_single_ended(mux: Int) -> Bool
pub fn ads_channel_label(channel: Int) -> Str
pub fn ads_pga_fsr_uv(index: Int, is_ads1115: Bool) -> Int
pub fn ads_pga_index(fsr_uv: Int, is_ads1115: Bool) -> Int
pub fn ads_data_rate_sps(index: Int, is_ads1115: Bool) -> Int
pub fn ads_data_rate_index(sps: Int, is_ads1115: Bool) -> Int
pub fn ads1x15_default_config() -> Ads1x15Config
pub fn ads1x15_config_encode_word(cfg: &Ads1x15Config) -> Result[Int, Str]
pub fn ads1x15_config_encode(cfg: &Ads1x15Config) -> Result[Vec[UInt8], Str]
pub fn ads1x15_config_decode_word(word: Int) -> Result[Ads1x15Config, Str]
pub fn ads1x15_config_decode(data: &Vec[UInt8]) -> Result[Ads1x15Config, Str]
```

### Semantics and validation order

`adc_validate_resolution(bits)` / `adc_full_scale(bits)` /
`adc_diff_full_scale(bits)`
: 8..24 valid; the accessors return -1 for an invalid resolution
  (`full_scale = 2^bits - 1`, `diff_full_scale = 2^(bits-1)`).

`adc_validate_gain(gain)`
: Any `gain >= 1`; error otherwise.

`adc_reference_uv(sel, external_uv)`
: 1. selector 0 -> the internal `ADC_INTERNAL_REF_UV` = 2048000 uV
  (external value ignored);
  2. selector 1 -> `external_uv` when positive, else the external error;
  3. any other selector -> the selector error.

`adc_reference_name(sel)` / `adc_mode_name(mode)` /
`ads_mux_label(mux)` / `ads_channel_label(channel)`
: Pure name lookups; `"unknown"` for unrecognized values, never fail.

`adc_validate_mode(mode)`
: 0 (`ADC_SINGLE_ENDED`) or 1 (`ADC_DIFFERENTIAL`).

`adc_raw_to_uv(raw, bits, vref_uv, gain)`
: 1. bits outside 8..24 -> resolution error;
  2. `vref_uv <= 0` -> vref error;
  3. `gain < 1` -> gain error;
  4. raw outside `0..2^bits-1` -> raw error;
  5. `vref_uv * raw / (2^bits - 1) / gain`.

`adc_raw_to_millivolts(...)`
: `adc_raw_to_uv(...)` then a truncating division by 1000; same errors.

`adc_lsb_nanovolts(bits, vref_uv, gain)`
: Validation steps 1..3; `vref_uv * 1000 / (2^bits - 1) / gain`.

`adc_twos_complement(raw, bits)`
: 1. bits outside 8..24 -> resolution error;
  2. raw outside `0..2^bits-1` -> raw error;
  3. `raw >= 2^(bits-1)` -> `raw - 2^bits`, else `raw`.

`adc_raw_to_uv_signed(raw, bits, vref_uv, gain)`
: 1..3 as above; 4. raw outside `-2^(bits-1) .. 2^(bits-1)-1` -> signed raw
  error; 5. `vref_uv * raw / 2^(bits-1) / gain`.

`adc_uv_to_raw(uv, bits, vref_uv, gain)`
: 1..3 as above; 4. `uv < 0` or `uv > vref_uv / gain` -> value error;
  5. `uv * gain * (2^bits - 1) / vref_uv`.

`adc_sum` / `adc_mean` / `adc_mean_rounded` / `adc_stats`
: Operate on `&Vec[Int]`; empty blocks: sum = 0, the others the no-samples
  error. Mean truncates; rounded mean rounds half away from zero.

`adc_oversample_shift(factor)` / `adc_oversample_bits(resolution, factor)`
: factor must be a power of two `>= 1`; effective bits must stay in 8..24.
  The shift lookup returns -1 for invalid factors and never fails; the
  bits helper returns the errors below.

`ads_mux_single(channel)`
: 0..3 -> `4 + channel`; otherwise the single-ended channel error.

`ads_mux_differential(pos, neg)`
: 1. either input outside 0..3 -> the channel error (pos checked first);
  2. the pair must be one of (0,1), (0,3), (1,3), (2,3) -> its MUX value;
  3. otherwise the unsupported-pair error naming both inputs.

`ads_mux_is_single_ended(mux)`
: True exactly for 4..7.

`ads_pga_fsr_uv(index, is_ads1115)` / `ads_data_rate_sps(index, is_ads1115)`
: Table lookups; -1 for an index outside 0..7, never fail.

`ads_pga_index(fsr_uv, is_ads1115)` / `ads_data_rate_index(sps, is_ads1115)`
: Lowest matching index or -1.

`ads1x15_config_encode_word(cfg)`
: Fields validated in register order OS, MUX, PGA, MODE, DR, COMP_MODE,
  COMP_POL, COMP_LAT, COMP_QUE; the first out-of-range field produces its
  error. The word is the composition formula above.

`ads1x15_config_encode(cfg)`
: The word, then `{ word / 256, word % 256 }`.

`ads1x15_config_decode_word(word)`
: 1. word outside 0..65535 -> word error;
  2. extract `os = (word/32768)%2`, `mux = (word/4096)%8`,
  `pga = (word/512)%8`, `mode = (word/256)%2`, `dr = (word/32)%8`,
  `comp_mode = (word/16)%2`, `comp_pol = (word/8)%2`,
  `comp_lat = (word/4)%2`, `comp_que = word%4`. Every valid word decodes.

`ads1x15_config_decode(data)`
: 1. fewer than 2 bytes -> the needs-2-bytes error;
  2. `hi * 256 + lo`, then the word decoder. Extra bytes are ignored.

## Error string catalog

| Condition | Error text |
|---|---|
| Resolution outside 8..24 | `adc: resolution N out of range 8..24` |
| Gain below 1 | `adc: gain N must be at least 1` |
| Reference selector not 0/1 | `adc: reference selector N is not 0 or 1` |
| External reference not positive | `adc: external reference N uV must be positive` |
| Input mode not 0/1 | `adc: mode N is not 0 (single-ended) or 1 (differential)` |
| Non-positive reference | `adc: vref N uV must be positive` |
| Unsigned raw code out of range | `adc: raw N out of range 0..M` |
| Signed raw code out of range | `adc: signed raw N out of range -M..P` |
| Voltage out of range for the inverse | `adc: value N uV out of range 0..M` |
| Empty sample block | `adc: no samples` |
| Oversampling factor not a power of two | `adc: oversampling factor N is not a power of two` |
| Effective resolution leaves 8..24 | `adc: oversampled resolution N out of range 8..24` |
| Single-ended channel outside 0..3 | `adc.ads1x15: single-ended channel N out of range 0..3` |
| Differential input outside 0..3 | `adc.ads1x15: channel N out of range 0..3` |
| Pair not on the hardware | `adc.ads1x15: differential pair AINp-AINn is not supported` |
| OS field outside 0..1 | `adc.ads1x15: os N out of range 0..1` |
| MUX field outside 0..7 | `adc.ads1x15: mux N out of range 0..7` |
| PGA field outside 0..7 | `adc.ads1x15: pga N out of range 0..7` |
| MODE field outside 0..1 | `adc.ads1x15: mode N out of range 0..1` |
| DR field outside 0..7 | `adc.ads1x15: dr N out of range 0..7` |
| COMP_MODE field outside 0..1 | `adc.ads1x15: comp_mode N out of range 0..1` |
| COMP_POL field outside 0..1 | `adc.ads1x15: comp_pol N out of range 0..1` |
| COMP_LAT field outside 0..1 | `adc.ads1x15: comp_lat N out of range 0..1` |
| COMP_QUE field outside 0..3 | `adc.ads1x15: comp_que N out of range 0..3` |
| Config word outside 0..65535 | `adc.ads1x15: config word N out of range 0..65535` |
| Config buffer shorter than 2 bytes | `adc.ads1x15: config needs 2 bytes, have N` |

## Complexity

| Operation | Time | Space |
|---|---|---|
| Validators, names, mux/PGA/rate lookups, config codec | O(1) | O(1) |
| `adc_raw_to_*`, `adc_uv_to_raw`, `adc_lsb_nanovolts` | O(1) | O(1) |
| `adc_sum`, `adc_mean`, `adc_mean_rounded`, `adc_stats` | O(n) | O(1) |
| `adc_oversample_shift` / `adc_oversample_bits` | O(log factor) | O(1) |

## Constants

```xi
pub const ADC_RES_MIN: Int = 8;
pub const ADC_RES_MAX: Int = 24;
pub const ADC_SINGLE_ENDED: Int = 0;
pub const ADC_DIFFERENTIAL: Int = 1;
pub const ADC_REF_INTERNAL: Int = 0;
pub const ADC_REF_EXTERNAL: Int = 1;
pub const ADC_INTERNAL_REF_UV: Int = 2048000;
pub const ADS_MUX_DIFF_0_1: Int = 0;   // .. ADS_MUX_SINGLE_3 = 7
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
```

## Test plan

`tests/test_conformance.xi` (`module adc_tests`, 18 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. resolution 8..24: validation, pinned full scales 255/4095/65535/
   16777215, differential magnitudes 128/32768/8388608, -1 for 7 and 25;
2. gain: 1/128/3 accepted, 0 and -4 rejected;
3. reference selection: internal 2048000 uV (external value ignored),
   external 3300000 uV, external 0/-1 rejected, selector 2 rejected, names;
4. input mode: constants and names, 2 and -1 rejected;
5. unipolar scaling: pinned values (2048->2048500, 255@gain 2->2500000,
   24-bit max->2500000, 32767->1023984), raw/vref/gain/resolution errors;
6. millivolts and LSB nanovolts: 4095->4096 mV, 31250 nV and 1000244 nV
   pinned, 9803921 nV for the gain-2 8-bit case;
7. two's complement: 0x8000->-32768, 0xFFFF->-1, 12-bit and 8-bit cases,
   out-of-range codes rejected;
8. differential scaling: 32767->2047937 uV, -32768->-2048000 uV,
   -1->-62 uV (truncation toward zero), gain 2, signed millivolts, signed
   raw range errors;
9. inverse: 1024000 uV->32767, 2048000 uV->65535, full-scale bound and
   negative errors, round-trip within 1 LSB over pinned codes;
10. mux mapping: constants 0..7, single/differential mapping, all labels,
    single-ended predicate, channel labels;
11. mux validation: channel range and unsupported-pair errors (AIN0-AIN2,
    AIN2-AIN0, AIN3-AIN1);
12. PGA: both full-scale tables for all eight indices, invalid index -1,
    reverse lookup and -1 for an unknown range;
13. data rates: both tables for all eight indices, invalid index -1,
    reverse lookup (including ADS1015 3300 -> 6);
14. default config: field-by-field 0x8583, word 34179, big-endian bytes
    `85 83`, decode from word and from bytes, trailing bytes ignored;
15. golden configs: single-shot AIN0 single-ended 4.096 V 860 SPS ->
    0xC3E3 and a window-comparator continuous config -> 0x301D, both
    decoded back field by field;
16. config validation: one pinned message per field, word -1/65536, short
    and empty buffers, encode error propagation;
17. averaging: sum/mean/rounded mean (including 100.5 -> 101 and
    -7.5 -> -8), stats min/max/sum, empty-block errors;
18. oversampling shift/bits (16->18, 256->24, overflow and non-power-of-two
    errors) plus codec determinism.

Fixtures: hex literals come from `xiom.encoding.hex`; all sample vectors
are built in-test with explicit pushes. No `Str` value is compared with
`==` (BUG 17 discipline); labels and error messages go through
`xiom.string.compare.str_compare`. All `Vec` element reads are bound to
typed locals and `Vec[UInt8]` bytes are widened with `& 0xFF`.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.adc
```

Last verified: compiler 0.61.3,
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Known limitations

- No transport, no timing, no device state and no calibration (see
  Non-goals). The codec formats registers and scales codes; triggering
  conversions and reading results is the transport's job.
- The unipolar scale uses `2^bits - 1` (the task formula) while the
  differential scale uses `2^(bits-1)` (the datasheet magnitude); the two
  conventions are documented and pinned separately.
- Integer truncation means the forward and inverse conversions can differ
  by up to 1 LSB; callers needing exact rational arithmetic should keep
  microvolts and avoid the inverse.
- `adc_validate_gain` accepts any positive integer; non-power-of-two gains
  are mathematically supported but unusual for PGAs.
- Oversampling factors must be powers of two for `adc_oversample_bits`;
  `adc_mean` itself works for any block size.
- PGA and data-rate reverse lookups resolve duplicates to the lowest index
  (ADS1015 0.512 V -> PGA 4, ADS1015 3300 SPS -> DR 6).
- Only the ADS1x15 config register format is modeled; no conversion-result
  register decode and no other ADC families.
- No FFI, no `extern "C"` blocks, no unsafe code, no floats.

## Compiler / stdlib notes for v0.61.3

- Free functions only: no methods, no lambdas, no `Vec[fn]` dispatch, no
  `Vec[StructType]`.
- `Ok`/`Err` construction is confined to the tiny leaf helpers
  (`_ok_unit`/`_err_unit`, `_ok_int`/`_err_int`, `_ok_bytes`/`_err_bytes`,
  `_ok_cfg`/`_err_cfg`, `_ok_stats`/`_err_stats`), because constructing
  Results directly inside other functions miscompiles.
- No `Str` comparison happens in the library module; the tests compare
  labels and messages through `xiom.string.compare.str_compare` after the
  values are bound to typed locals (BUG 17).
- `&struct.field` is never passed as a `&Vec[UInt8]` parameter (that yields
  an empty vector); struct fields are first bound to typed locals.
- Every `Vec[UInt8]` byte read is widened with `(x as Int) & 0xFF` before
  entering Int arithmetic.
- The config validator takes nine scalar fields rather than a struct
  reference, so no reference travels beyond the function that received it.
- The test helper `cfg_eq` takes `&Ads1x15Config` references, so comparing
  the same config value several times does not move it.
- Bit composition and extraction use multiplication and division by powers
  of two, never a shift on a value that could carry the sign bit; division
  truncates toward zero.
- Dynamic error strings are built with `xiom.convert.int_to_string` (the
  `xiom.convert` module, imported as `convert`).
- The package declares no `extern "C"` blocks (no FFI).

## Contracts (batch #38 hardening pass, 2026-10-08)

Runtime-checkable `ensures:` clauses added to `src/adc.xi` in the batch #38
hardening pass (compiler v0.64.0; `package.xi` is left for the coordinator to
bump at integration). 69 clauses over the 17 contracted functions (the
private helper `_pow2` plus the public accessors below); all are `ensures:`
with no `requires:`, so the accepted-input domain is unchanged. Two
consecutive `& .\scripts\port.ps1 -Package xiom.adc -TimeoutSec 60` runs ended
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)` with the clauses
active (20.73 s and 20.47 s); the 18-test conformance suite exercises every
entry point and no clause trapped, so none was dropped.

Every clause is **runtime-checked** (no Z3 claim; `xiom-verify` was not run,
and per the batch #37 finding a bare `xiom-verify` `[OK] VERIFIED` can be a
vacuous UNSAT). Clause inputs are parameters or parameter fields only;
`AdcStats` and `Ads1x15Config` result payload fields are never read (the
three `Result[Ads1x15Config, Str]` functions constrain only the word/length
bands and `result is Ok`/`result is Err`); `ads1x15_default_config` is a
plain struct return and is read field by field through `result`. Module
constants are inlined as integer literals and no clause indexes a vector or
compares a `Str`. The only clause calls are the non-re-entrant definitional
ones: `_pow2` (`adc_full_scale`, `adc_diff_full_scale` and the scaling
formulas) and `adc_sum` (`adc_mean`); neither callee calls its caller. Every
guarded division is the aiff `info.sample_rate > 0` / eeprom `page_size > 0`
pattern, where the divisor is positive whenever the evaluator reaches it;
`adc_uv_to_raw`'s upper bound is stated in the equivalent Ok-guarded
contrapositive form `result is Ok => uv <= vref_uv / gain` so the variable
divisor never appears in an antecedent. Every clause holds for hand-built
structs: the config field guards mirror the source's own validation
branches, and hand-built out-of-range fields are rejected exactly as
claimed.

Two planned shapes were re-expressed (family kept), not dropped:

- `adc_oversample_bits`'s general `resolution + shift > 24 => Err` cannot be
  written without calling `adc_oversample_shift`, which is not on the
  approved cross-call list; it is replaced by the boundary pair
  `resolution == 24 && factor > 1 => result is Err` and
  `resolution == 23 && factor > 2 => result is Err`, both true for every
  integer factor (non-power-of-two factors already fail the factor check).
- `adc_uv_to_raw`'s `uv < 0 || uv > vref_uv / gain => Err` is split into
  `uv < 0 => result is Err` plus the Ok-guarded contrapositive above,
  keeping the variable divisor out of clause antecedents.

| Function | Clause(s) added | Class |
|---|---|---|
| `_pow2` (private) | `k == 0 => result == 1`; `k == 8 => result == 256`; `k == 16 => result == 65536` | runtime-checked |
| `adc_validate_resolution` | `bits < 8 \|\| bits > 24 => result is Err`; `bits >= 8 && bits <= 24 => result is Ok` | runtime-checked |
| `adc_full_scale` | `bits < 8 \|\| bits > 24 => result == -1`; `bits >= 8 && bits <= 24 => result == _pow2(bits) - 1` | runtime-checked |
| `adc_diff_full_scale` | `bits < 8 \|\| bits > 24 => result == -1`; `bits >= 8 && bits <= 24 => result == _pow2(bits - 1)` | runtime-checked |
| `adc_raw_to_uv` | `bits < 8 \|\| bits > 24 => result is Err`; `vref_uv <= 0 => result is Err`; `gain < 1 => result is Err`; `raw < 0 \|\| raw > _pow2(bits) - 1 => result is Err`; valid path `=> result.value == vref_uv * raw / (_pow2(bits) - 1) / gain` | runtime-checked |
| `adc_twos_complement` | `bits < 8 \|\| bits > 24 => result is Err`; `raw < 0 \|\| raw > _pow2(bits) - 1 => result is Err`; top bit set `=> result.value == raw - _pow2(bits)`; top bit clear `=> result.value == raw` | runtime-checked |
| `adc_raw_to_uv_signed` | `bits < 8 \|\| bits > 24 => result is Err`; `vref_uv <= 0 => result is Err`; `gain < 1 => result is Err`; signed raw out of range `=> result is Err`; valid path `=> result.value == vref_uv * raw / _pow2(bits - 1) / gain` | runtime-checked |
| `adc_uv_to_raw` | `bits < 8 \|\| bits > 24 => result is Err`; `vref_uv <= 0 => result is Err`; `gain < 1 => result is Err`; `uv < 0 => result is Err`; `result is Ok => uv <= vref_uv / gain`; `result is Ok => result.value == uv * gain * (_pow2(bits) - 1) / vref_uv` | runtime-checked |
| `adc_sum` | `samples.len() == 0 => result == 0` | runtime-checked |
| `adc_mean` | `samples.len() == 0 => result is Err`; `samples.len() > 0 => result.value == adc_sum(samples) / samples.len()` | runtime-checked |
| `adc_oversample_bits` | `resolution < 8 \|\| resolution > 24 => result is Err`; `factor < 1 => result is Err`; `resolution == 24 && factor > 1 => result is Err`; `resolution == 23 && factor > 2 => result is Err`; `factor == 1 => result.value == resolution`; `resolution <= 23 && factor == 2 => result.value == resolution + 1` | runtime-checked |
| `ads_mux_single` | `channel < 0 \|\| channel > 3 => result is Err`; `channel >= 0 && channel <= 3 => result.value == 4 + channel` | runtime-checked |
| `ads_mux_differential` | pos/neg outside 0..3 `=> result is Err`; `(0,1) -> 0`, `(0,3) -> 1`, `(1,3) -> 2`, `(2,3) -> 3`; every other in-range pair `=> result is Err` | runtime-checked |
| `ads1x15_default_config` | `result.os == 1`; `result.mux == 0`; `result.pga == 2`; `result.mode == 1`; `result.dr == 4`; `result.comp_mode == 0`; `result.comp_pol == 0`; `result.comp_lat == 0`; `result.comp_que == 3` | runtime-checked |
| `ads1x15_config_encode_word` | one `=> result is Err` clause per out-of-range field (os 0..1, mux/pga/dr 0..7, mode/comp_mode/comp_pol/comp_lat 0..1, comp_que 0..3); all-valid `=> result.value ==` the nine-term register formula | runtime-checked |
| `ads1x15_config_decode_word` | `word < 0 \|\| word > 65535 => result is Err`; `word >= 0 && word <= 65535 => result is Ok` | runtime-checked |
| `ads1x15_config_decode` | `data.len() < 2 => result is Err`; `data.len() >= 2 => result is Ok` | runtime-checked |
