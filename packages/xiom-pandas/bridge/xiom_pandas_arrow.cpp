// xiom_pandas_arrow.cpp -- REAL Arrow-backed bridge for xiom.pandas (Phase 2).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// C++17, exception-free at the C ABI. Implements the 12 pandas_c_* symbols
// declared in pandas.xi (bridge/REAL-BACKEND-REQUIREMENTS.md sections 1-3)
// on top of Apache Arrow C++. NOT linked by the offline conformance suite:
// port.args.json keeps bridge/pandas_bridge.c as the deterministic stub leg.
// The suite owns only the offline stub; this file is for the evidence-only
// probe tests/probe_real_arrow.xi and for consumer builds.
//
// PIN: Apache Arrow C++ 22.0.0 (tag apache-arrow-22.0.0, commit
// 5aeb5f217f1ba39c428c9b481f393bd37097f69e). The verified local runtime is
// the pyarrow 22.0.0 win_amd64 wheel (MSVC-built; headers + import libraries
// + DLLs in the wheel). Arrow >= 24 requires C++20 headers (std::span), so
// 22.0.0 is the newest C++17-compatible release. ACERO NODE NAMES ARE PINNED
// TO THIS RELEASE: "table_source", "aggregate", "hashjoin" (Arrow 22 spelling;
// the requirements doc's "hash_join"/"hash_group_aggregate" names are the
// newer/older spellings and do not exist here). See SPEC.md for the re-pin
// procedure.
//
// ABI (matches pandas.xi IR): every parameter and return value is i64
// (`long long`). 0 = null/failure, > 0 = live handle. A live handle is the
// address of a bridge-owned C++ object. The argument-validation contract is
// byte-for-byte the stub's (bridge/pandas_bridge.c) for every case pinned by
// tests/test_conformance.xi -- the real bridge only differs by returning live
// handles for valid input.
//
// HANDLE TYPES / OWNERSHIP
//   DataFrame -> PdDataFrame { shared_ptr<arrow::Table> }
//   Series    -> PdSeries    { shared_ptr<arrow::ChunkedArray> }
//   GroupBy   -> PdGroupBy   { input Table + grouped Table + key name }
//   series_to_vec -> malloc'd bridge-owned buffer (numeric/bool); free it with
//                    pandas_c_free. String/binary extraction is OWNER-PENDING
//                    (returns 0; see section 6.4/6.5 notes in SPEC.md).
//   set_column/filter/groupby/join return NEW handles; the input handles stay
//   valid and unchanged. Free DataFrame/Series handles with the additive
//   pandas_c_dataframe_free/pandas_c_series_free; pandas_c_free releases
//   series_to_vec buffers. Those three symbols are implemented here but NOT
//   declared in pandas.xi pending the owner's additive-ABI decision (the
//   declared 12-symbol ABI is unchanged).
//
// OWNER-PENDING ITEMS (section 6, explicitly not ABI-decided here)
//   6.3 series_apply: implemented against the recommended `double(*)(double)`
//       callback; element coercion to double is the documented policy until
//       the owner pins the signature in pandas.xi.
//   6.5 dataframe_filter: `value` remains the declared i64. Numeric columns
//       widen it (int -> float for float32/float64); bool compares != 0.
//       A Float64-bit-pattern entry point is NOT added (additive ABI decision
//       belongs to the owner).
//   6.6 parquet: not implemented; no parquet symbol is added.
//   6.4 free functions: implemented (above) but not declared/wrapped.

#include <arrow/acero/exec_plan.h>
#include <arrow/acero/options.h>
#include <arrow/api.h>
#include <arrow/compute/api.h>
#include <arrow/compute/initialize.h>
#include <arrow/csv/api.h>
#include <arrow/csv/options.h>
#include <arrow/csv/writer.h>
#include <arrow/io/api.h>
#include <arrow/io/file.h>

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <utility>
#include <vector>

