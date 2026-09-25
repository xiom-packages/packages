// XIOM -- xiom.hostfile package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string, xiom.string.compare
// and xiom.convert from it; the tests additionally use xiom.test and xiom.io.

package xiom_hostfile {
  name: "xiom.hostfile";
  version: "0.1.0";
  description: "Hosts-file parser and canonical emitter: address/hostname entries, lookups and round-trips";
  categories: ["systems"];
  keywords: ["hosts", "network", "parser", "unix"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.hostfile"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
