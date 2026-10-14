/* xiom.ogg -- GENERATED bridge ABI prototypes (tools/gen_ogg.py).
 * Included by src/ogg_bridge.c so every body is signature-checked. */
#ifndef XIOM_OGG_ABI_PROTOS_H
#define XIOM_OGG_ABI_PROTOS_H
#include <stdint.h>

int64_t xo_pack_writeinit(void);
int64_t xo_pack_writecheck(int64_t p0);
int64_t xo_pack_writetrunc(int64_t p0, int32_t p1);
int64_t xo_pack_writealign(int64_t p0);
int64_t xo_pack_writecopy(int64_t p0, const unsigned char* p1, int32_t p2);
int64_t xo_pack_reset(int64_t p0);
int64_t xo_pack_writeclear(int64_t p0);
int64_t xo_pack_readinit(int64_t p0, const unsigned char* p1, int32_t p2);
int64_t xo_pack_write(int64_t p0, int32_t p1, int32_t p2);
int64_t xo_pack_look(int64_t p0, int32_t p1);
int64_t xo_pack_look1(int64_t p0);
int64_t xo_pack_adv(int64_t p0, int32_t p1);
int64_t xo_pack_adv1(int64_t p0);
int64_t xo_pack_read(int64_t p0, int32_t p1);
int64_t xo_pack_read1(int64_t p0);
int64_t xo_pack_bytes(int64_t p0);
int64_t xo_pack_bits(int64_t p0);
int64_t xo_pack_get_buffer(int64_t p0, unsigned char* p1, int32_t p2);
int64_t xo_stream_packetin(int64_t p0, int64_t p1);
int64_t xo_stream_iovecin(int64_t os, const unsigned char* a, int32_t a_len, const unsigned char* b, int32_t b_len, int32_t e_o_s, int64_t granulepos);
int64_t xo_stream_pageout(int64_t os, int64_t page, unsigned char* hdr_out, int32_t hdr_cap, unsigned char* body_out, int32_t body_cap, unsigned char* info_out);
int64_t xo_stream_pageout_fill(int64_t os, int32_t nfill, int64_t page, unsigned char* hdr_out, int32_t hdr_cap, unsigned char* body_out, int32_t body_cap, unsigned char* info_out);
int64_t xo_stream_flush(int64_t os, int64_t page, unsigned char* hdr_out, int32_t hdr_cap, unsigned char* body_out, int32_t body_cap, unsigned char* info_out);
int64_t xo_stream_flush_fill(int64_t os, int32_t nfill, int64_t page, unsigned char* hdr_out, int32_t hdr_cap, unsigned char* body_out, int32_t body_cap, unsigned char* info_out);
int64_t xo_sync_init(void);
int64_t xo_sync_clear(int64_t p0);
int64_t xo_sync_reset(int64_t p0);
int64_t xo_sync_destroy(int64_t p0);
int64_t xo_sync_check(int64_t p0);
int64_t xo_sync_buffer(int64_t sync, const unsigned char* data, int32_t size);
int64_t xo_sync_wrote(int64_t p0, int32_t p1);
int64_t xo_sync_pageseek(int64_t p0);
int64_t xo_sync_pageout(int64_t sync, int64_t page, unsigned char* hdr_out, int32_t hdr_cap, unsigned char* body_out, int32_t body_cap, unsigned char* info_out);
int64_t xo_stream_pagein(int64_t p0, int64_t p1);
int64_t xo_stream_packetout(int64_t os, int64_t packet, unsigned char* data_out, int32_t cap, unsigned char* info_out);
int64_t xo_stream_packetpeek(int64_t os, int64_t packet, unsigned char* data_out, int32_t cap, unsigned char* info_out);
int64_t xo_stream_init(int32_t p0);
int64_t xo_stream_clear(int64_t p0);
int64_t xo_stream_reset(int64_t p0);
int64_t xo_stream_reset_serialno(int64_t p0, int32_t p1);
int64_t xo_stream_destroy(int64_t p0);
int64_t xo_stream_check(int64_t p0);
int64_t xo_stream_eos(int64_t p0);
int64_t xo_page_checksum_set(int64_t p0);
int64_t xo_page_version(int64_t p0);
int64_t xo_page_continued(int64_t p0);
int64_t xo_page_bos(int64_t p0);
int64_t xo_page_eos(int64_t p0);
int64_t xo_page_granulepos(int64_t p0);
int64_t xo_page_serialno(int64_t p0);
int64_t xo_page_pageno(int64_t p0);
int64_t xo_page_packets(int64_t p0);
int64_t xo_packet_clear(int64_t p0);
/* owned struct companions (documented extensions) */
int64_t xo_pack_free(int64_t pack);
int64_t xo_packet_create(void);
int64_t xo_packet_free(int64_t packet);
int64_t xo_packet_set(int64_t packet, unsigned char* data, int32_t bytes, int32_t b_o_s, int32_t e_o_s, int64_t granulepos, int64_t packetno);
int64_t xo_page_create(void);
int64_t xo_page_free(int64_t page);
int64_t xo_page_set(int64_t page, unsigned char* header, int32_t header_len, unsigned char* body, int32_t body_len);

#endif
