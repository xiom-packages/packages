#!/usr/bin/env python3
# XIOM -- xiom.dxc full COM bridge generator (oracle: dxcapi.h).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# Licensed under the MIT or Apache-2.0 license, at your option.
#
# Parses the pinned dxcapi.h and emits, deterministically:
#   src/dxc_abi.h            local C++ ABI declarations (GUIDs, vtbl structs)
#   src/dxc_bridge.cpp       scalar-ABI C bridge, one stub per COM method
#   src/dxc_gen_support.xi   XIOM slot helpers
#   src/dxc_gen_runtime.xi   loader / instances / bound-method inventory
#   src/dxc_gen_<family>.xi  family-split typed wrappers (<600 lines each)
#   docs/DXC-INVENTORY.md    oracle inventory (interfaces/methods/slots/GUIDs)
#
# Usage:  python tools/gen_dxc.py [--header PATH] [--package-dir DIR] [--check]
# `--check` re-generates in memory and fails when committed output differs.
# Fails loudly on any header construct it does not understand: the committed
# output can never silently drift from the oracle.
import argparse
import hashlib
import os
import re
import sys

HEADER_DEFAULT = r"C:\VulkanSDK\1.4.350.0\Include\dxc\dxcapi.h"

UUID_RE = re.compile(r"CROSS_PLATFORM_UUIDOF\(\s*(\w+)\s*,\s*\"([0-9a-fA-F-]+)\"\s*\)")
CLSID_RE = re.compile(
    r"CLSID_SCOPE\s+const\s+(?:CLSID|GUID)\s+(\w+)\s*=\s*\{([^}]*\{[^}]*\}[^}]*)\}\s*;", re.S)
CLSID_ALIAS_RE = re.compile(r"CLSID_SCOPE\s+const\s+(?:CLSID|GUID)\s+(\w+)\s*=\s*(\w+)\s*;")
STRUCT_RE = re.compile(r"struct\s+(IDxc\w+)\s*(?::\s*public\s+(\w+))?\s*\{")
METHOD_RE = re.compile(r"virtual\s+(.*?)\s+(\w+)\s*\((.*?)\)\s*=\s*0\s*;", re.S)
PARAM_ANN_RE = re.compile(r"(?<![\w])_\w+(\([^)]*\))?\s*")


class GenError(Exception):
    pass


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", text)


def parse_guid_body(body):
    nums = re.findall(r"0x([0-9a-fA-F]+)", re.sub(r"\s+", " ", body))
    if len(nums) != 11:
        raise GenError("GUID literal with %d numbers" % len(nums))
    return (int(nums[0], 16), int(nums[1], 16), int(nums[2], 16),
            [int(n, 16) for n in nums[3:11]])


def parse_uuid_string(s):
    p = s.replace("-", "")
    if len(p) != 32:
        raise GenError("bad uuid: %s" % s)
    return (int(p[0:8], 16), int(p[8:12], 16), int(p[12:16], 16),
            [int(p[16 + i * 2:18 + i * 2], 16) for i in range(8)])


class Param(object):
    def __init__(self, name, kind, ctype):
        self.name, self.kind, self.ctype = name, kind, ctype


class Method(object):
    def __init__(self, iface, name, ret, params):
        self.iface, self.name, self.ret, self.params = iface, name, ret, params


class Iface(object):
    def __init__(self, name, base, uuid, uuid_str, decl_index):
        self.name, self.base, self.uuid, self.uuid_str = name, base, uuid, uuid_str
        self.decl_index = decl_index
        self.methods = []
        self.all_methods = []


def normalize_type(t):
    t = " ".join(t.split())
    t = re.sub("[ ]*[*][ ]*[*]", "**", t)
    return re.sub("([A-Za-z0-9_])([*])",
                  lambda m: m.group(1) + " " + m.group(2), t)


PARAM_KINDS = {
    "UINT32": "scalar32", "UINT": "scalar32", "BOOL": "scalar32",
    "SIZE_T": "scalar64", "REFIID": "refiid",
    "LPCWSTR": "str", "const WCHAR *": "str",
    "const DxcBuffer *": "buffer", "DxcBuffer *": "buffer",
    "const DxcDefine *": "defines", "DxcArgPair *": "argpairs",
    "BSTR *": "bstr_out", "LPWSTR *": "wstr_out", "char **": "cstr_out",
    "LPCWSTR *": "strarr", "const LPCWSTR *": "strarr", "LPCSTR *": "strarr_narrow",
    "UINT32 *": "scalar32_out", "BOOL *": "scalar32_out", "HRESULT *": "scalar32_out",
    "SIZE_T *": "scalar64_out", "void **": "voidptr_out", "IStream **": "iface_out",
    "IMalloc *": "iface_in", "DXC_OUT_KIND": "scalar32",
    "LPCVOID": "voidptr_in", "LPVOID *": "voidptr_out",
}

RET_KINDS = {
    "HRESULT": "status", "BOOL": "value32", "UINT32": "value32", "UINT": "value32",
    "DXC_OUT_KIND": "value32", "SIZE_T": "value64", "LPVOID": "copy",
    "LPCWSTR": "copy_wstr", "LPCSTR": "copy_cstr", "LPCWSTR *": "copy_strarr",
}


def classify_param(ctype):
    t = normalize_type(ctype)
    if t in PARAM_KINDS:
        return PARAM_KINDS[t]
    if re.match(r"^IDxc\w+ \*\*$", t):
        return "iface_out"
    if re.match(r"^IDxc\w+ \*$", t):
        return "iface_in"
    raise GenError("unclassified parameter type: %r" % t)


def classify_ret(ctype):
    t = re.sub(r"\bSTDMETHODCALLTYPE\b", "", normalize_type(ctype)).strip()
    if t in RET_KINDS:
        return RET_KINDS[t]
    raise GenError("unclassified return type: %r" % t)


def parse_params(raw):
    raw = raw.strip()
    if not raw or raw == "void":
        return []
    parts, depth, cur = [], 0, ""
    for ch in raw:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    out = []
    for p in parts:
        p = normalize_type(PARAM_ANN_RE.sub(" ", p))
        m = re.match(r"^(.*?)\s*([A-Za-z_]\w*)$", p)
        if not m:
            raise GenError("unparsable parameter: %r" % p)
        out.append(Param(m.group(2), classify_param(m.group(1)), m.group(1)))
    return out


def parse_header(text):
    clean = strip_comments(text)
    by_name = {}
    for m in UUID_RE.finditer(clean):
        by_name.setdefault(m.group(1), {}).update(
            uuid=parse_uuid_string(m.group(2)), uuid_str=m.group(2))
    order = []
    for m in STRUCT_RE.finditer(clean):
        name, base = m.group(1), m.group(2) or "IUnknown"
        body = clean[m.end():clean.find("};", m.end())]
        methods = [Method(name, mm.group(2), classify_ret(mm.group(1)),
                          parse_params(mm.group(3)))
                   for mm in METHOD_RE.finditer(body)]
        by_name.setdefault(name, {}).update(base=base, methods=methods)
        if name not in order:
            order.append(name)
    ifaces = []
    for idx, name in enumerate(order):
        info = by_name[name]
        if "uuid" not in info:
            raise GenError("interface without CROSS_PLATFORM_UUIDOF: %s" % name)
        iface = Iface(name, info["base"], info["uuid"], info["uuid_str"], idx)
        iface.methods = info["methods"]
        ifaces.append(iface)
        by_name[name]["__iface__"] = iface
    for iface in ifaces:
        chain, cur = [], iface
        while cur is not None:
            chain.append(cur)
            if cur.base in ("IUnknown", None):
                cur = None
            elif cur.base.startswith("IDxc") and cur.base in by_name:
                cur = by_name[cur.base]["__iface__"]
            else:
                raise GenError("unknown base %s of %s" % (cur.base, cur.name))
        methods = []
        for f in reversed(chain):
            methods.extend(f.methods)
        iface.all_methods = methods
    clsids = [(m.group(1), parse_guid_body(m.group(2)))
              for m in CLSID_RE.finditer(clean)]
    resolved = dict(clsids)
    for m in CLSID_ALIAS_RE.finditer(clean):
        if m.group(2) in resolved:
            clsids.append((m.group(1), resolved[m.group(2)]))
    seen, ordered = set(), []
    for name, g in clsids:
        if name not in seen:
            seen.add(name)
            ordered.append((name, g))
    return ifaces, ordered


def snake(name):
    s = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", name)
    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", s).lower()


def iface_key(name):
    return name[4:].lower()


def guid_ctor(g):
    d1, d2, d3, d4 = g
    return ("{0x%08x,0x%04x,0x%04x,{0x%02x,0x%02x,0x%02x,0x%02x,"
            "0x%02x,0x%02x,0x%02x,0x%02x}}" % (d1, d2, d3, d4[0], d4[1], d4[2],
                                               d4[3], d4[4], d4[5], d4[6], d4[7]))


WSTR_MAX, ARG_MAX, ARG_W_MAX = 4096, 64, 1024

# ============================ C: ABI header ==================================

