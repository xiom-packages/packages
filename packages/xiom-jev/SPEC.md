<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# xiom.jev -- SPEC (M1)

`xiom.jev` 0.1.0 -- the TypeSafe Jev client tier ("System One" structured
decisions) of the ML/AI coverage program, paired with `xiom.llm` (System
Two text). This file is the doc-of-record for the M1 slice: sources, surface,
rules, catalog, evidence, deviations and open items.

## 1. Identity and M1 scope

JEV = System One: structured decisions where the answer space is known in
advance. One request carries a state (text or JSON) and a set of typed
questions (several per request, evaluated in parallel server-side); the
response carries one typed answer per question with the full probability
distribution and (choice/score) confidence.

M1 (this package, implemented): state (text | JSON), typed questions
(choice / score / noul), request builder, response parser (typed answers +
micro-unit probabilities + confidence + usage), deterministic selection
helpers (argmax / threshold / sample-by-probability from caller-supplied
entropy), typed Err catalog, transport over the xiom.http client surface
(0.1.9 for the compressed path) + xiom.serialize.json.

Out of M1 (see ROADMAP.md): structured instructions/criteria (objects and
arrays), the danger-zone `box` question/answer, media assets, compression,
retry/backoff policy, hierarchical-classification helpers, legend exposure.

## 2. Schema sources and fixture map

Sources (fetched 2026-10-16; read-only references):

| # | Source | Used for |
|---|---|---|
| S1 | https://docs.typesafe.ai/introduction | concepts: primitives, System One, atomic questions, fan-out motivation |
| S2 | https://docs.typesafe.ai/introduction/quickstart | exact endpoint/auth/body/raw-response shape; the 3-question ticket example |
| S3 | https://docs.typesafe.ai/primitives/choice | Choice request/response schemas; the 1-question and 5-question triage examples; structured criteria |
| S4 | https://docs.typesafe.ai/primitives/score | Score request/response schemas; score = probability-weighted level mean; legend; structured levels |
| S5 | https://docs.typesafe.ai/primitives/noul | Noul request/response schemas; optional true/false criteria; no confidence |
| S6 | https://docs.typesafe.ai/confidence | confidence semantics (choice/score formulas; noul = |2p-1|) |
| S7 | https://docs.typesafe.ai/patterns/fan-out | send all questions in one call; route in code |
| S8 | https://api.typesafe.ai/openapi.json (v0.2.0) | SystemOneRequest/SystemOneResponse schemas; limits (choice 1..255 options, score 1..10 levels); HTTPValidationError (`{"detail":[{"loc","msg","type"}]}`) for 422; HTTPBearer auth |
| S9 | https://github.com/browser-use/jev-ultrafast (MIT), commit `1231850a0bf1a0c0341fe408ef1668dbbfdfac46` | real request/response payload shapes (`jev_ultrafast/model.py`: state as text|object, questions map, `probabilities`/`confidence`/`choice` validation, `usage` optional, retry on 429/529/503) |

Fixture map (tests/test_conformance.xi):

