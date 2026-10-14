/* xiom.ogg -- C bridge over the vendored libogg v1.3.6 (packet layer).
 *
 * MIT OR Apache-2.0 (this file only), XIOM Authors.  The vendored upstream
 * sources under vendor/ogg are BSD-3-Clause (see vendor/COPYING).
 *
 * ABI contract (generated in src/ogg_abi_protos.h; bindings discipline):
 *   - every entry point returns int64_t; upstream int/long returns widen
 *     with sign intact (sentinels and negative "hole" values survive)
 *   - state structs (ogg_sync_state, ogg_stream_state, oggpack_buffer,
 *     ogg_page, ogg_packet) are allocated HERE and cross as int64 handles;
 *     XIOM never casts a pointer (B-25)
 *   - byte payloads cross as XIOM-owned buffers: inputs are read, outputs
 *     are written into caller-owned slots; page/packet copy-out writes the
 *     bytes into owned buffers and the meta into owned slots (B-20/B-24)
 *   - info-slot layouts (little-endian, owned):
 *       page   (16 bytes): header_len i32 @0 | body_len i32 @4
 *                          serialno i32 @8 | pageno i32 @12
 *       packet (32 bytes): bytes i32 @0 | b_o_s i32 @4 | e_o_s i32 @8
 *                          pad i32 @12 | granulepos i64 @16 | packetno i64 @24
 *   - ogg_sync_buffer(oy, size) is folded into xo_sync_buffer(h, src, size):
 *     the bridge obtains the internal buffer and copies the owned input
 *     bytes in; the caller then calls xo_sync_wrote(h, size) exactly like
 *     the upstream buffer/memcpy/wrote idiom
 *   - oggpack_readinit COPIES the owned input bytes into a malloc'd buffer
 *     so that oggpack_writeclear is always safe on any pack handle
 *     (upstream reads would otherwise free foreign memory)
 *   - page/packet struct companions (xo_page_create/set/free,
 *     xo_packet_create/set/free, xo_pack_free) are documented extensions;
 *     structs point at caller-owned buffers and never own them
 */

#include "ogg_abi_protos.h"

#include "../vendor/ogg/ogg.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static void put_i32(unsigned char* slot, int32_t v)
{
  uint32_t u = (uint32_t)v;
  slot[0] = (unsigned char)(u & 0xFF);
  slot[1] = (unsigned char)((u >> 8) & 0xFF);
  slot[2] = (unsigned char)((u >> 16) & 0xFF);
  slot[3] = (unsigned char)((u >> 24) & 0xFF);
}

static void put_i64(unsigned char* slot, int64_t v)
{
  uint64_t u = (uint64_t)v;
  int i;
  for (i = 0; i < 8; ++i) {
    slot[i] = (unsigned char)((u >> (8 * i)) & 0xFF);
  }
}

static void zero_page_info(unsigned char* slot)
{
  if (slot != 0) {
    put_i32(slot, 0);
    put_i32(slot + 4, 0);
    put_i32(slot + 8, 0);
    put_i32(slot + 12, 0);
  }
}

static void zero_packet_info(unsigned char* slot)
{
  if (slot != 0) {
    put_i32(slot, 0);
    put_i32(slot + 4, 0);
    put_i32(slot + 8, 0);
    put_i32(slot + 12, 0);
    put_i64(slot + 16, 0);
    put_i64(slot + 24, 0);
  }
}

/* Copy an out-page into the caller's page struct + owned buffers/slots. */
static void copy_page_out(const ogg_page* pg, int64_t page_h,
                          unsigned char* hdr_out, int32_t hdr_cap,
                          unsigned char* body_out, int32_t body_cap,
                          unsigned char* info_out)
{
  int32_t hl = 0;
  int32_t bl = 0;
  if (pg->header != 0 && pg->header_len > 0 && hdr_out != 0 && hdr_cap > 0) {
    hl = (int32_t)(pg->header_len < (long)hdr_cap ? pg->header_len : (long)hdr_cap);
    memcpy(hdr_out, pg->header, (size_t)hl);
  }
  if (pg->body != 0 && pg->body_len > 0 && body_out != 0 && body_cap > 0) {
    bl = (int32_t)(pg->body_len < (long)body_cap ? pg->body_len : (long)body_cap);
    memcpy(body_out, pg->body, (size_t)bl);
  }
  if (page_h != 0) {
    ogg_page* dst = (ogg_page*)(intptr_t)page_h;
    dst->header = hdr_out;
    dst->header_len = (long)hl;
    dst->body = body_out;
    dst->body_len = (long)bl;
  }
  if (info_out != 0) {
    put_i32(info_out, hl);
    put_i32(info_out + 4, bl);
    put_i32(info_out + 8, pg->header != 0 ? ogg_page_serialno(pg) : 0);
    put_i32(info_out + 12, pg->header != 0 ? (int32_t)ogg_page_pageno(pg) : 0);
  }
}

