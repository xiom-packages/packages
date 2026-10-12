<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Upstream-first doctrine (owner policy, 2026-10-11)

**Mandate: no package code from memory.** Every package that implements an algorithm,
format, protocol, or external API is built against its authoritative source: the upstream
project cloned at a pinned commit, or the governing spec when one exists (RFC + published
test vectors). This applies to BOTH lanes -- native ports and FFI bindings.

## 1. Clone workflow (both lanes)

1. Pick the authoritative upstream (the reference implementation, or the spec + its
   reference vectors when the spec is the better source of truth).
2. Clone it into `E:\repos\<name>` (owner-provided, SHARED across lanes, disposable;
   never committed into this repo).
3. Pin the commit/tag/release you studied; record it in the package's `PROVENANCE.md`
   and, where relevant, `SPEC.md` (bindings keep their soname/header-set pins).
4. Study before writing. Code is written against what the clone shows, not from
   model/training memory.
5. Register the clone in `E:\repos\CLEANUP.md` (see section 6) with a review-after date.

## 2. License policy

Port/derive only from permissive sources:

- OK: MIT, Apache-2.0, BSD-2/3-clause, ISC, zlib, X11, public domain / CC0,
  Unicode License (data), RFCs and openly published test vectors.
- Reference-only (do NOT copy code or structure): MPL-2.0, LGPL, EPL.
- Never: GPL, AGPL, SSPL, Elastic License, or anything with unclear provenance.
- Check per-directory: "MIT" repos often vendor differently-licensed parts.
- Prefer re-implementation + imported vectors over verbatim copying; keep the upstream
  license text whenever any verbatim portion is retained.
- Attribution lives in `PROVENANCE.md`; the repo stays MIT OR Apache-2.0.

## 3. Provenance record (per package)

`packages/<pkg>/PROVENANCE.md`:

- upstream repo + pinned commit/tag, license;
- files/parts studied; what was derived vs independently implemented;
- test vectors / golden data imported from upstream, and where they live;
- re-carve procedure (how to refresh if upstream moves).

## 4. Verification = parity

- Import the upstream test vectors / golden data into `tests/` and the conformance
  suite; parity with upstream is the definition of done.
- Natives: 100% of the DECLARED surface implemented -- no silent gaps; out-of-scope
  items are explicit non-goals in SPEC/README.
- Bindings: bind to 100% of the target public API surface -- complete export coverage,
  not partial (the glfw 124/124 shape is the standard; every library continues to full
  coverage). The export matrix in SPEC records the counts. Runtime "SKIP when absent"
  stays a classified platform state, not a coverage gap.
- Record the run (x2) and publish under the normal pipeline.

## 5. Re-carve

Upstream updates are handled as a pinned re-carve (precedent: `xiom.btree` SPEC 2.3 --
re-carve at the fixed upstream commit, re-run vectors, re-verify x2, record, wrap,
publish).

## 6. Clone hygiene + retention (E:\repos)

Clones are disposable but are NOT deleted the moment a port lands -- they are kept
while a re-carve, debug, or sibling lane may still need them, under a timestamped
review date.

- **Ledger:** `E:\repos\CLEANUP.md` lists every clone (upstream, cloned date, lane/use,
  review-after date, status).
- **Sweep** at a quiet moment (doorbell/idle), never while a package using the clone is
  mid-work. Delete a clone only when ALL hold:
  1. its review-after date has passed;
  2. the corresponding package(s) are shipped + live-verified (or the research is
     concluded / abandoned);
  3. no open relay item, SPEC, or repro references the clone;
  4. the owning lane confirms (E:\repos is shared).
- On delete: remove the whole clone directory and update the ledger. If still needed,
  set a new review-after date with a one-line reason.

## 7. Stage promotion (owner policy, 2026-10-12)

Bindings packages start (and publish) at `incubating`; the stage is a maturity marker,
not a coverage marker -- publishing works at `incubating` + tests=pass, and coverage is
evidenced separately (records, `docs/COVERAGE.md` oracles, `PROVENANCE.md`).

Promotion to `stable` is per package and requires BOTH:

1. the package's **full declared surface is published** (its SDK100/full-surface version
   is live on the registry -- e.g. vulkan, sdl3, and the wave packages only after their
   eco batches), and
2. **no open/known defects** reference it (no open relay item, audit finding, or failing
   consumer), with at least one settle cycle since the full-surface publish.

Promotions happen at the package's next touch (stage flip + reason in the same commit)
and are listed in SESSION.md as they occur. Names not yet promoted stay `incubating`
with no shipping downside.
