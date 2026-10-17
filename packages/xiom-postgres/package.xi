// XIOM -- xiom.postgres package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM PostgreSQL wire-protocol (v3) client. No FFI, no libpq, no
// bridge C: the transport is xiom.net.socket and the protocol codec is
// XIOM. xiom.std is the standard library: a platform dependency, excluded
// from the registry install closure. The modules import xiom.net.socket,
// xiom.string, xiom.convert, xiom.crypto, xiom.encoding and xiom.rand; the
// tests additionally use xiom.test and xiom.io.

package xiom_postgres {
  name: "xiom.postgres";
  version: "0.1.0";
  description: "PostgreSQL wire-protocol (v3) client in pure XIOM: startup, cleartext/MD5/SCRAM-SHA-256 auth, simple queries, typed errors";
  categories: ["database"];
  keywords: ["postgresql", "postgres", "wire-protocol", "sql", "scram-sha-256"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.postgres", "xiom.postgres.wire", "xiom.postgres.auth"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
