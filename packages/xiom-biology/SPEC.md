# xiom.biology -- specification

FASTA and FASTQ text codecs, version 0.1.0. This document is the reference
for the grammar, alphabet, quality math, streaming semantics, and error
catalog; `tests/test_conformance.xi` pins the behavior below.

## 1. Data model

Parsing is text-in / plain-values-out. All public entry points are free
functions:

| Function | Role |
|----------|------|
| `bio_detect_format(s, from)` | format from the first non-whitespace byte |
| `bio_format(s)` | `bio_detect_format(s, 0)` |
| `bio_fasta_parse_next(s, from, rec)` | one FASTA record |
| `bio_fastq_parse_next(s, from, rec)` | one FASTQ record, Phred+33 |
| `bio_fastq_parse_next_enc(s, from, rec, enc)` | one FASTQ record, explicit encoding |
| `bio_record_count(s)` / `bio_record_count_enc(s, enc)` | validated record count |
| `bio_parse_all(s)` / `bio_parse_all_enc(s, enc)` | parallel-vector `BioBatch` |
| `bio_base_counts(seq)` | six-bucket counts of a bare sequence |
| `bio_gc_permille(counts)` | GC per-mille of a `BaseCounts` |
| `bio_phred_quality(byte, enc)` | Phred score of one byte, -1 invalid |
| `bio_phred_offset(enc)` | 33, 64, or -1 |

`BioRecord` is a flat struct: `kind`, `id`, `description`, `sequence`
(whitespace-stripped, case preserved), `quality` (raw FASTQ quality text),
`seq_len`, six count fields (`count_a` … `count_other`), `gc_permille`,
`has_quality`, `encoding` (-1 for FASTA), `qual_min`, `qual_max`,
`qual_mean10`, and the span (`offset`, `next_offset`). Accessors are
provided for every field (`bio_record_id`, `bio_record_sequence_bytes`,
`bio_record_gc_permille`, `bio_record_qual_mean10`, …); `bio_record_consumed`
is `next_offset - offset`.

`BioBatch` carries whole-buffer walks as parallel vectors that are always
pushed in lockstep and therefore always have equal lengths; use the
`bio_batch_*` accessors, which return `""` / `-1` for out-of-range indices.

## 2. Lexical rules

- Input is a byte string (`Str`); positions are 0-based byte offsets.
- A line ends at LF (`\n`). A CR (`\r`) immediately before the LF is part of
  the terminator (CRLF files work). A lone CR **does not** terminate a line
  and is only treated as whitespace inside header/FASTA-sequence lines; a
  CR-only file is therefore rejected (leading to an empty-sequence error,
  see §3).
- The final line may be unterminated: the end of input ends it.
- Blank lines (empty or only spaces/tabs) are skipped between records and
  contribute nothing inside a FASTA sequence. `next_offset` already skips
  them, so a walk loop can move `from = next_offset` directly.
- A record may be preceded by any run of whitespace: parsing starts at the
  first non-whitespace byte at or after `from`. If none exists before the
  end of input, the record is missing (error).
- Detect format: `>` → `BIO_FORMAT_FASTA`, `@` → `BIO_FORMAT_FASTQ`,
  anything else (or nothing) → `BIO_FORMAT_UNKNOWN`.

## 3. FASTA grammar

```
fasta_record := ">" header_text line_end sequence_line*
header_text  := id ( ws+ description )?
sequence_line:= ( base | ws )* line_end
```

- `id` is the first run of non-whitespace bytes on the header line;
  `description` is the rest of the line with surrounding whitespace trimmed
  (it may be empty). An empty id is a malformed record.
- Sequence lines continue until the next line whose **first byte is `>`** or
  the end of input. Spaces, tabs and CRs inside sequence lines are dropped;
  the retained letters keep their original case.
- The sequence must be non-empty: a header with no sequence letters is
  malformed. (Zero-length sequences are not representable in 0.1.0.)
- Within one buffer, `next_offset` points at the `>` that starts the next
  record (blank lines already consumed), or at the input length.

## 4. FASTQ grammar

```
fastq_record := "@" header_text line_end sequence_line+ separator_line quality_line+
separator_line := "+" header_text?
quality_line := quality_byte* line_end
```

- The header parses exactly like FASTA's.
- Sequence lines continue until the next line whose first byte is `+` (a
  line starting with `+` is always the separator), or the end of input.
  Sequence bytes are validated against the alphabet in §5; whitespace
  **inside** a sequence line is illegal (only line terminators separate
  lines). The sequence must be non-empty.
- The separator may repeat the header, `+id ...`; when it carries a
  non-empty id token, that token must equal the record id, otherwise the
  record is malformed. Anything after the `+` that starts with whitespace is
  ignored as a repeated description.
- Quality bytes are consumed across as many lines as needed until their
  count equals the sequence length exactly. Overshooting, or hitting the end
  of input first, is a `quality-length mismatch`. The record ends right
  after the line on which the counts matched; extra bytes on that line are a
  mismatch, not the next record.
- Quality bytes outside the encoding's range are `invalid FASTQ quality`
  (see §6). Accepted bytes are stored verbatim in `quality`.
