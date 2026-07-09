# Ecosystem Syntax Errors — Genuine AI Code Bugs

> **Purpose.** These are places where the AI-written `ecosystem/` code **genuinely violates
> `docs/AI_CONTEXT.md`** and must be fixed in a later ecosystem pass (NOT compiler work).
> They are the opposite of `COMPILER_GAPS.md`. **Do not fix these yet** — this is the
> catalog for the dedicated ecosystem-cleanup pass, so it can be done consistently after the
> compiler is upgraded (some files are blocked by BOTH a compiler gap and a code bug; fixing
> code first would be wasted until the gap is closed).
>
> Verified with `xiomc --diagnostics=json` and isolated minimal repros. `T001` type errors are
> non-fatal and excluded here; only genuine fatal syntax violations are listed.

---

## E1 — Trailing `;` on the `module` line  (13 files)
- **Wrong:** `module xiom.bench.types;`
- **Right:** `module xiom.bench.types`  (spec L473: module line has no semicolon)
- **Error:** `error[P001]: expected declaration, found ';'` at 1:col
- **Files:**
  - xiom-bench/src/{runner,stats,types}.xi
  - xiom-ffi/src/{buffer,ptr,result}.xi
  - xiom-kafka/src/{admin,consumer,producer,types}.xi
  - xiom-log/src/{format,logger,types}.xi

## E2 — Trailing comma after a **block-form** match arm  (9 files)
- **Wrong:** `Err(e) => { handle(e); },`  (comma after a `{…}` block arm)
- **Right:** `Err(e) => { handle(e); }`  (no separator after block arms; spec L136)
- **Error:** `error[P001]: expected identifier, found ','`
- **NOTE:** AI_CONTEXT.md examples themselves show the wrong form (`None => {},`) — a **doc defect** that seeded this error. See COMPILER_GAPS.md "Documentation defects". Fix the docs too.
- **Files:**
  - xiom-vulkan/examples/{demo_2d,demo_3d,demo_cubes,demo_particles,demo_shapes}.xi
  - xiom-vulkan/tests/test_vulkan.xi
  - xiom-http/src/demo.xi
  - xiom-test/src/test.xi
  - (also verify xiom-net/src/demo.xi, xiom-sqlite/src/demo.xi if not GAP-10)

## E3 — `;` used inside a struct **literal**  (5 files)
- **Wrong:** `SearchResult{ id: idx.ids[i]; distance: dist; }`  (semicolons in a literal)
- **Right:** `SearchResult{ id: idx.ids[i], distance: dist }`  (literals use `,`; only type *definitions* use `;`) (spec L158-159)
- **Error:** `error[P001]: expected identifier, found ';'`
- **Files:**
  - xiom-vector/src/index/hnsw.xi
  - xiom-vector/src/query/search_service.xi
  - xiom-vector/src/storage/vector_store.xi
  - xiom-grpc/src/server.xi
  - xiom-protobuf/src/schema.xi

## E4 — Single-expression match arm terminated with `;` instead of `,`  (2 files)
- **Wrong:** `None => return false;`  (as a single-expression arm)
- **Right:** `None => return false,`  (single-expr arms end with `,`; spec L136)
- **Error:** `error[P001]: expected identifier, found ';'`
- **Files:**
  - xiom-db/src/engine.xi
  - xiom-db/src/index/btree.xi

## E5 — Match arm doing a bare assignment as a single expression  (2 files)
- **Wrong:** `Start => x = outer.x,`  (assignment as single-expr arm)
- **Right:** `Start => { x = outer.x; }`  (wrap the assignment in a block)
- **Error:** `error[P001]: expected identifier, found '='`
- **Files:**
  - xiom-ui/src/layout.xi
  - xiom-ui/src/types.xi

## E6 — `let mut` binding  (1 file)
- **Wrong:** `let mut i = 0;`
- **Right:** `var i = 0;`  (spec: `var` = mutable, `let` = immutable; there is no `let mut`)
- **Error:** `error[P001]: expected '=', found i`
- **Files:** xiom-blas/src/linalg.xi

