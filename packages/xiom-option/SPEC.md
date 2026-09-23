// XIOM -- xiom.option specification
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

# xiom.option -- Specification

Package: `xiom.option` (folder `packages/xiom-option`)
Version: 0.1.0
Module: `xiom.option` (`src/option.xi`)
Status: incubating -- implemented, conformance-tested locally, not published.

## 1. Scope

Free-function combinators for the built-in `Option[T]` and `Result[T, E]`
forms:

- transform the present side: `map`, `flat_map`, `filter`
- extract values with defaults: `unwrap_or`, `unwrap_or_else`
- fall back to an alternate option: `or_else`
- convert between `Option` and `Result`: `to_result`, `from_result`,
  `result_ok`, `result_err`, `result_to_option`

Two element types are in scope: `Int` and `Str`.

## 2. Non-goals

- No generic/polymorphic entry points (`option_map[T]`): blocked by the
  compiler's generic function-pointer codegen bug. The frozen API is the set
  of concrete specializations below.
- No method syntax (`o.map(f)`): this package ships free functions only.
- No new types: `Option`/`Result` are built-in language forms.
- No error chaining/context wrapping: that is `xiom.std`'s `xiom.error`.
- No `Float64`/`Float32` or collection element variants (`Vec`-typed payloads
  are outside the verified language subset).

## 3. API signatures

All functions are `pub` free functions in `src/option.xi` (`module xiom.option`).

| # | Signature |
|---|---|
| 1 | `option_map_int(o: Option[Int], f: fn(&Int) -> Int) -> Option[Int]` |
| 2 | `option_flat_map_int(o: Option[Int], f: fn(&Int) -> Option[Int]) -> Option[Int]` |
| 3 | `option_filter_int(o: Option[Int], pred: fn(&Int) -> Bool) -> Option[Int]` |
| 4 | `option_unwrap_or_int(o: Option[Int], fallback: Int) -> Int` |
| 5 | `option_unwrap_or_else_int(o: Option[Int], f: fn() -> Int) -> Int` |
| 6 | `option_or_else_int(o: Option[Int], alt: Option[Int]) -> Option[Int]` |
| 7 | `option_to_result_int(o: Option[Int], err: Str) -> Result[Int, Str]` |
| 8 | `option_from_result_int(r: Result[Int, Str]) -> Option[Int]` |
| 9 | `option_map_str(o: Option[Str], f: fn(&Str) -> Str) -> Option[Str]` |
| 10 | `option_unwrap_or_str(o: Option[Str], fallback: Str) -> Str` |
| 11 | `option_to_result_str(o: Option[Str], err: Str) -> Result[Str, Str]` |
| 12 | `result_map_int(r: Result[Int, Str], f: fn(&Int) -> Int) -> Result[Int, Str]` |
| 13 | `result_unwrap_or_int(r: Result[Int, Str], fallback: Int) -> Int` |
| 14 | `result_ok_int(r: Result[Int, Str]) -> Option[Int]` |
| 15 | `result_err_str(r: Result[Int, Str]) -> Option[Str]` |
| 16 | `result_to_option_int(r: Result[Int, Str]) -> Option[Int]` |

Callback arguments must be NAMED top-level functions of exactly these
concrete signatures; inline lambdas and generic signatures are not supported
by compiler v0.61.x codegen.

## 4. Semantics

`Some(v)` / `Ok(v)` denote the present side; `None` / `Err(e)` the absent side.

| Function | Input present | Input absent |
|---|---|---|
| `option_map_int` | `Some(f(&v))` | `None` |
| `option_flat_map_int` | `f(&v)` (flattened) | `None` |
| `option_filter_int` | `Some(v)` if `pred(&v)`, else `None` | `None` |
| `option_unwrap_or_int` | `v` | `fallback` |
| `option_unwrap_or_else_int` | `v` | `f()` |
| `option_or_else_int` | `Some(v)` | `alt` |
| `option_to_result_int` | `Ok(v)` | `Err(err)` |
| `option_from_result_int` | `Ok(v)` -> `Some(v)` | `Err(_)` -> `None` |
| `option_map_str` | `Some(f(&v))` | `None` |
| `option_unwrap_or_str` | `v` | `fallback` |
| `option_to_result_str` | `Ok(v)` | `Err(err)` |
| `result_map_int` | `Ok(f(&v))` | `Err(e)` returned unchanged (message preserved) |
| `result_unwrap_or_int` | `v` | `fallback` |
| `result_ok_int` | `Ok(v)` -> `Some(v)` | `Err(_)` -> `None` |
| `result_err_str` | `Ok(_)` -> `None` | `Err(e)` -> `Some(e)` |
| `result_to_option_int` | `Ok(v)` -> `Some(v)` | `Err(_)` -> `None` |

