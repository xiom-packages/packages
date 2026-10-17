// XIOM -- xiom.template package manifest
// Port task: replace the xiom.template placeholder with a real, tested,
// documented, pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure.
//
// Modules:
//   * xiom.template        (src/template.xi) -- v0.1.x placeholder surface
//     (template_render / template_render_lenient / template_keys /
//     template_needs_keys); unchanged in 0.2.0.
//   * xiom.template.blocks (src/blocks.xi)   -- v0.2.0 block surface
//     ({{#sections}} / {{^inverted}} / {{/close}}, loops with {{.}},
//     inverted sections, dotted paths, a context stack, HTML auto-escaping
//     and the flat TemplateData model).
//
// The module imports xiom.string, xiom.string.builder and
// xiom.string.compare from the standard library; the tests additionally
// use xiom.test and xiom.io.

package xiom_template {
  name: "xiom.template";
  version: "0.2.0";
  description: "Mustache-style template rendering: placeholder substitution (v0.1 surface) plus sections, loops and auto-escaping (v0.2 block surface)";
  categories: ["text-nlp", "tooling"];
  keywords: ["template", "mustache", "render", "text", "sections", "escape"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.template", "xiom.template.blocks"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