- Phred+64 is never auto-detected: select it explicitly, because the same
  bytes are legal in both encodings and only the caller knows the
  provenance of the file.

## 5. Alphabet and base buckets

Legal letters, case-insensitive: `A C G T U N R Y S W K M B D H V`.
Everything else (including `-`, `.`, digits, and whitespace inside a
sequence) is `invalid base`.

Bucket mapping used by `count_a`/`count_c`/`count_g`/`count_t`/`count_n`/
`count_other`:

| bucket | letters |
|--------|---------|
| `count_a` | A / a |
| `count_c` | C / c |
| `count_g` | G / g |
| `count_t` | T / t |
| `count_n` | N / n |
| `count_other` | U, R, Y, S, W, K, M, B, D, H, V (either case) |

So `other` is exactly "U plus the ambiguity codes". `bio_base_counts(seq)`
applies the same rules to a bare sequence and does **not** strip whitespace
(feed it already-stripped text; the record parsers strip for you).

## 6. Quality math

- Phred+33 (`BIO_PHRED33`, default): legal bytes ASCII 33..126,
  `Q = byte - 33`, range 0..93.
- Phred+64 (`BIO_PHRED64`): legal bytes ASCII 64..126, `Q = byte - 64`,
  range 0..62.
- `qual_min` / `qual_max` are the smallest / largest Q over the record.
- `qual_mean10` is the mean quality in tenths:
  `(sum of Q) * 10 / seq_len`, computed with the sum accumulated in `Int`
  and a single division at the end. The division is **truncating**, so
  "II!" (`40,40,0`, len 3) yields `266` (= 266.66…, floor); no rounding.
- For FASTA records `has_quality` is false and `encoding`, `qual_min`,
  `qual_max`, `qual_mean10` are all `-1`.

## 7. GC content

`gc_permille = (count_c + count_g) * 1000 / seq_len`, one truncating
division (positive values, so floor). `N`, `U` and the ambiguity codes are
not counted. Examples: `ACGT` → 500; `GGCC` → 1000; `ACGTacgtT`
(9 letters, 4 GC) → 444; `acgtURY` (7 letters, 2 GC) → 285. A zero-length
composition (only reachable through `bio_gc_permille` on an empty
`BaseCounts`) yields 0.

## 8. Streams, offsets, and record indices

- `offset` is the byte offset of the record's leading `>`/`@`; leading
  blank lines belong to no record.
- `next_offset` is where the next record starts (the input length at the
  end). `consumed = next_offset - offset` covers the record plus the blank
  lines that follow it.
- `bio_*_parse_next` takes the caller's `rec_index` and uses it verbatim in
  error messages, so a walk loop can number records from any base. The
  whole-buffer entry points number records from 0 in walk order.
- Walks stop after the last record; whitespace-only tails are legal and do
  not produce an extra (empty) record.

## 9. Error catalog

Every error message has the shape
`bio: <what> at record <R> offset <N>`; `R` is the record index and `N` the
byte offset described below.

| message | trigger | offset `N` |
|---------|---------|------------|
| `bad offset` | `from` < 0 or > input length | `from` |
| `missing FASTA header` | no `>` at the scan start | first non-ws byte, or the input length |
| `empty FASTA header` | `>` with an empty id | the `>` byte |
| `invalid FASTA base` | illegal sequence byte | the byte |
| `empty FASTA sequence` | zero sequence letters | first byte after the header line |
| `missing FASTQ header` | no `@` at the scan start | first non-ws byte, or the input length |
| `empty FASTQ header` | `@` with an empty id | the `@` byte |
| `invalid FASTQ base` | illegal sequence byte | the byte |
| `missing FASTQ separator` | end of input before `+` | the input length |
| `empty FASTQ sequence` | zero sequence letters | the `+` byte |
| `FASTQ repeated header mismatch` | `+id` differs from the record id | the `+` byte |
| `invalid FASTQ quality` | quality byte outside the encoding range | the byte |
| `FASTQ quality-length mismatch` | quality run overshoots or input ends first | the byte after the sequence-length-th quality byte, or the input length |
| `invalid quality encoding` | `enc` is not 0 or 1 | `from` (walkers: 0) |
| `unknown format` | walkers only: first non-ws byte is neither `>` nor `@` | 0 |
| `invalid base` | `bio_base_counts` on an illegal byte | offset in `seq` (record reported as 0) |

Per-record parse errors are returned verbatim by `bio_record_count`,
`bio_record_count_enc`, `bio_parse_all`, and `bio_parse_all_enc`.

## 10. Complexity and representation notes

All entry points are O(record size) or O(input size), single-pass, and
allocation is limited to the returned strings/vectors. Arithmetic is 64-bit
signed integer only (no floats anywhere); byte reads are widened with an
explicit mask before arithmetic. Multi-record output is carried by parallel
vectors because a `Vec` of structs is not supported by the pinned compiler
(XIOM v0.61.3); for the same reason `Str` equality goes through
`xiom.string.compare.str_compare` in the implementation and tests.

## 11. Non-goals for 0.1.0

Gap characters, alignment formats, codon translation, gzip/streaming file
readers, record writing, quality-encoding auto-detection, and lone-CR line
endings are out of scope. Behavior for inputs above 2 GiB is untested
(offsets are `Int`).