/* Copy an out-packet into the caller's packet struct + owned buffer/slot. */
static void copy_packet_out(const ogg_packet* op, int64_t pkt_h,
                            unsigned char* data_out, int32_t cap,
                            unsigned char* info_out)
{
  int32_t n = 0;
  if (op->packet != 0 && op->bytes > 0 && data_out != 0 && cap > 0) {
    n = (int32_t)(op->bytes < (long)cap ? op->bytes : (long)cap);
    memcpy(data_out, op->packet, (size_t)n);
  }
  if (pkt_h != 0) {
    ogg_packet* dst = (ogg_packet*)(intptr_t)pkt_h;
    dst->packet = data_out;
    dst->bytes = (long)n;
    dst->b_o_s = op->b_o_s;
    dst->e_o_s = op->e_o_s;
    dst->granulepos = op->granulepos;
    dst->packetno = op->packetno;
  }
  if (info_out != 0) {
    put_i32(info_out, (int32_t)op->bytes);
    put_i32(info_out + 4, (int32_t)op->b_o_s);
    put_i32(info_out + 8, (int32_t)op->e_o_s);
    put_i32(info_out + 12, 0);
    put_i64(info_out + 16, (int64_t)op->granulepos);
    put_i64(info_out + 24, (int64_t)op->packetno);
  }
}

/* ======================================================================== */
/* ogg_sync_state                                                           */
/* ======================================================================== */

int64_t xo_sync_init(void)
{
  ogg_sync_state* oy = (ogg_sync_state*)malloc(sizeof(ogg_sync_state));
  if (oy == 0) {
    return 0;
  }
  if (ogg_sync_init(oy) != 0) {
    free((void*)oy);
    return 0;
  }
  return (int64_t)(intptr_t)oy;
}

int64_t xo_sync_clear(int64_t sync)
{
  if (sync == 0) {
    return -1;
  }
  return (int64_t)ogg_sync_clear((ogg_sync_state*)(intptr_t)sync);
}

int64_t xo_sync_reset(int64_t sync)
{
  if (sync == 0) {
    return -1;
  }
  return (int64_t)ogg_sync_reset((ogg_sync_state*)(intptr_t)sync);
}

int64_t xo_sync_destroy(int64_t sync)
{
  int rc;
  if (sync == 0) {
    return -1;
  }
  rc = ogg_sync_clear((ogg_sync_state*)(intptr_t)sync);
  free((void*)(intptr_t)sync);
  return (int64_t)rc;
}

int64_t xo_sync_check(int64_t sync)
{
  if (sync == 0) {
    return -1;
  }
  return (int64_t)ogg_sync_check((ogg_sync_state*)(intptr_t)sync);
}

int64_t xo_sync_buffer(int64_t sync, const unsigned char* data, int32_t size)
{
  char* buf;
  if (sync == 0) {
    return -1;
  }
  if (size <= 0) {
    return 0;
  }
  if (data == 0) {
    return -1;
  }
  buf = ogg_sync_buffer((ogg_sync_state*)(intptr_t)sync, (long)size);
  if (buf == 0) {
    return -1;
  }
  memcpy(buf, data, (size_t)size);
  return (int64_t)size;
}

int64_t xo_sync_wrote(int64_t sync, int32_t bytes)
{
  if (sync == 0) {
    return -1;
  }
  return (int64_t)ogg_sync_wrote((ogg_sync_state*)(intptr_t)sync, (long)bytes);
}

int64_t xo_sync_pageseek(int64_t sync)
{
  if (sync == 0) {
    return -1;
  }
  return (int64_t)ogg_sync_pageseek((ogg_sync_state*)(intptr_t)sync, 0);
}

