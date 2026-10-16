/* XIOM -- xiom.v4l: Video4Linux2 UAPI bridge (camera capture).
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * DESIGN: V4L2 is an ioctl(2) UAPI (include/uapi/linux/videodev2.h) with no
 * runtime library; the full constant/struct-layout surface is declared in
 * XIOM modules (src/consts.xi, src/cids.xi, src/layout.xi -- values
 * evaluated from the pinned kernel text), and this bridge owns the live
 * syscall path plus a small pinned-ABI kernel:
 *
 *   - every pinned fact (ioctl number, struct size, key field offset) is a
 *     literal copied from docs/repro/gen/v4l2_consts_dump.txt (gcc against
 *     the pinned headers); _Static_asserts re-derive them from the local
 *     struct definitions below, so a drifted field definition fails the
 *     Windows suite build, and the Linux repro build adds the generated
 *     3107-fact _Static_assert gate against the REAL pinned headers
 *     (compile with -DXV_USE_REAL_UAPI; see docs/repro/v4l2_abi_probe.c);
 *   - xv_abi_check() re-derives the ioctl encodings at runtime from the
 *     pinned dir/type/nr/size quadruples, giving the suite a real ABI stage
 *     on every host (classification V4L_ABI -> FAIL, never silent);
 *   - on Linux the live camera path is open/QUERYCAP/G_FMT/S_FMT/REQBUFS/
 *     QUERYBUF/mmap/QBUF/STREAMON/DQBUF/frame-copy/STREAMOFF/close;
 *   - on Windows (and any non-Linux host) devices cannot exist: the probe
 *     classifies ABSENT (SKIP) by construction.
 *
 * Contract (flat extern "C", called from module xiom.v4l):
 *   int         xv_platform(void)              0 = linux, 1 = no device access
 *   int         xv_probe_named(const char* dev_dir)
 *                                              0 ok / 1 absent / 2 abi
 *   int         xv_probe(void)                 scan "/dev"
 *   const char* xv_error(void)                 last error / classification text
 *   int         xv_last_errno(void)            errno captured by the last call
 *   int         xv_abi_fail_count(void)        failed pinned-fact count
 *   const char* xv_abi_fail_names(void)        comma-joined failed fact names
 *   int         xv_device_count(void)          devices found by the last probe
 *   const char* xv_device_path(int idx)        "/dev/videoN"
 *   int         xv_open(int idx)               handle > 0; 0 = failed
 *   int         xv_open_path(const char* path) handle > 0; 0 = failed
 *   void        xv_close(int h)
 *   int         xv_querycap(int h)             0 ok / -1 errno / -2 abi
 *   const char* xv_cap_driver(int h)           QUERYCAP strings (snapshot)
 *   const char* xv_cap_card(int h)
 *   const char* xv_cap_bus_info(int h)
 *   long long   xv_cap_version(int h)          KERNEL_VERSION(...)
 *   long long   xv_cap_capabilities(int h)     physical-device caps
 *   long long   xv_cap_device_caps(int h)      node caps (0 if CAP_DEVICE_CAPS unset)
 *   int         xv_g_fmt(int h)                VIDIOC_G_FMT (single-planar capture)
 *   int         xv_s_fmt(int h, w, hgt, fourcc, field)  VIDIOC_S_FMT, stores
 *                                              the negotiated result
 *   long long   xv_fmt_width(int h) ... xv_fmt_xfer_func(int h)   fmt snapshot
 *   int         xv_reqbufs(int h, count, type, memory)  VIDIOC_REQBUFS
 *   long long   xv_reqbufs_count(int h)        buffers granted by the driver
 *   int         xv_querybuf(int h, idx)        VIDIOC_QUERYBUF (length/offset)
 *   long long   xv_buf_length(int h, idx)
 *   long long   xv_buf_offset(int h, idx)
 *   int         xv_mmap(int h, idx)            mmap the QUERYBUF'd buffer; 0/-1
 *   long long   xv_buf_ptr(int h, idx)         mapped VA as opaque Int
 *   void        xv_munmap_all(int h)
 *   int         xv_qbuf(int h, idx)            VIDIOC_QBUF
 *   int         xv_dqbuf(int h, timeout_ms)    poll + VIDIOC_DQBUF; >=0 index,
 *                                              -1 errno, -3 timeout (EAGAIN)
 *   long long   xv_dq_flags(int h)             DQBUF snapshot
 *   long long   xv_dq_bytesused(int h)
 *   long long   xv_dq_sequence(int h)
 *   long long   xv_dq_timestamp_ns(int h)
 *   int         xv_frame_copy(int h, idx, dst, cap)  bytes copied (frame bytes)
 *   int         xv_streamon(int h, type)       VIDIOC_STREAMON; 0/-1
 *   int         xv_streamoff(int h, type)      VIDIOC_STREAMOFF; 0/-1
 *   void        xv_close_all(void)
 *
 * Sentinels: functional calls return 0 on success / -1 on failure with the
 * errno captured (xv_last_errno); -2 = ABI fault (a pinned fact failed at
 * runtime); -3 = DQBUF timeout (captured errno EAGAIN).  Pointers never
 * cross the boundary: device handles and mapped addresses are opaque Ints;
 * frame bytes move through caller-owned buffers via xv_frame_copy.
 */

#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#if defined(__linux__)
#  define XV_LINUX 1
#  include <fcntl.h>
#  include <poll.h>
#  include <sys/mman.h>
#  include <sys/ioctl.h>
#  include <unistd.h>
#  include <sys/stat.h>
#  include <time.h>
#else
#  define XV_LINUX 0
#endif

