// xiom.assimp -- C bridge over the vendored assimp core (import probes:
// OBJ/PLY/glTF2/COLLADA/FBX).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Scalar returns plus cached getters (no out-param slots; finding B-11).
// The probe imports in-memory assets -- OBJ, ASCII PLY, glTF2, COLLADA and
// ASCII FBX -- through Assimp::Importer and caches the scene counts.

#include "../vendor/include/assimp/Importer.hpp"
#include "../vendor/include/assimp/scene.h"
#include "../vendor/include/assimp/version.h"

#include <string.h>

static int g_meshes;
static int g_vertices;
static int g_faces;
static int g_ply_vertices;
static int g_ply_ok;
static int g_gltf_vertices;
static int g_collada_vertices;
static int g_fbx_vertices;
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

const char* assimprobe_error(void) {
  return g_error;
}

} // extern "C"