int64_t xo_sync_pageout(int64_t sync, int64_t page, unsigned char* hdr_out, int32_t hdr_cap,
                        unsigned char* body_out, int32_t body_cap, unsigned char* info_out)
{
  ogg_page pg;
  int rc;
  if (sync == 0) {
    return -1;
  }
  memset(&pg, 0, sizeof(pg));
  rc = ogg_sync_pageout((ogg_sync_state*)(intptr_t)sync, &pg);
  if (rc > 0) {
    copy_page_out(&pg, page, hdr_out, hdr_cap, body_out, body_cap, info_out);
  } else {
    zero_page_info(info_out);
  }
  return (int64_t)rc;
}

/* ======================================================================== */
/* ogg_stream_state                                                         */
/* ======================================================================== */

int64_t xo_stream_init(int32_t serialno)
{
  ogg_stream_state* os = (ogg_stream_state*)malloc(sizeof(ogg_stream_state));
  if (os == 0) {
    return 0;
  }
  memset(os, 0, sizeof(*os));
  if (ogg_stream_init(os, (int)serialno) != 0) {
    free((void*)os);
    return 0;
  }
  return (int64_t)(intptr_t)os;
}

int64_t xo_stream_clear(int64_t os)
{
  if (os == 0) {
    return -1;
  }
  return (int64_t)ogg_stream_clear((ogg_stream_state*)(intptr_t)os);
}

int64_t xo_stream_reset(int64_t os)
{
  if (os == 0) {
    return -1;
  }
  return (int64_t)ogg_stream_reset((ogg_stream_state*)(intptr_t)os);
}

int64_t xo_stream_reset_serialno(int64_t os, int32_t serialno)
{
  if (os == 0) {
    return -1;
  }
  return (int64_t)ogg_stream_reset_serialno((ogg_stream_state*)(intptr_t)os, (int)serialno);
}

int64_t xo_stream_destroy(int64_t os)
{
  int rc;
  if (os == 0) {
    return -1;
  }
  rc = ogg_stream_clear((ogg_stream_state*)(intptr_t)os);
  free((void*)(intptr_t)os);
  return (int64_t)rc;
}

int64_t xo_stream_check(int64_t os)
{
  if (os == 0) {
    return -1;
  }
  return (int64_t)ogg_stream_check((ogg_stream_state*)(intptr_t)os);
}

int64_t xo_stream_eos(int64_t os)
{
  if (os == 0) {
    return -1;
  }
  return (int64_t)ogg_stream_eos((ogg_stream_state*)(intptr_t)os);
}

int64_t xo_stream_pagein(int64_t os, int64_t page)
{
  if (os == 0 || page == 0) {
    return -1;
  }
  return (int64_t)ogg_stream_pagein((ogg_stream_state*)(intptr_t)os, (ogg_page*)(intptr_t)page);
}

int64_t xo_stream_packetout(int64_t os, int64_t packet, unsigned char* data_out, int32_t cap,
                            unsigned char* info_out)
{
  ogg_packet op;
  int rc;
  if (os == 0) {
    return -1;
  }
  memset(&op, 0, sizeof(op));
  rc = ogg_stream_packetout((ogg_stream_state*)(intptr_t)os, &op);
  if (rc > 0) {
    copy_packet_out(&op, packet, data_out, cap, info_out);
  } else {
    zero_packet_info(info_out);
  }
  return (int64_t)rc;
}

int64_t xo_stream_packetpeek(int64_t os, int64_t packet, unsigned char* data_out, int32_t cap,
                             unsigned char* info_out)
{
  ogg_packet op;
  int rc;
  if (os == 0) {
    return -1;
  }
  memset(&op, 0, sizeof(op));
  rc = ogg_stream_packetpeek((ogg_stream_state*)(intptr_t)os, &op);
  if (rc > 0) {
    copy_packet_out(&op, packet, data_out, cap, info_out);
  } else {
    zero_packet_info(info_out);
  }
  return (int64_t)rc;
}

int64_t xo_stream_packetin(int64_t os, int64_t packet)
{
  if (os == 0 || packet == 0) {
    return -1;
  }
  return (int64_t)ogg_stream_packetin((ogg_stream_state*)(intptr_t)os, (ogg_packet*)(intptr_t)packet);
}