namespace {

constexpr std::uint32_t kDfMagic = 0x50444631u;   // "PDF1"
constexpr std::uint32_t kSerMagic = 0x50535231u;  // "PSR1"
constexpr std::uint32_t kGbMagic = 0x50474231u;   // "PGB1"

struct PdDataFrame {
  std::uint32_t magic = kDfMagic;
  std::shared_ptr<arrow::Table> table;
};

struct PdSeries {
  std::uint32_t magic = kSerMagic;
  std::shared_ptr<arrow::ChunkedArray> column;
};

struct PdGroupBy {
  std::uint32_t magic = kGbMagic;
  std::shared_ptr<arrow::Table> input;
  std::shared_ptr<arrow::Table> grouped;
  std::string key;
};

PdDataFrame* as_frame(long long handle) {
  if (handle == 0) return nullptr;
  auto* frame = reinterpret_cast<PdDataFrame*>(static_cast<std::intptr_t>(handle));
  return frame->magic == kDfMagic ? frame : nullptr;
}

PdSeries* as_series(long long handle) {
  if (handle == 0) return nullptr;
  auto* series = reinterpret_cast<PdSeries*>(static_cast<std::intptr_t>(handle));
  return series->magic == kSerMagic ? series : nullptr;
}

PdGroupBy* as_groupby(long long handle) {
  if (handle == 0) return nullptr;
  auto* group = reinterpret_cast<PdGroupBy*>(static_cast<std::intptr_t>(handle));
  return group->magic == kGbMagic ? group : nullptr;
}

long long frame_to_handle(PdDataFrame* frame) {
  return static_cast<long long>(reinterpret_cast<std::intptr_t>(frame));
}

long long series_to_handle(PdSeries* series) {
  return static_cast<long long>(reinterpret_cast<std::intptr_t>(series));
}

long long group_to_handle(PdGroupBy* group) {
  return static_cast<long long>(reinterpret_cast<std::intptr_t>(group));
}

std::shared_ptr<arrow::DataType> dtype_for_code(int64_t code) {
  switch (code) {
    case 0:
      return arrow::int32();
    case 1:
      return arrow::int64();
    case 2:
      return arrow::float32();
    case 3:
      return arrow::float64();
    case 4:
      return arrow::utf8();
    case 5:
      return arrow::boolean();
    default:
      return nullptr;
  }
}

std::shared_ptr<arrow::ChunkedArray> wrap_array(
    std::shared_ptr<arrow::Array> array) {
  return std::make_shared<arrow::ChunkedArray>(std::move(array));
}

long long append_frame(std::shared_ptr<arrow::Table> table) {
  if (table == nullptr) return 0;
  auto* frame = new PdDataFrame();
  frame->table = std::move(table);
  return frame_to_handle(frame);
}

long long append_series(std::shared_ptr<arrow::ChunkedArray> column) {
  if (column == nullptr) return 0;
  auto* series = new PdSeries();
  series->column = std::move(column);
  return series_to_handle(series);
}

template <typename T>
std::shared_ptr<arrow::Scalar> make_scalar(
    const std::shared_ptr<arrow::DataType>& type, T value) {
  auto result = arrow::MakeScalar(type, value);
  return result.ok() ? *result : nullptr;
}

std::shared_ptr<arrow::Scalar> scalar_for_column(
    const std::shared_ptr<arrow::DataType>& type, long long value) {
  switch (type->id()) {
    case arrow::Type::INT8:
      return make_scalar(type, static_cast<int8_t>(value));
    case arrow::Type::INT16:
      return make_scalar(type, static_cast<int16_t>(value));
    case arrow::Type::INT32:
      return make_scalar(type, static_cast<int32_t>(value));
    case arrow::Type::INT64:
      return make_scalar(type, static_cast<int64_t>(value));
    case arrow::Type::UINT8:
      return make_scalar(type, static_cast<uint8_t>(value));
    case arrow::Type::UINT16:
      return make_scalar(type, static_cast<uint16_t>(value));
    case arrow::Type::UINT32:
      return make_scalar(type, static_cast<uint32_t>(value));
    case arrow::Type::UINT64:
      return make_scalar(type, static_cast<uint64_t>(value));
    case arrow::Type::FLOAT:
      return make_scalar(type, static_cast<float>(value));
    case arrow::Type::DOUBLE:
      return make_scalar(type, static_cast<double>(value));
    case arrow::Type::BOOL:
      return make_scalar(type, value != 0);
    default:
      return nullptr;
  }
}

const char* const kCompareFunctions[6] = {"equal",      "not_equal",
                                          "less",       "less_equal",
                                          "greater",    "greater_equal"};

// Arrow 22 splits the compute kernels into arrow_compute.dll; linking alone
// does not load it. arrow::compute::Initialize() forces the DLL in and
// registers the scalar/vector functions ("equal", "greater", "hash_count_all",
// ...). Called once per process, before any compute/Acero plan is built.
void ensure_compute_initialized() {
  static std::once_flag once;
  std::call_once(once, [] {
    auto status = arrow::compute::Initialize();
    (void)status;
  });
}

std::shared_ptr<arrow::ChunkedArray> datum_as_chunked(
    const arrow::Datum& datum) {
  if (datum.is_chunked_array()) return datum.chunked_array();
  if (datum.is_array()) {
    return std::make_shared<arrow::ChunkedArray>(datum.make_array());
  }
  return nullptr;
}

long long make_series_from_array(std::shared_ptr<arrow::Array> array) {
  if (array == nullptr) return 0;
  return append_series(wrap_array(std::move(array)));
}

}  // namespace

