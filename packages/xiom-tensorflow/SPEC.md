# SPEC -- xiom.tensorflow

**Package:** `xiom.tensorflow` 0.1.0 -- TensorFlow C API (libtensorflow)
bindings for XIOM. **Modules:** `xiom.tensorflow.types`, `.loader`,
`.tensor`, `.graph`, `.session`, `.ops`. **Stdlib dependency:** `xiom.std`
(ffi, dl, io, os.platform) only.

## 1. Delivery model

The package is a **runtime loader**, not a vendored library:

- Nothing is linked or bundled at build time; the suite compiles and runs
  with the pinned XIOM toolchain alone (no `--link` flags, no C sources).
- `loader.tf_load()` probes the multi-soname candidate list
  (`XIOM_TENSORFLOW_RUNTIME` override, then `tensorflow.dll`,
  `libtensorflow.so`, `libtensorflow.so.2`, `libtensorflow.dylib`), resolves
  every one of the 109 declared entry points by name, negotiates the version
  floor (`TF_MIN_MAJOR = 2`), and returns a `TfLibrary` handle carrying the
  resolved function table + version.
- No candidate loadable -> typed `TF_LOAD_ABSENT` (**SKIP state**); a
  candidate that loads but is not a usable TF 2.x runtime -> typed
  `TF_LOAD_ABI` (first missing symbol is named); a call returning a non-OK
  `TF_Status` -> `TF_CALL_FAILED` with the TF code name and message;
  ABI-inexpressible calls -> `TF_ABI_UNSUPPORTED` (currently only
  `TF_OperationInput` on SysV; see AUDIT section 1).

## 2. API surface (wrapper tiers)

- **loader** -- `tf_load`, `tf_load_named`, `tf_load_candidates`, `tf_probe`,
  `tf_close`, `tf_fn`, `tf_surface_names`/`tf_surface_count`,
  `tf_status_error`/`tf_check`, `tf_own_c_str`, `int_to_str`,
  `tf_parse_major`, the `TF_FN_*` slot constants (0..108), and the ABI
  adapters (`tf_add_input`, `tf_operation_output_type`,
  `tf_operation_input_type`, `tf_operation_input`,
  `tf_graph_get_tensor_num_dims`, `tf_graph_get_tensor_shape`,
  `tf_graph_set_tensor_shape`, `tf_opts_add_input_mapping`).
- **types** -- `TfLibrary`, `TfError`, `TfInfo`, `TfTensorInfo` and the
  struct-wrapped result payloads (`TfStrList`, `TfTensorList`, `TfIntList`,
  `TfF32List`, `TfByteList`), the `TF_LOAD_*`/`TF_CALL_FAILED`/
  `TF_ABI_UNSUPPORTED` kinds, the full `TF_Code` (incl. the
  `TF_UNAUTHENTICATED = 16` quirk), `TF_DataType` (1..34), `TF_AttrType`
  constant sets, `tf_dtype_size`, `tf_dtype_name`, `tf_code_name`.
- **tensor** -- `tf_tensor_alloc`, `tf_tensor_borrow` (aligned-only; AUDIT
  TF-A1), `tf_tensor_delete`, `tf_tensor_type`, `tf_tensor_default_alignment`,
  `tf_tensor_num_dims`, `tf_tensor_dim`, `tf_tensor_byte_size`,
  `tf_tensor_data`, `tf_tensor_element_count`, `tf_tensor_is_aligned`,
  `tf_tensor_set_shape`, `tf_tensor_bitcast`, `tf_tensor_info`,
  `tf_tensor_create_f32`/`_i32`, `tf_tensor_read_f32`/`_i32`, raw
  `tf_f32_store`/`tf_f32_load`/`tf_i32_store`/`tf_i32_load`,
  `tf_shape_count`.
- **graph** -- graph lifecycle + tensor-shape introspection, operation
  construction (network builders + attribute setters), operation
  introspection (names, arities, edges, control edges, attributes),
  GraphDef export/import incl. import options and the results tier.
