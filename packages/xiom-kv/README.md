# xiom.kv

Embedded log-structured key-value store for XIOM: append-only segment files,
CRC32C-framed records, tombstones, crash-consistent reopen and atomic-rename
compaction. Pure XIOM, standard library only (`xiom.std`).

## Consumer snippet

```xiom
let mut s = kv_open("data", "app-", 4194304).value; // check is_ok first
let _ = kv_put(&mut s, "user:1", "Ada");
let v = kv_get(&s, "user:1");                       // Ok(Some("Ada"))
```

`kv_open(dir, prefix, seg_max)` discovers (or creates) files named
`<prefix>seg-<10-digit-id>.kv` inside `dir`. Keys are 1..4096 bytes, values up
to 64 MiB; `kv_put_bytes`/`kv_get_bytes` move arbitrary bytes, while
`kv_put`/`kv_get` use the `Str` (NUL-terminated text) representation.

## API

| Function | Result |
| --- | --- |
| `kv_open(dir, prefix, seg_max)` | `Result[KvStore, Str]` |
| `kv_reopen(&mut store)` | `Result[Unit, Str]` |
| `kv_put(&mut, key, value)` / `kv_put_bytes(&mut, key, &Vec[UInt8])` | `Result[Unit, Str]` |
| `kv_get(&store, key)` / `kv_get_bytes` | `Result[Option[Str], Str]` / `Result[Option[Vec[UInt8]], Str]` |
| `kv_delete(&mut, key)` | `Result[Bool, Str]` (true = was live; idempotent) |
| `kv_contains` / `kv_count` / `kv_keys` | `Bool` / `Int` / `Vec[Str]` (first-write order) |
| `kv_compact(&mut)` | `Result[Unit, Str]` |
| `kv_snapshot(&mut)` | `Result[Unit, Str]` (optional accelerator) |
| `kv_close(&mut)` | no-op lifecycle marker |

All errors start with `kv: `.

## Durability caveat

The store is **crash-consistent, not durable**: this toolchain has no
fsync/flush (the stdlib stubs are empty), so an acknowledged `kv_put` can be
lost if the OS or machine crashes before it flushes the file. What is
guaranteed is consistency: a torn or corrupt final record is repaired away on
the next `kv_open`/`kv_reopen` (the file is rewritten to its last valid record
boundary and a fresh segment is started), and a partially finished compaction
leaves either the old or the new segment set readable.

## Single-writer rule

One process (or thread) must own a `prefix` at a time. There are no file
locks in the toolchain, so concurrent writers to the same prefix are an
unenforced contract and can lose or interleave records. Multiple prefixes in
one directory are safe.

## Toolchain note

`io.list_dir` returns corrupted entry names on the pinned v0.64.0 Windows
runtime, so segment discovery probes `<prefix>seg-<id>.kv` ids 1.. up to 32
consecutive misses instead of listing the directory. See `SPEC.md`
("toolchain deviations").
