# ROADMAP: xiom.pulse

Current state: v0.1.0 (incubating), the frozen PULSE protocol core carved
from `56eb9f8` (keep-alive A+B). 125/125 checks green x2 on XIOM v0.64.5.
Tier map: **Beacon** = this embeddable package; **Station** = the standalone
PULSE product (one core, never a fork).
See `SPEC.md` (declared surface, caps, deviations), `PROVENANCE.md`
(pinned commit + per-file SHA256) and `STATUS.json` (verification record).

Nothing below is implemented; each item is a candidate for a future
version and requires its own conformance slice before shipping.

## Post-extraction integration (coordinator lane)

1. **Family composition, never a fork.** The PULSE family packages
   (session / static / kv / rate / metrics / middleware / sqlite) are
   consumed *alongside* `xiom.pulse` by application code; they are not
   bundled and not forked into this package.
2. **The Station product consumes this package.** The Station product
   (and any sibling product of the PULSE line) must depend on
   `xiom.pulse` from the registry exactly as published -- never copy the
   carved sources back into a product repo.
3. **Registry publish.** New name: the ops scope review + the
   `publish-allowlist.txt` append are pending (Beacon registry tier;
   `STATUS.json` `excluded_reason` records this).

## Near term (0.1.x) -- candidates

4. **Date/CSP seam documented in SPEC section 5 item 5**: either a
   stdlib-only HTTP-date formatter (or an injected `with_header_line`
   wrapper shipped as a helper) so consumers can re-add the `Date`
   header without the dropped registry `xiom.static` dependency.
5. **Access-log seam**: a consumer-supplied per-request callback (the
   frozen loop's `access_log` call sites are dropped); only if a consumer
   asks for it -- the loop stays minimal until then.
6. **Multi-handler dispatch helper**: the current seam is one `fn`
   handler dispatching on `PulseRoute.route_id`; a small table of
   `(route_id, fn)` helpers would be sugar over the same mechanism.

## Medium term (0.2+)

7. **Accept-loop fairness**: a select/poll-capable stdlib would let the
   loop drain readiness instead of blocking in `accept` (out of scope at
   v0.64.5; the frozen architecture is sequential-accept by design).
8. **HTTP/1.0 keep-alive opt-in**: deliberately NOT planned -- the frozen
   semantics follow the h11 simplification (1.0 peers never reuse).
9. **Trailer exposure**: decoded trailers are validated and skipped by
   the frozen parser; surfacing them would change `PulseRequest` and is
   frozen out of 0.1.x.

## Long term (exploratory)

10. **Re-carve procedure**: when the upstream PULSE repo moves past the
    `56eb9f8`/`7924222` pair, a re-carve pins the new commit, replays the
    carve method in `PROVENANCE.md`, re-derives the SHA256 table, and
    diffs against this package's target files; it must not silently track
    `main`.