Purity: every function is pure (no I/O, no allocation beyond what `Str`
construction for `map_str` requires). `unwrap_or_else` calls `f` only on
`None`.

## 5. Test plan

`tests/test_conformance.xi` (`module option_tests`) contains 32 tests, one
named top-level function per test returning `TestResult` via
`assert(cond, "name")`. All callback arguments are named top-level functions
(`double`, `is_even`, `zero`, `shout`, `double_if_even`); `Ok`/`Err` values in
the tests are built through the `make_ok` / `make_err` helpers (see Known
limitations item 5).

| Group | Tests |
|---|---|
| `option_map_int` | Some(3)->Some(6); None->None |
| `option_flat_map_int` | Some(4)->Some(8); Some(5)->None |
| `option_filter_int` | keep Some(4); drop Some(5) |
| `option_unwrap_or_int` | Some(9)->9; None->7 |
| `option_unwrap_or_else_int` | Some(9)->9; None->zero()=0 |
| `option_or_else_int` | Some(1)+alt->Some(1); None+alt->Some(2) |
| `option_to_result_int` | Some(5)->Ok(5); None->Err("missing") |
| `option_from_result_int` | Ok(6)->Some(6); Err("boom")->None |
| `option_map_str` | Some("hi")->Some("hi!"); None->None |
| `option_unwrap_or_str` | Some->value; None->"fallback" |
| `option_to_result_str` | Some("hi")->Ok("hi"); None->Err("nostr") |
| `result_map_int` | Ok(4)->Ok(8); Err("bad") unchanged |
| `result_unwrap_or_int` | Ok(3)->3; Err->12 |
| `result_ok_int` | Ok(8)->Some(8); Err->None |
| `result_err_str` | Err("boom")->Some("boom"); Ok->None |
| `result_to_option_int` | Ok(11)->Some(11); Err->None |

Harness: `& .\scripts\port.ps1 -Package xiom.option` (from the repo root);
expected `port: PASS (passed=32 failed=0 exit=0)`.

## 6. Known limitations

1. **Generic function-pointer codegen (compiler v0.61.x).** Generic
   instantiation of functions taking `fn` parameters is broken, so the API is
   expressed as concrete `Int`/`Str` specializations. This is the same
   constraint documented for `xiom.iter.map` and `xiom.misc.natural`
   (`docs/STDLIB_GENERICS.md` in the compiler repo). Adding `option_map[T]`
   requires that fix; the concrete names are the stable frozen surface.

2. **Named callbacks only.** Inline lambdas passed in function-pointer
   position crash or miscompile; every call site must pass a named top-level
   function. The conformance suite demonstrates the supported pattern.

3. **No `Float64`/`Float32` variants.** `Vec[Float64]`/`Vec[Float32]` are
   unusable (BUG 12); payloads are limited to `Int` and `Str`.

4. **`unwrap_or_else` zero-argument callback.** `fn() -> Int` is verified
   against the shipped compiler by test t10 and is kept; if a future compiler
   regresses this signature, the function is the first candidate for removal
   (documented, not silently dropped).

5. **Direct `Ok`/`Err` construction inside struct-returning functions
   (compiler v0.61.3 issue, found while porting this package).** Emitting
   `Ok(x)` or `Err(x)` directly in a function whose declared return type is a
   struct (e.g. `TestResult`) miscompiles: clang rejects the module with
   `'%tmp8' defined with type '%struct.TestResult' ... but expected
   '%struct.Result'`. Minimal repro:

   ```xi
   fn t() -> TestResult {
     let r: Result[Int, Str] = Ok(6);   // IR temp gets TestResult type
     return assert(true, "x");
   }
   ```

   `option_from_result_int(Ok(6))` (inline constructor argument) fails the same
   way. Workaround used by the suite: construct through helpers that declare
   the `Result` return type (`make_ok` / `make_err` in
   `tests/test_conformance.xi`). `Some`/`None` construction inside
   `TestResult`-returning functions is not affected, nor is `Ok`/`Err`
   construction inside functions that themselves return `Result` (as in
   `src/option.xi`).