// ===========================================================================
// DataFrame lifecycle
// ===========================================================================

extern "C" long long pandas_c_dataframe_new(long long col_names,
                                            long long col_types,
                                            long long num_cols) {
  try {
    if (col_names == 0 || col_types == 0 || num_cols <= 0) return 0;
    if (num_cols > 65536) return 0;
    const auto* names = reinterpret_cast<const char* const*>(
        static_cast<std::intptr_t>(col_names));
    const auto* types =
        reinterpret_cast<const int64_t*>(static_cast<std::intptr_t>(col_types));
    std::vector<std::shared_ptr<arrow::Field>> fields;
    std::vector<std::shared_ptr<arrow::ChunkedArray>> columns;
    fields.reserve(static_cast<std::size_t>(num_cols));
    columns.reserve(static_cast<std::size_t>(num_cols));
    for (long long i = 0; i < num_cols; ++i) {
      auto type = dtype_for_code(types[i]);
      if (type == nullptr) return 0;
      const char* name = names[i] != nullptr ? names[i] : "";
      fields.push_back(arrow::field(name, type, /*nullable=*/true));
      auto empty = arrow::MakeArrayOfNull(type, 0);
      if (!empty.ok()) return 0;
      columns.push_back(wrap_array(*empty));
    }
    auto schema = arrow::schema(std::move(fields));
    return append_frame(arrow::Table::Make(schema, std::move(columns), 0));
  } catch (...) {
    return 0;
  }
}

extern "C" long long pandas_c_dataframe_from_csv(long long path) {
  try {
    if (path == 0) return 0;
    const auto* c_path = reinterpret_cast<const char*>(
        static_cast<std::intptr_t>(path));
    auto input = arrow::io::ReadableFile::Open(std::string(c_path));
    if (!input.ok()) return 0;
    auto read_options = arrow::csv::ReadOptions::Defaults();
    read_options.use_threads = false;
    auto parse_options = arrow::csv::ParseOptions::Defaults();
    auto convert_options = arrow::csv::ConvertOptions::Defaults();
    auto reader = arrow::csv::TableReader::Make(
        arrow::io::IOContext(), *input, read_options, parse_options,
        convert_options);
    if (!reader.ok()) return 0;
    auto table = (*reader)->Read();
    if (!table.ok()) return 0;
    return append_frame(*table);
  } catch (...) {
    return 0;
  }
}

extern "C" long long pandas_c_dataframe_to_csv(long long df, long long path) {
  try {
    PdDataFrame* frame = as_frame(df);
    if (frame == nullptr || path == 0) return 1;
    const auto* c_path = reinterpret_cast<const char*>(
        static_cast<std::intptr_t>(path));
    auto output = arrow::io::FileOutputStream::Open(std::string(c_path));
    if (!output.ok()) return 1;
    auto options = arrow::csv::WriteOptions::Defaults();
    auto status = arrow::csv::WriteCSV(*frame->table, options, output->get());
    return status.ok() ? 0 : 1;
  } catch (...) {
    return 1;
  }
}

// ===========================================================================
// DataFrame access / mutation
// ===========================================================================

extern "C" long long pandas_c_dataframe_get_column(long long df,
                                                   long long col_name) {
  try {
    PdDataFrame* frame = as_frame(df);
    if (frame == nullptr || col_name == 0) return 0;
    const auto* name = reinterpret_cast<const char*>(
        static_cast<std::intptr_t>(col_name));
    auto column = frame->table->GetColumnByName(std::string(name));
    if (column == nullptr) return 0;
    return append_series(column);
  } catch (...) {
    return 0;
  }
}

