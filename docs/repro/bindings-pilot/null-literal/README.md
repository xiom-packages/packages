# null-literal -- B-23 repro (v0.64.4)

The `null` pointer literal does **not** marshal to 0 when passed as an
argument to a C extern function. Both a direct call argument
(`xs_ptr_val(null)`) and forwarding through an XIOM function parameter
(`forward(null)`) deliver a garbage address. A zero pointer that
ORIGINATED from C (`get_null()` -> `xs_ptr_val(c_null)`) converts
correctly, and re-passing that same value also works.

## Run

```
. scripts\xiom.ps1
$tool = Resolve-XiomToolchain; $env:XIOM_STDLIB = $tool.Stdlib
& $tool.Xiom --run <abs>\probe.xi --c-source <abs>\host.c
```

## Observed (2026-10-12, v0.64.4 release pin, RTX 3070 Ti host)

```
direct=951536580863 via_fn=951536581040 from_c=0 via_var=0
```

`direct`/`via_fn` values vary per run (uninitialized register/stack
bits); `from_c`/`via_var` are exact zero.

## How it surfaced

`xiom.dx12` 0.3.0 built `D3D12_RESOURCE_DESC` and heap-properties
structs in owned slots and called
`ID3D12Device::CreateCommittedResource(..., pOptimizedClearValue, ...)`.
For buffers `pOptimizedClearValue` must be NULL; passing `null` made the
runtime return `E_INVALIDARG` (`hr=0x80070057`) because a garbage
non-null pointer arrived at C. The same call with a bridge-provided
NULL (`xd12_null_ptr()`) succeeds: `hr=0`, `GetDesc` roundtrip
`dim=1 width=256 mips=1`.

## Workaround (shipped in xiom.dx12 0.3.0)

Bridge helper returning C-side NULL (e.g. `xd12_null_ptr()`), used for
all nullable C arguments until the compiler fix ships.

## Classification

Same class as **B-22** (fn-typed PARAM values do not cross to C via
cast-call positions): pointer-shaped argument marshaling at the
extern/cast-call boundary. Filed as **B-23**.
