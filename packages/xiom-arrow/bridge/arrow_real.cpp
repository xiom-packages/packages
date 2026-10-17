// arrow_real.cpp -- REAL Apache Arrow backend for xiom.arrow (Phase 2).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe-only translation unit: it is NOT linked by the offline conformance
// suite (port.args.json keeps bridge/arrow_bridge.c as the deterministic stub
// leg). Build it with C++17 against the SAME Apache Arrow C++ build whose
// headers/libraries are used; see SPEC.md "Real backend / ABI gate".
//
// PIN: Apache Arrow C++ 22.0.0 (tag apache-arrow-22.0.0, commit
// 5aeb5f217f1ba39c428c9b481f393bd37097f69e). The verified local runtime is
// the pyarrow 22.0.0 win_amd64 wheel (MSVC-built, headers + import libraries
// + DLLs shipped; SHA256 in PROVENANCE.md). Arrow >= 24 requires C++20
// headers (std::span), so 22.0.0 is the newest C++17-compatible release.
//
// ABI: XIOM `Int` is i64. Every exported symbol below is `long long` in,
// `long long`/`const char*` out, matching src/arrow.xi exactly. No C++
// exception may escape the C ABI: every entry point catches (...) and
// reports 0 (failure) or 1 (success rc).
//
// HANDLE MODEL. A handle (Int) is the address of a bridge-owned `Handle`
// C++ object. Kinds:
//   kField       owns shared_ptr<arrow::Field>       (arrow_schema_create)
//   kSchema      owns shared_ptr<arrow::Schema>      (struct schemas, batch schema)
//   kArray       owns shared_ptr<arrow::Array>       (typed columns)
//   kBatch       owns shared_ptr<arrow::RecordBatch> (record batches)
//   kLegacyArray owns a real CDI `struct ArrowArray` (arrow_array_create)
// A handle stays valid until arrow_array_free/arrow_schema_free (the
// `array_free` symbol covers every ArrowArray-shaped handle, including
// batches). Accessors never transfer ownership.
//
// C DATA INTERFACE HANDOFF (section 5 of the pandas bridge requirements):
//   arrow_record_batch_export(batch, out_schema, out_array)
//     Writes a real (ArrowSchema, ArrowArray) pair into caller-owned 72/80
//     byte slots via arrow::ExportRecordBatch. Zero copy: the structs point
//     at the Arrow buffers and keep the C++ batch's shared_ptr alive through
//     their private_data. Ownership of the two structs passes to the
//     consumer. The XIOM/bridge handle REMAINS valid and independent.
//   arrow_record_batch_import(schema_slot, array_slot)
//     Moves that pair into a new Arrow RecordBatch (arrow::ImportRecordBatch).
//     Import CONSUMES both structs: their release pointers are NULLed (the
//     schema is released even if import fails). The consumer must not call
//     release afterwards.
//   arrow_schema_release(slot) / arrow_array_release(slot)
//     The only correct way for an XIOM caller to give up an exported pair it
//     did NOT import. Returns 1 when this call released it, 0 when the slot
//     was already released (or null). Never call these on a pair already
//     passed to arrow_record_batch_import.
//   Exactly one of {import the pair, release both structs once} must happen;
//   copying the struct bytes without either leaks the producer reference.

#include <arrow/acero/exec_plan.h>
#include <arrow/acero/options.h>
#include <arrow/api.h>
#include <arrow/c/abi.h>
#include <arrow/c/bridge.h>
#include <arrow/c/helpers.h>
#include <arrow/compute/api.h>

#include <cstdint>
#include <cstring>
#include <memory>
#include <new>
#include <string>
#include <vector>

namespace {

enum class Kind : int32_t {
  kField = 1,
  kSchema = 2,
  kArray = 3,
  kBatch = 4,
  kLegacyArray = 5,
};

constexpr std::uint32_t kHandleMagic = 0x58415248u;  // "XARH"

struct Handle {
  std::uint32_t magic = kHandleMagic;
  Kind kind = Kind::kField;
  std::shared_ptr<arrow::Field> field;
  std::shared_ptr<arrow::Schema> schema;
  std::shared_ptr<arrow::Array> array;
  std::shared_ptr<arrow::RecordBatch> batch;
  std::string format;
  std::string name;
  std::vector<const void*> legacy_buffers;
  ArrowArray legacy{};
  bool legacy_released = false;

