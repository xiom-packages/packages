# xiom.macaddr -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.macaddr` (`src/macaddr.xi`). Pure XIOM, no FFI.
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`).

## 1. Scope

Ten free functions over a MAC-48 address represented as a non-negative `Int`
in the low 48 bits:

```xi
pub fn mac_parse(s: Str) -> Result[Int, Str]
pub fn mac_format(m: Int) -> Str
pub fn mac_format_upper(m: Int) -> Str
pub fn mac_oui(m: Int) -> Int
pub fn mac_nic(m: Int) -> Int
pub fn mac_is_multicast(m: Int) -> Bool
pub fn mac_is_local(m: Int) -> Bool
pub fn mac_is_unicast(m: Int) -> Bool
pub fn mac_broadcast() -> Int
pub fn mac_is_broadcast(m: Int) -> Bool
```

The module never compares `Str` values and constructs `Ok`/`Err` only in the
leaf helpers `_ok_int`/`_err_int`.

## 2. Non-goals

- EUI-64 or any length other than six octets.
- Byte-vector (`Vec[UInt8]`) interchange, random MAC generation, OUI/vendor
  registry lookup (the stdlib `xiom.convert.mac` covers those separately).
- Whitespace tolerance, `0x` prefixes, bracket notation, abbreviated groups
  (`aabb.ccdd.eeff` is the only dotted form).
- Any error channel for `format`/flag helpers (they are total and mask).
- Any FFI, file I/O or registry integration.

## 3. Grammar

```
address  = pairs | dotted | bare
pairs    = HEX2 ( ":" | "-" ) HEX2 ( same-sep HEX2 ){4}      # 17 chars
dotted   = HEX4 "." HEX4 "." HEX4                            # 14 chars
bare     = HEX12                                             # 12 chars
HEX      = 0-9 | a-f | A-F
HEX2     = HEX HEX
HEX4     = HEX HEX HEX HEX
HEX12    = HEX{12}
```

Decision: the pair separator is decided by the byte at position 2; it must be
`:` or `-`, and every later separator must be the same byte. This makes
`aa:bb-cc:dd:ee:ff` and `aa.bb.cc.dd.ee.ff` (17 bytes) `Err`. In the dotted
form the bytes at positions 4 and 9 must both be `.`; in all forms every other
byte must be a hex digit. Length is checked first: only 12, 14 and 17 are
candidate lengths.

## 4. Value and bit model

A value `m` occupies bits 47..0: octet 0 is `(m >> 40) & 0xFF` and octet 5 is
`m & 0xFF`. All helpers mask with `0xFFFFFFFFFFFF` before use, so bits above
bit 47 never affect the result.

| Property | Rule |
|---|---|
| OUI | `(m & 0xFFFFFFFFFFFF) >> 24` (bits 47..24) |
| NIC | `m & 0xFFFFFF` (bits 23..0) |
| Multicast (I/G) | bit 0 of octet 0 = bit 40: `((m >> 40) & 1) == 1` |
| Local (U/L) | bit 1 of octet 0 = bit 41: `((m >> 41) & 1) == 1` |
| Unicast | `!mac_is_multicast(m)` |
| Broadcast | `(m & 0xFFFFFFFFFFFF) == 0xFFFFFFFFFFFF` |
| Broadcast constant | `mac_broadcast() == 0xFFFFFFFFFFFF` |

Examples: `01:00:5e:00:00:01` is multicast, not local, not unicast;
`02:11:22:33:44:55` is local but unicast; `00:11:22:33:44:55` is neither
multicast nor local, hence unicast; `ff:ff:ff:ff:ff:ff` is multicast,
broadcast and not unicast.

## 5. Formatting and masking

- `mac_format(m)` returns exactly 17 characters: six lowercase hex octets
  joined by `:`. `mac_format_upper(m)` is the same with `A-F`.
- Both mask the input: `mac_format(1 << 48)` is `00:00:00:00:00:00`,
  `mac_format(0xFFAABBCCDDEEFF)` is `aa:bb:cc:dd:ee:ff`, and
  `mac_format(-1)` is `ff:ff:ff:ff:ff:ff`. Masking is documented behavior,
  not an error.
- Output is built in a `Vec[UInt8]` and materialized once with
  `xiom.string.builder.sb_to_str`.

## 6. Error catalog

All `mac_parse` errors are `Err` with a message starting with the literal
prefix `mac: `:

| Message | Trigger |
|---|---|
| `mac: invalid length` | `s.len()` is not 12, 14 or 17 (`""`, `aa:bb`, an 18-char trailing-separator form, ...). |
| `mac: invalid separator` | pair form: byte at position 2 is not `:`/`-`, or a later separator differs; dotted form: byte at 4 or 9 is not `.`. |
| `mac: invalid character` | any non-hex byte at a hex-digit position (positions 4 and 9 in the dotted form are separators, not characters). |

Check order: length, then separator, then characters, left to right.

## 7. Test plan

`tests/test_conformance.xi` (module `macaddr_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All `Str` equality uses
`xiom.string.compare.str_compare`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | colon lowercase | `aa:bb:cc:dd:ee:ff`, `00:11:...`, `01:00:5e:...` |
| t2 | case-insensitive | all-upper and mixed-case pair forms |
| t3 | dash pairs | `aa-bb-cc-dd-ee-ff` and upper |
| t4 | Cisco dotted | `aabb.ccdd.eeff`, `AABB.CCDD.EEFF`, `0011.2233.4455` |
| t5 | bare 12 digits | lower, upper, `001122334455` |
| t6 | cross-notation equality | all four notations parse to `0xAABBCCDDEEFF` |
| t7 | parse -> format | each notation reformats to canonical lowercase |
| t8 | bad lengths | `""`, `aa:bb`, plus 13-, 16- and 18-char candidates are `invalid length` |
| t9 | bad characters | `g`, trailing `g`, dotted `g`, bare `g`, space are `invalid character` |
| t10 | bad separators | mixed `: -`, dots in pair form, `-` at 4/9, `;` are `invalid separator` |
| t11 | format masking | `-1`, `1 << 48`, `0xFFAABBCCDDEEFF`, 49-bit all-ones, high-bit OR |
| t12 | format_upper | uppercase `A-F`, digits unchanged, lowercase counterpart |
| t13 | OUI/NIC split | `0xAABBCC`/`0xDDEEFF`, `0x001122`/`0x334455`, recomposition, masked input |
| t14 | multicast | `01:00:5e:...` true; `00:...`, `02:...`, `0` false; `ff..`, `03..` true |
| t15 | local | `02:...`, `fe:...`, `03:...` true; `00:...`, `01:...`, `0` false |
| t16 | unicast | complement of multicast; broadcast is not unicast |
| t17 | broadcast | constant `0xFFFFFFFFFFFF`; masked 49-bit all-ones true; partial false |
| t18 | zero address | parses in three notations, formats, all flags false except unicast |
| t19 | 48-bit maximum | all four notations parse to `0xFFFFFFFFFFFF`; OUI/NIC all ones |
| t20 | format -> parse -> format | lowercase and uppercase round-trip to the same value |

## 8. Known limitations

- MAC-48 only; no EUI-64.
- Exactly four notations; separators must be uniform.
- Silent masking above bit 47 (documented) rather than an overflow error.
- No random generation, no registry/vendor lookup, no byte-vector API.
- Formatting always yields the full six-octet colon form; no dotted/dash
  output modes.

## 9. Compiler / stdlib notes

Follows the proven v0.61.3 package idioms:

- Free functions only; no methods, no lambdas, no structs, no `Vec[StructType]`,
  no `Vec[fn]` dispatch.
- Every `xiom.string.byte_at` result is widened with `(byte_at(s, i) as Int)
  & 0xFF` before comparison or arithmetic.
- `Ok`/`Err` for `Result[Int, Str]` are constructed only in `_ok_int`/`_err_int`.
- Output bytes use `Vec[UInt8]` literals (`58u8`) and
  `xiom.string.builder.sb_to_str`.
- Tests call each check explicitly and return the failure count from `main`.
