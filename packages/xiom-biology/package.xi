// XIOM -- xiom.biology package manifest
// Port task: populate the xiom.biology package with real, tested, pure-XIOM
// FASTA/FASTQ sequence codecs (records, base counts, GC content, Phred
// quality statistics, multi-record stream walking).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.compare, xiom.string.builder and xiom.convert.int from it; the
// tests additionally use xiom.test and xiom.io.

package xiom_biology {
  name: "xiom.biology";
  version: "0.1.1";
  description: "FASTA and FASTQ sequence parsing: records, base composition, GC content, and Phred quality statistics";
  categories: ["science", "data"];
  keywords: ["fasta", "fastq", "bioinformatics", "sequence", "genomics"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.biology"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