ABI_TEMPLATE = r'''/* GENERATED by tools/gen_dxc.py -- do not edit by hand.
 * Local DXC COM ABI declarations mirrored from dxcapi.h (oracle:
 * @@BYTES@@ bytes, sha256 @@SHA@@).
 * The bridge includes NO DXC headers; this file IS the ABI.
 */
#ifndef XDXB_DXC_ABI_H
#define XDXB_DXC_ABI_H

#include <stdint.h>
#include <stddef.h>

#if defined(_WIN32)
#define XDXB_CALL __stdcall
#else
#define XDXB_CALL
#endif

#define XDXB_ORACLE_INTERFACES @@IFACES@@
#define XDXB_ORACLE_METHODS @@METHODS@@
#define XDXB_FREE_FUNCTIONS 2
#define XDXB_WSTR_MAX @@WSTR_MAX@@
#define XDXB_ARG_MAX @@ARG_MAX@@
#define XDXB_ARG_W_MAX @@ARG_W_MAX@@

typedef struct XdxbGuid {
  uint32_t d1; uint16_t d2; uint16_t d3; unsigned char d4[8];
} XdxbGuid;

typedef struct XdxbDxcBuffer {
  const void* Ptr; uint64_t Size; uint32_t Encoding;
} XdxbDxcBuffer;

typedef struct XdxbDxcDefine {
  const wchar_t* Name; const wchar_t* Value;
} XdxbDxcDefine;

typedef struct XdxbDxcArgPair {
  const wchar_t* pName; const wchar_t* pValue;
} XdxbDxcArgPair;

typedef int32_t (XDXB_CALL *XdxbDxcCreateInstanceProc)(
    const XdxbGuid* rclsid, const XdxbGuid* riid, void** ppv);
typedef int32_t (XDXB_CALL *XdxbDxcCreateInstance2Proc)(
    void* pMalloc, const XdxbGuid* rclsid, const XdxbGuid* riid, void** ppv);

typedef void (XDXB_CALL *XdxbFnPtr)(void);

typedef struct XdxbIUnknownVtbl {
  int32_t (XDXB_CALL *QueryInterface)(void* self, const XdxbGuid* riid, void** ppv);
  uint32_t (XDXB_CALL *AddRef)(void* self);
  uint32_t (XDXB_CALL *Release)(void* self);
} XdxbIUnknownVtbl;
@@VTBL@@
#endif /* XDXB_DXC_ABI_H */
'''

VTBL_TEMPLATE = r'''
/* @@NAME@@ : @@BASE@@ [@@UUID@@] -- @@COUNT@@ declared method(s) */
typedef struct Xdxb@@NAME@@Vtbl {
@@MEMBERS@@} Xdxb@@NAME@@Vtbl;
'''

IUNKNOWN_MEMBERS = (
    "  int32_t (XDXB_CALL *QueryInterface)(void* self, const XdxbGuid* riid, void** ppv);\n"
    "  uint32_t (XDXB_CALL *AddRef)(void* self);\n"
    "  uint32_t (XDXB_CALL *Release)(void* self);\n")

VTBL_PARAM_C = {
    "scalar32": "uint32_t", "scalar64": "uint64_t", "iface_in": "void*",
    "voidptr_in": "const void*",
    "refiid": "const XdxbGuid*", "str": "const wchar_t*",
    "buffer": "const XdxbDxcBuffer*", "defines": "const XdxbDxcDefine*",
    "argpairs": "XdxbDxcArgPair*", "bstr_out": "wchar_t**",
    "wstr_out": "wchar_t**", "cstr_out": "char**",
    "strarr": "const wchar_t**", "strarr_narrow": "const char**",
    "scalar32_out": "uint32_t*", "scalar64_out": "uint64_t*",
    "iface_out": "void**", "voidptr_out": "void**",
}

VTBL_RET_C = {
    "status": "int32_t", "value32": "uint32_t", "value64": "uint64_t",
    "copy": "void*", "copy_wstr": "const wchar_t*", "copy_cstr": "const char*",
    "copy_strarr": "const wchar_t**",
}


def emit_abi(ifaces, header_sha, header_bytes):
    blocks = []
    for iface in ifaces:
        # Every COM vtable starts with the three IUnknown slots; derived
        # interfaces then repeat the base declaration's slots in order.
        members = IUNKNOWN_MEMBERS
        for mm in iface.all_methods:
            args = ["void* self"] + [
                "%s %s" % (VTBL_PARAM_C[p.kind], p.name) for p in mm.params]
            members += "  %s (XDXB_CALL *%s)(%s);\n" % (
                VTBL_RET_C[mm.ret], mm.name, ", ".join(args))
        blocks.append(VTBL_TEMPLATE
                      .replace("@@NAME@@", iface.name)
                      .replace("@@BASE@@", iface.base)
                      .replace("@@UUID@@", iface.uuid_str)
                      .replace("@@COUNT@@", str(len(iface.methods)))
                      .replace("@@MEMBERS@@", members))
    return (ABI_TEMPLATE
            .replace("@@BYTES@@", str(header_bytes))
            .replace("@@SHA@@", header_sha)
            .replace("@@IFACES@@", str(len(ifaces)))
            .replace("@@METHODS@@", str(sum(len(i.methods) for i in ifaces)))
            .replace("@@WSTR_MAX@@", str(WSTR_MAX))
            .replace("@@ARG_MAX@@", str(ARG_MAX))
            .replace("@@ARG_W_MAX@@", str(ARG_W_MAX))
            .replace("@@VTBL@@", "".join(blocks)))

# ============================ C: bridge helpers ==============================

