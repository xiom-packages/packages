// XIOM -- xiom.nft package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string, xiom.string.compare
// and xiom.convert from it; the tests additionally use xiom.test, xiom.io and
// xiom.string.str_repeat.

package xiom_nft {
  name: "xiom.nft";
  version: "0.1.0";
  description: "Deterministic NFT registry model in pure XIOM: collections, mint/burn, approved transfers, royalties and a canonical event log (no crypto, no network)";
  categories: ["data"];
  keywords: ["nft", "registry", "ownership", "royalty", "approval", "event-log"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.nft"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
