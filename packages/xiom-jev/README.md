<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# xiom.jev

TypeSafe Jev client tier: **System One** structured decisions for XIOM.

> **Status:** `incubating` -- 0.1.0. Offline conformance suite **210/210 x2** on
> compiler `v0.64.8` (native-session, 2026-10-19). Live probe is SKIP-safe and
> link-gated (see "Live probe"). Published in `eco-v0.1.193` (sha256
> `ed212ee6...`, 2026-10-16).

JEV = System One: fast, **structured decisions where the answer space is known
in advance** -- routing, classification, scoring. Send a state (text or JSON)
plus typed questions (`choice` / `score` / `noul`) in one call; get typed
answers, probability distributions and confidence your code branches on. No
text generation, no parsing. This package is the System One tier of the ML/AI
coverage program; it pairs with the `xiom.llm` runner tier (System Two text).

## Modules

| Module | Contents |
|---|---|
| `xiom.jev` | identity, `default_model`, `default_base_url`, `systemone_endpoint`, `api_key_validate`, `base_url_validate` |
| `xiom.jev.types` | `State`, `Question` (+ builders), `Answers`, `Response` (+ guarded accessors incl. `response_legend_*`), `micro_text` |
| `xiom.jev.request` | `build_request` -- validated JSON body (exact bytes, insertion order) |
| `xiom.jev.response` | `parse_response` -- typed answers + confidence + usage; `api_error_detail` |
| `xiom.jev.selection` | `answer_argmax`, `answer_labels_at_or_above`, `answer_sample_index` (caller-supplied entropy), score/noul helpers |
| `xiom.jev.retry` | `retry_is_retryable`, `retry_backoff_millis`, `default_max_attempts/base_millis/cap_millis` -- pure bounded-backoff policy |
| `xiom.jev.beam` | `BeamLevel`/`BeamPath`/`BeamResult`, `beam_level_new`, `beam_add_option`, `beam_level_from_answer`, `beam_search` (deterministic width-K hierarchy search), guarded result accessors |
| `xiom.jev.compression` | 32 MiB `body_size_check`, encoding tags (`identity`/`gzip`/`zstd`), `encoding_check`, `wire_uses_bytes`, `prepare_body`/`EncodedBody`, `compress_bytes`/`compress_body` (gzip; zstd typed unavailable) |
| `xiom.jev.errors` | `JevError` (BadRequest / Transport / HttpStatus / Parse) + `jev_error_text` |
| `xiom.jev.client` | `system_one` (identity) and `system_one_with_encoding` -- transport over xiom.http 0.1.9 (`http_request` Str / `http_request_bytes` binary) |

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

The other M3 items (danger-zone `box` question/answer + media assets, and
batch/streaming ergonomics) were **pinned by the owner on 2026-10-19**
(`SPEC.md` section 19): box/media now has an exact wire shape, and batch is
caller-side aggregation only (`batch_collect`; no streaming endpoint exists in
v0.2.0). Implementation is queued; until it lands, `box` responses still fail
closed as an unknown answer type.

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
