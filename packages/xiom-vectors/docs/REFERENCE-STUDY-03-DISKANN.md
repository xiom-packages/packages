<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Reference study 03 -- tight SSD layout (DiskANN lineage) vs. xvector

Owner-granted study area (`E:\repos`); sources are MIT (verified in-clone):
the **DiskANN Rust rewrite** (`E:\repos\DiskANN`, `LICENSE.txt`:
"Copyright (c) Microsoft Corporation. MIT License") and sqlite-vec's
LM-DiskANN implementation (`sqlite-vec/sqlite-vec-diskann.c`; MIT/Apache).
**No code is vendored and no build dependency is added.** Citations are
`diskann-disk/<path>:<line>`, `sqlite-vec/...` at the shallow clones
(2026-10-11). Scope: design input for **D5 (delta segments)**, **D6
(retention)** and **P5 (mmap)** -- all three gated on the stdlib fsync/mmap
chain today, which is exactly why the *format* decisions below should be
made before the gates open.

## What was examined

| Area | Source | xvector today |
|---|---|---|
| Sector geometry | `diskann-disk/src/build/configuration/disk_index_build_parameter.rs:20-22` `DISK_SECTOR_LEN = 4096` ("offset alignment and smallest block size"); `disk_sector_graph.rs:19` fallback 4096 (512 also supported) | segment file is a whole-file TEXT codec (`xvector-segment 1`), no alignment |
| Node record + packing | `disk_index_writer.rs:386-394` (nodes never split across sectors; `node_len < sector` packs floor(sector/node_len); `node_len > sector` aligns the start and pads to the next boundary); `disk_sector_graph.rs:28-33` (`{full precision vector}{num_nbrs: u32}{neighbors: [u32]}` per node; `node i -> sector i / num_nodes_per_sector`, `offset (i % n) * node_len`) | full-precision vector in the `v` line + graph words in the `h` line (text) |
| Header + versioning | `data_model/graph_header.rs:16` (header in the first sector), `:58-76` (metadata 80 B + block_size u64 + layout version), `:44-45` (bump the layout version whenever the header layout changes) | `xvector-segment 1` header line; manifest `xvector-manifest 1` |
| Aligned IO contract | `aligned_file_reader/aligned_read.rs:37-79`: three constraints (disk offset, buffer length, buffer pointer) checked against an alignment witness (`A1`/`A512`), `DiskIOAlignmentError` on violation; read buffers sized `next_multiple_of(4096)` (`disk_vertex_provider_factory.rs:55-58`) | whole-file `read_file_bytes` (stdlib); mmap pending (P5 gate) |
| Hot-vertex cache | `data_model/cache.rs` + `search/provider/cached_disk_vertex_provider.rs` | whole graph in memory (no cache tier) |
| Disk-side compression | `storage/quant/pq/*` (PQData + ADC scratch `search/pq/pq_scratch.rs:14-52`, A128-aligned) | none (study 02 Q-a/q-c proposals) |
| Append/delta pattern | DiskANN builds once (builder); sqlite-vec: `_diskann_buffer` + `buffer_threshold` batch flush (`sqlite-vec-diskann.c:1476-1502`, `:1336-1344`) | WAL delta + whole-file `segment_seal` (temp + rename) |
| Delete / repair | sqlite-vec LM-Delete: node + vector removal, reverse-edge slot repair, full stale-reference scrub, medoid replacement (`:316-342`, `:1515-1727`); unconfirmed candidates (missing vector) skipped in search (`:823-831`) | tombstones + `hnsw_compact`; segment restore swaps whole state |

## Findings (ranked; no format change in this slice)

**F1 -- Sector-aligned fixed-size node records are the core SSD pattern.**
Every node occupies the same `node_len` bytes; a 4 KB sector holds
`floor(4096/node_len)` whole nodes (never split); larger nodes start
sector-aligned and pad to the next boundary (`disk_index_writer.rs:386-394`).
Addressing is pure arithmetic: `sector = i / nodes_per_sector`,
`offset = (i % n) * node_len` (`disk_sector_graph.rs:30-33`). This is the
shape our D5 base segments should adopt: fixed record size per collection
(dim-dependent), append/write sector-at-a-time, offset math instead of a
parse step.

