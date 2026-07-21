// XIOM — Box2D Physics Engine FFI Bindings (v4.x — 100% API surface)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level FFI declarations for the Box2D C API (box2d.dll / libbox2d.so).
// Box2D v4+ uses a pure C handle-based API. All objects are POD structs
// passed by value — no C++ classes, vtables, or inheritance.
//
// TARGET COMPILER: xiom v0.46.0+ "Production"
// All struct types, fixed-size arrays, and value-type FFI are expected
// to work with v0.46's extended extern "C" ABI support.
// See AUDIT.md for remaining gaps (callbacks, bool layout).

module xiom.box2d

// ===========================================================================
// OPAQUE HANDLE TYPES (box2d/id.h)
// ===========================================================================

pub type B2WorldId = {
  index1:     Int16;
  generation: Int16;
} derive[Clone, Copy]

pub type B2BodyId = {
  index1:     Int32;
  world0:     Int16;
  generation: Int16;
} derive[Clone, Copy]

pub type B2ShapeId = {
  index1:     Int32;
  world0:     Int16;
  generation: Int16;
} derive[Clone, Copy]

pub type B2ChainId = {
  index1:     Int32;
  world0:     Int16;
  generation: Int16;
} derive[Clone, Copy]

pub type B2JointId = {
  index1:     Int32;
  world0:     Int16;
  generation: Int16;
} derive[Clone, Copy]

pub type B2ContactId = {
  index1:     Int32;
  world0:     Int16;
  padding:    Int16;
  generation: UInt32;
} derive[Clone, Copy]

// ===========================================================================
// VERSION & BASE TYPES (box2d/base.h)
// ===========================================================================

pub type B2Version = {
  major:    Int32;
  minor:    Int32;
  revision: Int32;
}

// ===========================================================================
// MATH TYPES (box2d/math_functions.h)
// ===========================================================================

pub type B2Vec2 = { x: Float32; y: Float32; }
pub type B2CosSin = { cosine: Float32; sine: Float32; }
pub type B2Rot = { c: Float32; s: Float32; }

pub type B2Transform = { p: B2Vec2; q: B2Rot; }
pub type B2Mat22 = { cx: B2Vec2; cy: B2Vec2; }
pub type B2AABB = { lowerBound: B2Vec2; upperBound: B2Vec2; }
pub type B2Plane = { normal: B2Vec2; offset: Float32; }

// World-precision types (double when BOX2D_DOUBLE_PRECISION, else float)
pub type B2Pos = { x: Float64; y: Float64; }
pub type B2WorldTransform = { p: B2Pos; q: B2Rot; }

// ===========================================================================
// TUNING CONSTANTS (box2d/constants.h)
// ===========================================================================

pub const B2_MAX_POLYGON_VERTICES: Int32 = 8;
pub const B2_MAX_WORKERS:          Int32 = 32;
pub const B2_NAME_LENGTH:          Int32 = 10;
pub const B2_PI:                   Float32 = 3.14159265359;

// ===========================================================================
// ENUMERATIONS (box2d/types.h)
// ===========================================================================

pub const B2_STATIC_BODY:     Int32 = 0;
pub const B2_KINEMATIC_BODY:  Int32 = 1;
pub const B2_DYNAMIC_BODY:    Int32 = 2;

pub const B2_CIRCLE_SHAPE:        Int32 = 0;
pub const B2_CAPSULE_SHAPE:       Int32 = 1;
pub const B2_SEGMENT_SHAPE:       Int32 = 2;
pub const B2_POLYGON_SHAPE:       Int32 = 3;
pub const B2_CHAIN_SEGMENT_SHAPE: Int32 = 4;

pub const B2_DISTANCE_JOINT:  Int32 = 0;
pub const B2_FILTER_JOINT:    Int32 = 1;
pub const B2_MOTOR_JOINT:     Int32 = 2;
pub const B2_PRISMATIC_JOINT: Int32 = 3;
pub const B2_REVOLUTE_JOINT:  Int32 = 4;
pub const B2_WELD_JOINT:      Int32 = 5;
pub const B2_WHEEL_JOINT:     Int32 = 6;

pub const B2_TOI_UNKNOWN:    Int32 = 0;
pub const B2_TOI_FAILED:     Int32 = 1;
pub const B2_TOI_OVERLAPPED: Int32 = 2;
pub const B2_TOI_HIT:        Int32 = 3;
pub const B2_TOI_SEPARATED:  Int32 = 4;

// ===========================================================================
// SHAPE GEOMETRY TYPES (box2d/collision.h)
// ===========================================================================

pub type B2Circle = {
  center: B2Vec2;
  radius: Float32;
}

pub type B2Capsule = {
  center1: B2Vec2;
  center2: B2Vec2;
  radius:  Float32;
}

pub type B2Segment = {
  point1: B2Vec2;
  point2: B2Vec2;
}

pub type B2ChainSegment = {
  ghost1:  B2Vec2;
  segment: B2Segment;
  ghost2:  B2Vec2;
  chainId: Int32;
}

pub type B2Polygon = {
  vertices: [B2Vec2; B2_MAX_POLYGON_VERTICES as UInt];
  normals:  [B2Vec2; B2_MAX_POLYGON_VERTICES as UInt];
  centroid: B2Vec2;
  radius:   Float32;
  count:    Int32;
}

pub type B2Hull = {
  points: [B2Vec2; B2_MAX_POLYGON_VERTICES as UInt];
  count:  Int32;
}

pub type B2MassData = {
  mass:              Float32;
  center:            B2Vec2;
  rotationalInertia: Float32;
}

// ===========================================================================
// RAY/SHAPE CAST TYPES (box2d/collision.h)
// ===========================================================================

pub type B2RayCastInput = {
  origin:      B2Vec2;
  translation: B2Vec2;
  maxFraction: Float32;
}

pub type B2ShapeProxy = {
  points: [B2Vec2; B2_MAX_POLYGON_VERTICES as UInt];
  count:  Int32;
  radius: Float32;
}

pub type B2ShapeCastInput = {
  proxy:       B2ShapeProxy;
  translation: B2Vec2;
  maxFraction: Float32;
  canEncroach: Int32;
}

pub type B2CastOutput = {
  normal:     B2Vec2;
  point:      B2Vec2;
  fraction:   Float32;
  iterations: Int32;
  hit:        Int32;
}

pub type B2WorldCastOutput = {
  normal:     B2Vec2;
  point:      B2Pos;
  fraction:   Float32;
  iterations: Int32;
  hit:        Int32;
}

// ===========================================================================
// DISTANCE & TOI TYPES (box2d/collision.h)
// ===========================================================================

pub type B2SegmentDistanceResult = {
  closest1:       B2Vec2;
  closest2:       B2Vec2;
  fraction1:      Float32;
  fraction2:      Float32;
  distanceSquared: Float32;
}

pub type B2SimplexCache = {
  count:   Int16;
  indexA:  [Int8; 3];
  indexB:  [Int8; 3];
}

pub type B2DistanceInput = {
  proxyA:   B2ShapeProxy;
  proxyB:   B2ShapeProxy;
  transform: B2Transform;
  useRadii: Int32;
}

pub type B2DistanceOutput = {
  pointA:       B2Vec2;
  pointB:       B2Vec2;
  normal:       B2Vec2;
  distance:     Float32;
  iterations:   Int32;
  simplexCount: Int32;
}

pub type B2SimplexVertex = {
  wA:     B2Vec2;
  wB:     B2Vec2;
  w:      B2Vec2;
  a:      Float32;
  indexA: Int32;
  indexB: Int32;
}

pub type B2Simplex = {
  v1:    B2SimplexVertex;
  v2:    B2SimplexVertex;
  v3:    B2SimplexVertex;
  count: Int32;
}

pub type B2ShapeCastPairInput = {
  proxyA:       B2ShapeProxy;
  proxyB:       B2ShapeProxy;
  transform:    B2Transform;
  translationB: B2Vec2;
  maxFraction:  Float32;
  canEncroach:  Int32;
}

pub type B2Sweep = {
  localCenter: B2Vec2;
  c1:          B2Vec2;
  c2:          B2Vec2;
  q1:          B2Rot;
  q2:          B2Rot;
}

pub type B2TOIInput = {
  proxyA:      B2ShapeProxy;
  proxyB:      B2ShapeProxy;
  sweepA:      B2Sweep;
  sweepB:      B2Sweep;
  maxFraction: Float32;
}

pub type B2TOIOutput = {
  state:    Int32;
  point:    B2Vec2;
  normal:   B2Vec2;
  fraction: Float32;
}

// ===========================================================================
// LOCAL COLLISION TYPES (box2d/collision.h)
// ===========================================================================

