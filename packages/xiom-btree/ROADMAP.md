# xiom.btree roadmap

Nothing here changes the frozen 0.1.1 surface (verbatim carve from ORBITDB
`src/engine.xi` at `c017165`; originally 0.1.0 at `10109e1`).

| Stage | Item | Gate |
| --- | --- | --- |
| reconciliation | ORBITDB consumes `xiom.btree` and deletes its local B-TREE INDEX region (same pattern as `xiom.durable -> xiom.wal`) | separate sequenced lane step; this package never edits ORBITDB |
| correctness | ~~resolve the order-3 delete defect: upstream fix in ORBITDB's merge/fill path at `min_keys = 0`~~ **RESOLVED 0.1.1**: upstream fix (`c017165`) re-carved; churn matrix re-expanded to order 3 (incl. the former reproducer) and the suite's delete coverage re-expanded | done 2026-10-11; SPEC 2.3 keeps the history |
| memory | free-list reuse of abandoned node indices (splits/merges append forever today) | after consumer demand; needs an index-validity contract |
| contracts | join the contract program (postconditions the verifier can consume) | contract-program scheduling; no new clauses before then |
| tests | port `churn.ps1` to sh for the Linux lane; add a long-soak variant (100k+ ops) as an ops-side soak | ops lane scheduling |
