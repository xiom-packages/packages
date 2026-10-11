/* xiom.meshopt compile unit -- MIT OR Apache-2.0 (this file), XIOM Authors.
 *
 * The vendored meshoptimizer v1.2 (commit f843aae0; MIT) is compiled TU by TU
 * via port.args.json; this file adds the `extern "C"` probe bridge the XIOM
 * module calls (meshopt.xi).  Every probe builds its own deterministic mesh,
 * so no foreign pointer is ever read from XIOM (B-20); out-params are 4-byte
 * ints and the XIOM side reads them little-endian from owned slots
 * (B-11/B-16/B-17 discipline).
 *
 * The one buffer-direction trio writes into an XIOM-owned byte slot and back
 * out of it:
 *   xmo_build_indices      C copies the probe grid into the XIOM buffer
 *   xmo_optimize_inplace   C optimizes in place and verifies the triangle set
 *   xmo_checksum           FNV-1a over the XIOM buffer (order-change evidence)
 *
 * Probe surface (all return 0; out-params may be NULL):
 *   xmo_version            -> MESHOPTIMIZER_VERSION (v1.2 = 1020)
 *   xmo_remap_probe        -> unique vertex count + mapped-index validity
 *   xmo_cache_probe        -> ACMR (milli) before/after optimizeVertexCache
 *   xmo_fetch_probe        -> analyzeVertexFetch bytes + overfetch (milli)
 *   xmo_simplify_probe     -> simplified index count + relative error (milli)
 *   xmo_encode_index_probe -> encoded size, decode rc, triangle-set equality
 *   xmo_vertex_codec_probe -> same for the vertex codec
 *   xmo_strip_probe        -> strip size, unstripified triangles, set equality
 *   xmo_quant_probe        -> fp16 bit patterns + dequantized milli value
 *   xmo_bounds_probe       -> sphere radius/center (milli) for a 2x2 square
 *   xmo_meshlet_probe      -> meshlet count + triangle conservation
 *   xmo_filter_probe       -> max octahedral normal error (milli, 8-bit)
 */

#include "../vendor/src/meshoptimizer.h"

#include <string.h>

namespace
{
const int kGridW = 8;
const int kGridH = 8;
const int kGridVerts = kGridW * kGridH;               /* 64 */
const int kGridTris = (kGridW - 1) * (kGridH - 1) * 2; /* 98 */
const int kGridIndices = kGridTris * 3;               /* 294 */

const int kSimW = 11;
const int kSimH = 11;
const int kSimVerts = kSimW * kSimH;                  /* 121 */
const int kSimTris = (kSimW - 1) * (kSimH - 1) * 2;   /* 200 */
const int kSimIndices = kSimTris * 3;                 /* 600 */

void grid_positions(float* out, int w, int h, float zscale)
{
	for (int y = 0; y < h; ++y)
	{
		for (int x = 0; x < w; ++x)
		{
			int i = (y * w + x) * 3;
			out[i + 0] = float(x);
			out[i + 1] = float(y);
			out[i + 2] = zscale * float(x * x + y * y);
		}
	}
}

/* Forward grid triangle list. */
int grid_indices(unsigned int* out, int w, int h)
{
	int k = 0;
	for (int y = 0; y + 1 < h; ++y)
	{
		for (int x = 0; x + 1 < w; ++x)
		{
			unsigned int a = (unsigned int)(y * w + x);
			unsigned int b = a + 1;
			unsigned int c = a + (unsigned int)w;
			unsigned int d = c + 1;
			out[k++] = a;
			out[k++] = b;
			out[k++] = c;
			out[k++] = b;
			out[k++] = d;
			out[k++] = c;
		}
	}
	return k;
}

/* Same triangles with the triangle order reversed: a deliberately
 * cache-hostile layout that optimizeVertexCache has to reorder. */
int grid_indices_reversed(unsigned int* out, int w, int h)
{
	static unsigned int forward[kGridTris * 3];
	int count = grid_indices(forward, w, h);
	int tris = count / 3;
	for (int i = 0; i < tris; ++i)
	{
		const unsigned int* src = &forward[(tris - 1 - i) * 3];
		out[i * 3 + 0] = src[0];
		out[i * 3 + 1] = src[1];
		out[i * 3 + 2] = src[2];
	}
	return count;
}

void tri_key(const unsigned int* tri, unsigned int* key)
{
	unsigned int a = tri[0], b = tri[1], c = tri[2], t;
	if (a > b) { t = a; a = b; b = t; }
	if (b > c) { t = b; b = c; c = t; }
	if (a > b) { t = a; a = b; b = t; }
	key[0] = a;
	key[1] = b;
	key[2] = c;
}

int tri_key_less(const unsigned int* a, const unsigned int* b)
{
	for (int i = 0; i < 3; ++i)
	{
		if (a[i] != b[i]) return a[i] < b[i] ? 1 : 0;
	}
	return 0;
}

void sort_keys(unsigned int (*k)[3], int n)
{
	for (int i = 1; i < n; ++i)
	{
		unsigned int cur[3];
		cur[0] = k[i][0];
		cur[1] = k[i][1];
		cur[2] = k[i][2];
		int j = i - 1;
		while (j >= 0 && tri_key_less(cur, k[j]))
		{
			k[j + 1][0] = k[j][0];
			k[j + 1][1] = k[j][1];
			k[j + 1][2] = k[j][2];
			j = j - 1;
		}
		k[j + 1][0] = cur[0];
		k[j + 1][1] = cur[1];
		k[j + 1][2] = cur[2];
	}
}

/* Order-insensitive triangle multiset comparison (each triangle is sorted
 * by vertex id, then the triangle list is sorted lexicographically). */
int triangle_sets_equal(const unsigned int* a, int a_count, const unsigned int* b, int b_count)
{
	if (a_count != b_count) return 0;
	int n = a_count / 3;
	static unsigned int ka[512][3];
	static unsigned int kb[512][3];
	if (n <= 0 || n > 512) return 0;

	for (int i = 0; i < n; ++i)
	{
		tri_key(&a[i * 3], ka[i]);
		tri_key(&b[i * 3], kb[i]);
	}
	sort_keys(ka, n);
	sort_keys(kb, n);

	for (int i = 0; i < n; ++i)
	{
		if (ka[i][0] != kb[i][0] || ka[i][1] != kb[i][1] || ka[i][2] != kb[i][2]) return 0;
	}
	return 1;
}

unsigned int fnv1a(const unsigned char* p, int n)
{
	unsigned int h = 2166136261u;
	for (int i = 0; i < n; ++i)
	{
		h ^= (unsigned int)p[i];
		h *= 16777619u;
	}
	return h;
}

float g_positions[kGridVerts * 3];
float g_positions_sim[kSimVerts * 3];
unsigned int g_indices_bad[kGridIndices];
unsigned int g_indices_good[kGridIndices];
unsigned int g_indices_sim[kSimIndices];
} // namespace

