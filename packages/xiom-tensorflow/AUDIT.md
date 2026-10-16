# AUDIT -- xiom.tensorflow

Safety, ABI, and verification audit for the xiom.tensorflow 0.1.0 delivery
(toolchain pin v0.64.5; live runtime libtensorflow 2.18.1 CPU). Findings are
grouped: verified ABI facts, live-verified TensorFlow behaviors, and
compiler findings. Every claim below has a reproduction in the suite or in
the probes described here.

## 1. ABI seam: TF_Output / TF_Input by value

`TF_Output` / `TF_Input` are 16-byte `{pointer, int32, pad}` C structs that
the C API passes **by value** (TF_AddInput, TF_OperationOutputType,
TF_OperationInputType, TF_OperationInput, TF_GraphGetTensorNumDims,
TF_GraphGetTensorShape, TF_GraphSetTensorShape,
TF_ImportGraphDefOptionsAddInputMapping) and also **returns** by value
(TF_OperationInput). The Windows x64 and SysV x64 ABIs treat such aggregates
differently, so the loader emits a per-platform call shape chosen at runtime
(`tf_abi_windows()`), verified empirically with a clang-built probe DLL
(throwaway, documented here rather than committed):

| Fact | Probe | Result |
| --- | --- | --- |
| Win64 by-value 16-byte arg = caller temp passed by reference | `int probe_add_input_arg(TF_Output o)` called with a 16-byte XIOM buffer `{oper=0,index=41}` through `fn(Int) -> Int32` | returned 42 (PASS) |
| Win64 16-byte struct return = hidden retbuf first arg | `TF_Output probe_make_output(void*, int)` called as `fn(retbuf, oper, index) -> Unit` | `{12345, 7}` round-tripped (PASS) |
| `unsigned char` return must be masked | `unsigned char probe_bool_ret(int)` | reading 8 bytes returned garbage in the high bits; the wrappers read `fn(...) -> Int` and mask `& 0xFF` (suite: TF_TensorIsAligned) |

SysV shape (Linux/macOS): the 16-byte aggregate splits across two integer
registers, so the adapters call `fn(lead..., oper, index, trailer...)`.
**Transferable knowledge:** SysV returns a 16-byte aggregate in RAX:RDX and a
hidden-retbuf shape is not expressible through an XIOM `fn` pointer, so
`TF_OperationInput` reports `TF_ABI_UNSUPPORTED` on POSIX; the portable path
is `TF_OperationAllInputs` (bound, live-verified on Windows). All other
declared wrappers are shape-portable.

## 2. TF-A1 -- TF_NewTensor calls a null deallocator for unaligned buffers

`TF_NewTensor` (oracle: `tensorflow/c/tf_tensor.cc` @pin) takes a *copy path*
when `data` is not aligned to `TF_TensorDefaultAlignment` (64 = 
EIGEN_MAX_ALIGN_BYTES on official x64 builds) and in that path **invokes the
deallocator argument immediately**:

```cc
if (... reinterpret_cast<intptr_t>(data) % std::max(1, EIGEN_MAX_ALIGN_BYTES) != 0) {
  buf = new TF_ManagedBuffer(tensorflow::allocate_tensor("TF_NewTensor", len), ...);
  std::memcpy(buf->data(), data, len);
  deallocator(data, len, deallocator_arg);   // NULL deallocator -> call through 0
}
```

Live observation (probe, 2026-10-17): calling `TF_NewTensor` with an
XIOM-owned (unaligned) buffer and a null deallocator terminated the process
silently with no diagnostic. Mitigation in the package:
`tensor.tf_tensor_borrow` queries `TF_TensorDefaultAlignment` (declared
surface slot `TF_TensorDefaultAlignment`, index 108) and refuses unaligned
addresses with a typed `TF_CALL_FAILED` error before calling TF; the suite
proves the aligned path (aliasing + survival of TF_DeleteTensor) and the
typed refusal for `base + 1`.

**Transferable knowledge:** "pass null deallocator" for borrowed TF tensor
storage is only safe at `TF_TensorDefaultAlignment`-aligned addresses; model
this as an oracle call, not a constant, because the alignment is a build
property.

## 3. TF-B2 -- compiler finding: a local fn-pointer named `set`

A local variable holding a cast fn pointer, named `set`, whose call takes the
form `set(a, b, c)`, is compiled as the builtin `Vec.set` method on the first
argument instead of the indirect call. Reproduced twice (suite probe and a
minimal emitter probe), IR evidence at v0.64.5:

