<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# xiom.jev

TypeSafe Jev client tier: **System One** structured decisions for XIOM.

> **Status:** `incubating` -- 0.1.0. Offline conformance suite **324/324 x2** on
> compiler `v0.64.8` (native-session, 2026-10-19). Live probe is SKIP-safe and
> link-gated (see "Live probe"). Published in `eco-v0.1.193` (sha256
> `ed212ee6...`, 2026-10-16).

JEV = System One: fast, **structured decisions where the answer space is known
in advance** -- routing, classification, scoring. Send a state (text or JSON)
plus typed questions (`choice` / `score` / `noul` / danger-zone `box`, with
optional image assets) in one call; get typed answers, probability
distributions and confidence your code branches on. No
text generation, no parsing. This package is the System One tier of the ML/AI
coverage program; it pairs with the `xiom.llm` runner tier (System Two text).

## Modules

| Module | Contents |
|---|---|
| `xiom.jev` | identity, `default_model`, `default_base_url`, `systemone_endpoint`, `api_key_validate`, `base_url_validate` |
| `xiom.jev.types` | `State`, `Question` (+ builders incl. `question_box`), `Asset`/`AssetEntry` (+ builders), `Answers`, `Response` (+ guarded accessors incl. `response_legend_*` and `response_box_*_micro`), `micro_text` |
| `xiom.jev.request` | `build_request`, `build_request_with_assets`, `danger_zone_images_required` -- validated JSON body (exact bytes, insertion order) |
| `xiom.jev.response` | `parse_response` -- typed answers + confidence + usage; `api_error_detail` |
| `xiom.jev.selection` | `answer_argmax`, `answer_labels_at_or_above`, `answer_sample_index` (caller-supplied entropy), score/noul helpers |
| `xiom.jev.retry` | `retry_is_retryable`, `retry_backoff_millis`, `default_max_attempts/base_millis/cap_millis` -- pure bounded-backoff policy |
| `xiom.jev.beam` | `BeamLevel`/`BeamPath`/`BeamResult`, `beam_level_new`, `beam_add_option`, `beam_level_from_answer`, `beam_search` (deterministic width-K hierarchy search), guarded result accessors |
| `xiom.jev.compression` | 32 MiB `body_size_check`, encoding tags (`identity`/`gzip`/`zstd`), `encoding_check`, `wire_uses_bytes`, `prepare_body`/`EncodedBody`, `compress_bytes`/`compress_body` (gzip; zstd typed unavailable) |
| `xiom.jev.confidence` | `confidence_choice_micro`, `confidence_score_micro` (S6 formulas), `composite_score_micro`, `composite_weights_valid` -- pure micro-unit statistics |
| `xiom.jev.batch` | `BatchOutcome`/`BatchSuccess`/`BatchFailure`, `batch_collect` -- pure caller-side aggregation (stable order, per-item typed errors); no I/O, no runtime |
| `xiom.jev.errors` | `JevError` (BadRequest / Transport / HttpStatus / Parse) + `jev_error_text` |
| `xiom.jev.client` | `system_one` (identity), `system_one_with_encoding`, `system_one_with_assets`, `system_one_with_assets_and_encoding` -- transport over xiom.http 0.1.9 (`http_request` Str / `http_request_bytes` binary) |

## Quick start (offline shape)

```xiom
use xiom.jev.types;
use xiom.jev.request;
use xiom.jev.response;
use xiom.jev.selection;

// 1. questions
var qs: Vec[Question] = Vec[Question].new();
var d: Question = types.question_choice("department", "Which team should handle this?");
types.question_add_option(&mut d, "returns", "Exchanges, wrong or damaged items");
types.question_add_option(&mut d, "billing", "Charges, invoices, payment problems");
qs.push(d);

// 2. request body (send it with xiom.jev.client.system_one)
let body: Result[Str, JevError] = request.build_request("jev-latest", types.state_text(ticket), qs);

// 3. typed answers (parse the endpoint's response body)
let r: Result[Response, JevError] = response.parse_response(raw);
let resp: Response = r.value;
let first: Str = selection.answer_argmax_label(&resp, 0);   // "returns"

// 4. deterministic probabilistic selection: caller supplies the entropy
let pick: Int = selection.answer_sample_index(&resp, 0, my_seed_value);
```

