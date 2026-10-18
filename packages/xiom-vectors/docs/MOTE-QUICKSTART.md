<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xvector-mote quickstart (embedded)

`xvector-mote` is the embedded tier of XVECTOR: the same engine the
`xvector-lattice` server runs, linked in-process -- no socket, no daemon.
The registry package is **`xiom.vectors`** (vector types, metrics, top-K)
plus the engine sources of this repo (`src/`, imported via `xiom.toml`
roots). Architecture: `docs/PRODUCT-ARCHITECTURE.md`; naming:
`docs/PRODUCT-LAYERS.md`. The gate for everything below is
`tests/probes/probe_mote_embedded.xi` (46th probe, both batteries).

## Project setup

`xiom.toml` (a consumer project):

```toml
[project]
name = "my-app"
kind = "exe"

[roots]
src = "src"

[dependencies]
xiom.vectors = "0.1.0"
```

Install the package once (`XIOM_HOME/packages`):

```bash
xiom pkg install xiom.vectors --home "$XIOM_HOME"
```

Inside THIS repo the lane already wires it (`out/toolchain` +
`out/xiom-home`, see `scripts/dev-env.ps1` / `dev-env.sh`).

## The round trip (open -> create -> upsert -> search -> persist -> reopen)

```xiom
module my_app
use xiom.vector.engine;
use xiom.vectors;
use xiom.io;

fn main() -> Int {
  // 1. open the engine (embedded).
  var eng = engine_new();

  // 2. create a named collection (dim 4, cosine); it becomes active.
  match create_named_collection(&mut eng, "docs", 4, DistanceMetric.Cosine) {
    Ok(_) => {}
    Err(e) => { io.println("create failed: " + e); return 1; }
  }

  // 3. upsert points.
  var v = Vector.new(4);
  v.set(0, 1.0); v.set(1, 0.0); v.set(2, 0.0); v.set(3, 0.0);
  match upsert(&mut eng, 1, v) { Ok(_) => {} Err(_) => { return 1; } }

  // 4. search in-process.
  var q = Vector.new(4);
  q.set(0, 1.0); q.set(1, 0.0); q.set(2, 0.0); q.set(3, 0.0);
  match search(&eng, &q, 3) {
    Ok(hits) => {
      var i: Int = 0;
      while i < hits.items.len() {
        io.println("hit id=" + hits.items[i].id);
        i = i + 1;
      }
    }
    Err(e) => { return 1; }
  }

  // 5. persist the home: manifest (registry) + WAL checkpoint.
  let sm = save_manifest(&mut eng, "mydb/manifest");
  let wp = wal_persist(&eng.wal, "mydb/wal");
  if !(sm && wp) { return 1; }
  return 0;
}
```

Reopen the same home (embedded) on the next run:

```xiom
var rec = open_engine(&wal_load("mydb/wal"), "mydb/manifest", 4, DistanceMetric.Cosine);
// rec is the same engine: collections, points, configs.
```

## Home layout (the portable format)

```
mydb/
  manifest                 # collection registry (atomic temp+rename)
  wal                      # WAL checkpoint (longest-valid-prefix safe)
  <segments/snapshots as used>
```

The files are tier-neutral: the same home opens embedded (above) and is
served unchanged by `xvectord` (tier 2) -- see the architecture plan's P2.
For a durable server home the daemon additionally keeps a delta segment
(`enable_durability`) and checkpoints via `wal_persist_sync`.

## Notes

- Multi-collection routing: `select_collection(&mut eng, "name")` switches
  the active collection; `list_collections(&eng)` enumerates; every
  operation (upsert/search/delete/`engine_size`) targets the active one.
- Creating a collection AFTER a reopen is a gated regression case (the
  probe's second/third cycles): recovered cids must never be reused.
- Query surface: knn (`search`), range, pagination (offset + after-id),
  batch ops, filters, payloads, HNSW (`set_index`) -- see the probes under
  `tests/probes/` for each.
- Next tier: the same engine behind HTTP with auth/limits/metrics and a
  stateless router -- `docs/PRODUCT-ARCHITECTURE.md` sections 3-6.
