// xiom.usd -- C ABI bridge over the OpenUSD v26.08 C++ API.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN (bindings lane, assimp-class treatment):
//   * The package does not link against USD at build time.  The bridge is
//     compiled with the vendored v26.08 headers (PSR_STATIC) and linked to a
//     generated import library for the prebuilt `usd_ms.dll` shipped by the
//     official `usd-core` wheel.  The import is DELAY-LOADED, so a process
//     starts without the runtime and the suite reports SKIP.
//   * Data imports cannot be resolved by function trampolines.  The bridge therefore defines the
//     three data symbols its inline header code touches -- Sdf_Pool's
//     _regionStarts (Prim/Prop) and UsdPrimDefaultPredicate -- locally, and
//     mirrors the DLL's Sdf pool region table before every USD call.  The
//     local pool arrays are exported from this module so the sync shim can
//     address them (see sync_pools).
//   * TfMallocTag::_isInitialized is defined false locally: our translation
//     unit's inline malloc-tag probes stay no-ops; the DLL keeps its own.
//   * ABI gate: the bridge binds the v26.08 namespace
//     (pxrInternal_v0_26_8__pxrReserved__) and `usd_ms.dll`.  Other sonames
//     (usd.dll, libusd.so) are probed and reported as typed ABI errors; the
//     wheel at the pin is the supported runtime.
//
// All USD calls happen under one mutex (handles are IDs into maps), and every
// public entry point syncs the pool table before and after the call.
//
// Surface: stage open/close/traversal, prim read (name/type/path/authored
// attributes), mesh extraction (points/face-vertex counts/indices), material
// surface subset (binding -> surface shader -> inputs) and time samples.

// ---------------------------------------------------------------------------
// Compile-time configuration (the XIOM link line has no -D passthrough).
// ---------------------------------------------------------------------------
#ifndef PXR_STATIC
#define PXR_STATIC 1
#endif
#ifndef _ITERATOR_DEBUG_LEVEL
#define _ITERATOR_DEBUG_LEVEL 0
#endif
#ifndef NDEBUG
#define NDEBUG 1
#endif
#ifndef __TBB_NO_IMPLICIT_LINKAGE
#define __TBB_NO_IMPLICIT_LINKAGE 1
#endif
#ifndef NOMINMAX
#define NOMINMAX 1
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN 1
#endif

#include "../vendor/include/pxr/pxr.h"
#include "../vendor/include/pxr/usd/sdf/path.h"
#include "../vendor/include/pxr/usd/sdf/pool.h"
#include "../vendor/include/pxr/usd/usd/stage.h"
#include "../vendor/include/pxr/usd/usd/prim.h"
#include "../vendor/include/pxr/usd/usd/attribute.h"
#include "../vendor/include/pxr/usd/usd/relationship.h"
#include "../vendor/include/pxr/usd/usd/primRange.h"
#include "../vendor/include/pxr/usd/usd/primFlags.h"
#include "../vendor/include/pxr/base/vt/array.h"
#include "../vendor/include/pxr/base/gf/vec3f.h"
#include "../vendor/include/pxr/base/tf/token.h"

#include <windows.h>

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <exception>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

PXR_NAMESPACE_USING_DIRECTIVE

extern "C" int usdbridge_resolve_all(void *module);
// ---------------------------------------------------------------------------
// Sdf pool / static-data shims (see DESIGN).
// ---------------------------------------------------------------------------
#define USD_PRIM_STARTS_SYM \
    "?_regionStarts@?$Sdf_Pool@USdf_PathPrimTag@pxrInternal_v0_26_8__pxrReserved__@@$0BI@$07$0EAAA@@pxrInternal_v0_26_8__pxrReserved__@@0PAPEADA"
#define USD_PROP_STARTS_SYM \
    "?_regionStarts@?$Sdf_Pool@USdf_PathPropTag@pxrInternal_v0_26_8__pxrReserved__@@$0BI@$07$0EAAA@@pxrInternal_v0_26_8__pxrReserved__@@0PAPEADA"

#pragma comment(linker, "/export:" USD_PRIM_STARTS_SYM)
#pragma comment(linker, "/export:" USD_PROP_STARTS_SYM)

template <class Tag, unsigned ElemSize, unsigned RegionBits, unsigned ElemsPerSpan>
char *Sdf_Pool<Tag, ElemSize, RegionBits, ElemsPerSpan>::_regionStarts[
    Sdf_Pool<Tag, ElemSize, RegionBits, ElemsPerSpan>::NumRegions + 1];

PXR_NAMESPACE_OPEN_SCOPE
std::atomic<bool> TfMallocTag::_isInitialized{false};
const Usd_PrimFlagsConjunction UsdPrimDefaultPredicate =
    UsdPrimIsActive && UsdPrimIsDefined &&
    UsdPrimIsLoaded && !UsdPrimIsAbstract;
PXR_NAMESPACE_CLOSE_SCOPE

// ---------------------------------------------------------------------------
// Error model.  Every status-returning entry point returns 0 on success and
// -code on failure; last_error carries the detail.
// ---------------------------------------------------------------------------
enum {
    USD_OK = 0,
    USD_ERR_RUNTIME_ABSENT = 1,
    USD_ERR_RUNTIME_ABI = 2,
    USD_ERR_RUNTIME_DEPS = 3,
    USD_ERR_OPEN = 4,
    USD_ERR_INVALID_HANDLE = 5,
    USD_ERR_NOT_PRIM = 6,
    USD_ERR_NOT_MESH = 7,
    USD_ERR_MESH_INVALID = 8,
    USD_ERR_ATTR_MISSING = 9,
    USD_ERR_TYPE = 10,
    USD_ERR_RANGE = 11,
    USD_ERR_BUFFER = 12,
    USD_ERR_NO_SURFACE = 13,
    USD_ERR_NO_VALUE = 14,
    USD_ERR_INTERNAL = 15,
    USD_ERR_NO_BINDING = 16,
    USD_ERR_NOT_MATERIAL = 17,
    USD_ERR_INVALID_PATH = 18,
    USD_ERR_OVERFLOW = 19
};

static thread_local int t_error_code = USD_OK;
static thread_local std::string t_error_message;

static int fail(int code, const std::string &message) {
    t_error_code = code;
    t_error_message = message;
    return -code;
}

static void clear_error() {
    t_error_code = USD_OK;
    t_error_message.clear();
}

// ---------------------------------------------------------------------------
// Runtime loading.
// ---------------------------------------------------------------------------
static HMODULE g_usd_dll = nullptr;
static HMODULE g_self_module = nullptr;
static std::mutex g_mutex;
static uint64_t g_next_id = 0x1000;

struct StageHandle {
    UsdStageRefPtr stage;
};

struct PrimHandle {
    UsdPrim prim;
    std::vector<UsdAttribute> attrs;
    uint64_t stage_id;
};

struct IterHandle {
    UsdPrimRange range;
    UsdPrimRange::iterator it;
    uint64_t stage_id;

