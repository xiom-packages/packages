# xiom.macaddr

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** MAC-48 address parsing, formatting and flag helpers; a MAC-48
> address is a non-negative `Int` in the low 48 bits.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at` and
> `xiom.string.builder`). Tests additionally use `xiom.test`, `xiom.io` and
> `xiom.string.compare`.

## What it is

`xiom.macaddr` converts between the textual notations of a 48-bit MAC
address and its integer value, and answers the standard IEEE 802 flag
questions (multicast, locally administered, unicast, broadcast). It is a
small, dependency-free module: free functions only, no structs, no FFI, no
methods.

## API

| Function | Returns | Description |
|---|---|---|
| `mac_parse(s)` | `Result[Int, Str]` | Parse any accepted notation into a 48-bit value; errors start with `mac: `. |
| `mac_format(m)` | `Str` | Lowercase `xx:xx:xx:xx:xx:xx`; bits above bit 47 are masked off. |
| `mac_format_upper(m)` | `Str` | Uppercase `XX:XX:XX:XX:XX:XX`; same masking. |
| `mac_oui(m)` | `Int` | Upper 24 bits (organizationally unique identifier). |
| `mac_nic(m)` | `Int` | Lower 24 bits (NIC-specific part). |
| `mac_is_multicast(m)` | `Bool` | I/G bit: bit 0 of the first octet (bit 40 of the value). |
| `mac_is_local(m)` | `Bool` | U/L bit: bit 1 of the first octet (bit 41 of the value). |
| `mac_is_unicast(m)` | `Bool` | Complement of `mac_is_multicast`. |
| `mac_broadcast()` | `Int` | `0xFFFFFFFFFFFF` (`ff:ff:ff:ff:ff:ff`). |
| `mac_is_broadcast(m)` | `Bool` | True when all 48 low bits are set. |

## Notations

`mac_parse` accepts exactly four notations (hex digits are case-insensitive):

| Notation | Example | Length |
|---|---|---|
| Colon-separated pairs | `aa:bb:cc:dd:ee:ff` | 17 |
| Dash-separated pairs | `AA-BB-CC-DD-EE-FF` | 17 |
| Cisco dotted triplets | `aabb.ccdd.eeff` | 14 |
| Bare hex digits | `AABBCCDDEEFF` | 12 |

Pair separators must be uniform: `aa:bb-cc:dd:ee:ff` is rejected. Any other
length, separator or non-hex byte is an `Err` whose message starts with
`mac: ` (`invalid length`, `invalid separator`, `invalid character`).

## Usage

```xi
use xiom.macaddr;
use xiom.io;

fn main() -> Int {
  let r = mac_parse("AABB.CCDD.EEFF");
  if r.is_ok {
    io.println(mac_format(r.value));        // aa:bb:cc:dd:ee:ff
    io.println(mac_format_upper(r.value));  // AA:BB:CC:DD:EE:FF
    if mac_is_multicast(r.value) {
      io.println("multicast");
    }
  }
  io.println(mac_format(mac_broadcast()));  // ff:ff:ff:ff:ff:ff
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.macaddr
```

Expected tail: 20 `[PASS]` lines, `xiom.macaddr: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- MAC-48 / EUI-48 only: exactly six octets. EUI-64 (eight octets, `xx-xx-...`
  with a variable grouping) is not supported, and `mac_format` always emits
  six colon-separated octets.
- Only the four notations above; whitespace, `0x` prefixes, brackets, mixed
  separators and abbreviated forms are rejected.
- Values above 48 bits are silently masked (`mac_format(1 << 48)` is
  `00:00:00:00:00:00`); no overflow error is reported.
- No random-MAC generation, no vendor/OUI registry lookup, no byte-array or
  `Vec[UInt8]` interchange (the stdlib `xiom.convert.mac` covers those in a
  different namespace).
- Not a full registry-integration package.

See `SPEC.md` for the grammar, bit rules, error catalog and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
