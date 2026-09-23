# xiom.flags

> **Status:** `incubating` -- implemented and green, **NOT published yet**.
> **Scope:** one module (`xiom.flags`) for command-line flag parsing: long and
> short flags, inline `--name=value`, spaced `--name value`, boolean presence,
> bare positionals, a `--` terminator, required flags, and environment
> fallback for absent flags.
> **Deps:** `xiom.std` only (stdlib modules `xiom.string`, `xiom.convert`,
> `xiom.os.args`, `xiom.env`).

## API

| Function | Returns | Description |
|---|---|---|
| `flags_new()` | `FlagParser` | Parser with no declared flags. |
| `flags_flag(p, name, short, takes_value, required, env_var, help)` | `Int` | Declare a flag; `""` for unused short/env/help; returns the declaration index. |
| `flags_parse(p, args)` | `Result[Unit, Str]` | Parse an argument vector; last occurrence wins. |
| `flags_parse_process(p)` | `Result[Unit, Str]` | Parse the process arguments (`xiom.os.args.args_raw()`, index 0 skipped). |
| `flags_has(p, name)` | `Bool` | Provided on the command line, or environment fallback set. |
| `flags_value(p, name)` | `Option[Str]` | Explicit value (or `"true"` for booleans), else environment fallback. |
| `flags_int_value(p, name)` | `Result[Int, Str]` | Parsed integer, or `Err("flag not provided: <name>")` / parse error. |
| `flags_positionals(p)` | `Vec[Str]` | Non-flag arguments in order (including after `--`). |
| `flags_help(p)` | `Str` | One line per flag: names, value hint, `(required)`, `[env: VAR]`, help text. |

## Usage

```xi
use xiom.flags;
use xiom.io;

fn main() -> Int {
  var p = flags_new();
  let _ = flags_flag(&mut p, "output", "o", true, false, "APP_OUTPUT", "output file");
  let _ = flags_flag(&mut p, "verbose", "v", false, false, "", "verbose logging");
  let r = flags_parse_process(&mut p);
  match r {
    Ok(_) => {
      if flags_has(&p, "verbose") { io.println("verbose on"); }
      let v = flags_value(&p, "output");
      match v {
        Some(path) => io.println("output: " + path);
        None => io.println("output: <stdout>");
      }
    }
    Err(e) => { io.println("error: " + e); return 2; }
  }
  return 0;
}
```

Accepted forms: `--name` (boolean), `--name=value`, `--name value`,
`-s` (boolean short), `-s value`, `--` terminator, bare positionals.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.flags
```

Expected: 18 `[PASS]` lines, then
`port: PASS (passed=18 failed=0 exit=0)`.

## Limitations

- Short flags are single-character only; combined clusters (`-abc`) and
  attached values (`-ovalue`) are rejected as unknown flags.
- A value-taking flag consumes the next argument even when it starts with
  `-`.
- An inline value on a boolean flag (`--verbose=true`) is accepted and
  ignored; the flag is merely recorded as present.
- On `Err` the parser state is unspecified: only the error is meaningful.
- Duplicate declarations of the same name resolve to the first declaration.
- No subcommand nesting; `flags_positionals()` preserves order so callers can
  dispatch subcommands themselves.
- Environment fallback only reads names declared with `env_var != ""`.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