    IterHandle(UsdPrimRange r, uint64_t sid)
        : range(std::move(r)), it(range.begin()), stage_id(sid) {}
};

static std::unordered_map<uint64_t, StageHandle> g_stages;
static std::unordered_map<uint64_t, PrimHandle> g_prims;
static std::unordered_map<uint64_t, std::unique_ptr<IterHandle>> g_iters;

static std::wstring utf8_to_wide(const char *s) {
    if (!s || !*s) return std::wstring();
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, nullptr, 0);
    if (n <= 0) {
        n = MultiByteToWideChar(CP_ACP, 0, s, -1, nullptr, 0);
        if (n <= 0) return std::wstring();
        std::wstring out(static_cast<size_t>(n - 1), L'\0');
        MultiByteToWideChar(CP_ACP, 0, s, -1, &out[0], n);
        return out;
    }
    std::wstring out(static_cast<size_t>(n - 1), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, &out[0], n);
    return out;
}

static std::string wide_to_utf8(const wchar_t *s) {
    if (!s || !*s) return std::string();
    int n = WideCharToMultiByte(CP_UTF8, 0, s, -1, nullptr, 0, nullptr, nullptr);
    if (n <= 0) return std::string();
    std::string out(static_cast<size_t>(n - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, s, -1, &out[0], n, nullptr, nullptr);
    return out;
}

static bool file_exists(const std::wstring &path) {
    DWORD attrs = GetFileAttributesW(path.c_str());
    return attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY);
}

static void preload_if_present(const std::wstring &path) {
    if (file_exists(path)) {
        LoadLibraryW(path.c_str());
    }
}

static void prepend_path(const std::wstring &dir) {
    DWORD needed = GetEnvironmentVariableW(L"PATH", nullptr, 0);
    std::wstring current;
    if (needed > 0) {
        current.resize(needed);
        DWORD got = GetEnvironmentVariableW(L"PATH", &current[0], needed);
        if (got > 0 && got <= needed) current.resize(got);
        else current.clear();
    }
    std::wstring next = dir + L";" + current;
    SetEnvironmentVariableW(L"PATH", next.c_str());
}

static void append_plugin_path(const std::wstring &plugin_dir) {
    DWORD needed = GetEnvironmentVariableW(L"PXR_PLUGINPATH_NAME", nullptr, 0);
    std::wstring current;
    if (needed > 0) {
        current.resize(needed);
        DWORD got = GetEnvironmentVariableW(L"PXR_PLUGINPATH_NAME", &current[0], needed);
        if (got > 0 && got <= needed) current.resize(got);
        else current.clear();
    }
    std::wstring next = plugin_dir;
    if (!current.empty()) next += L";" + current;
    SetEnvironmentVariableW(L"PXR_PLUGINPATH_NAME", next.c_str());
}

// Mirror the DLL's Sdf_Pool region tables into this module's local copies.
// Returns false when the local exports are missing (an ABI/build-gate error).
static bool sync_pools() {
    static bool resolved = false;
    static char **local_prim = nullptr;
    static char **local_prop = nullptr;
    static char **remote_prim = nullptr;
    static char **remote_prop = nullptr;

    if (!g_self_module) {
        GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                               GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           reinterpret_cast<LPCWSTR>(&sync_pools), &g_self_module);
    }
    if (!g_usd_dll) return false;

    if (!resolved) {
        if (g_self_module) {
            local_prim = reinterpret_cast<char **>(
                GetProcAddress(g_self_module, USD_PRIM_STARTS_SYM));
            local_prop = reinterpret_cast<char **>(
                GetProcAddress(g_self_module, USD_PROP_STARTS_SYM));
        }
        remote_prim = reinterpret_cast<char **>(
            GetProcAddress(g_usd_dll, USD_PRIM_STARTS_SYM));
        remote_prop = reinterpret_cast<char **>(
            GetProcAddress(g_usd_dll, USD_PROP_STARTS_SYM));
        resolved = true;
    }
    if (!local_prim || !local_prop || !remote_prim || !remote_prop) return false;

    // Sdf_PathPrimTag/Sdf_PathPropTag at v26.08: regionBits=8 => 257 slots.
    const size_t slots = 257;
    std::memcpy(local_prim, remote_prim, slots * sizeof(char *));
    std::memcpy(local_prop, remote_prop, slots * sizeof(char *));
    return true;
}

extern "C" int32_t usdbridge_runtime_prepare(const char *runtime_dir_utf8) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    if (g_usd_dll) return USD_OK;

    std::wstring dir = utf8_to_wide(runtime_dir_utf8);
    if (!dir.empty()) {
        SetDllDirectoryW(dir.c_str());
        prepend_path(dir);
        SetEnvironmentVariableW(L"PXR_USD_WINDOWS_DLL_PATH", dir.c_str());

        std::wstring pluginfo = dir + L"\\pluginfo";
        if (file_exists(pluginfo + L"\\plugInfo.json")) {
            append_plugin_path(pluginfo);
        } else if (file_exists(dir + L"\\plugInfo.json")) {
            append_plugin_path(dir);
        }

        preload_if_present(dir + L"\\tbb.dll");
        preload_if_present(dir + L"\\tbb12.dll");

        // The usd-core wheel's monolithic DLL imports the CPython runtime.
        // Accept the wheel layouts seen in the wild (cp39-cp314) without
        // requiring the caller to edit PATH.
        static const wchar_t *const py_names[] = {
            L"python314.dll", L"python313.dll", L"python312.dll",
            L"python311.dll", L"python310.dll", L"python39.dll"
        };
        bool py_loaded = false;
        for (const wchar_t *name : py_names) {
            if (file_exists(dir + L"\\" + name)) {
                preload_if_present(dir + L"\\" + name);
                py_loaded = true;
                break;
            }
        }
        if (!py_loaded) {
            std::wstring parent = dir + L"\\..";
            std::wstring grandparent = parent + L"\\..";
            for (const wchar_t *name : py_names) {
                if (file_exists(parent + L"\\" + name)) {
                    preload_if_present(parent + L"\\" + name);
                    py_loaded = true;
                    break;
                }
                std::wstring py_name(name);
                std::wstring ver = py_name.substr(6, py_name.size() - 10); // "311"
                const std::wstring candidates[] = {
                    parent + L"\\python" + ver + L"\\" + name,
                    grandparent + L"\\python" + ver + L"\\" + name,
                    grandparent + L"\\python\\" + name,
                    grandparent + L"\\" + name,
                };
                for (const std::wstring &candidate : candidates) {
                    if (file_exists(candidate)) {
                        preload_if_present(candidate);
                        py_loaded = true;
                        break;
                    }
                }
                if (py_loaded) break;
            }
        }
    }

    HMODULE h = LoadLibraryW(L"usd_ms.dll");
    if (!h) {
        DWORD err = GetLastError();
        bool primary_present = !dir.empty() && file_exists(dir + L"\\usd_ms.dll");
        if (!primary_present) {
            HMODULE alt = LoadLibraryW(L"usd.dll");
            if (alt) {
                FreeLibrary(alt);
                t_error_code = USD_ERR_RUNTIME_ABI;
                t_error_message =
                    "usd.dll is present but this bridge binds the v26.08 "
                    "usd_ms.dll wheel (ABI gate)";
                return -USD_ERR_RUNTIME_ABI;
            }
            t_error_code = USD_ERR_RUNTIME_ABSENT;
            t_error_message = "usd_ms.dll not found (runtime dir: " +
                (dir.empty() ? std::string("<default search path>") : wide_to_utf8(dir.c_str())) +
                ")";
            return -USD_ERR_RUNTIME_ABSENT;
        }
        t_error_code = USD_ERR_RUNTIME_DEPS;
        char buf[128];
        std::snprintf(buf, sizeof(buf), "LoadLibrary(usd_ms.dll) failed (error %lu); "
                      "check tbb.dll and the CPython runtime in the wheel dir",
                      static_cast<unsigned long>(err));
        t_error_message = buf;
        return -USD_ERR_RUNTIME_DEPS;
    }

    if (!usdbridge_resolve_all(reinterpret_cast<void *>(h))) {
        FreeLibrary(h);
        t_error_code = USD_ERR_RUNTIME_ABI;
        t_error_message =
            "usd_ms.dll is missing one or more pinned v26.08 functions "
            "(pxrInternal_v0_26_8__pxrReserved__; ABI gate)";
        return -USD_ERR_RUNTIME_ABI;
    }

    g_usd_dll = h;
    if (!sync_pools()) {
        FreeLibrary(g_usd_dll);
        g_usd_dll = nullptr;
        t_error_code = USD_ERR_RUNTIME_ABI;
        t_error_message =
            "bridge pool shim is not exported from the executable module "
            "(rebuild with the /export pragmas; ABI gate)";
        return -USD_ERR_RUNTIME_ABI;
    }
    return USD_OK;
}

