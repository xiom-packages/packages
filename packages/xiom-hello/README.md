# xiom.hello

> **Status:** IMPLEMENTED -- the canonical minimal package.
> **Scope:** one dependency-free module that demonstrates the full XIOM
> package lifecycle: manifest, source, conformance tests, publish, install.
> **Deps:** none (the library imports nothing; tests use `xiom.std` modules).

## What it is

`xiom.hello` is intentionally tiny. It exists so the first real publish to
the XIOM registry exercises the whole pipeline with a package that is small
enough to audit in one sitting:

- a dotted manifest name (`xiom.hello`) and an explicit (empty) `deps` block,
- one module (`src/hello.xi`, `module xiom.hello`),
- conformance tests (`tests/test_hello.xi`, four checks),
- a clean tarball: no build artifacts, no secrets, no generated files.

## API

| Function | Returns | Description |
|---|---|---|
| `greeting()` | `Str` | The canonical greeting text. |
| `greet(name)` | `Str` | `"Hello, <name>!"`; empty name falls back to `greeting()`. |

```xi
use xiom.hello;
io.println(greeting());     // "Hello from xiom.hello!"
io.println(greet("Ada"));   // "Hello, Ada!"
```

## Tests

```
xiom --run tests/test_hello.xi
```

Expected: four `[PASS]` lines, then `xiom.hello: all tests passed`, exit 0.

## Install / publish

```
xiom pkg install xiom.hello@0.1.0     # consumer
xiom pkg publish                      # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
