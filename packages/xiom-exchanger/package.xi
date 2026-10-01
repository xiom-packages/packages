// XIOM -- xiom.exchanger package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep, legacy xiom-std alias also
// accepted). The library module itself imports nothing; the tests use
// xiom.io and xiom.test from it.

package xiom_exchanger {
  name: "xiom.exchanger";
  version: "0.1.0";
  description: "Deterministic integer limit order book: price-time matching, bps fees, tape, depth, OHLCV";
  categories: ["finance"];
  keywords: ["orderbook", "matching-engine", "trading", "exchange"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.exchanger"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
