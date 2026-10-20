// xiom_pandas_arrow.cpp -- REAL Arrow-backed bridge for xiom.pandas (phases 2-4).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// C++17, exception-free at the C ABI. Implements the declared pandas_c_* symbols
// (bridge/REAL-BACKEND-REQUIREMENTS.md sections 1-3 + the owner decisions in
// section 8) on top of Apache Arrow C++. NOT linked by the offline conformance
// suite: port.args.json keeps bridge/pandas_bridge.c as the deterministic stub
// leg. The suite owns only the offline stub; this file is for the evidence-only
// probe tests/probe_real_arrow.xi and for consumer builds.
//
// PIN: Apache Arrow C++ 22.0.0 (tag apache-arrow-22.0.0, commit
// 5aeb5f217f1ba39c428c9b481f393bd37097f69e). The verified local runtime is
// the pyarrow 22.0.0 win_amd64 wheel (MSVC-built; headers + import libraries
// + DLLs in the wheel). Arrow >= 24 requires C++20 headers (std::span), so
// 22.0.0 is the newest C++17-compatible release.
//
// SECTION-8 DECISIONS IMPLEMENTED HERE (owner GO 2026-10-19):
//   1. ACERO IS NOT A BUILD REQUIREMENT. This file includes NO arrow/acero
//      headers and references NO Acero symbol. Group-by uses the release-
//      available compute/exec API (arrow::compute::Grouper from
//      arrow/compute/row/grouper.h); the join is the Acero-free bridge-side
//      fallback (Grouper key ids + arrow::compute::Take gather).
//   2. TableGroupBy: arrow/compute/exec/group_by.h is absent in 22.0.0, so the
//      Grouper-based aggregate-in-the-bridge fallback is used (count per group,
//      key column preserved, output "count" column is Int64).
//   3. series_apply: double (*)(double), Float64-only. Every stored value must
//      be f64; no element coercion is performed; a non-Float64 series or a
//      null element returns 0 (fail closed). NA/NaN policies are explicitly
//      OUT OF SCOPE (NaN values are passed through to the callback unchanged).
//   4. Ownership: pandas_c_dataframe_free / pandas_c_series_free /
//      pandas_c_free(series_to_vec buffer) -- additive, declared in pandas.xi.
//   5. dataframe_filter_f64 (owner-pinned symbol name, no pandas_c_ prefix)
//      compares an IEEE-754 f64 bit pattern carried as an Int64; the existing
//      Int entry point is unchanged.
//   6. Parquet: parquet::arrow::OpenFile + FileReader::ReadTable and
//      parquet::arrow::WriteTable from the pinned Arrow 22.0.0 Parquet
//      component (Thrift/zstd/snappy are transitive deps of that component).
//      No separate parquet stack. When the Parquet headers are absent the
//      entry points are compiled as backend-unavailable stubs (see
//      XIOM_PANDAS_HAVE_PARQUET below) so the bridge still builds.
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
//                    pandas_c_free. String/binary extraction returns 0.
//   set_column/filter/filter_f64/groupby/join/parquet-read return NEW handles;
//   the input handles stay valid and unchanged. Free DataFrame/Series handles
//   with pandas_c_dataframe_free/pandas_c_series_free.

#include <arrow/api.h>
#include <arrow/array/concatenate.h>
#include <arrow/compute/api.h>
#include <arrow/compute/exec.h>
#include <arrow/compute/initialize.h>
#include <arrow/compute/row/grouper.h>
#include <arrow/csv/api.h>
#include <arrow/csv/options.h>
#include <arrow/csv/writer.h>
#include <arrow/io/api.h>
#include <arrow/io/file.h>

// Parquet is an optional Arrow component. __has_include keeps the bridge
// buildable on an Arrow install without the Parquet headers; the entry points
// then report "backend unavailable" (0 / 1) instead of failing to compile.
#if !defined(XIOM_PANDAS_NO_PARQUET) && defined(__has_include)
#  if __has_include(<parquet/arrow/reader.h>) && \
      __has_include(<parquet/arrow/writer.h>)
#    define XIOM_PANDAS_HAVE_PARQUET 1
#  endif
#endif
#ifndef XIOM_PANDAS_HAVE_PARQUET
#  define XIOM_PANDAS_HAVE_PARQUET 0
#endif

