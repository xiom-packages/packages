// XIOM -- xiom.mbox package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// mbox mailbox codec: From-line message separation, mboxrd quoting, byte-range
// bodies and a canonical emitter. xiom.std is the standard library: a
// platform dependency, excluded from the registry install closure. The module
// itself imports xiom.string and xiom.string.builder from it; the tests
// additionally use xiom.string.compare, xiom.test and xiom.io.

package xiom_mbox {
  name: "xiom.mbox";
  version: "0.1.0";
  description: "mbox mailbox codec: From-line separation, mboxrd quoting, byte-range bodies, canonical emit";
  categories: ["data"];
  keywords: ["mbox", "mail", "mailbox", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.mbox"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
