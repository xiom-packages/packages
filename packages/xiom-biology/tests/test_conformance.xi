// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.biology conformance tests (18 checks)
// Port task: prove the pure-XIOM xiom.biology FASTA/FASTQ codecs against
// SPEC.md: record structure and accessors, wrapped FASTA lines with
// whitespace stripping, case-insensitive six-bucket base counts, GC content
// in per-mille, FASTQ sequence/quality handling with Phred+33 and Phred+64,
// multi-line records, quality statistics with truncating mean, streaming
// with consumed byte counts, whole-buffer walks, format auto-detection, and
// the malformed-input catalog with record index and byte offset. Every
// buffer is built in-test; there are no data files.
//
// All Str equality goes through xiom.string.compare.str_compare (BUG 17:
// `==` on Str values read from Vec[Str] elements lowers to a pointer
// comparison), and every Vec element read binds a typed local first.

module biology_tests
use xiom.io; use xiom.test; use xiom.biology;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn fasta_err_is(s: Str, want: Str) -> Bool {
  let r = bio_fasta_parse_next(s, 0, 0);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn fasta_err_at(s: Str, from: Int, rec: Int, want: Str) -> Bool {
  let r = bio_fasta_parse_next(s, from, rec);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn fastq33_err_is(s: Str, want: Str) -> Bool {
  let r = bio_fastq_parse_next(s, 0, 0);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn fastq64_err_is(s: Str, want: Str) -> Bool {
  let r = bio_fastq_parse_next_enc(s, 0, 0, BIO_PHRED64);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn count_err_is(s: Str, want: Str) -> Bool {
  let r = bio_record_count(s);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn parse_all_err_is(s: Str, want: Str) -> Bool {
  let r = bio_parse_all(s);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// --- fixtures ---------------------------------------------------------------

fn fasta_two() -> Str {
  return ">seq1 first record\nACGTACGT\nNN\n>seq2 second\nGGCC\n";
}

fn fasta_wrapped() -> Str {
  return ">wrapped\nAC GT\n  acgt \nT\n";
}

fn fastq_two() -> Str {
  return "@a\nACGT\n+\nIIII\n@b\nGG\n+b desc\n!!\n";
}

fn fastq_two_64() -> Str {
  return "@a\nACGT\n+\nIIII\n@b\nGG\n+b desc\nBB\n";
}

fn fastq_multiline() -> Str {
  return "@m\nACGT\nAC\n+\nIIII\nII\n";
}

fn fastq_trunc() -> Str {
  return "@m2\nACG\n+\nII!\n";
}

fn fastq_basic() -> Str {
  return "@r1 desc\nACGT\n+\nIIII\n";
}

fn fastq_phred64() -> Str {
  return "@r1 desc\nACGT\n+\nBBBB\n";
}

// --- tests ------------------------------------------------------------------

fn t1() -> TestResult {
  let r = bio_fasta_parse_next(fasta_two(), 0, 0);
  var ok = false;
  match r {
    Ok(rec) => {
      ok = bio_record_kind(&rec) == BIO_FORMAT_FASTA;
      if !streq(bio_record_id(&rec), "seq1") { ok = false; }
      if !streq(bio_record_description(&rec), "first record") { ok = false; }
      if !streq(bio_record_sequence(&rec), "ACGTACGTNN") { ok = false; }
      if bio_record_length(&rec) != 10 { ok = false; }
      if bio_record_base_count(&rec, 0) != 2 { ok = false; }
      if bio_record_base_count(&rec, 1) != 2 { ok = false; }
      if bio_record_base_count(&rec, 2) != 2 { ok = false; }
      if bio_record_base_count(&rec, 3) != 2 { ok = false; }
      if bio_record_base_count(&rec, 4) != 2 { ok = false; }
      if bio_record_base_count(&rec, 5) != 0 { ok = false; }
      if bio_record_gc_permille(&rec) != 400 { ok = false; }
      if bio_record_has_quality(&rec) { ok = false; }
      if bio_record_encoding(&rec) != -1 { ok = false; }
      if bio_record_qual_mean10(&rec) != -1 { ok = false; }
      if bio_record_offset(&rec) != 0 { ok = false; }
      if bio_record_next_offset(&rec) != 31 { ok = false; }
      if bio_record_consumed(&rec) != 31 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "FASTA first record: id, description, sequence, counts, GC, span");
}

fn t2() -> TestResult {
  let r = bio_fasta_parse_next(fasta_wrapped(), 0, 0);
  var ok = false;
  match r {
    Ok(rec) => {
      ok = streq(bio_record_sequence(&rec), "ACGTacgtT");
      if !streq(bio_record_id(&rec), "wrapped") { ok = false; }
      if !streq(bio_record_description(&rec), "") { ok = false; }
      if bio_record_length(&rec) != 9 { ok = false; }
      if bio_record_base_count(&rec, 0) != 2 { ok = false; }
      if bio_record_base_count(&rec, 1) != 2 { ok = false; }
      if bio_record_base_count(&rec, 2) != 2 { ok = false; }
      if bio_record_base_count(&rec, 3) != 3 { ok = false; }
      if bio_record_base_count(&rec, 5) != 0 { ok = false; }
      if bio_record_gc_permille(&rec) != 444 { ok = false; }
      if bio_record_next_offset(&rec) != 25 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "FASTA wrapped lines strip whitespace and count case-insensitively");
}

fn t3() -> TestResult {
  let r0 = bio_fasta_parse_next(fasta_two(), 0, 0);
  var ok = false;
  match r0 {
    Ok(rec0) => {
      ok = bio_record_next_offset(&rec0) == 31;
      let r1 = bio_fasta_parse_next(fasta_two(), bio_record_next_offset(&rec0), 1);
      match r1 {
        Ok(rec1) => {
          if !streq(bio_record_id(&rec1), "seq2") { ok = false; }
          if !streq(bio_record_description(&rec1), "second") { ok = false; }
          if !streq(bio_record_sequence(&rec1), "GGCC") { ok = false; }
          if bio_record_offset(&rec1) != 31 { ok = false; }
          if bio_record_next_offset(&rec1) != 49 { ok = false; }
          if bio_record_consumed(&rec1) != 18 { ok = false; }
          if bio_record_gc_permille(&rec1) != 1000 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
      let c = bio_record_count(fasta_two());
      match c {
        Ok(n) => { if n != 2 { ok = false; } },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "FASTA multi-record walk: consumed byte counts and record_count");
}

fn t4() -> TestResult {
  var ok = fasta_err_is("hello\n", "bio: missing FASTA header at record 0 offset 0");
  if !fasta_err_is(">e\n", "bio: empty FASTA sequence at record 0 offset 3") { ok = false; }
  if !fasta_err_is(">bad\nACGX\n", "bio: invalid FASTA base at record 0 offset 8") { ok = false; }
  if !fasta_err_is(">\nAC\n", "bio: empty FASTA header at record 0 offset 0") { ok = false; }
  if !fasta_err_at("x", 99, 2, "bio: bad offset at record 2 offset 99") { ok = false; }
  if !fasta_err_at("x", -1, 0, "bio: bad offset at record 0 offset -1") { ok = false; }
  if !fasta_err_at(">bad\nACGX\n", 0, 7, "bio: invalid FASTA base at record 7 offset 8") { ok = false; }
  return assert(ok, "FASTA malformed catalog carries record index and byte offset");
}

fn t5() -> TestResult {
  var ok = bio_detect_format(fasta_two(), 0) == BIO_FORMAT_FASTA;
  if bio_detect_format(fastq_two(), 0) != BIO_FORMAT_FASTQ { ok = false; }
  if bio_detect_format("  \n\t\n>a\nAC\n", 0) != BIO_FORMAT_FASTA { ok = false; }
  if bio_format(fastq_basic()) != BIO_FORMAT_FASTQ { ok = false; }
  if bio_format("hello") != BIO_FORMAT_UNKNOWN { ok = false; }
  if bio_detect_format("", 0) != BIO_FORMAT_UNKNOWN { ok = false; }
  if bio_detect_format(">a", 1) != BIO_FORMAT_UNKNOWN { ok = false; }
  if bio_detect_format(">a", -1) != BIO_FORMAT_UNKNOWN { ok = false; }
  return assert(ok, "format auto-detect skips leading blanks and honors from");
}

fn t6() -> TestResult {
  let r = bio_fastq_parse_next(fastq_basic(), 0, 0);
  var ok = false;
  match r {
    Ok(rec) => {
      ok = bio_record_kind(&rec) == BIO_FORMAT_FASTQ;
      if !streq(bio_record_id(&rec), "r1") { ok = false; }
      if !streq(bio_record_description(&rec), "desc") { ok = false; }
      if !streq(bio_record_sequence(&rec), "ACGT") { ok = false; }
      if !streq(bio_record_quality(&rec), "IIII") { ok = false; }
      if bio_record_length(&rec) != 4 { ok = false; }
      if !bio_record_has_quality(&rec) { ok = false; }
      if bio_record_encoding(&rec) != BIO_PHRED33 { ok = false; }
      if bio_record_qual_min(&rec) != 40 { ok = false; }
      if bio_record_qual_max(&rec) != 40 { ok = false; }
      if bio_record_qual_mean10(&rec) != 400 { ok = false; }
      if bio_record_offset(&rec) != 0 { ok = false; }
      if bio_record_next_offset(&rec) != 21 { ok = false; }
      if bio_record_gc_permille(&rec) != 500 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "FASTQ Phred+33 record: sequence, quality, stats, span");
}

fn t7() -> TestResult {
  let a = bio_fastq_parse_next(fastq_phred64(), 0, 0);
  let b = bio_fastq_parse_next_enc(fastq_phred64(), 0, 0, BIO_PHRED64);
  var ok = false;
  match a {
    Ok(rec33) => {
      ok = bio_record_qual_mean10(&rec33) == 330;
      if bio_record_encoding(&rec33) != BIO_PHRED33 { ok = false; }
      match b {
        Ok(rec64) => {
          if bio_record_encoding(&rec64) != BIO_PHRED64 { ok = false; }
          if bio_record_qual_min(&rec64) != 2 { ok = false; }
          if bio_record_qual_max(&rec64) != 2 { ok = false; }
          if bio_record_qual_mean10(&rec64) != 20 { ok = false; }
          if !streq(bio_record_quality(&rec64), "BBBB") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "FASTQ explicit Phred+64: same bytes, offset-64 scores");
}

fn t8() -> TestResult {
  let r = bio_fastq_parse_next(fastq_multiline(), 0, 0);
  var ok = false;
  match r {
    Ok(rec) => {
      ok = streq(bio_record_sequence(&rec), "ACGTAC");
      if !streq(bio_record_quality(&rec), "IIIIII") { ok = false; }
      if bio_record_length(&rec) != 6 { ok = false; }
      if bio_record_qual_mean10(&rec) != 400 { ok = false; }
      if bio_record_next_offset(&rec) != 21 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let t = bio_fastq_parse_next(fastq_trunc(), 0, 0);
  match t {
    Ok(rec2) => {
      if !streq(bio_record_quality(&rec2), "II!") { ok = false; }
      if bio_record_qual_min(&rec2) != 0 { ok = false; }
      if bio_record_qual_max(&rec2) != 40 { ok = false; }
      if bio_record_qual_mean10(&rec2) != 266 { ok = false; }
      if bio_record_length(&rec2) != 3 { ok = false; }
      if bio_record_next_offset(&rec2) != 14 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "FASTQ multi-line sequence/quality and truncated mean (tenths)");
}

fn t9() -> TestResult {
  let r0 = bio_fastq_parse_next(fastq_two(), 0, 0);
  var ok = false;
  match r0 {
    Ok(rec0) => {
      ok = streq(bio_record_id(&rec0), "a");
      if bio_record_next_offset(&rec0) != 15 { ok = false; }
      if bio_record_qual_mean10(&rec0) != 400 { ok = false; }
      let r1 = bio_fastq_parse_next(fastq_two(), bio_record_next_offset(&rec0), 1);
      match r1 {
        Ok(rec1) => {
          if !streq(bio_record_id(&rec1), "b") { ok = false; }
          if !streq(bio_record_sequence(&rec1), "GG") { ok = false; }
          if !streq(bio_record_quality(&rec1), "!!") { ok = false; }
          if bio_record_offset(&rec1) != 15 { ok = false; }
          if bio_record_next_offset(&rec1) != 32 { ok = false; }
          if bio_record_consumed(&rec1) != 17 { ok = false; }
          if bio_record_qual_mean10(&rec1) != 0 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
      let c = bio_record_count(fastq_two());
      match c {
        Ok(n) => { if n != 2 { ok = false; } },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "FASTQ multi-record walk: offsets, consumed, count");
}

fn t10() -> TestResult {
  var ok = fastq33_err_is("@e\n+\n\n", "bio: empty FASTQ sequence at record 0 offset 3");
  if !fastq33_err_is("@q\nAC\n", "bio: missing FASTQ separator at record 0 offset 6") { ok = false; }
  if !fastq33_err_is("@q\nAC\n+\nI \n", "bio: invalid FASTQ quality at record 0 offset 9") { ok = false; }
  if !fastq33_err_is("@q\nAC\n+\n", "bio: FASTQ quality-length mismatch at record 0 offset 8") { ok = false; }
  if !fastq33_err_is("@q\nACGT\n+\nII\n", "bio: FASTQ quality-length mismatch at record 0 offset 13") { ok = false; }
  if !fastq33_err_is("@q\nAC\n+\nIII\n", "bio: FASTQ quality-length mismatch at record 0 offset 10") { ok = false; }
  if !fastq33_err_is("@abc\nAC\n+xyz\nII\n", "bio: FASTQ repeated header mismatch at record 0 offset 8") { ok = false; }
  if !fastq33_err_is("@\nAC\n+\nII\n", "bio: empty FASTQ header at record 0 offset 0") { ok = false; }
  if !fastq33_err_is("hello", "bio: missing FASTQ header at record 0 offset 0") { ok = false; }
  if !fastq64_err_is("@q\nAC\n+\n!I\n", "bio: invalid FASTQ quality at record 0 offset 8") { ok = false; }
  return assert(ok, "FASTQ malformed catalog: separator, mismatch, quality, header");
}

fn t11() -> TestResult {
  let r = bio_parse_all(fasta_two());
  var ok = false;
  match r {
    Ok(b) => {
      ok = bio_batch_format(&b) == BIO_FORMAT_FASTA;
      if bio_batch_count(&b) != 2 { ok = false; }
      if !streq(bio_batch_id(&b, 0), "seq1") { ok = false; }
      if !streq(bio_batch_id(&b, 1), "seq2") { ok = false; }
      if !streq(bio_batch_sequence(&b, 0), "ACGTACGTNN") { ok = false; }
      if bio_batch_length(&b, 0) != 10 { ok = false; }
      if bio_batch_length(&b, 1) != 4 { ok = false; }
      if bio_batch_gc_permille(&b, 0) != 400 { ok = false; }
      if bio_batch_gc_permille(&b, 1) != 1000 { ok = false; }
      if bio_batch_offset(&b, 0) != 0 { ok = false; }
      if bio_batch_offset(&b, 1) != 31 { ok = false; }
      if bio_batch_next_offset(&b, 1) != 49 { ok = false; }
      if bio_batch_qual_mean10(&b, 0) != -1 { ok = false; }
      if !streq(bio_batch_id(&b, 9), "") { ok = false; }
      if bio_batch_length(&b, -1) != -1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "bio_parse_all FASTA batch: parallel accessors");
}

fn t12() -> TestResult {
  let a = bio_parse_all(fastq_two());
  var ok = false;
  match a {
    Ok(b33) => {
      ok = bio_batch_format(&b33) == BIO_FORMAT_FASTQ;
      if bio_batch_count(&b33) != 2 { ok = false; }
      if !streq(bio_batch_id(&b33, 0), "a") { ok = false; }
      if !streq(bio_batch_sequence(&b33, 1), "GG") { ok = false; }
      if bio_batch_length(&b33, 0) != 4 { ok = false; }
      if bio_batch_qual_mean10(&b33, 0) != 400 { ok = false; }
      if bio_batch_qual_mean10(&b33, 1) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let c = bio_parse_all_enc(fastq_two_64(), BIO_PHRED64);
  match c {
    Ok(b64) => {
      if bio_batch_qual_mean10(&b64, 0) != 90 { ok = false; }
      if bio_batch_qual_mean10(&b64, 1) != 20 { ok = false; }
      if bio_batch_next_offset(&b64, 1) != 32 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "bio_parse_all FASTQ batch: Phred+33 vs +64 stats");
}

fn t13() -> TestResult {
  var ok = count_err_is("hello\n", "bio: unknown format at record 0 offset 0");
  if !parse_all_err_is("", "bio: unknown format at record 0 offset 0") { ok = false; }
  let bad_enc = bio_parse_all_enc(fasta_two(), 9);
  match bad_enc {
    Ok(_) => { ok = false; },
    Err(e) => { if !streq(e, "bio: invalid quality encoding at record 0 offset 0") { ok = false; } },
  }
  let bad_enc2 = bio_record_count_enc(">a\nAC\n", 3);
  match bad_enc2 {
    Ok(_) => { ok = false; },
    Err(e2) => { if !streq(e2, "bio: invalid quality encoding at record 0 offset 0") { ok = false; } },
  }
  let mid = bio_parse_all(">a\nAC\n>b\nAX\n");
  match mid {
    Ok(_) => { ok = false; },
    Err(e3) => { if !streq(e3, "bio: invalid FASTA base at record 1 offset 10") { ok = false; } },
  }
  return assert(ok, "unknown format, invalid encoding, and mid-buffer record index");
}

fn t14() -> TestResult {
  let r = bio_base_counts("ACGTN");
  var ok = false;
  match r {
    Ok(c) => {
      ok = c.total == 5;
      if c.count_a != 1 { ok = false; }
      if c.count_c != 1 { ok = false; }
      if c.count_g != 1 { ok = false; }
      if c.count_t != 1 { ok = false; }
      if c.count_n != 1 { ok = false; }
      if c.count_other != 0 { ok = false; }
      if bio_gc_permille(c) != 400 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = bio_base_counts("acgtURY");
  match r2 {
    Ok(c2) => {
      if c2.total != 7 { ok = false; }
      if c2.count_a != 1 { ok = false; }
      if c2.count_t != 1 { ok = false; }
      if c2.count_other != 3 { ok = false; }
      if bio_gc_permille(c2) != 285 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = bio_base_counts("AC X");
  match r3 {
    Ok(_) => { ok = false; },
    Err(e3) => { if !streq(e3, "bio: invalid base at record 0 offset 2") { ok = false; } },
  }
  let r4 = bio_base_counts("");
  match r4 {
    Ok(c4) => {
      if c4.total != 0 { ok = false; }
      if bio_gc_permille(c4) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "bio_base_counts and bio_gc_permille: alphabet and truncation");
}

fn t15() -> TestResult {
  var ok = bio_phred_offset(BIO_PHRED33) == 33;
  if bio_phred_offset(BIO_PHRED64) != 64 { ok = false; }
  if bio_phred_offset(9) != -1 { ok = false; }
  if bio_phred_quality(33, BIO_PHRED33) != 0 { ok = false; }
  if bio_phred_quality(126, BIO_PHRED33) != 93 { ok = false; }
  if bio_phred_quality(126, BIO_PHRED64) != 62 { ok = false; }
  if bio_phred_quality(63, BIO_PHRED64) != -1 { ok = false; }
  if bio_phred_quality(32, BIO_PHRED33) != -1 { ok = false; }
  if bio_phred_quality(127, BIO_PHRED33) != -1 { ok = false; }
  if bio_phred_quality(200, BIO_PHRED33) != -1 { ok = false; }
  return assert(ok, "bio_phred_quality/bio_phred_offset boundaries");
}

fn t16() -> TestResult {
  let r = bio_fasta_parse_next(">a\nAC\n\n\n", 0, 0);
  var ok = false;
  match r {
    Ok(rec) => {
      ok = bio_record_next_offset(&rec) == 8;
      if !streq(bio_record_sequence(&rec), "AC") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = bio_fasta_parse_next(">a\r\nACGT\r\n", 0, 0);
  match r2 {
    Ok(rec2) => {
      if !streq(bio_record_sequence(&rec2), "ACGT") { ok = false; }
      if bio_record_length(&rec2) != 4 { ok = false; }
      if bio_record_next_offset(&rec2) != 10 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = bio_fasta_parse_next(">a\nACGT", 0, 0);
  match r3 {
    Ok(rec3) => {
      if !streq(bio_record_sequence(&rec3), "ACGT") { ok = false; }
      if bio_record_next_offset(&rec3) != 7 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "FASTA trailing blank lines, CRLF and unterminated last line");
}

fn t17() -> TestResult {
  var ok = fasta_err_is("", "bio: missing FASTA header at record 0 offset 0");
  if !fasta_err_is("   \n", "bio: missing FASTA header at record 0 offset 4") { ok = false; }
  let c = bio_record_count(">a\nAC\n>b\nGT\n");
  match c {
    Ok(n) => { if n != 2 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty and whitespace-only buffers are missing-header errors");
}

fn t18() -> TestResult {
  let r = bio_fasta_parse_next(fasta_two(), 0, 0);
  var ok = false;
  match r {
    Ok(rec) => {
      let bs = bio_record_sequence_bytes(&rec);
      ok = bs.len() == 10;
      let b0: UInt8 = bs[0];
      let b9: UInt8 = bs[9];
      if ((b0 as Int) & 255) != 65 { ok = false; }
      if ((b9 as Int) & 255) != 78 { ok = false; }
      let bc = bio_record_base_counts(&rec);
      if bc.total != 10 { ok = false; }
      if bc.count_n != 2 { ok = false; }
      if bio_gc_permille(bc) != 400 { ok = false; }
      if bio_record_base_count(&rec, 9) != -1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "record accessors: sequence bytes, base buckets, quality text");
}

fn main() -> Int {
  io.println("=== xiom.biology conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.biology: all tests passed");
  } else {
    io.println("xiom.biology: tests failed");
  }
  return failed;
}