extern "C" long long pandas_c_dataframe_set_column(long long df,
                                                   long long col_name,
                                                   long long values,
                                                   long long len) {
  try {
    PdDataFrame* frame = as_frame(df);
    if (frame == nullptr || col_name == 0 || values == 0 || len <= 0) return 0;
    const auto* name = reinterpret_cast<const char*>(
        static_cast<std::intptr_t>(col_name));
    const auto* raw =
        reinterpret_cast<const double*>(static_cast<std::intptr_t>(values));
    arrow::DoubleBuilder builder;
    auto status = builder.AppendValues(raw, len);
    if (!status.ok()) return 0;
    auto array = builder.Finish();
    if (!array.ok()) return 0;
    auto column = wrap_array(*array);

    auto schema = frame->table->schema();
    std::vector<std::shared_ptr<arrow::Field>> fields = schema->fields();
    std::vector<std::shared_ptr<arrow::ChunkedArray>> columns =
        frame->table->columns();
    const int index = schema->GetFieldIndex(std::string(name));
    auto field = arrow::field(std::string(name), arrow::float64(), true);
    if (index >= 0) {
      fields[static_cast<std::size_t>(index)] = field;
      columns[static_cast<std::size_t>(index)] = column;
    } else {
      fields.push_back(field);
      columns.push_back(column);
    }
    auto out_schema = arrow::schema(std::move(fields));
    return append_frame(
        arrow::Table::Make(out_schema, std::move(columns)));
  } catch (...) {
    return 0;
  }
}

// ===========================================================================
// DataFrame operations
// ===========================================================================

extern "C" long long pandas_c_dataframe_filter(long long df, long long col_name,
                                               long long op, long long value) {
  try {
    PdDataFrame* frame = as_frame(df);
    if (frame == nullptr || col_name == 0 || op < 0 || op > 5) return 0;
    ensure_compute_initialized();
    const auto* name = reinterpret_cast<const char*>(
        static_cast<std::intptr_t>(col_name));
    auto column = frame->table->GetColumnByName(std::string(name));
    if (column == nullptr) return 0;
    auto scalar = scalar_for_column(column->type(), value);
    if (scalar == nullptr) return 0;
    auto mask = arrow::compute::CallFunction(
        kCompareFunctions[op], {arrow::Datum(column), arrow::Datum(scalar)});
    if (!mask.ok() || !mask->is_arraylike()) return 0;
    std::vector<std::shared_ptr<arrow::ChunkedArray>> columns;
    columns.reserve(static_cast<std::size_t>(frame->table->num_columns()));
    for (int i = 0; i < frame->table->num_columns(); ++i) {
      auto filtered = arrow::compute::Filter(
          arrow::Datum(frame->table->column(i)), *mask);
      if (!filtered.ok()) return 0;
      auto chunked = datum_as_chunked(*filtered);
      if (chunked == nullptr) return 0;
      columns.push_back(std::move(chunked));
    }
    return append_frame(
        arrow::Table::Make(frame->table->schema(), std::move(columns)));
  } catch (...) {
    return 0;
  }
}

extern "C" long long pandas_c_dataframe_groupby(long long df,
                                                long long col_name) {
  try {
    PdDataFrame* frame = as_frame(df);
    if (frame == nullptr || col_name == 0) return 0;
    const auto* name = reinterpret_cast<const char*>(
        static_cast<std::intptr_t>(col_name));
    const std::string key(name);
    if (frame->table->GetColumnByName(key) == nullptr) return 0;
    ensure_compute_initialized();
    namespace acero = arrow::acero;
    acero::AggregateNodeOptions options(
        {arrow::compute::Aggregate("hash_count_all", "count")},
        {arrow::FieldRef(key)});
    acero::Declaration plan = acero::Declaration::Sequence(
        {{"table_source", acero::TableSourceNodeOptions(frame->table)},
         {"aggregate", options}});
    auto grouped = acero::DeclarationToTable(plan, /*use_threads=*/false);
    if (!grouped.ok()) return 0;
    auto* group = new PdGroupBy();
    group->input = frame->table;
    group->grouped = *grouped;
    group->key = key;
    return group_to_handle(group);
  } catch (...) {
    return 0;
  }
}

