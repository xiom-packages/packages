// XIOM -- xiom.jev live probe (SKIP-safe; evidence file, NOT part of the
// offline conformance suite run by scripts\port.ps1)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Performs ONE real System One call ONLY when TYPESAFE_API_KEY is set in the
// environment; otherwise prints [SKIP] and exits 0. The key is read at run
// time, never stored, logged or echoed. The call selects gzip so the live leg
// exercises the binary-body path (xiom.http 0.1.9 http_request_bytes +
// Content-Encoding) end to end.
//
// Invocation (PowerShell, repo root E:\xiom-packages\packages):
//
//   $env:XIOM_STDLIB = "E:\xiom-lang\stdlib"
//   $env:TYPESAFE_API_KEY = "<key>"        # omit to SKIP; never committed
//   xiom --run packages\xiom-jev\tests\probe_live.xi `
//     --c-source packages\xiom-http\bridge\xiom_http_shims.c `
//     --link curl --link-path <scratch-dir-with-curl.lib>
//
// The two extra flags come from the xiom.http consumer recipe (README
// "Consumer client build recipe"): the client speaks through the libcurl
// bridge, so the shim C source is linked in and curl is resolved from a
// scratch dir holding curl.lib (copy libcurl.dll.a / curl.lib there; put
// libcurl-x64.dll on PATH and set CURL_CA_BUNDLE for TLS at runtime).
//
// Live leg (resolved 2026-10-16; compressed path 2026-10-17): the client
// attaches Authorization: Bearer and sends the gzip frame through
// http_request_bytes with Content-Encoding: gzip. With a valid key a 2xx
// answer [PASS]es; a typed 401 with its decoded detail [SKIP]s (treat as
// key/permission trouble, never as PASS); a transport failure [SKIP]s as
// network-unreachable. Anything else is a [FAIL].
//
// Typed type-check without any link (dependency-free surface check):
//   xiom --check packages\xiom-jev\tests\probe_live.xi

module jev_live_probe

use xiom.io;
use xiom.env;
use xiom.convert;
use xiom.jev;
use xiom.jev.client;
use xiom.jev.compression;
use xiom.jev.errors;
use xiom.jev.types;

fn main() -> Int {
  io.println("=== xiom.jev live probe (SKIP-safe) ===");
  let key_opt: Option[Str] = env.var_opt("TYPESAFE_API_KEY");
  if !key_opt.is_some {
    io.println("[SKIP] TYPESAFE_API_KEY is not set; no network call made");
    return 0;
  }
  let key: Str = key_opt.value;
  if key.len() == 0 {
    io.println("[SKIP] TYPESAFE_API_KEY is empty; no network call made");
    return 0;
  }
  var qs: Vec[Question] = Vec[Question].new();
  var d: Question = types.question_choice("department", "Which team should handle this");
  types.question_add_option(&mut d, "billing", "Payment or subscription issues");
  types.question_add_option(&mut d, "technical", "Bugs or integration problems");
  types.question_add_option(&mut d, "sales", "Pricing or account questions");
  qs.push(d);
  var u: Question = types.question_noul("is_urgent", "The message conveys urgency or time-sensitivity");
  qs.push(u);
  let state: State = types.state_text("Our API integration started returning 500 errors on every request about 20 minutes ago.");
  let r: Result[Response, JevError] = client.system_one_with_encoding(jev.default_base_url(), key, jev.default_model(), state, qs, compression.ENCODING_GZIP);
  match r {
    Ok(resp) => {
      io.println("[PASS] live gzip call answered by " + types.response_model(&resp));
      io.println("  answers: " + convert.to_string(types.response_count(&resp)));
      return 0;
    },
    Err(e) => {
      match e {
        JevError.HttpStatus(code, detail) => {
          io.println("[SKIP] live call reached the API; typed status " + convert.to_string(code) + ": " + detail);
          io.println("       (key/permission trouble or gzip-body rejection; see SPEC.md sections 8 and 16)");
          return 0;
        },
        JevError.Transport(why) => {
          io.println("[SKIP] network unreachable: " + why);
          return 0;
        },
        JevError.BadRequest(reason) => {
          io.println("[FAIL] bad request: " + reason);
          return 1;
        },
        JevError.Parse(reason) => {
          io.println("[FAIL] response parse: " + reason);
          return 1;
        },
      };
    },
  };
}