#if defined(XV_USE_REAL_UAPI)
#  include <sys/time.h>
#  include <linux/bits.h>
#  include <linux/videodev2.h>
#  include "v4l2_const_asserts.h"
#endif

/* =========================================================================
 * Pinned V4L2 UAPI facts (torvalds/linux v6.19 = 05f7e89ab9731565...).
 * Every literal below is from docs/repro/gen/v4l2_consts_dump.txt; the
 * _Static_asserts re-derive them from the definitions in this file, and the
 * Linux repro build re-checks them against the real pinned headers.
 * ========================================================================= */

#define XV_PIN_VIDIOC_QUERYCAP   0x80685600UL
#define XV_PIN_VIDIOC_G_FMT      0xC0D05604UL
#define XV_PIN_VIDIOC_S_FMT      0xC0D05605UL
#define XV_PIN_VIDIOC_REQBUFS    0xC0145608UL
#define XV_PIN_VIDIOC_QUERYBUF   0xC0585609UL
#define XV_PIN_VIDIOC_QBUF       0xC058560FUL
#define XV_PIN_VIDIOC_DQBUF      0xC0585611UL
#define XV_PIN_VIDIOC_STREAMON   0x40045612UL
#define XV_PIN_VIDIOC_STREAMOFF  0x40045613UL

#define XV_PIN_V4L2_BUF_TYPE_VIDEO_CAPTURE 1
#define XV_PIN_V4L2_MEMORY_MMAP            1
#define XV_PIN_V4L2_FIELD_ANY              0

#define XV_PIN_SZ_CAPABILITY      104
#define XV_PIN_SZ_PIX_FORMAT      48
#define XV_PIN_SZ_FORMAT          208
#define XV_PIN_SZ_REQUESTBUFFERS  20
#define XV_PIN_SZ_BUFFER          88
#define XV_PIN_SZ_TIMECODE        16
#define XV_PIN_SZ_TIMEVAL         16

#define XV_PIN_OFF_CAP_DRIVER       0
#define XV_PIN_OFF_CAP_CARD         16
#define XV_PIN_OFF_CAP_BUS_INFO     48
#define XV_PIN_OFF_CAP_VERSION      80
#define XV_PIN_OFF_CAP_CAPABILITIES 84
#define XV_PIN_OFF_CAP_DEVICE_CAPS  88
#define XV_PIN_OFF_FMT_TYPE         0
#define XV_PIN_OFF_FMT_FMT          8
#define XV_PIN_OFF_PIX_WIDTH        0
#define XV_PIN_OFF_PIX_HEIGHT       4
#define XV_PIN_OFF_PIX_PIXELFORMAT  8
#define XV_PIN_OFF_PIX_FIELD        12
#define XV_PIN_OFF_PIX_BYTESPERLINE 16
#define XV_PIN_OFF_PIX_SIZEIMAGE    20
#define XV_PIN_OFF_PIX_COLORSPACE   24
#define XV_PIN_OFF_PIX_PRIV         28
#define XV_PIN_OFF_PIX_FLAGS        32
#define XV_PIN_OFF_PIX_YCBCR_ENC    36
#define XV_PIN_OFF_PIX_QUANTIZATION 40
#define XV_PIN_OFF_PIX_XFER_FUNC    44
#define XV_PIN_OFF_RB_COUNT         0
#define XV_PIN_OFF_RB_TYPE          4
#define XV_PIN_OFF_RB_MEMORY        8
#define XV_PIN_OFF_BUF_INDEX        0
#define XV_PIN_OFF_BUF_TYPE         4
#define XV_PIN_OFF_BUF_BYTESUSED    8
#define XV_PIN_OFF_BUF_FLAGS        12
#define XV_PIN_OFF_BUF_FIELD        16
#define XV_PIN_OFF_BUF_TIMESTAMP    24
#define XV_PIN_OFF_BUF_TIMECODE     40
#define XV_PIN_OFF_BUF_SEQUENCE     56
#define XV_PIN_OFF_BUF_MEMORY       60
#define XV_PIN_OFF_BUF_M            64
#define XV_PIN_OFF_BUF_LENGTH       72
#define XV_PIN_OFF_BUF_RESERVED2    76

/* ioctl encoding helper (asm-generic <linux/ioctl.h> semantics; the pinned
 * constants above are the reference values xv_abi_check() re-derives). */
#define XV_IOC_NRBITS    8
#define XV_IOC_TYPEBITS  8
#define XV_IOC_SIZEBITS  14
#define XV_IOC_DIRBITS   2
#define XV_IOC_NRSHIFT   0
#define XV_IOC_TYPESHIFT (XV_IOC_NRSHIFT + XV_IOC_NRBITS)
#define XV_IOC_SIZESHIFT (XV_IOC_TYPESHIFT + XV_IOC_TYPEBITS)
#define XV_IOC_DIRSHIFT  (XV_IOC_SIZESHIFT + XV_IOC_SIZEBITS)
#define XV_IOC_NONE  0U
#define XV_IOC_WRITE 1U
#define XV_IOC_READ  2U
#define XV_IOC(dir_, type_, nr_, size_) \
  ((unsigned long)(((dir_) << XV_IOC_DIRSHIFT) | ((type_) << XV_IOC_TYPESHIFT) | \
                   ((nr_) << XV_IOC_NRSHIFT) | ((size_) << XV_IOC_SIZESHIFT)))

/* =========================================================================
 * Pinned struct definitions (LP64; explicit-width types keep every host ABI
 * identical so the offsets hold on Windows too).
 * ========================================================================= */

