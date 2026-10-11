/* B-20 repro host: exposes pointers to known buffers plus C-side
 * ground-truth readers. */
static const unsigned g_buf[4] = {
    0x3F800000u, /* 1.0f */
    0x40000000u, /* 2.0f */
    0x40400000u, /* 3.0f */
    0x40800000u  /* 4.0f */
};

const unsigned* xt_buf_ptr(void) {
  return g_buf;
}

int xt_buf_sum(void) {
  return (int)(g_buf[0] + g_buf[1] + g_buf[2] + g_buf[3]);
}

int xt_buf_u32(int i) {
  if (i < 0 || i > 3) return -1;
  return (int)g_buf[i];
}