extern "C" int32_t usdbridge_runtime_soname(char *out, int32_t cap) {
    const char *name = "usd_ms.dll";
    size_t n = std::strlen(name);
    if (!out || cap <= 0) return fail(USD_ERR_BUFFER, "output buffer is null/empty");
    if (static_cast<size_t>(cap) <= n) {
        return fail(USD_ERR_BUFFER, "output buffer too small for soname");
    }
    std::memcpy(out, name, n + 1);
    return static_cast<int32_t>(n);
}

extern "C" int32_t usdbridge_bridge_version(void) { return 100; }
extern "C" int32_t usdbridge_bridge_abi(void) { return 2608; }
extern "C" int32_t usdbridge_bridge_surface_count(void) { return 58; }

extern "C" int32_t usdbridge_last_error_code(void) { return t_error_code; }
extern "C" const char *usdbridge_last_error_message(void) { return t_error_message.c_str(); }

extern "C" const char *usdbridge_error_name(int32_t code) {
    switch (code) {
        case USD_OK: return "OK";
        case USD_ERR_RUNTIME_ABSENT: return "RUNTIME_ABSENT";
        case USD_ERR_RUNTIME_ABI: return "RUNTIME_ABI";
        case USD_ERR_RUNTIME_DEPS: return "RUNTIME_DEPS";
        case USD_ERR_OPEN: return "OPEN";
        case USD_ERR_INVALID_HANDLE: return "INVALID_HANDLE";
        case USD_ERR_NOT_PRIM: return "NOT_PRIM";
        case USD_ERR_NOT_MESH: return "NOT_MESH";
        case USD_ERR_MESH_INVALID: return "MESH_INVALID";
        case USD_ERR_ATTR_MISSING: return "ATTR_MISSING";
        case USD_ERR_TYPE: return "TYPE";
        case USD_ERR_RANGE: return "RANGE";
        case USD_ERR_BUFFER: return "BUFFER";
        case USD_ERR_NO_SURFACE: return "NO_SURFACE";
        case USD_ERR_NO_VALUE: return "NO_VALUE";
        case USD_ERR_INTERNAL: return "INTERNAL";
        case USD_ERR_NO_BINDING: return "NO_BINDING";
        case USD_ERR_NOT_MATERIAL: return "NOT_MATERIAL";
        case USD_ERR_INVALID_PATH: return "INVALID_PATH";
        case USD_ERR_OVERFLOW: return "OVERFLOW";
        default: return "UNKNOWN";
    }
}

// ---------------------------------------------------------------------------
// Small helpers.
// ---------------------------------------------------------------------------
static int copy_out(const std::string &s, char *out, int32_t cap) {
    if (!out || cap <= 0) return fail(USD_ERR_BUFFER, "output buffer is null/empty");
    if (s.size() >= static_cast<size_t>(cap)) {
        return fail(USD_ERR_BUFFER, "output buffer too small for value");
    }
    std::memcpy(out, s.c_str(), s.size() + 1);
    return static_cast<int32_t>(s.size());
}

static std::string attr_type_name(const UsdAttribute &a) {
    TfToken t = a.GetTypeName().GetAsToken();
    return std::string(t.GetText());
}

static bool prim_alive_locked(uint64_t id, PrimHandle **out) {
    auto it = g_prims.find(id);
    if (it == g_prims.end()) return false;
    if (g_stages.find(it->second.stage_id) == g_stages.end()) return false;
    *out = &it->second;
    return true;
}

static bool iter_alive_locked(uint64_t id, IterHandle **out) {
    auto it = g_iters.find(id);
    if (it == g_iters.end()) return false;
    if (g_stages.find(it->second->stage_id) == g_stages.end()) return false;
    *out = it->second.get();
    return true;
}

static UsdAttribute *attr_at(PrimHandle *p, int32_t index) {
    if (index < 0 || static_cast<size_t>(index) >= p->attrs.size()) return nullptr;
    return &p->attrs[static_cast<size_t>(index)];
}

static UsdAttribute *attr_by_name(PrimHandle *p, const char *name) {
    if (!name || !*name) return nullptr;
    for (UsdAttribute &a : p->attrs) {
        if (std::strcmp(a.GetName().GetText(), name) == 0) return &a;
    }
    return nullptr;
}

static UsdAttribute *input_at(PrimHandle *p, int32_t index) {
    int32_t seen = 0;
    for (UsdAttribute &a : p->attrs) {
        const char *name = a.GetName().GetText();
        if (std::strncmp(name, "inputs:", 7) != 0) continue;
        if (seen == index) return &a;
        ++seen;
    }
    return nullptr;
}

static UsdAttribute *input_by_name(PrimHandle *p, const char *name) {
    if (!name || !*name) return nullptr;
    std::string full(name);
    if (full.compare(0, 7, "inputs:") != 0) full = "inputs:" + full;
    for (UsdAttribute &a : p->attrs) {
        if (full == a.GetName().GetText()) return &a;
    }
    return nullptr;
}