BRIDGE_HELPERS = r'''#include "dxc_abi.h"

#include <windows.h>
#include <stdint.h>
#include <string.h>
#include <wchar.h>
#include <stdio.h>

extern "C" {

/* ---- runtime state --------------------------------------------------- */

static HMODULE g_lib = 0;
static XdxbDxcCreateInstanceProc g_create = 0;
static XdxbDxcCreateInstance2Proc g_create2 = 0;
static int32_t g_resolved = 0;
static char g_error[1024];

static void xdxb_set_err(const char* msg)
{
  if (!msg) msg = "(no message)";
  strncpy(g_error, msg, sizeof(g_error) - 1);
  g_error[sizeof(g_error) - 1] = 0;
}

static void xdxb_set_err_hr(const char* what, int32_t hr)
{
  char buf[512];
  snprintf(buf, sizeof(buf), "%s failed (hr=0x%08X)", what, (unsigned)hr);
  xdxb_set_err(buf);
}

static void xdxb_put_u32(unsigned char* p, uint32_t v) { if (p) memcpy(p, &v, 4); }
static void xdxb_put_u64(unsigned char* p, uint64_t v) { if (p) memcpy(p, &v, 8); }

typedef struct XdxbNamedGuid { const char* name; XdxbGuid guid; } XdxbNamedGuid;

static const XdxbNamedGuid g_clsids[] = {
@@CLSIDS@@};

#define XDXB_CLSID_COUNT ((int32_t)(sizeof(g_clsids) / sizeof(g_clsids[0])))

static const XdxbNamedGuid g_iids[] = {
@@IIDS@@};

#define XDXB_IID_COUNT ((int32_t)(sizeof(g_iids) / sizeof(g_iids[0])))

/* ---- UTF-8 <-> UTF-16 (surrogate-pair aware) ------------------------- */

static int32_t xdxb_utf8_from_utf16(const wchar_t* w, int32_t wlen,
                                    unsigned char* dst, int32_t cap)
{
  int32_t i = 0;
  int32_t written = 0;
  if (!w) return 0;
  while (i < wlen) {
    uint32_t cp;
    uint16_t u = (uint16_t)w[i++];
    unsigned char tmp[4];
    int32_t n = 0;
    if (u >= 0xD800 && u <= 0xDBFF && i < wlen) {
      uint16_t lo = (uint16_t)w[i];
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        cp = 0x10000u + (((uint32_t)(u - 0xD800u)) << 10) + (uint32_t)(lo - 0xDC00u);
        i++;
      } else { cp = 0xFFFDu; }
    } else if (u >= 0xD800 && u <= 0xDFFF) {
      cp = 0xFFFDu;
    } else { cp = (uint32_t)u; }
    if (cp < 0x80u) { tmp[n++] = (unsigned char)cp; }
    else if (cp < 0x800u) {
      tmp[n++] = (unsigned char)(0xC0u | (cp >> 6));
      tmp[n++] = (unsigned char)(0x80u | (cp & 0x3Fu));
    } else if (cp < 0x10000u) {
      tmp[n++] = (unsigned char)(0xE0u | (cp >> 12));
      tmp[n++] = (unsigned char)(0x80u | ((cp >> 6) & 0x3Fu));
      tmp[n++] = (unsigned char)(0x80u | (cp & 0x3Fu));
    } else {
      tmp[n++] = (unsigned char)(0xF0u | (cp >> 18));
      tmp[n++] = (unsigned char)(0x80u | ((cp >> 12) & 0x3Fu));
      tmp[n++] = (unsigned char)(0x80u | ((cp >> 6) & 0x3Fu));
      tmp[n++] = (unsigned char)(0x80u | (cp & 0x3Fu));
    }
    if (dst && written + n <= cap) memcpy(dst + written, tmp, (size_t)n);
    written += n;
  }
  return written;
}

static int32_t xdxb_utf16_from_utf8(const unsigned char* s, int32_t len,
                                    wchar_t* dst, int32_t cap)
{
  int32_t i = 0;
  int32_t written = 0;
  if (!s || len < 0) { if (dst && cap > 0) dst[0] = 0; return 1; }
  while (i < len) {
    uint32_t cp = 0;
    unsigned char b = s[i++];
    int32_t extra = 0;
    if (b < 0x80u) { cp = b; }
    else if ((b & 0xE0u) == 0xC0u) { cp = b & 0x1Fu; extra = 1; }
    else if ((b & 0xF0u) == 0xE0u) { cp = b & 0x0Fu; extra = 2; }
    else if ((b & 0xF8u) == 0xF0u) { cp = b & 0x07u; extra = 3; }
    else { cp = 0xFFFDu; }
    while (extra > 0 && i < len) {
      unsigned char c = s[i];
      if ((c & 0xC0u) != 0x80u) break;
      cp = (cp << 6) | (c & 0x3Fu);
      i++; extra--;
    }
    if (extra > 0) cp = 0xFFFDu;
    if (cp >= 0x10000u) {
      uint32_t v = cp - 0x10000u;
      if (dst && written + 2 <= cap) {
        dst[written] = (wchar_t)(0xD800u + (v >> 10));
        dst[written + 1] = (wchar_t)(0xDC00u + (v & 0x3FFu));
      }
      written += 2;
    } else {
      if (dst && written + 1 <= cap) dst[written] = (wchar_t)cp;
      written += 1;
    }
  }
  if (dst) { if (written < cap) dst[written] = 0; else if (cap > 0) dst[cap - 1] = 0; }
  if (written + 1 > cap) return 0;
  return 1;
}

/* newline-separated entry splitting: offsets/lens of non-empty lines */
static int32_t xdxb_split_lines(const unsigned char* blob, int32_t len,
                                int32_t* offs, int32_t* lens, int32_t max)
{
  int32_t n = 0;
  int32_t start = 0;
  int32_t i;
  if (!blob || len < 0) return 0;
  for (i = 0; i <= len; i++) {
    if (i == len || blob[i] == (unsigned char)'\n') {
      int32_t l = i - start;
      if (l > 0) {
        if (n >= max) return n;
        offs[n] = start; lens[n] = l; n++;
      }
      start = i + 1;
    }
  }
  return n;
}

static int32_t xdxb_build_wide_args(const unsigned char* blob, int32_t len,
                                    int32_t want, wchar_t w[][XDXB_ARG_W_MAX],
                                    const wchar_t** out, int32_t max)
{
  int32_t offs[XDXB_ARG_MAX];
  int32_t lens[XDXB_ARG_MAX];
  int32_t n = xdxb_split_lines(blob, len, offs, lens, XDXB_ARG_MAX);
  int32_t i;
  if (want > 0 && want < n) n = want;
  if (n > max) return -1;
  for (i = 0; i < n; i++) {
    if (!xdxb_utf16_from_utf8(blob + offs[i], lens[i], w[i], XDXB_ARG_W_MAX)) return -1;
    out[i] = w[i];
  }
  return n;
}

static int32_t xdxb_build_narrow_args(const unsigned char* blob, int32_t len,
                                      int32_t want, char c[][XDXB_ARG_W_MAX],
                                      const char** out, int32_t max)
{
  int32_t offs[XDXB_ARG_MAX];
  int32_t lens[XDXB_ARG_MAX];
  int32_t n = xdxb_split_lines(blob, len, offs, lens, XDXB_ARG_MAX);
  int32_t i;
  if (want > 0 && want < n) n = want;
  if (n > max) return -1;
  for (i = 0; i < n; i++) {
    int32_t l = lens[i];
    if (l >= XDXB_ARG_W_MAX) return -1;
    if (l) memcpy(c[i], blob + offs[i], (size_t)l);
    c[i][l] = 0;
    out[i] = c[i];
  }
  return n;
}

/* `name=value` lines; value optional (empty). */
static int32_t xdxb_build_pairs(const unsigned char* blob, int32_t len,
                                int32_t want, wchar_t nw[][XDXB_ARG_W_MAX],
                                wchar_t vw[][XDXB_ARG_W_MAX], int32_t* has_value,
                                int32_t max)
{
  int32_t offs[XDXB_ARG_MAX];
  int32_t lens[XDXB_ARG_MAX];
  int32_t n = xdxb_split_lines(blob, len, offs, lens, XDXB_ARG_MAX);
  int32_t i;
  if (want > 0 && want < n) n = want;
  if (n > max) return -1;
  for (i = 0; i < n; i++) {
    const unsigned char* line = blob + offs[i];
    int32_t l = lens[i];
    int32_t eq = -1;
    int32_t k;
    for (k = 0; k < l; k++) { if (line[k] == (unsigned char)'=') { eq = k; break; } }
    if (eq < 0) eq = l;
    if (!xdxb_utf16_from_utf8(line, eq, nw[i], XDXB_ARG_W_MAX)) return -1;
    if (eq < l) {
      if (!xdxb_utf16_from_utf8(line + eq + 1, l - eq - 1, vw[i], XDXB_ARG_W_MAX)) return -1;
      has_value[i] = 1;
    } else {
      vw[i][0] = 0;
      has_value[i] = 0;
    }
  }
  return n;
}

static int32_t xdxb_copy_out_wstr(const wchar_t* w, unsigned char* dst, int32_t cap)
{
  if (!w) return 0;
  return xdxb_utf8_from_utf16(w, (int32_t)wcslen(w), dst, cap);
}

/* narrow string -> utf8 copy into an XIOM-owned slot; returns full length. */
static int32_t xdxb_copy_out_cstr(const char* s, unsigned char* dst, int32_t cap)
{
  int32_t full;
  uint32_t room, n;
  if (!s) return 0;
  full = (int32_t)strlen(s);
  room = (cap > 0) ? (uint32_t)cap : 0u;
  n = ((uint32_t)full > room) ? room : (uint32_t)full;
  if (dst && n) memcpy(dst, s, n);
  return full;
}

/* COM string frees via OS allocators resolved at runtime (no import libs). */
typedef void (XDXB_CALL *XdxbFreeProc)(void* p);
static XdxbFreeProc g_cotask_free = 0;
static XdxbFreeProc g_sys_free_bstr = 0;
static int32_t g_free_resolved = 0;

static void xdxb_resolve_frees(void)
{
  if (g_free_resolved) return;
  g_free_resolved = 1;
  { HMODULE ole = LoadLibraryA("ole32.dll");
    if (ole) g_cotask_free = (XdxbFreeProc)(void*)GetProcAddress(ole, "CoTaskMemFree"); }
  { HMODULE oa = LoadLibraryA("oleaut32.dll");
    if (oa) g_sys_free_bstr = (XdxbFreeProc)(void*)GetProcAddress(oa, "SysFreeString"); }
}

static void xdxb_free_com(void* p)
{
  xdxb_resolve_frees();
  if (g_cotask_free && p) g_cotask_free(p);
}

static void xdxb_free_bstr(void* p)
{
  xdxb_resolve_frees();
  if (g_sys_free_bstr && p) g_sys_free_bstr(p);
}

/* ---- loader ---------------------------------------------------------- */

int32_t __cdecl xdxb_load_named(const char* soname)
{
  if (g_lib) { FreeLibrary(g_lib); g_lib = 0; }
  g_create = 0; g_create2 = 0; g_resolved = 0;
  if (!soname || !soname[0]) { xdxb_set_err("empty soname"); return 1; }
  g_lib = LoadLibraryA(soname);
  if (!g_lib) { xdxb_set_err("LoadLibrary failed for the requested soname"); return 1; }
  g_create = (XdxbDxcCreateInstanceProc)(void*)GetProcAddress(g_lib, "DxcCreateInstance");
  if (g_create) g_resolved++;
  g_create2 = (XdxbDxcCreateInstance2Proc)(void*)GetProcAddress(g_lib, "DxcCreateInstance2");
  if (g_create2) g_resolved++;
  if (!g_create) {
    xdxb_set_err("missing export: DxcCreateInstance");
    FreeLibrary(g_lib); g_lib = 0;
    return 2;
  }
  return 0;
}

int32_t __cdecl xdxb_load(void) { return xdxb_load_named("dxcompiler.dll"); }

const char* __cdecl xdxb_error(void) { return g_error; }

int32_t __cdecl xdxb_free_function_count(void) { return XDXB_FREE_FUNCTIONS; }

int32_t __cdecl xdxb_resolved_free_functions(void) { return g_resolved; }

const char* __cdecl xdxb_free_function_name(int32_t i)
{
  if (i == 0) return "DxcCreateInstance";
  if (i == 1) return "DxcCreateInstance2";
  return 0;
}

void __cdecl xdxb_unload(void)
{
  if (g_lib) FreeLibrary(g_lib);
  g_lib = 0; g_create = 0; g_create2 = 0; g_resolved = 0;
}

/* ---- CLSID / IID lookups --------------------------------------------- */

int32_t __cdecl xdxb_clsid_count(void) { return XDXB_CLSID_COUNT; }

const char* __cdecl xdxb_clsid_name(int32_t i)
{
  if (i < 0 || i >= XDXB_CLSID_COUNT) return 0;
  return g_clsids[i].name;
}

int32_t __cdecl xdxb_clsid_index(const char* name)
{
  int32_t i;
  if (!name) return -1;
  for (i = 0; i < XDXB_CLSID_COUNT; i++) {
    if (strcmp(g_clsids[i].name, name) == 0) return i;
  }
  return -1;
}

int32_t __cdecl xdxb_iid_count(void) { return XDXB_IID_COUNT; }

const char* __cdecl xdxb_iid_name(int32_t i)
{
  if (i < 0 || i >= XDXB_IID_COUNT) return 0;
  return g_iids[i].name;
}

int32_t __cdecl xdxb_iid_index(const char* name)
{
  int32_t i;
  if (!name) return -1;
  for (i = 0; i < XDXB_IID_COUNT; i++) {
    if (strcmp(g_iids[i].name, name) == 0) return i;
  }
  return -1;
}

/* ---- instance / lifecycle helpers ------------------------------------ */

void* __cdecl xdxb_create_instance(int32_t clsid_idx, int32_t iid_idx)
{
  void* obj = 0;
  int32_t hr;
  if (!g_create) { xdxb_set_err("DxcCreateInstance not resolved"); return 0; }
  if (clsid_idx < 0 || clsid_idx >= XDXB_CLSID_COUNT ||
      iid_idx < 0 || iid_idx >= XDXB_IID_COUNT) {
    xdxb_set_err("create: index out of range");
    return 0;
  }
  hr = g_create(&g_clsids[clsid_idx].guid, &g_iids[iid_idx].guid, &obj);
  if (hr < 0) { xdxb_set_err_hr("DxcCreateInstance", hr); return 0; }
  return obj;
}

void* __cdecl xdxb_create_instance2(void* malloc_obj, int32_t clsid_idx, int32_t iid_idx)
{
  void* obj = 0;
  int32_t hr;
  if (!g_create2) { xdxb_set_err("DxcCreateInstance2 not resolved"); return 0; }
  if (clsid_idx < 0 || clsid_idx >= XDXB_CLSID_COUNT ||
      iid_idx < 0 || iid_idx >= XDXB_IID_COUNT) {
    xdxb_set_err("create2: index out of range");
    return 0;
  }
  hr = g_create2(malloc_obj, &g_clsids[clsid_idx].guid, &g_iids[iid_idx].guid, &obj);
  if (hr < 0) { xdxb_set_err_hr("DxcCreateInstance2", hr); return 0; }
  return obj;
}

void* __cdecl xdxb_query_interface(void* self, int32_t iid_idx)
{
  void* obj = 0;
  int32_t hr;
  if (!self) { xdxb_set_err("QueryInterface: null object"); return 0; }
  if (iid_idx < 0 || iid_idx >= XDXB_IID_COUNT) {
    xdxb_set_err("QueryInterface: iid index out of range");
    return 0;
  }
  hr = ((const XdxbIUnknownVtbl*)(*(void***)self))->QueryInterface(
      self, &g_iids[iid_idx].guid, &obj);
  if (hr < 0) { xdxb_set_err_hr("QueryInterface", hr); return 0; }
  return obj;
}

uint32_t __cdecl xdxb_addref(void* self)
{
  if (!self) return 0;
  return ((const XdxbIUnknownVtbl*)(*(void***)self))->AddRef(self);
}

uint32_t __cdecl xdxb_release(void* self)
{
  if (!self) return 0;
  return ((const XdxbIUnknownVtbl*)(*(void***)self))->Release(self);
}

/* Convenience creators (CLSID -> primary interface IID). */
@@CREATORS@@
'''

