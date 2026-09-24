# xiom.crc

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI), bitwise, table-free CRC-8/16/32 with the
> classic Rocksoft / CRC-RevEng parameter model and five named presets.
> **Deps:** `xiom.std` only. The library module imports nothing; the tests
> use `xiom.test`, `xiom.io` and `xiom.string`.

## What it is

`xiom.crc` computes CRC checksums over `Vec[UInt8]` buffers from the
parameter tuple `(width, poly, init, refin, refout, xorout)` and ships the
common named presets with their catalogue check values:

- `crc32_ieee` -- CRC-32/IEEE (zlib, PKZIP, Ethernet);
- `crc32c` -- CRC-32C / Castagnoli (iSCSI, SSE4.2);
- `crc16_ccitt_false` -- CRC-16/CCITT-FALSE (CRC-16/IBM-3740);
- `crc16_arc` -- CRC-16/ARC (CRC-16/IBM, LHA);
- `crc8` -- CRC-8/SMBUS.

The engine is bitwise (8 bit-steps per byte) and table-free: a lookup table
is a performance optimization only, and module-level `[256]` tables are
mis-materialized by the v0.61.3 compiler (see `xiom.compress.gzip`). Every
preset is cross-checked against its published check value ("123456789"), and
`crc_compute` is additionally pinned against the wider CRC catalogue
(KERMIT, XMODEM, MODBUS, RIELLO, GENIBUS, MAXIM-DOW, ROHC, ITU, JAMCRC,
BZIP2, MPEG-2, POSIX). See `SPEC.md` for the formal model.

## API

All functions are free functions in module `xiom.crc`:

| Function | Returns | Description |
|---|---|---|
| `crc_compute(data, width, poly, init, refin, refout, xorout)` | `Int` | Generic CRC; `0` when `width` is not 8, 16 or 32. Value in `[0, 2^width - 1]`. |
| `crc_matches(data, width, poly, init, refin, refout, xorout, expected)` | `Bool` | `crc_compute(...) == expected`; same parameters as `crc_compute`. |
| `crc32_ieee(data)` | `Int` | CRC-32/IEEE. Check `"123456789"` = `0xCBF43926` (3421780262). |
| `crc32c(data)` | `Int` | CRC-32C / Castagnoli. Check = `0xE3069283` (3808858755). |
| `crc16_ccitt_false(data)` | `Int` | CRC-16/CCITT-FALSE. Check = `0x29B1` (10673). |
| `crc16_arc(data)` | `Int` | CRC-16/ARC. Check = `0xBB3D` (47933). |
| `crc8(data)` | `Int` | CRC-8/SMBUS. Check = `0xF4` (244). |

## Parameter model

| Parameter | Meaning | Handling |
|---|---|---|
| `width` | Register width in bits | Exactly 8, 16 or 32; any other value makes `crc_compute` return 0. |
| `poly` | Generator polynomial, **normal (MSB-first) form** | Masked to `width` bits; when `refin` is true the reflected polynomial is derived internally. |
| `init` | Initial register contents, normal form | Masked to `width` bits; reflected internally when `refin` is true. |
| `refin` | Input reflection | `true`: process each byte LSB-first with the reflected polynomial; `false`: MSB-first with `poly`. |
| `refout` | Output reflection | When `refout != refin`, the final register is reflected before `xorout`. |
| `xorout` | Final XOR value | Masked to `width` bits, applied last. |

`poly`, `init` and `xorout` must be non-negative; no error is raised --
out-of-range bits are simply masked away (e.g. `poly = 0x107` with
`width = 8` behaves as `0x07`).

## Usage

```xi
use xiom.crc;
use xiom.io;
use xiom.convert;

var data = Vec[UInt8].new();
data.push(49);   // '1'
data.push(50);   // '2'
data.push(51);   // '3'

io.println(convert.int_to_string(crc8(&data)));              // 192
io.println(convert.int_to_string(crc16_ccitt_false(&data))); // 23502
io.println(convert.int_to_string(crc32_ieee(&data)));        // 2286445522

// Generic form: CRC-16/KERMIT (reflected poly 0x8408 of 0x1021, init 0).
io.println(convert.int_to_string(
  crc_compute(&data, 16, 4129, 0, true, true, 0)));          // 23160
```

(Every value above is a pinned cross-check; see `SPEC.md` for the tables.)

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.crc
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Bitwise, not tabled.** 8 shift/XOR steps per byte: correct and portable,
  but several times slower than a `[256]` lookup-table or slicing-by-N
  implementation. Use it for checksums, not for bulk hashing at wire speed.
- **No lookup tables and no streaming API.** The whole input must be a
  `Vec[UInt8]` in memory; there is no incremental `update/finalize` object
  and no table construction helper.
- **No CRC-64 and no non-standard widths.** Only exactly 8, 16 and 32 bits
  are supported; other widths return 0 (documented, not an error type).
- **Checksum, not cryptography.** CRCs detect accidental corruption; they do
  not authenticate data and are trivially forgeable.
- Parameters must be non-negative; masking silently drops out-of-range bits
  rather than reporting them.
- No FFI, no `extern "C"` blocks, no unsafe code.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
