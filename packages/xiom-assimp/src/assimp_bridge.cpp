// xiom.assimp -- C bridge over the vendored assimp core (import probes:
// OBJ/PLY/glTF2/COLLADA/FBX/BLEND/OFF/SMD).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Scalar returns plus cached getters (no out-param slots; finding B-11).
// The probe imports in-memory assets -- OBJ, ASCII PLY, glTF2, COLLADA and
// ASCII FBX -- through Assimp::Importer and caches the scene counts.

#include "../vendor/include/assimp/Importer.hpp"
#include "../vendor/include/assimp/scene.h"
#include "../vendor/include/assimp/version.h"
#include "../vendor/include/assimp/postprocess.h"

#include <string.h>

#include "blend_default_248.inc"

static int g_meshes;
static int g_vertices;
static int g_faces;
static int g_ply_vertices;
static int g_ply_ok;
static int g_gltf_vertices;
static int g_collada_vertices;
static int g_fbx_vertices;
static int g_blend_meshes;
static int g_blend_vertices;
static int g_blend_faces;
static int g_off_meshes;
static int g_off_vertices;
static int g_off_faces;
static int g_smd_meshes;
static int g_smd_vertices;
static int g_smd_faces;
static char g_error[512];

static void set_error(const char* msg) {
  if (msg == 0) msg = "";
  strncpy(g_error, msg, sizeof(g_error) - 1);
  g_error[sizeof(g_error) - 1] = 0;
}