BRIDGE_TABLE = r'''
/* ---- bound-method table (one entry per dxcapi.h declared method) ---- */

typedef struct XdxbBoundMethod { const char* name; int32_t iface; XdxbFnPtr fn; } XdxbBoundMethod;

static const XdxbBoundMethod g_methods[] = {
@@METHODS@@};

int32_t __cdecl xdxb_method_count(void)
{
  return (int32_t)(sizeof(g_methods) / sizeof(g_methods[0]));
}

const char* __cdecl xdxb_method_name(int32_t i)
{
  if (i < 0 || i >= (int32_t)(sizeof(g_methods) / sizeof(g_methods[0]))) return 0;
  return g_methods[i].name;
}

int32_t __cdecl xdxb_method_interface(int32_t i)
{
  if (i < 0 || i >= (int32_t)(sizeof(g_methods) / sizeof(g_methods[0]))) return -1;
  return g_methods[i].iface;
}

int32_t __cdecl xdxb_interface_count(void) { return XDXB_ORACLE_INTERFACES; }

const char* __cdecl xdxb_interface_name(int32_t i)
{
  if (i < 0 || i >= XDXB_ORACLE_INTERFACES) return 0;
@@IFACE_NAMES@@
  return 0;
}

int32_t __cdecl xdxb_interface_method_count(int32_t i)
{
  int32_t n = 0;
  int32_t k;
  for (k = 0; k < (int32_t)(sizeof(g_methods) / sizeof(g_methods[0])); k++) {
    if (g_methods[k].iface == i) n++;
  }
  return n;
}
'''

# ======================= C: per-method stub emission =========================


def stub_parts(iface, m):
    """Return (args, prelude, call_args, post) for one bridge stub."""
    args = ["void* self"]
    prelude = []
    call_args = ["(void*)self"]
    post = []
    consumed = set()
    for idx, p in enumerate(m.params):
        if idx in consumed:
            continue
        n = p.name
        if p.kind == "scalar32":
            args.append("uint32_t %s" % n)
            call_args.append(n)
        elif p.kind == "voidptr_in":
            args.append("const void* %s" % n)
            call_args.append(n)
        elif p.kind == "scalar64":
            args.append("uint64_t %s" % n)
            call_args.append(n)
        elif p.kind == "iface_in":
            args.append("void* %s" % n)
            call_args.append(n)
        elif p.kind == "refiid":
            args.append("int32_t %s" % n)
            prelude.append(
                "  if (%s < 0 || %s >= XDXB_IID_COUNT) { xdxb_set_err("
                "\"%s::%s: iid index out of range\"); return 2; }"
                % (n, n, iface.name, m.name))
            call_args.append("&g_iids[%s].guid" % n)
        elif p.kind == "str":
            args += ["const unsigned char* %s_utf8" % n, "int32_t %s_utf8_len" % n]
            prelude.append("  static wchar_t w_%s[XDXB_WSTR_MAX];" % n)
            prelude.append(
                "  if (!xdxb_utf16_from_utf8(%s_utf8, %s_utf8_len, w_%s, XDXB_WSTR_MAX))"
                " { xdxb_set_err(\"%s::%s: %s conversion failed\"); return 2; }"
                % (n, n, n, iface.name, m.name, n))
            call_args.append("w_%s" % n)
        elif p.kind == "buffer":
            args += ["const void* %s_ptr" % n, "uint64_t %s_size" % n,
                     "uint32_t %s_encoding" % n]
            prelude.append("  XdxbDxcBuffer b_%s;" % n)
            prelude.append(
                "  b_%s.Ptr = %s_ptr; b_%s.Size = %s_size; b_%s.Encoding = %s_encoding;"
                % (n, n, n, n, n, n))
            call_args.append("&b_%s" % n)
        elif p.kind in ("defines", "argpairs"):
            count_name = m.params[idx + 1].name
            consumed.add(idx + 1)
            args += ["const unsigned char* %s_blob" % n, "int32_t %s_blob_len" % n,
                     "int32_t %s_count" % count_name]
            short = "def" if p.kind == "defines" else "pair"
            ctype = "XdxbDxcDefine" if p.kind == "defines" else "XdxbDxcArgPair"
            prelude += [
                "  static wchar_t %sn_%s[XDXB_ARG_MAX][XDXB_ARG_W_MAX];" % (short, n),
                "  static wchar_t %sv_%s[XDXB_ARG_MAX][XDXB_ARG_W_MAX];" % (short, n),
                "  static int32_t %sh_%s[XDXB_ARG_MAX];" % (short, n),
                "  static %s %s_%s[XDXB_ARG_MAX];" % (ctype, short + "s", n),
                "  int32_t %sn_%s_n;" % (short, n),
                "  %sn_%s_n = xdxb_build_pairs(%s_blob, %s_blob_len, %s_count,"
                " %sn_%s, %sv_%s, %sh_%s, XDXB_ARG_MAX);"
                % (short, n, n, n, count_name, short, n, short, n, short, n),
                "  if (%sn_%s_n < 0) { xdxb_set_err(\"%s::%s: %s marshalling failed\");"
                " return 2; }" % (short, n, iface.name, m.name, p.kind),
                "  { int32_t q; for (q = 0; q < %sn_%s_n; q++) {" % (short, n),
                ("    %ss_%s[q].Name = %sn_%s[q]; %ss_%s[q].Value = %sv_%s[q];"
                 % (short, n, short, n, short, n, short, n)) if p.kind == "defines"
                else ("    %ss_%s[q].pName = %sn_%s[q]; %ss_%s[q].pValue ="
                      " %sh_%s[q] ? %sv_%s[q] : 0;"
                      % (short, n, short, n, short, n, short, n, short, n)),
                "  } }",
            ]
            call_args += ["%ss_%s" % (short, n), "(uint32_t)%sn_%s_n" % (short, n)]
        elif p.kind in ("strarr", "strarr_narrow"):
            count_name = m.params[idx + 1].name
            consumed.add(idx + 1)
            args += ["const unsigned char* %s_blob" % n, "int32_t %s_blob_len" % n,
                     "int32_t %s_count" % count_name]
            if p.kind == "strarr":
                prelude += [
                    "  static wchar_t aw_%s[XDXB_ARG_MAX][XDXB_ARG_W_MAX];" % n,
                    "  static const wchar_t* ap_%s[XDXB_ARG_MAX];" % n,
                    "  int32_t an_%s;" % n,
                    "  an_%s = xdxb_build_wide_args(%s_blob, %s_blob_len, %s_count,"
                    " aw_%s, ap_%s, XDXB_ARG_MAX);" % (n, n, n, count_name, n, n),
                    "  if (an_%s < 0) { xdxb_set_err(\"%s::%s: argument vector"
                    " marshalling failed\"); return 2; }" % (n, iface.name, m.name),
                ]
                call_args += ["ap_%s" % n, "(uint32_t)an_%s" % n]
            else:
                prelude += [
                    "  static char ac_%s[XDXB_ARG_MAX][XDXB_ARG_W_MAX];" % n,
                    "  static const char* acp_%s[XDXB_ARG_MAX];" % n,
                    "  int32_t acn_%s;" % n,
                    "  acn_%s = xdxb_build_narrow_args(%s_blob, %s_blob_len, %s_count,"
                    " ac_%s, acp_%s, XDXB_ARG_MAX);" % (n, n, n, count_name, n, n),
                    "  if (acn_%s < 0) { xdxb_set_err(\"%s::%s: narrow argument vector"
                    " marshalling failed\"); return 2; }" % (n, iface.name, m.name),
                ]
                call_args += ["acp_%s" % n, "(uint32_t)acn_%s" % n]
        elif p.kind in ("scalar32_out", "scalar64_out"):
            args.append("unsigned char* %s" % n)
            ctype = "uint32_t" if p.kind == "scalar32_out" else "uint64_t"
            put = "xdxb_put_u32" if p.kind == "scalar32_out" else "xdxb_put_u64"
            prelude.append("  %s out_%s = 0;" % (ctype, n))
            call_args.append("(%s*)&out_%s" % (ctype, n))
            post.append("  if (%s) %s(%s, out_%s);" % (n, put, n, n))
        elif p.kind in ("iface_out", "voidptr_out"):
            args.append("unsigned char* %s" % n)
            prelude.append("  void* out_%s = 0;" % n)
            call_args.append("(void**)&out_%s" % n)
            post.append("  if (%s) xdxb_put_u64(%s, (uint64_t)(uintptr_t)out_%s);"
                        % (n, n, n))
        elif p.kind in ("bstr_out", "wstr_out", "cstr_out"):
            args += ["unsigned char* %s" % n, "int32_t %s_cap" % n,
                     "unsigned char* %s_len" % n]
            if p.kind == "cstr_out":
                prelude.append("  char* out_%s = 0;" % n)
                call_args.append("(char**)&out_%s" % n)
            else:
                prelude.append("  wchar_t* out_%s = 0;" % n)
                call_args.append("(wchar_t**)&out_%s" % n)
            copy_fn = "xdxb_copy_out_cstr" if p.kind == "cstr_out" else "xdxb_copy_out_wstr"
            post.append(
                "  if (%s) { int32_t full = %s(out_%s, %s, %s_cap);"
                " if (%s_len) xdxb_put_u32(%s_len, (uint32_t)full); }"
                % (n, copy_fn, n, n, n, n, n))
            if p.kind == "bstr_out":
                post.append("  if (out_%s) xdxb_free_bstr(out_%s);" % (n, n))
            else:
                post.append("  if (out_%s) xdxb_free_com(out_%s);" % (n, n))
        else:
            raise GenError("stub param kind %s" % p.kind)
    return args, prelude, call_args, post