typedef struct XV_timeval {
  int64_t tv_sec;
  int64_t tv_usec;
} XV_timeval;

typedef struct XV_timecode {
  uint32_t type;
  uint32_t flags;
  uint8_t  frames;
  uint8_t  seconds;
  uint8_t  minutes;
  uint8_t  hours;
  uint8_t  userbits[4];
} XV_timecode;

typedef struct XV_capability {
  uint8_t  driver[16];
  uint8_t  card[32];
  uint8_t  bus_info[32];
  uint32_t version;
  uint32_t capabilities;
  uint32_t device_caps;
  uint32_t reserved[3];
} XV_capability;

typedef struct XV_pix_format {
  uint32_t width;
  uint32_t height;
  uint32_t pixelformat;
  uint32_t field;
  uint32_t bytesperline;
  uint32_t sizeimage;
  uint32_t colorspace;
  uint32_t priv;
  uint32_t flags;
  union {
    uint32_t ycbcr_enc;
    uint32_t hsv_enc;
  };
  uint32_t quantization;
  uint32_t xfer_func;
} XV_pix_format;

typedef struct XV_format {
  uint32_t type;
  union {
    XV_pix_format pix;
    uint64_t      _align_u64; /* the real union holds pointers: 8-byte aligned */
    uint8_t       _pad[200];  /* pinned union size: 208 - 8 (fmt offset) */
  } fmt;
} XV_format;

typedef struct XV_requestbuffers {
  uint32_t count;
  uint32_t type;
  uint32_t memory;
  uint32_t capabilities;
  uint8_t  flags;
  uint8_t  reserved[3];
} XV_requestbuffers;

typedef struct XV_buffer {
  uint32_t index;
  uint32_t type;
  uint32_t bytesused;
  uint32_t flags;
  uint32_t field;
  XV_timeval timestamp;
  XV_timecode timecode;
  uint32_t sequence;
  uint32_t memory;
  union {
    uint32_t offset;
    uint64_t userptr;
    void*    planes;
    int32_t  fd;
  } m;
  uint32_t length;
  uint32_t reserved2;
  union {
    int32_t  request_fd;
    uint32_t reserved;
  } req;
} XV_buffer;

_Static_assert(sizeof(XV_timeval) == XV_PIN_SZ_TIMEVAL, "XV_timeval");
_Static_assert(sizeof(XV_timecode) == XV_PIN_SZ_TIMECODE, "XV_timecode");
_Static_assert(sizeof(XV_capability) == XV_PIN_SZ_CAPABILITY, "XV_capability");
_Static_assert(sizeof(XV_pix_format) == XV_PIN_SZ_PIX_FORMAT, "XV_pix_format");
_Static_assert(sizeof(XV_format) == XV_PIN_SZ_FORMAT, "XV_format");
_Static_assert(sizeof(XV_requestbuffers) == XV_PIN_SZ_REQUESTBUFFERS, "XV_requestbuffers");
_Static_assert(sizeof(XV_buffer) == XV_PIN_SZ_BUFFER, "XV_buffer");
_Static_assert(offsetof(XV_format, fmt) == XV_PIN_OFF_FMT_FMT, "XV_format.fmt");
_Static_assert(offsetof(XV_pix_format, xfer_func) == XV_PIN_OFF_PIX_XFER_FUNC, "XV_pix_format.xfer_func");
_Static_assert(offsetof(XV_requestbuffers, flags) == XV_PIN_OFF_RB_COUNT + 16, "XV_requestbuffers.flags");
_Static_assert(offsetof(XV_buffer, timestamp) == XV_PIN_OFF_BUF_TIMESTAMP, "XV_buffer.timestamp");
_Static_assert(offsetof(XV_buffer, m) == XV_PIN_OFF_BUF_M, "XV_buffer.m");
_Static_assert(offsetof(XV_buffer, length) == XV_PIN_OFF_BUF_LENGTH, "XV_buffer.length");

/* =========================================================================
 * Bridge state
 * ========================================================================= */

#define XV_MAX_DEVS    64
#define XV_MAX_HANDLES 8
#define XV_MAX_BUFS    32 /* VIDEO_MAX_FRAME at the pin */

typedef struct XV_buf_slot {
  int      used;
  uint32_t length;   /* QUERYBUF length */
  uint32_t offset;   /* QUERYBUF m.offset */
  void*    addr;     /* mmap address (NULL when not mapped) */
} XV_buf_slot;

typedef struct XV_dev_slot {
  int      open;
  int      fd;
  char     path[160];
  XV_capability       cap;
  XV_format           fmt;
  XV_requestbuffers   rb;
  XV_buf_slot         bufs[XV_MAX_BUFS];
  int      nbufs;         /* buffers granted by REQBUFS (clamped) */
  int      dq_index;      /* last DQBUF index (-1 none) */
  uint32_t dq_flags;
  uint32_t dq_bytesused;
  uint32_t dq_sequence;
  int64_t  dq_ts_ns;
} XV_dev_slot;

static XV_dev_slot g_devs[XV_MAX_HANDLES];
static char g_dev_paths[XV_MAX_DEVS][160];
static int  g_dev_count = 0;
static char g_error[1200] = {0};
static char g_abi_fail[1024] = {0};
static int  g_last_errno = 0;

static void xv_set_error(const char* msg) {
  snprintf(g_error, sizeof(g_error), "%s", msg);
}

#if XV_LINUX
static void xv_set_errno_msg(const char* what) {
  g_last_errno = errno;
  snprintf(g_error, sizeof(g_error), "%s: errno %d", what, errno);
}

