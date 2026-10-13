# PROVENANCE: xiom.harfbuzz

Upstream-first record (owner policy 2026-10-11, `docs/UPSTREAM-FIRST.md`).
This package is **NOT independent**: it binds the upstream harfbuzz library
and vendors its sources.

## 1. Upstream and pin

| Item | Value |
|---|---|
| Project | HarfBuzz -- `https://github.com/harfbuzz/harfbuzz` |
| Clone | `E:\repos\harfbuzz` (shallow, `--depth 1` at the tag; shared, disposable) |
| Pin | tag **14.6.0** = commit `c7a7457b7385f33178e8cf87615ca077a810bbe7` (2026-10-13) |
| License | **"Old MIT"** (`COPYING` in the clone and in `vendor/harfbuzz/COPYING`) |

Ledger: `E:\repos\CLEANUP.md` row `harfbuzz` (added 2026-10-13 by the
codec/container wave-B prep, lane=bindings, review-after 2026-12-01;
refreshed with the package landing at this touch). Cleanup discipline:
shallow clone, disposable, never committed into this repo -- only the
vendored subset below is.

## 2. License verification (per-directory, in the clone)

- `COPYING` (root): "Old MIT" full text (verified, copied to
  `vendor/harfbuzz/COPYING`).
- `src/ms-use/COPYING`: MIT (Microsoft) -- covers the vendored
  `src/ms-use/**` files; retained verbatim in the vendor tree.
- Test assets (`test/**`, fonts under SIL OFL) are **NOT vendored**: the
  package vendors `src/**` only.
- Class: permissive (MIT-class). Binding + vendoring of this clone is
  inside policy (`docs/UPSTREAM-FIRST.md` sec. 2).

## 3. What is vendored (byte-exact)

`vendor/harfbuzz/src/**` -- 576 files (7.6 MB) copied verbatim from the
pinned clone, plus `vendor/harfbuzz/COPYING`. Byte fidelity is enforced by
`.gitattributes` (`vendor/** -text`) and the SHA256 pins in SPEC.md
section 2. No upstream file was modified; no patch is applied anywhere.

What the package compiles from it: the **default amalgam**
`harfbuzz-subset.cc` (core + subset + instancer, no optional backends) as
a single C++ TU. Everything else in `vendor/` exists so the amalgam's
includes resolve and so a re-carve is a straight re-copy.

## 4. Derived vs independently written

| Artifact | Disposition |
|---|---|
| `vendor/harfbuzz/**` | **verbatim upstream** (Old MIT; license text retained) |
| `tools/gen_harfbuzz.py` | original XIOM-authors work; parses the pinned headers (comment/preprocessor stripping + the two default-build guards) and emits the binding surface |
| `src/hb_bridge.cpp` | original work; uses the public harfbuzz C API only |
| `src/*.xi` (generated) | original, machine-generated from the pinned headers |
| `src/harfbuzz.xi`, `tests/test_conformance.xi` | original work |
| `tests/fixtures/make_tiny_font.py`, `tests/fixtures/tiny.ttf` | **original generated font, no third-party font bundled** |

## 5. Test data provenance

- **`tests/fixtures/tiny.ttf`** (632 bytes, sha256
  `4d35932bb027e9df5065d43571c9663c37dcb38d2df67798a7b8417984d75c2f`):
  produced by `tests/fixtures/make_tiny_font.py` (original code, MIT OR
  Apache-2.0, same as the repository). Three glyphs (.notdef / `A` / `V`),
  tables head/hhea/maxp/hmtx/cmap(4)/glyf/loca/name/OS-2(v1)/post(v3).
  The wave brief allowed "vendor a permissively-licensed test font **or**
  generate/minimal TTF"; the generated option is used, so **no upstream or
  third-party font license applies** to the fixture. Regenerate with
  `python tests/fixtures/make_tiny_font.py`.
- **Upstream test vectors**: none imported. HarfBuzz's shape/subset test
  corpus (large, per-directory licenses) is intentionally NOT vendored;
  the probes assert semantic invariants (glyph ids from cmap, advances
  from hmtx, direction guess, subset-then-reshape) on the generated font
  plus the compile-time version pin (14.6.0).

## 6. Re-carve

See SPEC.md section 6 (fetch tag at depth 1, re-copy `src/**` + `COPYING`,
re-run `python tools/gen_harfbuzz.py`, update hashes/pins, port x2,
record). The generated oracle (`docs/gen_manifest.json`) makes drift
visible: `python tools/gen_harfbuzz.py --check` fails if the committed
artifacts no longer match the pinned headers.