// ---------------------------------------------------------------------------
// Stage / iterator / prim handles.
// ---------------------------------------------------------------------------
extern "C" uint64_t usdbridge_stage_open(const char *path_utf8) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    if (!g_usd_dll) {
        fail(USD_ERR_RUNTIME_ABSENT, "USD runtime is not loaded (call usd_load first)");
        return 0;
    }
    if (!path_utf8 || !*path_utf8) {
        fail(USD_ERR_OPEN, "empty stage path");
        return 0;
    }
    sync_pools();
    try {
        UsdStageRefPtr stage = UsdStage::Open(std::string(path_utf8));
        sync_pools();
        if (!stage) {
            fail(USD_ERR_OPEN, std::string("UsdStage::Open failed: ") + path_utf8);
            return 0;
        }
        uint64_t id = g_next_id++;
        g_stages.emplace(id, StageHandle{stage});
        return id;
    } catch (const std::exception &e) {
        fail(USD_ERR_OPEN, std::string("UsdStage::Open exception: ") + e.what());
        return 0;
    } catch (...) {
        fail(USD_ERR_OPEN, "UsdStage::Open unknown exception");
        return 0;
    }
}

extern "C" int32_t usdbridge_stage_release(uint64_t stage_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_stages.find(stage_id);
    if (it == g_stages.end()) return fail(USD_ERR_INVALID_HANDLE, "invalid stage handle");
    for (auto pit = g_prims.begin(); pit != g_prims.end();) {
        if (pit->second.stage_id == stage_id) pit = g_prims.erase(pit);
        else ++pit;
    }
    for (auto iit = g_iters.begin(); iit != g_iters.end();) {
        if (iit->second->stage_id == stage_id) iit = g_iters.erase(iit);
        else ++iit;
    }
    g_stages.erase(it);
    clear_error();
    return USD_OK;
}

extern "C" int32_t usdbridge_stage_default_prim(uint64_t stage_id, char *out, int32_t cap) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    auto it = g_stages.find(stage_id);
    if (it == g_stages.end()) return fail(USD_ERR_INVALID_HANDLE, "invalid stage handle");
    sync_pools();
    UsdPrim p = it->second.stage->GetDefaultPrim();
    sync_pools();
    if (!p) return copy_out(std::string(), out, cap);
    return copy_out(std::string(p.GetName().GetText()), out, cap);
}

extern "C" uint64_t usdbridge_stage_iter(uint64_t stage_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    auto it = g_stages.find(stage_id);
    if (it == g_stages.end()) {
        fail(USD_ERR_INVALID_HANDLE, "invalid stage handle");
        return 0;
    }
    sync_pools();
    try {
        UsdPrimRange range = UsdPrimRange::Stage(it->second.stage);
        sync_pools();
        uint64_t id = g_next_id++;
        g_iters.emplace(id, std::unique_ptr<IterHandle>(
            new IterHandle(std::move(range), stage_id)));
        return id;
    } catch (const std::exception &e) {
        fail(USD_ERR_INTERNAL, std::string("stage iterator: ") + e.what());
        return 0;
    } catch (...) {
        fail(USD_ERR_INTERNAL, "stage iterator: unknown exception");
        return 0;
    }
}

extern "C" uint64_t usdbridge_prim_iter(uint64_t prim_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) {
        fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
        return 0;
    }
    sync_pools();
    try {
        UsdPrimRange range(p->prim);
        sync_pools();
        uint64_t id = g_next_id++;
        g_iters.emplace(id, std::unique_ptr<IterHandle>(
            new IterHandle(std::move(range), p->stage_id)));
        return id;
    } catch (const std::exception &e) {
        fail(USD_ERR_INTERNAL, std::string("prim iterator: ") + e.what());
        return 0;
    } catch (...) {
        fail(USD_ERR_INTERNAL, "prim iterator: unknown exception");
        return 0;
    }
}

extern "C" uint64_t usdbridge_iter_next(uint64_t iter_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    IterHandle *it = nullptr;
    if (!iter_alive_locked(iter_id, &it)) {
        fail(USD_ERR_INVALID_HANDLE, "invalid iterator handle");
        return 0;
    }
    sync_pools();
    if (it->it == it->range.end()) return 0;
    UsdPrim p = *it->it;
    sync_pools();
    ++it->it;
    sync_pools();
    if (!p) {
        fail(USD_ERR_NOT_PRIM, "iterator yielded an invalid prim");
        return 0;
    }
    uint64_t id = g_next_id++;
    g_prims.emplace(id, PrimHandle{p, p.GetAuthoredAttributes(), it->stage_id});
    return id;
}

extern "C" int32_t usdbridge_iter_release(uint64_t iter_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_iters.find(iter_id);
    if (it == g_iters.end()) return fail(USD_ERR_INVALID_HANDLE, "invalid iterator handle");
    g_iters.erase(it);
    clear_error();
    return USD_OK;
}

extern "C" uint64_t usdbridge_prim_at_path(uint64_t stage_id, const char *path_utf8) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    auto it = g_stages.find(stage_id);
    if (it == g_stages.end()) {
        fail(USD_ERR_INVALID_HANDLE, "invalid stage handle");
        return 0;
    }
    if (!path_utf8 || !*path_utf8) {
        fail(USD_ERR_INVALID_PATH, "empty prim path");
        return 0;
    }
    sync_pools();
    try {
        SdfPath path{std::string(path_utf8)};
        sync_pools();
        if (path.IsEmpty()) {
            fail(USD_ERR_INVALID_PATH, std::string("invalid prim path: ") + path_utf8);
            return 0;
        }
        UsdPrim p = it->second.stage->GetPrimAtPath(path);
        sync_pools();
        if (!p) {
            fail(USD_ERR_NOT_PRIM, std::string("prim not found: ") + path_utf8);
            return 0;
        }
        uint64_t id = g_next_id++;
        g_prims.emplace(id, PrimHandle{p, p.GetAuthoredAttributes(), stage_id});
        return id;
    } catch (const std::exception &e) {
        fail(USD_ERR_INTERNAL, std::string("GetPrimAtPath: ") + e.what());
        return 0;
    } catch (...) {
        fail(USD_ERR_INTERNAL, "GetPrimAtPath: unknown exception");
        return 0;
    }
}

extern "C" int32_t usdbridge_prim_release(uint64_t prim_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_prims.find(prim_id);
    if (it == g_prims.end()) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    g_prims.erase(it);
    clear_error();
    return USD_OK;
}

extern "C" int32_t usdbridge_prim_is_valid(uint64_t prim_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    return prim_alive_locked(prim_id, &p) && p->prim ? 1 : 0;
}

extern "C" int32_t usdbridge_prim_name(uint64_t prim_id, char *out, int32_t cap) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    if (!p->prim) return fail(USD_ERR_NOT_PRIM, "prim is invalid");
    return copy_out(std::string(p->prim.GetName().GetText()), out, cap);
}

extern "C" int32_t usdbridge_prim_type(uint64_t prim_id, char *out, int32_t cap) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    if (!p->prim) return fail(USD_ERR_NOT_PRIM, "prim is invalid");
    return copy_out(std::string(p->prim.GetTypeName().GetText()), out, cap);
}