def emit_stub(iface, m):
    args, prelude, call_args, post = stub_parts(iface, m)
    fn = "xdxb_%s_%s" % (iface_key(iface.name), snake(m.name))
    vt = "((const Xdxb%sVtbl*)(*(void***)self))" % iface.name
    L = ["/* %s::%s */" % (iface.name, m.name)]
    a = L.append
    if m.ret == "status":
        a("int32_t __cdecl %s(%s)" % (fn, ", ".join(args)))
        a("{")
        L.extend(prelude)
        a("  int32_t hr;")
        a("  if (!self) { xdxb_set_err(\"%s::%s: null object\"); return 2; }"
          % (iface.name, m.name))
        a("  hr = %s->%s(%s);" % (vt, m.name, ", ".join(call_args)))
        a("  if (hr < 0) { xdxb_set_err_hr(\"%s::%s\", hr); return 1; }"
          % (iface.name, m.name))
        L.extend(post)
        a("  return 0;")
        a("}")
    elif m.ret in ("value32", "value64"):
        ctype = "uint32_t" if m.ret == "value32" else "uint64_t"
        a("%s __cdecl %s(%s)" % (ctype, fn, ", ".join(args)))
        a("{")
        L.extend(prelude)
        a("  if (!self) { xdxb_set_err(\"%s::%s: null object\"); return 0; }"
          % (iface.name, m.name))
        a("  return (%s)%s->%s(%s);" % (ctype, vt, m.name, ", ".join(call_args)))
        a("}")
    elif m.ret == "copy":
        a("int32_t __cdecl %s(%s, unsigned char* out_data, int32_t out_cap,"
          " unsigned char* out_len)" % (fn, ", ".join(args)))
        a("{")
        L.extend(prelude)
        a("  const unsigned char* src;")
        a("  uint64_t size;")
        a("  if (!self) { xdxb_set_err(\"%s::%s: null object\"); return 2; }"
          % (iface.name, m.name))
        a("  src = (const unsigned char*)%s->%s(%s);" % (vt, m.name, ", ".join(call_args)))
        a("  size = (uint64_t)%s->GetBufferSize((void*)self);" % vt)
        a("  if (out_len) xdxb_put_u32(out_len, (uint32_t)size);")
        a("  if (out_data && out_cap > 0 && src) {")
        a("    uint32_t n = (size > (uint64_t)out_cap) ? (uint32_t)out_cap : (uint32_t)size;")
        a("    if (n) memcpy(out_data, src, n);")
        a("  }")
        L.extend(post)
        a("  return 0;")
        a("}")
    elif m.ret in ("copy_wstr", "copy_cstr"):
        a("int32_t __cdecl %s(%s, unsigned char* out_data, int32_t out_cap,"
          " unsigned char* out_len)" % (fn, ", ".join(args)))
        a("{")
        L.extend(prelude)
        a("  if (!self) { xdxb_set_err(\"%s::%s: null object\"); return 2; }"
          % (iface.name, m.name))
        if m.ret == "copy_wstr":
            a("  const wchar_t* src = %s->%s(%s);" % (vt, m.name, ", ".join(call_args)))
            a("  if (!src) { if (out_len) xdxb_put_u32(out_len, 0); return 0; }")
            a("  { int32_t full = xdxb_utf8_from_utf16(src, (int32_t)wcslen(src),"
              " out_data, out_cap);")
            a("    if (out_len) xdxb_put_u32(out_len, (uint32_t)full); }")
        else:
            a("  const char* src = %s->%s(%s);" % (vt, m.name, ", ".join(call_args)))
            a("  if (!src) { if (out_len) xdxb_put_u32(out_len, 0); return 0; }")
            a("  { int32_t full = (int32_t)strlen(src);")
            a("    uint32_t room = (out_cap > 0) ? (uint32_t)out_cap : 0u;")
            a("    uint32_t n = ((uint32_t)full > room) ? room : (uint32_t)full;")
            a("    if (out_data && n) memcpy(out_data, src, n);")
            a("    if (out_len) xdxb_put_u32(out_len, (uint32_t)full); }")
        L.extend(post)
        a("  return 0;")
        a("}")
    elif m.ret == "copy_strarr":
        a("int32_t __cdecl %s(%s, unsigned char* out_data, int32_t out_cap,"
          " unsigned char* out_len, unsigned char* out_count)" % (fn, ", ".join(args)))
        a("{")
        L.extend(prelude)
        a("  const wchar_t** arr;")
        a("  uint32_t n;")
        a("  uint32_t i;")
        a("  if (!self) { xdxb_set_err(\"%s::%s: null object\"); return 2; }"
          % (iface.name, m.name))
        a("  arr = %s->%s(%s);" % (vt, m.name, ", ".join(call_args)))
        a("  n = %s->GetCount((void*)self);" % vt)
        a("  if (out_count) xdxb_put_u32(out_count, n);")
        a("  { int32_t written = 0;")
        a("    for (i = 0; i < n && arr && arr[i]; i++) {")
        a("      int32_t need;")
        a("      if (i > 0) { if (out_data && written < out_cap)"
          " out_data[written] = (unsigned char)'\\n'; written++; }")
        a("      need = xdxb_utf8_from_utf16(arr[i], (int32_t)wcslen(arr[i]), 0, 0);")
        a("      if (out_data && written < out_cap) {")
        a("        int32_t room = out_cap - written;")
        a("        xdxb_utf8_from_utf16(arr[i], (int32_t)wcslen(arr[i]),"
          " out_data + written, room);")
        a("        written += (need < room) ? need : room;")
        a("      } else { written += need; }")
        a("    }")
        a("    if (out_len) xdxb_put_u32(out_len, (uint32_t)written); }")
        L.extend(post)
        a("  return 0;")
        a("}")
    else:
        raise GenError("stub return kind %s" % m.ret)
    L.append("")
    return "\n".join(L)


