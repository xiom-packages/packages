# xiom.chromatography -- specification

Pure XIOM deterministic chromatography data model. No FFI, no floating point,
no `Vec[Float64]`, no `Vec[StructType]`: every stored quantity is an `Int` and
every table is a set of parallel `Vec[Int]`.

## 1. Fixed-point convention

- Scale: `CHROM_FP_SCALE = 10000` (1e-4). A stored value `v` represents
  `v / 10000` in real units: `12345` means `1.2345`.
- All fixed-point quantities are validated to lie in
  `0 .. CHROM_FP_MAX`, where `CHROM_FP_MAX = 1000000000` (1e9, i.e.
  `100000.0000`), unless a stricter per-function rule is stated.
- **Division truncates toward zero** (verified: `-7 / 2 = -3`); the remainder
  keeps the dividend sign. Every formula below divides at most once per
  truncation step, and the step is called out explicitly.
- Overflow guards: products are bounded by the documented input caps --
  single quantities by `CHROM_FP_MAX` (1e9), summed areas by
  `CHROM_TOTAL_MAX` (1e12), alkane carbon numbers by `CHROM_CARBON_MAX`
  (1000). The largest intermediate in the module is
  `100*10000*1000*1e9 = 1e18 < 2^63`.
- Range comparisons are inclusive unless stated otherwise.

## 2. Data model

A **peak table** is four parallel vectors of equal length `n`:

| field  | meaning                        | unit            |
|--------|--------------------------------|-----------------|
| times  | retention time                 | 1e-4 min        |
| areas  | integrated peak area           | 1e-4 area units |
| heights| peak height                    | 1e-4 signal     |
| widths | width at half height           | 1e-4 min        |

A **baseline segment table** is four parallel vectors of equal length `n`:
`starts`, `ends`, `levels0`, `levels1`. Segment `i` covers
`[starts[i], ends[i]]` (inclusive at both ends, so touching segments share
their boundary and the earlier segment wins there) and interpolates linearly
from `levels0[i]` to `levels1[i]`.

## 3. Constants

| constant             | value            | meaning                                  |
|----------------------|------------------|------------------------------------------|
| `CHROM_FP_SCALE`     | 10000            | fixed-point scale 1e-4                   |
| `CHROM_FP_MAX`       | 1000000000       | largest single quantity                  |
| `CHROM_TOTAL_MAX`    | 1000000000000    | largest total area                       |
| `CHROM_AREA_100`     | 1000000          | 100 percent in 1e-4 percent units        |
| `CHROM_CARBON_MAX`   | 1000             | largest alkane carbon number             |
| `CHROM_ASYM_TAIL_MIN`| 11000            | tailing strictly above 1.1000            |
| `CHROM_ASYM_FRONT_MAX`| 9000            | fronting strictly below 0.9000           |
| `CHROM_SN_MIN`       | 100000           | low S/N strictly below 10.0000           |
| `CHROM_RES_BASELINE` | 15000            | baseline separation at or above 1.5000   |
| `CHROM_RES_CRITICAL` | 10000            | unresolved strictly below 1.0000         |
| `CHROM_QC_OK`        | 0                | no flag                                  |
| `CHROM_QC_TAILING`   | 1                | tailing QC bit                           |
| `CHROM_QC_FRONTING`  | 2                | fronting QC bit                          |
| `CHROM_QC_LOW_SN`    | 4                | low signal-to-noise QC bit               |
| `CHROM_QC_UNRESOLVED`| 8                | unresolved pair QC bit                   |
| `CHROM_TABLE_HEADER` | `#chromatography peaks v1` | exact codec header line        |

## 4. Validation

`chrom_peak_validate(times, areas, heights, widths) -> Result[Unit, Str]`

Checks, in order, returning the first violation:

1. `areas.len() == times.len()` (`"chrom: table length mismatch times=N areas=M"`),
   then the same for `heights` and `widths` (in that order).
2. Per peak `i`, in index order, the fields in the order time, area, height,
   width: range `0..CHROM_FP_MAX`
   (`"chrom: peak I <field> out of range 0..1000000000"`).
3. Then positivity: `area > 0`, `height > 0`, `width > 0` (same wording with
   `must be positive`).
4. Then order: for `i > 0`, `times[i] > times[i-1]`
   (`"chrom: peak I time not increasing after peak P"`).

An empty table (all lengths 0) is valid. `t = 0` is valid.

## 5. Area math

`chrom_peak_total_area(areas) -> Result[Int, Str]`

Sum with the guard `total <= CHROM_TOTAL_MAX` after each addition.
Errors: `"chrom: no peaks"` (empty), `"chrom: negative area at index I"`,
`"chrom: total area exceeds 1000000000000"`.

`chrom_peak_normalize_areas(areas) -> Result[Vec[Int], Str]`

Normalizes to 100 percent in 1e-4 percent units. With `cum_i` the running sum
and `total` the full sum (validated as above, plus `total > 0`):

```
norm_i = (cum_i * 1000000) / total - (cum_{i-1} * 1000000) / total
```

