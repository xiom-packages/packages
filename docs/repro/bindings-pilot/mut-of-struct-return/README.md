# B-21: `&mut` of a var initialized from a struct-returning call

**Found:** 2026-10-11 by the bindings lane during the SDK100 Vulkan full-surface
work (the generated loader originally used `vk_api_set_handles(&mut api, ...)`
right after `let at = vk_api_load(...)` / `var api = at.value`).

**Symptom (compiler v0.64.3 pin):**

```
error: clang failed with exit code 1
stderr: xiominput.ll:796:80: error: use of undefined value '%tmp4'
  %tmp0 = load %struct.mut_struct_param2.Pair, %struct.mut_struct_param2.Pair* %tmp4
```

The address operand of a full-struct load is an undefined SSA temp -- the
`&mut` argument materialized from a struct-returning call never gets a
definition.

**Bisect (same `Pair` struct + `&mut` setter):**

| Initialization of the receiver | Result |
|---|---|
| `var q = Pair{ a: 0, b: 0 };` | GREEN (prints `a=7 b=9`) |
| `var q = make_pair();` (struct-returning fn) | **RED** (IR error, this repro) |
| `var api = result.value;` (Result payload extraction) | **RED** (seen in the loader seam) |

So the trigger is taking `&mut` of a variable whose value came from a
struct-returning call (direct return or Result payload), not `&mut` itself.

**Workaround used by the lane:** construct the struct fully in place
(`vk_api_load_full(soname, inst, dev) -> Result[VkApi, Str]`, no post-hoc
`&mut` mutation). The full-surface loader, suite, and bridge hot paths avoid
`&mut` of payload-derived vars.

**Status:** filed to the compiler lane (`REL-20261011-2107-bindings`); needs a
verdict on the v0.64.4 wave (m261-m274 do not visibly touch this path).