def emit_bridge(ifaces, clsids, header_sha, header_bytes):
    creators = []
    for name, cname, iid in [
            ("xdxb_create_compiler", "CLSID_DxcCompiler", "IDxcCompiler3"),
            ("xdxb_create_compiler_args", "CLSID_DxcCompilerArgs", "IDxcCompilerArgs"),
            ("xdxb_create_library", "CLSID_DxcLibrary", "IDxcLibrary"),
            ("xdxb_create_utils", "CLSID_DxcUtils", "IDxcUtils"),
            ("xdxb_create_linker", "CLSID_DxcLinker", "IDxcLinker"),
            ("xdxb_create_validator", "CLSID_DxcValidator", "IDxcValidator"),
            ("xdxb_create_assembler", "CLSID_DxcAssembler", "IDxcAssembler"),
            ("xdxb_create_container_reflection", "CLSID_DxcContainerReflection",
             "IDxcContainerReflection"),
            ("xdxb_create_optimizer", "CLSID_DxcOptimizer", "IDxcOptimizer"),
            ("xdxb_create_container_builder", "CLSID_DxcContainerBuilder",
             "IDxcContainerBuilder"),
            ("xdxb_create_pdb_utils", "CLSID_DxcPdbUtils", "IDxcPdbUtils2")]:
        creators.append(
            "void* __cdecl %s(void) { return xdxb_create_instance("
            "xdxb_clsid_index(\"%s\"), xdxb_iid_index(\"%s\")); }\n"
            % (name, cname, iid))
    helper = (BRIDGE_HELPERS
              .replace("@@CLSIDS@@", "".join(
                  '  { "%s", %s },\n' % (n, guid_ctor(g)) for n, g in clsids))
              .replace("@@IIDS@@", "".join(
                  '  { "%s", %s },\n' % (i.name, guid_ctor(i.uuid)) for i in ifaces))
              .replace("@@CREATORS@@", "".join(creators)))
    stubs = "".join(
        emit_stub(iface, m) for iface in ifaces for m in iface.methods)
    table = (BRIDGE_TABLE
             .replace("@@METHODS@@", "".join(
                 '  { "%s::%s", %d, (XdxbFnPtr)&xdxb_%s_%s },\n'
                 % (iface.name, m.name, iface.decl_index, iface_key(iface.name),
                    snake(m.name))
                 for iface in ifaces for m in iface.methods))
             .replace("@@IFACE_NAMES@@", "".join(
                 '  %sif (i == %d) return "%s";\n'
                 % ("else " if idx else "", idx, iface.name)
                 for idx, iface in enumerate(ifaces))))
    head = ("/* GENERATED by tools/gen_dxc.py -- do not edit by hand.\n"
            " *\n"
            " * xiom.dxc full COM bridge over the DXC API (dxcompiler.dll).\n"
            " * Oracle: dxcapi.h (%d bytes, sha256 %s).\n"
            " * %d interfaces, %d methods, %d CLSIDs; scalar ABI + XIOM-owned"
            " out slots.\n"
            " *\n"
            " * Discipline (B-11..B-20): the DLL is resolved at runtime"
            " (LoadLibraryA +\n"
            " * GetProcAddress). Objects cross the XIOM boundary as opaque Int"
            " handles;\n"
            " * every out-param is written into an XIOM-owned slot as"
            " little-endian\n"
            " * scalars or byte copies -- XIOM never reads through a foreign"
            " pointer.\n"
            " */\n"
            % (header_bytes, header_sha, len(ifaces),
               sum(len(i.methods) for i in ifaces), len(clsids)))
    return head + helper + "\n/* ---- interface methods (one stub per declared method) ---- */\n\n" + stubs + table + "\n} /* extern \"C\" */\n"


# ============================ XIOM: support module ===========================

XIOM_HEADER = """// XIOM -- @@TITLE@@
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// GENERATED by tools/gen_dxc.py -- do not edit by hand.
// Oracle: dxcapi.h (sha256 @@SHA@@).
//
// @@WHAT@@
"""

SUPPORT_MODULE = XIOM_HEADER + """
module xiom.dxc.gen_support

/// An XIOM-owned zeroed byte slot (one slot per out-param).
pub fn dxc_slot(n: Int) -> Vec[UInt8]
  requires: n > 0
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

/// Little-endian u32 read from an XIOM-owned slot (byte-indexed).
pub fn dxc_rd_u32(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 4
{
  let b0 = buf[0] as Int;
  let b1 = buf[1] as Int;
  let b2 = buf[2] as Int;
  let b3 = buf[3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

/// Little-endian u64 read from an XIOM-owned slot (byte-indexed).
pub fn dxc_rd_u64(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 8
{
  var lo_slot = dxc_slot(4);
  lo_slot[0] = buf[0];
  lo_slot[1] = buf[1];
  lo_slot[2] = buf[2];
  lo_slot[3] = buf[3];
  let lo = dxc_rd_u32(&lo_slot);
  var hi_slot = dxc_slot(4);
  hi_slot[0] = buf[4];
  hi_slot[1] = buf[5];
  hi_slot[2] = buf[6];
  hi_slot[3] = buf[7];
  let hi = dxc_rd_u32(&hi_slot);
  return lo | (hi << 32);
}

/// UTF-8 bytes of a Str captured into an XIOM-owned Vec.
pub fn dxc_bytes(text: Str) -> Vec[UInt8]
  requires: text.len() > 0
{
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < text.len() {
    v.push(text.byte_at(i));
    i = i + 1;
  }
  return v;
}

pub fn dxc_i2s(n: Int) -> Str
  requires: n >= 0
{
  if n == 0 { return "0"; }
  var num = n;
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  return out;
}
"""

# ============================ XIOM: runtime module ===========================

RUNTIME_EXTERNS = [
    "  fn xdxb_load_named(soname: *UInt8) -> Int32;",
    "  fn xdxb_load() -> Int32;",
    "  fn xdxb_error() -> *UInt8;",
    "  fn xdxb_unload();",
    "  fn xdxb_free_function_count() -> Int32;",
    "  fn xdxb_resolved_free_functions() -> Int32;",
    "  fn xdxb_free_function_name(i: Int32) -> *UInt8;",
    "  fn xdxb_clsid_count() -> Int32;",
    "  fn xdxb_clsid_name(i: Int32) -> *UInt8;",
    "  fn xdxb_clsid_index(name: *UInt8) -> Int32;",
    "  fn xdxb_iid_count() -> Int32;",
    "  fn xdxb_iid_name(i: Int32) -> *UInt8;",
    "  fn xdxb_iid_index(name: *UInt8) -> Int32;",
    "  fn xdxb_create_instance(clsid_idx: Int32, iid_idx: Int32) -> Int;",
    "  fn xdxb_create_instance2(malloc_obj: Int, clsid_idx: Int32, iid_idx: Int32) -> Int;",
    "  fn xdxb_create_compiler() -> Int;",
    "  fn xdxb_create_compiler_args() -> Int;",
    "  fn xdxb_create_library() -> Int;",
    "  fn xdxb_create_utils() -> Int;",
    "  fn xdxb_create_linker() -> Int;",
    "  fn xdxb_create_validator() -> Int;",
    "  fn xdxb_create_assembler() -> Int;",
    "  fn xdxb_create_container_reflection() -> Int;",
    "  fn xdxb_create_optimizer() -> Int;",
    "  fn xdxb_create_container_builder() -> Int;",
    "  fn xdxb_create_pdb_utils() -> Int;",
    "  fn xdxb_query_interface(obj: Int, iid_idx: Int32) -> Int;",
    "  fn xdxb_addref(obj: Int) -> Int32;",
    "  fn xdxb_release(obj: Int) -> Int32;",
    "  fn xdxb_method_count() -> Int32;",
    "  fn xdxb_method_name(i: Int32) -> *UInt8;",
    "  fn xdxb_method_interface(i: Int32) -> Int32;",
    "  fn xdxb_interface_count() -> Int32;",
    "  fn xdxb_interface_name(i: Int32) -> *UInt8;",
    "  fn xdxb_interface_method_count(i: Int32) -> Int32;",
]

RUNTIME_WRAPPERS = [
    # (fn name, params, ret, body expr, requires)
    ("dxc_load_named", "soname: Str", "Int",
     "unsafe { xdxb_load_named(soname.c_str()) as Int }", ["soname.len() > 0"]),
    ("dxc_load", "", "Int", "unsafe { xdxb_load() as Int }", []),
    ("dxc_error", "", "Str", "unsafe { Str::from_c_str(xdxb_error()) }", []),
    ("dxc_unload", "", "", "unsafe { xdxb_unload(); }", []),
    ("dxc_free_function_count", "", "Int",
     "unsafe { xdxb_free_function_count() as Int }", []),
    ("dxc_resolved_free_functions", "", "Int",
     "unsafe { xdxb_resolved_free_functions() as Int }", []),
    ("dxc_free_function_name", "i: Int", "Str",
     "unsafe { Str::from_c_str(xdxb_free_function_name(i as Int32)) }", ["i >= 0"]),
    ("dxc_clsid_count", "", "Int", "unsafe { xdxb_clsid_count() as Int }", []),
    ("dxc_clsid_name", "i: Int", "Str",
     "unsafe { Str::from_c_str(xdxb_clsid_name(i as Int32)) }", ["i >= 0"]),
    ("dxc_clsid_index", "name: Str", "Int",
     "unsafe { xdxb_clsid_index(name.c_str()) as Int }", ["name.len() > 0"]),
    ("dxc_iid_count", "", "Int", "unsafe { xdxb_iid_count() as Int }", []),
    ("dxc_iid_name", "i: Int", "Str",
     "unsafe { Str::from_c_str(xdxb_iid_name(i as Int32)) }", ["i >= 0"]),
    ("dxc_iid_index", "name: Str", "Int",
     "unsafe { xdxb_iid_index(name.c_str()) as Int }", ["name.len() > 0"]),
    ("dxc_create_instance", "clsid_idx: Int, iid_idx: Int", "Int",
     "unsafe { xdxb_create_instance(clsid_idx as Int32, iid_idx as Int32) }",
     ["clsid_idx >= 0", "iid_idx >= 0"]),
    ("dxc_create_instance2", "malloc_obj: Int, clsid_idx: Int, iid_idx: Int", "Int",
     "unsafe { xdxb_create_instance2(malloc_obj, clsid_idx as Int32, iid_idx as Int32) }",
     ["clsid_idx >= 0", "iid_idx >= 0"]),
    ("dxc_create_compiler", "", "Int", "unsafe { xdxb_create_compiler() }", []),
    ("dxc_create_compiler_args", "", "Int", "unsafe { xdxb_create_compiler_args() }", []),
    ("dxc_create_library", "", "Int", "unsafe { xdxb_create_library() }", []),
    ("dxc_create_utils", "", "Int", "unsafe { xdxb_create_utils() }", []),
    ("dxc_create_linker", "", "Int", "unsafe { xdxb_create_linker() }", []),
    ("dxc_create_validator", "", "Int", "unsafe { xdxb_create_validator() }", []),
    ("dxc_create_assembler", "", "Int", "unsafe { xdxb_create_assembler() }", []),
    ("dxc_create_container_reflection", "", "Int",
     "unsafe { xdxb_create_container_reflection() }", []),
    ("dxc_create_optimizer", "", "Int", "unsafe { xdxb_create_optimizer() }", []),
    ("dxc_create_container_builder", "", "Int",
     "unsafe { xdxb_create_container_builder() }", []),
    ("dxc_create_pdb_utils", "", "Int", "unsafe { xdxb_create_pdb_utils() }", []),
    ("dxc_query_interface", "obj: Int, iid_idx: Int", "Int",
     "unsafe { xdxb_query_interface(obj, iid_idx as Int32) }",
     ["obj != 0", "iid_idx >= 0"]),
    ("dxc_addref", "obj: Int", "Int", "unsafe { xdxb_addref(obj) as Int }",
     ["obj != 0"]),
    ("dxc_release", "obj: Int", "Int", "unsafe { xdxb_release(obj) as Int }",
     ["obj != 0"]),
    ("dxc_method_count", "", "Int", "unsafe { xdxb_method_count() as Int }", []),
    ("dxc_method_name", "i: Int", "Str",
     "unsafe { Str::from_c_str(xdxb_method_name(i as Int32)) }", ["i >= 0"]),
    ("dxc_method_interface", "i: Int", "Int",
     "unsafe { xdxb_method_interface(i as Int32) as Int }", ["i >= 0"]),
    ("dxc_interface_count", "", "Int", "unsafe { xdxb_interface_count() as Int }", []),
    ("dxc_interface_name", "i: Int", "Str",
     "unsafe { Str::from_c_str(xdxb_interface_name(i as Int32)) }", ["i >= 0"]),
    ("dxc_interface_method_count", "i: Int", "Int",
     "unsafe { xdxb_interface_method_count(i as Int32) as Int }", ["i >= 0"]),
]


