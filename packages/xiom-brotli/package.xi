// XIOM -- xiom.brotli package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports only xiom.string.compare
// from the stdlib (plus its own local helpers); the tests use xiom.io,
// xiom.convert, xiom.test, xiom.string and xiom.string.compare.

package xiom_brotli {
  name: "xiom.brotli";
  version: "0.1.0";
  description: "Real RFC 7932 brotli bindings for XIOM (vendored google/brotli 1.2.0 C sources, no system library): decoder (create/stream/one-shot/destroy, upstream error codes + strings) and encoder (one-shot, streaming with quality/lgwin/mode parameters, TakeOutput/IsFinished) at 100% of the declared surface";
  categories: ["data"];
  keywords: ["brotli", "compression", "rfc7932", "http", "streaming", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.brotli"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
