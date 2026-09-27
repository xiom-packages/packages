// XIOM -- xiom.ethereum package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string, xiom.convert and
// xiom.encoding.hex from it; the tests additionally use xiom.test, xiom.io
// and xiom.string.compare.

package xiom_ethereum {
  name: "xiom.ethereum";
  version: "0.1.0";
  description: "Ethereum RLP and ABI encoding structures in pure XIOM (no keccak, no crypto, no network)";
  categories: ["data"];
  keywords: ["ethereum", "rlp", "abi", "encoding", "transaction"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ethereum"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