static int xv_rc_errno(const char* what) {
  xv_set_errno_msg(what);
  return -1;
}
#endif

/* =========================================================================
 * ABI self-check: re-derive every pinned ioctl/size/offset fact at runtime.
 * ========================================================================= */

static void xv_abi_add_fail(const char* name) {
  size_t used = strlen(g_abi_fail);
  snprintf(g_abi_fail + used, sizeof(g_abi_fail) - used, "%s%s", used ? "," : "", name);
}

static int xv_abi_check(void) {
  int fails = 0;
  g_abi_fail[0] = 0;

#define XV_CHECK(name, have, want)      \
  do {                                  \
    if ((unsigned long)(have) != (unsigned long)(want)) { \
      xv_abi_add_fail(name);            \
      fails++;                          \
    }                                   \
  } while (0)

  /* ioctl encodings, re-derived from the pinned dir/type/nr/size quadruples:
   * QUERYCAP  (_IOR('V',  0, cap))
   * G_FMT     (_IOWR('V', 4, fmt))        S_FMT (_IOWR('V', 5, fmt))
   * REQBUFS   (_IOWR('V', 8, reqbufs))
   * QUERYBUF  (_IOWR('V', 9, buf))        QBUF  (_IOWR('V', 15, buf))
   * DQBUF     (_IOWR('V', 17, buf))
   * STREAMON  (_IOW('V', 18, int))        STREAMOFF (_IOW('V', 19, int))
   */
  XV_CHECK("VIDIOC_QUERYCAP", XV_IOC(XV_IOC_READ, 'V', 0, XV_PIN_SZ_CAPABILITY), XV_PIN_VIDIOC_QUERYCAP);
  XV_CHECK("VIDIOC_G_FMT", XV_IOC(XV_IOC_READ | XV_IOC_WRITE, 'V', 4, XV_PIN_SZ_FORMAT), XV_PIN_VIDIOC_G_FMT);
  XV_CHECK("VIDIOC_S_FMT", XV_IOC(XV_IOC_READ | XV_IOC_WRITE, 'V', 5, XV_PIN_SZ_FORMAT), XV_PIN_VIDIOC_S_FMT);
  XV_CHECK("VIDIOC_REQBUFS", XV_IOC(XV_IOC_READ | XV_IOC_WRITE, 'V', 8, XV_PIN_SZ_REQUESTBUFFERS), XV_PIN_VIDIOC_REQBUFS);
  XV_CHECK("VIDIOC_QUERYBUF", XV_IOC(XV_IOC_READ | XV_IOC_WRITE, 'V', 9, XV_PIN_SZ_BUFFER), XV_PIN_VIDIOC_QUERYBUF);
  XV_CHECK("VIDIOC_QBUF", XV_IOC(XV_IOC_READ | XV_IOC_WRITE, 'V', 15, XV_PIN_SZ_BUFFER), XV_PIN_VIDIOC_QBUF);
  XV_CHECK("VIDIOC_DQBUF", XV_IOC(XV_IOC_READ | XV_IOC_WRITE, 'V', 17, XV_PIN_SZ_BUFFER), XV_PIN_VIDIOC_DQBUF);
  XV_CHECK("VIDIOC_STREAMON", XV_IOC(XV_IOC_WRITE, 'V', 18, sizeof(int)), XV_PIN_VIDIOC_STREAMON);
  XV_CHECK("VIDIOC_STREAMOFF", XV_IOC(XV_IOC_WRITE, 'V', 19, sizeof(int)), XV_PIN_VIDIOC_STREAMOFF);

  /* struct sizes re-derived from the definitions above */
  XV_CHECK("sizeof(v4l2_capability)", sizeof(XV_capability), XV_PIN_SZ_CAPABILITY);
  XV_CHECK("sizeof(v4l2_pix_format)", sizeof(XV_pix_format), XV_PIN_SZ_PIX_FORMAT);
  XV_CHECK("sizeof(v4l2_format)", sizeof(XV_format), XV_PIN_SZ_FORMAT);
  XV_CHECK("sizeof(v4l2_requestbuffers)", sizeof(XV_requestbuffers), XV_PIN_SZ_REQUESTBUFFERS);
  XV_CHECK("sizeof(v4l2_buffer)", sizeof(XV_buffer), XV_PIN_SZ_BUFFER);
  XV_CHECK("sizeof(v4l2_timecode)", sizeof(XV_timecode), XV_PIN_SZ_TIMECODE);
  XV_CHECK("sizeof(timeval)", sizeof(XV_timeval), XV_PIN_SZ_TIMEVAL);

  /* key field offsets */
  XV_CHECK("off(v4l2_capability,driver)", offsetof(XV_capability, driver), XV_PIN_OFF_CAP_DRIVER);
  XV_CHECK("off(v4l2_capability,card)", offsetof(XV_capability, card), XV_PIN_OFF_CAP_CARD);
  XV_CHECK("off(v4l2_capability,bus_info)", offsetof(XV_capability, bus_info), XV_PIN_OFF_CAP_BUS_INFO);
  XV_CHECK("off(v4l2_capability,capabilities)", offsetof(XV_capability, capabilities), XV_PIN_OFF_CAP_CAPABILITIES);
  XV_CHECK("off(v4l2_capability,device_caps)", offsetof(XV_capability, device_caps), XV_PIN_OFF_CAP_DEVICE_CAPS);
  XV_CHECK("off(v4l2_format,type)", offsetof(XV_format, type), XV_PIN_OFF_FMT_TYPE);
  XV_CHECK("off(v4l2_format,fmt)", offsetof(XV_format, fmt), XV_PIN_OFF_FMT_FMT);
  XV_CHECK("off(v4l2_pix_format,width)", offsetof(XV_pix_format, width), XV_PIN_OFF_PIX_WIDTH);
  XV_CHECK("off(v4l2_pix_format,height)", offsetof(XV_pix_format, height), XV_PIN_OFF_PIX_HEIGHT);
  XV_CHECK("off(v4l2_pix_format,pixelformat)", offsetof(XV_pix_format, pixelformat), XV_PIN_OFF_PIX_PIXELFORMAT);
  XV_CHECK("off(v4l2_pix_format,bytesperline)", offsetof(XV_pix_format, bytesperline), XV_PIN_OFF_PIX_BYTESPERLINE);
  XV_CHECK("off(v4l2_pix_format,sizeimage)", offsetof(XV_pix_format, sizeimage), XV_PIN_OFF_PIX_SIZEIMAGE);
  XV_CHECK("off(v4l2_requestbuffers,count)", offsetof(XV_requestbuffers, count), XV_PIN_OFF_RB_COUNT);
  XV_CHECK("off(v4l2_requestbuffers,type)", offsetof(XV_requestbuffers, type), XV_PIN_OFF_RB_TYPE);
  XV_CHECK("off(v4l2_requestbuffers,memory)", offsetof(XV_requestbuffers, memory), XV_PIN_OFF_RB_MEMORY);
  XV_CHECK("off(v4l2_buffer,index)", offsetof(XV_buffer, index), XV_PIN_OFF_BUF_INDEX);
  XV_CHECK("off(v4l2_buffer,bytesused)", offsetof(XV_buffer, bytesused), XV_PIN_OFF_BUF_BYTESUSED);
  XV_CHECK("off(v4l2_buffer,flags)", offsetof(XV_buffer, flags), XV_PIN_OFF_BUF_FLAGS);
  XV_CHECK("off(v4l2_buffer,sequence)", offsetof(XV_buffer, sequence), XV_PIN_OFF_BUF_SEQUENCE);
  XV_CHECK("off(v4l2_buffer,memory)", offsetof(XV_buffer, memory), XV_PIN_OFF_BUF_MEMORY);
  XV_CHECK("off(v4l2_buffer,m)", offsetof(XV_buffer, m), XV_PIN_OFF_BUF_M);
  XV_CHECK("off(v4l2_buffer,length)", offsetof(XV_buffer, length), XV_PIN_OFF_BUF_LENGTH);
  XV_CHECK("off(v4l2_buffer,reserved2)", offsetof(XV_buffer, reserved2), XV_PIN_OFF_BUF_RESERVED2);

#undef XV_CHECK
  return fails;
}

