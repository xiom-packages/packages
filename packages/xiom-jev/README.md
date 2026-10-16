<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# xiom.jev

TypeSafe Jev client tier: **System One** structured decisions for XIOM.

> **Status:** `incubating` -- 0.1.0. Offline conformance suite **82/82 x2** on
> compiler `v0.64.5` (native-session, 2026-10-16). Live probe is SKIP-safe and
> link-gated (see "Live probe"). `publish: false` (new name: pending ops scope
> + allowlist, coverage program).

JEV = System One: fast, **structured decisions where the answer space is known
in advance** -- routing, classification, scoring. Send a state (text or JSON)
plus typed questions (`choice` / `score` / `noul`) in one call; get typed
answers, probability distributions and confidence your code branches on. No
text generation, no parsing. This package is the System One tier of the ML/AI
coverage program; it pairs with the `xiom.llm` runner tier (System Two text).

## Modules

| Module | Contents |
|---|---|
| `xiom.jev` | identity, `default_model`, `default_base_url`, `systemone_endpoint` |
| `xiom.jev.types` | `State`, `Question` (+ builders), `Answers`, `Response` (+ guarded accessors), `micro_text` |
| `xiom.jev.request` | `build_request` -- validated JSON body (exact bytes, insertion order) |
| `xiom.jev.response` | `parse_response` -- typed answers + confidence + usage; `api_error_detail` |
| `xiom.jev.selection` | `answer_argmax`, `answer_labels_at_or_above`, `answer_sample_index` (caller-supplied entropy), score/noul helpers |
| `xiom.jev.errors` | `JevError` (BadRequest / Transport / HttpStatus / Parse) + `jev_error_text` |
| `xiom.jev.client` | `system_one` -- transport over the xiom.http 0.1.8 headers surface |

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

## Transport (xiom.http 0.1.8 headers surface)

`xiom.jev.client.system_one(base_url, api_key, model, state, questions)`
builds the body, attaches `Authorization: Bearer <api_key>` +
`Content-Type: application/json` via `xiom.http.headers`, and sends it to
`<base_url>/v1/systemone` through `xiom.http.http_request` (NO new FFI; TLS
is the consumer's libcurl bridge). Failures map onto the typed `JevError`
catalog.

**Live leg (resolved 2026-10-16):** xiom.http 0.1.8 ships the custom-headers
surface, so the API receives the bearer token; a valid key now yields a 2xx
([PASS] in the probe). `api_key` is validated and never logged or stored.

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
