# xiom-json AUDIT — Remaining Compiler Gap Issues

**Date:** 2026-07-15
**Status:** 0 type errors, 43 borrow-check errors remain

## Summary

All type errors (140 originally) have been resolved. The remaining errors are all `E001` borrow errors caused by the XIOM compiler's branch-dependent move tracking — the compiler cannot prove that a variable is only consumed in one branch of an `if`/`else`.

## Compiler Gaps

### 1. Branch-Dependent Move Analysis

**Description:** The borrow checker flags a variable as "use of moved value" when it is consumed in one branch of `if`/`else` but not the other. Even when both branches have `return` statements, the compiler treats the variable as potentially moved in both paths.

**Minimal Repro:**
```xiom
fn example(cond: Bool, s: Str) -> Str {
  if cond {
    var t = xiom.string.str_concat(s, " suffix");
    return t;
  } else {
    return s;  // E001: use of moved value 's'
  }
}
```

**Workaround:** Duplicate all code that depends on the variable into each branch, or use separate variable names per branch. This leads to significant code duplication.

**Impact:** Affects `stringify_array_item`, `stringify_object_item`, `stringify_number_body`, and other functions with conditional string building.

### 2. Reassignment After Move (Value Types)

**Description:** The compiler does not support reassigning to a variable after it has been moved, even for value types like `Int`. Pattern `x = x + 1` fails because `x + 1` reads (moves) `x`, then the assignment target is invalid.

**Minimal Repro:**
```xiom
var i: Int = 0;
while i < 10 {
  i = i + 1;  // E001: use of moved value 'i'
}
```

**Workaround:** Use `var x = original + 0` to create a copy without moving, OR use separate loop counters (`var idx` for loop condition, `var i = idx + 0` for body usage). This clutters the code significantly.

**Recommendation:** The compiler should treat `Int`, `Float64`, `Bool`, and `Char` as `Copy` types (trivially copyable bit patterns) — they are 64-bit-or-less primitives with no heap data.

### 3. Immutable Method Resolution from Within Same-Type Methods

**Description:** Methods defined on a type with `fn Type.method()` syntax cannot be called from within other methods of the same type using implicit `self` syntax. The compiler reports "undefined variable" for bare method calls like `advance()`.

**Minimal Repro:**
```xiom
type Parser = { pos: Int; }
fn Parser.advance() { pos = pos + 1; }
fn Parser.parse() -> Int {
  advance();   // T001: undefined variable 'advance'
  return 0;
}
```

**Workaround:** Convert all internal type methods to free functions that take `&mut Type` as an explicit first parameter. Public API functions remain as free functions. This was done for all `JsonParser` methods (renamed to `parser_*`).

**Recommendation:** The compiler should resolve method names from within same-type method bodies, matching the documented behavior of implicit `self`.

## Files Affected

- `ecosystem/xiom-json/src/json.xi` — all internal `JsonParser` methods converted to free functions; Result/Option patterns replaced with `match`; remaining borrow errors in stringify helpers and JSONPath parser

## Workaround Patterns Used

1. `var x = original + 0` — creates an `Int` copy without moving `original`
2. `var x = original + 0.0` — same for `Float64`
3. Separate `if`/`else` branches with duplicated code to avoid branch-dependent move tracking
4. Recursive helpers instead of `while` loops with reassigned counters