int64_t xo_stream_iovecin(int64_t os, const unsigned char* a, int32_t a_len,
                          const unsigned char* b, int32_t b_len,
                          int32_t e_o_s, int64_t granulepos)
{
  ogg_iovec_t iov[2];
  int count = 1;
  if (os == 0 || a == 0) {
    return -1;
  }
  iov[0].iov_base = (void*)a;
  iov[0].iov_len = (size_t)(a_len > 0 ? a_len : 0);
  if (b != 0 && b_len > 0) {
    iov[1].iov_base = (void*)b;
    iov[1].iov_len = (size_t)b_len;
    count = 2;
  }
  return (int64_t)ogg_stream_iovecin((ogg_stream_state*)(intptr_t)os, iov, count,
                                     (long)e_o_s, (ogg_int64_t)granulepos);
}

int64_t xo_stream_pageout(int64_t os, int64_t page, unsigned char* hdr_out, int32_t hdr_cap,
                          unsigned char* body_out, int32_t body_cap, unsigned char* info_out)
{
  ogg_page pg;
  int rc;
  if (os == 0) {
    return -1;
  }
  memset(&pg, 0, sizeof(pg));
  rc = ogg_stream_pageout((ogg_stream_state*)(intptr_t)os, &pg);
  if (rc > 0) {
    copy_page_out(&pg, page, hdr_out, hdr_cap, body_out, body_cap, info_out);
  } else {
    zero_page_info(info_out);
  }
  return (int64_t)rc;
}

int64_t xo_stream_pageout_fill(int64_t os, int32_t nfill, int64_t page, unsigned char* hdr_out,
                               int32_t hdr_cap, unsigned char* body_out, int32_t body_cap,
                               unsigned char* info_out)
{
  ogg_page pg;
  int rc;
  if (os == 0) {
    return -1;
  }
  memset(&pg, 0, sizeof(pg));
  rc = ogg_stream_pageout_fill((ogg_stream_state*)(intptr_t)os, &pg, (int)nfill);
  if (rc > 0) {
    copy_page_out(&pg, page, hdr_out, hdr_cap, body_out, body_cap, info_out);
  } else {
    zero_page_info(info_out);
  }
  return (int64_t)rc;
}

int64_t xo_stream_flush(int64_t os, int64_t page, unsigned char* hdr_out, int32_t hdr_cap,
                        unsigned char* body_out, int32_t body_cap, unsigned char* info_out)
{
  ogg_page pg;
  int rc;
  if (os == 0) {
    return -1;
  }
  memset(&pg, 0, sizeof(pg));
  rc = ogg_stream_flush((ogg_stream_state*)(intptr_t)os, &pg);
  if (rc > 0) {
    copy_page_out(&pg, page, hdr_out, hdr_cap, body_out, body_cap, info_out);
  } else {
    zero_page_info(info_out);
  }
  return (int64_t)rc;
}

int64_t xo_stream_flush_fill(int64_t os, int32_t nfill, int64_t page, unsigned char* hdr_out,
                             int32_t hdr_cap, unsigned char* body_out, int32_t body_cap,
                             unsigned char* info_out)
{
  ogg_page pg;
  int rc;
  if (os == 0) {
    return -1;
  }
  memset(&pg, 0, sizeof(pg));
  rc = ogg_stream_flush_fill((ogg_stream_state*)(intptr_t)os, &pg, (int)nfill);
  if (rc > 0) {
    copy_page_out(&pg, page, hdr_out, hdr_cap, body_out, body_cap, info_out);
  } else {
    zero_page_info(info_out);
  }
  return (int64_t)rc;
}

/* ======================================================================== */
/* ogg_page                                                                 */
/* ======================================================================== */

int64_t xo_page_create(void)
{
  ogg_page* pg = (ogg_page*)malloc(sizeof(ogg_page));
  if (pg == 0) {
    return 0;
  }
  memset(pg, 0, sizeof(*pg));
  return (int64_t)(intptr_t)pg;
}

int64_t xo_page_free(int64_t page)
{
  if (page == 0) {
    return -1;
  }
  free((void*)(intptr_t)page);
  return 0;
}

int64_t xo_page_set(int64_t page, unsigned char* header, int32_t header_len,
                    unsigned char* body, int32_t body_len)
{
  ogg_page* pg;
  if (page == 0) {
    return -1;
  }
  pg = (ogg_page*)(intptr_t)page;
  pg->header = header;
  pg->header_len = (long)header_len;
  pg->body = body;
  pg->body_len = (long)body_len;
  return 0;
}