- **session** -- options (target, ConfigProto), session lifecycle incl.
  `tf_session_load_saved_model`, `tf_session_run` (packed TF_Output /
  TF_Tensor* arrays), partial runs (`tf_session_prun_setup`/`_prun`/
  `tf_prun_delete`), `tf_session_extend`, device enumeration.
- **ops** -- ROADMAP Phase 3 essentials composed on the graph tier:
  `op_placeholder`, `op_const_f32`, `op_const_i32`, `op_add`, `op_matmul`,
  `op_relu`, `op_identity` (each returns the finished `TF_Operation*`;
  outputs are consumed as `(oper, 0)` edges).

## 3. Declared C API surface -- 109/109 coverage

The single source of truth is `loader.tf_surface_names()` (index-aligned with
the `TF_FN_*` constants). Every slot is (a) resolved by name at load and
(b) exercised live by the conformance suite when a runtime is present.
"L" = live evidence in `tests/test_conformance.xi` (run against
libtensorflow 2.18.1, see STATUS.json).

| # | TF C API | wrapper | live evidence (L) |
| --- | --- | --- | --- |
| 0 | TF_Version | `loader.tf_probe` (version captured at load) | probe (2.18.1) |
| 1 | TF_NewStatus | `loader` status protocol | NewStatus non-null |
| 2 | TF_DeleteStatus | `loader.tf_check` / `tf_status_error` | all status paths |
| 3 | TF_SetStatus | tests direct | SetStatus/GetCode roundtrip |
| 4 | TF_GetCode | `loader.tf_check` / `tf_status_error` | typed error paths |
| 5 | TF_Message | `loader.tf_status_error` (via `tf_own_c_str`) | Message roundtrip |
| 6 | TF_NewBufferFromString | `graph.tf_buffer_from_bytes` | import tests |
| 7 | TF_NewBuffer | `graph.tf_graph_to_graph_def`, `session` meta buffer | GraphToGraphDef |
| 8 | TF_DeleteBuffer | `graph.tf_buffer_delete` | import tests |
| 9 | TF_DataTypeSize | tests direct | dtype-size cross-check |
| 10 | TF_NewTensor | `tensor.tf_tensor_borrow` | aligned borrow live |
| 11 | TF_AllocateTensor | `tensor.tf_tensor_alloc` | `[2,3]` f32 live |
| 12 | TF_DeleteTensor | `tensor.tf_tensor_delete` | every tensor test |
| 13 | TF_TensorType | `tensor.tf_tensor_type`/`tf_tensor_info` | AllocateTensor live |
| 14 | TF_SetShape | `tensor.tf_tensor_set_shape` | SetShape keeps `[2,3]` |
| 15 | TF_NumDims | `tensor.tf_tensor_num_dims`/`_info` | AllocateTensor live |
| 16 | TF_Dim | `tensor.tf_tensor_dim`/`_info` | AllocateTensor live |
| 17 | TF_TensorByteSize | `tensor.tf_tensor_byte_size`/`_info` | AllocateTensor live |
| 18 | TF_TensorData | `tensor.tf_tensor_data` (+ typed create/read) | write/read roundtrip |
| 19 | TF_TensorElementCount | `tensor.tf_tensor_element_count`/`_info` | AllocateTensor live |
| 20 | TF_TensorBitcastFrom | `tensor.tf_tensor_bitcast` | f32->i32 `0x3F800000` |
| 21 | TF_TensorIsAligned | `tensor.tf_tensor_is_aligned` | IsAligned live |
| 22 | TF_NewGraph | `graph.tf_graph_new` | graph construction |
| 23 | TF_DeleteGraph | `graph.tf_graph_delete` | every graph test |
| 24 | TF_GraphSetTensorShape | `graph.tf_graph_set_tensor_shape` (adapter) | set `[2]` live |
| 25 | TF_GraphGetTensorNumDims | `graph.tf_graph_tensor_num_dims` (adapter) | `a:0` rank 1 |
| 26 | TF_GraphGetTensorShape | `graph.tf_graph_tensor_shape` (adapter) | `a:0` == `[2]` |
| 27 | TF_GraphOperationByName | `graph.tf_graph_op_by_name` | hit + miss |
| 28 | TF_GraphNextOperation | `graph.tf_graph_next_op`/`tf_graph_op_count` | op walk >= 3 |
| 29 | TF_GraphToGraphDef | `graph.tf_graph_to_graph_def` | serializes live |
| 30 | TF_GraphImportGraphDef | `graph.tf_graph_import_graph_def` | prefix import |
| 31 | TF_GraphImportGraphDefWithResults | `graph.tf_graph_import_graph_def_with_results` | results tier live |
| 32 | TF_GraphImportGraphDefWithReturnOutputs | `graph.tf_graph_import_graph_def_with_return_outputs` | `sum:0` returned |
| 33 | TF_NewImportGraphDefOptions | `graph.tf_import_options_new` | import tests |
| 34 | TF_DeleteImportGraphDefOptions | `graph.tf_import_options_delete` | import tests |
| 35 | TF_ImportGraphDefOptionsSetPrefix | `graph.tf_import_options_set_prefix` | `imp/sum` live |
| 36 | TF_ImportGraphDefOptionsSetDefaultDevice | `graph.tf_import_options_set_default_device` | import tests |
| 37 | TF_ImportGraphDefOptionsSetUniquifyNames | `graph.tf_import_options_set_uniquify_names` | import tests |
| 38 | TF_ImportGraphDefOptionsSetUniquifyPrefix | `graph.tf_import_options_set_uniquify_prefix` | import tests |
| 39 | TF_ImportGraphDefOptionsAddInputMapping | `graph.tf_import_options_add_input_mapping` (adapter) | rewires sum input to ext |
| 40 | TF_ImportGraphDefOptionsAddReturnOutput | `graph.tf_import_options_add_return_output` | returns `sum:0` |
| 41 | TF_ImportGraphDefOptionsAddReturnOperation | `graph.tf_import_options_add_return_operation` | results tier live |
| 42 | TF_ImportGraphDefOptionsNumReturnOutputs | `graph.tf_import_options_num_return_outputs` | count == 1 |
| 43 | TF_ImportGraphDefOptionsNumReturnOperations | `graph.tf_import_options_num_return_operations` | count == 1 |
| 44 | TF_ImportGraphDefResultsReturnOutputs | `graph.tf_import_results_return_outputs` | results tier live |
| 45 | TF_ImportGraphDefResultsReturnOperations | `graph.tf_import_results_return_operations` | name == `sum` |
| 46 | TF_DeleteImportGraphDefResults | `graph.tf_import_results_delete` | results tier live |
| 47 | TF_NewOperation | `graph.tf_op_new` (+ `ops.*` builders) | every ops test |
| 48 | TF_SetDevice | `graph.tf_op_set_device` | `/device:CPU:0` roundtrip |
| 49 | TF_AddInput | `graph.tf_op_add_input` (adapter) | Placeholder Add live |
| 50 | TF_AddInputList | `graph.tf_op_add_input_list` | AddN `[9,12]` |
| 51 | TF_AddControlInput | `graph.tf_op_add_control_input` | AddN control edge |
| 52 | TF_ColocateWith | `graph.tf_op_colocate_with` | AddN live |
| 53 | TF_SetAttrString | `graph.tf_op_set_attr_string` | Conv2D `padding=VALID` |
| 54 | TF_SetAttrInt | `graph.tf_op_set_attr_int` | Unpack `num=3` |
| 55 | TF_SetAttrIntList | `graph.tf_op_set_attr_int_list` | Conv2D `strides` |
| 56 | TF_SetAttrFloat | `graph.tf_op_set_attr_float` | LeakyRelu `alpha=0.5` |
| 57 | TF_SetAttrFloatList | `graph.tf_op_set_attr_float_list` | mismatch -> typed err |
| 58 | TF_SetAttrBool | `graph.tf_op_set_attr_bool` | Conv2D `use_cudnn_on_gpu` |
| 59 | TF_SetAttrType | `graph.tf_op_set_attr_type` | every builder |
| 60 | TF_SetAttrShape | `graph.tf_op_set_attr_shape` | Placeholder `shape` |
| 61 | TF_SetAttrTensor | `graph.tf_op_set_attr_tensor` | Const builders |
| 62 | TF_SetAttrValueProto | `graph.tf_op_set_attr_value_proto` | Neg `T` via bytes |
| 63 | TF_SetAttrPlaceholder | `graph.tf_op_set_attr_placeholder` | placeholder observable |
| 64 | TF_FinishOperation | `graph.tf_op_finish` | every builder |
| 65 | TF_OperationName | `graph.tf_op_name` | `sum`/`ext`/`b` |
| 66 | TF_OperationOpType | `graph.tf_op_type` | `Add` |
| 67 | TF_OperationDevice | `graph.tf_op_device` | device roundtrip |
| 68 | TF_OperationNumOutputs | `graph.tf_op_num_outputs` | sum == 1 |
| 69 | TF_OperationOutputType | `graph.tf_op_output_type` (adapter) | sum == FLOAT |
| 70 | TF_OperationOutputListLength | `graph.tf_op_output_list_length` | Unpack == 3 |
| 71 | TF_OperationNumInputs | `graph.tf_op_num_inputs` | sum == 2 |
| 72 | TF_OperationInputType | `graph.tf_op_input_type` (adapter) | sum input FLOAT |
| 73 | TF_OperationInputListLength | `graph.tf_op_input_list_length` | AddN == 3 |
| 74 | TF_OperationInput | `graph.tf_op_input` (adapter; POSIX typed-unsupported) | producer of sum:0 == a:0 |
| 75 | TF_OperationAllInputs | `graph.tf_op_all_inputs` | producers a/b |
| 76 | TF_OperationNumControlInputs | `graph.tf_op_num_control_inputs` | AddN == 1 |
| 77 | TF_OperationGetControlInputs | `graph.tf_op_control_inputs` | `[a1]` |
| 78 | TF_OperationNumControlOutputs | `graph.tf_op_num_control_outputs` | 0 / 1 |
| 79 | TF_OperationGetControlOutputs | `graph.tf_op_control_outputs` | `[addn]` |
| 80 | TF_OperationGetNumAttrs | `graph.tf_op_num_attrs` | Placeholder >= 2 |
| 81 | TF_OperationGetAttrInt | `graph.tf_op_get_attr_int` | Unpack `num` == 3 |
| 82 | TF_OperationGetAttrFloat | `graph.tf_op_get_attr_float` | LeakyRelu == 0.5 |
| 83 | TF_OperationGetAttrBool | `graph.tf_op_get_attr_bool` | Conv2D == true |
| 84 | TF_OperationGetAttrType | `graph.tf_op_get_attr_type` | `dtype` == FLOAT |
| 85 | TF_OperationGetAttrShape | `graph.tf_op_get_attr_shape` | `shape` == `[2]` |
| 86 | TF_OperationGetAttrValueProto | `graph.tf_op_get_attr_value_proto` | `T` non-empty |
| 87 | TF_OperationToNodeDef | `graph.tf_op_to_node_def` | serializes `sum` |
| 88 | TF_NewSessionOptions | `session.tf_session_options_new` | session tests |
| 89 | TF_SetTarget | `session.tf_session_options_set_target` | `local` accepted |
| 90 | TF_SetConfig | `session.tf_session_options_set_config` | valid ok / malformed typed |
| 91 | TF_DeleteSessionOptions | `session.tf_session_options_delete` | session tests |
| 92 | TF_NewSession | `session.tf_session_new` (+ `new_session` helper) | session live |
| 93 | TF_LoadSessionFromSavedModel | `session.tf_session_load_saved_model` | typed-absent path |
| 94 | TF_CloseSession | `session.tf_session_close` | session tests |
| 95 | TF_DeleteSession | `session.tf_session_delete` | session tests |
| 96 | TF_SessionRun | `session.tf_session_run` | Add `[5,7]`, AddN `[9,12]`, Conv2D, Unpack, Neg, MatMul, Relu |
| 97 | TF_SessionPRunSetup | `session.tf_session_prun_setup` | PRun live |
| 98 | TF_SessionPRun | `session.tf_session_prun` | PRun `[5,7]` |
| 99 | TF_DeletePRunHandle | `session.tf_prun_delete` | PRun live |
| 100 | TF_ExtendSession | `session.tf_session_extend` | session live |
| 101 | TF_SessionListDevices | `session.tf_device_list` | device 0 |
| 102 | TF_DeleteDeviceList | `session.tf_device_list_delete` | device live |
| 103 | TF_DeviceListCount | `session.tf_device_list_count` | >= 1 |
| 104 | TF_DeviceListName | `session.tf_device_list_name` | non-empty |
| 105 | TF_DeviceListType | `session.tf_device_list_type` | == `CPU` |
| 106 | TF_DeviceListMemoryBytes | `session.tf_device_list_memory_bytes` | readable |
| 107 | TF_DeviceListIncarnation | `session.tf_device_list_incarnation` | readable |
| 108 | TF_TensorDefaultAlignment | `tensor.tf_tensor_default_alignment` | borrow pre-flight oracle |

