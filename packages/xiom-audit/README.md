# xiom.audit

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** hash-chained append-only audit log with verification and export.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`/
> `xiom.string.str_slice` and `xiom.convert.int_to_string`). Tests additionally
> use `xiom.test`, `xiom.io` and `xiom.string.compare`.

## What it is

`xiom.audit` keeps an append-only list of `Str` entries where every entry is
chained to its predecessor with FNV-1a 32-bit over the entry's UTF-8 bytes:

```
h(i) = fnv1a(decimal(h(i-1)) + ":" + entry(i))     h(-1) = 0 (seed)
```

The whole chain can be recomputed and compared to the stored hashes
(`audit_verify`), a prefix can be checked on its own (`audit_verify_prefix`),
and the log can be serialized to a line-oriented text form (`audit_export`).

## API

| Function | Returns | Description |
|---|---|---|
| `audit_hash_fnv1a(s)` | `Int` | FNV-1a 32-bit over the UTF-8 bytes of `s`, in `[0, 2^32-1]`. |
| `audit_new()` | `AuditLog` | Empty log (zero entries, zero hashes, head 0). |
| `audit_append(log, entry)` | `Int` | Chains `entry` onto the head and stores it; returns the new hash. |
| `audit_len(log)` | `Int` | Number of entries. |
| `audit_entry(log, i)` | `Str` | Entry `i`; `""` when out of range. |
| `audit_hash(log, i)` | `Int` | Hash of entry `i`; `-1` when out of range (hashes are never negative). |
| `audit_head_hash(log)` | `Int` | Hash of the last entry; `0` for an empty log. |
| `audit_verify(log)` | `Bool` | Recompute the whole chain and compare; false on any mismatch or vector length mismatch. |
| `audit_verify_prefix(log, up_to)` | `Bool` | Verify entries `[0, up_to)`; `up_to` clamped to `[0, len]`. |
| `audit_export(log)` | `Str` | One `"<seq>\|<hash>\|<entry>"` line per entry joined by LF. |

## Usage

```xi
use xiom.audit;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  var log = audit_new();
  let h0 = audit_append(&mut log, "user=ada action=login");
  let h1 = audit_append(&mut log, "user=ada action=logout");
  io.println(int_to_string(h0));          // 32-bit chain hash, e.g. ...
  io.println(int_to_string(h1));
  if audit_verify(&log) {
    io.println("chain intact");
  }
  io.println(audit_export(&log));
  // 0|...|user=ada action=login
  // 1|...|user=ada action=logout
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.audit
```

Expected tail: 23 `[PASS]` lines, `xiom.audit: all tests passed`, then
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## Limitations

- **FNV-1a 32-bit is not cryptographic.** It is a checksum, not a MAC; a
  motivated attacker can compute colliding/preimage text cheaply. Use a real
  cryptographic hash chain when the adversary is active.
- **Tamper-EVIDENT only with external anchoring.** Anyone who can rewrite the
  whole `entries`/`hashes` pair can recompute a consistent chain and
  `audit_verify` passes. Detection requires the head hash (or the full export)
  to be stored/compared somewhere the writer does not control. There are no
  secrets and no authentication in this module.
- **Export escaping is minimal.** Only LF (`\n`) and `|` (`\|`) are escaped;
  backslashes are used literally, so an entry already containing `\n` or `\|`
  is indistinguishable from an escaped sequence on a byte level.
- **No deletion, compaction or repair**; the log is append-only in memory.
- **No persistence, no concurrency, no clock**: all inputs are explicit; the
  caller stores and synchronizes the log.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