extern "C" {

// Packed version: major * 10000 + minor * 100 + revision (v6.0.5 -> 60005).
int assimprobe_version(void) {
  return (int)aiGetVersionMajor() * 10000 + (int)aiGetVersionMinor() * 100 +
         (int)aiGetVersionRevision();
}

// In-memory OBJ import (triangle): caches mesh/vertex/face counts.  0 on
// success, negative on failure (see assimprobe_error).
int assimprobe_obj(void) {
  g_meshes = 0;
  g_vertices = 0;
  g_faces = 0;
  g_error[0] = 0;

  static const char* obj =
      "# xiom.assimp probe\n"
      "v 0 0 0\n"
      "v 1 0 0\n"
      "v 0 1 0\n"
      "f 1 2 3\n";

  Assimp::Importer importer;
  const aiScene* scene = importer.ReadFileFromMemory(obj, strlen(obj), 0, "obj");
  if (scene == 0) {
    set_error(importer.GetErrorString());
    return -2;
  }
  g_meshes = (int)scene->mNumMeshes;
  if (g_meshes > 0 && scene->mMeshes[0] != 0) {
    g_vertices = (int)scene->mMeshes[0]->mNumVertices;
    g_faces = (int)scene->mMeshes[0]->mNumFaces;
  }
  return 0;
}

int assimprobe_meshes(void) {
  return g_meshes;
}

int assimprobe_vertices(void) {
  return g_vertices;
}

int assimprobe_faces(void) {
  return g_faces;
}

// In-memory ASCII PLY import (triangle): caches the vertex count and a
// 3-vertex sanity flag.  0 on success, negative on failure.
int assimprobe_ply(void) {
  g_ply_vertices = 0;
  g_ply_ok = 0;
  g_error[0] = 0;

  static const char* ply =
      "ply\n"
      "format ascii 1.0\n"
      "element vertex 3\n"
      "property float x\n"
      "property float y\n"
      "property float z\n"
      "element face 1\n"
      "property list uchar int vertex_indices\n"
      "end_header\n"
      "0 0 0\n"
      "1 0 0\n"
      "0 1 0\n"
      "3 0 1 2\n";

  Assimp::Importer importer;
  const aiScene* scene = importer.ReadFileFromMemory(ply, strlen(ply), 0, "ply");
  if (scene == 0 || scene->mNumMeshes == 0 || scene->mMeshes[0] == 0) {
    set_error(importer.GetErrorString());
    return -3;
  }
  g_ply_vertices = (int)scene->mMeshes[0]->mNumVertices;
  g_ply_ok = g_ply_vertices == 3 ? 1 : 0;
  return g_ply_ok ? 0 : -4;
}

int assimprobe_ply_vertices(void) {
  return g_ply_vertices;
}

int assimprobe_ply_ok(void) {
  return g_ply_ok;
}

// In-memory glTF 2.0 import: a triangle whose buffer is embedded as a
// base64 data URI (36 bytes: three float32 VEC3 positions).  Caches the
// vertex count.  0 on success, negative on failure.
int assimprobe_gltf(void) {
  g_gltf_vertices = 0;
  g_error[0] = 0;

  static const char* gltf =
      "{\"asset\":{\"version\":\"2.0\"},"
      "\"scenes\":[{\"nodes\":[0]}],"
      "\"nodes\":[{\"mesh\":0}],"
      "\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0}}]}],"
      "\"buffers\":[{\"uri\":\"data:application/octet-stream;base64,"
      "AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAA\",\"byteLength\":36}],"
      "\"bufferViews\":[{\"buffer\":0,\"byteOffset\":0,\"byteLength\":36,\"target\":34962}],"
      "\"accessors\":[{\"bufferView\":0,\"componentType\":5126,\"count\":3,"
      "\"type\":\"VEC3\",\"max\":[1,1,0],\"min\":[0,0,0]}]}";

  Assimp::Importer importer;
  const aiScene* scene = importer.ReadFileFromMemory(gltf, strlen(gltf), 0, "gltf2");
  if (scene == 0 || scene->mNumMeshes == 0 || scene->mMeshes[0] == 0) {
    set_error(importer.GetErrorString());
    return -5;
  }
  g_gltf_vertices = (int)scene->mMeshes[0]->mNumVertices;
  return g_gltf_vertices == 3 ? 0 : -6;
}

int assimprobe_gltf_vertices(void) {
  return g_gltf_vertices;
}

// In-memory COLLADA (.dae) import: a minimal 1.4.1 document with one
// triangle.  Caches the vertex count.  0 on success, negative on failure.
int assimprobe_collada(void) {
  g_collada_vertices = 0;
  g_error[0] = 0;

  static const char* dae =
      "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
      "<COLLADA xmlns=\"http://www.collada.org/2005/11/COLLADASchema\" version=\"1.4.1\">"
      "<asset><up_axis>Y_UP</up_axis></asset>"
      "<library_geometries><geometry id=\"tri\" name=\"tri\"><mesh>"
      "<source id=\"pos\">"
      "<float_array id=\"pos-array\" count=\"9\">0 0 0 1 0 0 0 1 0</float_array>"
      "<technique_common><accessor source=\"#pos-array\" count=\"3\" stride=\"3\">"
      "<param name=\"X\" type=\"float\"/><param name=\"Y\" type=\"float\"/>"
      "<param name=\"Z\" type=\"float\"/></accessor></technique_common></source>"
      "<vertices id=\"verts\"><input semantic=\"POSITION\" source=\"#pos\"/></vertices>"
      "<triangles material=\"none\" count=\"1\">"
      "<input semantic=\"VERTEX\" source=\"#verts\" offset=\"0\"/>"
      "<p>0 1 2</p></triangles>"
      "</mesh></geometry></library_geometries>"
      "<library_visual_scenes><visual_scene id=\"scene\">"
      "<node id=\"n\" name=\"tri\"><instance_geometry url=\"#tri\"/></node>"
      "</visual_scene></library_visual_scenes>"
      "<scene><instance_visual_scene url=\"#scene\"/></scene>"
      "</COLLADA>";

  Assimp::Importer importer;
  const aiScene* scene = importer.ReadFileFromMemory(dae, strlen(dae), 0, "dae");
  if (scene == 0 || scene->mNumMeshes == 0 || scene->mMeshes[0] == 0) {
    set_error(importer.GetErrorString());
    return -7;
  }
  g_collada_vertices = (int)scene->mMeshes[0]->mNumVertices;
  return g_collada_vertices == 3 ? 0 : -8;
}

int assimprobe_collada_vertices(void) {
  return g_collada_vertices;
}

// In-memory ASCII FBX import: a minimal FBX 7400 document with one triangle
// Geometry, a Model, and the two object-object connections (geometry ->
// model, model -> root).  Caches the vertex count.  0 on success, negative
// on failure.
int assimprobe_fbx(void) {
  g_fbx_vertices = 0;
  g_error[0] = 0;

  static const char* fbx =
      "; xiom.assimp probe: minimal ASCII FBX (7400), one triangle\n"
      "FBXHeaderExtension:  {\n"
      "    FBXVersion: 7400\n"
      "}\n"
      "Objects:  {\n"
      "    Geometry: 100000, \"Geometry::tri\", \"Mesh\" {\n"
      "        Vertices: *9 {\n"
      "            a: 0,0,0,1,0,0,0,1,0\n"
      "        }\n"
      "        PolygonVertexIndex: *3 {\n"
      "            a: 0,1,-3\n"
      "        }\n"
      "    }\n"
      "    Model: 200000, \"Model::tri\", \"Mesh\" {\n"
      "    }\n"
      "}\n"
      "Connections:  {\n"
      "    C: \"OO\",100000,200000\n"
      "    C: \"OO\",200000,0\n"
      "}\n";

  Assimp::Importer importer;
  const aiScene* scene = importer.ReadFileFromMemory(fbx, strlen(fbx), 0, "fbx");
  if (scene == 0 || scene->mNumMeshes == 0 || scene->mMeshes[0] == 0) {
    set_error(importer.GetErrorString());
    return -9;
  }
  g_fbx_vertices = (int)scene->mMeshes[0]->mNumVertices;
  return g_fbx_vertices == 3 ? 0 : -10;
}

int assimprobe_fbx_vertices(void) {
  return g_fbx_vertices;
}

// In-memory BLEND import: the committed Blender 2.48 default-scene fixture
// (one cube; the format is DNA-driven binary and not synthesizable
// in-memory -- see tools/embed_blend_fixture.py).  Caches mesh/vertex/face
// counts.  0 on success, negative on failure.
int assimprobe_blend(void) {
  g_blend_meshes = 0;
  g_blend_vertices = 0;
  g_blend_faces = 0;
  g_error[0] = 0;

  Assimp::Importer importer;
  const aiScene* scene = importer.ReadFileFromMemory(
      kBlendDefault248, kBlendDefault248Len, 0, "blend");
  if (scene == 0) {
    set_error(importer.GetErrorString());
    return -11;
  }
  g_blend_meshes = (int)scene->mNumMeshes;
  if (g_blend_meshes > 0 && scene->mMeshes[0] != 0) {
    g_blend_vertices = (int)scene->mMeshes[0]->mNumVertices;
    g_blend_faces = (int)scene->mMeshes[0]->mNumFaces;
  }
  return 0;
}

int assimprobe_blend_meshes(void) {
  return g_blend_meshes;
}

int assimprobe_blend_vertices(void) {
  return g_blend_vertices;
}

int assimprobe_blend_faces(void) {
  return g_blend_faces;
}

// In-memory OFF import: a minimal ASCII OFF document (3 vertices, 1 face).
// Caches mesh/vertex/face counts.  0 on success, negative on failure.
int assimprobe_off(void) {
  g_off_meshes = 0;
  g_off_vertices = 0;
  g_off_faces = 0;
  g_error[0] = 0;

  static const char* off =
      "OFF\n"
      "3 1 0\n"
      "0 0 0\n"
      "1 0 0\n"
      "0 1 0\n"
      "3 0 1 2\n";

  Assimp::Importer importer;
  const aiScene* scene = importer.ReadFileFromMemory(off, strlen(off), 0, "off");
  if (scene == 0) {
    set_error(importer.GetErrorString());
    return -12;
  }
  g_off_meshes = (int)scene->mNumMeshes;
  if (g_off_meshes > 0 && scene->mMeshes[0] != 0) {
    g_off_vertices = (int)scene->mMeshes[0]->mNumVertices;
    g_off_faces = (int)scene->mMeshes[0]->mNumFaces;
  }
  return 0;
}

int assimprobe_off_meshes(void) {
  return g_off_meshes;
}

int assimprobe_off_vertices(void) {
  return g_off_vertices;
}

int assimprobe_off_faces(void) {
  return g_off_faces;
}

// In-memory SMD import: a minimal ASCII SMD document (one node, one skeleton
// key, one triangle with three bone-linked vertices).  Caches mesh/vertex/
// face counts.  0 on success, negative on failure.
int assimprobe_smd(void) {
  g_smd_meshes = 0;
  g_smd_vertices = 0;
  g_smd_faces = 0;
  g_error[0] = 0;

  static const char* smd =
      "version 1\n"
      "nodes\n"
      "0 \"root\" -1\n"
      "end\n"
      "skeleton\n"
      "time 0\n"
      "0 0 0 0 0 0 0\n"
      "end\n"
      "triangles\n"
      "mat_xiom\n"
      "0 0 0 0 0 0 1 0 0 1 0 1\n"
      "0 1 0 0 0 0 1 1 0 1 0 1\n"
      "0 0 1 0 0 0 1 0 1 1 0 1\n"
      "end\n";

  Assimp::Importer importer;
  const aiScene* scene = importer.ReadFileFromMemory(smd, strlen(smd), 0, "smd");
  if (scene == 0) {
    set_error(importer.GetErrorString());
    return -13;
  }
  g_smd_meshes = (int)scene->mNumMeshes;
  if (g_smd_meshes > 0 && scene->mMeshes[0] != 0) {
    g_smd_vertices = (int)scene->mMeshes[0]->mNumVertices;
    g_smd_faces = (int)scene->mMeshes[0]->mNumFaces;
  }
  return 0;
}

int assimprobe_smd_meshes(void) {
  return g_smd_meshes;
}

int assimprobe_smd_vertices(void) {
  return g_smd_vertices;
}

int assimprobe_smd_faces(void) {
  return g_smd_faces;
}

const char* assimprobe_error(void) {
  return g_error;
}

// ---- 0.8.0: file import registry + mesh-data copies ------------------------
// Engine P4 asset pipeline: import a file from disk with Triangulate +
// FlipUVs, then copy object-space positions, UVs, and post-triangulate
// indices into caller-owned buffers.  The XIOM side passes an owned slot
// pointer (the proven out-param pattern) and then reads the bytes with
// byte-indexed Vec access -- raw foreign-pointer value round-trips are not
// usable on the pinned compiler (B-17 family).  Handles are 1-based
// registry slots (0 invalid).

enum { ASSIMB_MAX_IMPORTS = 4 };

static Assimp::Importer g_importers[ASSIMB_MAX_IMPORTS];
static const aiScene* g_import_scenes[ASSIMB_MAX_IMPORTS];
static int g_import_used[ASSIMB_MAX_IMPORTS];

static const aiScene* import_scene(int handle) {
  int i = handle - 1;
  if (i < 0 || i >= ASSIMB_MAX_IMPORTS || !g_import_used[i]) return 0;
  return g_import_scenes[i];
}

static const aiMesh* import_mesh(int handle, int mesh) {
  const aiScene* s = import_scene(handle);
  if (s == 0 || mesh < 0 || (unsigned)mesh >= s->mNumMeshes) return 0;
  return s->mMeshes[mesh];
}

// Import a file from disk (Triangulate + FlipUVs): handle > 0 on success,
// negative on failure (see assimbridge_error).
int assimbridge_import_file(const char* path) {
  g_error[0] = 0;
  if (path == 0 || path[0] == 0) {
    set_error("empty path");
    return -20;
  }
  for (int i = 0; i < ASSIMB_MAX_IMPORTS; i++) {
    if (!g_import_used[i]) {
      const aiScene* scene = g_importers[i].ReadFile(
          path, aiProcess_Triangulate | aiProcess_FlipUVs);
      if (scene == 0) {
        set_error(g_importers[i].GetErrorString());
        return -21;
      }
      g_import_scenes[i] = scene;
      g_import_used[i] = 1;
      return i + 1;
    }
  }
  set_error("import registry full -- release a handle first");
  return -22;
}

void assimbridge_release(int handle) {
  int i = handle - 1;
  if (i < 0 || i >= ASSIMB_MAX_IMPORTS) return;
  if (!g_import_used[i]) return;
  g_importers[i].FreeScene();
  g_import_scenes[i] = 0;
  g_import_used[i] = 0;
}

int assimbridge_mesh_count(int handle) {
  const aiScene* s = import_scene(handle);
  return s == 0 ? 0 : (int)s->mNumMeshes;
}

int assimbridge_mesh_vertex_count(int handle, int mesh) {
  const aiMesh* m = import_mesh(handle, mesh);
  return m == 0 ? 0 : (int)m->mNumVertices;
}

int assimbridge_mesh_triangle_count(int handle, int mesh) {
  const aiMesh* m = import_mesh(handle, mesh);
  if (m == 0) return 0;
  int tris = 0;
  for (unsigned i = 0; i < m->mNumFaces; i++) {
    if (m->mFaces[i].mNumIndices == 3) tris++;
  }
  return tris;
}

int assimbridge_mesh_has_uvs(int handle, int mesh) {
  const aiMesh* m = import_mesh(handle, mesh);
  return (m != 0 && m->HasTextureCoords(0)) ? 1 : 0;
}

// Copy positions (3 f32 per vertex, 12-byte stride) into `out`
// (max_bytes >= n*12).  Returns bytes copied, -1 invalid mesh/null, -2
// buffer too small.
int assimbridge_copy_positions(int handle, int mesh, unsigned char* out, int max_bytes) {
  const aiMesh* m = import_mesh(handle, mesh);
  if (m == 0 || m->mNumVertices == 0 || out == 0) return -1;
  int bytes = (int)m->mNumVertices * 12;
  if (bytes > max_bytes) return -2;
  memcpy(out, (const void*)&m->mVertices[0].x, (size_t)bytes);
  return bytes;
}

// Copy UVs (3 f32 per vertex, 12-byte stride; read u/v) into `out`.
// Returns bytes copied, 0 when the mesh has no UV channel (out untouched).
int assimbridge_copy_uvs(int handle, int mesh, unsigned char* out, int max_bytes) {
  const aiMesh* m = import_mesh(handle, mesh);
  if (m == 0 || m->mNumVertices == 0) return -1;
  if (!m->HasTextureCoords(0) || out == 0) return 0;
  int bytes = (int)m->mNumVertices * 12;
  if (bytes > max_bytes) return -2;
  memcpy(out, (const void*)&m->mTextureCoords[0][0].x, (size_t)bytes);
  return bytes;
}

// Copy post-triangulate indices (3 u32 per triangle) into `out`.
// Returns bytes copied, -1 invalid mesh/null, -2 buffer too small.
int assimbridge_copy_indices(int handle, int mesh, unsigned char* out, int max_bytes) {
  const aiMesh* m = import_mesh(handle, mesh);
  if (m == 0 || out == 0) return -1;
  int tris = assimbridge_mesh_triangle_count(handle, mesh);
  int bytes = tris * 12;
  if (bytes > max_bytes) return -2;
  unsigned* dst = (unsigned*)out;
  int w = 0;
  for (unsigned f = 0; f < m->mNumFaces; f++) {
    if (m->mFaces[f].mNumIndices == 3) {
      dst[w++] = m->mFaces[f].mIndices[0];
      dst[w++] = m->mFaces[f].mIndices[1];
      dst[w++] = m->mFaces[f].mIndices[2];
    }
  }
  return bytes;
}

const char* assimbridge_error(void) {
  return g_error;
}

} // extern "C"
