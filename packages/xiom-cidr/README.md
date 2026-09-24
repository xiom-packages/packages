# xiom.cidr

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** IPv4 addresses and CIDR blocks: parse, format, containment and
> range math. Addresses are 32-bit `Int`s.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test`, `xiom.io`
> and `xiom.string.compare`.

## Model

An IPv4 address is a non-negative 32-bit `Int` in host byte order:
`0.0.0.0` is `0`, `1.2.3.4` is `16909060`, `255.255.255.255` is
`4294967295`. A CIDR block is the pair `(network, prefix)` where `network`
has all host bits zero. There is no address struct: the module is deliberately
flat so callers can store addresses in `Int` fields or `Vec[Int]`.

Only the two parsers can fail (`Result`); every other function is total and
infallible. Values outside 0..2^32-1 are masked to their low 32 bits rather
than rejected.

## API

| Function | Returns | Description |
|---|---|---|
| `cidr_ip_parse(s)` | `Result[Int, Str]` | Dotted quad -> 32-bit `Int`. Leading zeros in an octet are rejected (`"0"` is valid, `"01"` is not). |
| `cidr_ip_format(ip)` | `Str` | `"a.b.c.d"`; only the low 32 bits of `ip` are used. |
| `cidr_parse(s)` | `Result[(Int, Int), Str]` | `"a.b.c.d/len"` -> `(network, prefix)`. **Host bits are masked off** (`"192.168.1.77/24"` -> `192.168.1.0/24`); `len` 0..32, canonical decimal (no `/024`). |
| `cidr_format(network, prefix)` | `Str` | `"a.b.c.d/len"` with host bits cleared first; prefix echoed verbatim. |
| `cidr_mask(prefix)` | `Int` | Top `prefix` bits set; `0` for any prefix outside 0..32. |
| `cidr_network(ip, prefix)` | `Int` | `ip & mask`; an out-of-range prefix behaves like `/0` (`0`). |
| `cidr_broadcast(network, prefix)` | `Int` | Highest address in the block; `/32` returns the network; out-of-range behaves like `/0` (`4294967295`). |
| `cidr_contains(network, prefix, ip)` | `Bool` | Inclusive containment (network and broadcast are inside); out-of-range prefix contains everything. |
| `cidr_overlap(a_net, a_prefix, b_net, b_prefix)` | `Bool` | True when the two inclusive ranges intersect (partial, containment either way, or equality). |
| `cidr_host_count(prefix)` | `Int` | `2^(32-prefix)`, exact for the full range: `/0` -> `4294967296`, `/32` -> `1`; out-of-range behaves like `/0`. |
| `cidr_first_host(network, prefix)` | `Int` | `network + 1`; for `/31` and `/32` the network itself. |
| `cidr_last_host(network, prefix)` | `Int` | `broadcast - 1` (network and broadcast are not usable hosts); for `/31` and `/32` the network itself. |

Mask table for the common prefixes (`cidr_mask`):

| prefix | mask (decimal) | dotted | block size |
|---|---|---|---|
| /0 | 0 | 0.0.0.0 | 4294967296 |
| /8 | 4278190080 | 255.0.0.0 | 16777216 |
| /12 | 4293918720 | 255.240.0.0 | 1048576 |
| /16 | 4294901760 | 255.255.0.0 | 65536 |
| /24 | 4294967040 | 255.255.255.0 | 256 |
| /30 | 4294967292 | 255.255.255.252 | 4 |
| /31 | 4294967294 | 255.255.255.254 | 2 |
| /32 | 4294967295 | 255.255.255.255 | 1 |

## Usage

```xi
use xiom.cidr;
use xiom.io;

fn main() -> Int {
  let block = cidr_parse("192.168.1.77/24");
  if block.is_ok {
    let t = block.value;
    io.println(cidr_format(t.0, t.1));        // 192.168.1.0/24
  }
  if cidr_contains(cidr_network(3232235777, 24), 24, 3232235777) {
    io.println("inside");
  }
  io.println(cidr_ip_format(cidr_broadcast(0, 0)));  // 255.255.255.255
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.cidr
```

Expected tail: 22 `[PASS]` lines, `xiom.cidr: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **IPv4 only. There is no IPv6 support** of any kind (no parsing, no
  formatting, no masking, no 128-bit addresses). IPv4-mapped forms such as
  `::ffff:192.168.0.1` are out of scope.
- The parsers accept only canonical dotted quads and `address/len` text: no
  CIDR ranges, no hostnames, no `+`/`-` signs, no whitespace, no leading zeros
  in octets or prefix lengths, no `/len` omitted defaults.
- `cidr_parse` deliberately masks host bits; it never reports the original
  host address. Call `cidr_ip_parse` first when the host part matters.
- `cidr_first_host`/`cidr_last_host` use the classic usable-host convention
  (network and broadcast excluded) with `/31` and `/32` returning the network
  itself (see `SPEC.md` section 5).
- An out-of-range prefix is treated as `/0` by every prefix-taking function
  except `cidr_mask`, which returns `0`. No function panics on bad prefixes.
- No normalization beyond masking, no routing/longest-prefix logic, no
  address arithmetic helpers beyond the functions listed above.

See `SPEC.md` for the model, masking rules, the full error catalog and the
test plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
