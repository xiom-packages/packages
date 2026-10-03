// XIOM -- xiom.web3 package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.compare, xiom.string.builder, xiom.convert and
// xiom.encoding.hex from it; the tests additionally use xiom.test and xiom.io.

package xiom_web3 {
  name: "xiom.web3";
  version: "0.1.1";
  description: "Pure-XIOM Web3 primitives: provider request/response model, contract selectors and minimal ABI words, ENS normalization/namehash and EIP-55 account addresses (Keccak-256 in-package, no networking)";
  categories: ["web", "network"];
  keywords: ["web3", "ethereum", "keccak", "eip55", "ens", "namehash", "abi", "json-rpc", "provider"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.web3", "xiom.web3.accounts", "xiom.web3.contract", "xiom.web3.ens", "xiom.web3.keccak", "xiom.web3.provider"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