/* Run the self-check once; the result is stable for the process lifetime. */
static int xv_abi_fails(void) {
  static int cached = -1;
  if (cached < 0) { cached = xv_abi_check(); }
  return cached;
}

/* =========================================================================
 * Platform + probe
 * ========================================================================= */

int xv_platform(void) {
#if XV_LINUX
  return 0;
#else
  return 1;
#endif
}

int xv_abi_fail_count(void) {
  return xv_abi_fails();
}

const char* xv_abi_fail_names(void) {
  (void)xv_abi_fails();
  return g_abi_fail;
}

const char* xv_error(void) {
  return g_error;
}

int xv_last_errno(void) {
  return g_last_errno;
}

int xv_device_count(void) {
  return g_dev_count;
}

const char* xv_device_path(int idx) {
  if (idx < 0 || idx >= g_dev_count) { return ""; }
  return g_dev_paths[idx];
}

/* Scan `dev_dir` for videoN nodes.  A node counts as a V4L2 device when it
 * opens read-write and VIDIOC_QUERYCAP succeeds.  Classification:
 *   0 = at least one device, 1 = absent (SKIP), 2 = present but QUERYCAP
 *   fails on every openable node (ABI fault -- never a silent SKIP). */
int xv_probe_named(const char* dev_dir) {
  g_dev_count = 0;
  g_last_errno = 0;
  if (xv_abi_fails() != 0) {
    snprintf(g_error, sizeof(g_error), "pinned ABI self-check failed: %s", g_abi_fail);
    return 2;
  }
#if XV_LINUX
  {
    int opened_any = 0;
    char path[160];
    int i;
    for (i = 0; i < XV_MAX_DEVS; i++) {
      XV_capability cap;
      int fd;
      snprintf(path, sizeof(path), "%s/video%d", dev_dir, i);
      fd = open(path, O_RDWR | O_NONBLOCK);
      if (fd < 0) { continue; }
      opened_any = 1;
      memset(&cap, 0, sizeof(cap));
      if (ioctl(fd, XV_PIN_VIDIOC_QUERYCAP, &cap) == 0) {
        if (g_dev_count < XV_MAX_DEVS) {
          snprintf(g_dev_paths[g_dev_count], sizeof(g_dev_paths[0]), "%s", path);
          g_dev_count++;
        }
      }
      close(fd);
    }
    if (g_dev_count > 0) {
      snprintf(g_error, sizeof(g_error), "%d V4L2 device node(s) under %s", g_dev_count, dev_dir);
      return 0;
    }
    if (opened_any) {
      snprintf(g_error, sizeof(g_error), "video nodes under %s open but VIDIOC_QUERYCAP fails (not a V4L2 node?)", dev_dir);
      return 2;
    }
    snprintf(g_error, sizeof(g_error), "no V4L2 device nodes under %s (SKIP)", dev_dir);
    return 1;
  }
#else
  (void)dev_dir;
  snprintf(g_error, sizeof(g_error), "no V4L2 device access on this platform (blanket SKIP; SKIP)");
  return 1;
#endif
}

