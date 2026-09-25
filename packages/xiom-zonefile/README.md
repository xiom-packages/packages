# xiom.zonefile

> **Status:** `incubating` -- implemented and green on the local harness
> (compiler v0.61.3), NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI, no sockets) DNS zone-file (master file)
> codec for a documented subset: `$ORIGIN`/`$TTL` directives, relative-name
> completion, `@`, parenthesized multi-line records, `;` comments, quoted
> TXT strings, eight record types and a canonical emitter.
> **Deps:** `xiom.std` only. The library module imports `xiom.string`,
> `xiom.string.builder` and `xiom.string.compare`; the tests use `xiom.test`,
> `xiom.io` and `xiom.string.compare`.

## What it is

`xiom.zonefile` turns zone-file text into a flat record document and back.
It is a codec, not a DNS server or a resolver: it does not open sockets and
does not validate the meaning of RDATA. What it does cover is the master-file
structure people actually hand to a name server:

- the `$ORIGIN name` and `$TTL n` directives, tracked while parsing;
- records `[name] [ttl] [class] type rdata`, with an omitted name or TTL
  inherited from the previous record;
- owner names completed against the current origin, `@` meaning the origin,
  and absolute names (trailing dot) preserved verbatim;
- parenthesized records spanning lines, `;` comments to end of line, and
  quoted tokens with `\"` and `\\` escapes;
- the types SOA, NS, A, AAAA, CNAME, MX, TXT and PTR, with RDATA stored as
  whitespace-separated tokens plus a joined-text form for TXT;
- a canonical emitter that writes one record per line, and a byte-stable
  parse -> emit -> parse -> emit round-trip.

Storage is deliberately flat: parallel vectors on one `Zone` value
(`Zone` fields are index-aligned; RDATA tokens live in a shared pool sliced
by start/count), because `Vec[StructType]` is unsupported in this compiler.
See `SPEC.md` for the grammar, the resolution rules, the error catalog and
the exact subset.

## API

| Function | Returns | Description |
|---|---|---|
| `zone_parse(text)` | `Result[Zone, Str]` | Parse a whole zone file. |
| `zone_record_count(z)` | `Int` | Number of records. |
| `zone_name(z, i)` | `Str` | Resolved absolute owner name (`""` out of range). |
| `zone_ttl(z, i)` | `Int` | Effective TTL, `0..4294967295` (`-1` out of range). |
| `zone_class(z, i)` | `Str` | Class, always `"IN"` (`""` out of range). |
| `zone_type(z, i)` | `Str` | Canonical uppercase type (`""` out of range). |
| `zone_rdata_token_count(z, i)` | `Int` | RDATA token count (`0` out of range). |
| `zone_rdata_token(z, i, j)` | `Str` | Token `j` verbatim (`""` out of range). |
| `zone_txt_text(z, i)` | `Str` | TXT tokens joined with single spaces, else `""`. |
| `zone_emit(z)` | `Str` | Canonical one-record-per-line text. |

Errors are `Err("zonefile: ...")` strings; the full catalog is in `SPEC.md`.

## Grammar at a glance

```text
$ORIGIN example.com.
$TTL 300
@   IN SOA ns1.example.com. admin.example.com. ( 2024010101
                                                 3600 600 604800 86400 )
www     A     192.0.2.1
        AAAA  2001:db8::1      ; name and TTL inherited
txt     TXT   "hello world" "quoted \" and \\"
```

- A record line that starts with whitespace inherits the previous owner name;
  an explicit TTL becomes the inherited TTL for the following records until
  the next explicit TTL or `$TTL`.
- `(` and `)` group a record across lines; newlines inside them are
  whitespace. `;` starts a comment (outside quoted strings).
- A quoted token may contain spaces and `;`; inside it `\"` is `"`, `\\` is
  `\`, and any other backslash sequence is kept verbatim.
- RDATA tokens are stored verbatim. Only owner names (and `$ORIGIN` values)
  are completed against the origin; an NS/CNAME/MX/PTR/SOA target inside the
  RDATA is not rewritten.

## Usage

```xi
use xiom.zonefile;
use xiom.io;

let text = "$ORIGIN example.com.\n$TTL 300\nwww A 192.0.2.1\n        A 192.0.2.2\n";
let parsed = zone_parse(text);
match parsed {
  Ok(z) => {
    io.println("records: " + zone_record_count(&z).to_str());
    let i = 0;
    while i < zone_record_count(&z) {
      io.println(zone_name(&z, i) + " " + zone_ttl(&z, i).to_str() + " " + zone_type(&z, i));
      i = i + 1;
    }
    io.println(zone_emit(&z));   // "www.example.com. 300 IN A 192.0.2.1\n..."
  },
  Err(e) => { io.println("bad zone: " + e); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.zonefile
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Documented subset only.** Types outside SOA/NS/A/AAAA/CNAME/MX/TXT/PTR
  and classes other than IN are rejected with `zonefile: bad type`; there is
  no `$INCLUDE`, no `$GENERATE`, no TTL time units (`1h`), no DNSSEC types
  and no class/type registry.
- **No RDATA semantics.** Token counts are enforced, but addresses, names
  and numbers inside RDATA are not parsed or validated.
- **Owner names only are resolved.** NS/CNAME/MX/PTR targets and SOA
  mname/rname stay exactly as written.
- **Directives are not stored.** `Zone` exposes resolved names and effective
  TTLs, not the `$ORIGIN`/`$TTL` history, comments or source line numbers.
- **Canonical emit is not the input.** Names are resolved, TTLs are
  effective, types are uppercased, records are one per line and quoting is
  normalized; emit(parse(x)) is a fixed point, but not byte-identical to x.
- **Strict scanning.** A quote must close on the same line (no
  quoted-string line continuation), and a record must end at a newline or
  EOF (a `)` does not start a new record).
- **Errors are strings, not codes.** All failures are `Err(Str)` with a
  stable `zonefile: ...` text (catalog in `SPEC.md`).

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
