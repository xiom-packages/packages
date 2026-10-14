# PROVENANCE: xiom.photometrics

Upstream-first record (owner policy 2026-10-11, `docs/UPSTREAM-FIRST.md`).
This package is an **EXPLICITLY INDEPENDENT declaration: no vendored
upstream code, no translated code, no generated code, no upstream
implementation source consulted.** It is a pure-XIOM, from-scratch reader
for two small text formats whose semantics are publicly documented.

## Format references

The implementation was written against the public format documentation
below; the relay item for this package explicitly framed the work as an
independent declaration on exactly these grounds ("own reader; IESNA
LM-63 and .cube are small well-specified text formats").

| Format | Reference | Use |
|---|---|---|
| IESNA LM-63-2002 layout | AGi32 / Photometric Toolbox documentation, "IESNA LM-63 Format" (`https://docs.agi32.com/PhotometricToolbox/Content/Open_Tool/iesna_lm-63_format.htm`) -- public, vendor-published line-by-line description of LM-63-2002 (version line, keyword block, `TILT=` line and INCLUDE block, 10-value and 3-value parameter lines, angle and candela block order, the candela-per-horizontal-plane grouping) | consulted 2026-10-14 to fix the declared grammar in `SPEC.md` section 3 |
| IESNA LM-63 revisions 1986/1991/1995 | The revision tags and their header tokens are the standard's published interoperability surface: `IESNA:LM-63-1986`, `IESNA91`, `IESNA:LM-63-1995`; the normative standards texts are IES-published documents (not copied, not consulted). The reader accepts the documented common superset and stores the revision tag (see `SPEC.md` section 3, decision 7) | header table in `SPEC.md` section 3 |
| Adobe ".cube" | "Cube LUT Specification Version 1.0" (Adobe Systems, 2013), archived at `https://web.archive.org/web/20220220033515/https://wwwimages2.adobe.com/content/dam/acom/en/products/speedgrade/cc/pdfs/cube-lut-specification-1.0.pdf` -- keyword set (`TITLE`, `LUT_1D_SIZE`, `LUT_3D_SIZE`, `DOMAIN_MIN`, `DOMAIN_MAX`), 0..1 defaults, three-float data lines, 3D ordering with the red channel varying fastest | declared grammar in `SPEC.md` section 4 |

No implementation source was read for either format: not the IES
standards' sample code, not any open-source `.cube`/IES parser (e.g.
color-management or renderer code bases were deliberately not consulted),
so nothing needed to be derived, attributed or re-licensed. The facts
reproduced here are the formats' interoperability surface (tokens, field
order, block order, defaults, ordering rules), re-expressed in XIOM with
no shared identifiers, structure or text.

## Clone / cleanup ledger

**No oracle repository was cloned or consulted for this package**
(`E:\repos` was searched first: no IES or LUT implementation clone
exists there, and none was created). `E:\repos\CLEANUP.md` therefore has
no row for this work item and was not modified -- there is nothing to
sweep. If a future revision wants an upstream-file parity test (e.g.
reading IES files produced by a lighting manufacturer's photometer or a
`.cube` exported by a color-grading tool), clone the relevant tool at a
pinned commit and add a ledger row at that time.

## Fixture provenance (honest record)

- **No upstream-produced IES or `.cube` file is read by the suite.** All
  fixtures are small hand-written documents that follow the layouts in
  `SPEC.md` sections 3-4, embedded as string literals in
  `tests/test_conformance.xi`; expectations are computed from the
  documented structure itself (counts, block order, interpolation
  arithmetic), not from any tool's output.
- Every error path is exercised with a deliberately malformed fixture:
  all 12 IES error codes and all 11 cube error codes have at least one
  test asserting the numeric code (`ies_fail` / `cube_fail` helpers).
- When an upstream consumer becomes available (a real photometric file or
  a real `.cube`), the suite should gain an oracle-file regression test;
  this is declared as a limitation, not a claim of parity.

## Tooling note

Developed against XIOM v0.64.4
(`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`, stdlib `E:\xiom-lang\stdlib`) as
a read-only consumer, in the bindings-lane isolated worktree. The
v0.64.4 defect notes that shaped the style (no `?` propagation, no
`Vec.with_len`, no `Result[Option[T]]`, no `&mut` of struct-return
temps) are restated in `SPEC.md` section 10; the B-20/B-25 FFI rules are
trivially satisfied because the package contains no FFI.