Every 0..1 quantity is carried as **Int micro units** (1.0 = 1000000), so the
core is float-free and deterministic; `types.micro_text(610000)` renders
`"0.61"`. Tie rules, rounding and the exact entropy interval semantics are
pinned in `SPEC.md` section 7.

**Structured instructions/criteria (M2, 2026-10-16):** `instructions` and
every criteria entry may be an object or array, not just a string
(S3/S4/S5). Use the `*_json` builders with a parsed `JsonValue`:
`question_set_instructions_json`, `question_add_option_json`,
`question_add_level_json`, `question_set_noul_criteria_json`. A set doc is
emitted verbatim and overrides the string form, so string questions and
their byte-exact fixtures are unchanged; string, object and array entries
can be mixed in one question. Validation counts an instruction/level as
present when its string is non-empty or its doc is set.

**Score legend (M2, 2026-10-16):** a score answer's `legend`
(level -> description) is now carried through parsing, not just validated.
Read it with `types.response_legend_count/label/doc/is_structured/text/find`
(guarded; empty for choice/noul answers) and rebuild the object with
`types.response_legend_json`; both string and structured (object/array) S4
legend forms round-trip.

## Hierarchical beam search (M3, 2026-10-17)

`xiom.jev.beam` runs a pure, deterministic beam search over a hierarchy of
Choice probability levels. Levels use the same encoded micro probabilities as
parsed answers, and `beam.beam_level_from_answer(&resp, i)` converts a Choice
answer directly. `beam_search(levels, width)` expands every kept path with
every option level by level, scores a path with the integer product of its
option probabilities (`score = (score * micro) / 1000000`), and keeps the
best `width` paths. Equal scores keep discovery order (previous beam order,
then option order), so results are identical on every run and platform.

```xiom
use xiom.jev.beam;

var l1: BeamLevel = beam.beam_level_new();
beam.beam_add_option(&mut l1, "returns", 610000);
beam.beam_add_option(&mut l1, "billing", 350000);
// resp: Response, resolution_answer: index of a Choice answer
var l2: BeamLevel = beam.beam_level_from_answer(&resp, resolution_answer).value;

var levels: Vec[BeamLevel] = Vec[BeamLevel].new();
levels.push(l1);
levels.push(l2);
let r = beam.beam_search(levels, 3);       // Result[BeamResult, JevError]
let top = r.value.paths[0];
```

Malformed input fails typed (`JevError.BadRequest`): `beam: width must be
positive`, `beam: missing levels`, `beam: empty children at level <n>`,
empty/duplicate labels, out-of-range micro, and the answer-bridge arms.
The score rule, tie order, full error table and golden values are pinned in
`SPEC.md` section 17; suite t45..t47 cover them offline.

## Danger-zone box and media (M3, 2026-10-19)

`box` is a first-class question and answer type (S8 v0.2.0, `SPEC.md`
sections 19.2/19.4). A box question has no criteria and optional
instructions; image assets travel as a placeholder -> `Asset` map and are
referenced from state/instructions/criteria strings. Placeholder substitution
is server-side.

```xiom
use xiom.jev.types;
use xiom.jev.request;

var qs: Vec[Question] = Vec[Question].new();
qs.push(types.question_box("target", "Where is the invoice total?"));

var assets: Vec[AssetEntry] = types.assets_new();
assets.push(types.asset_entry("page", types.asset_image_base64("png", png_b64)));
// multipart form: types.asset_image_part("page_image")

let body = request.build_request_with_assets(
  "jev-latest", types.state_text("Find the total on page page"), qs, assets);
// emits ..."assets":{"page":{"type":"image","format":"png","data_base64":"..."}}
```

`build_request` is unchanged and byte-identical; the no-asset path omits
`assets`. The client emits `TypeSafe-Danger-Zone-Images: true` automatically
when any box question or any asset is present
(`request.danger_zone_images_required`), so a box question cannot go out
without the capability header.

Assets are validated: non-empty base64 with `A-Za-z0-9+/` and correct `=`
padding, `format` in `png`/`jpg`/`jpeg` required with `data_base64`, and a
`part` form ignores `data_base64` entirely. Box answers parse
`{type:"box",box:{top,bottom,left,right},confidence}` into micro units:
edges are required finite numbers in `[0,1]` with `bottom >= top` and
`right >= left`; `confidence` is required and may be `null` (stored as the
Option-shaped none, -1 micro). Every malformed member has a typed Parse
reason (see `SPEC.md` section 19.7). Suite t50..t52 cover the exact bytes,
the header predicate and all parse errors offline.