  ~Handle() {
    if (kind == Kind::kLegacyArray && legacy.release != nullptr) {
      legacy.release(&legacy);
    }
  }
};

Handle* get_handle(long long value) {
  if (value == 0) return nullptr;
  auto* handle = reinterpret_cast<Handle*>(static_cast<std::intptr_t>(value));
  if (handle->magic != kHandleMagic) return nullptr;
  return handle;
}

long long put_handle(Handle* handle) {
  if (handle == nullptr) return 0;
  return static_cast<long long>(reinterpret_cast<std::intptr_t>(handle));
}

void legacy_array_release(ArrowArray* array) {
  if (array == nullptr) return;
  auto* handle = reinterpret_cast<Handle*>(array->private_data);
  if (handle != nullptr && handle->magic == kHandleMagic &&
      handle->kind == Kind::kLegacyArray) {
    handle->legacy_released = true;
  }
  array->release = nullptr;
}

void noop_schema_release(ArrowSchema* schema) {
  if (schema != nullptr) schema->release = nullptr;
}

bool export_field_format(const arrow::Field& field, std::string* format,
                         std::string* name) {
  ArrowSchema out{};
  auto status = arrow::ExportField(field, &out);
  if (!status.ok()) return false;
  if (out.format != nullptr) format->assign(out.format);
  if (out.name != nullptr) name->assign(out.name);
  ArrowSchemaRelease(&out);
  return true;
}

Handle* new_array_handle(std::shared_ptr<arrow::Array> array) {
  auto* handle = new Handle();
  handle->kind = Kind::kArray;
  handle->array = std::move(array);
  return handle;
}

}  // namespace

// ===========================================================================
// Arrow C Data Interface structs (probe helpers)
// ===========================================================================

extern "C" long long xiom_arrow_cdi_layout_check(void) {
  if (sizeof(void*) != 8) return 2;
  if (sizeof(ArrowSchema) != 72) return 1;
  if (sizeof(ArrowArray) != 80) return 1;
  if (offsetof(ArrowArray, buffers) != 40) return 1;
  if (offsetof(ArrowSchema, release) != 56) return 1;
  return 0;
}

extern "C" const char* xiom_arrow_cdi_detail(void) {
  if (sizeof(void*) != 8) return "64-bit layout check skipped: pointer size is not 8";
  if (sizeof(ArrowSchema) == 72 && sizeof(ArrowArray) == 80) {
    return "ArrowSchema=72 ArrowArray=80, field offsets pinned";
  }
  return "ArrowSchema/ArrowArray layout mismatch";
}

extern "C" long long arrow_backend_available(void) { return 1; }

extern "C" long long arrow_backend_version(void) {
  return static_cast<long long>(
      reinterpret_cast<std::intptr_t>(ARROW_VERSION_STRING));
}

// ===========================================================================
// ArrowSchema
// ===========================================================================

extern "C" long long arrow_schema_create(const char* format, const char* name) {
  try {
    if (format == nullptr || format[0] == '\0' || name == nullptr) return 0;
    ArrowSchema source{};
    source.format = format;
    source.name = name;
    source.flags = ARROW_FLAG_NULLABLE;
    source.release = noop_schema_release;
    auto imported = arrow::ImportField(&source);
    if (!imported.ok()) return 0;
    auto* handle = new Handle();
    handle->kind = Kind::kField;
    handle->field = *imported;
    handle->name = name;
    if (!export_field_format(*handle->field, &handle->format, &handle->name)) {
      delete handle;
      return 0;
    }
    return put_handle(handle);
  } catch (...) {
    return 0;
  }
}