#if XIOM_PANDAS_HAVE_PARQUET
#  include <parquet/arrow/reader.h>
#  include <parquet/arrow/writer.h>
#  include <parquet/properties.h>
#endif

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <unordered_set>
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

// f64 value entry: the scalar is built from an IEEE-754 double. Float64 is the
// intended column type; Float32 narrows and integer/bool columns follow the
// same promotion rules as the Int entry point (documented in SPEC.md).
std::shared_ptr<arrow::Scalar> scalar_for_column_f64(
    const std::shared_ptr<arrow::DataType>& type, double value) {
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
      return make_scalar(type, value);
    case arrow::Type::BOOL:
      return make_scalar(type, value != 0.0);
    default:
      return nullptr;
  }
}

const char* const kCompareFunctions[6] = {"equal",      "not_equal",
                                          "less",       "less_equal",
                                          "greater",    "greater_equal"};

// Arrow 22 splits the compute kernels into arrow_compute.dll; linking alone
// does not load it. arrow::compute::Initialize() forces the DLL in and
// registers the scalar/vector functions ("equal", "greater", ...). Called once
// per process, before any compute call.
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

// Flatten a chunked column to one Array. A single chunk is returned zero-copy;
// multiple chunks are concatenated (COPY); zero chunks become a typed empty
// array. This is the only copy in the group-by/join key path.
std::shared_ptr<arrow::Array> flatten_column(
    const std::shared_ptr<arrow::ChunkedArray>& column) {
  if (column == nullptr) return nullptr;
  if (column->num_chunks() == 0) {
    auto empty = arrow::MakeArrayOfNull(column->type(), 0);
    return empty.ok() ? *empty : nullptr;
  }
  if (column->num_chunks() == 1) return column->chunk(0);
  auto concatenated =
      arrow::Concatenate(column->chunks(), arrow::default_memory_pool());
  return concatenated.ok() ? *concatenated : nullptr;
}

bool make_span(const std::shared_ptr<arrow::Array>& array,
               arrow::compute::ExecSpan* out) {
  if (array == nullptr || out == nullptr) return false;
  arrow::compute::ExecValue value;
  value.SetArray(*array->data());
  *out = arrow::compute::ExecSpan({value}, array->length());
  return true;
}

std::shared_ptr<arrow::UInt32Array> ids_from_datum(
    const arrow::Datum& datum) {
  auto array = flatten_column(datum_as_chunked(datum));
  if (array == nullptr || array->type_id() != arrow::Type::UINT32) {
    return nullptr;
  }
  return std::static_pointer_cast<arrow::UInt32Array>(array);
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
    if (!status.ok()) return 1;
    auto close_status = (*output)->Close();
    return close_status.ok() ? 0 : 1;
  } catch (...) {
    return 1;
  }
}

// ===========================================================================
// Parquet I/O (section-8 decision 6) -- Arrow Parquet component only
// ===========================================================================

extern "C" long long pandas_c_dataframe_from_parquet(long long path) {
  try {
    if (path == 0) return 0;
#if XIOM_PANDAS_HAVE_PARQUET
    const auto* c_path = reinterpret_cast<const char*>(
        static_cast<std::intptr_t>(path));
    auto input = arrow::io::ReadableFile::Open(std::string(c_path));
    if (!input.ok()) return 0;
    auto reader =
        parquet::arrow::OpenFile(*input, arrow::default_memory_pool());
    if (!reader.ok()) return 0;
    std::shared_ptr<arrow::Table> table;
    auto status = (*reader)->ReadTable(&table);
    if (!status.ok() || table == nullptr) return 0;
    return append_frame(std::move(table));
#else
    (void)path;
    return 0;  // Parquet component absent: backend unavailable
#endif
  } catch (...) {
    return 0;
  }
}