int xv_probe(void) {
  return xv_probe_named("/dev");
}

/* =========================================================================
 * Device handles
 * ========================================================================= */

static XV_dev_slot* xv_slot(int h) {
  if (h < 1 || h > XV_MAX_HANDLES) { return 0; }
  if (!g_devs[h - 1].open) { return 0; }
  return &g_devs[h - 1];
}

static int xv_open_common(const char* path) {
  g_last_errno = 0;
  if (xv_abi_fails() != 0) {
    snprintf(g_error, sizeof(g_error), "pinned ABI self-check failed: %s", g_abi_fail);
    return 0;
  }
#if XV_LINUX
  {
    int slot = -1;
    int fd;
    int i;
    for (i = 0; i < XV_MAX_HANDLES; i++) {
      if (!g_devs[i].open) { slot = i; break; }
    }
    if (slot < 0) {
      xv_set_error("no free device handle slot");
      return 0;
    }
    fd = open(path, O_RDWR);
    if (fd < 0) {
      xv_set_errno_msg("open");
      return 0;
    }
    memset(&g_devs[slot], 0, sizeof(g_devs[slot]));
    g_devs[slot].open = 1;
    g_devs[slot].fd = fd;
    g_devs[slot].dq_index = -1;
    snprintf(g_devs[slot].path, sizeof(g_devs[slot].path), "%s", path);
    snprintf(g_error, sizeof(g_error), "opened %s", path);
    return slot + 1;
  }
#else
  (void)path;
  snprintf(g_error, sizeof(g_error), "no V4L2 device access on this platform");
  g_last_errno = 38; /* ENOSYS */
  return 0;
#endif
}

int xv_open_path(const char* path) {
  if (path == 0 || path[0] == 0) {
    xv_set_error("empty device path");
    return 0;
  }
  return xv_open_common(path);
}

int xv_open(int idx) {
  if (idx < 0 || idx >= g_dev_count) {
    xv_set_error("device index out of range (probe first)");
    return 0;
  }
  return xv_open_common(g_dev_paths[idx]);
}

int xv_querycap(int h) {
  XV_dev_slot* d = xv_slot(h);
  if (!d) { xv_set_error("device not open"); g_last_errno = 9; return -1; }
#if XV_LINUX
  memset(&d->cap, 0, sizeof(d->cap));
  if (ioctl(d->fd, XV_PIN_VIDIOC_QUERYCAP, &d->cap) != 0) {
    return xv_rc_errno("VIDIOC_QUERYCAP");
  }
  return 0;
#else
  return -1;
#endif
}

static const char* xv_cap_str(int h, int off, int n) {
  XV_dev_slot* d = xv_slot(h);
  static char buf[64];
  if (!d) { return ""; }
  snprintf(buf, sizeof(buf), "%.*s", n, (const char*)(((const uint8_t*)&d->cap) + off));
  return buf;
}

const char* xv_cap_driver(int h)   { return xv_cap_str(h, XV_PIN_OFF_CAP_DRIVER, 16); }
const char* xv_cap_card(int h)     { return xv_cap_str(h, XV_PIN_OFF_CAP_CARD, 32); }
const char* xv_cap_bus_info(int h) { return xv_cap_str(h, XV_PIN_OFF_CAP_BUS_INFO, 32); }

long long xv_cap_version(int h) {
  XV_dev_slot* d = xv_slot(h);
  return d ? (long long)d->cap.version : -1;
}
long long xv_cap_capabilities(int h) {
  XV_dev_slot* d = xv_slot(h);
  return d ? (long long)d->cap.capabilities : -1;
}
long long xv_cap_device_caps(int h) {
  XV_dev_slot* d = xv_slot(h);
  return d ? (long long)d->cap.device_caps : -1;
}

/* =========================================================================
 * Format negotiation (single-planar capture)
 * ========================================================================= */

int xv_g_fmt(int h) {
  XV_dev_slot* d = xv_slot(h);
  if (!d) { xv_set_error("device not open"); g_last_errno = 9; return -1; }
#if XV_LINUX
  memset(&d->fmt, 0, sizeof(d->fmt));
  d->fmt.type = XV_PIN_V4L2_BUF_TYPE_VIDEO_CAPTURE;
  if (ioctl(d->fd, XV_PIN_VIDIOC_G_FMT, &d->fmt) != 0) {
    return xv_rc_errno("VIDIOC_G_FMT");
  }
  return 0;
#else
  return -1;
#endif
}

int xv_s_fmt(int h, long long width, long long height, long long fourcc, long long field) {
  XV_dev_slot* d = xv_slot(h);
  if (!d) { xv_set_error("device not open"); g_last_errno = 9; return -1; }
#if XV_LINUX
  memset(&d->fmt, 0, sizeof(d->fmt));
  d->fmt.type = XV_PIN_V4L2_BUF_TYPE_VIDEO_CAPTURE;
  d->fmt.fmt.pix.width = (uint32_t)width;
  d->fmt.fmt.pix.height = (uint32_t)height;
  d->fmt.fmt.pix.pixelformat = (uint32_t)fourcc;
  d->fmt.fmt.pix.field = (uint32_t)field;
  if (ioctl(d->fd, XV_PIN_VIDIOC_S_FMT, &d->fmt) != 0) {
    return xv_rc_errno("VIDIOC_S_FMT");
  }
  return 0;
#else
  (void)width; (void)height; (void)fourcc; (void)field;
  return -1;
#endif
}

