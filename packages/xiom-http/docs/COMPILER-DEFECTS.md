# Known compiler defects (xiom.http)

## v0.64.9: nested enum pattern inside `Result` miscompiles

Matching an enum variant directly inside a `Result` arm:

```xiom
match result {
  Ok(_) => {},
  Err(E.A(v)) => { /* ... */ },
  Err(E.B(v)) => { /* ... */ },
}
```

is lowered incorrectly. Every `Err(...)` arm is guarded by the `Result`
error tag (0) instead of the inner enum discriminant, so the **first** `Err`
arm always matches and its payload is read from the wrong slot (observed as
`0`).

Minimized probe: `docs/probe_match_result_enum_defect.xi` (expected exit 1 on
v0.64.9; the two-level control passes).

**Workaround (shipped in 0.1.10):** match the `Result` first, then the enum:

```xiom
match result {
  Ok(_) => {},
  Err(e) => match e {
    E.A(v) => { /* ... */ },
    E.B(v) => { /* ... */ },
  },
}
```

Affected code in 0.1.10: `http_request_with_options`,
`session_request_with_options`, `http_request_bytes_with_options`, and
`tests/probe_root_module.xi` used the two-level form.

**Status on v0.65.2: FIXED.** The tree now matches
`Err(E.A(v))` / `Err(E.B(v))` directly again (the workaround is retired);
the three functions above were converted back. Keep
`docs/probe_match_result_enum_defect.xi` as the regression witness.