Batch/streaming ergonomics is **pinned by the owner on 2026-10-19**
(`SPEC.md` section 19.5): v0.2.0 has no batch or streaming endpoint, so the
package exposes only the pure caller-side `batch_collect` aggregation helper
(now implemented; see below) and streaming remains out of scope.

## Confidence and composite scoring (M3, 2026-10-19)

`xiom.jev.confidence` implements the pinned S6 formulas and the composite
scoring pattern over the same micro-unit distributions returned by
`parse_response`:

- `confidence_choice_micro(&probs)` -- `(p_max - 1/n) / (1 - 1/n)`,
  clamped to `[0,1]`, half-up to micro once at the end.
- `confidence_score_micro(&probs)` -- `max(0, 1 - spread/MAD_unif)` with
  `m` the maximum-probability index (lowest index on a tie); `n == 1`
  returns `1.0`.
- `composite_score_micro(&scores, &weights)` -- integer weights `>= 0`,
  `round_half_up(sum(s_i*w_i) / sum(w_i))`, widened to Float64, rounded
  once, clamped to `[0, MICRO]`; typed `BadRequest` guards.
- `composite_weights_valid(&weights)` -- non-empty, all weights `>= 0`,
  sum `> 0`.

```xiom
use xiom.jev.confidence;

let probs: Vec[Int] = ...;                 // micro units from a parsed answer
let c: Int = confidence.confidence_score_micro(&probs);
let blended = confidence.composite_score_micro(&scores, &weights); // Result[Int, JevError]
```

Exact goldens live in suite t48..t49. `SPEC.md` section 19.7 records the two
pin-text details worth knowing: `(0,0.57,0.43)` displays as `0.35` but its
exact half-up micro value is `355000`, and the score formula gives
`(0.1,0.1,0.8) -> 0.55` (the pin's `0.7` is the Choice formula's value).

## Batch aggregation (M3, 2026-10-19)

`xiom.jev.batch.batch_collect` is the only batch surface: v0.2.0 has no batch
endpoint, so scheduling stays with the caller (sequential or host-provided
concurrency) and this helper performs no I/O and owns no runtime.

```xiom
pub type BatchSuccess = { index: Int; value: Str }
pub type BatchFailure = { index: Int; error: JevError }
pub type BatchOutcome = {
  successes: Vec[BatchSuccess];
  failures: Vec<BatchFailure>;
  ok: Bool;
}

pub fn batch_collect(results: &Vec[Result[Str, JevError]]) -> BatchOutcome
```

`successes` and `failures` each preserve ascending input-index order; every
`JevError` payload is copied unchanged; `ok` is true exactly when `failures`
is empty (so empty input is ok with both vectors empty). This is the
struct-per-row form of the SPEC's `Vec[(Int, Str)]` / `Vec[(Int, JevError)]`
pairs (tuples inside `Vec` have a known element-read defect).

Example:

```xiom
use xiom.jev.batch;

var results: Vec[Result[Str, JevError]] = ...;  // caller-scheduled calls
let outcome: BatchOutcome = batch.batch_collect(&results);
if outcome.ok {
  // every item succeeded, in input order
} else {
  let first_bad: Int = outcome.failures[0].index;
  let why: JevError = outcome.failures[0].error;
}
```

Suite t53 (30 checks) pins empty, all-success, all-failure, mixed, order
stability and size-1 inputs with exact indices and error identity.

Compiler note (v0.64.8): `Vec.push` loses the `Err` `Str` payload (and can
perturb order) when a directly-constructed `Err` is passed straight to it.
Bind each `Result` returned by a call to a local before pushing; the probe
`docs/repro/batch_result_vec_push.xi` reduces the defect.

## Transport (xiom.http 0.1.9 headers + binary-body surface)