```
%tmp1006 = inttoptr i64 %tmp1007 to i64 (i64, i32, i64)*   ; the cast fn ptr
%tmp1008 = alloca i64 (i64, i32, i64)*
...
%tmp1010 = trunc i64 3 to i32
%tmp1011 = load i8*, i8** %tmp1005
%tmp1013 = ptrtoint i8* %tmp1011 to i64
%tmp1014 = bitcast i64* %tmp1003 to %struct.Vec*          ; <- first arg as Vec receiver
%tmp1015 = sext i32 %tmp1010 to i64
%tmp1016 = call i64 @set_Int(%struct.Vec* %tmp1014, i64 %tmp1015, i64 %tmp1013)
```

Effect observed live: `TF_SetStatus(status, TF_INVALID_ARGUMENT, msg)` never
reached TensorFlow (a fresh TF_OK status stayed OK and TF_Message stayed
empty) while other calls in the same block worked. Workaround applied:
locals for cast fn pointers must not be named after builtin methods
(`set`, and by extension any stdlib method name); the suite calls the local
`set_fn`. **Recommend upstreaming** as a name-resolution defect (local
shadowing should win over method resolution).

## 4. Memory and lifetime rules enforced by the package

- **Statuses**: every wrapper that allocates a TF_Status deletes it on both
  the success and error path (`loader.tf_check` / `loader.tf_status_error`);
  a TF-owned message is copied out before the status dies.
- **Graphs/sessions/options/import-options**: explicit `*_delete` wrappers;
  deletion is safe on 0. `TF_NewSession` requires non-null options in TF 2.x
  (the C API dereferences it); the suite always passes real options.
- **Tensors**: caller owns fetched output tensors (delete with
  `tf_tensor_delete`); `tf_tensor_alloc` gives TF-owned storage;
  `tf_tensor_borrow` wraps caller storage with the TF-A1 alignment contract.
- **Buffers**: `TF_NewBuffer*` results are always deleted
  (`graph.take_buffer` reads data+length then deletes; failure paths delete
  too).
- **Device lists**: copied names/types (`tf_own_c_str`) survive
  `TF_DeleteDeviceList`; the list itself is caller-owned.
- **PRun handles**: returned to the caller as an opaque handle; release with
  `tf_prun_delete`.
- **Strings into TF**: all `const char*` arguments are passed as
  NUL-terminated `Str.c_str()` for the duration of the call only; TF copies
  what it retains (verified by the live tests that read names back).

No silent failures: every fallible path returns `Result[*, TfError]` with a
non-empty message; missing slots are impossible after a successful load
(surface check) and still guarded defensively (`fp == 0` short-circuits).

## 5. Declared-surface exclusions (documented, not bound)

Excluded from the 109-entry declared surface, with reasons:

| Excluded | Reason |
| --- | --- |
| Deprecated TF 1.x session API (`TF_NewDeprecatedSession`, `TF_SessionRun` overloads, etc.) | Superseded by the 2.x session tier; not in the ROADMAP declaration |
| `TF_GetBuffer` | Returns TF_Buffer **by value** (same struct-return ABI seam); replaced by direct field reads of `TF_NewBuffer` results (data@0, length@8), which is exactly the getter's semantics |
| `TF_OperationGetAttrMetadata` | Returns a 32-byte struct by value; the concrete readers (Int/Float/Bool/Type/Shape/ValueProto) cover the values; SysV struct-return not expressible |
| `TF_ImportGraphDefOptionsRemapControlDependency`, `TF_SetPayload*`, `TF_TString_*`, graph function (`TF_GraphCopyFunction` etc.), `TF_TryEvaluateConstant`, `TF_OperationOutputConsumers` | Not needed by the declared graph/session/tensor/ops-essentials surface; graph functions are a separate tier |
| `TF_NewTensor` deallocation/borrowing combos beyond the null-deallocator path | XIOM cannot supply a C deallocator function pointer; ownership model documented in `tensor.xi` (TF_AllocateTensor for TF-owned, aligned borrow otherwise) |

## 6. Residual risks

- **POSIX (Linux/macOS)** is covered by the adapters and the typed
  `TF_ABI_UNSUPPORTED` path for `TF_OperationInput`, but the live leg was
  executed on Windows x64 only (the workstation's runtime is the official
  Windows CPU build). A Linux live run would exercise the same declared
  surface through the SysV branches; no test asserts Linux behavior today.
- The suite's live leg depends on `XIOM_TENSORFLOW_RUNTIME` or PATH sonames;
  CI without a runtime reports SKIP, so live regressions can only be caught
  where a runtime is present (the recorded runs had it present).
- `TF_LoadSessionFromSavedModel` is exercised on the typed-absent path only
  (no exported SavedModel fixture is generated by the suite); loading a real
  SavedModel is deferred to a consumer-side fixture.
