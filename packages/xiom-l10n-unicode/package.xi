// XIOM -- xiom.l10n-unicode package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep). The library module uses
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.io, xiom.test and xiom.convert.
//
// Naming note: the package (manifest) name is "xiom.l10n-unicode" as
// requested, but the compiler module name must be a dotted identifier
// (v0.62.2 rejects '-' in `module` declarations), so the public module is
// xiom.l10n.unicode; the generated tables live in xiom.l10n.unicode.tables.

package xiom_l10n_unicode {
  name: "xiom.l10n-unicode";
  version: "0.1.0";
  description: "Unicode subset for l10n: category/script/block data, full case mapping and folding, NFD/NFC/NFKD/NFKC, grapheme/word/sentence boundaries";
  categories: ["text", "data"];
  keywords: ["unicode", "l10n", "i18n", "normalization", "case-folding", "segmentation", "grapheme", "utf8"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.l10n.unicode", "xiom.l10n.unicode.tables"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
