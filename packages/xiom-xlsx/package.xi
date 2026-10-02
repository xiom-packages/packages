// XIOM -- xiom.xlsx package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder, xiom.string.compare, xiom.convert, the real
// xiom.compress.deflate stack (fixed-Huffman deflate + capped inflate) and
// xiom.hash.hash for CRC32-IEEE; the tests additionally use xiom.test and
// xiom.io.

package xiom_xlsx {
  name: "xiom.xlsx";
  version: "0.1.0";
  description: "Excel OpenXML (XLSX) spreadsheet codec: minimal ZIP container plus SpreadsheetML workbook/sheet/style reader and writer";
  categories: ["data"];
  keywords: ["xlsx", "excel", "spreadsheet", "openxml", "zip", "deflate", "spreadsheetml"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.xlsx"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