int64_t xo_page_checksum_set(int64_t page)
{
  if (page == 0) {
    return -1;
  }
  ogg_page_checksum_set((ogg_page*)(intptr_t)page);
  return 0;
}

int64_t xo_page_version(int64_t page)
{
  if (page == 0) {
    return -1;
  }
  return (int64_t)ogg_page_version((const ogg_page*)(intptr_t)page);
}

int64_t xo_page_continued(int64_t page)
{
  if (page == 0) {
    return -1;
  }
  return (int64_t)ogg_page_continued((const ogg_page*)(intptr_t)page);
}

int64_t xo_page_bos(int64_t page)
{
  if (page == 0) {
    return -1;
  }
  return (int64_t)ogg_page_bos((const ogg_page*)(intptr_t)page);
}

int64_t xo_page_eos(int64_t page)
{
  if (page == 0) {
    return -1;
  }
  return (int64_t)ogg_page_eos((const ogg_page*)(intptr_t)page);
}

int64_t xo_page_granulepos(int64_t page)
{
  if (page == 0) {
    return -1;
  }
  return (int64_t)ogg_page_granulepos((const ogg_page*)(intptr_t)page);
}

int64_t xo_page_serialno(int64_t page)
{
  if (page == 0) {
    return -1;
  }
  return (int64_t)ogg_page_serialno((const ogg_page*)(intptr_t)page);
}

int64_t xo_page_pageno(int64_t page)
{
  if (page == 0) {
    return -1;
  }
  return (int64_t)ogg_page_pageno((const ogg_page*)(intptr_t)page);
}

int64_t xo_page_packets(int64_t page)
{
  if (page == 0) {
    return -1;
  }
  return (int64_t)ogg_page_packets((const ogg_page*)(intptr_t)page);
}

/* ======================================================================== */
/* ogg_packet                                                               */
/* ======================================================================== */

int64_t xo_packet_create(void)
{
  ogg_packet* op = (ogg_packet*)malloc(sizeof(ogg_packet));
  if (op == 0) {
    return 0;
  }
  memset(op, 0, sizeof(*op));
  return (int64_t)(intptr_t)op;
}

int64_t xo_packet_free(int64_t packet)
{
  if (packet == 0) {
    return -1;
  }
  free((void*)(intptr_t)packet);
  return 0;
}

int64_t xo_packet_set(int64_t packet, unsigned char* data, int32_t bytes,
                      int32_t b_o_s, int32_t e_o_s, int64_t granulepos, int64_t packetno)
{
  ogg_packet* op;
  if (packet == 0) {
    return -1;
  }
  op = (ogg_packet*)(intptr_t)packet;
  op->packet = data;
  op->bytes = (long)bytes;
  op->b_o_s = (long)b_o_s;
  op->e_o_s = (long)e_o_s;
  op->granulepos = (ogg_int64_t)granulepos;
  op->packetno = (ogg_int64_t)packetno;
  return 0;
}

int64_t xo_packet_clear(int64_t packet)
{
  ogg_packet* op;
  if (packet == 0) {
    return -1;
  }
  op = (ogg_packet*)(intptr_t)packet;
  op->packet = 0; /* never free XIOM-owned bytes */
  ogg_packet_clear(op);
  return 0;
}

/* ======================================================================== */
/* oggpack_buffer                                                           */
/* ======================================================================== */

int64_t xo_pack_writeinit(void)
{
  oggpack_buffer* b = (oggpack_buffer*)malloc(sizeof(oggpack_buffer));
  if (b == 0) {
    return 0;
  }
  memset(b, 0, sizeof(*b));
  oggpack_writeinit(b);
  return (int64_t)(intptr_t)b;
}

int64_t xo_pack_free(int64_t pack)
{
  oggpack_buffer* b;
  if (pack == 0) {
    return -1;
  }
  b = (oggpack_buffer*)(intptr_t)pack;
  oggpack_writeclear(b);
  free((void*)b);
  return 0;
}

int64_t xo_pack_writecheck(int64_t pack)
{
  if (pack == 0) {
    return -1;
  }
  return (int64_t)oggpack_writecheck((oggpack_buffer*)(intptr_t)pack);
}