| Test | Mirrors |
|---|---|
| t1 | S3 first request (department Choice) byte-exact; t2: S2 quickstart request byte-exact (3 mixed questions); t3: S5 criteria true/false + S3 null-description option; t4: S8 state-as-object |
| t5/t6 | validation limits from S3 (255 options), S4 (min 2 / max 10 levels), S8 (minProperties 1) |
| t7 | S3 first response example; t8: S3 five-question triage response; t9: S4 bug_severity response (score 1.43); t10: S4 structured-levels response (legend values as objects); t11: S5 two-noul response; t12: S9 optional usage (reference client's `result.get("usage", {})`) |
| t13..t16 | S8 required fields + S9 fail-closed validation intent (choice present & argmax, sum tolerance) |
| t17 | forward compatibility (unknown extra fields ignored) |
| t18..t22 | S3/S6 thresholds and S7 "route in code"; entropy boundaries are package rules (section 7) |
| t23..t26 | presentation + endpoint + error-body decode (S8 422 shape) |

## 3. Declared module surface

| Module | M1 public surface |
|---|---|
| `xiom.jev` | `default_model`, `default_base_url`, `version`, `systemone_endpoint`, `api_key_validate`, `base_url_validate` |
| `xiom.jev.types` | `state_text`, `state_json`, `question_choice`, `question_add_option`, `question_add_option_json`, `question_score`, `question_add_level`, `question_add_level_json`, `question_noul`, `question_set_noul_criteria`, `question_set_noul_criteria_json`, `question_set_instructions_json`, `doc_is_set`, `answers_new`, `response_new`, accessors (`response_count/id/kind/find/choice/confidence_micro/score_micro/noul_micro/prob_count/prob_label/prob_micro/prob_find/prob_total_micro/legend_count/legend_label/legend_doc/legend_is_structured/legend_text/legend_find/legend_json/has_usage/input_tokens/output_tokens`), `kind_name`, `micro_text`, constants `MICRO`, `KIND_CHOICE`, `KIND_SCORE`, `KIND_NOUL` |
| `xiom.jev.request` | `build_request` |
| `xiom.jev.response` | `parse_response`, `api_error_detail` |
| `xiom.jev.selection` | `answer_argmax`, `answer_argmax_label`, `answer_max_micro`, `answer_count_at_or_above`, `answer_labels_at_or_above`, `answer_sample_index`, `answer_sample_label`, `choice_answer_covers_question`, `score_round_level`, `score_normalized_micro`, `noul_yes`, `noul_confidence_micro` |
| `xiom.jev.errors` | `JevError`, `jev_error_kind`, `jev_error_text` |
| `xiom.jev.compression` | `max_body_bytes`, `body_size_check`, `encoding_name`, `encoding_from_name`, `encoding_supported`, `encoding_check`, `wire_uses_bytes`, `compress_bytes`, `compress_body`, `prepare_body`, `bytes_copy`, type `EncodedBody`; constants `MAX_BODY_BYTES`, `ENCODING_IDENTITY`, `ENCODING_GZIP`, `ENCODING_ZSTD` |
| `xiom.jev.beam` | `beam_level_new`, `beam_add_option`, `beam_level_len`, `beam_level_from_answer`, `beam_search`, `beam_result_count/width/levels/path_levels/path_score/path_label/path_text`, `beam_path_score/levels/text`; types `BeamLevel`, `BeamPath`, `BeamResult` |
| `xiom.jev.client` | `system_one` (identity path), `system_one_with_encoding` (explicit `Content-Encoding` selection) |

Per the program brief there are NO contracts (`requires:`/`ensures:`) on new
functions; every accessor guards its indices (out-of-range returns ""/-1/0 as
documented) and every rejected input returns a stable typed error string.

## 4. Micro units and the JSON boundary

- prob / confidence / noul in [0,1]: stored as `micro = round(value * 1000000)`
  (round half away from zero, `math.round`), range [0, 1000000].
- score: stored as `score_micro = round(score * 1000000)`; one rubric level is
  1000000 micro (domain 0 .. top level, max 9000000 for 10 levels).
- tokens: `math.round(value)` after a non-negative check.
- The ONLY Float64 touch points are parsing a response number and letting
  `json_stringify` render numbers inside a JSON state. All selection/
  rendering arithmetic is integer-only. `NaN` fails the `>=`/`<=` bounds
  (a NaN comparison is false), so non-finite values are rejected as
  out-of-range.

## 5. Request shape and validation

Body (insertion-ordered, compact): `{"state":...,"model":...,"questions":{id:
{"type","instructions",["criteria"]}}}`. Choice criteria = object of option ->
description (empty description -> `null`, per S3); Score criteria = ordered
array of level descriptions; Noul criteria = object emitted only when at
least one of true/false is non-empty, keys in order `true`, `false` (S5).
Question ids are never sent to the model (S2/S3) but are the answer keys.

Structured forms (M2 chunk 2, S3/S4/S5): `instructions` and each criteria
entry may be a string, an object or an array. The `*_json` builders in
`xiom.jev.types` set a `JsonValue` doc that is emitted verbatim in place of
the string (a JSON-null doc means "not set"); `criterion_docs` stays
parallel to the option/level vectors, so string and structured entries can
be mixed in one question. An instruction counts as present when its string
is non-empty or its doc is set; a Score level likewise (a structured level
carries no string). A Choice criterion's JSON-null doc falls back to the
string rule ("" -> `null`).

Rejections (BadRequest). Order: model -> state -> question count -> per
question (id, duplicates, instructions, kind-specific):

| Reason string |
|---|
| `request: model is empty` |
| `request: state is empty` (text states only; an empty JSON document is allowed) |
| `request: no questions` |
| `request: question <i>: id is empty` (i = 0-based position) |
| `request: duplicate question id '<id>'` |
| `request: question '<id>': instructions is empty` |
| `request: question '<id>': choice needs at least one option` |
| `request: question '<id>': choice has more than 255 options` |
| `request: question '<id>': choice options are malformed` (labels/texts drifted) |
| `request: question '<id>': choice option <j>: label is empty` |
| `request: question '<id>': score needs at least 2 levels` |
| `request: question '<id>': score has more than 10 levels` |
| `request: question '<id>': score level <j>: description is empty` |
| `request: question '<id>': unknown question kind` |

`instructions is empty` and `score level <j>: description is empty` fire
only when BOTH the string is empty and no structured doc is set for that
position.

## 6. Error catalog

`JevError` variants and `jev_error_text` rendering:

| kind | variant | text | trigger |
|---|---|---|---|
| 0 | `BadRequest(reason)` | `jev: bad request: <reason>` | section 5; `client: base_url is empty`; `client: base_url scheme must be http or https`; `client: base_url host is empty`; `client: api_key is empty`; `client: api_key has invalid characters` |
| 1 | `Transport(reason)` | `jev: transport: <reason>` | the libcurl bridge failed (no HTTP response; reason is the curl-level message) |
| 2 | `HttpStatus(code, detail)` | `jev: http <code>: <detail>` | non-2xx status; `detail` = decoded API error message else the first 200 chars of the raw body |
| 3 | `Parse(reason)` | `jev: parse: <reason>` | section 6.1 |

Response Parse reasons (all prefixed `response: `; per-answer ones use
`response: answer '<id>': `):

- structural: `invalid JSON`, `root is not an object`, `missing model`,
  `model is not a string`, `model is empty`, `missing answers`,
  `answers is not an object`, `answers is empty`, `answer '<id>': not an
  object`, `answer '<id>': missing type`, `answer '<id>': type is not a
  string`, `answer '<id>': unknown answer type '<t>'` (includes `box` in M1).
- choice: `missing choice`, `choice is not a string`, `choice is empty`,
  `missing probabilities`, `probabilities is not an object`, `probabilities
  is empty`, `probability '<l>' is not a number`, `probability '<l>' out of
  range`, `probabilities sum out of tolerance`, `choice '<l>' is not in
  probabilities`, `choice '<l>' is not the highest-probability option`,
  `missing confidence`, `confidence is not a number`, `confidence out of
  range`.
- score: `missing score`, `score is not a number`, `score out of range`
  (domain [0, 10]), `missing legend`, `legend is not an object`, `legend is
  empty`, `probability '<l>' is not in legend`, plus the choice set above
  (probabilities/confidence/sum).
- noul: `missing noul`, `noul is not a number`, `noul out of range`.
- usage: `usage is not an object`, `usage.input_tokens is not a number`,
  `usage.input_tokens out of range`, `usage.output_tokens is not a number`,
  `usage.output_tokens out of range`.

Validation semantics: probability keys/legend values may be strings or
structured (S4); a choice's selected option must be present in probabilities
and be a maximum (mirrors S9's `validate_choice`); a score's probability keys
must be a subset of legend keys; distribution sums must be within +/- 2% of
1.0 (micro sum in [980000, 1020000], mirroring S9's tolerance); `usage` is
optional (S9) and its token keys are optional within it; unknown extra fields
are ignored (forward compatibility). Answer order follows wire order.

`xiom.jev.compression` (S8, section 15) adds these BadRequest reasons:
`request: body exceeds 32 MiB limit` (body size > 33554432 bytes),
`compression: body size is negative`, `compression: unknown encoding '<name>'`,
`compression: unknown encoding <tag>`, and
`compression: zstd compressor is not available`. `compression.encoding_check`
is the pure selection gate and reuses the last two strings for an unsupported
selected compressor; `compression.prepare_body` applies the logical-body size
rule before that gate.

## 7. Selection rules (pinned)

- `answer_argmax`: index of the maximum micro; ties -> lowest index; an
  all-zero vector with >= 1 entry -> index 0 (documented corner); no
  probabilities -> -1.
- Threshold (`answer_count_at_or_above` / `answer_labels_at_or_above`):
  inclusive (`micro >= threshold`); labels in criterion order.
- `answer_sample_index(r, i, entropy)`: the package never draws entropy;
  the caller supplies any Int. `u = ((entropy % total) + total) % total`
  (Euclidean modulo; negative entropy wraps deterministically). Option j owns
  the half-open interval `[cum_before, cum_before + p_j)` in wire order; an
  exact cumulative boundary selects the later option. Zero-probability
  options are never selected. `total <= 0` or no probabilities -> -1. Same
  entropy + same distribution -> same index, on every run and platform.
- `score_round_level`: nearest level, halves away from zero.
- `score_normalized_micro(score_micro, top_level)`: score / top_level, halves
  away from zero (integer q/r rule); `top_level <= 0` -> 0.
- `noul_yes`: inclusive threshold gate. `noul_confidence_micro`: `|2p - 1|`
  (S6's Noul formula).
- `micro_text`: integer-only rendering, trailing zeros stripped
  (`610000 -> "0.61"`, `1000000 -> "1"`, negatives -> `"0"`).

## 8. Transport, known gap, live probe

`system_one(base_url, api_key, model, state, questions)` composes
`<base_url>/v1/systemone` (trailing slashes collapsed), builds the body,
builds the header blob (`Authorization: Bearer <api_key>` +
`Content-Type: application/json` via `xiom.http.headers`), calls
`xiom.http.http_request(endpoint, "POST", body, blob)`, and parses 2xx
bodies. `system_one_with_encoding(..., encoding)` adds the S8 compression
selection: identity takes that exact Str path (byte-identical to the 0.1.8
behavior), while gzip builds the logical body, compresses it with
`xiom.jev.compression.prepare_body`, and sends the exact frame plus its exact
`content_length` through the binary-safe xiom.http 0.1.9
`http_request_bytes`, with `Content-Encoding: gzip` in the same header blob.
No new FFI; TLS is the consumer's libcurl bridge.

**RESOLVED 2026-10-16 -- Authorization:** the xiom.http 0.1.8 surface ships
custom request headers (`http_headers_blob` + `http_request`; commit
`249f1d61`), so the `Authorization: Bearer <key>` header (S2/S8, HTTPBearer)
now goes out on the wire. A live 2xx needs only a valid key; a typed 401
with its decoded detail is reported by the probe as `[SKIP]` (key/permission
trouble, never as PASS). Before the POST, `system_one` runs the pure hygiene
helpers: `base_url_validate` (scheme http/https, non-empty host) and
`api_key_validate` (S2 trim; after trimming every byte must be printable
ASCII, so internal whitespace/control/non-ASCII fail with a typed
BadRequest). The trimmed key is what goes into the header; the raw key is
never logged or stored.

Probe invocation (documented in README and tests/probe_live.xi; read the key
from the environment only, never store it):

```powershell
xiom --run packages\xiom-jev\tests\probe_live.xi `
  --c-source packages\xiom-http\bridge\xiom_http_shims.c `
  --link curl --link-path <scratch-with-curl.lib>
```

Evidence (this session, 2026-10-16): `xiom --check tests\probe_live.xi`
-> "Type check PASSED"; full build with the shim + vcpkg `libcurl.lib` copied
as `curl.lib` + `libcurl.dll` on PATH -> compiled, ran, printed
`[SKIP] TYPESAFE_API_KEY is not set; no network call made`, exit 0.

## 9. Deviations from the references

1. **Float-free micro units** (house style; compiler trap: no `Vec[Float64]`):
   probabilities/confidence/noul/score are Int micro units; the reference
   client (S9) and SDKs use floats. Conversion happens once at the JSON
   boundary with documented rounding.
2. **Tighter choice validation**: S9 checks `probabilities[choice] >= max -
   1e-6`; here the parser requires `micro[choice] == max` after rounding and
   additionally requires |sum - 1| <= 0.02 (same tolerance as S9, applied in
   micro).
3. **`box` answers rejected** as unknown type in M1 (danger-zone API, needs
   `TypeSafe-Danger-Zone-Images` and vision models; S8).
4. ~~**Structured instructions/criteria not built**~~ RESOLVED 2026-10-16
   (M2 chunk 2): object/array/string forms are accepted through the `*_json`
   builders (see section 5 and section 13); the plain-string builders and the
   M1 byte-exact fixtures are unchanged.
5. **No retry policy**: S9 retries 429/529/503 with backoff; M1 returns the
   typed `HttpStatus` and leaves retry to the caller (ROADMAP).
6. ~~**No base_url/API-key whitespace normalization**~~ RESOLVED 2026-10-16
   (M2 chunk 3): `api_key_validate` trims the key and rejects internal
   whitespace/control/non-ASCII; `base_url_validate` enforces an http/https
   scheme and a non-empty host (see sections 3, 6, 8, 14).
7. **`usage` optional** (mirrors S9, though S8 lists it required).

## 10. Test strategy and evidence

- Suite: `tests/test_conformance.xi` -- 47 test functions, **210/210 checks
  passed, x2** (two consecutive runs at the end of the M3-pin-gate lane) via
  `& .\scripts\port.ps1 -Package xiom.jev -TimeoutSec 240` on compiler
  `v0.64.8` (native-session, 2026-10-19); `program_exit=0` both runs. History:
  26 functions/82 checks at M1; +4 functions (retry) -> 86; +5 functions
  (structured instructions/criteria) -> 91; +4 functions (legend exposure x2,
  api-key hygiene, base_url validation) -> 110; +3 functions (32 MiB boundary,
  compression encodings, pre-compression gate) -> 143; +2 functions (encoding
  selection/wire plan, request-builder gzip plan) -> 169; +3 functions
  (beam golden/tie/determinism, beam typed errors, answer bridge) -> 210
  (the boundary/encoder/selection/beam functions emit one check per case).
- Offline/deterministic: no API key, no network, no randomness; selection
  uses hand-supplied entropy; request fixtures are compared byte-exact.
- Link-free: the suite never imports `xiom.jev.client` (the transport links
  the libcurl bridge); the client is covered by `xiom --check` and the probe.
- STATUS.json is seeded (`incubating`, `tests: unknown`, `publish: false`)
  per the program's porter conventions; recording the run is the
  coordinator's step.

## 11. Unresolved items

1. ~~Custom request headers in xiom.http~~ RESOLVED 2026-10-16: xiom.http
   0.1.8 shipped `http_headers_blob` + `http_request` (commit 249f1d61), and
   0.1.9 adds binary-safe `http_request_bytes`; `system_one` attaches
   `Authorization: Bearer` -- the probe's [PASS] leg is reachable with a
   valid key (item 2 below still applies: none available here).
2. **Live verification** of the 401 detail decode and of a real 2xx parse
   could not be exercised here: no `TYPESAFE_API_KEY` is available in this
   session (by design none is stored).
3. **Confidence formula reimplementation** (S6 choice/score formulas): still
   not exposed. This SPEC pins only the noul spread `|2p - 1|` (section 7,
   `noul_confidence_micro`); the exact S6 choice/score formulas are not
   defined here, so the M2-chunk-3 lane skipped the helper cleanly rather than
   inventing semantics (the API-returned confidence is carried through
   unchanged). Blocked on the Architect pinning the S6 formulas in this file.
4. **`Vec[StructType]` / `&Result` compiler traps**: `Result` payloads must
   be read via a local binding or matched by value (a `&Result` parameter
   that reads `r.value` crashes with an access violation on `v0.64.5`,
   reproduced in scratch probes during this build); the package and suite
   follow the safe patterns everywhere.
5. ~~**Compressed request bodies over the live transport**~~ RESOLVED
   2026-10-17 (M2 chunk 5): xiom.http 0.1.9 ships binary-safe
   `http_request_bytes` (exact `CURLOPT_POSTFIELDSIZE`, no UTF-8 re-encode);
   `system_one_with_encoding` now sends gzip frames end-to-end. See sections
   15 and 16.
6. **zstd compressor**: declared as `ENCODING_ZSTD` but unavailable (typed
   error). The in-tree `xiom.zstd` binding is vendored-C/FFI and would break
   the package's link-free offline suite; wiring it needs a deliberate
   FFI/port-args allowance. See section 15.

## 12. M2 progress (increment 1: retry policy)

First M2 chunk (ROADMAP M2 bullet 2, "retry policy for 429/529/503 with
bounded backoff (mirror S9)"). New module `xiom.jev.retry`:

- `retry_is_retryable(status)` -- 1 for the transient statuses 429 / 503 /
  529, else 0 (pure).
- `retry_backoff_millis(attempt, base_millis, cap_millis)` -- `base *
  2^(attempt-1)` clamped to `cap`; `attempt` is the 1-based retry number, so
  the first retry is `base`. `attempt < 1` or `base < 1` -> 0; `cap < 1`
  means no cap (growth still bounded to 2^39 * base to avoid overflow). No
  clock, no randomness, no jitter -- a pure integer function.
- `default_max_attempts()` = 4 (initial + 3 retries), `default_base_millis()`
  = 500, `default_cap_millis()` = 30000.

`xiom.jev.client.system_one` drives the policy: the POST is attempted up to
`default_max_attempts()` times; a retryable non-2xx sleeps
`retry_backoff_millis(attempt, base, cap)` via `xiom.time.sleep_ms` and
retries; transport failures (no HTTP response) and non-retryable statuses
surface immediately. The non-2xx `HttpStatus` mapping and the decoded
`detail` are unchanged (section 6). The client stays `xiom --check`-clean.

The retry core is fully offline-golden-tested (suite t27..t30, 4 checks,
exact values including the doubling/cap sequence and the overflow bound); no
live network is involved.

## 13. M2 progress (increment 2: structured instructions/criteria)

Second M2 chunk (ROADMAP M2 bullet 3, "structured instructions and criteria
(object/array forms, S3/S4/S5) in the question builders"). The question
builders gained structured setters and the request builder emits them
verbatim:

- `xiom.jev.types.question_set_instructions_json(q, doc)` -- sets an
  object/array `instructions` value (S3/S4/S5).
- `xiom.jev.types.question_add_option_json(q, label, doc)` -- Choice
  criterion as object/array/string (S3); `criterion_docs` stays parallel to
  the label/text vectors.
- `xiom.jev.types.question_add_level_json(q, doc)` -- Score level as
  object/array (S4).
- `xiom.jev.types.question_set_noul_criteria_json(q, yes, no)` -- Noul
  true/false criteria as object/array/string (S5); either side may be
  JSON-null (omitted).
- `xiom.jev.types.doc_is_set(doc)` -- 1 when the doc is not JSON null (the
  "string form is used" sentinel).

A set doc is emitted verbatim and overrides the string form, so the M1
string fixtures stay byte-exact. Validation treats an instruction/level as
present when either the string is non-empty or a doc is set. The client path
is unchanged: `system_one` calls `build_request`, so structured questions
travel the existing offline encoder and live-capable transport.

Fully offline-golden-tested (suite t31..t35, 5 checks): the S3 structured
choice example (object instructions + object option criteria), the S4
structured score example (array of object levels), the S5 structured noul
instructions example (object with a nested `potential_duplicate` record and
an array-form instruction variant), structured true/false noul criteria, and
a mixed string/object/array/null choice + score fixture. No live network is
involved.

## 14. M2 progress (increment 3: legend exposure + transport input hygiene)

Third M2 chunk (ROADMAP M2 bullets 4, 6 and 7). Score-answer legends are now
carried through parsing instead of validating-only, and the transport inputs
are validated before any network call:

- **Legend exposure** (ROADMAP bullet 4). The parser stores each score
  answer's legend (level key -> description) in the `Answers` parallel
  vectors `legend_starts`/`legend_counts`/`legend_labels`/`legend_docs`, where
  `legend_docs` holds the raw JSON value so both the plain-string and the
  structured (object/array) S4 forms round-trip. Choice/noul answers carry an
  empty legend (count 0). New accessors in `xiom.jev.types`:
  `response_legend_count/label/doc/is_structured/text/find` (all index-guarded)
  and `response_legend_json`, which rebuilds the legend object for emission.
- **API-key hygiene** (ROADMAP bullet 6, S2). `xiom.jev.api_key_validate`
  trims leading/trailing ASCII whitespace and then requires every remaining
  byte to be printable ASCII (0x21..0x7E); empty-after-trim ->
  `client: api_key is empty`, any internal whitespace/control/non-ASCII ->
  `client: api_key has invalid characters`. It returns the trimmed key, which
  is what `system_one` sends.
- **base_url validation** (ROADMAP bullet 7). `xiom.jev.base_url_validate`
  requires an `http://` or `https://` scheme and a non-empty host (the text
  between the scheme and the first `/`); empty/all-slash stays
  `client: base_url is empty`. `system_one` runs it before building the
  request, so a malformed base fails typed and offline.
- **S6 confidence formulas**: skipped cleanly (see section 11 item 3) -- this
  SPEC does not define the exact choice/score formulas.

`system_one` now validates both inputs through these pure helpers (still
`--check`-clean); they are unit-tested offline in the suite rather than
through the libcurl-linked client. Fully offline-golden-tested (suite
t36..t39): string and structured legend exposure (labels/order/text/
structured flag/emission bytes), the api-key trim/reject matrix, and the
base_url scheme/host matrix. No live network is involved.

## 15. M2 progress (increment 4: S8 body rule and compression)

Fourth M2 chunk (ROADMAP M2 bullet 8, "content compression (gzip/zstd) and
the 32 MiB body rule (S8)"). New module `xiom.jev.compression`; the client
applies the body rule before the POST.

**The 32 MiB rule (pinned).** The limit is inclusive and counts bytes:

| logical body bytes | verdict |
|---|---|
| 0 .. 33554431 (32 MiB - 1) | accepted |
| 33554432 (32 MiB exactly) | accepted |
| 33554433 (32 MiB + 1) and above | rejected: `request: body exceeds 32 MiB limit` |
| negative size | rejected: `compression: body size is negative` |

The rule applies to the logical request body produced by `build_request` (the
uncompressed JSON bytes), BEFORE any `Content-Encoding` is applied, so
compression cannot be used to sneak an oversized logical body past the rule.
`xiom.jev.client.system_one` runs `compression.body_size_check(body.len())`
immediately after `build_request` and before building the header blob or
calling the transport, so an oversized body is rejected typed with no network
call. `compression.compress_body` enforces the same check before it runs an
encoder.

**Encodings.** Tags are stable integers exposed as constants:

| tag | token | support |
|---|---|---|
| `ENCODING_IDENTITY` (0) | `identity` | yes -- byte-exact pass-through |
| `ENCODING_GZIP` (1) | `gzip` | yes -- RFC 1952 frame via the pure-XIOM stdlib `xiom.compress.gzip` (no FFI, no vendored C) |
| `ENCODING_ZSTD` (2) | `zstd` | **no** -- typed `compression: zstd compressor is not available` |

`encoding_name` / `encoding_from_name` map tags to/from the exact,
case-sensitive Content-Encoding tokens; an unknown token yields
`compression: unknown encoding '<name>'`, an unknown integer tag yields
`compression: unknown encoding <tag>`. `encoding_supported` returns 1 for
identity/gzip and 0 for zstd/unknown. `compress_bytes` encodes an owned byte
buffer; `compress_body` converts the UTF-8 body with
`xiom.encoding.utf8_encode` and then encodes.

**Why zstd is not wired.** The in-tree `xiom.zstd` package is a vendored
`zstd.c` binding compiled via `--c-source`; this package's suite and live
path are deliberately link-free (only the consumer-supplied libcurl bridge is
linked for the probe). Importing the binding would make the offline suite
depend on a C toolchain. The typed error above is the deliberate fail-closed
path; adding zstd later means giving this package a `port.args.json` with the
vendored C source and allowing FFI in the suite.

**Transport blocker (resolved 2026-10-17, see section 16).** xiom.http 0.1.8
accepted request bodies only as `Str` and re-encoded them to UTF-8 in
`http.xi` `str_to_cstr` before the C call, so a gzip frame could not be
carried unchanged. xiom.http 0.1.9 adds `http_request_bytes` (Vec[UInt8]
plus an explicit `content_length`; no re-encode and no NUL truncation), and
the M2-chunk-5 client now selects it for every non-identity encoding.
Identity remains on the original Str `http_request` path.

Fully offline-golden-tested (suite t40..t42, 33 checks): the exact boundary
on numeric sizes and on synthetic 32 MiB-1 / 32 MiB / 32 MiB+1 buffers; the
inclusive 32 MiB acceptance; negative-size and oversize typed errors; the
identity byte-exact path; gzip header magic and a gzip round-trip of a JSON
body and of all 256 byte values through the stdlib decompressor; the
tag/token/support matrix; the unknown-token and unknown-tag error arms; the
zstd-absent typed error through both `compress_bytes` and `compress_body`;
and proof that an oversized logical body is rejected before any encoder runs
(even when it would compress below the limit). No live network is involved.

## 16. M2 progress (increment 5: end-to-end compressed requests)

Fifth M2 chunk (ROADMAP M2 bullet 8 completion): compression is wired into
the client now that xiom.http 0.1.9 ships a binary-safe request entry.

- **Selection.** `xiom.jev.compression.encoding_check(enc)` is the pure gate:
  identity and gzip pass through; zstd fails
  `compression: zstd compressor is not available`; any other tag fails
  `compression: unknown encoding <tag>`. `system_one_with_encoding` runs it
  before building the body, and `system_one` delegates with
  `ENCODING_IDENTITY`.
- **Wire plan.** `compression.prepare_body(body, enc)` enforces the 32 MiB
  rule on the LOGICAL body first, then the encoding gate, then encodes. Its
  `EncodedBody` carries the exact `bytes`, `content_length = bytes.len()` and
  the `Content-Encoding` token ("" for identity). `wire_uses_bytes` is the
  pure transport-choice predicate. gzip output is deterministic (mtime 0), so
  exact-byte tests are stable.
- **Transport.** identity keeps the existing `http_request` Str path
  byte-identical (no Content-Encoding header). gzip passes the exact frame
  and its exact content length to `http_request_bytes` (xiom.http 0.1.9,
  binary-safe; libcurl emits Content-Length from `CURLOPT_POSTFIELDSIZE`) and
  adds `Content-Encoding: gzip` to the same header blob. The retry policy is
  shared by both paths; a `HttpBytesRequestError.Transport` message maps onto
  `JevError.Transport` unchanged, and the pre-FFI body-length arms map onto a
  descriptive transport reason (they cannot fire from the client's plan).

**Tests (suite t43..t44, 26 checks, offline).** The selection matrix
(identity/gzip accepted, zstd/unknown typed), the transport-choice predicate,
identity plan bytes/length/no-header, gzip plan token/exact length/frame
header/round-trip/determinism, the plan error arms and logical-rule
precedence, and a request-builder integration leg that gzips the real
conformance JSON and decompresses back to the exact `build_request` bytes.
The client module itself stays out of the link-free suite (it links the
libcurl bridge) and is covered by `xiom --check` plus `tests/probe_live.xi`;
the probe gains a gzip leg behind the same SKIP-safe key gate.

## 17. M3 progress (increment 1: hierarchical beam search)

First M3 chunk (ROADMAP M3 bullet 1, "hierarchical classification helper:
beam search over Choice probabilities keeping the best K paths per level").
New module `xiom.jev.beam`; it is pure, offline and integer-only.

**Input.** A hierarchy is a `Vec[BeamLevel]` in level order. Level 0 is the
root level, level 1 its children, and so on. A `BeamLevel` holds parallel
`labels: Vec[Str]` and `micro: Vec[Int]` vectors -- the same encoded
probabilities already used by `Answers` (`prob_labels` / `prob_micro`, micro
units, wire/criterion order). `beam_level_from_answer(&Response, i)` bridges
a parsed Choice answer straight into a level, reusing its encoded
distribution. The per-level distribution is the conditional distribution
given any prefix; a path is one label per level.

**Search.** `beam_search(levels, width)` starts with the empty path at score
1.0 (`MICRO`), then for each level expands every kept path with every option,
ranks the expanded paths and keeps the best `width`. The path score is the
probability product carried in micro units, normalized after each expansion
with truncating integer division:

    score_0 = MICRO
    score_{i+1} = (score_i * micro_i) / MICRO

Integer-only arithmetic and deterministic ordering make the result identical
on every run and platform. Zero-probability options remain valid paths with
score 0.

**Tie-breaking (pinned).** Paths are ordered by `score_micro` descending;
equal scores keep DISCOVERY ORDER -- the previous beam order (already ranked)
as the outer loop, then the level's option order as the inner loop. `width 1`
therefore keeps the first-discovered path among equal maxima.

**Result.** `BeamResult { width, levels, paths }` carries at most `width`
paths, best first. Guards: `beam_result_count`, `beam_result_width`,
`beam_result_levels`, `beam_result_path_levels`, `beam_result_path_score`
(-1 out of range), `beam_result_path_label` (""), `beam_result_path_text`
(join with a caller separator, ""), plus `beam_path_score/levels/text`.
`beam_level_len` is the option count.

**Typed errors.** Every malformed input is `JevError.BadRequest` with a
stable reason (all prefixed `beam: `):

| reason | trigger |
|---|---|
| `beam: width must be positive` | `width <= 0` (checked first) |
| `beam: missing levels` | `levels.len() == 0` |
| `beam: empty children at level <n>` | level `<n>` (1-based) has zero options |
| `beam: level <n>: malformed children` | label/micro vectors drifted |
| `beam: level <n>: label is empty` | empty option label |
| `beam: level <n>: duplicate label '<label>'` | repeated option label in one level |
| `beam: level <n>: probability out of range` | micro outside [0, 1000000] |
| `beam: answer <i> is not a choice` | `beam_level_from_answer` on a non-choice/out-of-range answer |
| `beam: answer <i> has no probabilities` | `beam_level_from_answer` on an empty distribution |

**Tests (suite t45..t47, 41 checks, offline).** t45 pins a hand-computed
three-level golden (0.5/0.3/0.2 x 0.5/0.5 x 0.4/0.6, width 2), the full
eight-path ranking, determinism across runs, the width-1 tie pin, and
zero-probability ordering. t46 covers every typed error arm. t47 bridges two
parsed Choice answers (department 0.04/0.35/0.61 and resolution
0.34/0.40/0.02/0.24) into a search and pins 244000 / 207400 / 146400 micro.
No network, no randomness, no Float64.

## 18. M3 progress (increment 2: owner-pin gate)

The second M3 lane targeted the two remaining ROADMAP M3 bullets, the
danger-zone `box` question/answer plus media assets and batch/streaming
ergonomics. Both are **not implemented**: this SPEC pins neither the wire
shape nor the API, so under the no-guessing rule the lane adds no source and
no tests. The M1 fail-closed behavior for `box` (unknown answer type,
section 6) and the existing caller-side transport API stand unchanged.

Pins required before either item can be implemented:

- **`box` request** -- the exact question object: whether `type` is `box`,
  the required/optional members (instructions, media reference), and how
  media assets are represented on the wire (inline base64, URL, or
  multipart), including MIME types and size limits.
- **Media headers** -- the exact `TypeSafe-Danger-Zone-Images` header
  serialization and limits, plus the endpoint/model (vision) requirements
  from S8.
- **`box` answer** -- required keys, box geometry (coordinate system/units,
  tuple order versus x/y/w/h), single versus multiple boxes, and the
  probability/confidence semantics.
- **`box` errors and fixtures** -- the per-field Parse reason strings and at
  least one S8 response golden; section 6 currently rejects `box` as an
  unknown answer type.
- **Batch/streaming** -- the API surface (module, function/type names and
  signatures), what "the same question set" means for reuse/ownership,
  concurrency and result-ordering rules, partial-failure/typed-error
  aggregation, streaming framing (NDJSON/SSE/chunked), cancellation and
  backpressure, and the deterministic offline test shape. ROADMAP says
  "caller-side scheduling only (no async runtime here)", so the SPEC must
  also state whether a package-level API is in scope at all.

Suite evidence for this lane: 47 functions, **210/210 checks x2** on compiler
`v0.64.8`, unchanged because no surface was added.

## 19. Owner pins resolved (owner GO, 2026-10-19)

The owner granted GO for all previously owner-pinned items. The pins below are
authoritative; they supersede section 18 and the S6/S8 entries in section 11.
Sources: `docs.typesafe.ai/confidence` (confidence formulas) and
`api.typesafe.ai/openapi.json` **v0.2.0** (wire schema), retrieved 2026-10-19.

### 19.1 S6 confidence formulas (pinned)

Inputs are the answer's probability distribution (already validated: finite,
in `[0,1]`, sum 1 within the existing tolerance). All results are on the same
`[0,1]` scale and converted to micro units at the boundary.

- **Noul** (unchanged): `confidence = |2p - 1|`.
- **Choice** with `n >= 2` options and top probability `p_max`:
  `confidence = (p_max - 1/n) / (1 - 1/n)`; equivalently `(n*p_max - 1)/(n - 1)`.
  Clamp to `[0,1]`. Only the top probability counts.
- **Score** with `n >= 1` levels indexed `0..n-1`, probabilities `p_i`, and
  `m` = index of the maximum probability (lowest index on a tie):
  `spread = sum_i p_i * |i - m|`;
  `MAD_unif = (1/n) * sum_i |i - (n-1)/2|`;
  `confidence = max(0, 1 - spread / MAD_unif)`. For `n == 1` the confidence is
  `1.0` (a single level is certain; MAD_unif is 0 -- special-cased, no division).
- Rounding: compute in Float64, round **half-up** to micro once at the end
  (`round(x * 1e6)`), clamp to `[0, MICRO]`. Reject non-finite inputs with the
  existing Parse/BadRequest classes; `n == 0` is structurally impossible.
- New helpers: `confidence_choice_micro(probabilities)`,
  `confidence_score_micro(probabilities)` (pure; no transport dependency).
- Goldens: choice `(0.6,0.3,0.1)` -> 0.4; `(0.8,0.1,0.1)` -> 0.7;
  `(0.5,0.5)` -> 0; `(1,0,0)` -> 1. Score `(0,0.57,0.43)` -> 0.35 (reference
  example); `(0,0.5,0.5)` -> 0.25; `(0.5,0,0.5)` -> 0; `(0,0,1)` -> 1;
  `(0.1,0.1,0.8)` -> 0.7 (reference example scaled).

### 19.2 S8 v0.2.0 wire schema (pinned)

Endpoint `POST /v1/systemone`, security `HTTPBearer`.

Request `SystemOneRequest` (required: `model`, `state`, `questions`):
- `model: string`; `state: string | object | array`.
- `questions: object` (minProperties 1) mapping caller-chosen name ->
  `Question` discriminated on `type` (`noul | choice | score | box`).
- `questions[name].instructions` (all types): `string | object | array | null`,
  optional. Already supported by section 13 (string + structured docs).
- `NoulQuestion`: `type`, optional `instructions`, optional `criteria`
  `{true?, false?}` whose values are `string | object | array | null`.
- `ChoiceQuestion`: `type`, optional `instructions`, required `criteria`
  object (minProperties 1, maxProperties 255) mapping choice name ->
  `string | object | array | null`.
- `ScoreQuestion`: `type`, optional `instructions`, required `criteria`
  array (minItems 1, maxItems 10) of `string | object | array` (null is NOT
  allowed in score criteria per the schema).
- `BoxQuestion`: `type`, optional `instructions`; no criteria.
- Optional `assets: object` (minProperties 1) mapping an opaque placeholder
  (recommend UUID) -> `Asset`: `{type:"image", format:"png"|"jpg"|"jpeg"
  (required with data_base64), data_base64?: string, part?: string}`. Assets
  are referenced by their placeholder appearing as or inside strings in
  `state`, instructions, or criteria. With `part`, `data_base64` is ignored
  and the bytes ride a multipart part of that name.
- Headers: `TypeSafe-Danger-Zone-Images: true` is REQUIRED for box questions
  and assets; `TypeSafe-Danger-Zone-Long-Context: true` optional for long
  context. Emit only when needed.

Response `SystemOneResponse` (required: `model`, `answers`, `usage`):
- `answers: object` (minProperties 1) mapping question name -> `Answer`
  discriminated on `type`.
- `NoulAnswer`: `type:"noul"`, `noul: number`.
- `ChoiceAnswer`: `type:"choice"`, `choice: string`, `confidence: number`,
  `probabilities: {string: number}`.
- `ScoreAnswer`: `type:"score"`, `score: number`, `confidence: number`,
  `legend: {string: string|object|array}`, `probabilities: {string: number}`.
- `BoxAnswer`: `type:"box"`, `box: {top,bottom,left,right: number}` (required;
  fractions of image height/width, 0..1, top/bottom measured from the top,
  left/right from the left; each coordinate is the expected edge position),
  `confidence: number | null` (required member; null when the model gives none).
- `usage: {input_tokens: integer, output_tokens: integer}` (required on the
  wire in v0.2.0). The client keeps its tolerant read (`has_usage`) for
  forward compatibility — no breaking change to parsed answers.
- Errors: 422 `HTTPValidationError {detail: [{loc: (string|integer)[], msg,
  type, input?, ctx?}]}` — the existing 422 mapping stays.

The one deviation to record: score criteria `null` entries are rejected
(schema says `string | object | array` only); structured instructions remain
accepted on all question types.

### 19.3 Composite scoring (pinned)

Pure weighted combine of normalized scores with **integer weights**:
- Inputs: `scores: Vec[Int]` (micro units, each in `[0, MICRO]`),
  `weights: Vec[Int]` (raw integers, `>= 0`).
- Validation (typed `BadRequest`): empty vectors; length mismatch;
  any score outside `[0, MICRO]`; any negative weight; sum of weights == 0
  (`composite: all weights are zero`).
- Formula: `result = round_half_up( sum_i s_i * w_i / sum_i w_i )` in Float64,
  rounded once at the end, clamped to `[0, MICRO]`; `Int` overflow is avoided
  by widening the products/sums to Float64.
- Ordering: results are deterministic; no reordering. Helpers:
  `composite_score_micro(scores, weights) -> Result[Int, JevError]` and
  `composite_weights_valid(weights) -> Bool`.
- Goldens: `([400000, 900000], [1,1]) -> 650000`;
  `([400000, 900000], [3,1]) -> 525000`; `([0, 1000000], [0,5]) -> 1000000`;
  `all-zero weights -> BadRequest`; length mismatch -> BadRequest.

### 19.4 Danger-zone box + media (pinned)

- `BoxQuestion` / `BoxAnswer` / `Asset` exactly as section 19.2.
- Box geometry is **normalized floats** (`top`, `bottom`, `left`, `right` in
  `[0,1]`, bottom >= top, right >= left, all finite), carried in micro units
  (`1e6`) inside the package; parse errors name the offending field.
- Base64: JSON mode uses `data_base64` with `format`; the package validates
  base64 shape (`A-Za-z0-9+/` with correct padding) and rejects empty data.
  Multipart mode is a transport concern: the package builds the asset map
  with `part` and documents the multipart layout (JSON request first as
  `request`, then one image part per asset name). JSON/base64 is what the
  offline suite exercises byte-exactly; multipart gets a build-plan test only.
- The `TypeSafe-Danger-Zone-Images: true` header is emitted by the client
  when any box question or any asset is present; absence is a `BadRequest`
  when a box question is present (fail-closed).
- Answer parsing: `box` becomes a first-class answer (no longer the
  fail-closed unknown type); `confidence` is `Option`-shaped (null allowed);
  the other answer kinds are unchanged.

### 19.5 Batch/streaming (pinned)

The v0.2.0 API has **no batch or streaming endpoint** (only
`POST /v1/systemone`). Pins:
- **Batch is caller-side scheduling ONLY** (matches the ROADMAP): the package
  exposes a pure aggregation helper, no I/O and no async runtime:
  `batch_collect(results: Vec[Result[Str, JevError]]) -> BatchOutcome` where
  `BatchOutcome { successes: Vec[(index, Str)]; failures: Vec[(index, JevError)];
  ok: Bool }` — stable input order, per-item typed errors, `ok` = no failures.
  This gives consumers deterministic partial-failure handling without owning
  a runtime.
- **Streaming is NOT implemented** (no SSE/NDJSON/chunked contract exists in
  v0.2.0); the SPEC records it as out of scope until the reference defines a
  framing. No API is invented.

### 19.6 Implementation order and evidence

1. S6 helpers + composite scoring (pure; exact goldens above).
2. S8 box/media request+answer support (header + asset emission; box parse).
3. Batch helper (`batch_collect`).
Each lands with its own suite increments x2 on the pin; the live probe stays
SKIP-safe. No guesswork remains in this SPEC.

