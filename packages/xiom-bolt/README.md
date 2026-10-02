# xiom.bolt

> **Status:** `incubating` -- conformance-tested (18/18); published at `v0.1.2` on the XIOM registry.
> **Scope:** read-only STRUCTURE parsing of a bbolt database file. No mmap,
> no writes, no transactions.

`xiom.bolt` decodes the on-disk page-file layout of
[bbolt](https://github.com/etcd-io/bbolt) (the maintained etcd-io fork of
BoltDB) from a caller-supplied `Vec[UInt8]`:

- **Page headers** (id u64, flags u16, count u16, overflow u32) and
  page-by-offset access with the page size taken from the meta page.
- **Both meta pages**: magic `0xED0CDAED`, version 2, page-size policy
  (power of two in 1024..65536), root bucket `{root pgid, sequence}`,
  freelist pgid, high-water pgid, txid and the FNV-1a-64 checksum over the 56
  bytes before the checksum field. The valid page with the higher txid is
  selected; both pages (including their failed checks) are reported.
- **Branch page elements**: pos u32, ksize u32, pgid u64 per 16-byte element,
  key bytes at `element + pos`, plus the child page-pointer array.
- **Leaf page elements**: flags u32 (bucket `0x01`), pos u32, ksize u32,
  vsize u32; key bytes at `element + pos`, value bytes directly after the
  key. Bucket leaf values decode as `{root pgid, sequence}` with an optional
  inline page image when the bucket flag is set and the value is longer than
  16 bytes.
- **Freelist pages**: element count from the page-header count field, with the
  `0xFFFF` overflow sentinel whose true count is the first u64 payload word;
  the payload may span `overflow` continuation pages.
- **A bounded tree walk** (`bolt_walk_tree`) from a root bucket pgid: an
  explicit depth-first traversal with a caller depth cap, cycle detection,
  page-consistency checks (element pointers inside the page, child ids in
  range) and enforcement of the non-decreasing leaf-key order, returning every
  leaf key span, value span, leaf flags, page id and depth.

The parser never copies page bytes: results are offsets and sizes into your
buffer. Two copy helpers (`bolt_span_bytes`, `bolt_span_str`) and walk-level
convenience accessors (`bolt_walk_key_str`, `bolt_walk_value_str`) are
provided. Every structural error message carries the byte offset or page id
involved.

## What it does NOT do

- No mmap, no file I/O, no writes, no page allocation or merging.
- No transaction, locking, freelist-synchronisation or write-ahead semantics.
- No hash/index bucket support and no `Bucket.Sequence` mutation semantics:
  the sequence is decoded, not maintained.
- Non-meta pages are not checksummed (bbolt only checksums meta pages).
- Not a name-addressed bucket reader: walk the tree and compare key bytes
  yourself. `bolt_walk_key_str` is a convenience, not an API for arbitrary
  binary keys (compare `bolt_span_bytes` results instead when keys are not
  text).

## Usage

```xiom
use xiom.bolt;

// `data` is the whole database file as bytes.
let pr = bolt_meta_read(&data);
if !pr.is_ok { return Err(pr.error); }
let pair: BoltMetaPair = pr.value;

// The selected meta page carries the page size and the root bucket pgid.
let sr = bolt_meta_selected_field(&pair, BOLT_META_FIELD_ROOT);
if !sr.is_ok { return Err(sr.error); }
let root: Int = sr.value;
let qr = bolt_meta_selected_field(&pair, BOLT_META_FIELD_PAGE_SIZE);
if !qr.is_ok { return Err(qr.error); }
let page_size: Int = qr.value;

// In-order leaf cursor: key span, value span, leaf flags, page id, depth.
let wr = bolt_walk_tree(&data, page_size, root, BOLT_MAX_DEPTH);
if !wr.is_ok { return Err(wr.error); }
let walk: BoltWalk = wr.value;
var i = 0;
while i < bolt_walk_count(&walk) {
  let k = bolt_walk_key_str(&data, &walk, i);
  let v = bolt_walk_value_str(&data, &walk, i);
  i = i + 1;
}

// One page by id, checks included.
let pg = bolt_read_page(&data, page_size, root);
```

Running the tests:

```
xiom --run tests/test_conformance.xi
# or, from the repository root:
.\scripts\port.ps1 -Package xiom.bolt
```

The suite builds every fixture byte by byte inside the test, so no database
file is needed.

See `SPEC.md` for the exact byte layouts implemented, the validation order,
the error catalog and the documented clarifications of the port brief
(branch child pointers are u64 element pgids; the freelist count is not a
standalone u32).
