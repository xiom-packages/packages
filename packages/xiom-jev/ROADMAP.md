<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# xiom.jev -- ROADMAP

## M1 -- client tier core (DONE, 0.1.0, 2026-10-16)

- state (text | JSON) + typed questions (choice / score / noul), several per
  request (fan-out), one validator + request builder (byte-exact JSON).
- response parser: typed answers, probability distributions, confidence,
  usage; fail-closed validation with a stable typed Parse catalog.
- deterministic selection core: argmax, inclusive threshold,
  sample-by-probability from caller-supplied entropy; score round/normalize;
  noul gate and |2p-1| spread.
- typed `JevError` catalog; transport over the xiom.http client surface.
- offline conformance suite 82/82 x2 on v0.64.5; SKIP-safe live probe.

## M2 -- transport completion and structured surface

- [x] custom request headers in xiom.http (upstream) -- DONE 2026-10-16:
      xiom.http 0.1.8 `http_headers_blob` + `http_request`; `system_one`
      attaches `Authorization: Bearer`. Probe re-run with a real key still
      pending (no key in this lane).
- [x] retry policy for 429/529/503 with bounded backoff (mirror S9) --
      DONE 2026-10-16: `xiom.jev.retry` (pure classification + deterministic
      exponential backoff, 4 attempts / 500 ms base / 30 s cap) and the
      `xiom.jev.client.system_one` retry loop (`xiom.time.sleep_ms`). Policy
      core is offline-golden-tested; the client stays `--check`-clean.
- [x] structured instructions and criteria (object/array forms, S3/S4/S5)
      in the question builders -- DONE 2026-10-16: `*_json` builders in
      `xiom.jev.types` (instructions, choice options, score levels, noul
      true/false), emitted verbatim by `build_request`; string fixtures stay
      byte-exact; offline-golden-tested (suite t31..t35).
- [x] expose `legend` (level -> description, string or structured) on score
      answers instead of validating-only -- DONE 2026-10-16: `Answers` gains
      `legend_*` parallel vectors (raw JSON values, so string and object/array
      forms round-trip) and `xiom.jev.types` gains
      `response_legend_count/label/doc/is_structured/text/find/json`;
      offline-golden-tested (suite t36..t37).
- [ ] confidence formula helpers (S6 choice/score exact formulas) for
      verification and for callers computing their own statistics -- BLOCKED:
      SPEC.md does not pin the exact S6 choice/score formulas (only the noul
      `|2p-1|` spread). Skipped cleanly in the M2-chunk-3 lane rather than
      inventing semantics; needs the Architect to pin the formulas first.
- [x] api key hygiene per S2: trim, reject internal whitespace/control/
      non-ASCII before the call -- DONE 2026-10-16:
      `xiom.jev.api_key_validate` (typed BadRequest; returns the trimmed key);
      wired into `system_one`; offline-golden-tested (suite t38).
- [x] base_url validation (scheme/host) before composing the endpoint --
      DONE 2026-10-16: `xiom.jev.base_url_validate` (http/https scheme,
      non-empty host; typed BadRequest); wired into `system_one`;
      offline-golden-tested (suite t39).
- [x] content compression (gzip/zstd) and the 32 MiB body rule (S8) --
      DONE 2026-10-17 (client wiring): `xiom.jev.compression` pins the
      inclusive 32 MiB logical-body rule and provides the pure
      `encoding_check`/`prepare_body` wire plan; `system_one_with_encoding`
      sends gzip through xiom.http 0.1.9 `http_request_bytes` with the exact
      Content-Length and `Content-Encoding: gzip`, while identity keeps the
      original Str path byte-identical (suite t43..t44; probe gzip leg is
      SKIP-safe). zstd remains a typed "compressor is not available" path
      (vendored-C/FFI binding, deliberately not wired).

## M3 -- decision-systems ergonomics

- [ ] hierarchical classification helper: beam search over Choice
      probabilities keeping the best K paths per level (S3 cookbook).
- [ ] composite scoring helper: weighted combine of normalized scores
      (S4 pattern) with integer weights.
- [ ] danger-zone `box` question/answer + media assets (needs the image
      headers and a vision model; S8).
- [ ] batch/streaming ergonomics: multiple requests in flight with the same
      question set; caller-side scheduling only (no async runtime here).

## Tracking notes

- Upstream dependencies: `xiom.ssl` eventually for a pluggable TLS story.
  The libcurl bridge (consumer-side, per the xiom.http recipe) remains the
  transport.
- Pairing: `xiom.llm` is the System Two (text) tier; systems combine both --
  Jev for the typed decision, the runner for generated text.