extern "C" long long arrow_schema_create_struct(long long names,
                                                long long formats,
                                                long long n_columns) {
  try {
    if (names == 0 || formats == 0 || n_columns <= 0) return 0;
    if (n_columns > 4096) return 0;
    const auto* name_array =
        reinterpret_cast<const char* const*>(static_cast<std::intptr_t>(names));
    const auto* format_array = reinterpret_cast<const char* const*>(
        static_cast<std::intptr_t>(formats));
    const auto count = static_cast<std::size_t>(n_columns);
    std::vector<ArrowSchema> children(count);
    std::vector<ArrowSchema*> child_ptrs(count);
    for (std::size_t i = 0; i < count; ++i) {
      if (format_array[i] == nullptr || format_array[i][0] == '\0') return 0;
      children[i] = ArrowSchema{};
      children[i].format = format_array[i];
      children[i].name = name_array[i];
      children[i].flags = ARROW_FLAG_NULLABLE;
      children[i].release = noop_schema_release;
      child_ptrs[i] = &children[i];
    }
    ArrowSchema root{};
    root.format = "+s";
    root.name = "";
    root.flags = ARROW_FLAG_NULLABLE;
    root.n_children = static_cast<int64_t>(count);
    root.children = child_ptrs.data();
    root.release = noop_schema_release;
    auto imported = arrow::ImportSchema(&root);
    if (!imported.ok()) return 0;
    auto* handle = new Handle();
    handle->kind = Kind::kSchema;
    handle->schema = *imported;
    handle->format = "+s";
    handle->name = "";
    return put_handle(handle);
  } catch (...) {
    return 0;
  }
}

extern "C" void arrow_schema_free(long long schema) {
  try {
    Handle* handle = get_handle(schema);
    if (handle != nullptr) delete handle;
  } catch (...) {
  }
}

extern "C" long long arrow_schema_get_format(long long schema) {
  try {
    Handle* handle = get_handle(schema);
    if (handle == nullptr) return 0;
    if (handle->kind != Kind::kField && handle->kind != Kind::kSchema) return 0;
    return static_cast<long long>(
        reinterpret_cast<std::intptr_t>(handle->format.c_str()));
  } catch (...) {
    return 0;
  }
}

extern "C" long long arrow_schema_get_name(long long schema) {
  try {
    Handle* handle = get_handle(schema);
    if (handle == nullptr) return 0;
    if (handle->kind != Kind::kField && handle->kind != Kind::kSchema) return 0;
    return static_cast<long long>(
        reinterpret_cast<std::intptr_t>(handle->name.c_str()));
  } catch (...) {
    return 0;
  }
}

// ===========================================================================
// ArrowArray -- typed arrays
// ===========================================================================

extern "C" long long arrow_array_from_int64(long long values, long long length) {
  try {
    if (values == 0 || length <= 0) return 0;
    arrow::Int64Builder builder;
    auto status = builder.AppendValues(
        reinterpret_cast<const int64_t*>(static_cast<std::intptr_t>(values)),
        static_cast<int64_t>(length));
    if (!status.ok()) return 0;
    auto array = builder.Finish();
    if (!array.ok()) return 0;
    return put_handle(new_array_handle(*array));
  } catch (...) {
    return 0;
  }
}

extern "C" long long arrow_array_from_float64(long long values,
                                              long long length) {
  try {
    if (values == 0 || length <= 0) return 0;
    arrow::DoubleBuilder builder;
    auto status = builder.AppendValues(
        reinterpret_cast<const double*>(static_cast<std::intptr_t>(values)),
        static_cast<int64_t>(length));
    if (!status.ok()) return 0;
    auto array = builder.Finish();
    if (!array.ok()) return 0;
    return put_handle(new_array_handle(*array));
  } catch (...) {
    return 0;
  }
}

// Legacy CDI-shaped allocation: a real struct ArrowArray with a release
// callback and private_data. No typed data is attached (the typed
// constructors above are the data path); the accessors read the struct
// fields exactly as an external consumer would.
extern "C" long long arrow_array_create(long long length, long long n_buffers) {
  try {
    if (length < 0 || n_buffers < 0 || n_buffers > 3) return 0;
    auto* handle = new Handle();
    handle->kind = Kind::kLegacyArray;
    handle->legacy_buffers.assign(static_cast<std::size_t>(n_buffers), nullptr);
    handle->legacy.length = length;
    handle->legacy.null_count = -1;
    handle->legacy.offset = 0;
    handle->legacy.n_buffers = n_buffers;
    handle->legacy.n_children = 0;
    handle->legacy.buffers = handle->legacy_buffers.data();
    handle->legacy.children = nullptr;
    handle->legacy.dictionary = nullptr;
    handle->legacy.release = legacy_array_release;
    handle->legacy.private_data = handle;
    return put_handle(handle);
  } catch (...) {
    return 0;
  }
}

extern "C" void arrow_array_free(long long arr) {
  try {
    Handle* handle = get_handle(arr);
    if (handle != nullptr) delete handle;
  } catch (...) {
  }
}

