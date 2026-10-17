// XIOM -- xiom.jev package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// TypeSafe Jev client tier ("System One" structured decisions): a state
// (text or JSON) plus typed questions (choice / score / noul) in one
// request, out come typed answers with probability distributions and
// confidence, plus deterministic selection helpers (argmax / threshold /
// sample-by-probability from caller-supplied entropy).
//
// Wire references (read-only; recorded in SPEC.md section 2): the public
// TypeSafe documentation at https://docs.typesafe.ai, the OpenAPI schema at
// https://api.typesafe.ai/openapi.json (v0.2.0), and browser-use/jev-ultrafast
// (MIT) at commit 1231850a0bf1a0c0341fe408ef1668dbbfdfac46.
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The client module additionally consumes xiom.http
// 0.1.9 (headers + binary-body client surface) as an in-tree path dependency
// declared in xiom.toml; every other module is stdlib-only
// (xiom.serialize.json, xiom.string, xiom.math, xiom.convert,
// xiom.compress.gzip).

package xiom_jev {
  name: "xiom.jev";
  version: "0.1.0";
  description: "TypeSafe Jev client tier (System One structured decisions): typed questions (choice/score/noul) -> typed answers with probabilities and confidence, plus deterministic selection (argmax, threshold, sample-by-probability from caller-supplied entropy); float-free micro-unit core";
  categories: ["ai-ml"];
  keywords: ["jev", "typesafe", "decision", "system-one", "choice", "score", "noul", "probability", "confidence", "selection"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.jev", "xiom.jev.beam", "xiom.jev.client", "xiom.jev.compression", "xiom.jev.errors", "xiom.jev.request", "xiom.jev.response", "xiom.jev.retry", "xiom.jev.selection", "xiom.jev.types"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0", "xiom.http": "0.1.9" };
}
