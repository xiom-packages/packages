# xiom.biology

Pure-XIOM FASTA and FASTQ sequence parsing: records, base composition, GC
content, Phred quality statistics, one-record streaming with consumed byte
counts, whole-buffer walks, and format auto-detection. No FFI, no data
files, no floating point.

## Status

Implemented and conformance-tested (18 checks, see
`tests/test_conformance.xi`). Honest scope:

- **FASTA**: `>` header (id + free-text description), wrapped sequence lines
  with space/tab/CR stripped, case-insensitive six-bucket base counts
  (A/C/G/T/N/other), GC content in per-mille (truncated), length.
- **FASTQ**: `@` header, one or more sequence lines, `+` separator with an
  optional repeated header (id must match when present), quality lines
  counted to exactly the sequence length. Phred+33 is the default;
  Phred+64 is opt-in through the `*_enc` entry points. Per-record min, max
  and mean quality in tenths (truncated mean).
- **Streaming**: `bio_fasta_parse_next` / `bio_fastq_parse_next_enc` parse a
  single record from any byte offset and report the next offset, so
  multi-record buffers are walked with explicit consumed byte counts.
- **Whole-buffer walks**: `bio_record_count` and `bio_parse_all` (plus
  `_enc` variants) auto-detect the format from the first non-whitespace
  byte and validate every record.
- **Errors** carry the record index and byte offset, e.g.
  `bio: invalid FASTA base at record 1 offset 10`.

Not implemented (deliberately, for this 0.1.0 scope): gap characters `-`
and `.`, alignment formats (SAM/BAM/stockholm/CLUSTAL), gzip readers,
writing/serializing records, codon translation, and statistical
auto-detection between Phred+33 and Phred+64 (choose the encoding
explicitly).

## Usage

```xiom
use xiom.biology;

fn summarize(buffer: Str) -> Int {
  let r = bio_parse_all(buffer);        // Phred+33 for FASTQ
  match r {
    Ok(batch) => {
      var i = 0;
      while i < bio_batch_count(&batch) {
        let id = bio_batch_id(&batch, i);
        let len = bio_batch_length(&batch, i);
        let gc = bio_batch_gc_permille(&batch, i);   // per-mille, truncated
        let q = bio_batch_qual_mean10(&batch, i);    // tenths, -1 for FASTA
        // ... use id / len / gc / q ...
        i = i + 1;
      }
      return bio_batch_count(&batch);
    },
    Err(e) => {
      // e looks like "bio: <what> at record <r> offset <n>"
      return 0;
    },
  }
}
```

Single-record streaming, with explicit Phred+64 quality:

```xiom
use xiom.biology;

fn walk(buffer: Str) -> Int {
  var from: Int = 0;
  var idx: Int = 0;
  while from < buffer.len() && bio_detect_format(buffer, from) != BIO_FORMAT_UNKNOWN {
    let r = bio_fastq_parse_next_enc(buffer, from, idx, BIO_PHRED64);
    match r {
      Ok(rec) => {
        from = bio_record_next_offset(&rec);   // consumed: next_offset - offset
        idx = idx + 1;
      },
      Err(_) => { return idx; },
    }
  }
  return idx;
}
```

Notes for callers: compare `Str` values with
`xiom.string.compare.str_compare` (the plain `==` on a `Str` read from a
`Vec[Str]` element is a pointer comparison on this compiler), and read
`Vec[...]` elements into a typed local before use.

## Verification

From the repository root:

```powershell
.\scripts\port.ps1 -Package xiom.biology
```

Expected tail: `port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Specification

`SPEC.md` documents the grammar, alphabet table, quality math, streaming
semantics, and the exact error message catalog.