Bound-but-not-wrapped entry points: none. The one intentional exclusion with
substitutes is `TF_GetBuffer` (struct-return ABI; direct field reads instead)
plus the documented exclusions in AUDIT section 5.

## 4. Version negotiation

`TF_Version` supplies the runtime string (e.g. `2.18.1`); `tf_parse_major`
extracts the major; runtimes with major < 2 are rejected as `TF_LOAD_ABI`
before the surface check (1.x lacked several entry points and the 2.x
session semantics this package declares). The full 109-symbol surface check
is the second gate and names the first missing symbol in the error.

## 5. ABI seam

See AUDIT sections 1--3: 16-byte by-value struct call shapes per platform
(Win64 empirical probe), `unsigned char` return masking, struct-return
limits (`TF_OperationInput` POSIX), the `TF_NewTensor` alignment contract
(TF-A1), and the compiler `set`-name finding (TF-B2).

## 6. Test plan and counts

`tests/test_conformance.xi` (single suite, no fixtures required):

- Pure tier (17 tests, always green): constant tables, surface list
  properties, candidate list, version parse, SKIP probe (bogus soname ->
  `TF_LOAD_ABSENT`), ABI probe (`kernel32.dll` / `libc.so.6` ->
  `TF_LOAD_ABI`), 16-byte image pack/read, raw f32/i32 helpers.