## E7 — `mut` binding keyword inside a pattern  (1 file)
- **Wrong:** `Ok(mut req) => { … }`
- **Right:** `Ok(req) => { … }` (bind then reassign via `var`, or restructure)
- **Error:** `error[P001]: expected ')', found req`
- **Files:** xiom-http/src/parser.xi

## E8 — `@identifier(...)` intrinsic-call syntax  (invented; not in spec)  (files: url, and elsewhere)
- **Wrong:** `var len: Int = @xiom_str_len(input);`
- **Right:** use the stdlib string API per AI_CONTEXT.md (e.g. `xiom.string` functions). `@` is only valid in `@pre` within contracts.
- **Error:** `error[P001]: expected identifier, found '@'`
- **Files:** xiom-http/src/url.xi (and audit xiom-http/src/parser.xi which also references intrinsics)

## E9 — `&` before a parameter **name** (ref on the name, not the type)  (1 file)
- **Wrong:** `pub fn begin_modal(name: Str, &open: Bool) -> Bool;`
- **Right:** `pub fn begin_modal(name: Str, open: &Bool) -> Bool;`  (ref belongs to the type: `Param = Ident ":" Type`)
- **Error:** `error[P001]: expected identifier, found '&'`
- **Files:** xiom-imgui/imgui.xi

## E10 — Anonymous (untyped) struct literal  (1 file)
- **Wrong:** `return { num_threads: 4; … };`  (no type name; also `;` separators)
- **Right:** `return OnnxConfig{ num_threads: 4, … };`  (name the type; use `,`)
- **Error:** `error[P001]: expected identifier, found '{'`
- **Files:** xiom-onnx/src/types.xi

## E11 — Contract clause terminated with `;`, orphaning the body  (1 file)
- **Wrong:**
  ```
  pub fn f() -> ...
    requires: count > 0;      // stray ';' ends the decl → body '{' orphaned
  { ... }
  ```
- **Right:** `requires: count > 0`  (no trailing `;` on a contract clause; spec contract grammar)
- **Error:** `error[P001]: expected declaration, found '{'`
- **Files:** xiom-crypto/src/random.xi

## E12 — Body-less fn signature MISSING its terminating `;`  (1 file)
- **Wrong:** `pub fn connect(...) requires: !s.is_empty()`  (no `;`, next `pub` seen)
- **Right:** end the body-less decl with `;`, or give it a `{ … }` body.
- **Error:** `error[P001]: expected '{', found pub`
- **Files:** xiom-postgres/postgres.xi

## E13 — Trailing comma in a **function parameter list**  (1 file, borderline)
- **Wrong:** `fn theme(... , radius: Float32, )`  (trailing comma before `)`)
- **Right:** drop the trailing comma. (Spec explicitly allows trailing commas only for enum variants, L293; param-list trailing comma is unspecified and the compiler rejects it.)
- **Error:** `error[P001]: expected identifier, found ')'`
- **Note:** Borderline — could be argued as a compiler ergonomics gap. Listed here as the safe fix.
- **Files:** xiom-ui/src/theme.xi

## E14 — `crypto/demo.xi` `Ok(())` — SEE GAP-12 (compiler)
- This one is a **compiler gap** (unit literal), not an ecosystem bug. Listed here only to note it
  was triaged. Do NOT change the code — fix the compiler (GAP-12).

---

## Summary
| Class | Description | Files |
|-------|-------------|-------|
| E1 | module-line trailing `;` | 13 |
| E2 | block match arm trailing `,` (+ doc defect) | 9 |
| E3 | `;` in struct literal | 5 |
| E4 | single-expr arm `;` not `,` | 2 |
| E5 | match arm bare assignment | 2 |
| E6 | `let mut` | 1 |
| E7 | `mut` in pattern | 1 |
| E8 | `@intrinsic()` syntax | 1-2 |
| E9 | `&name` param | 1 |
| E10 | anonymous struct literal | 1 |
| E11 | contract clause trailing `;` | 1 |
| E12 | body-less fn missing `;` | 1 |
| E13 | param-list trailing comma (borderline) | 1 |

**~38-39 files** have genuine ecosystem syntax errors. Several also carry a compiler-gap
blocker; fix order = **compiler gaps first (COMPILER_GAPS.md), then this list.**

> Reminder: this catalog was produced read-only. No ecosystem `.xi` files were modified.
