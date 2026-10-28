# C-ORBIT-14: `let`/`var` binding of a Vec returned through a match silently truncates

> **Status:** FIXED on compiler main `478e06f8b` (2026-10-21); v0.64.8
> predates the fix. Re-run unchanged on the next archive; close when
> `via_let=3` and `via_var_init=3` (the Station workaround can then drop).

Found 2026-10-21 while building the Station ORBITWIRE codec on **v0.64.8**
(Windows exe `ee3ee902...`; the same receiver/scratch family as the
module-level `Vec.pop` no-op, m2057/029595080).

## Minimal repro

`repro.xi`:

```xi
module repro.vec_match_binding

use xiom.io;

fn make3() -> Result[Vec[Int], Int] {
  var v = Vec[Int].new();
  v.push(10);
  v.push(20);
  v.push(30);
  return Ok(v);
}

fn via_let() -> Int {
  let v = match make3() {
    Ok(x) => { x }
    Err(_) => { return -1; }
  };
  return v.len();
}

fn via_var_init() -> Int {
  var v = match make3() {
    Ok(x) => { x }
    Err(_) => { return -1; }
  };
  return v.len();
}

fn via_var() -> Int {
  var v = Vec[Int].new();
  match make3() {
    Ok(x) => { v = x; }
    Err(_) => { return -1; }
  };
  return v.len();
}

fn direct_len() -> Int {
  match make3() {
    Ok(x) => { return x.len(); }
    Err(_) => { return -1; }
  }
}

pub fn main() -> Int {
  io.println("via_let=" + via_let().to_str());
  io.println("via_var_init=" + via_var_init().to_str());
  io.println("via_var=" + via_var().to_str());
  io.println("direct_len=" + direct_len().to_str());
  return 0;
}
```

Observed on v0.64.8 (exit 0):

```
via_let=1
via_var_init=1
via_var=3
direct_len=3
```

Expected: `3` everywhere. A `let` **or** `var` initializer whose value is a
`match` over a `Result[Vec[T], E]` corrupts the Vec length (1 instead of 3);
the payload may also be truncated. The declare-then-assign form
(`via_var`) and the direct match-arm return are correct.

## Impact

Silent data truncation in any consumer that writes:

```xi
let rows = match load_rows() { Ok(r) => { r } Err(e) => { return Err(e); } };
```

or `var rows = match ...`. The Station's `frame_encode` hit this as a 38-byte
header reported as 1 byte (encoded frame 61 -> 24 bytes), which the codec's
own length check did not catch because the corrupted length was used
consistently.

## Workaround used by ORBITDB

Declare an empty `var`, then assign inside the match arm (or return the Vec
directly from the arm) until the compiler fix lands:

```xi
var header = Vec[Int].new();
match wire_header_encode(fields) {
  Ok(h) => { header = h; }
  Err(e) => { return Err(e); }
}
```

## Repro command

```powershell
.\scripts\run.ps1 docs\repro\vec-match-binding\repro.xi
```

WSL: `scripts/run.sh docs/repro/vec-match-binding/repro.xi`.
