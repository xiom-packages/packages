# xiom.chromatography

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.0` on the XIOM registry.

Pure XIOM, deterministic, FFI-free chromatography data model. Everything is
fixed-point integer math with scale 1e-4 (an Int value of `12345` means
`1.2345`); there is no floating point anywhere in the module.

## What it provides

- **Peak tables** -- four parallel `Vec[Int]`: retention times, areas, peak
  heights and widths at half height, validated as a unit
  (`chrom_peak_validate`).
- **Area math** -- total area with the documented 1e12 cap
  (`chrom_peak_total_area`) and exact normalization to 100 percent in 1e-4
  percent units via the cumulative-floor method
  (`chrom_peak_normalize_areas`).
- **Resolution** -- the half-height formula `R = 1.18*(t2-t1)/(w1+w2)` for a
  pair (`chrom_peak_resolution`) and for adjacent rows of a table
  (`chrom_table_adjacent_resolution`).
- **Kovats retention indices** -- interpolation against a caller-supplied
  alkane anchor table (`chrom_kovats_index`), with the standard consecutive
  alkane case `RI = 100*n + 100*(t_x - t_n)/(t_{n+1} - t_n)`.
- **Signal-to-noise and QC** -- `chrom_signal_to_noise`,
  `chrom_asymmetry_flag` (tailing/fronting) and the combined bitmask
  `chrom_qc_flags` (low S/N, tailing, fronting, unresolved).
- **Baseline segments** -- linear interpolation over mirrored segment records
  (`chrom_baseline_level_at`) and signal correction
  (`chrom_baseline_corrected`).
- **Canonical text codec** -- `chrom_table_emit` / `chrom_table_parse` with a
  strict grammar and a documented error catalog.

## Example

```xiom
use xiom.chromatography;

// times, areas, heights, widths at half height, scale 1e-4
let times = ...;  // e.g. [10000, 15000]
let norm = chrom_peak_normalize_areas(&areas);      // sums to 1000000
let res = chrom_peak_resolution(10000, 1000, 15000, 1000);  // Ok(29500)
```

Codec text:

```
#chromatography peaks v1
peak 1.0000 3.0000 0.5000 0.1000
peak 1.5000 1.0000 0.4000 0.2000
```

## Tests

```
.\scripts\port.ps1 -Package xiom.chromatography -TimeoutSec 60
```

24 conformance checks cover validation, normalization (including the exact
1000000 residual sum), resolution truncation, Kovats anchors, S/N and QC
boundaries, baseline interpolation (including truncation toward zero), and the
codec round-trip plus its error catalog. See `SPEC.md` for the formulas,
rounding rules and grammar.
