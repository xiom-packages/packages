# xiom.option

> **Status:** incubating -- implemented and conformance-tested with the local
> toolchain; NOT published to the registry yet.
> **Scope:** combinators for `Option` and `Result` values -- map, flat-map,
> filter, unwrap, and Option/Result conversions -- as concrete `Int`/`Str`
> specializations.
> **Deps:** `xiom.std` (standard library) only.

## What it is

`xiom.option` is the package home for the frozen Option/Result combinator API.
The compiler's function-pointer codegen currently only supports non-generic
concrete signatures, so the API ships as explicit `Int` and `Str`
specializations (for example `option_map_int` / `option_map_str`) instead of
one generic `map`. Callbacks are always NAMED top-level functions; inline
lambdas are not supported in function-pointer position.

The library module itself is dependency-free at the source level (it uses only
the built-in `Option`/`Result` forms and `match`); `xiom.test` and `xiom.io`
are used by the conformance suite.

## API

| Function | Signature | Description |
|---|---|---|
| `option_map_int` | `(Option[Int], fn(&Int) -> Int) -> Option[Int]` | Apply `f` to `Some`; `None` passes through. |
| `option_flat_map_int` | `(Option[Int], fn(&Int) -> Option[Int]) -> Option[Int]` | Apply `f` and flatten. |
| `option_filter_int` | `(Option[Int], fn(&Int) -> Bool) -> Option[Int]` | Keep `Some(v)` when `pred` holds, else `None`. |
| `option_unwrap_or_int` | `(Option[Int], Int) -> Int` | Value, or fallback on `None`. |
| `option_unwrap_or_else_int` | `(Option[Int], fn() -> Int) -> Int` | Value, or `f()` on `None`. |
| `option_or_else_int` | `(Option[Int], Option[Int]) -> Option[Int]` | `Some` stays; `None` becomes `alt`. |
| `option_to_result_int` | `(Option[Int], Str) -> Result[Int, Str]` | `Some(v)` -> `Ok(v)`; `None` -> `Err(msg)`. |
| `option_from_result_int` | `(Result[Int, Str]) -> Option[Int]` | `Ok(v)` -> `Some(v)`; `Err` -> `None`. |
| `option_map_str` | `(Option[Str], fn(&Str) -> Str) -> Option[Str]` | Apply `f` to `Some`; `None` passes through. |
| `option_unwrap_or_str` | `(Option[Str], Str) -> Str` | Value, or fallback on `None`. |
| `option_to_result_str` | `(Option[Str], Str) -> Result[Str, Str]` | `Some(v)` -> `Ok(v)`; `None` -> `Err(msg)`. |
| `result_map_int` | `(Result[Int, Str], fn(&Int) -> Int) -> Result[Int, Str]` | Apply `f` to `Ok`; `Err` passes through unchanged. |
| `result_unwrap_or_int` | `(Result[Int, Str], Int) -> Int` | `Ok` value, or fallback on `Err`. |
| `result_ok_int` | `(Result[Int, Str]) -> Option[Int]` | `Ok(v)` -> `Some(v)`; `Err` -> `None`. |
| `result_err_str` | `(Result[Int, Str]) -> Option[Str]` | `Err(e)` -> `Some(e)`; `Ok` -> `None`. |
| `result_to_option_int` | `(Result[Int, Str]) -> Option[Int]` | Alias of `result_ok_int`. |

## Usage

```xi
use xiom.io;
use xiom.option;

fn double(x: &Int) -> Int { return *x * 2; }

fn main() -> Int {
  let maybe: Option[Int] = Some(21);
  let doubled = option_map_int(maybe, double);       // Some(42)
  let v = option_unwrap_or_int(doubled, 0);          // 42
  let r = option_to_result_int(doubled, "missing");  // Ok(42)
  if r.is_ok {
    io.println("ok");
  } else {
    io.println("err");
  }
  return v;
}
```

Callbacks must be named top-level functions (`double` above), never inline
lambdas. See `SPEC.md` for the full semantics table.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.option
```

Expected: 32 `[PASS]` lines and `port: PASS (passed=32 failed=0 exit=0)`.
Direct run (toolchain resolved by the repo script):

```
& .\scripts\xiom.ps1 --run tests\test_conformance.xi
```

The suite exits with the number of failed tests (0 = green).

## Limitations

- **Concrete specializations only.** The API ships as `Int`/`Str` variants
  because generic function-pointer codegen is broken in compiler v0.61.x;
  there is no polymorphic `option_map[T]`. See `SPEC.md`.
- **Named callbacks only.** Inline lambdas in function-pointer position are
  rejected/miscompiled; pass a named top-level function.
- **No `Float64`/`Float32` vector variants.** Not applicable to this package,
  but note `Vec[Float64]`/`Vec[Float32]` are unusable (BUG 12).
- **No method syntax.** These are free functions (the language rule for this
  package family); call them as `option_*` / `result_*`.
- **Compiler quirk when constructing `Ok`/`Err` in struct-returning
  functions (v0.61.3).** Building `Ok(x)`/`Err(x)` directly inside a function
  that returns a struct (for example `TestResult` in a test helper)
  miscompiles; route construction through a small helper returning
  `Result[Int, Str]` (see `make_ok`/`make_err` in the conformance suite and
  `SPEC.md`).

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