**F2 -- Co-locate the re-rank data with the adjacency.** DiskANN's node
record stores the full-precision vector AND the neighbor list in the same
sector (`disk_sector_graph.rs:28`): one read serves both the graph hop and
the final re-ranking. For our Q-a design this argues for keeping the
f32 rescore bytes and the int8 codes (and adjacency) in one record, not in
parallel arrays with separate read paths.

**F3 -- Two append models; sqlite-vec's buffer matches our WAL model
better.** DiskANN builds the disk index in one pass (builder + quantizer);
sqlite-vec appends inserts into `_diskann_buffer` and flushes the batch
into the graph when `count >= buffer_threshold` (`sqlite-vec-diskann.c:1476-1502`).
For D5 I recommend the second shape: immutable sector-packed base
segments + a buffered delta tier (our WAL already is the buffer), with
`flush` = sealing a new base segment at checkpoint. Search must merge base
+ delta; the manifest (M-D2/M-D3) already tracks the collection list and
can carry segment generations.

**F4 -- Delete means edge repair OR rebuild; prefer rebuild.** DiskANN
1.0 (LM-Delete) removes the node and repairs every reverse edge plus a
full stale-reference scrub (`:1515-1727`) because its graph IS the
storage. Our tombstone + `hnsw_compact` rebuild is the same *intent* with
a much simpler failure surface; keep it for D6 and treat retention as
"drop sealed segments / re-seal", never in-place edge surgery.

**F5 -- Alignment is a format decision, not an IO detail.** The Rust
reader refuses misaligned offset/length/pointer triplets at construction
(`aligned_read.rs:55-79`), and all buffers are sized to sector multiples.
If P5 (mmap) is ever to map segment records directly, today's TEXT
segment codec forces a full parse; the D5/Q-a segment v2 layout should
already be sector-aligned and binary/word-based in its payload section so
P5 becomes a mapping, not a format migration. (Trade-off: the text v1
format is debuggable; the v2 format can keep a text manifest/header and
make only the vector payload binary.)

**F6 -- Version-discipline mirrors ours.** DiskANN stores the header in
sector 0 and bumps the layout version on any header change
(`graph_header.rs:44-45`); we do the same with `xvector-segment 1` ->
v-next and hnsw codec v2 -> v3. Keep that rule for the D5 record format:
new fields (codes, ranges, generation) = new version, old versions still
loadable or explicitly rejected.

## Design input (concrete)

| Target | Recommendation from this study |
|---|---|
| D5 base segments | Fixed `node_len` record per node: f32 vector + degree + neighbor ids (+ Q-a codes/ranges in the same record); 4096-byte sectors; `node i` addressing by division/modulo; delta tier stays the WAL until checkpoint seals a new base segment |
| D5 search path | Merge base (sector reads via offset math) + delta; re-rank from the co-located f32 bytes (F2); no parse step in the hot path |
| D6 retention | Manifest-level segment generations; drop/seal; never in-place edge repair (F4); medoid/entry fix-up on seal (sqlite-vec's medoid handling is the reference for the equivalent entry-point update) |
| P5 mmap (gated) | Map sector-aligned payloads; node addressing per F1; requires the v2 binary payload (F5); keep header/manifest text for debuggability |

## Explicit non-actions

- No segment format change in this slice: the D4 v2 / Q-a slice decides
  the record layout with its own probe gates (the above is input, not a
  commitment).
- No in-place edge-repair delete implementation (F4).
- No cache tier until M-P's memory budget exists (DiskANN's cached vertex
  provider is the reference shape then).
- No vendoring; adopted patterns land as original implementations with
  our probes.

## Next

1. The Q-a slice (study 02) picks up F1/F2/F5 for the segment v2 record
   layout; probe gates as scheduled there.
2. D5/D6/P5 slices consume F3/F4/F5/F6 when the stdlib fsync/mmap chain
   clears (re-checked every pass).
3. This closes the original study backlog (1-4: FAISS HNSW applied as
   P-a, quantization recon done, sqlite-vec kernel angle covered by study
   02 F1-F3, DiskANN layout covered here).
