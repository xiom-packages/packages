// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.salt package manifest
// Port task: promote the xiom.salt placeholder to a real, tested, pure-XIOM
// package (Salt-style remote-execution / configuration MANAGEMENT MODEL:
// state ids/functions/names with require/watch/onchanges ordering, pillar
// targeting and merge/precedence, minion targeting with glob / regex subset /
// grain / compound expressions, typed grains with precedence and aggregation,
// and an event-bus model with tags, payload framing and reactor rules).
// Model only -- no network, no sockets, no shell, no FFI, no file I/O.
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.compare and xiom.convert from it; the tests additionally use
// xiom.test and xiom.io.

package xiom_salt {
  name: "xiom.salt";
  version: "0.1.0";
  description: "Pure-XIOM Salt remote-execution model: state ids/functions/names with require/watch/onchanges ordering, pillar targeting and merge precedence, minion targeting (glob, regex subset, grains, compound and/or/not), typed grains with precedence and aggregation, and an event bus with tags, payload framing and reactor rules";
  categories: ["systems"];
  keywords: ["salt", "configuration-management", "remote-execution", "states", "pillar", "grains", "minion", "targeting", "reactor", "event-bus"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.salt"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
