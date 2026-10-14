# xiom.photometrics

> **Status:** `incubating` -- conformance-tested (43/43), recorded x2 green
> on XIOM v0.64.4; not yet published (registry/allowlist gate).
> **Scope:** import of photometric/color profile text formats, pure XIOM:
> IESNA LM-63 photometric files (1986, 1991, 1995, 2002) and Adobe
> `.cube` 1D/3D LUTs, with typed errors and sampling helpers.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.compare`, `xiom.math`). Tests additionally use `xiom.test`
> and `xiom.io`.

## What it is

`xiom.photometrics` reads the two small text formats that carry
photometric and color-profile data into flat, owned structs:

- **IES LM-63** (`ies_parse`): the four in-use revisions
  (`IESNA:LM-63-1986`, `IESNA91`, `IESNA:LM-63-1995`,
  `IESNA:LM-63-2002`). Parses the version tag, `[KEYWORD] value`
  luminaire metadata, `TILT=NONE|INCLUDE|<file>`, lamp/lumen/watt
  parameters, the vertical/horizontal angle grids and the candela table.
  `ies_sample` returns a bilinearly interpolated (normalized) candela
  value at any angle pair; `ies_candela_scaled` / `ies_sample_scaled`
  apply the file's candela multiplier.
- **Adobe `.cube`** (`cube_parse`): `TITLE`, `LUT_1D_SIZE` /
  `LUT_3D_SIZE`, `DOMAIN_MIN`/`DOMAIN_MAX` and the RGB triples
  (red channel varies fastest); `cube_sample_3d` / `cube_sample_1d`
  interpolate, `cube_entry` / `cube_3d_index` expose the raw table.

Malformed or truncated input never crashes: every failure is a typed
`IesError` / `CubeError` with a numeric code (catalogs in `SPEC.md`
section 5) and a message naming the offending token. Out-of-range
accessors return documented defaults.

## Install / use

Until the package is published to the registry, build against this
checkout with the repo harness:

```
.\scripts\port.ps1 -Package xiom.photometrics
```

Once published:

```
xiom pkg install xiom.photometrics@0.1.0
```

## Quick start

```xi
use xiom.photometrics;
use xiom.io;

fn main() -> Int {
  let src = "IESNA:LM-63-2002\n[MANUFAC] ACME\nTILT=NONE\n1 3000 1 2 1 1 1 0.6 0.3 0.1\n1.0 1.0 25.5\n0 180\n0\n1000 500\n";
  let r = ies_parse(src);
  match r {
    Ok(d) => {
      io.println(ies_version_label(&d));       // IESNA:LM-63-2002
      io.println(ies_vertical_count(&d));      // 2
      io.println(ies_input_watts(&d));         // 25.5
      io.println(ies_sample(&d, 90.0, 0.0));   // 750 (interpolated)
    },
    Err(e) => { io.println(e.message); },
  }
  return 0;
}
```

## Boundaries

See `SPEC.md` for the exact grammars, decisions, error catalogs, caps and
the 49-function/40-constant declared surface; `PROVENANCE.md` records the
independent-declaration format references and fixture provenance.