extern "C" long long pandas_c_dataframe_join(long long left, long long right,
                                             long long on_col,
                                             long long how) {
  try {
    PdDataFrame* left_frame = as_frame(left);
    PdDataFrame* right_frame = as_frame(right);
    if (left_frame == nullptr || right_frame == nullptr || on_col == 0 ||
        how < 0 || how > 3) {
      return 0;
    }
    const auto* name = reinterpret_cast<const char*>(
        static_cast<std::intptr_t>(on_col));
    const std::string key(name);
    if (left_frame->table->GetColumnByName(key) == nullptr ||
        right_frame->table->GetColumnByName(key) == nullptr) {
      return 0;
    }
    ensure_compute_initialized();
    arrow::acero::JoinType join_type = arrow::acero::JoinType::INNER;
    switch (how) {
      case 0:
        join_type = arrow::acero::JoinType::INNER;
        break;
      case 1:
        join_type = arrow::acero::JoinType::LEFT_OUTER;
        break;
      case 2:
        join_type = arrow::acero::JoinType::RIGHT_OUTER;
        break;
      case 3:
        join_type = arrow::acero::JoinType::FULL_OUTER;
        break;
      default:
        return 0;
    }
    arrow::acero::HashJoinNodeOptions options(
        join_type, {arrow::FieldRef(key)}, {arrow::FieldRef(key)},
        arrow::compute::literal(true), "_left", "_right");
    arrow::acero::Declaration left_source{
        "table_source", arrow::acero::TableSourceNodeOptions(left_frame->table)};
    arrow::acero::Declaration right_source{
        "table_source", arrow::acero::TableSourceNodeOptions(right_frame->table)};
    arrow::acero::Declaration join_declaration{
        "hashjoin", {left_source, right_source}, options};
    auto joined =
        arrow::acero::DeclarationToTable(join_declaration, /*use_threads=*/false);
    if (!joined.ok()) return 0;
    return append_frame(*joined);
  } catch (...) {
    return 0;
  }
}

// ===========================================================================
// Series
// ===========================================================================

extern "C" long long pandas_c_series_new(long long dtype, long long values,
                                         long long len) {
  try {
    if (values == 0 || len <= 0 || dtype < 0 || dtype > 5) return 0;
    if (len > 1LL << 40) return 0;
    const auto* raw = reinterpret_cast<const void*>(
        static_cast<std::intptr_t>(values));
    switch (dtype) {
      case 0: {
        arrow::Int32Builder builder;
        auto status = builder.AppendValues(
            static_cast<const int32_t*>(raw), len);
        if (!status.ok()) return 0;
        auto array = builder.Finish();
        if (!array.ok()) return 0;
        return make_series_from_array(*array);
      }
      case 1: {
        arrow::Int64Builder builder;
        auto status = builder.AppendValues(
            static_cast<const int64_t*>(raw), len);
        if (!status.ok()) return 0;
        auto array = builder.Finish();
        if (!array.ok()) return 0;
        return make_series_from_array(*array);
      }
      case 2: {
        arrow::FloatBuilder builder;
        auto status =
            builder.AppendValues(static_cast<const float*>(raw), len);
        if (!status.ok()) return 0;
        auto array = builder.Finish();
        if (!array.ok()) return 0;
        return make_series_from_array(*array);
      }
      case 3: {
        arrow::DoubleBuilder builder;
        auto status =
            builder.AppendValues(static_cast<const double*>(raw), len);
        if (!status.ok()) return 0;
        auto array = builder.Finish();
        if (!array.ok()) return 0;
        return make_series_from_array(*array);
      }
      case 4: {
        const auto* strings = static_cast<const char* const*>(raw);
        arrow::StringBuilder builder;
        for (long long i = 0; i < len; ++i) {
          if (strings[i] == nullptr) {
            auto status = builder.AppendNull();
            if (!status.ok()) return 0;
          } else {
            auto status = builder.Append(strings[i]);
            if (!status.ok()) return 0;
          }
        }
        auto array = builder.Finish();
        if (!array.ok()) return 0;
        return make_series_from_array(*array);
      }
      case 5: {
        const auto* flags = static_cast<const uint8_t*>(raw);
        arrow::BooleanBuilder builder;
        for (long long i = 0; i < len; ++i) {
          auto status = builder.Append(flags[i] != 0);
          if (!status.ok()) return 0;
        }
        auto array = builder.Finish();
        if (!array.ok()) return 0;
        return make_series_from_array(*array);
      }
      default:
        return 0;
    }
  } catch (...) {
    return 0;
  }
}

