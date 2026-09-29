// XIOM -- xiom.pgp package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.convert from it; the tests additionally use
// xiom.test, xiom.io, xiom.string.compare and xiom.encoding.hex.

package xiom_pgp {
  name: "xiom.pgp";
  version: "0.1.1";
  description: "OpenPGP (RFC 4880/9580 subset) packet and ASCII armor codec: packets, MPIs, v4 keys/signatures, CRC24 armor -- no crypto";
  categories: ["data"];
  keywords: ["pgp", "openpgp", "rfc4880", "armor", "packet", "mpi"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pgp"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
