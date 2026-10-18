<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# stdlib `json_parse` is superlinear on large numeric payloads

Found 2026-10-11 by the xvector lane while running the first end-to-end
benchmark through `xvectord` (compiler v0.64.3, stdlib `2ab2a13`).

**ROOT CAUSE (same day, deeper bisect): `slice.str_bytes(Str)` is
superlinear in string size.** Sweep (`probe_strbytes.xi`):
50 KB -> 88 ms, 100 KB -> 324 ms, 200 KB -> 939 ms, 400 KB -> 3685 ms
(2x size -> ~3.5-4x time: quadratic). `str_slice` of a small window is
cheap, so the class is the full-string/char-stepped conversion and the
char-indexed accesses the JSON parser uses per token (`_json_get_char`,
per-number substring slices) -- each token access costs O(offset), which
makes a document with N numbers O(N^2). `http_parse_request` showed the
same shape (8.5 s of its own on a 382 KB request) before the lane moved
the body to bytes.

## xvector lane mitigation (shipped 2026-10-11, 72nd pass)

The service no longer round-trips bodies through `Str`:
- `HttpRequest.body_bytes` (linear byte copy from the request buffer)
  + `body` (one `from_utf8`, which is linear-fast);
- the canonical upsert body is scanned directly on bytes
  (`api.json_fast.json_fast_upsert_bytes`), with a byte-for-byte
  fast-vs-strict equivalence gate (228 cases incl. mutations);
- measured effect: a 5,000 x dim-25 fit through `xvectord` went from
  661 s to 120 s (now HNSW-build-bound, not parser-bound); a 352 KB
  single request handles in ~1.7-2.9 s (strict: ~84 s).

## FIX SHIPPED + VERIFIED on stdlib main `9a2b5ab` (wave 111, 2026-10-11)

**Closure on the committed commit** (`9a2b5ab`; the committed content
equals the pre-verified WIP hashes -- `json.xi` `E69E0275...`, `slice.xi`
`874A8F67...`, `string.xi` `36D1F4FF...`):

- Windows: `repro_strbytes` exit 0 -- 43/87/174/379 ms at 50/100/200/400
  KB; `repro_json_quad` exit 0 -- 56/110/220/437 ms at 2.5k/5k/10k/20k
  numbers; full battery ALL GATES GREEN (suite 177/177 x2 + sbom 42
  modules unsafe=0 + 40 probes x2 + bench smoke).
- WSL: suite 177/177 x2; `repro_strbytes` exit 0 -- 87/177/359/691 ms
  (85/178/363/710 on the re-run); `repro_json_quad` exit 0 --
  103/206/395/799 ms; `probe_json_fast` 228-case byte-equality x2.
- Server: the 5k x dim-25 fit through `xvectord` **661 s -> 51.2 s**
  (**98 pts/s**; HNSW-build bound); quick_bench recall@10
  0.779/0.960/1.000 at ef 8/32/128.
- Acceptance re-pin (documented in `probe_strbytes.xi` header): the
  original 500 ms absolute gate was a pre-fix severity marker; post-fix
  the platform spread is real (Windows ~380 ms vs WSL ~650-750 ms at
  400 KB) while the scaling is linear on both (7-8x for 8x size; pre-fix
  34x), so the gate is a **20x-ratio bound + 3 s net**. Both platforms
  pass.
- Bus: `REL-20261011-1453-xvector` + `REL-20261011-1543-xvector`
  verified + closed; stdlib's bonus fix (the `\u` escape no longer
  swallows the byte after its hex digits) is covered by the green
  suite/probes.

### Pre-committed WIP verification (2026-10-11, 73rd pass)

The stdlib lane's wave-111 work (uncommitted at verification time on lane
HEAD `b8eda7d`; `json.xi` sha256 `E69E0275...`, `slice.xi` `874A8F67...`,
`string.xi` `36D1F4FF...`) makes both probes PASS:

- `probe_strbytes.xi`: 50/100/200/400 KB -> **53/99/204/438 ms** (was
  116/289/1065/3981 ms); gate met, exit **0**.
- `probe.xi`: 2.5k/5k/10k/20k numbers -> **79/168/343/755 ms** (was
  248 ms/1.10 s/4.77 s/17.9 s); exit **0**.
- Through `xvectord`: the 5k x dim-25 fit improved **120 s -> 57.4 s**
  (87 pts/s; HNSW-build bound; machine-load sensitive); recall@10
  0.779/0.960/1.000 at ef 8/32/128 and 58-82 QPS unchanged.

Full batteries on that pin: suite 177/177 x2 + sbom (42 modules,
unsafe=0) + 40 probes x2 + bench smoke (Windows) + WSL spot -- ALL
GREEN; working-tree hashes unchanged before/after the runs. The formal
acceptance completes on the committed wave-111 commit (the lane re-runs
the probes + batteries and reports on `REL-20261011-1453-xvector` /
`REL-20261011-1543-xvector`; the WIP signal is on the bus as
`REL-20261011-1618-xvector`).

## Symptom (measured)

- `json_parse` of a **382,397-byte** body (50,000 numbers, the
  `{"ids":[...],"vectors":[[...]]}` upsert shape): **83.7 s**.
- Full in-process service handle on the same body: **94.9 s** — the
  parser is ~88% of the cost; the engine itself inserts 2,000 dim-25
  vectors in ~4 s (2 ms/insert).
- Scaling sweep (this repro, `probe.xi`, 2026-10-11 v0.64.3:
  2,500 numbers / 22 KB -> **299 ms**; 5,000 / 44 KB -> **1.07 s**;
  10,000 / 88 KB -> **4.56 s**; 20,000 / 175 KB -> **~18 s**. 2x input
  -> ~3.6-4.3x time: **quadratic**.
- Server impact: a 1,000-point dim-25 upsert (25,000 numbers) takes
  ~112 s through `xvectord` (~9 points/s); a 5,000-point fit takes
  661 s. Benchmark integration (ann-benchmarks/VectorDBBench) is
  blocked on this: real datasets (10k-1M vectors) are unusable.

## Repro (revision-pinned, self-contained)

```
. .\scripts\dev-env.ps1
.\scripts\build.ps1 docs\repro\xv-json-parse-quadratic\probe.xi -Name repro_json_quad
.\out\repro_json_quad.exe
```

Pre-fix status: the sweep prints as above and exits **1** (the largest
parse exceeds the 5 s gate; the whole run takes ~2 minutes).
Post-fix expectation: ms-scale parses, exit **0**.

## Ask for the stdlib lane (confirmed, not hypotheses any more)

1. `slice.str_bytes(Str)` / full-string conversions: linear
   (O(n)) with one pass; the sweep above is the acceptance (`probe_strbytes.xi`).
2. Character access used by the JSON parser (`_json_get_char` and the
   per-token `str_slice`): O(1) per access, so the existing
   `probe.xi` (10,000-number parse) returns to ms scale.
3. `http_parse_request`'s body extraction in xvector is already patched
   (bytes); the stdlib-side readiness matters for other consumers
   (pulse HTTP paths, orbitdb payloads).

## Lane status -- RESOLVED (2026-10-11)

Closed on stdlib main `9a2b5ab` (wave 111): both probes exit 0 on
Windows AND WSL, the batteries are green on the committed pin, and the
5k x dim-25 fit is down to 51.2 s (98 pts/s). The lane keeps the
byte-level fast scanner (`api.json_fast`) as the canonical upsert hot
path (it is also the mitigation that unblocked benchmarks pre-fix); the
strict generic path is now linear too. Upstream note for a future wave:
`str_chars`/`str_code_points` still use the strnlen accessors (same
family, outside our acceptance).