extern "C" long long pandas_c_series_from_vec(long long dtype,
                                              long long values, long long len) {
  try {
    if (values == 0 || len <= 0 || dtype < 0 || dtype > 5) return 0;
    if (len > 1LL << 40) return 0;
    const auto* raw =
        reinterpret_cast<const double*>(static_cast<std::intptr_t>(values));
    switch (dtype) {
      case 0: {
        arrow::Int32Builder builder;
        for (long long i = 0; i < len; ++i) {
          auto status = builder.Append(static_cast<int32_t>(raw[i]));
          if (!status.ok()) return 0;
        }
        auto array = builder.Finish();
        if (!array.ok()) return 0;
        return make_series_from_array(*array);
      }
      case 1: {
        arrow::Int64Builder builder;
        for (long long i = 0; i < len; ++i) {
          auto status = builder.Append(static_cast<int64_t>(raw[i]));
          if (!status.ok()) return 0;
        }
        auto array = builder.Finish();
        if (!array.ok()) return 0;
        return make_series_from_array(*array);
      }
      case 2: {
        arrow::FloatBuilder builder;
        for (long long i = 0; i < len; ++i) {
          auto status = builder.Append(static_cast<float>(raw[i]));
          if (!status.ok()) return 0;
        }
        auto array = builder.Finish();
        if (!array.ok()) return 0;
        return make_series_from_array(*array);
      }
      case 3: {
        arrow::DoubleBuilder builder;
        auto status = builder.AppendValues(raw, len);
        if (!status.ok()) return 0;
        auto array = builder.Finish();
        if (!array.ok()) return 0;
        return make_series_from_array(*array);
      }
      case 4:
        return 0; /* double -> string coercion is not an owner-pinned policy */
      case 5: {
        arrow::BooleanBuilder builder;
        for (long long i = 0; i < len; ++i) {
          auto status = builder.Append(raw[i] != 0.0);
          if (!status.ok()) return 0;
        }
        auto array = builder.Finish();
        if (!array.ok()) return 0;
        return make_series_from_array(*array);
      }
      default:
        return 0;
    }
  } catch (...) {
    return 0;
  }
}

extern "C" long long pandas_c_series_to_vec(long long series,
                                            long long out_len) {
  try {
    PdSeries* handle = as_series(series);
    if (handle == nullptr || out_len == 0) return 0;
    auto* length_slot =
        reinterpret_cast<int64_t*>(static_cast<std::intptr_t>(out_len));
    const int64_t length = handle->column->length();
    const auto& type = *handle->column->type();
    void* buffer = nullptr;
    switch (type.id()) {
      case arrow::Type::INT32: {
        buffer = std::malloc(static_cast<std::size_t>(length) * sizeof(int32_t));
        if (buffer == nullptr) return 0;
        auto* out = static_cast<int32_t*>(buffer);
        int64_t offset = 0;
        for (const auto& chunk : handle->column->chunks()) {
          const auto* values = chunk->data()->GetValues<int32_t>(1);
          std::memcpy(out + offset, values,
                      static_cast<std::size_t>(chunk->length()) *
                          sizeof(int32_t));
          offset += chunk->length();
        }
        break;
      }
      case arrow::Type::INT64: {
        buffer = std::malloc(static_cast<std::size_t>(length) * sizeof(int64_t));
        if (buffer == nullptr) return 0;
        auto* out = static_cast<int64_t*>(buffer);
        int64_t offset = 0;
        for (const auto& chunk : handle->column->chunks()) {
          const auto* values = chunk->data()->GetValues<int64_t>(1);
          std::memcpy(out + offset, values,
                      static_cast<std::size_t>(chunk->length()) *
                          sizeof(int64_t));
          offset += chunk->length();
        }
        break;
      }
      case arrow::Type::FLOAT: {
        buffer = std::malloc(static_cast<std::size_t>(length) * sizeof(float));
        if (buffer == nullptr) return 0;
        auto* out = static_cast<float*>(buffer);
        int64_t offset = 0;
        for (const auto& chunk : handle->column->chunks()) {
          const auto* values = chunk->data()->GetValues<float>(1);
          std::memcpy(out + offset, values,
                      static_cast<std::size_t>(chunk->length()) * sizeof(float));
          offset += chunk->length();
        }
        break;
      }
      case arrow::Type::DOUBLE: {
        buffer = std::malloc(static_cast<std::size_t>(length) * sizeof(double));
        if (buffer == nullptr) return 0;
        auto* out = static_cast<double*>(buffer);
        int64_t offset = 0;
        for (const auto& chunk : handle->column->chunks()) {
          const auto* values = chunk->data()->GetValues<double>(1);
          std::memcpy(out + offset, values,
                      static_cast<std::size_t>(chunk->length()) *
                          sizeof(double));
          offset += chunk->length();
        }
        break;
      }
      case arrow::Type::BOOL: {
        buffer = std::malloc(static_cast<std::size_t>(length));
        if (buffer == nullptr) return 0;
        auto* out = static_cast<uint8_t*>(buffer);
        int64_t offset = 0;
        for (const auto& chunk : handle->column->chunks()) {
          const auto& bools =
              arrow::internal::checked_cast<const arrow::BooleanArray&>(*chunk);
          for (int64_t i = 0; i < bools.length(); ++i) {
            out[offset + i] = bools.Value(i) ? 1 : 0;
          }
          offset += bools.length();
        }
        break;
      }
      case arrow::Type::STRING:
      case arrow::Type::BINARY:
        return 0; /* owner-pending: string extraction ABI */
      default:
        return 0;
    }
    *length_slot = length;
    return static_cast<long long>(reinterpret_cast<std::intptr_t>(buffer));
  } catch (...) {
    return 0;
  }
}

