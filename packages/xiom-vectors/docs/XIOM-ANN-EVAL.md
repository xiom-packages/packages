<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.ann porter evaluation (2026-10-11, 68th pass)

Owner-granted porter flow, same pattern as `xiom.vectors`
(`docs/XIOM-VECTORS-EVAL.md` + the 60th-pass atomic swap): the package is
the ecosystem home for the ANN code; xvector evaluates it as a consumer
and swaps its internals once the package is current.

## Registry state (watch resolved)

- **`xiom.ann` 0.1.0 is LIVE** (registry `xiom_package_info`):
  sha256 `73f66ab558f6e3a61597da724063712a5e92266da31200ffd3cf0e30ac44abb7`,
  deps `xiom.std >=0.60.0 <1.0.0` + `xiom.vectors 0.1.0`; published in
  eco-v0.1.139 (packages commit `34d3d8bb`). The registry-404 watch
  (`REL-20261010-1908-packages`, fixed) is closed.
- Local source: `E:\xiom-packages\packages\packages\xiom-ann`
  (`src/ann.xi` = our `ann_index.xi` surface + `flat_search`;
  `src/hnsw.xi` = our hnsw module; 24/24 suite; own recall probe 35/35).

## Consumer diff vs our HEAD (`d42171c`)

The package was extracted from xvector at **`8a8b0ff`** (pre-P-a). It is a
faithful snapshot of everything *except* the 63rd/67th-pass work:

| Item | package 0.1.0 (`8a8b0ff`) | xvector HEAD |
|---|---|---|
| Level-0 degree | `<= m` everywhere | generous: capacity `m0 = 2*m`, full-block prune to 80% of `m0` (FAISS `prune_headroom` 0.2), `hnsw_new_full` control constructor |
| Codec | v2 `[2, m, ml, ...]` | **v3** `[3, m, m0, ...]`, v2 still decodes, per-layer degree validation (`m0` / `m`) |
| Recall probe | 35 checks; 296/300 at ef=8 | 40 checks incl. the P-a hard-corpus gate (285/300 generous vs 275/300 legacy control) |
| Everything else | identical (search/insert/update/delete/compact/id map/visited/build_ops/kind codes) | identical |

Consequence: swapping to the package **today** would regress the P-a
recall gains and the codec (our segment files write v3; v2-only would
break them).

## Adoption plan (the swap)

1. **Blocked on: `xiom.ann` 0.2.0** carrying the P-a + codec-v3 delta
   (re-extract from xvector HEAD >= `d42171c`, keeping the package's SPEC
   revision/SHA256 pin discipline). Ask filed on the bus (this pass).
2. Then (owner greenlight, vectors precedent): replace
   `src/index/ann_index.xi` + `src/index/hnsw.xi` internals with
   package-backed re-exports (`AnnIndexKind`/`AnnParams`/kind codes from
   `xiom.ann`; graph + codec from `xiom.ann.hnsw`), keeping our type
   names/aliases so the engine, probes, and `segment_file` are untouched;
   add the dependency to `xiom.toml`; zero stale module references.
3. Gates: the standard battery + `probe_hnsw_recall` (40 checks, P-a
   gates) + `probe_hnsw_codec` (12) + `probe_fuzz_codecs` +
   `probe_engine_hnsw` + segment/engine probes; WSL spot; docs re-framed
   like the vectors sections (SPEC "extracted module").

## Risks / notes

- Codec compatibility is the hard requirement: the swapped module must
  write v3 and read v2+v3 (segment files in the wild are v1/v2; ours now
  v2/v3).
- Re-extraction must be mechanical (the packages lane's flow with SHA256
  pins), not a hand port -- the vectors precedent.
- WSL installs with a custom `XIOM_HOME` hit the path-mangling bug
  (`REL-20261010-1937-xvector` / `REL-20261010-2100-packages`); verify at
  swap time (Windows install path is fine).
- Shared benefit: the engine lane and future consumers take `xiom.ann` as
  the ANN home; the P-a refresh upgrades the whole ecosystem, not just
  xvector.

## Status

- 2026-10-11 (67th): watch condition met (`xiom.ann` LIVE); evaluation
  written; refresh ask filed (packages lane).
- Next: `xiom.ann` 0.2.0 -> owner greenlight -> the swap slice.