long long xv_fmt_width(int h) { XV_dev_slot* d = xv_slot(h); return d ? (long long)d->fmt.fmt.pix.width : -1; }
long long xv_fmt_height(int h) { XV_dev_slot* d = xv_slot(h); return d ? (long long)d->fmt.fmt.pix.height : -1; }
long long xv_fmt_pixelformat(int h) { XV_dev_slot* d = xv_slot(h); return d ? (long long)d->fmt.fmt.pix.pixelformat : -1; }
long long xv_fmt_field(int h) { XV_dev_slot* d = xv_slot(h); return d ? (long long)d->fmt.fmt.pix.field : -1; }
long long xv_fmt_bytesperline(int h) { XV_dev_slot* d = xv_slot(h); return d ? (long long)d->fmt.fmt.pix.bytesperline : -1; }
long long xv_fmt_sizeimage(int h) { XV_dev_slot* d = xv_slot(h); return d ? (long long)d->fmt.fmt.pix.sizeimage : -1; }
long long xv_fmt_colorspace(int h) { XV_dev_slot* d = xv_slot(h); return d ? (long long)d->fmt.fmt.pix.colorspace : -1; }
long long xv_fmt_flags(int h) { XV_dev_slot* d = xv_slot(h); return d ? (long long)d->fmt.fmt.pix.flags : -1; }

/* =========================================================================
 * Buffer I/O (mmap streaming)
 * ========================================================================= */

int xv_reqbufs(int h, long long count, long long type, long long memory) {
  XV_dev_slot* d = xv_slot(h);
  if (!d) { xv_set_error("device not open"); g_last_errno = 9; return -1; }
#if XV_LINUX
  memset(&d->rb, 0, sizeof(d->rb));
  d->rb.count = (uint32_t)count;
  d->rb.type = (uint32_t)type;
  d->rb.memory = (uint32_t)memory;
  if (ioctl(d->fd, XV_PIN_VIDIOC_REQBUFS, &d->rb) != 0) {
    return xv_rc_errno("VIDIOC_REQBUFS");
  }
  d->nbufs = (int)(d->rb.count < XV_MAX_BUFS ? d->rb.count : XV_MAX_BUFS);
  memset(d->bufs, 0, sizeof(d->bufs));
  return 0;
#else
  (void)count; (void)type; (void)memory;
  return -1;
#endif
}

long long xv_reqbufs_count(int h) {
  XV_dev_slot* d = xv_slot(h);
  return d ? (long long)d->rb.count : -1;
}

int xv_querybuf(int h, long long idx) {
  XV_dev_slot* d = xv_slot(h);
  if (!d) { xv_set_error("device not open"); g_last_errno = 9; return -1; }
#if XV_LINUX
  {
    XV_buffer b;
    if (idx < 0 || idx >= d->nbufs) { xv_set_error("buffer index out of range"); g_last_errno = 22; return -1; }
    memset(&b, 0, sizeof(b));
    b.index = (uint32_t)idx;
    b.type = XV_PIN_V4L2_BUF_TYPE_VIDEO_CAPTURE;
    b.memory = XV_PIN_V4L2_MEMORY_MMAP;
    if (ioctl(d->fd, XV_PIN_VIDIOC_QUERYBUF, &b) != 0) {
      return xv_rc_errno("VIDIOC_QUERYBUF");
    }
    d->bufs[idx].used = 1;
    d->bufs[idx].length = b.length;
    d->bufs[idx].offset = b.m.offset;
    return 0;
  }
#else
  (void)idx;
  return -1;
#endif
}

long long xv_buf_length(int h, long long idx) {
  XV_dev_slot* d = xv_slot(h);
  if (!d || idx < 0 || idx >= XV_MAX_BUFS || !d->bufs[idx].used) { return -1; }
  return (long long)d->bufs[idx].length;
}

long long xv_buf_offset(int h, long long idx) {
  XV_dev_slot* d = xv_slot(h);
  if (!d || idx < 0 || idx >= XV_MAX_BUFS || !d->bufs[idx].used) { return -1; }
  return (long long)d->bufs[idx].offset;
}

int xv_mmap(int h, long long idx) {
  XV_dev_slot* d = xv_slot(h);
  if (!d) { xv_set_error("device not open"); g_last_errno = 9; return -1; }
  if (idx < 0 || idx >= XV_MAX_BUFS || !d->bufs[idx].used) { xv_set_error("buffer not QUERYBUF'd"); g_last_errno = 22; return -1; }
#if XV_LINUX
  {
    void* p = mmap(0, d->bufs[idx].length, PROT_READ | PROT_WRITE, MAP_SHARED, d->fd, (off_t)d->bufs[idx].offset);
    if (p == MAP_FAILED) {
      return xv_rc_errno("mmap");
    }
    d->bufs[idx].addr = p;
    return 0;
  }
#else
  return -1;
#endif
}

long long xv_buf_ptr(int h, long long idx) {
  XV_dev_slot* d = xv_slot(h);
  if (!d || idx < 0 || idx >= XV_MAX_BUFS) { return 0; }
  return (long long)(intptr_t)d->bufs[idx].addr;
}

void xv_munmap_all(int h) {
  XV_dev_slot* d = xv_slot(h);
  int i;
  if (!d) { return; }
#if XV_LINUX
  for (i = 0; i < XV_MAX_BUFS; i++) {
    if (d->bufs[i].addr) {
      munmap(d->bufs[i].addr, d->bufs[i].length);
      d->bufs[i].addr = 0;
    }
  }
#else
  (void)i;
#endif
}