- Live tier (57 tests, run when a runtime is present): version + 109/109
  resolution, status trio, dtype sizes, tensor tier (allocate, borrow
  aligned, typed unaligned refusal, bitcast, typed create/read), graph
  construction + introspection + attribute readers, GraphDef export and
  three import tiers (plain/prefix, results, return-outputs, input
  mapping), session options (target, ConfigProto valid + malformed), Run
  (exact FP arithmetic `1.5+3.5=5.0`, `2.5+4.5=7.0`), wrong-shape typed
  error, partial runs, device enumeration, session extend, typed
  SavedModel-absent path, and the ops tier: `Const`/`Add`, `MatMul`
  (`[[1,2],[3,4]]x[[5,6],[7,8]]` exact), `Relu`, `LeakyRelu`, `Neg`,
  `AddN` (control edge), `Unpack` (multi-output), `Conv2D` (string/int-list/
  bool attrs, exact window sums).
- Without a runtime the live tier reports `SKIP` and the suite exits 0 with
  17 passes; with the pinned CPU runtime it exits 0 with 74 passes
  (recorded x2 in STATUS.json).

Build+run: `scripts/port.ps1 -Package xiom.tensorflow` (set
`XIOM_TENSORFLOW_RUNTIME` to the runtime path for the live leg).
