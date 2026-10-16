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
- [ ] retry policy for 429/529/503 with bounded backoff (mirror S9).
- [ ] structured instructions and criteria (object/array forms, S3/S4/S5)
      in the question builders.
- [ ] expose `legend` (level -> description, string or structured) on score
      answers instead of validating-only.
- [ ] confidence formula helpers (S6 choice/score exact formulas) for
      verification and for callers computing their own statistics.
- [ ] api key hygiene per S2: trim, reject internal whitespace/control/
      non-ASCII before the call.
- [ ] base_url validation (scheme/host) before composing the endpoint.
- [ ] content compression (gzip/zstd) and the 32 MiB body rule (S8).

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