extern "C" long long pandas_c_series_apply(long long series,
                                           long long func_ptr) {
  using UnaryDouble = double (*)(double);
  try {
    PdSeries* handle = as_series(series);
    if (handle == nullptr || func_ptr == 0) return 0;
    auto fn = reinterpret_cast<UnaryDouble>(static_cast<std::intptr_t>(func_ptr));
    const auto& type = *handle->column->type();
    arrow::DoubleBuilder builder;
    for (const auto& chunk : handle->column->chunks()) {
      for (int64_t i = 0; i < chunk->length(); ++i) {
        if (chunk->IsNull(i)) {
          auto status = builder.AppendNull();
          if (!status.ok()) return 0;
          continue;
        }
        double value = 0.0;
        switch (type.id()) {
          case arrow::Type::INT32:
            value = static_cast<double>(
                arrow::internal::checked_cast<const arrow::Int32Array&>(*chunk)
                    .Value(i));
            break;
          case arrow::Type::INT64:
            value = static_cast<double>(
                arrow::internal::checked_cast<const arrow::Int64Array&>(*chunk)
                    .Value(i));
            break;
          case arrow::Type::FLOAT:
            value = static_cast<double>(
                arrow::internal::checked_cast<const arrow::FloatArray&>(*chunk)
                    .Value(i));
            break;
          case arrow::Type::DOUBLE:
            value =
                arrow::internal::checked_cast<const arrow::DoubleArray&>(*chunk)
                    .Value(i);
            break;
          case arrow::Type::BOOL:
            value = arrow::internal::checked_cast<const arrow::BooleanArray&>(
                        *chunk)
                        .Value(i)
                        ? 1.0
                        : 0.0;
            break;
          default:
            return 0; /* coercion policy for other types is owner-pending */
        }
        auto status = builder.Append(fn(value));
        if (!status.ok()) return 0;
      }
    }
    auto array = builder.Finish();
    if (!array.ok()) return 0;
    return make_series_from_array(*array);
  } catch (...) {
    return 0;
  }
}

// ===========================================================================
// Additive ownership free functions (section 6.4; NOT declared in pandas.xi)
// ===========================================================================

extern "C" long long pandas_c_dataframe_free(long long df) {
  try {
    PdDataFrame* frame = as_frame(df);
    if (frame == nullptr) return 0;
    delete frame;
    return 1;
  } catch (...) {
    return 0;
  }
}

extern "C" long long pandas_c_series_free(long long series) {
  try {
    PdSeries* handle = as_series(series);
    if (handle == nullptr) return 0;
    delete handle;
    return 1;
  } catch (...) {
    return 0;
  }
}

extern "C" long long pandas_c_free(long long ptr) {
  try {
    if (ptr == 0) return 0;
    std::free(reinterpret_cast<void*>(static_cast<std::intptr_t>(ptr)));
    return 1;
  } catch (...) {
    return 0;
  }
}
