// XIOM -- xiom.pgn package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// PGN (Portable Game Notation) codec for a documented subset: tag pairs,
// movetext tokens (move numbers, SAN, comments, NAGs, result), and canonical
// emit. xiom.std is the standard library: a platform dependency, excluded from
// the registry install closure. The module itself imports xiom.string,
// xiom.string.builder, xiom.string.compare and xiom.convert from it; the
// tests additionally use xiom.test and xiom.io.

package xiom_pgn {
  name: "xiom.pgn";
  version: "0.1.0";
  description: "PGN chess notation codec: tag pairs, movetext tokens, canonical emit";
  categories: ["graphics"];
  keywords: ["pgn", "chess", "notation", "games"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pgn"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