Both quotients truncate toward zero (values are non-negative). The sum
telescopes to exactly `1000000`, earlier peaks keep the truncated share and
the last nonzero peak absorbs the residual; a zero area yields 0. Examples:

| areas                       | normalized                         |
|-----------------------------|------------------------------------|
| `[30000, 10000]`            | `[750000, 250000]`                 |
| `[10000, 10000, 10000]`     | `[333333, 333333, 333334]`         |
| `[10000, 0, 30000]`         | `[250000, 0, 750000]`              |

Errors: `"chrom: no peaks to normalize"`, `"chrom: negative area at index I"`,
`"chrom: total area exceeds 1000000000000"`, `"chrom: total area is zero"`.

## 6. Resolution

`chrom_peak_resolution(t1, w1, t2, w2) -> Result[Int, Str]`

Half-height resolution:

```
R = 1.18 * (t2 - t1) / (w1 + w2)          real units
R = 11800 * (t2_fp - t1_fp) / (w1_fp + w2_fp)   fixed point, one truncating division
```

`t1`, `t2` are validated in `0..CHROM_FP_MAX` (t1 first), `w1`, `w2` in
`1..CHROM_FP_MAX` (w1 first), then `t2 > t1`.

Errors: `"chrom.resolution: t1 out of range 0..1000000000"`,
`"... t2 ..."`, `"... w1 out of range 1..1000000000"`,
`"... w2 ..."`, `"chrom.resolution: t2 must be greater than t1"`.

Pinned: `(10000,1000,15000,1000) -> 29500` (2.9500);
`(10000,1000,10101,1000) -> 595` (118.59/200 truncates).

`chrom_table_adjacent_resolution(times, widths, pair_index)`

Requires equal lengths and `n >= 2`, then `0 <= pair_index <= n-2`, and
delegates to `chrom_peak_resolution`. Errors:
`"chrom.resolution: table length mismatch times=N widths=M"`,
`"chrom.resolution: table needs at least 2 peaks"`,
`"chrom.resolution: adjacent index I out of range 0..K"`.

## 7. Kovats retention index

`chrom_kovats_index(anchor_carbon, anchor_time, tx) -> Result[Int, Str]`

The anchor table is caller-supplied: `anchor_carbon[i]` is the alkane carbon
number, `anchor_time[i]` its retention time (1e-4 min). Requirements: equal
lengths `>= 2`, both strictly increasing, carbon in `0..1000`, times in
`0..CHROM_FP_MAX`, and `tx` inside `[anchor_time[0], anchor_time[last]]`.

Between the bracketing anchors `(c0,t0)`, `(c1,t1)`:

```
RI = 100*c0 + 100*(c1-c0)*(tx-t0)/(t1-t0)     real units
RI_fp = c0*100*10000 + (100*10000*(c1-c0)*(tx-t0)) / (t1-t0)
```

one truncating division; an exact anchor hit returns `c*100*10000` exactly.
With consecutive anchors (`c1 = c0+1`) this is the standard Kovats formula.
The largest numerator is `1e6 * 1000 * 1e9 = 1e18`.

Errors, in order: `"chrom.kovats: anchor table length mismatch carbon=N time=M"`,
`"chrom.kovats: anchors need at least 2 points"`,
`"chrom.kovats: retention time out of range 0..1000000000"`,
then per anchor index in order: `"chrom.kovats: anchor I carbon out of range 0..1000"`,
`"chrom.kovats: anchor I time out of range 0..1000000000"`,
`"chrom.kovats: anchor carbon not increasing at I"`,
`"chrom.kovats: anchor time not increasing at I"` (carbon checked before time
at each index), and finally
`"chrom.kovats: retention time T outside anchor range A..B"`.

Pinned: anchors `(10,12,14)` at `(100000,200000,300000)`: `tx=150000` gives
`11000000` (RI 1100), `tx=200000` gives `12000000`; consecutive `(7,8)` at
`(5000,15000)`: `tx=12500` gives `7750000` (RI 775).

## 8. Signal-to-noise and QC flags

`chrom_signal_to_noise(height, noise) -> Result[Int, Str]`

```
SN_fp = height_fp * 10000 / noise_fp      one truncating division
```

`height` in `0..CHROM_FP_MAX`, `noise` in `1..CHROM_FP_MAX`.
Errors: `"chrom.sn: height out of range 0..1000000000"`,
`"chrom.sn: noise out of range 1..1000000000"`.
Pinned: `(10000, 3) -> 3333`.

`chrom_asymmetry_flag(asymmetry) -> Result[Int, Str]`

`> 11000` -> `CHROM_QC_TAILING (1)`; `< 9000` -> `CHROM_QC_FRONTING (2)`;
otherwise `CHROM_QC_OK (0)`. The exact boundaries 9000 and 11000 are
symmetric. `asymmetry` in `1..CHROM_FP_MAX`; error
`"chrom.qc: asymmetry out of range 1..1000000000"`.

`chrom_qc_flags(height, noise, asymmetry, resolution) -> Result[Int, Str]`

Validates `resolution` in `0..CHROM_FP_MAX` first, then S/N, then asymmetry,
and OR-s the bits:

