// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.cfn package manifest
// AWS CloudFormation templating and stack-lifecycle model as a pure,
// deterministic XIOM package: JSON-ish template scanning, resource and
// reference model, intrinsic-function evaluation subset, parameter/output
// handling, the stack state machine and change-set diffing. No AWS calls,
// no networking, no clock, no FFI.
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string, xiom.string.compare,
// xiom.convert and xiom.convert.tostring from it; the tests additionally use
// xiom.test and xiom.io.

package xiom_cfn {
  name: "xiom.cfn";
  version: "0.1.0";
  description: "AWS CloudFormation templating and stack lifecycle model: JSON-ish template scanning, resource model, intrinsic evaluation (Ref/GetAtt/Join/Sub/Select/Split/If/Equals/FindInMap), parameter/output handling, stack state machine, change sets";
  categories: ["systems"];
  keywords: ["cloudformation", "cfn", "template", "stack", "intrinsic", "aws", "infrastructure"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.cfn"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