extern "C"
{

int xmo_version(void)
{
	return MESHOPTIMIZER_VERSION;
}

int xmo_remap_probe(int* unique, int* valid)
{
	static const float quad[6 * 3] = {
		0.0f, 0.0f, 0.0f,
		1.0f, 0.0f, 0.0f,
		0.0f, 1.0f, 0.0f,
		1.0f, 0.0f, 0.0f,
		1.0f, 1.0f, 0.0f,
		0.0f, 1.0f, 0.0f,
	};
	unsigned int indices[6];
	unsigned int remap[6];
	unsigned int mapped[6];

	for (int i = 0; i < 6; ++i) indices[i] = (unsigned int)i;

	size_t unique_count = meshopt_generateVertexRemap(remap, indices, 6, quad, 6, 12);
	meshopt_remapIndexBuffer(mapped, indices, 6, remap);

	int ok = (unique_count == 4) ? 1 : 0;
	for (int i = 0; i < 6; ++i)
	{
		if (mapped[i] >= unique_count) ok = 0;
	}

	if (unique) *unique = (int)unique_count;
	if (valid) *valid = ok;
	return 0;
}

int xmo_cache_probe(int* acmr_before_milli, int* acmr_after_milli, int* transformed_before, int* transformed_after)
{
	grid_positions(g_positions, kGridW, kGridH, 0.25f);
	grid_indices_reversed(g_indices_bad, kGridW, kGridH);

	meshopt_VertexCacheStatistics before = meshopt_analyzeVertexCache(g_indices_bad, kGridIndices, kGridVerts, 16, 32, 0);
	meshopt_optimizeVertexCache(g_indices_good, g_indices_bad, kGridIndices, kGridVerts);
	meshopt_VertexCacheStatistics after = meshopt_analyzeVertexCache(g_indices_good, kGridIndices, kGridVerts, 16, 32, 0);

	if (acmr_before_milli) *acmr_before_milli = (int)(before.acmr * 1000.0f + 0.5f);
	if (acmr_after_milli) *acmr_after_milli = (int)(after.acmr * 1000.0f + 0.5f);
	if (transformed_before) *transformed_before = (int)before.vertices_transformed;
	if (transformed_after) *transformed_after = (int)after.vertices_transformed;
	return 0;
}

int xmo_fetch_probe(int* bytes_fetched, int* overfetch_milli)
{
	grid_indices_reversed(g_indices_bad, kGridW, kGridH);
	meshopt_optimizeVertexCache(g_indices_good, g_indices_bad, kGridIndices, kGridVerts);

	meshopt_VertexFetchStatistics stats = meshopt_analyzeVertexFetch(g_indices_good, kGridIndices, kGridVerts, 12);

	if (bytes_fetched) *bytes_fetched = (int)stats.bytes_fetched;
	if (overfetch_milli) *overfetch_milli = (int)(stats.overfetch * 1000.0f + 0.5f);
	return 0;
}

int xmo_simplify_probe(int* out_count, int* err_milli)
{
	static unsigned int dest[kSimIndices];
	float err = 0.0f;

	grid_positions(g_positions_sim, kSimW, kSimH, 0.02f);
	grid_indices(g_indices_sim, kSimW, kSimH);

	size_t count = meshopt_simplify(dest, g_indices_sim, kSimIndices, g_positions_sim, kSimVerts, 12, 100, 0.05f, 0, &err);

	if (out_count) *out_count = (int)count;
	if (err_milli) *err_milli = (int)(err * 1000.0f + 0.5f);
	return 0;
}

int xmo_encode_index_probe(int* enc_size, int* dec_rc, int* equal)
{
	static unsigned char buffer[4096];
	static unsigned int decoded[kGridIndices];

	grid_indices_reversed(g_indices_bad, kGridW, kGridH);

	size_t bound = meshopt_encodeIndexBufferBound(kGridIndices, kGridVerts);
	if (bound > sizeof(buffer)) bound = sizeof(buffer);
	size_t size = meshopt_encodeIndexBuffer(buffer, bound, g_indices_bad, kGridIndices);

	int rc = -1;
	int eq = 0;
	if (size > 0)
	{
		/* encodeIndexBuffer implicitly rotates triangle corners to match the
		 * edge FIFO (README: use encodeIndexSequence to keep the exact order);
		 * the lossless guarantee is the triangle multiset. */
		rc = meshopt_decodeIndexBuffer(decoded, kGridIndices, 4, buffer, size);
		eq = (rc == 0 && triangle_sets_equal(g_indices_bad, kGridIndices, decoded, kGridIndices)) ? 1 : 0;
	}

	if (enc_size) *enc_size = (int)size;
	if (dec_rc) *dec_rc = rc;
	if (equal) *equal = eq;
	return 0;
}

int xmo_vertex_codec_probe(int* enc_size, int* dec_rc, int* equal)
{
	static unsigned char buffer[4096];
	static float decoded[kGridVerts * 3];

	grid_positions(g_positions, kGridW, kGridH, 0.25f);

	size_t bound = meshopt_encodeVertexBufferBound(kGridVerts, 12);
	if (bound > sizeof(buffer)) bound = sizeof(buffer);
	size_t size = meshopt_encodeVertexBuffer(buffer, bound, g_positions, kGridVerts, 12);

	int rc = -1;
	int eq = 0;
	if (size > 0)
	{
		rc = meshopt_decodeVertexBuffer(decoded, kGridVerts, 12, buffer, size);
		eq = (rc == 0 && memcmp(decoded, g_positions, sizeof(float) * kGridVerts * 3) == 0) ? 1 : 0;
	}

	if (enc_size) *enc_size = (int)size;
	if (dec_rc) *dec_rc = rc;
	if (equal) *equal = eq;
	return 0;
}

int xmo_strip_probe(int* strip_count, int* unstrip_triangles, int* set_equal)
{
	static unsigned int strip[2048];
	static unsigned int back[2048];

	grid_indices_reversed(g_indices_bad, kGridW, kGridH);
	meshopt_optimizeVertexCache(g_indices_good, g_indices_bad, kGridIndices, kGridVerts);

	size_t sc = meshopt_stripify(strip, g_indices_good, kGridIndices, kGridVerts, 0xffffffffu);

	size_t bcount = 0;
	if (sc > 0)
	{
		size_t ubound = meshopt_unstripifyBound(sc);
		if (ubound > 2048) ubound = 2048;
		bcount = meshopt_unstripify(back, strip, sc, 0xffffffffu);
	}

	int eq = triangle_sets_equal(g_indices_good, kGridIndices, back, (int)bcount);

	if (strip_count) *strip_count = (int)sc;
	if (unstrip_triangles) *unstrip_triangles = (int)(bcount / 3);
	if (set_equal) *set_equal = eq;
	return 0;
}

int xmo_quant_probe(int* half_one, int* half_neg_two, int* back_one_milli)
{
	unsigned short h1 = meshopt_quantizeHalf(1.0f);
	unsigned short h2 = meshopt_quantizeHalf(-2.0f);
	float b1 = meshopt_dequantizeHalf(h1);

	if (half_one) *half_one = (int)h1;
	if (half_neg_two) *half_neg_two = (int)h2;
	if (back_one_milli) *back_one_milli = (int)(b1 * 1000.0f + 0.5f);
	return 0;
}

int xmo_bounds_probe(int* radius_milli, int* center_x_milli, int* center_y_milli)
{
	/* Planar square (0,0)-(2,0)-(0,2)-(2,2): the upstream enclosing-sphere
	 * heuristic starts from the longest axis pair (the diagonal), giving an
	 * exact center (1,1,0) and radius sqrt(2). */
	static const float points[4 * 3] = {
		0.0f, 0.0f, 0.0f,
		2.0f, 0.0f, 0.0f,
		0.0f, 2.0f, 0.0f,
		2.0f, 2.0f, 0.0f,
	};
	meshopt_Bounds bounds = meshopt_computeSphereBounds(points, 4, 12, 0, 0);

	if (radius_milli) *radius_milli = (int)(bounds.radius * 1000.0f + 0.5f);
	if (center_x_milli) *center_x_milli = (int)(bounds.center[0] * 1000.0f + 0.5f);
	if (center_y_milli) *center_y_milli = (int)(bounds.center[1] * 1000.0f + 0.5f);
	return 0;
}

int xmo_meshlet_probe(int* meshlet_count, int* triangle_sum, int* input_triangles)
{
	static meshopt_Meshlet meshlets[128];
	static unsigned int meshlet_vertices[kGridIndices];
	static unsigned char meshlet_triangles[kGridIndices];

	grid_positions(g_positions, kGridW, kGridH, 0.25f);
	grid_indices_reversed(g_indices_bad, kGridW, kGridH);
	meshopt_optimizeVertexCache(g_indices_good, g_indices_bad, kGridIndices, kGridVerts);

	size_t count = meshopt_buildMeshlets(meshlets, meshlet_vertices, meshlet_triangles, g_indices_good, kGridIndices, g_positions, kGridVerts, 12, 64, 64, 0.0f);

	int sum = 0;
	for (size_t i = 0; i < count && i < 128; ++i)
	{
		sum += (int)meshlets[i].triangle_count;
	}

	if (meshlet_count) *meshlet_count = (int)count;
	if (triangle_sum) *triangle_sum = sum;
	if (input_triangles) *input_triangles = kGridTris;
	return 0;
}

int xmo_filter_probe(int* max_err_milli)
{
	static const float normals[3 * 4] = {
		0.6f, 0.0f, 0.8f, 0.0f,
		-0.6f, 0.0f, 0.8f, 0.0f,
		0.0f, 1.0f, 0.0f, 0.0f,
	};
	unsigned char oct[3 * 4];
	float max_err = 0.0f;

	meshopt_encodeFilterOct(oct, 3, 4, 8, normals);
	meshopt_decodeFilterOct(oct, 3, 4);

	for (int i = 0; i < 3; ++i)
	{
		float x = float((signed char)oct[i * 4 + 0]) / 127.0f;
		float y = float((signed char)oct[i * 4 + 1]) / 127.0f;
		float z = float((signed char)oct[i * 4 + 2]) / 127.0f;

		float dx = x - normals[i * 4 + 0];
		float dy = y - normals[i * 4 + 1];
		float dz = z - normals[i * 4 + 2];
		float e = dx < 0 ? -dx : dx;

		if (dy < 0) dy = -dy;
		if (dz < 0) dz = -dz;
		if (dy > e) e = dy;
		if (dz > e) e = dz;
		if (e > max_err) max_err = e;
	}

	if (max_err_milli) *max_err_milli = (int)(max_err * 1000.0f + 0.5f);
	return 0;
}

int xmo_build_indices(unsigned char* dst, int capacity)
{
	static unsigned int scrambled[kGridIndices];
	size_t bytes = sizeof(unsigned int) * kGridIndices;

	if (dst == 0 || capacity < (int)bytes) return 0;

	grid_indices_reversed(scrambled, kGridW, kGridH);
	memcpy(dst, scrambled, bytes);
	return kGridIndices;
}

int xmo_optimize_inplace(unsigned char* buf, int index_count, int vertex_count)
{
	static unsigned int before[kGridIndices];
	static unsigned int after[kGridIndices];
	int ok;

	if (buf == 0 || index_count <= 0 || index_count > kGridIndices || vertex_count <= 0) return 0;

	memcpy(before, buf, sizeof(unsigned int) * (size_t)index_count);
	meshopt_optimizeVertexCache(after, before, (size_t)index_count, (size_t)vertex_count);
	ok = triangle_sets_equal(before, index_count, after, index_count);
	memcpy(buf, after, sizeof(unsigned int) * (size_t)index_count);
	return ok;
}

unsigned int xmo_checksum(const unsigned char* buf, int byte_count)
{
	if (buf == 0 || byte_count <= 0) return 0;
	return fnv1a(buf, byte_count);
}

} // extern "C"