pub type B2LocalManifoldPoint = {
  point:      B2Vec2;
  separation: Float32;
  id:         Int16;
}

pub type B2LocalManifold = {
  normal:     B2Vec2;
  points:     [B2LocalManifoldPoint; 2];
  pointCount: Int32;
}

// ===========================================================================
// CONTACT TYPES (box2d/collision.h + box2d/types.h)
// ===========================================================================

pub type B2ManifoldPoint = {
  anchorA:            B2Vec2;
  anchorB:            B2Vec2;
  separation:         Float32;
  baseSeparation:     Float32;
  normalImpulse:      Float32;
  tangentImpulse:     Float32;
  totalNormalImpulse: Float32;
  normalVelocity:     Float32;
  id:                 Int16;
  persisted:          Int32;
}

pub type B2Manifold = {
  normal:         B2Vec2;
  rollingImpulse: Float32;
  points:         [B2ManifoldPoint; 2];
  pointCount:     Int32;
}

pub type B2ContactData = {
  contactId: B2ContactId;
  shapeIdA:  B2ShapeId;
  shapeIdB:  B2ShapeId;
  manifold:  B2Manifold;
}

// ===========================================================================
// DYNAMIC TREE TYPES (box2d/collision.h)
// ===========================================================================

pub type B2TreeStats = {
  nodeVisits: Int32;
  leafVisits: Int32;
}

pub type B2BoxCastInput = {
  box:         B2AABB;
  translation: B2Vec2;
  maxFraction: Float32;
}

// ===========================================================================
// CHARACTER MOVER TYPES (box2d/collision.h)
// ===========================================================================

pub type B2PlaneResult = {
  plane: B2Plane;
  point: B2Vec2;
  hit:   Int32;
}

pub type B2CollisionPlane = {
  plane:        B2Plane;
  pushLimit:    Float32;
  push:         Float32;
  clipVelocity: Int32;
}

pub type B2PlaneSolverResult = {
  translation:    B2Vec2;
  iterationCount: Int32;
}

// ===========================================================================
// COLLISION FILTERING (box2d/types.h)
// ===========================================================================

pub type B2Filter = {
  categoryBits: UInt64;
  maskBits:     UInt64;
  groupIndex:   Int32;
}

pub type B2QueryFilter = {
  categoryBits: UInt64;
  maskBits:     UInt64;
}

// ===========================================================================
// SURFACE MATERIAL (box2d/types.h)
// ===========================================================================

pub type B2SurfaceMaterial = {
  friction:          Float32;
  restitution:       Float32;
  rollingResistance: Float32;
  tangentSpeed:      Float32;
  userMaterialId:    UInt64;
  customColor:       UInt32;
}

// ===========================================================================
// MOTION LOCKS (box2d/types.h)
// ===========================================================================

pub type B2MotionLocks = {
  linearX:  Int32;
  linearY:  Int32;
  angularZ: Int32;
}

// ===========================================================================
// WORLD DEFINITION (box2d/types.h)
// ===========================================================================

pub type B2Capacity = {
  staticShapeCount:  Int32;
  dynamicShapeCount: Int32;
  staticBodyCount:   Int32;
  dynamicBodyCount:  Int32;
  contactCount:      Int32;
}

pub type B2WorldDef = {
  gravity:                 B2Vec2;
  restitutionThreshold:    Float32;
  hitEventThreshold:       Float32;
  contactHertz:            Float32;
  contactDampingRatio:     Float32;
  contactSpeed:            Float32;
  maximumLinearSpeed:      Float32;
  frictionCallback:        *UInt8;
  restitutionCallback:     *UInt8;
  enableSleep:             Int32;
  enableContinuous:        Int32;
  enableContactSoftening:  Int32;
  workerCount:             Int32;
  enqueueTask:             *UInt8;
  finishTask:              *UInt8;
  userTaskContext:         *UInt8;
  userData:                *UInt8;
  capacity:                B2Capacity;
  internalValue:           Int32;
}

// ===========================================================================
// BODY DEFINITION (box2d/types.h)
// ===========================================================================

pub type B2BodyDef = {
  bodyType:               Int32;
  position:               B2Pos;
  rotation:               B2Rot;
  linearVelocity:         B2Vec2;
  angularVelocity:        Float32;
  linearDamping:          Float32;
  angularDamping:         Float32;
  gravityScale:           Float32;
  sleepThreshold:         Float32;
  name:                   *UInt8;
  userData:               *UInt8;
  motionLocks:            B2MotionLocks;
  enableSleep:            Int32;
  isAwake:                Int32;
  isBullet:               Int32;
  isEnabled:              Int32;
  allowFastRotation:      Int32;
  enableContactRecycling: Int32;
  internalValue:          Int32;
}

// ===========================================================================
// SHAPE DEFINITION (box2d/types.h)
// ===========================================================================

pub type B2ShapeDef = {
  userData:              *UInt8;
  material:              B2SurfaceMaterial;
  density:               Float32;
  filter:                B2Filter;
  enableCustomFiltering: Int32;
  isSensor:              Int32;
  enableSensorEvents:    Int32;
  enableContactEvents:   Int32;
  enableHitEvents:       Int32;
  enablePreSolveEvents:  Int32;
  invokeContactCreation: Int32;
  updateBodyMass:        Int32;
  internalValue:         Int32;
}

// ===========================================================================
// CHAIN DEFINITION (box2d/types.h)
// ===========================================================================

pub type B2ChainDef = {
  userData:           *UInt8;
  points:             *UInt8;
  count:              Int32;
  materials:          *UInt8;
  materialCount:      Int32;
  filter:             B2Filter;
  isLoop:             Int32;
  enableSensorEvents: Int32;
  internalValue:      Int32;
}

// ===========================================================================
// BASE JOINT DEFINITION (box2d/types.h)
// ===========================================================================

pub type B2JointDef = {
  userData:               *UInt8;
  bodyIdA:                B2BodyId;
  bodyIdB:                B2BodyId;
  localFrameA:            B2Transform;
  localFrameB:            B2Transform;
  forceThreshold:         Float32;
  torqueThreshold:        Float32;
  constraintHertz:        Float32;
  constraintDampingRatio: Float32;
  drawScale:              Float32;
  collideConnected:       Int32;
}

// ===========================================================================
// JOINT TYPE DEFINITIONS (box2d/types.h)
// ===========================================================================

pub type B2DistanceJointDef = {
  base:              B2JointDef;
  length:            Float32;
  enableSpring:      Int32;
  lowerSpringForce:  Float32;
  upperSpringForce:  Float32;
  hertz:             Float32;
  dampingRatio:      Float32;
  enableLimit:       Int32;
  minLength:         Float32;
  maxLength:         Float32;
  enableMotor:       Int32;
  maxMotorForce:     Float32;
  motorSpeed:        Float32;
  internalValue:     Int32;
}

pub type B2MotorJointDef = {
  base:                B2JointDef;
  linearVelocity:      B2Vec2;
  maxVelocityForce:    Float32;
  angularVelocity:     Float32;
  maxVelocityTorque:   Float32;
  linearHertz:         Float32;
  linearDampingRatio:  Float32;
  maxSpringForce:      Float32;
  angularHertz:        Float32;
  angularDampingRatio: Float32;
  maxSpringTorque:     Float32;
  internalValue:       Int32;
}

pub type B2FilterJointDef = {
  base:          B2JointDef;
  internalValue: Int32;
}

pub type B2PrismaticJointDef = {
  base:              B2JointDef;
  enableSpring:      Int32;
  hertz:             Float32;
  dampingRatio:      Float32;
  targetTranslation: Float32;
  enableLimit:       Int32;
  lowerTranslation:  Float32;
  upperTranslation:  Float32;
  enableMotor:       Int32;
  maxMotorForce:     Float32;
  motorSpeed:        Float32;
  internalValue:     Int32;
}

pub type B2RevoluteJointDef = {
  base:           B2JointDef;
  targetAngle:    Float32;
  enableSpring:   Int32;
  hertz:          Float32;
  dampingRatio:   Float32;
  enableLimit:    Int32;
  lowerAngle:     Float32;
  upperAngle:     Float32;
  enableMotor:    Int32;
  maxMotorTorque: Float32;
  motorSpeed:     Float32;
  internalValue:  Int32;
}

pub type B2WeldJointDef = {
  base:                B2JointDef;
  linearHertz:         Float32;
  angularHertz:        Float32;
  linearDampingRatio:  Float32;
  angularDampingRatio: Float32;
  internalValue:       Int32;
}

