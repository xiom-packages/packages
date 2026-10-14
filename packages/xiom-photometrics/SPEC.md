# xiom.photometrics -- Specification

Version: 0.1.0 (incubating).
Module: `xiom.photometrics` (`src/photometrics.xi`). Pure XIOM, no FFI.
Dependencies: `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
`xiom.string.compare`, `xiom.math`; the tests additionally use `xiom.test`
and `xiom.io`).

## 1. Scope

A small, dependency-free **photometric profile importer** with two readers
over in-memory `Str` documents:

- `ies_parse` -- IESNA LM-63 photometric text -> `Result[IesDoc, IesError]`
  (revisions 1986, 1991, 1995, 2002): version tag, bracketed luminaire
  metadata, `TILT=` handling, lamp/lumen/watt parameters, vertical and
  horizontal angle grids, candela table, plus a bilinear normalized lookup
  helper (`ies_sample` / `ies_sample_scaled`).
- `cube_parse` -- Adobe `.cube` 1D/3D LUT -> `Result[CubeLut, CubeError]`:
  `TITLE`, LUT size, `DOMAIN_MIN`/`DOMAIN_MAX`, RGB data triples, plus 1D
  and trilinear sampling helpers.

Both formats are read into flat, fully owned structs; every vector is
built with push-growth. Errors are typed: numeric `code` constants
(`IES_ERR_*`, `CUBE_ERR_*`) plus a human-readable message carrying the
offending token where useful.

## 2. Name and module choice

The relay work item proposed `xiom.photometrics` and left the name open
("name the package per the item's flexibility note"). The proposal is
adopted because it names the problem domain (photometry) rather than a
single format, leaving room for future profile formats (e.g. EULUMDAT
`.ldt`, IES TM-33/XML) without a rename, and because the registry
namespace `xiom.photometrics` is free (namespace audit run by
`scripts/port.ps1`; one module, no stdlib overlap). Alternatives
considered: `xiom.ies` (too narrow -- excludes `.cube`), `xiom.lut3d`
(excludes IES), `xiom.lighting` (broader than data import).
The package declares a single module `xiom.photometrics`; no cross-module
const aliases exist anywhere in the package (B-31 discipline by
construction).

## 3. IES LM-63 grammar (declared surface)

Recognized revision headers (first non-blank line; an optional UTF-8 BOM
is skipped; comparison is case-sensitive as in the standard):

| Header | `version` code | `ies_version_label` |
|---|---|---|
| `IESNA:LM-63-1986` | `IES_VERSION_1986` (1986) | `IESNA:LM-63-1986` |
| `IESNA91` | `IES_VERSION_1991` (1991) | `IESNA91` |
| `IESNA:LM-63-1995` | `IES_VERSION_1995` (1995) | `IESNA:LM-63-1995` |
| `IESNA:LM-63-2002` | `IES_VERSION_2002` (2002) | `IESNA:LM-63-2002` |

Document structure (blank lines ignored everywhere; LF and CRLF accepted):

```
IESNA:<revision>
[KEYWORD] value            ; zero or more bracketed metadata lines
<free description line>    ; zero or more non-bracketed lines
TILT=NONE | INCLUDE | <file>
                           ; INCLUDE only:
<lamp-to-luminaire geometry>          ; integer 1..5
<# of pairs of angles and factors>    ; integer 1..64
<angle> ...                           ; one value per pair
<multiplying factor> ...              ; one value per pair
<num_lamps> <lumens/lamp> <candela multiplier> <# vertical angles>
<# horizontal angles> <photometric type> <units type>
<width> <length> <height>              ; 10 values on one line
<ballast factor> <ballast-lamp factor> <input watts>   ; 3 values on one line
<vertical angles>          ; declared count, may span lines
<horizontal angles>        ; declared count, may span lines
<candela values>           ; #vertical * #horizontal, may span lines
```

Decisions (each covered by the conformance suite):

1. **Metadata.** Lines before `TILT=` starting with `[` are stored as
   keyword name/value pairs (first `]` terminates the name; the value is
   the trimmed remainder). Any other non-blank line before `TILT=` is a
   descriptive line. This mirrors the standard's tolerance for older
   revisions that precede keywords with descriptive text, and never
   fails on metadata content.
2. **TILT.** Required; `NONE`, `INCLUDE` (case-insensitive) or any other
   non-empty value stored as a file reference (`IES_TILT_FILE`). The
   INCLUDE block is stored as geometry + parallel angle/factor vectors
   and is **not applied** to the candela table (see non-goals). A line
   starting with `TILT` immediately followed by `=`, whitespace or
   end-of-line is the TILT line; a longer word such as `TILTAGE` is an
   ordinary descriptive line.
3. **Parameter lines.** The 10-value and 3-value lines are line-strict:
   all ten (resp. three) tokens must originate from one physical line.
   The angle and candela lists are token streams and may be wrapped over
   any number of lines.
4. **Angles and candela are stored exactly as read**, in degrees and
   candelas, in file order; no type-specific (C/B/A) re-orientation and no
   `TILT` application is performed. The candela multiplier is preserved
   separately (`ies_candela_multiplier`, `ies_candela_scaled`).
5. **Candela layout** is plane-major: `candela[h * num_vertical + v]` is
   the value for horizontal index `h` and vertical index `v` -- the
   standard's block order ("all vertical angles at the first horizontal
   angle, then at the second, ..."). `ies_candela(&d, h, v)` and
   `ies_candela_scaled(&d, h, v)` expose it with that signature.
6. **Trailing data** after the declared candela table is an error
   (`IES_ERR_TRAILING`), not silently ignored.
7. **Revision-specific normative differences** (paid IES standards) are
   not re-enforced beyond the revision tag; the reader accepts the
   documented common superset above. See PROVENANCE.md.

## 4. `.cube` grammar (declared surface)

```
# comment line                       ; also blank lines, both ignored
TITLE "<title>"                      ; optional, at most once
LUT_1D_SIZE <n>                      ; exactly one size declaration
LUT_3D_SIZE <n>                      ;   (mutually exclusive), n >= 2
DOMAIN_MIN <r> <g> <b>               ; optional, at most once (default 0 0 0)
DOMAIN_MAX <r> <g> <b>               ; optional, at most once (default 1 1 1)
<r> <g> <b>                          ; exactly n (1D) or n^3 (3D) triples
```

Decisions:

1. Keywords are recognized case-insensitively (`title` == `TITLE`).
2. `DOMAIN_MIN`/`DOMAIN_MAX` may appear in any order before the data;
   each may appear at most once; `min >= max` on any channel is
   `CUBE_ERR_BAD_DOMAIN` (degenerate mapping).
3. **3D data ordering is red-fastest**: triple index =
   `r + size * g + size * size * b` (`cube_3d_index`). The 1D table holds
   `size` triples; channel `c` of the input uses component `c` of each
   triple (`cube_sample_1d`).
4. Data lines require exactly three numeric tokens; a line whose first
   token is numeric but malformed/1-2/>3 tokens is `CUBE_ERR_BAD_DATA`.
   A line whose first token is not a recognized keyword and not numeric
   is `CUBE_ERR_BAD_KEYWORD`.
5. The data count must match the declared size exactly: fewer triples ->
   `CUBE_ERR_TRUNCATED`, more -> `CUBE_ERR_TRAILING`.
6. The 360-degree horizontal-grid convention of some IES files (a
   duplicated `360` plane equal to `0`) is preserved verbatim; ring
   wrapping at lookup time is a sampling concern (section 6).

## 5. Error catalogs

### IES `IesError.code` (`IES_ERR_*`)

| Code | Constant | Raised when |
|---|---|---|
| 1 | `IES_ERR_EMPTY` | no non-blank line |
| 2 | `IES_ERR_MISSING_VERSION` | first line does not start with `IESNA` |
| 3 | `IES_ERR_UNSUPPORTED_VERSION` | IESNA header not one of the four revisions |
| 4 | `IES_ERR_MISSING_TILT` | no `TILT=` line before end of input |
| 5 | `IES_ERR_BAD_TILT` | `TILT=` without `=`, or empty value |
| 6 | `IES_ERR_BAD_TILT_BLOCK` | INCLUDE geometry/count/angle/factor data malformed or short |
| 7 | `IES_ERR_BAD_NUMBER` | non-numeric token, or parameter line not on one line |
| 8 | `IES_ERR_BAD_COUNT` | lamps < 1, or vertical/horizontal count outside 1..10000 |
| 9 | `IES_ERR_TRUNCATED` | fewer token groups/angles/candela values than declared |
| 10 | `IES_ERR_TRAILING` | extra tokens after the candela table |
| 11 | `IES_ERR_BAD_ENUM` | photometric type outside 1..3, units outside 1..2 |
| 12 | `IES_ERR_LIMIT` | vertical * horizontal exceeds `IES_MAX_CANDELA` |

### Cube `CubeError.code` (`CUBE_ERR_*`)

| Code | Constant | Raised when |
|---|---|---|
| 1 | `CUBE_ERR_EMPTY` | no non-blank, non-comment line |
| 2 | `CUBE_ERR_MISSING_SIZE` | no `LUT_1D_SIZE`/`LUT_3D_SIZE` |
| 3 | `CUBE_ERR_DUPLICATE_SIZE` | size declared twice or both dimensions |
| 4 | `CUBE_ERR_BAD_SIZE` | non-integer size, or outside 2..128 (3D) / 2..65536 (1D) |
| 5 | `CUBE_ERR_BAD_DOMAIN` | domain line without three numbers, or `min >= max` |
| 6 | `CUBE_ERR_DUPLICATE_DOMAIN` | `DOMAIN_MIN`/`DOMAIN_MAX` repeated |
| 7 | `CUBE_ERR_BAD_TITLE` | unquoted/duplicate TITLE |
| 8 | `CUBE_ERR_BAD_DATA` | data line without exactly three numeric tokens |
| 9 | `CUBE_ERR_TRUNCATED` | fewer triples than `size` / `size^3` |
| 10 | `CUBE_ERR_TRAILING` | more triples than `size` / `size^3` |
| 11 | `CUBE_ERR_BAD_KEYWORD` | unrecognized keyword line |

### Documented caps

- `IES_MAX_ANGLES = 10000` per grid axis;
- `IES_MAX_CANDELA = 1000000` values per candela table;
- `IES_MAX_TILT_PAIRS = 64`;
- `CUBE_MAX_3D_SIZE = 128` (2,097,152 entries worst case);
- `CUBE_MAX_1D_SIZE = 65536`.

Caps are sanity limits against malformed headers, not format limits;
they are typed (`IES_ERR_BAD_COUNT`/`IES_ERR_LIMIT`/`CUBE_ERR_BAD_SIZE`).

## 6. Sample-value semantics

`ies_sample(&d, vert_deg, horiz_deg)` bilinearly interpolates the raw
candela table on the stored grids:

- vertical axis: clamp to the first/last stored angle; a single angle
  selects its plane;
- horizontal axis: a **closed ring** (first angle 0 and last angle >=
  359.999, i.e. the duplicated 360 plane) wraps modulo 360 with the
  duplicate endpoint excluded from interpolation; any other grid clamps;
  a single angle selects its plane;
- result excludes the candela multiplier (`ies_sample_scaled` applies it);
- a degenerate (zero-width) segment interpolates at its left end.

The standard requires ascending angle lists; the sampler assumes that
order (an out-of-order grid degrades to its first segment, never to an
out-of-range read).

`cube_sample_3d(&d, r, g, b)` maps each input through its channel's
`DOMAIN_MIN`/`DOMAIN_MAX` to [0, 1], clamps, and performs trilinear
interpolation on the uniform grid; `cube_sample_1d(&d, c, x)` is the
linear 1D equivalent (returns 0.0 for a 3D LUT). All accessors return
documented defaults (empty string / 0.0 / zero triple) out of range and
never crash.

## 7. Non-goals

- Applying `TILT=` data (file references and INCLUDE blocks are parsed
  and stored, not applied) and any photometric-type angle re-orientation.
- Physical units conversion between feet/meters, lumen/wattage
  computations, luminance/illuminance integrals.
- IES TM-33 / XML, EULUMDAT `.ldt`, CIBSE, or any binary photometric
  container.
- `.cube` writing, `LUT_1D_SIZE`+`LUT_3D_SIZE` combination files, GPU
  upload, or tetrahedral interpolation.
- File I/O, streaming parsing, registry integration. Documents are
  in-memory `Str` values.
- Rich error positions: errors carry the typed code and the offending
  token, not line/column offsets.

## 8. Fixtures and verification

- All fixtures live inline in `tests/test_conformance.xi` and are
  hand-written from the documented layouts above; no upstream-produced
  IES or `.cube` file is consumed (documented limitation -- see
  PROVENANCE.md). The 43-check suite covers the four IES revisions, the
  TILT variants, wrapped/CRLF/BOM input, all 12 IES error codes, the
  size-2 `.cube` 1D/3D cases, all 11 cube error codes and both sampling
  families.
- Run: `.\scripts\port.ps1 -Package xiom.photometrics -TimeoutSec 180`
  (namespace check + compile + suite). Recorded x2 green on XIOM v0.64.4;
  see `STATUS.json`.

## 9. Declared surface

Types: `IesDoc`, `IesError`, `CubeLut`, `CubeError`, `CubeRgb`.

Functions (49):

| Group | Functions |
|---|---|
| IES parse | `ies_parse` |
| IES version | `ies_version`, `ies_version_label` |
| IES metadata | `ies_keyword_count`, `ies_keyword_name`, `ies_keyword_value`, `ies_get_keyword`, `ies_description_count`, `ies_description` |
| IES tilt | `ies_tilt_kind`, `ies_tilt_ref`, `ies_tilt_geometry`, `ies_tilt_pair_count`, `ies_tilt_angle`, `ies_tilt_factor` |
| IES parameters | `ies_num_lamps`, `ies_lumens_per_lamp`, `ies_candela_multiplier`, `ies_photometric_type`, `ies_units_type`, `ies_width`, `ies_length`, `ies_height`, `ies_ballast_factor`, `ies_ballast_lamp_factor`, `ies_input_watts` |
| IES grids | `ies_vertical_count`, `ies_horizontal_count`, `ies_vertical_angle`, `ies_horizontal_angle`, `ies_candela_count`, `ies_candela`, `ies_candela_scaled` |
| IES lookup | `ies_sample`, `ies_sample_scaled` |
| Cube parse | `cube_parse` |
| Cube accessors | `cube_title`, `cube_has_title`, `cube_is_3d`, `cube_dim`, `cube_size`, `cube_domain_min`, `cube_domain_max`, `cube_entry_count`, `cube_value`, `cube_entry`, `cube_3d_index` |
| Cube lookup | `cube_sample_3d`, `cube_sample_1d` |

Constants (40): the four `IES_VERSION_*`, three `IES_TILT_*`, three
`IES_TYPE_*`, two `IES_UNITS_*`, the three caps, the twelve `IES_ERR_*`,
the two cube caps and the eleven `CUBE_ERR_*`.

## 10. Toolchain discipline (XIOM v0.64.4)

- No `?` operator anywhere: error propagation is explicit match/rewrap,
  avoiding the v0.64.4 error-payload corruption across Result payload
  types recorded in `xiom.vdb` SPEC section 13.
- No `Result[Option[T]]` nesting (B-26) and no `&mut` of a
  struct-return temp (B-21): parsers build locals and return one struct;
  helpers take `&T` only.
- No `Vec.with_len` (B-28): every vector is push-grown.
- Str equality binds a typed local and goes through
  `compare.str_compare` / `str_compare_ignore_case` (BUG 17); no `==` on
  `Str` values read from vectors.
- Single module: no cross-module const aliases (B-31) and no pointer
  casts/arithmetic (B-20/B-25) -- there is no FFI in this package.
