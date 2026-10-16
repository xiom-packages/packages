# PROVENANCE: xiom.pulse

This package is a **verbatim carve** of the frozen PULSE protocol core. It
is not an independent re-implementation and not a vendored C binding: the
source files below are XIOM sources taken byte-for-byte from the PULSE
project repository at a pinned commit, with the documented extractions in
`SPEC.md` section 5 (import repoints, product-feature drops, the router
shim and the generic registration seam).

## Upstream

| Field | Value |
|---|---|
| Repository | `https://github.com/xiom-projects/xiom-pulse.git` (remote `origin`, confirmed read-only at extraction time; public since 2026-10-09) |
| Frozen commit | `56eb9f888e3bb5ae1d85bd9bd484fd769a45ff23` (`56eb9f8`, 2026-10-16 17:00:49 +0300) |
| Pair commit | `7924222` (keep-alive Phase A; `56eb9f8` is Phase B) |
| Normative design doc | `docs/DESIGN-KEEPALIVE-DEADLINES.md` at `56eb9f8` (keep-alive A/B semantics) |
| Milestone | `REL-20261016-1401-pulse` (PULSE wrap 18 = `db8d21c`; keep-alive A+B green) |
| License | MIT OR Apache-2.0 (upstream `package.xi` declares the same) |

## Carve method

1. Each source blob was read **read-only** with
   `git -C E:\xiom-projects\xiom-pulse show 56eb9f8:<path>` and staged
   byte-for-byte; the SHA256 column below is over exactly those bytes (LF
   line endings, as stored in the repository).
2. Files marked **verbatim** were copied byte-identically into
   `packages/xiom-pulse/src/` and re-hashed to prove the copy.
3. Files marked **carved+edited** were edited from the byte-identical base;
   every delta is listed in `SPEC.md` section 5 and in the reconciliation
   note below.
4. No other package was read or copied. The registry `xiom.router` package
   was **not** consulted as source for the shim; the shim in
   `src/router.xi` is a 1:1 re-expression of the matching mechanism
   described by the frozen `src/router.xi` comments and the in-repo
   consumer contract (registration order, `:param` capture, 404/405 +
   Allowed methods). `xiom.std` is the only dependency.

## Carved source SHA256 (extraction time, frozen commit `56eb9f8`)

| Source path | SHA256 | Target | Mode |
|---|---|---|---|
| `src/http.xi` | `B48CD8D8F53002F0CD9482FCB6B7673D0A3AB2F194EDCA226DE163D2A40B0969` | `src/http.xi` | verbatim (hash-equal) |
| `src/envelope.xi` | `BFCCB9A32CABB78989BA439299544A16B56DDAD706E4B517D22496DE318FF4C3` | `src/envelope.xi` | verbatim (hash-equal) |
| `src/reqctx.xi` | `FB853D96B43044BC4F0D8BB6FC2427BD6B93D9A2024579BAD106B04C7B2F08A2` | `src/reqctx.xi` | verbatim (hash-equal) |
| `src/pulse.xi` | `858C576A1857856654E913EE61B10B2947B9FAD4D96AE66F3A33C394B39A0D7E` | `src/pulse.xi` | verbatim (hash-equal) |
| `src/router.xi` | `35F573F2861A076E3EBA6666561BE9096A508808E9210A5611822430DA4E3A9A` | `src/router.xi` | carved+edited (shim inlined, `route_match` signature, product table dropped) |
| `src/config.xi` | `A651FB3FF9B3543801522EE5FA4EDBA0CC9B659CDD3B3E0C35069031BD6C859B` | `src/config.xi` | carved+edited (slimmed to six loop getters) |
| `src/server.xi` | `8A9EE18EC1F4A70F400DEEAE58429F51451C12471298C59B8C1F951C0DA522A3` | `src/server.xi` (module `xiom.pulse.app`) | carved+edited (product features dropped, generic seam added) |

Reference blobs read at the same commit (basis for the suite and the
extraction decisions; nothing is copied from them):