def emit_runtime(ifaces, header_sha):
    total = sum(len(i.methods) for i in ifaces)
    L = []
    a = L.append
    a(XIOM_HEADER
      .replace("@@TITLE@@", "xiom.dxc generated runtime (loader / instances / bound surface)")
      .replace("@@SHA@@", header_sha)
      .replace("@@WHAT@@",
               "Runtime half of the generated surface: dynamic load of\n"
               "// dxcompiler.dll, DxcCreateInstance / DxcCreateInstance2, object\n"
               "// lifecycle (query/addref/release), CLSID/IID tables, and the\n"
               "// bound-method inventory (one bridge entry per dxcapi.h method)."))
    a("")
    a("module xiom.dxc.gen_runtime")
    a("")
    a("use xiom.dxc.gen_support;")
    a("")
    a("pub const DXC_ORACLE_INTERFACES: Int = %d;" % len(ifaces))
    a("pub const DXC_ORACLE_METHODS: Int = %d;" % total)
    a("pub const DXC_FREE_FUNCTIONS: Int = 2;")
    a("")
    a("pub const DXC_RC_OK: Int = 0;      // loader: resolved")
    a("pub const DXC_RC_ABSENT: Int = 1;  // loader: DLL not present (SKIP)")
    a("pub const DXC_RC_ABI: Int = 2;     // loader: present but missing DxcCreateInstance")
    a("")
    a('extern "C" {')
    L.extend(RUNTIME_EXTERNS)
    a("}")
    a("")
    for name, params, ret, body, requires in RUNTIME_WRAPPERS:
        a("pub fn %s(%s)%s" % (name, params, (" -> " + ret) if ret else ""))
        for r in requires:
            a("  requires: %s" % r)
        if not requires:
            a("  requires: true")
        a("{")
        a("  %s%s" % ("return " if ret else "", body))
        a("}")
        a("")
    a("/// Oracle per-interface method count (from the dxcapi.h parse).")
    a("pub fn dxc_oracle_iface_count(i: Int) -> Int")
    a("  requires: i >= 0")
    a("  requires: i < %d" % len(ifaces))
    a("{")
    for idx, iface in enumerate(ifaces):
        a("  %sif i == %d { return %d; }"
          % ("else " if idx else "", idx, len(iface.methods)))
    a("  return 0;")
    a("}")
    a("")
    return "\n".join(L)


# ============================ XIOM: family wrappers ==========================

def extern_decl_args(m):
    out = []
    consumed = set()
    for idx, p in enumerate(m.params):
        if idx in consumed:
            continue
        n = p.name
        if p.kind in ("scalar32",):
            out.append((n, "Int32"))
        elif p.kind == "voidptr_in":
            out.append((n, "*UInt8"))
        elif p.kind in ("scalar64", "iface_in", "refiid"):
            out.append((n, "Int"))
        elif p.kind == "str":
            out.append((n, "*UInt8"))
            out.append((n + "_utf8_len", "Int32"))
        elif p.kind == "buffer":
            out.append((n + "_ptr", "*UInt8"))
            out.append((n + "_size", "Int"))
            out.append((n + "_encoding", "Int32"))
        elif p.kind in ("defines", "argpairs", "strarr", "strarr_narrow"):
            consumed.add(idx + 1)
            out.append((n + "_blob", "*UInt8"))
            out.append((n + "_blob_len", "Int32"))
            out.append((m.params[idx + 1].name, "Int32"))
        elif p.kind in ("scalar32_out", "scalar64_out", "iface_out", "voidptr_out"):
            out.append((n, "*UInt8"))
        elif p.kind in ("bstr_out", "wstr_out", "cstr_out"):
            out.append((n, "*UInt8"))
            out.append((n + "_cap", "Int32"))
            out.append((n + "_len", "*UInt8"))
        else:
            raise GenError("extern arg kind %s" % p.kind)
    return out


def wrap_params(m):
    decl, call, consumed = [], [], set()
    for idx, p in enumerate(m.params):
        if idx in consumed:
            continue
        n = p.name
        if p.kind == "scalar32":
            decl.append("%s: Int32" % n)
            call.append(n)
        elif p.kind == "voidptr_in":
            decl.append("%s: &mut Vec[UInt8]" % n)
            call.append("%s.as_mut_ptr()" % n)
        elif p.kind in ("scalar64", "iface_in"):
            decl.append("%s: Int" % n)
            call.append(n)
        elif p.kind == "refiid":
            decl.append("%s: Int" % n)
            call.append("%s as Int32" % n)
        elif p.kind == "str":
            decl.append("%s: Str" % n)
            call += ["%s.c_str()" % n, "%s.len() as Int32" % n]
        elif p.kind == "buffer":
            decl += ["%s: &mut Vec[UInt8]" % n, "%s_size: Int" % n,
                     "%s_encoding: Int32" % n]
            call += ["%s.as_mut_ptr()" % n, "%s_size" % n, "%s_encoding" % n]
        elif p.kind in ("defines", "argpairs", "strarr", "strarr_narrow"):
            count_name = m.params[idx + 1].name
            consumed.add(idx + 1)
            decl += ["%s: Str" % n, "%s_count: Int" % count_name]
            call += ["%s.c_str()" % n, "%s.len() as Int32" % n,
                     "%s_count as Int32" % count_name]
        elif p.kind in ("scalar32_out", "scalar64_out", "iface_out", "voidptr_out"):
            decl.append("%s: &mut Vec[UInt8]" % n)
            call.append("%s.as_mut_ptr()" % n)
        elif p.kind in ("bstr_out", "wstr_out", "cstr_out"):
            decl += ["%s: &mut Vec[UInt8]" % n, "%s_len: &mut Vec[UInt8]" % n]
            call += ["%s.as_mut_ptr()" % n, "%s.len() as Int32" % n,
                     "%s_len.as_mut_ptr()" % n]
        else:
            raise GenError("wrapper param kind %s" % p.kind)
    return decl, call


def emit_wrapper(iface, m):
    key = "%s_%s" % (iface_key(iface.name), snake(m.name))
    fn, ext = "dxc_%s" % key, "xdxb_%s" % key
    decl, call = wrap_params(m)
    slot = 3 + (iface.all_methods.index(m) if m in iface.all_methods else 0)
    L = ["/// `%s::%s` (dxcapi.h vtable slot %d)." % (iface.name, m.name, slot)]
    a = L.append
    if m.ret in ("status", "value32", "value64"):
        params = ["obj: Int"] + decl
        a("pub fn %s(%s) -> Int" % (fn, ", ".join(params)))
        a("  requires: obj != 0")
        a("{")
        args = ["obj"] + call
        a("  return unsafe { %s(%s) as Int };" % (ext, ", ".join(args)))
        a("}")
    elif m.ret in ("copy", "copy_wstr", "copy_cstr"):
        params = ["obj: Int"] + decl + [
            "out_data: &mut Vec[UInt8]", "out_len: &mut Vec[UInt8]"]
        a("pub fn %s(%s) -> Int" % (fn, ", ".join(params)))
        a("  requires: obj != 0")
        a("  requires: out_data.len() > 0")
        a("{")
        args = ["obj"] + call + [
            "out_data.as_mut_ptr()", "out_data.len() as Int32",
            "out_len.as_mut_ptr()"]
        a("  return unsafe { %s(%s) as Int };" % (ext, ", ".join(args)))
        a("}")
    elif m.ret == "copy_strarr":
        params = ["obj: Int"] + decl + [
            "out_data: &mut Vec[UInt8]", "out_len: &mut Vec[UInt8]",
            "out_count: &mut Vec[UInt8]"]
        a("pub fn %s(%s) -> Int" % (fn, ", ".join(params)))
        a("  requires: obj != 0")
        a("  requires: out_data.len() > 0")
        a("{")
        args = ["obj"] + call + [
            "out_data.as_mut_ptr()", "out_data.len() as Int32",
            "out_len.as_mut_ptr()", "out_count.as_mut_ptr()"]
        a("  return unsafe { %s(%s) as Int };" % (ext, ", ".join(args)))
        a("}")
    else:
        raise GenError("wrapper return %s" % m.ret)
    a("")
    return "\n".join(L)