extern "C" int32_t usdbridge_prim_path(uint64_t prim_id, char *out, int32_t cap) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    if (!p->prim) return fail(USD_ERR_NOT_PRIM, "prim is invalid");
    return copy_out(std::string(p->prim.GetPath().GetText()), out, cap);
}

extern "C" int32_t usdbridge_prim_attr_count(uint64_t prim_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    if (!p->prim) return fail(USD_ERR_NOT_PRIM, "prim is invalid");
    if (p->attrs.size() > 0x7FFFFFFFULL)
        return fail(USD_ERR_OVERFLOW, "attribute count exceeds int32");
    return static_cast<int32_t>(p->attrs.size());
}

extern "C" int32_t usdbridge_prim_attr_name(uint64_t prim_id, int32_t index,
                                      char *out, int32_t cap) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    UsdAttribute *a = attr_at(p, index);
    if (!a) return fail(USD_ERR_RANGE, "attribute index out of range");
    return copy_out(std::string(a->GetName().GetText()), out, cap);
}

extern "C" int32_t usdbridge_prim_attr_type(uint64_t prim_id, int32_t index,
                                      char *out, int32_t cap) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    UsdAttribute *a = attr_at(p, index);
    if (!a) return fail(USD_ERR_RANGE, "attribute index out of range");
    return copy_out(attr_type_name(*a), out, cap);
}

extern "C" int32_t usdbridge_prim_attr_index(uint64_t prim_id, const char *name) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    if (!name) return -1;
    for (size_t i = 0; i < p->attrs.size(); ++i) {
        if (std::strcmp(p->attrs[i].GetName().GetText(), name) == 0) {
            return static_cast<int32_t>(i);
        }
    }
    return -1;
}

static int32_t read_float_attr(PrimHandle *p, int32_t index, float *out) {
    UsdAttribute *a = attr_at(p, index);
    if (!a) return fail(USD_ERR_RANGE, "attribute index out of range");
    if (!out) return fail(USD_ERR_BUFFER, "float output is null");
    std::string tn = attr_type_name(*a);
    sync_pools();
    if (tn == "float") {
        float v = 0.0f;
        if (a->Get(&v)) { sync_pools(); *out = v; return USD_OK; }
    } else if (tn == "double") {
        double v = 0.0;
        if (a->Get(&v)) { sync_pools(); *out = static_cast<float>(v); return USD_OK; }
    } else {
        return fail(USD_ERR_TYPE, "attribute " + std::string(a->GetName().GetText()) +
            " has type " + tn + ", not float/double");
    }
    sync_pools();
    return fail(USD_ERR_NO_VALUE, "attribute has no value: " + std::string(a->GetName().GetText()));
}

extern "C" int32_t usdbridge_prim_attr_float(uint64_t prim_id, int32_t index, float *out) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    return read_float_attr(p, index, out);
}

extern "C" int32_t usdbridge_prim_attr_double(uint64_t prim_id, int32_t index, double *out) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    UsdAttribute *a = attr_at(p, index);
    if (!a) return fail(USD_ERR_RANGE, "attribute index out of range");
    if (!out) return fail(USD_ERR_BUFFER, "double output is null");
    std::string tn = attr_type_name(*a);
    sync_pools();
    if (tn == "double") {
        double v = 0.0;
        if (a->Get(&v)) { sync_pools(); *out = v; return USD_OK; }
    } else if (tn == "float") {
        float v = 0.0f;
        if (a->Get(&v)) { sync_pools(); *out = static_cast<double>(v); return USD_OK; }
    } else {
        return fail(USD_ERR_TYPE, "attribute " + std::string(a->GetName().GetText()) +
            " has type " + tn + ", not double/float");
    }
    sync_pools();
    return fail(USD_ERR_NO_VALUE, "attribute has no value: " + std::string(a->GetName().GetText()));
}

extern "C" int32_t usdbridge_prim_attr_int(uint64_t prim_id, int32_t index, int32_t *out) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    UsdAttribute *a = attr_at(p, index);
    if (!a) return fail(USD_ERR_RANGE, "attribute index out of range");
    if (!out) return fail(USD_ERR_BUFFER, "int output is null");
    std::string tn = attr_type_name(*a);
    sync_pools();
    if (tn == "int") {
        int v = 0;
        if (a->Get(&v)) { sync_pools(); *out = static_cast<int32_t>(v); return USD_OK; }
    } else if (tn == "int64") {
        int64_t v = 0;
        if (a->Get(&v)) { sync_pools(); *out = static_cast<int32_t>(v); return USD_OK; }
    } else {
        return fail(USD_ERR_TYPE, "attribute " + std::string(a->GetName().GetText()) +
            " has type " + tn + ", not int/int64");
    }
    sync_pools();
    return fail(USD_ERR_NO_VALUE, "attribute has no value: " + std::string(a->GetName().GetText()));
}

extern "C" int32_t usdbridge_prim_attr_bool(uint64_t prim_id, int32_t index, int32_t *out) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    UsdAttribute *a = attr_at(p, index);
    if (!a) return fail(USD_ERR_RANGE, "attribute index out of range");
    if (!out) return fail(USD_ERR_BUFFER, "bool output is null");
    std::string tn = attr_type_name(*a);
    if (tn != "bool")
        return fail(USD_ERR_TYPE, "attribute " + std::string(a->GetName().GetText()) +
            " has type " + tn + ", not bool");
    sync_pools();
    bool v = false;
    bool got = a->Get(&v);
    sync_pools();
    if (!got) return fail(USD_ERR_NO_VALUE, "attribute has no value: " +
        std::string(a->GetName().GetText()));
    *out = v ? 1 : 0;
    return USD_OK;
}

extern "C" int32_t usdbridge_prim_attr_string(uint64_t prim_id, int32_t index,
                                        char *out, int32_t cap) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    UsdAttribute *a = attr_at(p, index);
    if (!a) return fail(USD_ERR_RANGE, "attribute index out of range");
    std::string tn = attr_type_name(*a);
    sync_pools();
    if (tn == "token") {
        TfToken t;
        bool got = a->Get(&t);
        sync_pools();
        if (!got) return fail(USD_ERR_NO_VALUE, "attribute has no value: " +
            std::string(a->GetName().GetText()));
        return copy_out(std::string(t.GetText()), out, cap);
    }
    if (tn == "string" || tn == "asset") {
        std::string s;
        bool got = a->Get(&s);
        sync_pools();
        if (!got) return fail(USD_ERR_NO_VALUE, "attribute has no value: " +
            std::string(a->GetName().GetText()));
        return copy_out(s, out, cap);
    }
    sync_pools();
    return fail(USD_ERR_TYPE, "attribute " + std::string(a->GetName().GetText()) +
        " has type " + tn + ", not token/string/asset");
}