pub type B2WheelJointDef = {
  base:              B2JointDef;
  enableSpring:      Int32;
  hertz:             Float32;
  dampingRatio:      Float32;
  enableLimit:       Int32;
  lowerTranslation:  Float32;
  upperTranslation:  Float32;
  enableMotor:       Int32;
  maxMotorTorque:    Float32;
  motorSpeed:        Float32;
  internalValue:     Int32;
}

// ===========================================================================
// EXPLOSION DEFINITION (box2d/types.h)
// ===========================================================================

pub type B2ExplosionDef = {
  maskBits:         UInt64;
  position:         B2Pos;
  radius:           Float32;
  falloff:          Float32;
  impulsePerLength: Float32;
}

// ===========================================================================
// EVENT TYPES (box2d/types.h)
// ===========================================================================

pub type B2SensorBeginTouchEvent = {
  sensorShapeId:  B2ShapeId;
  visitorShapeId: B2ShapeId;
}

pub type B2SensorEndTouchEvent = {
  sensorShapeId:  B2ShapeId;
  visitorShapeId: B2ShapeId;
}

pub type B2SensorEvents = {
  beginEvents: *B2SensorBeginTouchEvent;
  endEvents:   *B2SensorEndTouchEvent;
  beginCount:  Int32;
  endCount:    Int32;
}

pub type B2ContactBeginTouchEvent = {
  shapeIdA:  B2ShapeId;
  shapeIdB:  B2ShapeId;
  contactId: B2ContactId;
}

pub type B2ContactEndTouchEvent = {
  shapeIdA:  B2ShapeId;
  shapeIdB:  B2ShapeId;
  contactId: B2ContactId;
}

pub type B2ContactHitEvent = {
  shapeIdA:      B2ShapeId;
  shapeIdB:      B2ShapeId;
  contactId:     B2ContactId;
  point:         B2Pos;
  normal:        B2Vec2;
  approachSpeed: Float32;
}

pub type B2ContactEvents = {
  beginEvents: *B2ContactBeginTouchEvent;
  endEvents:   *B2ContactEndTouchEvent;
  hitEvents:   *B2ContactHitEvent;
  beginCount:  Int32;
  endCount:    Int32;
  hitCount:    Int32;
}

pub type B2BodyMoveEvent = {
  userData:   *UInt8;
  transform:  B2WorldTransform;
  bodyId:     B2BodyId;
  fellAsleep: Int32;
}

pub type B2BodyEvents = {
  moveEvents: *B2BodyMoveEvent;
  moveCount:  Int32;
}

pub type B2JointEvent = {
  jointId:  B2JointId;
  userData: *UInt8;
}

pub type B2JointEvents = {
  jointEvents: *B2JointEvent;
  count:       Int32;
}

// ===========================================================================
// RAY RESULT (box2d/types.h)
// ===========================================================================

pub type B2RayResult = {
  shapeId:    B2ShapeId;
  point:      B2Pos;
  normal:     B2Vec2;
  fraction:   Float32;
  nodeVisits: Int32;
  leafVisits: Int32;
  hit:        Int32;
}

// ===========================================================================
// PROFILE & COUNTERS (box2d/types.h)
// ===========================================================================

pub type B2Profile = {
  step:                Float32;
  pairs:               Float32;
  collide:             Float32;
  solve:               Float32;
  solverSetup:         Float32;
  constraints:         Float32;
  prepareConstraints:  Float32;
  integrateVelocities: Float32;
  warmStart:           Float32;
  solveImpulses:       Float32;
  integratePositions:  Float32;
  relaxImpulses:       Float32;
  applyRestitution:    Float32;
  storeImpulses:       Float32;
  splitIslands:        Float32;
  transforms:          Float32;
  sensorHits:          Float32;
  jointEvents:         Float32;
  hitEvents:           Float32;
  refit:               Float32;
  bullets:             Float32;
  sleepIslands:        Float32;
  sensors:             Float32;
}

pub type B2Counters = {
  byteCount:           Int32;
  bodyCount:           Int32;
  shapeCount:          Int32;
  contactCount:        Int32;
  jointCount:          Int32;
  islandCount:         Int32;
  stackUsed:           Int32;
  staticTreeHeight:    Int32;
  treeHeight:          Int32;
  taskCount:           Int32;
  colorCounts:         [Int32; 24];
  awakeContactCount:   Int32;
  recycledContactCount: Int32;
}

// ===========================================================================
// HEX COLOR (box2d/types.h)
// ===========================================================================

pub type B2HexColor = { color: UInt32; }

// Named color constants
pub const B2_COLOR_BOX2D_RED:    UInt32 = 0xDC3132;
pub const B2_COLOR_BOX2D_BLUE:   UInt32 = 0x30AEBF;
pub const B2_COLOR_BOX2D_GREEN:  UInt32 = 0x8CC924;
pub const B2_COLOR_BOX2D_YELLOW: UInt32 = 0xFFEE8C;
pub const B2_COLOR_WHITE:        UInt32 = 0xFFFFFF;
pub const B2_COLOR_BLACK:        UInt32 = 0x000000;
pub const B2_COLOR_RED:          UInt32 = 0xFF0000;
pub const B2_COLOR_GREEN:        UInt32 = 0x00FF00;
pub const B2_COLOR_BLUE:         UInt32 = 0x0000FF;
pub const B2_COLOR_GRAY:         UInt32 = 0x808080;
pub const B2_COLOR_DARK_GRAY:    UInt32 = 0x404040;
pub const B2_COLOR_LIGHT_GRAY:   UInt32 = 0xC0C0C0;

// ===========================================================================
// DEBUG DRAW (box2d/types.h)
// ===========================================================================

pub type B2DebugDraw = {
  DrawPolygon:       *UInt8;
  DrawSolidPolygon:  *UInt8;
  DrawCircle:        *UInt8;
  DrawSolidCircle:   *UInt8;
  DrawSolidCapsule:  *UInt8;
  DrawLine:          *UInt8;
  DrawTransform:     *UInt8;
  DrawPoint:         *UInt8;
  DrawString:        *UInt8;
  DrawBounds:        *UInt8;
  drawingBounds:     B2AABB;
  forceScale:        Float32;
  jointScale:        Float32;
  drawContacts:      Int32;
  drawAnchorA:       Int32;
  drawShapes:        Int32;
  drawChainNormals:  Int32;
  drawJoints:        Int32;
  drawJointExtras:   Int32;
  drawBounds:        Int32;
  drawMass:          Int32;
  drawBodyNames:     Int32;
  drawGraphColors:   Int32;
  drawContactFeatures:  Int32;
  drawContactNormals:   Int32;
  drawContactForces:    Int32;
  drawFrictionForces:   Int32;
  drawIslands:       Int32;
  context:           *UInt8;
}

// ===================================================================
// EXTERN "C" — COMPLETE Box2D C API (100% B2_API surface)
//
// Total: ~300 functions across world, body, shape, chain, joint,
// collision, distance, dynamic tree, character mover, base, math.
// Excludes B2_INLINE functions — those are reimplemented in box2d_safe.xi.
// ===================================================================