def emit_family(fam, iface_names, by_name, header_sha):
    ifaces = [by_name[n] for n in iface_names]
    L = []
    a = L.append
    total = sum(len(i.methods) for i in ifaces)
    a(XIOM_HEADER
      .replace("@@TITLE@@", "xiom.dxc generated wrappers: %s" % fam)
      .replace("@@SHA@@", header_sha)
      .replace("@@WHAT@@",
               "Generated typed wrappers over the DXC COM bridge (family-split:\n"
               "// %s). Out-params are caller-owned slots (&mut Vec[UInt8]) written\n"
               "// by C little-endian; handles are opaque Int values."
               % ", ".join(iface_names)))
    a("")
    a("module xiom.dxc.%s" % fam)
    a("")
    a("use xiom.dxc.gen_support;")
    a("")
    a('extern "C" {')
    for iface in ifaces:
        for m in iface.methods:
            name = "xdxb_%s_%s" % (iface_key(iface.name), snake(m.name))
            args = [("obj", "Int")] + extern_decl_args(m)
            if m.ret in ("copy", "copy_wstr", "copy_cstr"):
                args += [("out_data", "*UInt8"), ("out_cap", "Int32"),
                         ("out_len", "*UInt8")]
            elif m.ret == "copy_strarr":
                args += [("out_data", "*UInt8"), ("out_cap", "Int32"),
                         ("out_len", "*UInt8"), ("out_count", "*UInt8")]
            ret = "Int" if m.ret == "value64" else "Int32"
            a("  fn %s(%s) -> %s;" % (
                name, ", ".join("%s: %s" % (n, t) for n, t in args), ret))
    a("}")
    a("")
    for iface in ifaces:
        for m in iface.methods:
            a(emit_wrapper(iface, m))
    return "\n".join(L)


# ============================ inventory document =============================

FAMILIES = [
    ("gen_blob", "IDxcBlob / IDxcBlobEncoding / IDxcBlobWide / IDxcBlobUtf8",
     ["IDxcBlob", "IDxcBlobEncoding", "IDxcBlobWide", "IDxcBlobUtf8"]),
    ("gen_handler", "IDxcIncludeHandler / IDxcCompilerArgs",
     ["IDxcIncludeHandler", "IDxcCompilerArgs"]),
    ("gen_legacy", "IDxcLibrary / IDxcOperationResult / IDxcCompiler / IDxcCompiler2 / IDxcLinker",
     ["IDxcLibrary", "IDxcOperationResult", "IDxcCompiler", "IDxcCompiler2", "IDxcLinker"]),
    ("gen_utils", "IDxcUtils", ["IDxcUtils"]),
    ("gen_compiler3", "IDxcCompiler3", ["IDxcCompiler3"]),
    ("gen_result", "IDxcResult / IDxcExtraOutputs", ["IDxcResult", "IDxcExtraOutputs"]),
    ("gen_container", "IDxcContainerReflection / IDxcContainerBuilder / IDxcAssembler",
     ["IDxcContainerReflection", "IDxcContainerBuilder", "IDxcAssembler"]),
    ("gen_optimizer", "IDxcOptimizerPass / IDxcOptimizer",
     ["IDxcOptimizerPass", "IDxcOptimizer"]),
    ("gen_validator", "IDxcValidator / IDxcValidator2 / IDxcVersionInfo / IDxcVersionInfo2 / IDxcVersionInfo3",
     ["IDxcValidator", "IDxcValidator2", "IDxcVersionInfo", "IDxcVersionInfo2",
      "IDxcVersionInfo3"]),
    ("gen_pdb", "IDxcPdbUtils", ["IDxcPdbUtils"]),
    ("gen_pdb2", "IDxcPdbUtils2", ["IDxcPdbUtils2"]),
]


def emit_inventory(ifaces, clsids, header_path, header_sha, header_bytes):
    total = sum(len(i.methods) for i in ifaces)
    L = []
    a = L.append
    a("# xiom.dxc oracle inventory -- GENERATED by tools/gen_dxc.py")
    a("")
    a("Header: `%s`" % header_path)
    a("Size: %d bytes; SHA256: `%s`" % (header_bytes, header_sha))
    a("")
    a("- Interfaces (IDxc*): **%d**" % len(ifaces))
    a("- Declared COM methods (pure virtual, excluding IUnknown): **%d**" % total)
    a("- Free functions: **2** (`DxcCreateInstance`, `DxcCreateInstance2`)")
    a("- CLSIDs: **%d**; interface IIDs: **%d**" % (len(clsids), len(ifaces)))
    a("")
    a("Slot index = IUnknown 3 + position in the flattened vtable.")
    a("")
    for iface in ifaces:
        a("## %s  (%d method(s))" % (iface.name, len(iface.methods)))
        a("")
        a("IID `%s` -- base `%s`" % (iface.uuid_str, iface.base))
        a("")
        a("| slot | method | returns |")
        a("|------|--------|---------|")
        for m in iface.methods:
            a("| %d | `%s` | `%s` |" % (
                3 + iface.all_methods.index(m), m.name,
                re.sub(r"\bSTDMETHODCALLTYPE\b", "", m.ret).strip()))
        a("")
    a("## CLSIDs")
    a("")
    a("| CLSID | value |")
    a("|-------|-------|")
    seen = set()
    for name, g in clsids:
        if name in seen:
            continue
        seen.add(name)
        d1, d2, d3, d4 = g
        a("| `%s` | `{%08x-%04x-%04x-%s}` |" % (
            name, d1, d2, d3, "-".join("%02x%02x" % (d4[i], d4[i + 1])
                                       for i in range(0, 8, 2))))
    a("")
    return "\n".join(L) + "\n"


# ============================ main ===========================================

def build_all(header_path, pkg_dir):
    raw = open(header_path, "rb").read()
    header_bytes = len(raw)
    header_sha = hashlib.sha256(raw).hexdigest().upper()
    ifaces, clsids = parse_header(raw.decode("utf-8", "replace"))
    by_name = dict((i.name, i) for i in ifaces)
    out = {}
    out["src/dxc_abi.h"] = emit_abi(ifaces, header_sha, header_bytes)
    out["src/dxc_bridge.cpp"] = emit_bridge(ifaces, clsids, header_sha, header_bytes)
    out["src/dxc_gen_support.xi"] = (
        SUPPORT_MODULE
        .replace("@@TITLE@@", "xiom.dxc generated support (owned slots, little-endian reads)")
        .replace("@@SHA@@", header_sha)
        .replace("@@WHAT@@",
                 "Byte-level helpers for the generated wrappers. Every out-param is\n"
                 "// an XIOM-owned Vec[UInt8] slot; reads are byte-indexed little-endian\n"
                 "// (B-11..B-20 discipline -- no pointer arithmetic, no foreign reads)."))
    out["src/dxc_gen_runtime.xi"] = emit_runtime(ifaces, header_sha)
    used = set()
    for fam, title, names in FAMILIES:
        for n in names:
            if n not in by_name:
                raise GenError("family %s references unknown interface %s" % (fam, n))
            used.add(n)
        out["src/dxc_%s.xi" % fam] = emit_family(fam, names, by_name, header_sha)
    if used != set(by_name):
        raise GenError("families do not cover all interfaces: %s"
                       % sorted(set(by_name) - used))
    out["docs/DXC-INVENTORY.md"] = emit_inventory(
        ifaces, clsids, header_path, header_sha, header_bytes)
    stats = {
        "interfaces": len(ifaces),
        "methods": sum(len(i.methods) for i in ifaces),
        "clsids": len(clsids),
        "header_sha": header_sha,
        "header_bytes": header_bytes,
    }
    return out, stats


def main():
    ap = argparse.ArgumentParser(description="Generate the xiom.dxc bridge.")
    ap.add_argument("--header", default=HEADER_DEFAULT)
    ap.add_argument("--package-dir", default="")
    ap.add_argument("--check", action="store_true",
                    help="verify committed output matches a fresh generation")
    args = ap.parse_args()
    pkg = args.package_dir or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if not os.path.isdir(pkg):
        raise GenError("package dir not found: %s" % pkg)
    if not os.path.isfile(args.header):
        print("gen_dxc: header not found: %s" % args.header, file=sys.stderr)
        return 2
    try:
        files, stats = build_all(args.header, pkg)
    except GenError as e:
        print("gen_dxc: PARSE FAILURE: %s" % e, file=sys.stderr)
        return 1
    drift = []
    for rel, content in sorted(files.items()):
        path = os.path.join(pkg, rel.replace("/", os.sep))
        if args.check:
            old = open(path, "r", newline="").read() if os.path.isfile(path) else None
            if old != content:
                drift.append(rel)
        else:
            d = os.path.dirname(path)
            if d and not os.path.isdir(d):
                os.makedirs(d)
            with open(path, "w", newline="") as f:
                f.write(content)
            print("gen_dxc: wrote %s (%d bytes)" % (rel, len(content)))
    if args.check:
        if drift:
            print("gen_dxc: DRIFT detected in: %s" % ", ".join(drift), file=sys.stderr)
            return 1
        print("gen_dxc: check OK -- committed output matches the oracle parse")
    print("gen_dxc: %d interfaces, %d methods, %d CLSIDs (header sha256 %s)"
          % (stats["interfaces"], stats["methods"], stats["clsids"],
             stats["header_sha"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