| Reference path | SHA256 | Use |
|---|---|---|
| `tests/test_http.xi` | `C4583C31865A484BC6A5A34A09FEA9842A3057EB9C7DD6339FE55AAC61820824` | hardening fixtures ported into `tests/test_conformance.xi` |
| `scripts/http_smoke.ps1` | `6E95A56B985EEFBE08B9B1B5A0ABF3D7DAB9269915198FEB9DE5F581CB3416D8` | keep-alive A/B checks (sections 13e/13f) mined into the suite |
| `tests/test_smoke.xi` | `68F17B3BCEFAF5B7031F324CC2A0E44EF8C1656B78A8C91716D9D50E8EB38568` | identity check (`pulse_version`) |
| `docs/DESIGN-KEEPALIVE-DEADLINES.md` | `A71D54D487570F0EE96E9544FE121BC079C69AD8A3FE5796B6026CE7A1FD6689` | normative keep-alive A/B semantics (SPEC section 3) |
| `README.md` | `A00B4B55B5523C212A4B0DFAAAE363460F11A42078E74197A7A4EAC7E386DAE5` | minimal-example shape ("register a route + start the loop") |
| `package.xi` | `F1799D748CAEBD4C2F263F2A8F8D62CDC80D505696D554377EDD8791DECFB962` | upstream dependency/license record |
| `xiom.toml` | `15529410616084427DCFC7ED946C3049776E50E70FFB44CE0E137024E912C89B` | upstream dependency record |

## Reconciliation note (what was dropped, per file)

- **`src/http.xi`** -- nothing dropped (byte-verbatim; all imports are
  stdlib).
- **`src/router.xi`** -- `use xiom.router;` (registry package) dropped and
  replaced by the inlined `local_router_*` shim; `route_defs()` /
  `routes_list()` (the 25-entry product route table) dropped;
  `route_match` now takes the caller's table. **Nothing else changed.**
- **`src/config.xi`** -- kept: `cfg_parse_port`, `cfg_parse_uint`,
  `cfg_read_timeout`, `cfg_write_timeout`, `cfg_idle_timeout`,
  `cfg_keepalive`, `cfg_port`, `cfg_bind` (verbatim bodies). Dropped:
  `cfg_load_file` + `cfg_apply_str` (PULSE_CONFIG loader), `cfg_validate`
  and all product getters (rate limit/burst, uploads, site/assets/landing,
  csp, cors, csrf, log, audit, store/kv, session, jwt, icon, openapi,
  game).
- **`src/server.xi`** -- kept generic and verbatim: `HandlerOut`,
  `next_rid`, `error_status_body`, `out_json`/`out_text`/`out_html`,
  `recv_bounded`, `request_complete`, `read_request`, `send_step`,
  `send_all`, the dispatch/TE-CL policy in `handle_route`, and the
  connection-loop body with the Phase A+B semantics. Dropped: static/site
  serving (`serve_static_file`/`site_candidate`/`serve_site_page`),
  `load_icon`, JWT, game, multipart, openapi, audit, metrics hooks,
  access log, store/session wiring, CORS branches, CSRF branch, rate
  limiting, product route dispatch (`route_id` if-chain), product CLI
  (`main`), and `with_std_headers` (Date via the registry `xiom.static`
  formatter + `PULSE_CSP`).
- **Not carved at all** (product modules at the frozen commit):
  `audit.xi`, `cors.xi`, `game.xi`, `metrics.xi`, `multipart.xi`,
  `openapi.xi`, `outbound.xi`, `outbound_transport.xi`, `ratelimit.xi`,
  `schema.xi`, `session.xi`, `store.xi`, `validate.xi`.
- **PULSE family packages stay out of the bundle** (session / static / kv /
  rate / metrics / middleware / sqlite): consumers compose them
  separately.

## Target file list (this package)

`package.xi`, `SPEC.md`, `PROVENANCE.md`, `README.md`, `ROADMAP.md`,
`STATUS.json`, `.gitignore`, `src/pulse.xi`, `src/http.xi`,
`src/router.xi`, `src/envelope.xi`, `src/reqctx.xi`, `src/config.xi`,
`src/server.xi`, `src/minimal.xi`, `tests/test_conformance.xi`.
Target tree SHA256 is recorded by the coordinator at commit time; the
source-side hashes above are the extraction record.