// ---------------------------------------------------------------------------
// Mesh extraction.
// ---------------------------------------------------------------------------
static int32_t mesh_arrays(PrimHandle *p, VtArray<GfVec3f> *points,
                           VtArray<int> *counts, VtArray<int> *indices) {
    if (!p->prim) return fail(USD_ERR_NOT_PRIM, "prim is invalid");
    if (std::strcmp(p->prim.GetTypeName().GetText(), "Mesh") != 0) {
        return fail(USD_ERR_NOT_MESH, std::string("prim is not a Mesh: ") +
            p->prim.GetTypeName().GetText());
    }
    sync_pools();
    UsdAttribute pa = p->prim.GetAttribute(TfToken("points"));
    UsdAttribute ca = p->prim.GetAttribute(TfToken("faceVertexCounts"));
    UsdAttribute ia = p->prim.GetAttribute(TfToken("faceVertexIndices"));
    if (!pa || !ca || !ia) {
        return fail(USD_ERR_MESH_INVALID,
            "Mesh is missing points/faceVertexCounts/faceVertexIndices");
    }
    points->clear(); counts->clear(); indices->clear();
    if (!pa.Get(points) || !ca.Get(counts) || !ia.Get(indices)) {
        sync_pools();
        return fail(USD_ERR_MESH_INVALID, "Mesh attribute read failed");
    }
    sync_pools();
    int64_t sum = 0;
    for (int c : *counts) {
        if (c < 3) return fail(USD_ERR_MESH_INVALID, "face vertex count < 3");
        sum += c;
    }
    if (sum != static_cast<int64_t>(indices->size())) {
        return fail(USD_ERR_MESH_INVALID,
            "faceVertexCounts sum does not match faceVertexIndices length");
    }
    for (int idx : *indices) {
        if (idx < 0 || static_cast<size_t>(idx) >= points->size()) {
            return fail(USD_ERR_MESH_INVALID, "faceVertexIndices element out of range");
        }
    }
    return USD_OK;
}

extern "C" int32_t usdbridge_mesh_info(uint64_t prim_id, int32_t *out_points,
                                 int32_t *out_faces, int32_t *out_indices) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    VtArray<GfVec3f> points;
    VtArray<int> counts, indices;
    int32_t rc = mesh_arrays(p, &points, &counts, &indices);
    if (rc != USD_OK) return rc;
    if (points.size() > 0x7FFFFFFFULL || counts.size() > 0x7FFFFFFFULL ||
        indices.size() > 0x7FFFFFFFULL) {
        return fail(USD_ERR_OVERFLOW, "mesh array exceeds int32");
    }
    if (out_points) *out_points = static_cast<int32_t>(points.size());
    if (out_faces) *out_faces = static_cast<int32_t>(counts.size());
    if (out_indices) *out_indices = static_cast<int32_t>(indices.size());
    return USD_OK;
}

extern "C" int32_t usdbridge_mesh_face_counts(uint64_t prim_id, int32_t *out, int32_t cap_faces) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    VtArray<GfVec3f> points;
    VtArray<int> counts, indices;
    int32_t rc = mesh_arrays(p, &points, &counts, &indices);
    if (rc != USD_OK) return rc;
    if (!out || cap_faces < 0) return fail(USD_ERR_BUFFER, "face-count output is null/negative cap");
    if (static_cast<size_t>(cap_faces) < counts.size())
        return fail(USD_ERR_BUFFER, "face-count output capacity too small");
    for (size_t i = 0; i < counts.size(); ++i) out[i] = counts[i];
    sync_pools();
    return static_cast<int32_t>(counts.size());
}

extern "C" int32_t usdbridge_mesh_indices(uint64_t prim_id, int32_t *out, int32_t cap_indices) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    VtArray<GfVec3f> points;
    VtArray<int> counts, indices;
    int32_t rc = mesh_arrays(p, &points, &counts, &indices);
    if (rc != USD_OK) return rc;
    if (!out || cap_indices < 0) return fail(USD_ERR_BUFFER, "index output is null/negative cap");
    if (static_cast<size_t>(cap_indices) < indices.size())
        return fail(USD_ERR_BUFFER, "index output capacity too small");
    for (size_t i = 0; i < indices.size(); ++i) out[i] = indices[i];
    sync_pools();
    return static_cast<int32_t>(indices.size());
}

// ---------------------------------------------------------------------------
// Material surface subset.
// ---------------------------------------------------------------------------
static bool surface_shader_path(UsdPrim material, SdfPath *out) {
    sync_pools();
    UsdAttribute surf = material.GetAttribute(TfToken("outputs:surface"));
    if (!surf) return false;
    SdfPathVector conns;
    if (!surf.GetConnections(&conns)) { sync_pools(); return false; }
    sync_pools();
    if (conns.empty()) return false;
    *out = conns[0].GetPrimPath();
    return true;
}

extern "C" int32_t usdbridge_material_binding(uint64_t prim_id, char *out, int32_t cap) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    sync_pools();
    UsdRelationship rel = p->prim.GetRelationship(TfToken("material:binding"));
    if (!rel) return fail(USD_ERR_NO_BINDING, "no material:binding relationship");
    SdfPathVector targets;
    bool ok = rel.GetTargets(&targets);
    sync_pools();
    if (!ok || targets.empty())
        return fail(USD_ERR_NO_BINDING, "material:binding has no targets");
    return copy_out(std::string(targets[0].GetText()), out, cap);
}

extern "C" int32_t usdbridge_material_surface_shader(uint64_t prim_id, char *out, int32_t cap) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    if (!p->prim) return fail(USD_ERR_NOT_PRIM, "prim is invalid");
    SdfPath shader;
    if (!surface_shader_path(p->prim, &shader))
        return fail(USD_ERR_NO_SURFACE, "material has no connected outputs:surface shader");
    return copy_out(std::string(shader.GetText()), out, cap);
}

extern "C" uint64_t usdbridge_material_surface_shader_prim(uint64_t prim_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) {
        fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
        return 0;
    }
    auto stage_it = g_stages.find(p->stage_id);
    if (stage_it == g_stages.end()) {
        fail(USD_ERR_INVALID_HANDLE, "stage is no longer open");
        return 0;
    }
    SdfPath shader;
    if (!surface_shader_path(p->prim, &shader)) {
        fail(USD_ERR_NO_SURFACE, "material has no connected outputs:surface shader");
        return 0;
    }
    sync_pools();
    UsdPrim sp = stage_it->second.stage->GetPrimAtPath(shader);
    sync_pools();
    if (!sp) {
        fail(USD_ERR_NOT_PRIM, std::string("surface shader prim not found: ") + shader.GetText());
        return 0;
    }
    uint64_t id = g_next_id++;
    g_prims.emplace(id, PrimHandle{sp, sp.GetAuthoredAttributes(), p->stage_id});
    return id;
}

extern "C" int32_t usdbridge_material_shader_id(uint64_t prim_id, char *out, int32_t cap) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    UsdAttribute *a = attr_by_name(p, "info:id");
    if (!a) return fail(USD_ERR_ATTR_MISSING, "shader has no info:id");
    sync_pools();
    TfToken t;
    bool got = a->Get(&t);
    sync_pools();
    if (!got) return fail(USD_ERR_NO_VALUE, "info:id has no value");
    return copy_out(std::string(t.GetText()), out, cap);
}