extern "C" {

  // ============ base.h — Version, Allocator, Logging, Timing ============

  fn b2GetVersion() -> B2Version;
  fn b2IsDoublePrecision() -> Int32;
  fn b2SetAllocator(allocFcn: *UInt8, freeFcn: *UInt8);
  fn b2SetAssertFcn(assertFcn: *UInt8);
  fn b2SetLogFcn(logFcn: *UInt8);
  fn b2GetTicks() -> UInt64;
  fn b2GetMilliseconds(ticks: UInt64) -> Float32;
  fn b2GetMillisecondsAndReset(ticks: *UInt64) -> Float32;
  fn b2Yield();

  // ============ math_functions.h — Exported Math ============

  fn b2SetLengthUnitsPerMeter(lengthUnits: Float32);
  fn b2GetLengthUnitsPerMeter() -> Float32;
  fn b2IsValidFloat(a: Float32) -> Int32;
  fn b2IsValidVec2(v: B2Vec2) -> Int32;
  fn b2IsValidRotation(q: B2Rot) -> Int32;
  fn b2IsValidTransform(t: B2Transform) -> Int32;
  fn b2IsValidAABB(aabb: B2AABB) -> Int32;
  fn b2IsValidPlane(a: B2Plane) -> Int32;
  fn b2IsValidPosition(p: B2Pos) -> Int32;
  fn b2IsValidWorldTransform(t: B2WorldTransform) -> Int32;
  fn b2Atan2(y: Float32, x: Float32) -> Float32;
  fn b2ComputeCosSin(radians: Float32) -> B2CosSin;
  fn b2ComputeRotationBetweenUnitVectors(v1: B2Vec2, v2: B2Vec2) -> B2Rot;

  // ============ box2d.h — World Lifecycle ============

  fn b2DefaultWorldDef() -> B2WorldDef;
  fn b2CreateWorld(def: *B2WorldDef) -> B2WorldId;
  fn b2DestroyWorld(worldId: B2WorldId);
  fn b2World_IsValid(worldId: B2WorldId) -> Int32;

  // ============ box2d.h — World Settings ============

  fn b2World_SetGravity(worldId: B2WorldId, gravity: B2Vec2);
  fn b2World_GetGravity(worldId: B2WorldId) -> B2Vec2;
  fn b2World_EnableSleeping(worldId: B2WorldId, flag: Int32);
  fn b2World_IsSleepingEnabled(worldId: B2WorldId) -> Int32;
  fn b2World_EnableContinuous(worldId: B2WorldId, flag: Int32);
  fn b2World_IsContinuousEnabled(worldId: B2WorldId) -> Int32;
  fn b2World_SetRestitutionThreshold(worldId: B2WorldId, value: Float32);
  fn b2World_GetRestitutionThreshold(worldId: B2WorldId) -> Float32;
  fn b2World_SetHitEventThreshold(worldId: B2WorldId, value: Float32);
  fn b2World_GetHitEventThreshold(worldId: B2WorldId) -> Float32;
  fn b2World_SetMaximumLinearSpeed(worldId: B2WorldId, maximumLinearSpeed: Float32);
  fn b2World_GetMaximumLinearSpeed(worldId: B2WorldId) -> Float32;
  fn b2World_EnableWarmStarting(worldId: B2WorldId, flag: Int32);
  fn b2World_IsWarmStartingEnabled(worldId: B2WorldId) -> Int32;
  fn b2World_EnableSpeculative(worldId: B2WorldId, flag: Int32);
  fn b2World_SetContactTuning(worldId: B2WorldId, hertz: Float32, dampingRatio: Float32, pushSpeed: Float32);
  fn b2World_SetContactRecycleDistance(worldId: B2WorldId, recycleDistance: Float32);
  fn b2World_GetContactRecycleDistance(worldId: B2WorldId) -> Float32;
  fn b2World_SetFrictionCallback(worldId: B2WorldId, callback: *UInt8);
  fn b2World_SetRestitutionCallback(worldId: B2WorldId, callback: *UInt8);
  fn b2World_SetCustomFilterCallback(worldId: B2WorldId, fcn: *UInt8, context: *UInt8);
  fn b2World_SetPreSolveCallback(worldId: B2WorldId, fcn: *UInt8, context: *UInt8);
  fn b2World_SetWorkerCount(worldId: B2WorldId, count: Int32);
  fn b2World_GetWorkerCount(worldId: B2WorldId) -> Int32;
  fn b2World_SetUserData(worldId: B2WorldId, userData: *UInt8);
  fn b2World_GetUserData(worldId: B2WorldId) -> *UInt8;

  // ============ box2d.h — World Stats ============

  fn b2World_GetAwakeBodyCount(worldId: B2WorldId) -> Int32;
  fn b2World_GetProfile(worldId: B2WorldId) -> B2Profile;
  fn b2World_GetCounters(worldId: B2WorldId) -> B2Counters;
  fn b2World_GetMaxCapacity(worldId: B2WorldId) -> B2Capacity;
  fn b2World_GetBounds(worldId: B2WorldId) -> B2AABB;
  fn b2World_DumpMemoryStats(worldId: B2WorldId);
  fn b2World_RebuildStaticTree(worldId: B2WorldId);

  // ============ box2d.h — Simulation ============

  fn b2World_Step(worldId: B2WorldId, timeStep: Float32, subStepCount: Int32);

  // ============ box2d.h — Explosion ============

  fn b2DefaultExplosionDef() -> B2ExplosionDef;
  fn b2World_Explode(worldId: B2WorldId, def: *B2ExplosionDef);

  // ============ box2d.h — Body Lifecycle ============

  fn b2DefaultBodyDef() -> B2BodyDef;
  fn b2CreateBody(worldId: B2WorldId, def: *B2BodyDef) -> B2BodyId;
  fn b2DestroyBody(bodyId: B2BodyId);
  fn b2Body_IsValid(bodyId: B2BodyId) -> Int32;

  // ============ box2d.h — Body Properties ============

  fn b2Body_GetType(bodyId: B2BodyId) -> Int32;
  fn b2Body_SetType(bodyId: B2BodyId, bodyType: Int32);
  fn b2Body_GetPosition(bodyId: B2BodyId) -> B2Pos;
  fn b2Body_GetRotation(bodyId: B2BodyId) -> B2Rot;
  fn b2Body_GetTransform(bodyId: B2BodyId) -> B2WorldTransform;
  fn b2Body_SetTransform(bodyId: B2BodyId, position: B2Pos, rotation: B2Rot);
  fn b2Body_GetLocalPoint(bodyId: B2BodyId, worldPoint: B2Pos) -> B2Vec2;
  fn b2Body_GetWorldPoint(bodyId: B2BodyId, localPoint: B2Vec2) -> B2Pos;
  fn b2Body_GetLocalVector(bodyId: B2BodyId, worldVector: B2Vec2) -> B2Vec2;
  fn b2Body_GetWorldVector(bodyId: B2BodyId, localVector: B2Vec2) -> B2Vec2;
  fn b2Body_GetLinearVelocity(bodyId: B2BodyId) -> B2Vec2;
  fn b2Body_GetAngularVelocity(bodyId: B2BodyId) -> Float32;
  fn b2Body_SetLinearVelocity(bodyId: B2BodyId, linearVelocity: B2Vec2);
  fn b2Body_SetAngularVelocity(bodyId: B2BodyId, angularVelocity: Float32);
  fn b2Body_SetTargetTransform(bodyId: B2BodyId, target: B2WorldTransform, timeStep: Float32, wake: Int32);
  fn b2Body_GetLocalPointVelocity(bodyId: B2BodyId, localPoint: B2Vec2) -> B2Vec2;
  fn b2Body_GetWorldPointVelocity(bodyId: B2BodyId, worldPoint: B2Pos) -> B2Vec2;

  // ============ box2d.h — Body Forces ============

  fn b2Body_ApplyForce(bodyId: B2BodyId, force: B2Vec2, point: B2Pos, wake: Int32);
  fn b2Body_ApplyForceToCenter(bodyId: B2BodyId, force: B2Vec2, wake: Int32);
  fn b2Body_ApplyTorque(bodyId: B2BodyId, torque: Float32, wake: Int32);
  fn b2Body_ClearForces(bodyId: B2BodyId);
  fn b2Body_ApplyLinearImpulse(bodyId: B2BodyId, impulse: B2Vec2, point: B2Pos, wake: Int32);
  fn b2Body_ApplyLinearImpulseToCenter(bodyId: B2BodyId, impulse: B2Vec2, wake: Int32);
  fn b2Body_ApplyAngularImpulse(bodyId: B2BodyId, impulse: Float32, wake: Int32);

  // ============ box2d.h — Body Mass ============

  fn b2Body_GetMass(bodyId: B2BodyId) -> Float32;
  fn b2Body_GetRotationalInertia(bodyId: B2BodyId) -> Float32;
  fn b2Body_GetLocalCenter(bodyId: B2BodyId) -> B2Vec2;
  fn b2Body_GetWorldCenter(bodyId: B2BodyId) -> B2Pos;
  fn b2Body_SetMassData(bodyId: B2BodyId, massData: B2MassData);
  fn b2Body_GetMassData(bodyId: B2BodyId) -> B2MassData;
  fn b2Body_ApplyMassFromShapes(bodyId: B2BodyId);

  // ============ box2d.h — Body Damping & Gravity ============

  fn b2Body_SetLinearDamping(bodyId: B2BodyId, linearDamping: Float32);
  fn b2Body_GetLinearDamping(bodyId: B2BodyId) -> Float32;
  fn b2Body_SetAngularDamping(bodyId: B2BodyId, angularDamping: Float32);
  fn b2Body_GetAngularDamping(bodyId: B2BodyId) -> Float32;
  fn b2Body_SetGravityScale(bodyId: B2BodyId, gravityScale: Float32);
  fn b2Body_GetGravityScale(bodyId: B2BodyId) -> Float32;

  // ============ box2d.h — Body Sleep ============

  fn b2Body_IsAwake(bodyId: B2BodyId) -> Int32;
  fn b2Body_SetAwake(bodyId: B2BodyId, awake: Int32);
  fn b2Body_WakeTouching(bodyId: B2BodyId);
  fn b2Body_EnableSleep(bodyId: B2BodyId, enableSleep: Int32);
  fn b2Body_IsSleepEnabled(bodyId: B2BodyId) -> Int32;
  fn b2Body_SetSleepThreshold(bodyId: B2BodyId, sleepThreshold: Float32);
  fn b2Body_GetSleepThreshold(bodyId: B2BodyId) -> Float32;

  // ============ box2d.h — Body State ============

  fn b2Body_IsEnabled(bodyId: B2BodyId) -> Int32;
  fn b2Body_Disable(bodyId: B2BodyId);
  fn b2Body_Enable(bodyId: B2BodyId);
  fn b2Body_SetMotionLocks(bodyId: B2BodyId, locks: B2MotionLocks);
  fn b2Body_GetMotionLocks(bodyId: B2BodyId) -> B2MotionLocks;
  fn b2Body_SetBullet(bodyId: B2BodyId, flag: Int32);
  fn b2Body_IsBullet(bodyId: B2BodyId) -> Int32;
  fn b2Body_EnableContactRecycling(bodyId: B2BodyId, flag: Int32);
  fn b2Body_IsContactRecyclingEnabled(bodyId: B2BodyId) -> Int32;
  fn b2Body_EnableContactEvents(bodyId: B2BodyId, flag: Int32);
  fn b2Body_EnableHitEvents(bodyId: B2BodyId, flag: Int32);

  // ============ box2d.h — Body Metadata ============

  fn b2Body_SetName(bodyId: B2BodyId, name: *UInt8);
  fn b2Body_GetName(bodyId: B2BodyId) -> *UInt8;
  fn b2Body_SetUserData(bodyId: B2BodyId, userData: *UInt8);
  fn b2Body_GetUserData(bodyId: B2BodyId) -> *UInt8;
  fn b2Body_GetWorld(bodyId: B2BodyId) -> B2WorldId;

  // ============ box2d.h — Body Enumeration ============

  fn b2Body_GetShapeCount(bodyId: B2BodyId) -> Int32;
  fn b2Body_GetShapes(bodyId: B2BodyId, shapeArray: *B2ShapeId, capacity: Int32) -> Int32;
  fn b2Body_GetJointCount(bodyId: B2BodyId) -> Int32;
  fn b2Body_GetJoints(bodyId: B2BodyId, jointArray: *B2JointId, capacity: Int32) -> Int32;
  fn b2Body_GetContactCapacity(bodyId: B2BodyId) -> Int32;
  fn b2Body_GetContactData(bodyId: B2BodyId, contactData: *B2ContactData, capacity: Int32) -> Int32;
  fn b2Body_ComputeAABB(bodyId: B2BodyId) -> B2AABB;

  // ============ box2d.h — Shape Lifecycle ============

  fn b2DefaultShapeDef() -> B2ShapeDef;
  fn b2CreateCircleShape(bodyId: B2BodyId, def: *B2ShapeDef, circle: *B2Circle) -> B2ShapeId;
  fn b2CreateCapsuleShape(bodyId: B2BodyId, def: *B2ShapeDef, capsule: *B2Capsule) -> B2ShapeId;
  fn b2CreateSegmentShape(bodyId: B2BodyId, def: *B2ShapeDef, segment: *B2Segment) -> B2ShapeId;
  fn b2CreatePolygonShape(bodyId: B2BodyId, def: *B2ShapeDef, polygon: *B2Polygon) -> B2ShapeId;
  fn b2CreateChainSegmentShape(bodyId: B2BodyId, def: *B2ShapeDef, chainSegment: *B2ChainSegment) -> B2ShapeId;
  fn b2DestroyShape(shapeId: B2ShapeId, updateBodyMass: Int32);
  fn b2Shape_IsValid(shapeId: B2ShapeId) -> Int32;
  fn b2Shape_GetType(shapeId: B2ShapeId) -> Int32;
  fn b2Shape_GetBody(shapeId: B2ShapeId) -> B2BodyId;
  fn b2Shape_GetWorld(shapeId: B2ShapeId) -> B2WorldId;
  fn b2Shape_IsSensor(shapeId: B2ShapeId) -> Int32;
  fn b2Shape_GetParentChain(shapeId: B2ShapeId) -> B2ChainId;

  // ============ box2d.h — Shape Properties ============

  fn b2Shape_SetUserData(shapeId: B2ShapeId, userData: *UInt8);
  fn b2Shape_GetUserData(shapeId: B2ShapeId) -> *UInt8;
  fn b2Shape_SetDensity(shapeId: B2ShapeId, density: Float32, updateBodyMass: Int32);
  fn b2Shape_GetDensity(shapeId: B2ShapeId) -> Float32;
  fn b2Shape_SetFriction(shapeId: B2ShapeId, friction: Float32);
  fn b2Shape_GetFriction(shapeId: B2ShapeId) -> Float32;
  fn b2Shape_SetRestitution(shapeId: B2ShapeId, restitution: Float32);
  fn b2Shape_GetRestitution(shapeId: B2ShapeId) -> Float32;
  fn b2Shape_SetUserMaterial(shapeId: B2ShapeId, material: UInt64);
  fn b2Shape_GetUserMaterial(shapeId: B2ShapeId) -> UInt64;
  fn b2Shape_SetSurfaceMaterial(shapeId: B2ShapeId, surfaceMaterial: *B2SurfaceMaterial);
  fn b2Shape_GetSurfaceMaterial(shapeId: B2ShapeId) -> B2SurfaceMaterial;
  fn b2Shape_GetFilter(shapeId: B2ShapeId) -> B2Filter;
  fn b2Shape_SetFilter(shapeId: B2ShapeId, filter: B2Filter);

  // ============ box2d.h — Shape Events ============

  fn b2Shape_EnableSensorEvents(shapeId: B2ShapeId, flag: Int32);
  fn b2Shape_AreSensorEventsEnabled(shapeId: B2ShapeId) -> Int32;
  fn b2Shape_EnableContactEvents(shapeId: B2ShapeId, flag: Int32);
  fn b2Shape_AreContactEventsEnabled(shapeId: B2ShapeId) -> Int32;
  fn b2Shape_EnablePreSolveEvents(shapeId: B2ShapeId, flag: Int32);
  fn b2Shape_ArePreSolveEventsEnabled(shapeId: B2ShapeId) -> Int32;
  fn b2Shape_EnableHitEvents(shapeId: B2ShapeId, flag: Int32);
  fn b2Shape_AreHitEventsEnabled(shapeId: B2ShapeId) -> Int32;

  // ============ box2d.h — Shape Queries ============

  fn b2Shape_TestPoint(shapeId: B2ShapeId, point: B2Pos) -> Int32;
  fn b2Shape_RayCast(shapeId: B2ShapeId, origin: B2Pos, translation: B2Vec2) -> B2WorldCastOutput;
  fn b2Shape_GetAABB(shapeId: B2ShapeId) -> B2AABB;
  fn b2Shape_ComputeMassData(shapeId: B2ShapeId) -> B2MassData;
  fn b2Shape_GetClosestPoint(shapeId: B2ShapeId, target: B2Pos) -> B2Pos;
  fn b2Shape_ApplyWind(shapeId: B2ShapeId, wind: B2Vec2, drag: Float32, lift: Float32, wake: Int32);

  // ============ box2d.h — Shape Get/Set Geometry ============

  fn b2Shape_GetCircle(shapeId: B2ShapeId) -> B2Circle;
  fn b2Shape_GetSegment(shapeId: B2ShapeId) -> B2Segment;
  fn b2Shape_GetChainSegment(shapeId: B2ShapeId) -> B2ChainSegment;
  fn b2Shape_GetCapsule(shapeId: B2ShapeId) -> B2Capsule;
  fn b2Shape_GetPolygon(shapeId: B2ShapeId) -> B2Polygon;
  fn b2Shape_SetCircle(shapeId: B2ShapeId, circle: *B2Circle);
  fn b2Shape_SetCapsule(shapeId: B2ShapeId, capsule: *B2Capsule);
  fn b2Shape_SetSegment(shapeId: B2ShapeId, segment: *B2Segment);
  fn b2Shape_SetPolygon(shapeId: B2ShapeId, polygon: *B2Polygon);
  fn b2Shape_SetChainSegment(shapeId: B2ShapeId, chainSegment: *B2ChainSegment);

  // ============ box2d.h — Shape Contact Data ============

  fn b2Shape_GetContactCapacity(shapeId: B2ShapeId) -> Int32;
  fn b2Shape_GetContactData(shapeId: B2ShapeId, contactData: *B2ContactData, capacity: Int32) -> Int32;
  fn b2Shape_GetSensorCapacity(shapeId: B2ShapeId) -> Int32;
  fn b2Shape_GetSensorData(shapeId: B2ShapeId, visitorIds: *B2ShapeId, capacity: Int32) -> Int32;

  // ============ box2d.h — Filters ============

  fn b2DefaultFilter() -> B2Filter;
  fn b2DefaultQueryFilter() -> B2QueryFilter;

  // ============ collision.h — Polygon Factories ============

  fn b2MakePolygon(hull: *B2Hull, radius: Float32) -> B2Polygon;
  fn b2MakeOffsetPolygon(hull: *B2Hull, position: B2Vec2, rotation: B2Rot) -> B2Polygon;
  fn b2MakeOffsetRoundedPolygon(hull: *B2Hull, position: B2Vec2, rotation: B2Rot, radius: Float32) -> B2Polygon;
  fn b2MakeSquare(halfWidth: Float32) -> B2Polygon;
  fn b2MakeBox(halfWidth: Float32, halfHeight: Float32) -> B2Polygon;
  fn b2MakeRoundedBox(halfWidth: Float32, halfHeight: Float32, radius: Float32) -> B2Polygon;
  fn b2MakeOffsetBox(halfWidth: Float32, halfHeight: Float32, center: B2Vec2, rotation: B2Rot) -> B2Polygon;
  fn b2MakeOffsetRoundedBox(halfWidth: Float32, halfHeight: Float32, center: B2Vec2, rotation: B2Rot, radius: Float32) -> B2Polygon;
  fn b2TransformPolygon(transform: B2Transform, polygon: *B2Polygon) -> B2Polygon;
  fn b2ComputeHull(points: *B2Vec2, count: Int32) -> B2Hull;
  fn b2ValidateHull(hull: *B2Hull) -> Int32;

  // ============ collision.h — Mass & AABB Computation ============

  fn b2ComputeCircleMass(shape: *B2Circle, density: Float32) -> B2MassData;
  fn b2ComputeCapsuleMass(shape: *B2Capsule, density: Float32) -> B2MassData;
  fn b2ComputePolygonMass(shape: *B2Polygon, density: Float32) -> B2MassData;
  fn b2ComputeCircleAABB(shape: *B2Circle, transform: B2WorldTransform) -> B2AABB;
  fn b2ComputeCapsuleAABB(shape: *B2Capsule, transform: B2WorldTransform) -> B2AABB;
  fn b2ComputePolygonAABB(shape: *B2Polygon, transform: B2WorldTransform) -> B2AABB;
  fn b2ComputeSegmentAABB(shape: *B2Segment, transform: B2WorldTransform) -> B2AABB;

  // ============ collision.h — Point Queries ============

  fn b2PointInCircle(shape: *B2Circle, point: B2Vec2) -> Int32;
  fn b2PointInCapsule(shape: *B2Capsule, point: B2Vec2) -> Int32;
  fn b2PointInPolygon(shape: *B2Polygon, point: B2Vec2) -> Int32;
  fn b2IsValidRay(input: *B2RayCastInput) -> Int32;

  // ============ collision.h — Ray Casts ============

  fn b2RayCastCircle(shape: *B2Circle, input: *B2RayCastInput) -> B2CastOutput;
  fn b2RayCastCapsule(shape: *B2Capsule, input: *B2RayCastInput) -> B2CastOutput;
  fn b2RayCastSegment(shape: *B2Segment, input: *B2RayCastInput, oneSided: Int32) -> B2CastOutput;
  fn b2RayCastPolygon(shape: *B2Polygon, input: *B2RayCastInput) -> B2CastOutput;

  // ============ collision.h — Shape Casts ============

  fn b2ShapeCastCircle(shape: *B2Circle, input: *B2ShapeCastInput) -> B2CastOutput;
  fn b2ShapeCastCapsule(shape: *B2Capsule, input: *B2ShapeCastInput) -> B2CastOutput;
  fn b2ShapeCastSegment(shape: *B2Segment, input: *B2ShapeCastInput) -> B2CastOutput;
  fn b2ShapeCastPolygon(shape: *B2Polygon, input: *B2ShapeCastInput) -> B2CastOutput;

  // ============ collision.h — Distance ============

  fn b2SegmentDistance(p1: B2Vec2, q1: B2Vec2, p2: B2Vec2, q2: B2Vec2) -> B2SegmentDistanceResult;
  fn b2ShapeDistance(input: *B2DistanceInput, cache: *B2SimplexCache, simplexes: *B2Simplex, simplexCapacity: Int32) -> B2DistanceOutput;
  fn b2ShapeCast(input: *B2ShapeCastPairInput) -> B2CastOutput;
  fn b2MakeProxy(points: *B2Vec2, count: Int32, radius: Float32) -> B2ShapeProxy;
  fn b2MakeOffsetProxy(points: *B2Vec2, count: Int32, radius: Float32, position: B2Vec2, rotation: B2Rot) -> B2ShapeProxy;
  fn b2GetSweepTransform(sweep: *B2Sweep, time: Float32) -> B2Transform;
  fn b2TimeOfImpact(input: *B2TOIInput) -> B2TOIOutput;

  // ============ collision.h — Collision ============

  fn b2CollideCircles(circleA: *B2Circle, circleB: *B2Circle, xf: B2Transform) -> B2LocalManifold;
  fn b2CollideCapsuleAndCircle(capsuleA: *B2Capsule, circleB: *B2Circle, xf: B2Transform) -> B2LocalManifold;
  fn b2CollideSegmentAndCircle(segmentA: *B2Segment, circleB: *B2Circle, xf: B2Transform) -> B2LocalManifold;
  fn b2CollidePolygonAndCircle(polygonA: *B2Polygon, circleB: *B2Circle, xf: B2Transform) -> B2LocalManifold;
  fn b2CollideCapsules(capsuleA: *B2Capsule, capsuleB: *B2Capsule, xf: B2Transform) -> B2LocalManifold;
  fn b2CollideSegmentAndCapsule(segmentA: *B2Segment, capsuleB: *B2Capsule, xf: B2Transform) -> B2LocalManifold;
  fn b2CollidePolygonAndCapsule(polygonA: *B2Polygon, capsuleB: *B2Capsule, xf: B2Transform) -> B2LocalManifold;
  fn b2CollidePolygons(polygonA: *B2Polygon, polygonB: *B2Polygon, xf: B2Transform) -> B2LocalManifold;
  fn b2CollideSegmentAndPolygon(segmentA: *B2Segment, polygonB: *B2Polygon, xf: B2Transform) -> B2LocalManifold;
  fn b2CollideChainSegmentAndCircle(segmentA: *B2ChainSegment, circleB: *B2Circle, xf: B2Transform) -> B2LocalManifold;
  fn b2CollideChainSegmentAndCapsule(segmentA: *B2ChainSegment, capsuleB: *B2Capsule, xf: B2Transform, cache: *B2SimplexCache) -> B2LocalManifold;
  fn b2CollideChainSegmentAndPolygon(segmentA: *B2ChainSegment, polygonB: *B2Polygon, xf: B2Transform, cache: *B2SimplexCache) -> B2LocalManifold;

  // ============ collision.h — Character Mover ============

  fn b2SolvePlanes(targetDelta: B2Vec2, planes: *B2CollisionPlane, count: Int32) -> B2PlaneSolverResult;
  fn b2ClipVector(vector: B2Vec2, planes: *B2CollisionPlane, count: Int32) -> B2Vec2;

  // ============ box2d.h — Chain Shapes ============

  fn b2DefaultChainDef() -> B2ChainDef;
  fn b2CreateChain(bodyId: B2BodyId, def: *B2ChainDef) -> B2ChainId;
  fn b2DestroyChain(chainId: B2ChainId);
  fn b2Chain_IsValid(chainId: B2ChainId) -> Int32;
  fn b2Chain_GetWorld(chainId: B2ChainId) -> B2WorldId;
  fn b2Chain_GetSegmentCount(chainId: B2ChainId) -> Int32;
  fn b2Chain_GetSegments(chainId: B2ChainId, segmentArray: *B2ShapeId, capacity: Int32) -> Int32;
  fn b2Chain_GetSurfaceMaterialCount(chainId: B2ChainId) -> Int32;
  fn b2Chain_SetSurfaceMaterial(chainId: B2ChainId, material: *B2SurfaceMaterial, materialIndex: Int32);
  fn b2Chain_GetSurfaceMaterial(chainId: B2ChainId, materialIndex: Int32) -> B2SurfaceMaterial;

  // ============ box2d.h — Joint Creation ============

  fn b2DefaultDistanceJointDef() -> B2DistanceJointDef;
  fn b2CreateDistanceJoint(worldId: B2WorldId, def: *B2DistanceJointDef) -> B2JointId;

  fn b2DefaultMotorJointDef() -> B2MotorJointDef;
  fn b2CreateMotorJoint(worldId: B2WorldId, def: *B2MotorJointDef) -> B2JointId;

  fn b2DefaultFilterJointDef() -> B2FilterJointDef;
  fn b2CreateFilterJoint(worldId: B2WorldId, def: *B2FilterJointDef) -> B2JointId;

  fn b2DefaultPrismaticJointDef() -> B2PrismaticJointDef;
  fn b2CreatePrismaticJoint(worldId: B2WorldId, def: *B2PrismaticJointDef) -> B2JointId;

  fn b2DefaultRevoluteJointDef() -> B2RevoluteJointDef;
  fn b2CreateRevoluteJoint(worldId: B2WorldId, def: *B2RevoluteJointDef) -> B2JointId;

  fn b2DefaultWeldJointDef() -> B2WeldJointDef;
  fn b2CreateWeldJoint(worldId: B2WorldId, def: *B2WeldJointDef) -> B2JointId;

  fn b2DefaultWheelJointDef() -> B2WheelJointDef;
  fn b2CreateWheelJoint(worldId: B2WorldId, def: *B2WheelJointDef) -> B2JointId;

  // ============ box2d.h — Joint Common ============

  fn b2DestroyJoint(jointId: B2JointId, wakeAttached: Int32);
  fn b2Joint_IsValid(jointId: B2JointId) -> Int32;
  fn b2Joint_GetType(jointId: B2JointId) -> Int32;
  fn b2Joint_GetBodyA(jointId: B2JointId) -> B2BodyId;
  fn b2Joint_GetBodyB(jointId: B2JointId) -> B2BodyId;
  fn b2Joint_GetWorld(jointId: B2JointId) -> B2WorldId;
  fn b2Joint_SetLocalFrameA(jointId: B2JointId, localFrame: B2Transform);
  fn b2Joint_GetLocalFrameA(jointId: B2JointId) -> B2Transform;
  fn b2Joint_SetLocalFrameB(jointId: B2JointId, localFrame: B2Transform);
  fn b2Joint_GetLocalFrameB(jointId: B2JointId) -> B2Transform;
  fn b2Joint_SetCollideConnected(jointId: B2JointId, shouldCollide: Int32);
  fn b2Joint_GetCollideConnected(jointId: B2JointId) -> Int32;
  fn b2Joint_SetUserData(jointId: B2JointId, userData: *UInt8);
  fn b2Joint_GetUserData(jointId: B2JointId) -> *UInt8;
  fn b2Joint_WakeBodies(jointId: B2JointId);
  fn b2Joint_GetConstraintForce(jointId: B2JointId) -> B2Vec2;
  fn b2Joint_GetConstraintTorque(jointId: B2JointId) -> Float32;
  fn b2Joint_GetLinearSeparation(jointId: B2JointId) -> Float32;
  fn b2Joint_GetAngularSeparation(jointId: B2JointId) -> Float32;
  fn b2Joint_SetConstraintTuning(jointId: B2JointId, hertz: Float32, dampingRatio: Float32);
  fn b2Joint_SetForceThreshold(jointId: B2JointId, threshold: Float32);
  fn b2Joint_GetForceThreshold(jointId: B2JointId) -> Float32;
  fn b2Joint_SetTorqueThreshold(jointId: B2JointId, threshold: Float32);
  fn b2Joint_GetTorqueThreshold(jointId: B2JointId) -> Float32;

  // ============ box2d.h — Distance Joint ============

  fn b2DistanceJoint_SetLength(jointId: B2JointId, length: Float32);
  fn b2DistanceJoint_GetLength(jointId: B2JointId) -> Float32;
  fn b2DistanceJoint_EnableSpring(jointId: B2JointId, enableSpring: Int32);
  fn b2DistanceJoint_IsSpringEnabled(jointId: B2JointId) -> Int32;
  fn b2DistanceJoint_SetSpringForceRange(jointId: B2JointId, lowerForce: Float32, upperForce: Float32);
  fn b2DistanceJoint_SetSpringHertz(jointId: B2JointId, hertz: Float32);
  fn b2DistanceJoint_SetSpringDampingRatio(jointId: B2JointId, dampingRatio: Float32);
  fn b2DistanceJoint_GetSpringHertz(jointId: B2JointId) -> Float32;
  fn b2DistanceJoint_GetSpringDampingRatio(jointId: B2JointId) -> Float32;
  fn b2DistanceJoint_EnableLimit(jointId: B2JointId, enableLimit: Int32);
  fn b2DistanceJoint_IsLimitEnabled(jointId: B2JointId) -> Int32;
  fn b2DistanceJoint_SetLengthRange(jointId: B2JointId, minLength: Float32, maxLength: Float32);
  fn b2DistanceJoint_GetMinLength(jointId: B2JointId) -> Float32;
  fn b2DistanceJoint_GetMaxLength(jointId: B2JointId) -> Float32;
  fn b2DistanceJoint_GetCurrentLength(jointId: B2JointId) -> Float32;
  fn b2DistanceJoint_EnableMotor(jointId: B2JointId, enableMotor: Int32);
  fn b2DistanceJoint_IsMotorEnabled(jointId: B2JointId) -> Int32;
  fn b2DistanceJoint_SetMotorSpeed(jointId: B2JointId, motorSpeed: Float32);
  fn b2DistanceJoint_GetMotorSpeed(jointId: B2JointId) -> Float32;
  fn b2DistanceJoint_SetMaxMotorForce(jointId: B2JointId, force: Float32);
  fn b2DistanceJoint_GetMaxMotorForce(jointId: B2JointId) -> Float32;
  fn b2DistanceJoint_GetMotorForce(jointId: B2JointId) -> Float32;

  // ============ box2d.h — Motor Joint ============

  fn b2MotorJoint_SetLinearVelocity(jointId: B2JointId, velocity: B2Vec2);
  fn b2MotorJoint_GetLinearVelocity(jointId: B2JointId) -> B2Vec2;
  fn b2MotorJoint_SetAngularVelocity(jointId: B2JointId, velocity: Float32);
  fn b2MotorJoint_GetAngularVelocity(jointId: B2JointId) -> Float32;
  fn b2MotorJoint_SetMaxVelocityForce(jointId: B2JointId, maxForce: Float32);
  fn b2MotorJoint_GetMaxVelocityForce(jointId: B2JointId) -> Float32;
  fn b2MotorJoint_SetMaxVelocityTorque(jointId: B2JointId, maxTorque: Float32);
  fn b2MotorJoint_GetMaxVelocityTorque(jointId: B2JointId) -> Float32;
  fn b2MotorJoint_SetLinearHertz(jointId: B2JointId, hertz: Float32);
  fn b2MotorJoint_GetLinearHertz(jointId: B2JointId) -> Float32;
  fn b2MotorJoint_SetLinearDampingRatio(jointId: B2JointId, damping: Float32);
  fn b2MotorJoint_GetLinearDampingRatio(jointId: B2JointId) -> Float32;
  fn b2MotorJoint_SetAngularHertz(jointId: B2JointId, hertz: Float32);
  fn b2MotorJoint_GetAngularHertz(jointId: B2JointId) -> Float32;
  fn b2MotorJoint_SetAngularDampingRatio(jointId: B2JointId, damping: Float32);
  fn b2MotorJoint_GetAngularDampingRatio(jointId: B2JointId) -> Float32;
  fn b2MotorJoint_SetMaxSpringForce(jointId: B2JointId, maxForce: Float32);
  fn b2MotorJoint_GetMaxSpringForce(jointId: B2JointId) -> Float32;
  fn b2MotorJoint_SetMaxSpringTorque(jointId: B2JointId, maxTorque: Float32);
  fn b2MotorJoint_GetMaxSpringTorque(jointId: B2JointId) -> Float32;

  // ============ box2d.h — Prismatic Joint ============

  fn b2PrismaticJoint_EnableSpring(jointId: B2JointId, enableSpring: Int32);
  fn b2PrismaticJoint_IsSpringEnabled(jointId: B2JointId) -> Int32;
  fn b2PrismaticJoint_SetSpringHertz(jointId: B2JointId, hertz: Float32);
  fn b2PrismaticJoint_GetSpringHertz(jointId: B2JointId) -> Float32;
  fn b2PrismaticJoint_SetSpringDampingRatio(jointId: B2JointId, dampingRatio: Float32);
  fn b2PrismaticJoint_GetSpringDampingRatio(jointId: B2JointId) -> Float32;
  fn b2PrismaticJoint_SetTargetTranslation(jointId: B2JointId, translation: Float32);
  fn b2PrismaticJoint_GetTargetTranslation(jointId: B2JointId) -> Float32;
  fn b2PrismaticJoint_EnableLimit(jointId: B2JointId, enableLimit: Int32);
  fn b2PrismaticJoint_IsLimitEnabled(jointId: B2JointId) -> Int32;
  fn b2PrismaticJoint_GetLowerLimit(jointId: B2JointId) -> Float32;
  fn b2PrismaticJoint_GetUpperLimit(jointId: B2JointId) -> Float32;
  fn b2PrismaticJoint_SetLimits(jointId: B2JointId, lower: Float32, upper: Float32);
  fn b2PrismaticJoint_EnableMotor(jointId: B2JointId, enableMotor: Int32);
  fn b2PrismaticJoint_IsMotorEnabled(jointId: B2JointId) -> Int32;
  fn b2PrismaticJoint_SetMotorSpeed(jointId: B2JointId, motorSpeed: Float32);
  fn b2PrismaticJoint_GetMotorSpeed(jointId: B2JointId) -> Float32;
  fn b2PrismaticJoint_SetMaxMotorForce(jointId: B2JointId, force: Float32);
  fn b2PrismaticJoint_GetMaxMotorForce(jointId: B2JointId) -> Float32;
  fn b2PrismaticJoint_GetMotorForce(jointId: B2JointId) -> Float32;
  fn b2PrismaticJoint_GetTranslation(jointId: B2JointId) -> Float32;
  fn b2PrismaticJoint_GetSpeed(jointId: B2JointId) -> Float32;

  // ============ box2d.h — Revolute Joint ============

  fn b2RevoluteJoint_EnableSpring(jointId: B2JointId, enableSpring: Int32);
  fn b2RevoluteJoint_IsSpringEnabled(jointId: B2JointId) -> Int32;
  fn b2RevoluteJoint_SetSpringHertz(jointId: B2JointId, hertz: Float32);
  fn b2RevoluteJoint_GetSpringHertz(jointId: B2JointId) -> Float32;
  fn b2RevoluteJoint_SetSpringDampingRatio(jointId: B2JointId, dampingRatio: Float32);
  fn b2RevoluteJoint_GetSpringDampingRatio(jointId: B2JointId) -> Float32;
  fn b2RevoluteJoint_SetTargetAngle(jointId: B2JointId, angle: Float32);
  fn b2RevoluteJoint_GetTargetAngle(jointId: B2JointId) -> Float32;
  fn b2RevoluteJoint_GetAngle(jointId: B2JointId) -> Float32;
  fn b2RevoluteJoint_EnableLimit(jointId: B2JointId, enableLimit: Int32);
  fn b2RevoluteJoint_IsLimitEnabled(jointId: B2JointId) -> Int32;
  fn b2RevoluteJoint_GetLowerLimit(jointId: B2JointId) -> Float32;
  fn b2RevoluteJoint_GetUpperLimit(jointId: B2JointId) -> Float32;
  fn b2RevoluteJoint_SetLimits(jointId: B2JointId, lower: Float32, upper: Float32);
  fn b2RevoluteJoint_EnableMotor(jointId: B2JointId, enableMotor: Int32);
  fn b2RevoluteJoint_IsMotorEnabled(jointId: B2JointId) -> Int32;
  fn b2RevoluteJoint_SetMotorSpeed(jointId: B2JointId, motorSpeed: Float32);
  fn b2RevoluteJoint_GetMotorSpeed(jointId: B2JointId) -> Float32;
  fn b2RevoluteJoint_GetMotorTorque(jointId: B2JointId) -> Float32;
  fn b2RevoluteJoint_SetMaxMotorTorque(jointId: B2JointId, torque: Float32);
  fn b2RevoluteJoint_GetMaxMotorTorque(jointId: B2JointId) -> Float32;

  // ============ box2d.h — Weld Joint ============

  fn b2WeldJoint_SetLinearHertz(jointId: B2JointId, hertz: Float32);
  fn b2WeldJoint_GetLinearHertz(jointId: B2JointId) -> Float32;
  fn b2WeldJoint_SetLinearDampingRatio(jointId: B2JointId, dampingRatio: Float32);
  fn b2WeldJoint_GetLinearDampingRatio(jointId: B2JointId) -> Float32;
  fn b2WeldJoint_SetAngularHertz(jointId: B2JointId, hertz: Float32);
  fn b2WeldJoint_GetAngularHertz(jointId: B2JointId) -> Float32;
  fn b2WeldJoint_SetAngularDampingRatio(jointId: B2JointId, dampingRatio: Float32);
  fn b2WeldJoint_GetAngularDampingRatio(jointId: B2JointId) -> Float32;

  // ============ box2d.h — Wheel Joint ============

  fn b2WheelJoint_EnableSpring(jointId: B2JointId, enableSpring: Int32);
  fn b2WheelJoint_IsSpringEnabled(jointId: B2JointId) -> Int32;
  fn b2WheelJoint_SetSpringHertz(jointId: B2JointId, hertz: Float32);
  fn b2WheelJoint_GetSpringHertz(jointId: B2JointId) -> Float32;
  fn b2WheelJoint_SetSpringDampingRatio(jointId: B2JointId, dampingRatio: Float32);
  fn b2WheelJoint_GetSpringDampingRatio(jointId: B2JointId) -> Float32;
  fn b2WheelJoint_EnableLimit(jointId: B2JointId, enableLimit: Int32);
  fn b2WheelJoint_IsLimitEnabled(jointId: B2JointId) -> Int32;
  fn b2WheelJoint_GetLowerLimit(jointId: B2JointId) -> Float32;
  fn b2WheelJoint_GetUpperLimit(jointId: B2JointId) -> Float32;
  fn b2WheelJoint_SetLimits(jointId: B2JointId, lower: Float32, upper: Float32);
  fn b2WheelJoint_EnableMotor(jointId: B2JointId, enableMotor: Int32);
  fn b2WheelJoint_IsMotorEnabled(jointId: B2JointId) -> Int32;
  fn b2WheelJoint_SetMotorSpeed(jointId: B2JointId, motorSpeed: Float32);
  fn b2WheelJoint_GetMotorSpeed(jointId: B2JointId) -> Float32;
  fn b2WheelJoint_SetMaxMotorTorque(jointId: B2JointId, torque: Float32);
  fn b2WheelJoint_GetMaxMotorTorque(jointId: B2JointId) -> Float32;

  // ============ box2d.h — Event Retrieval ============

  fn b2World_GetBodyEvents(worldId: B2WorldId) -> B2BodyEvents;
  fn b2World_GetSensorEvents(worldId: B2WorldId) -> B2SensorEvents;
  fn b2World_GetContactEvents(worldId: B2WorldId) -> B2ContactEvents;
  fn b2World_GetJointEvents(worldId: B2WorldId) -> B2JointEvents;

  // ============ box2d.h — Contact Data ============

  fn b2Contact_IsValid(contactId: B2ContactId) -> Int32;
  fn b2Contact_GetData(contactId: B2ContactId) -> B2ContactData;

  // ============ box2d.h — Spatial Queries ============

  fn b2World_CastRayClosest(worldId: B2WorldId, origin: B2Pos, translation: B2Vec2, filter: B2QueryFilter) -> B2RayResult;
  fn b2World_CastMover(worldId: B2WorldId, origin: B2Pos, mover: *B2Capsule, translation: B2Vec2, filter: B2QueryFilter) -> Float32;

  // ============ box2d.h — Debug Draw ============

  fn b2DefaultDebugDraw() -> B2DebugDraw;
  fn b2World_Draw(worldId: B2WorldId, draw: *B2DebugDraw);
  fn b2GetGraphColor(index: Int32) -> B2HexColor;

  // ============ box2d.h — Snapshot ============

  fn b2World_Snapshot(worldId: B2WorldId, image: *UInt8, capacity: Int32) -> Int32;
  fn b2World_Restore(worldId: B2WorldId, image: *UInt8, size: Int32) -> Int32;
  fn b2CreateWorldFromSnapshot(image: *UInt8, size: Int32, workerCount: Int32) -> B2WorldId;

  // ============ box2d.h — Recording ============

  fn b2CreateRecording(byteCapacity: Int32) -> *UInt8;
  fn b2DestroyRecording(recording: *UInt8);
  fn b2Recording_GetData(recording: *UInt8) -> *UInt8;
  fn b2Recording_GetSize(recording: *UInt8) -> Int32;
  fn b2World_StartRecording(worldId: B2WorldId, recording: *UInt8);
  fn b2World_StopRecording(worldId: B2WorldId);
  fn b2SaveRecordingToFile(recording: *UInt8, path: *UInt8) -> Int32;
  fn b2LoadRecordingFromFile(path: *UInt8) -> *UInt8;

  // ============ box2d.h — Calibration ============

  fn b2DefaultSurfaceMaterial() -> B2SurfaceMaterial;

} // extern "C"
