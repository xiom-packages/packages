<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# XVC-C-16 repro: v0.64.5 linux-x64 miscompiles the HTTP service /search path

Found 2026-10-15 during the v0.64.5 archive re-verification (the WSL full
battery went RED: 6 gates, all service/search related).

## Symptom

On v0.64.5 **linux-x64** only (WSL), every search request through
`http_service_handle` misbehaves although the collection exists:

- `/search` knn -> `404 {"error":"not found","kind":"not_found"}`;
- `/search` with `mode":"range"` -> `400 {"error":"range mode does not
  support pagination",...}` (no pagination fields in the body);
- `/search` on an empty collection -> the same 404;
- batch search, `offset`/TOP-k search, and the service probes that embed a
  search (`probe_service_limits` top_k checks, `probe_service_auth` read-key
  search, `probe_http_fuzz` "service intact", `probe_metrics` counters,
  `probe_http_server` socket searches) fail the same way.

Everything else on the wire stays correct (create/upsert/get/stats/delete/
routing/framing); the engine-level search probes and the 177-check suite are
green on the same tree.

## A/B evidence (same tree, same stdlib checkout)

| Build | probe_http_service | repro probe |
|---|---|---|
| v0.64.4 linux-x64 (archive 72a131cc, re-downloaded) | **GREEN (0 failed)** | exit 0 |
| v0.64.5 linux-x64 (archive 246e5e82) | **RED (6 failed)** | exit 3 |
| v0.64.5 windows-x64 (archive bd71e2d3) | GREEN (full battery) | exit 0 |

The failure reproduces identically with the compiler's **bundled stdlib**
(`XIOM_STDLIB` unset), so the stdlib tree is not involved. Direct calls in
the same program are all green under the failing compiler: `select_collection`
-> Ok; `search_request_new` + `search_with_request` -> 2 hits with correct
field readback (`top_k=2 offset=0 after_id=-1`); `json_parse`/`json_get`
extraction -> "docs". The miscompile is context-sensitive to the service
module's search handler lowering (the XVC-C-08/C-09/C-14 family: fields set
via `&mut` setters / struct literals and read back in another function of
the module).

## Run

```powershell
. .\scripts\dev-env.ps1
.\scripts\build.ps1 docs\repro\xv-http-service-linux\probe.xi -Name repro_service_search
.\out\repro_service_search.exe    # expect exit 0 on v0.64.4/v0.64.5-windows
```

```bash
cd /mnt/e/xiom-projects/xiom-xvector
. scripts/dev-env.sh
bash scripts/build.sh docs/repro/xv-http-service-linux/probe.xi repro_service_search
./out/repro_service_search        # v0.64.5 linux: exit 3
```

The probe prints each wire response body and the direct-API controls; exit =
failed checks.

## Additional narrowing (parallel session, 2026-10-15)

A second xvector session filed the same regression independently
(`REL-20261015-2251-xvector`, since merged/closed into this item by its
reporter) and narrowed it further:

- `http_parse_request` on the exact bytes `POST /search HTTP/1.1 ...`
  returns byte-identical method/path ([/search]) on both compilers and
  platforms;
- a byte-exact replica of the private `path_segments("/search")` plus
  `segs[0] == "search"` MATCHES on both Linux compilers (and Windows).

So the divergence sits **deeper than path parsing / string comparison**
-- in the dispatcher layer (auth middleware chain, body/JSON gating, or a
helper it calls), consistent with the context-sensitive lowering
diagnosis above.

## Filing

Bus item `REL-20261015-…-xvector` (to compiler), filed 2026-10-15 with the
A/B table above; cross-refs: the v0.64.5 archive re-verification pass and the
thread-gate acceptance (both thread items verified green on this archive on
BOTH platforms -- this regression is unrelated to the thread fixes).