int xv_qbuf(int h, long long idx) {
  XV_dev_slot* d = xv_slot(h);
  if (!d) { xv_set_error("device not open"); g_last_errno = 9; return -1; }
#if XV_LINUX
  {
    XV_buffer b;
    if (idx < 0 || idx >= d->nbufs) { xv_set_error("buffer index out of range"); g_last_errno = 22; return -1; }
    memset(&b, 0, sizeof(b));
    b.index = (uint32_t)idx;
    b.type = XV_PIN_V4L2_BUF_TYPE_VIDEO_CAPTURE;
    b.memory = XV_PIN_V4L2_MEMORY_MMAP;
    if (ioctl(d->fd, XV_PIN_VIDIOC_QBUF, &b) != 0) {
      return xv_rc_errno("VIDIOC_QBUF");
    }
    return 0;
  }
#else
  (void)idx;
  return -1;
#endif
}

int xv_dqbuf(int h, long long timeout_ms) {
  XV_dev_slot* d = xv_slot(h);
  if (!d) { xv_set_error("device not open"); g_last_errno = 9; return -1; }
#if XV_LINUX
  {
    XV_buffer b;
    if (timeout_ms >= 0) {
      struct pollfd pfd;
      int prc;
      pfd.fd = d->fd;
      pfd.events = POLLIN;
      pfd.revents = 0;
      prc = poll(&pfd, 1, (int)timeout_ms);
      if (prc == 0) {
        g_last_errno = 11; /* EAGAIN */
        xv_set_error("VIDIOC_DQBUF timed out (poll)");
        return -3;
      }
      if (prc < 0) {
        return xv_rc_errno("poll");
      }
    }
    memset(&b, 0, sizeof(b));
    b.type = XV_PIN_V4L2_BUF_TYPE_VIDEO_CAPTURE;
    b.memory = XV_PIN_V4L2_MEMORY_MMAP;
    if (ioctl(d->fd, XV_PIN_VIDIOC_DQBUF, &b) != 0) {
      return xv_rc_errno("VIDIOC_DQBUF");
    }
    d->dq_index = (int)b.index;
    d->dq_flags = b.flags;
    d->dq_bytesused = b.bytesused;
    d->dq_sequence = b.sequence;
    d->dq_ts_ns =
        (int64_t)b.timestamp.tv_sec * 1000000000LL + (int64_t)b.timestamp.tv_usec * 1000LL;
    return (int)b.index;
  }
#else
  (void)timeout_ms;
  return -1;
#endif
}

long long xv_dq_flags(int h) { XV_dev_slot* d = xv_slot(h); return d ? (long long)d->dq_flags : -1; }
long long xv_dq_bytesused(int h) { XV_dev_slot* d = xv_slot(h); return d ? (long long)d->dq_bytesused : -1; }
long long xv_dq_sequence(int h) { XV_dev_slot* d = xv_slot(h); return d ? (long long)d->dq_sequence : -1; }
long long xv_dq_timestamp_ns(int h) { XV_dev_slot* d = xv_slot(h); return d ? d->dq_ts_ns : -1; }

int xv_frame_copy(int h, long long idx, unsigned char* dst, long long cap) {
  XV_dev_slot* d = xv_slot(h);
  if (!d || !dst || idx < 0 || idx >= XV_MAX_BUFS || !d->bufs[idx].used || !d->bufs[idx].addr) {
    xv_set_error("frame_copy: buffer not mapped (QUERYBUF+mmap first)");
    g_last_errno = 22;
    return -1;
  }
  {
    long long n = (d->dq_index == (int)idx && d->dq_bytesused > 0)
                      ? (long long)d->dq_bytesused
                      : (long long)d->bufs[idx].length;
    if (n > cap) { n = cap; }
    memcpy(dst, d->bufs[idx].addr, (size_t)n);
    return (int)n;
  }
}

/* =========================================================================
 * Streaming control
 * ========================================================================= */

static int xv_stream_ctl(int h, long long type, unsigned long req, const char* what) {
  XV_dev_slot* d = xv_slot(h);
  if (!d) { xv_set_error("device not open"); g_last_errno = 9; return -1; }
#if XV_LINUX
  {
    uint32_t t = (uint32_t)type;
    if (ioctl(d->fd, req, &t) != 0) {
      return xv_rc_errno(what);
    }
    return 0;
  }
#else
  (void)type; (void)req; (void)what;
  return -1;
#endif
}

int xv_streamon(int h, long long type) { return xv_stream_ctl(h, type, XV_PIN_VIDIOC_STREAMON, "VIDIOC_STREAMON"); }
int xv_streamoff(int h, long long type) { return xv_stream_ctl(h, type, XV_PIN_VIDIOC_STREAMOFF, "VIDIOC_STREAMOFF"); }

/* =========================================================================
 * Teardown
 * ========================================================================= */

void xv_close(int h) {
  XV_dev_slot* d = xv_slot(h);
  if (!d) { g_last_errno = 9; xv_set_error("close: device not open"); return; }
  xv_munmap_all(h);
#if XV_LINUX
  if (d->fd >= 0) { close(d->fd); }
#endif
  d->fd = -1;
  d->open = 0;
  g_last_errno = 0;
  xv_set_error("closed");
}

void xv_close_all(void) {
  int i;
  for (i = 1; i <= XV_MAX_HANDLES; i++) {
    if (g_devs[i - 1].open) { xv_close(i); }
  }
}
