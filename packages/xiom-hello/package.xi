// XIOM -- xiom.hello package manifest
// Copyright (c) 2026 Eleftherios Notas and XIOM Foundation
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// NOTE: `deps` is empty on purpose. The registry install closure resolves
// every version-spec dependency from the registry index, and `xiom.std`
// (the stdlib) is not a registry artifact, so declaring it here would make
// `xiom pkg install xiom.hello` fail with
// "dependency 'xiom.std' of xiom.hello v0.1.0 is not in the registry".
// The library itself imports nothing; the conformance tests use xiom.std
// modules at compile time, which is not a runtime dependency.

package xiom_hello {
  name: "xiom.hello";
  version: "0.1.0";
  description: "Minimal XIOM package -- the canonical first-publish example";
  authors: ["XIOM Foundation"];
  modules: ["xiom.hello"];
  deps: {};
}