extern "C" long long arrow_array_get_length(long long arr) {
  try {
    Handle* handle = get_handle(arr);
    if (handle == nullptr) return 0;
    switch (handle->kind) {
      case Kind::kArray:
        return handle->array->length();
      case Kind::kBatch:
        return handle->batch->num_rows();
      case Kind::kLegacyArray:
        return handle->legacy.length;
      default:
        return 0;
    }
  } catch (...) {
    return 0;
  }
}

extern "C" long long arrow_array_get_null_count(long long arr) {
  try {
    Handle* handle = get_handle(arr);
    if (handle == nullptr) return 0;
    if (handle->kind == Kind::kArray) return handle->array->null_count();
    if (handle->kind == Kind::kLegacyArray) return handle->legacy.null_count;
    return 0;
  } catch (...) {
    return 0;
  }
}

extern "C" long long arrow_array_get_offset(long long arr) {
  try {
    Handle* handle = get_handle(arr);
    if (handle == nullptr) return 0;
    if (handle->kind == Kind::kArray) return handle->array->offset();
    if (handle->kind == Kind::kLegacyArray) return handle->legacy.offset;
    return 0;
  } catch (...) {
    return 0;
  }
}

extern "C" long long arrow_array_get_n_buffers(long long arr) {
  try {
    Handle* handle = get_handle(arr);
    if (handle == nullptr) return 0;
    if (handle->kind == Kind::kArray) {
      return static_cast<long long>(handle->array->data()->buffers.size());
    }
    if (handle->kind == Kind::kLegacyArray) return handle->legacy.n_buffers;
    return 0;
  } catch (...) {
    return 0;
  }
}

extern "C" long long arrow_array_get_buffer(long long arr, long long index) {
  try {
    Handle* handle = get_handle(arr);
    if (handle == nullptr || index < 0) return 0;
    if (handle->kind == Kind::kArray) {
      const auto& buffers = handle->array->data()->buffers;
      if (static_cast<std::size_t>(index) >= buffers.size()) return 0;
      const auto& buffer = buffers[static_cast<std::size_t>(index)];
      if (buffer == nullptr) return 0;
      return static_cast<long long>(buffer->address());
    }
    if (handle->kind == Kind::kLegacyArray) {
      if (index >= handle->legacy.n_buffers) return 0;
      return static_cast<long long>(reinterpret_cast<std::intptr_t>(
          handle->legacy.buffers[index]));
    }
    return 0;
  } catch (...) {
    return 0;
  }
}

extern "C" long long arrow_array_get_n_children(long long arr) {
  try {
    Handle* handle = get_handle(arr);
    if (handle == nullptr) return 0;
    if (handle->kind == Kind::kArray) {
      return static_cast<long long>(
          handle->array->data()->child_data.size());
    }
    if (handle->kind == Kind::kBatch) {
      return handle->batch->num_columns();
    }
    return 0;
  } catch (...) {
    return 0;
  }
}

extern "C" long long arrow_array_get_child(long long arr, long long index) {
  try {
    Handle* handle = get_handle(arr);
    if (handle == nullptr || index < 0) return 0;
    if (handle->kind == Kind::kBatch) {
      if (index >= handle->batch->num_columns()) return 0;
      return put_handle(new_array_handle(handle->batch->column(
          static_cast<int>(index))));
    }
    if (handle->kind == Kind::kArray) {
      const auto& child_data = handle->array->data()->child_data;
      if (static_cast<std::size_t>(index) >= child_data.size()) return 0;
      return put_handle(
          new_array_handle(arrow::MakeArray(child_data[index])));
    }
    return 0;
  } catch (...) {
    return 0;
  }
}

// ===========================================================================
// RecordBatch
// ===========================================================================