extern "C" long long pandas_c_dataframe_to_parquet(long long df, long long path) {
  try {
    PdDataFrame* frame = as_frame(df);
    if (frame == nullptr || path == 0) return 1;
#if XIOM_PANDAS_HAVE_PARQUET
    const auto* c_path = reinterpret_cast<const char*>(
        static_cast<std::intptr_t>(path));
    auto output = arrow::io::FileOutputStream::Open(std::string(c_path));
    if (!output.ok()) return 1;
    auto status = parquet::arrow::WriteTable(
        *frame->table, arrow::default_memory_pool(), *output);
    if (!status.ok()) return 1;
    auto close_status = (*output)->Close();
    return close_status.ok() ? 0 : 1;
#else
    (void)path;
    return 1;  // Parquet component absent: backend unavailable
#endif
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

// Additive Float64-bit-pattern filter entry (section-8 decision 5). The bits
// parameter is the IEEE-754 binary64 representation of the comparison value,
// carried as an Int64; memcpy avoids type punning and pointer casts.
extern "C" long long pandas_dataframe_filter_f64(long long df, long long col_name,
                                                 long long op, long long bits) {
  try {
    PdDataFrame* frame = as_frame(df);
    if (frame == nullptr || col_name == 0 || op < 0 || op > 5) return 0;
    double value = 0.0;
    std::memcpy(&value, &bits, sizeof(value));
    ensure_compute_initialized();
    const auto* name = reinterpret_cast<const char*>(
        static_cast<std::intptr_t>(col_name));
    auto column = frame->table->GetColumnByName(std::string(name));
    if (column == nullptr) return 0;
    auto scalar = scalar_for_column_f64(column->type(), value);
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

// Acero-free group-by (section-8 decisions 1-2): arrow::compute::Grouper
// produces group ids and the unique keys; the bridge counts ids per group.
// Output: the key column under its original name plus "count" (Int64), in
// grouper (hash) order. No Acero headers or symbols are used.
extern "C" long long pandas_c_dataframe_groupby(long long df,
                                                long long col_name) {
  try {
    PdDataFrame* frame = as_frame(df);
    if (frame == nullptr || col_name == 0) return 0;
    const auto* name = reinterpret_cast<const char*>(
        static_cast<std::intptr_t>(col_name));
    const std::string key(name);
    auto column = frame->table->GetColumnByName(key);
    if (column == nullptr) return 0;
    ensure_compute_initialized();

    std::shared_ptr<arrow::ChunkedArray> unique_keys;
    std::shared_ptr<arrow::Array> counts;
    if (frame->table->num_rows() == 0) {
      auto empty_keys = arrow::MakeArrayOfNull(column->type(), 0);
      if (!empty_keys.ok()) return 0;
      unique_keys = wrap_array(*empty_keys);
      arrow::Int64Builder count_builder;
      auto count_array = count_builder.Finish();
      if (!count_array.ok()) return 0;
      counts = *count_array;
    } else {
      auto key_array = flatten_column(column);
      if (key_array == nullptr) return 0;
      auto grouper_result =
          arrow::compute::Grouper::Make({arrow::TypeHolder(column->type())});
      if (!grouper_result.ok()) return 0;
      auto grouper = std::move(*grouper_result);
      arrow::compute::ExecSpan span;
      if (!make_span(key_array, &span)) return 0;
      auto ids_result = grouper->Consume(span);
      if (!ids_result.ok()) return 0;
      auto ids = ids_from_datum(*ids_result);
      if (ids == nullptr) return 0;
      const std::uint32_t num_groups = grouper->num_groups();
      std::vector<int64_t> group_counts(num_groups, 0);
      for (int64_t i = 0; i < ids->length(); ++i) {
        if (ids->IsNull(i)) return 0;
        const std::uint32_t id = ids->Value(i);
        if (id >= num_groups) return 0;
        ++group_counts[id];
      }
      auto uniques_result = grouper->GetUniques();
      if (!uniques_result.ok()) return 0;
      const arrow::compute::ExecBatch& uniques = *uniques_result;
      if (uniques.num_values() != 1) return 0;
      unique_keys = datum_as_chunked(uniques[0]);
      if (unique_keys == nullptr || unique_keys->length() !=
                                        static_cast<int64_t>(num_groups)) {
        return 0;
      }
      arrow::Int64Builder count_builder;
      auto status = count_builder.AppendValues(group_counts);
      if (!status.ok()) return 0;
      auto count_array = count_builder.Finish();
      if (!count_array.ok()) return 0;
      counts = *count_array;
    }

    std::vector<std::shared_ptr<arrow::Field>> fields = {
        arrow::field(key, column->type(), /*nullable=*/true),
        arrow::field("count", arrow::int64(), /*nullable=*/false)};
    std::vector<std::shared_ptr<arrow::ChunkedArray>> columns = {
        unique_keys, wrap_array(counts)};
    auto grouped = arrow::Table::Make(arrow::schema(std::move(fields)),
                                      std::move(columns));
    auto* group = new PdGroupBy();
    group->input = frame->table;
    group->grouped = std::move(grouped);
    group->key = key;
    return group_to_handle(group);
  } catch (...) {
    return 0;
  }
}

// Acero-free hash join (section-8 decision 1). Keys are grouped with
// arrow::compute::Grouper (same key types required); rows are gathered with
// arrow::compute::Take. Duplicate column names get the Acero-style _left /
// _right suffixes. Null keys follow Grouper semantics (nulls group together;
// NA policy is out of scope for this package model).
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
    auto left_key = left_frame->table->GetColumnByName(key);
    auto right_key = right_frame->table->GetColumnByName(key);
    if (left_key == nullptr || right_key == nullptr) return 0;
    if (!left_key->type()->Equals(right_key->type())) return 0;
    ensure_compute_initialized();

    const int64_t left_row_count = left_frame->table->num_rows();
    const int64_t right_row_count = right_frame->table->num_rows();
    const bool keep_left = (how == 1 || how == 3);
    const bool keep_right = (how == 2 || how == 3);

    std::vector<int64_t> left_idx;
    std::vector<int64_t> right_idx;
    std::vector<bool> left_is_null;
    std::vector<bool> right_is_null;

    if (left_row_count > 0) {
      auto left_array = flatten_column(left_key);
      if (left_array == nullptr) return 0;
      auto grouper_result =
          arrow::compute::Grouper::Make({arrow::TypeHolder(left_key->type())});
      if (!grouper_result.ok()) return 0;
      auto grouper = std::move(*grouper_result);

      arrow::compute::ExecSpan left_span;
      if (!make_span(left_array, &left_span)) return 0;
      auto left_ids_result = grouper->Consume(left_span);
      if (!left_ids_result.ok()) return 0;
      auto left_ids = ids_from_datum(*left_ids_result);
      if (left_ids == nullptr) return 0;

      const std::uint32_t num_groups = grouper->num_groups();
      std::vector<std::vector<int64_t>> matches_by_group(num_groups);

      std::shared_ptr<arrow::UInt32Array> right_ids;
      if (right_row_count > 0) {
        auto right_array = flatten_column(right_key);
        if (right_array == nullptr) return 0;
        arrow::compute::ExecSpan right_span;
        if (!make_span(right_array, &right_span)) return 0;
        auto right_ids_result = grouper->Lookup(right_span);
        if (!right_ids_result.ok()) return 0;
        right_ids = ids_from_datum(*right_ids_result);
        if (right_ids == nullptr) return 0;
        for (int64_t i = 0; i < right_ids->length(); ++i) {
          if (right_ids->IsNull(i)) continue;
          const std::uint32_t id = right_ids->Value(i);
          if (id >= num_groups) return 0;
          matches_by_group[id].push_back(i);
        }
      }

      left_idx.reserve(static_cast<std::size_t>(left_row_count));
      for (int64_t i = 0; i < left_ids->length(); ++i) {
        const std::uint32_t id = left_ids->Value(i);
        if (id >= num_groups) return 0;
        const auto& matches = matches_by_group[id];
        if (!matches.empty()) {
          for (int64_t j : matches) {
            left_idx.push_back(i);
            right_idx.push_back(j);
            left_is_null.push_back(false);
            right_is_null.push_back(false);
          }
        } else if (keep_left) {
          left_idx.push_back(i);
          right_idx.push_back(0);
          left_is_null.push_back(false);
          right_is_null.push_back(true);
        }
      }
      if (keep_right && right_ids != nullptr) {
        for (int64_t i = 0; i < right_ids->length(); ++i) {
          if (right_ids->IsNull(i)) {
            left_idx.push_back(0);
            right_idx.push_back(i);
            left_is_null.push_back(true);
            right_is_null.push_back(false);
          }
        }
      }
    } else if (keep_right) {
      left_idx.reserve(static_cast<std::size_t>(right_row_count));
      for (int64_t i = 0; i < right_row_count; ++i) {
        left_idx.push_back(0);
        right_idx.push_back(i);
        left_is_null.push_back(true);
        right_is_null.push_back(false);
      }
    }

    arrow::Int64Builder left_index_builder;
    arrow::Int64Builder right_index_builder;
    for (std::size_t i = 0; i < left_idx.size(); ++i) {
      auto status = left_is_null[i] ? left_index_builder.AppendNull()
                                    : left_index_builder.Append(left_idx[i]);
      if (!status.ok()) return 0;
    }
    for (std::size_t i = 0; i < right_idx.size(); ++i) {
      auto status = right_is_null[i] ? right_index_builder.AppendNull()
                                     : right_index_builder.Append(right_idx[i]);
      if (!status.ok()) return 0;
    }

    auto left_indices_result = left_index_builder.Finish();
    auto right_indices_result = right_index_builder.Finish();
    if (!left_indices_result.ok() || !right_indices_result.ok()) return 0;
    auto left_indices = *left_indices_result;
    auto right_indices = *right_indices_result;

    std::unordered_set<std::string> left_names;
    std::unordered_set<std::string> right_names;
    for (const auto& field : left_frame->table->schema()->fields()) {
      left_names.insert(field->name());
    }
    for (const auto& field : right_frame->table->schema()->fields()) {
      right_names.insert(field->name());
    }

    std::vector<std::shared_ptr<arrow::Field>> fields;
    std::vector<std::shared_ptr<arrow::ChunkedArray>> columns;
    for (int i = 0; i < left_frame->table->num_columns(); ++i) {
      auto field = left_frame->table->schema()->field(i);
      const bool collides = right_names.count(field->name()) != 0;
      const std::string out_name =
          collides ? field->name() + "_left" : field->name();
      auto taken = arrow::compute::Take(
          arrow::Datum(left_frame->table->column(i)),
          arrow::Datum(left_indices));
      if (!taken.ok()) return 0;
      auto chunked = datum_as_chunked(*taken);
      if (chunked == nullptr) return 0;
      fields.push_back(arrow::field(out_name, field->type(), field->nullable()));
      columns.push_back(std::move(chunked));
    }
    for (int i = 0; i < right_frame->table->num_columns(); ++i) {
      auto field = right_frame->table->schema()->field(i);
      const bool collides = left_names.count(field->name()) != 0;
      const std::string out_name =
          collides ? field->name() + "_right" : field->name();
      auto taken = arrow::compute::Take(
          arrow::Datum(right_frame->table->column(i)),
          arrow::Datum(right_indices));
      if (!taken.ok()) return 0;
      auto chunked = datum_as_chunked(*taken);
      if (chunked == nullptr) return 0;
      fields.push_back(arrow::field(out_name, field->type(), field->nullable()));
      columns.push_back(std::move(chunked));
    }
    return append_frame(
        arrow::Table::Make(arrow::schema(std::move(fields)), std::move(columns)));
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

// Section-8 decision 3: double (*)(double), per element, Float64-only. No
// element coercion; null elements and non-Float64 series fail closed (0).
// NA/NaN policies are out of scope: NaN values are passed through unchanged.
extern "C" long long pandas_c_series_apply(long long series,
                                           long long func_ptr) {
  using UnaryDouble = double (*)(double);
  try {
    PdSeries* handle = as_series(series);
    if (handle == nullptr || func_ptr == 0) return 0;
    if (handle->column->type()->id() != arrow::Type::DOUBLE) return 0;
    auto fn = reinterpret_cast<UnaryDouble>(static_cast<std::intptr_t>(func_ptr));
    auto array = flatten_column(handle->column);
    if (array == nullptr) return 0;
    const auto& doubles =
        arrow::internal::checked_cast<const arrow::DoubleArray&>(*array);
    arrow::DoubleBuilder builder;
    auto status = builder.Reserve(doubles.length());
    if (!status.ok()) return 0;
    for (int64_t i = 0; i < doubles.length(); ++i) {
      if (doubles.IsNull(i)) return 0;  /* NA policy out of scope */
      status = builder.Append(fn(doubles.Value(i)));
      if (!status.ok()) return 0;
    }
    auto result = builder.Finish();
    if (!result.ok()) return 0;
    return make_series_from_array(*result);
  } catch (...) {
    return 0;
  }
}

// ===========================================================================
// Additive ownership free functions (section-8 decision 4)
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
