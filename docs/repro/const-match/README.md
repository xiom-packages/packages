<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# `const` match arms never match -- v0.62.3 (minimized)

Found while restoring `xiom.grpc`: `status_to_str` matched an `Int`
against 17 `pub const GRPC_STATUS_*` values and returned `"UNKNOWN"` for
every input (all arms fell through to the wildcard).

## Minimal repro

```xi
const TWO: Int = 2;

fn name(x: Int) -> Str {
  match x {
    TWO => { return "two"; },
    _ => { return "other"; },
  }
}
```

`name(2)` -> **`other`** on v0.62.3 (`probe_const_match.xi`: `two=other`,
`bad=1`, exit 1).

**Guidance:** use numeric/string **literals** (or real enum variants) as
match arms; `==` comparisons against constants work fine. Repo-wide scan:
only `grpc.xi` used const arms (17, now rewritten with literals).

**Update 2026-10-04:** the compiler lane fixed this on main (**m188**,
locked with an e2e fixture). After the next release pin, const-based
match arms are usable again and the `grpc.xi` literals can be restored
to named constants (cosmetic).

Run:

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\const-match\probe_const_match.xi
# expected after the fix: two=two ok bad=0
```
