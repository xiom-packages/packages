# xiom.btree roadmap

Nothing here changes the frozen 0.1.0 surface (verbatim carve from ORBITDB
`src/engine.xi` at `10109e1`).

| Stage | Item | Gate |
| --- | --- | --- |
| reconciliation | ORBITDB consumes `xiom.btree` and deletes its local B-TREE INDEX region (same pattern as `xiom.durable -> xiom.wal`) | separate sequenced lane step; this package never edits ORBITDB |
| correctness | resolve the order-3 delete defect: upstream fix in ORBITDB's merge/fill path at `min_keys = 0`, or an explicit `order >= 4` restatement in the surface; then re-run the churn matrix including order 3 and re-expand the suite's delete coverage | upstream decision + fix; SPEC 2.3 documents the repro |
| memory | free-list reuse of abandoned node indices (splits/merges append forever today) | after consumer demand; needs an index-validity contract |
| contracts | join the contract program (postconditions the verifier can consume) | contract-program scheduling; no new clauses before then |
| tests | port `churn.ps1` to sh for the Linux lane; add a long-soak variant (100k+ ops) as an ops-side soak | ops lane scheduling |