`xiom.jev.client.system_one(base_url, api_key, model, state, questions)`
builds the body, attaches `Authorization: Bearer <api_key>` +
`Content-Type: application/json` via `xiom.http.headers`, and sends it to
`<base_url>/v1/systemone` through `xiom.http.http_request` (NO new FFI; TLS
is the consumer's libcurl bridge). Failures map onto the typed `JevError`
catalog.

`system_one_with_encoding(..., compression.ENCODING_GZIP)` compresses the
logical body with `xiom.jev.compression.prepare_body` and sends the exact
frame plus its exact Content-Length through the binary-safe
`xiom.http.http_request_bytes` (0.1.9) with `Content-Encoding: gzip`.
`ENCODING_IDENTITY` (what `system_one` selects) keeps the original Str path
byte-identical and emits no `Content-Encoding` header. zstd and unknown tags
fail typed before any network call.

```xiom
use xiom.jev.client;
use xiom.jev.compression;

// gzip request path (identity: call client.system_one instead)
let r = client.system_one_with_encoding(
  "https://api.typesafe.ai", api_key, "jev-latest", state, questions,
  compression.ENCODING_GZIP);
```

**Live leg (resolved 2026-10-16):** xiom.http ships the custom-headers
surface, so the API receives the bearer token; a valid key yields a 2xx
([PASS] in the probe). The probe now selects gzip to exercise the binary
body path.

**Input hygiene (M2, 2026-10-16):** before the POST, `system_one` validates
both transport inputs through the pure helpers `xiom.jev.base_url_validate`
(scheme must be http/https, host non-empty) and `xiom.jev.api_key_validate`
(trims the key, then requires printable ASCII, rejecting internal
whitespace/control/non-ASCII) -- malformed input fails as a typed
`BadRequest` before any network call. The trimmed key is sent; the raw key is
never logged or stored.

**Retry (M2, 2026-10-16):** transient non-2xx statuses (429 / 503 / 529) are
retried up to `xiom.jev.retry.default_max_attempts()` total attempts with the
deterministic bounded backoff of `xiom.jev.retry` (500 ms base doubling to a
30 s cap, no jitter); the client sleeps via `xiom.time.sleep_ms`. Transport
failures are not retried. The policy core is offline-golden-tested.

**Body rule and compression (M2, 2026-10-17):** the client rejects a LOGICAL
(uncompressed) request body above **33554432 bytes (32 MiB)** with the typed
`request: body exceeds 32 MiB limit` before building headers, selecting an
encoder or touching the network; exactly 32 MiB is allowed (inclusive), so
compression cannot smuggle an oversized logical body past the rule.
`xiom.jev.compression` exposes the same `body_size_check`, the pure
`encoding_check`/`prepare_body` selection seam, `identity` and `gzip`
encoders (`compress_body`, pure stdlib RFC 1952, no FFI), and a typed
`compression: zstd compressor is not available` path. With xiom.http 0.1.9
(`http_request_bytes`) gzip requests now travel end-to-end; SPEC.md sections
15 and 16 pin the plan and the evidence.

## Live probe

`tests/probe_live.xi` performs ONE real call only when `TYPESAFE_API_KEY` is
set, else SKIPs (exit 0). It is an evidence file, not part of the offline
suite (port.ps1 runs `tests/test_conformance.xi`). Invocation on
Windows (repo root `E:\xiom-packages\packages`):

```powershell
$env:XIOM_STDLIB = "E:\xiom-lang\stdlib"
$env:TYPESAFE_API_KEY = "<key>"          # omit to SKIP; never committed
xiom --run packages\xiom-jev\tests\probe_live.xi `
  --c-source packages\xiom-http\bridge\xiom_http_shims.c `
  --link curl --link-path <scratch-dir-with-curl.lib>
```

(Pass `--c-source` absolute if your compiler links from a scratch cwd; put
`libcurl-x64.dll` on `PATH` and set `CURL_CA_BUNDLE` for TLS, per the
xiom.http README recipe.) Dependency-free surface check without any link:
`xiom --check packages\xiom-jev\tests\probe_live.xi`.

## Tests

```powershell
$env:XIOM_COMPILER = "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"
$env:XIOM_STDLIB = "E:\xiom-lang\stdlib"
& .\scripts\port.ps1 -Package xiom-jev -TimeoutSec 180
```

Offline and deterministic: request shapes are compared byte-for-byte against
the exact JSON pinned in the public TypeSafe docs, canned responses are
parsed and every probability/confidence/noul is checked in micro units, and
selection is exercised with hand-supplied entropy. No API key, no network,
no randomness. Fixture sources are recorded in `SPEC.md` sections 2 and 10.
