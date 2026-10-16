// XIOM -- xiom.ssl package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// libssl-class TLS context binding (multi-soname dynamic loader over the
// system libssl builds; SKIP when absent), mirroring the live xiom.openssl
// pattern and composing with xiom.tls (record/handshake codec) and
// xiom.openssl (libcrypto surface).  System-library path: nothing vendored;
// the oracle is the upstream OpenSSL clone (see PROVENANCE.md / SPEC.md).
// Modules: xiom.ssl (loader, contexts, streams, step handshake, memory-BIO
// pump, ALPN, verify modes, typed errors).

package xiom_ssl {
  name: "xiom.ssl";
  version: "0.1.0";
  description: "libssl-class TLS context bindings via dynamic loader (multi-soname, SKIP when absent): server/client contexts, PEM/DER cert-key-chain load, step handshake over a stream fd or memory BIOs, ALPN, verify modes, typed errors";
  categories: ["crypto-security"];
  keywords: ["ssl", "tls", "openssl", "libssl", "binding", "handshake", "alpn"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ssl"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