- `CHROM_QC_LOW_SN` when `SN_fp < CHROM_SN_MIN`;
- `CHROM_QC_TAILING` / `CHROM_QC_FRONTING` from the asymmetry flag;
- `CHROM_QC_UNRESOLVED` when `resolution < CHROM_RES_CRITICAL`.

Pinned: S/N exactly 10.0000 (height 10000000, noise 1000000) raises no flag;
9.9999 raises `LOW_SN`.

## 9. Baseline segments

`chrom_baseline_level_at(starts, ends, levels0, levels1, t) -> Result[Int, Str]`

Validation (all segments before any lookup), in order: equal lengths
(`ends`, `levels0`, `levels1` against `starts`); non-empty; `t` in
`0..CHROM_FP_MAX`; per segment `i` in index order: start `0..CHROM_FP_MAX`,
end `1..CHROM_FP_MAX`, `end > start`, `level0`, `level1` in
`0..CHROM_FP_MAX`, and `start >= previous end` (touching allowed, overlap
rejected).

Lookup: the first segment with `start <= t <= end` wins. At `t == start` the
result is `level0`; at `t == end` it is `level1`; otherwise

```
level = l0 + ((l1 - l0) * (t - start)) / (end - start)
```

one truncating-toward-zero division (`(l1-l0)*(t-start)` is at most 1e18).
Pinned: `l0=100, l1=0, span=3, t=1 -> 100 + (-100/3) = 67`; `t=2 -> 34`.

Errors: `"chrom.baseline: segment tables length mismatch starts=N <field>=M"`,
`"chrom.baseline: no baseline segments"`,
`"chrom.baseline: time out of range 0..1000000000"`,
`"chrom.baseline: segment I start out of range 0..1000000000"`,
`"chrom.baseline: segment I end out of range 0..1000000000"`,
`"chrom.baseline: segment I end not after start"`,
`"chrom.baseline: segment I level0 out of range 0..1000000000"`,
`"chrom.baseline: segment I level1 out of range 0..1000000000"`,
`"chrom.baseline: segment I overlaps previous"`,
`"chrom.baseline: time T not covered by baseline segments"`.

`chrom_baseline_corrected(signal, baseline) -> Result[Int, Str]` returns
`signal - baseline` (may be negative); both inputs in `0..CHROM_FP_MAX`.
Errors: `"chrom.baseline: signal out of range 0..1000000000"`,
`"chrom.baseline: baseline out of range 0..1000000000"`.

## 10. Canonical text codec

### Grammar

```
document   = header LF record*
header     = "#chromatography peaks v1"          (exact, first non-blank line)
record     = "peak" SP value SP value SP value SP value
value      = ["-"] digit+ ["." digit{1,4}]       (order: time area height width)
```

- Tokens are separated by one or more spaces and/or tabs; leading and trailing
  spaces/tabs on a line are ignored.
- A CR immediately before an LF is ignored (CRLF input accepted).
- Empty/blank lines are skipped, before and after the header.
- The header must be the very first non-blank line; a header-only document is
  a valid empty table.
- `1.5` -> 15000, `3` -> 30000, `0.1` -> 1000; `1.` and `.5` are rejected;
  more than four fraction digits is rejected; values above
  `CHROM_FP_MAX` are rejected. Values are parsed by exact decimal arithmetic,
  never through a float.
- After parsing, `chrom_peak_validate` runs on the collected table, so
  negative values, zero widths, non-increasing times and oversized values are
  rejected with the section 4 messages.

### Emit

`chrom_table_emit(times, areas, heights, widths) -> Result[Str, Str]`

Validates first (error returned unchanged), then writes the header line and
one `peak` record per row, each value as `int.` plus exactly four zero-padded
fraction digits. Every line (including the last) ends with LF; an empty table
emits exactly the header plus LF:

```
#chromatography peaks v1
peak 1.0000 3.0000 0.5000 0.1000
peak 1.5000 1.0000 0.4000 0.2000
```

`(5, 9999, 10000, 999999999)` emits
`peak 0.0005 0.9999 1.0000 99999.9999`.

### Parse

`chrom_table_parse(text, times, areas, heights, widths) -> Result[Unit, Str]`

The four output vectors are cleared first and filled only on success; on Err
they are left empty. Errors, after `"chrom.codec: missing header"`:

- `"chrom.codec: line L: expected 'peak' record"`
- `"chrom.codec: line L: expected 4 fixed-point fields, got K"`
- `"chrom.codec: line L: trailing text after 4 fields"`
- `"chrom.codec: line L field F: bad value"` (`empty value`, `bad value`)
- `"chrom.codec: line L field F: more than 4 decimal places"`
- `"chrom.codec: line L field F: value out of range 0..1000000000"`

`L` is the 1-based physical line number (including skipped blank lines), `F`
is 1..4. Emit-then-parse recovers all four vectors exactly and re-emitting the
parsed table reproduces the canonical text byte for byte.

## 11. Complexity and termination

Every function is O(n) or O(1); no loop can fail to advance (`i = i + 1` or
`break` on a strict bound). The whole conformance suite runs in well under a
second.
