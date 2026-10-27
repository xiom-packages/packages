// XIOM -- xiom.pulse package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The frozen PULSE protocol core (Beacon extraction): the HTTP/1.1 request
// parser + response builders, the keep-alive A/B connection loop with named
// deadlines, the route matching mechanism and the uniform JSON error
// envelope, carved verbatim from the PULSE repo at commit 56eb9f8 (pair
// 7924222; see PROVENANCE.md). The PULSE family packages (session / static /
// kv / rate / metrics / middleware / sqlite) stay OUT of this bundle;
// consumers compose them separately.
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library modules import xiom.string,
// xiom.string.slice, xiom.string.compare, xiom.convert.parse,
// xiom.net.socket, xiom.net.server, xiom.serialize.json, xiom.env and
// xiom.time; the tests additionally use xiom.io.

package xiom_pulse {
  name: "xiom.pulse";
  version: "0.3.2";
  description: "PULSE Beacon -- the embeddable protocol core (HTTP/1.1 request parser + response builders, keep-alive A/B connection loop with named deadlines, route mechanism, JSON error envelope); one core, two products -- the Station product consumes this same package (pure XIOM, stdlib-only)";
  categories: ["web", "network"];
  keywords: ["http", "server", "framework", "keep-alive", "pulse", "beacon", "http1.1"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pulse", "xiom.pulse.http", "xiom.pulse.router", "xiom.pulse.envelope", "xiom.pulse.reqctx", "xiom.pulse.config", "xiom.pulse.app", "xiom.pulse.minimal"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