extern "C" int32_t usdbridge_material_input_count(uint64_t prim_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    int32_t count = 0;
    for (const UsdAttribute &a : p->attrs) {
        if (std::strncmp(a.GetName().GetText(), "inputs:", 7) == 0) ++count;
    }
    return count;
}

extern "C" int32_t usdbridge_material_input_name(uint64_t prim_id, int32_t index,
                                           char *out, int32_t cap) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    UsdAttribute *a = input_at(p, index);
    if (!a) return fail(USD_ERR_RANGE, "material input index out of range");
    return copy_out(std::string(a->GetName().GetText()), out, cap);
}

extern "C" int32_t usdbridge_material_input_type(uint64_t prim_id, int32_t index,
                                           char *out, int32_t cap) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    UsdAttribute *a = input_at(p, index);
    if (!a) return fail(USD_ERR_RANGE, "material input index out of range");
    return copy_out(attr_type_name(*a), out, cap);
}

extern "C" int32_t usdbridge_material_input_connected(uint64_t prim_id, int32_t index) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    UsdAttribute *a = input_at(p, index);
    if (!a) return fail(USD_ERR_RANGE, "material input index out of range");
    sync_pools();
    SdfPathVector conns;
    bool ok = a->GetConnections(&conns);
    sync_pools();
    return ok && !conns.empty() ? 1 : 0;
}

extern "C" int32_t usdbridge_material_input_connection(uint64_t prim_id, int32_t index,
                                                 char *out, int32_t cap) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    UsdAttribute *a = input_at(p, index);
    if (!a) return fail(USD_ERR_RANGE, "material input index out of range");
    sync_pools();
    SdfPathVector conns;
    bool ok = a->GetConnections(&conns);
    sync_pools();
    if (!ok || conns.empty()) return copy_out(std::string(), out, cap);
    return copy_out(std::string(conns[0].GetText()), out, cap);
}

static int32_t input_float(PrimHandle *p, const char *name, float *out) {
    UsdAttribute *a = input_by_name(p, name);
    if (!a) return fail(USD_ERR_ATTR_MISSING, std::string("material input missing: ") + name);
    if (!out) return fail(USD_ERR_BUFFER, "float output is null");
    std::string tn = attr_type_name(*a);
    sync_pools();
    if (tn == "float") {
        float v = 0.0f;
        if (a->Get(&v)) { sync_pools(); *out = v; return USD_OK; }
    } else if (tn == "double") {
        double v = 0.0;
        if (a->Get(&v)) { sync_pools(); *out = static_cast<float>(v); return USD_OK; }
    } else {
        return fail(USD_ERR_TYPE, "material input " + std::string(name) +
            " has type " + tn + ", not float/double");
    }
    sync_pools();
    return fail(USD_ERR_NO_VALUE, std::string("material input has no value: ") + name);
}

extern "C" int32_t usdbridge_material_input_float(uint64_t prim_id, const char *name, float *out) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    return input_float(p, name, out);
}

extern "C" int32_t usdbridge_material_input_string(uint64_t prim_id, const char *name,
                                             char *out, int32_t cap) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    UsdAttribute *a = input_by_name(p, name);
    if (!a) return fail(USD_ERR_ATTR_MISSING, std::string("material input missing: ") + name);
    std::string tn = attr_type_name(*a);
    sync_pools();
    if (tn == "token") {
        TfToken t;
        bool got = a->Get(&t);
        sync_pools();
        if (!got) return fail(USD_ERR_NO_VALUE, std::string("material input has no value: ") + name);
        return copy_out(std::string(t.GetText()), out, cap);
    }
    if (tn == "string" || tn == "asset") {
        std::string s;
        bool got = a->Get(&s);
        sync_pools();
        if (!got) return fail(USD_ERR_NO_VALUE, std::string("material input has no value: ") + name);
        return copy_out(s, out, cap);
    }
    sync_pools();
    return fail(USD_ERR_TYPE, "material input " + std::string(name) +
        " has type " + tn + ", not token/string/asset");
}

// ---------------------------------------------------------------------------
// Time samples.
// ---------------------------------------------------------------------------
extern "C" int32_t usdbridge_attr_time_count(uint64_t prim_id, const char *name) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    UsdAttribute *a = attr_by_name(p, name);
    if (!a) return fail(USD_ERR_ATTR_MISSING, std::string("attribute missing: ") + (name ? name : ""));
    std::vector<double> times;
    sync_pools();
    a->GetTimeSamples(&times);
    sync_pools();
    if (times.size() > 0x7FFFFFFFULL) return fail(USD_ERR_OVERFLOW, "time sample count exceeds int32");
    return static_cast<int32_t>(times.size());
}

extern "C" int32_t usdbridge_attr_time_at(uint64_t prim_id, const char *name,
                                    int32_t index, double *out) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    UsdAttribute *a = attr_by_name(p, name);
    if (!a) return fail(USD_ERR_ATTR_MISSING, std::string("attribute missing: ") + (name ? name : ""));
    if (!out) return fail(USD_ERR_BUFFER, "time output is null");
    std::vector<double> times;
    sync_pools();
    a->GetTimeSamples(&times);
    sync_pools();
    if (index < 0 || static_cast<size_t>(index) >= times.size())
        return fail(USD_ERR_RANGE, "time sample index out of range");
    *out = times[static_cast<size_t>(index)];
    return USD_OK;
}

extern "C" int32_t usdbridge_attr_time_bounds(uint64_t prim_id, const char *name,
                                        double *out_min, double *out_max) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    UsdAttribute *a = attr_by_name(p, name);
    if (!a) return fail(USD_ERR_ATTR_MISSING, std::string("attribute missing: ") + (name ? name : ""));
    std::vector<double> times;
    sync_pools();
    a->GetTimeSamples(&times);
    sync_pools();
    if (times.empty()) return fail(USD_ERR_NO_VALUE, "attribute has no time samples");
    if (out_min) *out_min = times.front();
    if (out_max) *out_max = times.back();
    return USD_OK;
}

static int32_t attr_double_at(PrimHandle *p, const char *name, double time, double *out) {
    UsdAttribute *a = attr_by_name(p, name);
    if (!a) return fail(USD_ERR_ATTR_MISSING, std::string("attribute missing: ") + (name ? name : ""));
    if (!out) return fail(USD_ERR_BUFFER, "value output is null");
    std::string tn = attr_type_name(*a);
    sync_pools();
    if (tn == "double") {
        double v = 0.0;
        if (a->Get(&v, time)) { sync_pools(); *out = v; return USD_OK; }
    } else if (tn == "float") {
        float v = 0.0f;
        if (a->Get(&v, time)) { sync_pools(); *out = static_cast<double>(v); return USD_OK; }
    } else {
        return fail(USD_ERR_TYPE, "attribute " + std::string(name) +
            " has type " + tn + ", not double/float");
    }
    sync_pools();
    return fail(USD_ERR_NO_VALUE, std::string("attribute has no value: ") + (name ? name : ""));
}