extern "C" long long arrow_record_batch_create(long long schema,
                                               long long n_columns,
                                               long long columns) {
  try {
    Handle* schema_handle = get_handle(schema);
    if (schema_handle == nullptr || n_columns < 0 || columns == 0) return 0;
    std::shared_ptr<arrow::Schema> out_schema;
    if (schema_handle->kind == Kind::kField) {
      if (n_columns != 1) return 0;
      out_schema = arrow::schema({schema_handle->field});
    } else if (schema_handle->kind == Kind::kSchema) {
      if (static_cast<std::size_t>(n_columns) !=
          static_cast<std::size_t>(schema_handle->schema->num_fields())) {
        return 0;
      }
      out_schema = schema_handle->schema;
    } else {
      return 0;
    }
    const auto* column_values = reinterpret_cast<const long long*>(
        static_cast<std::intptr_t>(columns));
    std::vector<std::shared_ptr<arrow::Array>> arrays;
    arrays.reserve(static_cast<std::size_t>(n_columns));
    int64_t length = -1;
    for (long long i = 0; i < n_columns; ++i) {
      Handle* column = get_handle(column_values[i]);
      if (column == nullptr || column->kind != Kind::kArray) return 0;
      const auto& field = out_schema->field(static_cast<int>(i));
      if (!column->array->type()->Equals(field->type())) return 0;
      if (length < 0) {
        length = column->array->length();
      } else if (length != column->array->length()) {
        return 0;
      }
      arrays.push_back(column->array);
    }
    auto* handle = new Handle();
    handle->kind = Kind::kBatch;
    handle->batch = arrow::RecordBatch::Make(
        out_schema, length < 0 ? 0 : length, arrays);
    return put_handle(handle);
  } catch (...) {
    return 0;
  }
}

extern "C" long long arrow_record_batch_get_column(long long batch,
                                                   long long index) {
  try {
    Handle* handle = get_handle(batch);
    if (handle == nullptr || handle->kind != Kind::kBatch || index < 0) return 0;
    if (index >= handle->batch->num_columns()) return 0;
    return put_handle(
        new_array_handle(handle->batch->column(static_cast<int>(index))));
  } catch (...) {
    return 0;
  }
}

extern "C" long long arrow_record_batch_get_schema(long long batch) {
  try {
    Handle* handle = get_handle(batch);
    if (handle == nullptr || handle->kind != Kind::kBatch) return 0;
    auto* schema = new Handle();
    schema->kind = Kind::kSchema;
    schema->schema = handle->batch->schema();
    schema->format = "+s";
    schema->name = "";
    return put_handle(schema);
  } catch (...) {
    return 0;
  }
}

// ===========================================================================
// Zero-copy C Data Interface handoff (section 5)
// ===========================================================================

extern "C" long long arrow_record_batch_export(long long batch,
                                               long long out_schema,
                                               long long out_array) {
  try {
    Handle* handle = get_handle(batch);
    if (handle == nullptr || handle->kind != Kind::kBatch || out_schema == 0 ||
        out_array == 0) {
      return 0;
    }
    auto* schema_slot =
        reinterpret_cast<ArrowSchema*>(static_cast<std::intptr_t>(out_schema));
    auto* array_slot =
        reinterpret_cast<ArrowArray*>(static_cast<std::intptr_t>(out_array));
    std::memset(schema_slot, 0, sizeof(ArrowSchema));
    std::memset(array_slot, 0, sizeof(ArrowArray));
    auto status = arrow::ExportRecordBatch(*handle->batch, array_slot,
                                           schema_slot);
    return status.ok() ? 1 : 0;
  } catch (...) {
    return 0;
  }
}

extern "C" long long arrow_record_batch_import(long long schema_slot,
                                               long long array_slot) {
  try {
    if (schema_slot == 0 || array_slot == 0) return 0;
    auto* schema =
        reinterpret_cast<ArrowSchema*>(static_cast<std::intptr_t>(schema_slot));
    auto* array =
        reinterpret_cast<ArrowArray*>(static_cast<std::intptr_t>(array_slot));
    auto imported = arrow::ImportRecordBatch(array, schema);
    if (!imported.ok()) return 0;
    auto* handle = new Handle();
    handle->kind = Kind::kBatch;
    handle->batch = *imported;
    return put_handle(handle);
  } catch (...) {
    return 0;
  }
}

extern "C" long long arrow_schema_release(long long schema_slot) {
  try {
    if (schema_slot == 0) return 0;
    auto* schema =
        reinterpret_cast<ArrowSchema*>(static_cast<std::intptr_t>(schema_slot));
    if (schema->release == nullptr) return 0;
    ArrowSchemaRelease(schema);
    return 1;
  } catch (...) {
    return 0;
  }
}

extern "C" long long arrow_array_release(long long array_slot) {
  try {
    if (array_slot == 0) return 0;
    auto* array =
        reinterpret_cast<ArrowArray*>(static_cast<std::intptr_t>(array_slot));
    if (array->release == nullptr) return 0;
    ArrowArrayRelease(array);
    return 1;
  } catch (...) {
    return 0;
  }
}
