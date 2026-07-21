# Ecosystem Syntax Errors — Genuine AI Code Bugs

> **STATUS UPDATE (syntax-cleanup pass complete for genuine errors).**
> The mechanical/genuine spec-violation fixes below have been **APPLIED** to the ecosystem
> (31 `.xi` files changed, 144/144 balanced separator/path edits — no logic changes). What
> remains blocking those files is now almost entirely **compiler gaps** (see `COMPILER_GAPS.md`),
> chiefly **GAP-11 tail expressions**. Per project decision, spec-valid code is NOT rewritten to
> appease the current compiler — the compiler is upgraded instead.
>
> Scan movement this pass: **OK 94 → 103**, P001 90 → 74. Remaining P001 are dominated by
> GAP-10 (`;` after control block) and GAP-11 (tail expression), both compiler gaps.

> **Purpose.** Places where AI-written `ecosystem/` code **genuinely violates
> `docs/AI_CONTEXT.md`**. Opposite of `COMPILER_GAPS.md`.
> Verified with `xiomc --diagnostics=json`. `T001` type errors are non-fatal and excluded.

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

## E15 — Rust-style `::` path syntax  (27 occurrences)
- **Wrong:** `Vec::new()`, `LogLevel::Trace`, `HashMap::new()`
- **Right:** `Vec[T].new()` (or the correct XIOM constructor), `LogLevel.Trace` (enum variant uses `.`)
- **Error:** varies — `expected ';', found }` / `expected identifier, found ':'`
- **Root cause:** AI emitted Rust path syntax `::`. XIOM uses `.` for member/variant access and `Type[Params].method()` for associated calls.
- **Files (sample):** xiom-bench/src/types.xi, xiom-ffi/src/buffer.xi, xiom-kafka/src/consumer.xi, xiom-log/src/logger.xi (`LogLevel::Trace/Debug/Info/...`), and more — scan `::` across ecosystem.

## E16 — Reserved keyword used as a struct field name  (2 occurrences)
- **Wrong:** `module: Str;` (field named `module`), and literal `module: "";`
- **Right:** rename the field (e.g. `module_name: Str;`).
- **Error:** `error[P001]: expected identifier, found 'module'`
- **Reserved words** (AI_CONTEXT L215-223) cannot be field names: `module type match enum fn use const let var if elif else while for return self result pub is as async await spawn requires ensures invariant true false Some None Ok Err unsafe extern derive interface`.
- **Files:** xiom-log/src/types.xi (`module` field, lines 10 & 57).

## E17 — Deeper `;`-in-struct-literal (uncovered after E1 fixes)  (several)
- Same rule as E3, found in more files once the module-line `;` was removed:
  `BenchConfig { iterations: 1000; warmup: 3; ... }` → use `,`.
- **Files:** xiom-bench/src/types.xi, xiom-ffi/src/buffer.xi, xiom-kafka/src/consumer.xi, xiom-log/src/logger.xi, and others (re-scan after E1).

## NOTE — layered errors
Files often have MULTIPLE genuine errors stacked (the compiler reports only the first).
E.g. the 13 E1 files, after removing the module `;`, revealed E3/E15/E16 and some COMPILER
GAPS (GAP-11 tail expression `{ 0 } else {...}`, GAP-12 unit type `Result[(), E]`). A proper
fix pass must iterate each file: fix genuine error → recompile → fix next → until the file is
green OR fails only on a documented `COMPILER_GAPS.md` item.

---

## Summary
| Class | Description | Files | Status |
|-------|-------------|-------|--------|
| E1 | module-line trailing `;` | 13 | ✅ FIXED |
| E2 | block match arm trailing `,` (+ doc defect) | 9 | ✅ FIXED |
| E3 | `;` in struct literal | 5 | ✅ FIXED |
| E4 | single-expr arm `;` not `,` | 2 | ✅ FIXED |
| E5 | match arm bare assignment | 2 | ✅ FIXED |
| E6 | `let mut` | 1 | ✅ FIXED |
| E7 | `mut` in pattern | 1 | ⏳ pending (xiom-http/src/parser.xi — also has E8) |
| E8 | `@intrinsic()` syntax | 1-2 | ⏳ pending (deferred: semantic fix to stdlib string API) |
| E9 | `&name` param | 1 | ⏳ pending (xiom-imgui/imgui.xi) |
| E10 | anonymous struct literal | 1 | ⏳ pending (xiom-onnx/src/types.xi) |
| E11 | contract clause trailing `;` | 1 | ⏳ pending (xiom-crypto/src/random.xi) |
| E12 | body-less fn missing `;` | 1 | ⏳ pending (xiom-postgres/postgres.xi) |
| E13 | param-list trailing comma (borderline) | 1 | ✅ FIXED |
| E15 | Rust-style `::` paths | 27 | ✅ FIXED |
| E16 | reserved keyword as field name | 2 | ✅ FIXED (`module` → `module_name`) |
| E17 | deeper `;`-in-literal (post-E1) | several | ✅ FIXED |
| missing `=>` on match arm | filter_eval, search_service | 2 | ✅ FIXED |

**FIXED this pass:** E1, E2, E3, E4, E5, E6, E13, E15, E16, E17, missing-arrow.
**Still pending (small, mostly single-file):** E7, E8 (semantic — needs stdlib string API), E9, E10, E11, E12.

These remaining ~6 are low-volume and several are entangled with a compiler gap in the same
file; they are best finished in a short follow-up once the compiler gaps (esp. GAP-11) land.

**~103 files now compile clean.** Most remaining failures are compiler gaps, not ecosystem bugs.
The single highest-impact fix is **GAP-11 (tail expressions)** — see `COMPILER_GAPS.md`; it alone
blocks 14+ otherwise-clean files.

> This catalog and the applied fixes touched ONLY `.xi` files inside `ecosystem/`. No
> spec-valid code was altered (no tail expressions rewritten, no gap workarounds inserted).