int64_t xo_pack_writetrunc(int64_t pack, int32_t bits)
{
  if (pack == 0) {
    return -1;
  }
  oggpack_writetrunc((oggpack_buffer*)(intptr_t)pack, (long)bits);
  return 0;
}

int64_t xo_pack_writealign(int64_t pack)
{
  if (pack == 0) {
    return -1;
  }
  oggpack_writealign((oggpack_buffer*)(intptr_t)pack);
  return 0;
}

int64_t xo_pack_writecopy(int64_t pack, const unsigned char* source, int32_t bits)
{
  if (pack == 0) {
    return -1;
  }
  oggpack_writecopy((oggpack_buffer*)(intptr_t)pack, (void*)source, (long)bits);
  return 0;
}

int64_t xo_pack_reset(int64_t pack)
{
  if (pack == 0) {
    return -1;
  }
  oggpack_reset((oggpack_buffer*)(intptr_t)pack);
  return 0;
}

int64_t xo_pack_writeclear(int64_t pack)
{
  if (pack == 0) {
    return -1;
  }
  oggpack_writeclear((oggpack_buffer*)(intptr_t)pack);
  return 0;
}

int64_t xo_pack_readinit(int64_t pack, const unsigned char* src, int32_t bytes)
{
  oggpack_buffer* b;
  unsigned char* copy;
  if (pack == 0 || bytes < 0) {
    return -1;
  }
  b = (oggpack_buffer*)(intptr_t)pack;
  copy = (unsigned char*)malloc(bytes > 0 ? (size_t)bytes : 1);
  if (copy == 0) {
    return -1;
  }
  if (bytes > 0 && src != 0) {
    memcpy(copy, src, (size_t)bytes);
  }
  oggpack_readinit(b, copy, (int)bytes);
  return 0;
}

int64_t xo_pack_write(int64_t pack, int32_t value, int32_t bits)
{
  if (pack == 0) {
    return -1;
  }
  oggpack_write((oggpack_buffer*)(intptr_t)pack, (unsigned long)(uint32_t)value, (int)bits);
  return 0;
}

int64_t xo_pack_look(int64_t pack, int32_t bits)
{
  if (pack == 0) {
    return -1;
  }
  return (int64_t)oggpack_look((oggpack_buffer*)(intptr_t)pack, (int)bits);
}

int64_t xo_pack_look1(int64_t pack)
{
  if (pack == 0) {
    return -1;
  }
  return (int64_t)oggpack_look1((oggpack_buffer*)(intptr_t)pack);
}

int64_t xo_pack_adv(int64_t pack, int32_t bits)
{
  if (pack == 0) {
    return -1;
  }
  oggpack_adv((oggpack_buffer*)(intptr_t)pack, (int)bits);
  return 0;
}

int64_t xo_pack_adv1(int64_t pack)
{
  if (pack == 0) {
    return -1;
  }
  oggpack_adv1((oggpack_buffer*)(intptr_t)pack);
  return 0;
}

int64_t xo_pack_read(int64_t pack, int32_t bits)
{
  if (pack == 0) {
    return -1;
  }
  return (int64_t)oggpack_read((oggpack_buffer*)(intptr_t)pack, (int)bits);
}

int64_t xo_pack_read1(int64_t pack)
{
  if (pack == 0) {
    return -1;
  }
  return (int64_t)oggpack_read1((oggpack_buffer*)(intptr_t)pack);
}

int64_t xo_pack_bytes(int64_t pack)
{
  if (pack == 0) {
    return -1;
  }
  return (int64_t)oggpack_bytes((oggpack_buffer*)(intptr_t)pack);
}

int64_t xo_pack_bits(int64_t pack)
{
  if (pack == 0) {
    return -1;
  }
  return (int64_t)oggpack_bits((oggpack_buffer*)(intptr_t)pack);
}

int64_t xo_pack_get_buffer(int64_t pack, unsigned char* out, int32_t capacity)
{
  oggpack_buffer* b;
  unsigned char* p;
  long n;
  if (pack == 0) {
    return -1;
  }
  b = (oggpack_buffer*)(intptr_t)pack;
  n = oggpack_bytes(b);
  if (n < 0) {
    n = 0;
  }
  p = oggpack_get_buffer(b);
  if (out != 0 && capacity > 0 && p != 0) {
    memcpy(out, p, (size_t)(n < (long)capacity ? n : (long)capacity));
  }
  return (int64_t)n;
}