extern "C" int32_t usdbridge_attr_double_at(uint64_t prim_id, const char *name,
                                      double time, double *out) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    return attr_double_at(p, name, time, out);
}

extern "C" int32_t usdbridge_attr_float_at(uint64_t prim_id, const char *name,
                                     double time, float *out) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    if (!out) return fail(USD_ERR_BUFFER, "float output is null");
    double v = 0.0;
    int32_t rc = attr_double_at(p, name, time, &v);
    if (rc != USD_OK) return rc;
    *out = static_cast<float>(v);
    return USD_OK;
}

extern "C" int32_t usdbridge_attr_float_sample(uint64_t prim_id, const char *name,
                                         int32_t index, float *out) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    UsdAttribute *a = attr_by_name(p, name);
    if (!a) return fail(USD_ERR_ATTR_MISSING, std::string("attribute missing: ") + (name ? name : ""));
    std::vector<double> times;
    sync_pools();
    a->GetTimeSamples(&times);
    sync_pools();
    if (index < 0 || static_cast<size_t>(index) >= times.size())
        return fail(USD_ERR_RANGE, "time sample index out of range");
    if (!out) return fail(USD_ERR_BUFFER, "float output is null");
    double v = 0.0;
    int32_t rc = attr_double_at(p, name, times[static_cast<size_t>(index)], &v);
    if (rc != USD_OK) return rc;
    *out = static_cast<float>(v);
    return USD_OK;
}

// ---------------------------------------------------------------------------
// Component ABI used by the XIOM wrappers.  The runtime's FFI trampoline is
// reliable for 3-argument (out in R8) and 4-argument-with-Float64 (out in R9)
// calls; packing index+component into one Int32 and splitting name-based vec3
// reads into x/y/z entry points keeps every call on those proven shapes.
// ---------------------------------------------------------------------------
extern "C" int32_t usdbridge_mesh_point_packed(uint64_t prim_id, int32_t packed,
                                               double *out) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    if (packed < 0) return fail(USD_ERR_RANGE, "point index/component out of range");
    int32_t point_index = packed / 3;
    int32_t component = packed % 3;
    VtArray<GfVec3f> points;
    VtArray<int> counts, indices;
    int32_t rc = mesh_arrays(p, &points, &counts, &indices);
    if (rc != USD_OK) return rc;
    if (!out) return fail(USD_ERR_BUFFER, "point output is null");
    if (static_cast<size_t>(point_index) >= points.size()) {
        return fail(USD_ERR_RANGE, "point index out of range");
    }
    *out = static_cast<double>(points[point_index][component]);
    sync_pools();
    return USD_OK;
}

extern "C" int32_t usdbridge_prim_attr_vec3_packed(uint64_t prim_id, int32_t packed,
                                                   double *out) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    if (packed < 0) return fail(USD_ERR_RANGE, "attribute index/component out of range");
    int32_t index = packed / 3;
    int32_t component = packed % 3;
    UsdAttribute *a = attr_at(p, index);
    if (!a) return fail(USD_ERR_RANGE, "attribute index out of range");
    if (!out) return fail(USD_ERR_BUFFER, "vec3 output is null");
    std::string tn = attr_type_name(*a);
    if (tn != "float3" && tn != "color3f" && tn != "normal3f" &&
        tn != "point3f" && tn != "vector3f") {
        return fail(USD_ERR_TYPE, "attribute " + std::string(a->GetName().GetText()) +
            " has type " + tn + ", not a float3/color3f family");
    }
    sync_pools();
    GfVec3f v(0.0f);
    bool got = a->Get(&v);
    sync_pools();
    if (!got) return fail(USD_ERR_NO_VALUE, "attribute has no value: " +
        std::string(a->GetName().GetText()));
    *out = static_cast<double>(v[component]);
    return USD_OK;
}

static int32_t material_vec3_named(PrimHandle *p, const char *name,
                                   int32_t component, double *out) {
    UsdAttribute *a = input_by_name(p, name);
    if (!a) return fail(USD_ERR_ATTR_MISSING, std::string("material input missing: ") + name);
    if (!out) return fail(USD_ERR_BUFFER, "vec3 output is null");
    std::string tn = attr_type_name(*a);
    if (tn != "float3" && tn != "color3f" && tn != "normal3f" &&
        tn != "point3f" && tn != "vector3f") {
        return fail(USD_ERR_TYPE, "material input " + std::string(name) +
            " has type " + tn + ", not a float3/color3f family");
    }
    sync_pools();
    GfVec3f v(0.0f);
    bool got = a->Get(&v);
    sync_pools();
    if (!got) return fail(USD_ERR_NO_VALUE, std::string("material input has no value: ") + name);
    *out = static_cast<double>(v[component]);
    return USD_OK;
}

extern "C" int32_t usdbridge_material_input_vec3_x(uint64_t prim_id, const char *name, double *out) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    return material_vec3_named(p, name, 0, out);
}

extern "C" int32_t usdbridge_material_input_vec3_y(uint64_t prim_id, const char *name, double *out) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    return material_vec3_named(p, name, 1, out);
}

extern "C" int32_t usdbridge_material_input_vec3_z(uint64_t prim_id, const char *name, double *out) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    return material_vec3_named(p, name, 2, out);
}

static int32_t attr_vec3_at_named(PrimHandle *p, const char *name, double time,
                                  int32_t component, double *out) {
    UsdAttribute *a = attr_by_name(p, name);
    if (!a) return fail(USD_ERR_ATTR_MISSING, std::string("attribute missing: ") + (name ? name : ""));
    if (!out) return fail(USD_ERR_BUFFER, "vec3 output is null");
    std::string tn = attr_type_name(*a);
    if (tn != "float3" && tn != "color3f" && tn != "normal3f" &&
        tn != "point3f" && tn != "vector3f") {
        return fail(USD_ERR_TYPE, "attribute " + std::string(name) +
            " has type " + tn + ", not a float3/color3f family");
    }
    sync_pools();
    GfVec3f v(0.0f);
    bool got = a->Get(&v, time);
    sync_pools();
    if (!got) return fail(USD_ERR_NO_VALUE, std::string("attribute has no value: ") + (name ? name : ""));
    *out = static_cast<double>(v[component]);
    return USD_OK;
}

extern "C" int32_t usdbridge_attr_vec3_at_x(uint64_t prim_id, const char *name, double time, double *out) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    return attr_vec3_at_named(p, name, time, 0, out);
}

extern "C" int32_t usdbridge_attr_vec3_at_y(uint64_t prim_id, const char *name, double time, double *out) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    return attr_vec3_at_named(p, name, time, 1, out);
}

extern "C" int32_t usdbridge_attr_vec3_at_z(uint64_t prim_id, const char *name, double time, double *out) {
    std::lock_guard<std::mutex> lock(g_mutex);
    clear_error();
    PrimHandle *p = nullptr;
    if (!prim_alive_locked(prim_id, &p)) return fail(USD_ERR_INVALID_HANDLE, "invalid prim handle");
    return attr_vec3_at_named(p, name, time, 2, out);
}




