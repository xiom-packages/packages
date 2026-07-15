// XIOM — Box2D Physics Engine FFI Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level FFI declarations for the Box2D C API (box2d.dll / libbox2d.so).
// Box2D v4+ uses a pure C handle-based API. All objects are POD structs
// passed by value — no C++ classes, no vtables, no inheritance.
//
// COMPILER GAPS — see AUDIT.md for detailed analysis of:
//   1. Struct-by-value ABI: Box2D handles and math types are POD structs
//      passed/returned by value. Xiom extern blocks may not support this
//      calling convention yet. Recommendation: C bridge or ABI flattening.
//   2. Inline math functions: b2Add, b2Mul, b2Normalize, etc. are B2_INLINE
//      and not exported from the DLL. Must be reimplemented.
//   3. Callback function pointers: Query, filter, and pre-solve callbacks
//      require C function pointer support in extern blocks.
//   4. Double-precision variant: b2Pos / b2WorldTransform change layout.
//      Runtime check via b2IsDoublePrecision().
module xiom.box2d

// ===========================================================================
// OPAQUE HANDLE TYPES (layout matches C box2d/id.h)
//
// All handles are small POD structs — zero-initialization produces a null
// handle. Store/load helpers are available for persistence.
// These are passed BY VALUE in the Box2D C API.
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
// MATH TYPES (layout matches C box2d/math_functions.h)
//
// IMPORTANT: Most math functions (b2Add, b2Mul, b2Normalize, etc.) are
// B2_INLINE in the C headers and NOT exported from the shared library.
// Reimplemented in box2d_safe.xi. See AUDIT.md §2.
// ===========================================================================

pub type B2Vec2 = { x: Float32; y: Float32; }
pub type B2Rot  = { c: Float32; s: Float32; }

pub type B2Transform = { p: B2Vec2; q: B2Rot; }
pub type B2Mat22     = { cx: B2Vec2; cy: B2Vec2; }
pub type B2AABB      = { lowerBound: B2Vec2; upperBound: B2Vec2; }
pub type B2Plane     = { normal: B2Vec2; offset: Float32; }

// b2CosSin (used by b2ComputeCosSin — inline, not exported)
pub type B2CosSin = { cosine: Float32; sine: Float32; }

// World-precision types (double or float depending on BOX2D_DOUBLE_PRECISION)
pub type B2Pos = { x: Float64; y: Float64; }

pub type B2WorldTransform = { p: B2Pos; q: B2Rot; }

// ===========================================================================
// ENUMERATIONS (C enums → Xiom Int32 values)
// ===========================================================================

pub const B2_STATIC_BODY:    Int32 = 0;
pub const B2_KINEMATIC_BODY: Int32 = 1;
pub const B2_DYNAMIC_BODY:   Int32 = 2;

pub const B2_CIRCLE_SHAPE:       Int32 = 0;
pub const B2_CAPSULE_SHAPE:      Int32 = 1;
pub const B2_SEGMENT_SHAPE:      Int32 = 2;
pub const B2_POLYGON_SHAPE:      Int32 = 3;
pub const B2_CHAIN_SEGMENT_SHAPE: Int32 = 4;

pub const B2_DISTANCE_JOINT:  Int32 = 0;
pub const B2_FILTER_JOINT:    Int32 = 1;
pub const B2_MOTOR_JOINT:     Int32 = 2;
pub const B2_PRISMATIC_JOINT: Int32 = 3;
pub const B2_REVOLUTE_JOINT:  Int32 = 4;
pub const B2_WELD_JOINT:      Int32 = 5;
pub const B2_WHEEL_JOINT:     Int32 = 6;

// ===========================================================================
// TUNING CONSTANTS (box2d/constants.h)
// ===========================================================================

pub const B2_MAX_POLYGON_VERTICES: Int32 = 8;
pub const B2_MAX_WORKERS:          Int32 = 32;
pub const B2_NAME_LENGTH:          Int32 = 10;
pub const B2_PI:                   Float32 = 3.14159265359;

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

// ===========================================================================
// MASS DATA
// ===========================================================================

pub type B2MassData = {
  mass:              Float32;
  center:            B2Vec2;
  rotationalInertia: Float32;
}

// ===========================================================================
// COLLISION FILTERING
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
// SURFACE MATERIAL
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
// MOTION LOCKS
// ===========================================================================

pub type B2MotionLocks = {
  linearX:  Int32;
  linearY:  Int32;
  angularZ: Int32;
}

// ===========================================================================
// WORLD DEFINITION & LIFECYCLE
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
// BODY DEFINITION & LIFECYCLE
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
// SHAPE DEFINITION
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
// CHAIN DEFINITION
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
// BASE JOINT DEFINITION
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
// JOINT TYPE DEFINITIONS
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
  base:               B2JointDef;
  linearVelocity:     B2Vec2;
  maxVelocityForce:   Float32;
  angularVelocity:    Float32;
  maxVelocityTorque:  Float32;
  linearHertz:        Float32;
  linearDampingRatio: Float32;
  maxSpringForce:     Float32;
  angularHertz:       Float32;
  angularDampingRatio: Float32;
  maxSpringTorque:    Float32;
  internalValue:      Int32;
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
// EXPLOSION DEFINITION
// ===========================================================================

pub type B2ExplosionDef = {
  maskBits:         UInt64;
  position:         B2Pos;
  radius:           Float32;
  falloff:          Float32;
  impulsePerLength: Float32;
}

// ===========================================================================
// EVENT TYPES (transient arrays returned after b2World_Step)
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
// CONTACT DATA (per-contact manifold)
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
// RAY & SHAPE CAST RESULTS
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
// VERSION
// ===========================================================================

pub type B2Version = {
  major:    Int32;
  minor:    Int32;
  revision: Int32;
}

// ===========================================================================
// DEBUG DRAW (callback-based — requires callback FFI support)
// ===========================================================================

pub type B2HexColor = { color: UInt32; }

pub type B2DebugDraw = {
  DrawPolygon:          *UInt8;
  DrawSolidPolygon:     *UInt8;
  DrawCircle:           *UInt8;
  DrawSolidCircle:      *UInt8;
  DrawCapsule:          *UInt8;
  DrawSolidCapsule:     *UInt8;
  DrawSegment:          *UInt8;
  DrawTransform:        *UInt8;
  DrawPoint:            *UInt8;
  DrawString:           *UInt8;
  drawingBounds:        B2AABB;
  useDrawingBounds:     Int32;
  drawShapes:           Int32;
  drawJoints:           Int32;
  drawJointExtras:      Int32;
  drawAABBs:            Int32;
  drawMass:             Int32;
  drawBodyNames:        Int32;
  drawContacts:         Int32;
  drawGraphColors:      Int32;
  drawContactNormals:   Int32;
  drawContactImpulses:  Int32;
  drawFrictionImpulses: Int32;
  context:              *UInt8;
}

// ===========================================================================
// EXTERN "C" — RAW BOX2D C API
//
// WARNING: Box2D passes/returns handles and math types BY VALUE.
// Xiom's extern "C" ABI support for POD struct types may be incomplete.
// If the compiler cannot match the C ABI for these signatures,
// a C bridge library with flattened (pointer/primitive-only) wrappers
// is required. See AUDIT.md §1 for details.
// ===========================================================================

extern "C" {

  // --- Version & Configuration ---

  fn b2GetVersion() -> B2Version;
  fn b2IsDoublePrecision() -> Int32;
  fn b2SetLengthUnitsPerMeter(lengthUnits: Float32);
  fn b2GetLengthUnitsPerMeter() -> Float32;

  // --- World Lifecycle ---

  fn b2DefaultWorldDef() -> B2WorldDef;
  fn b2CreateWorld(def: *B2WorldDef) -> B2WorldId;
  fn b2DestroyWorld(worldId: B2WorldId);
  fn b2World_IsValid(worldId: B2WorldId) -> Int32;

  // --- Simulation ---

  fn b2World_Step(worldId: B2WorldId, timeStep: Float32, subStepCount: Int32);

  // --- Gravity ---

  fn b2World_GetGravity(worldId: B2WorldId) -> B2Vec2;
  fn b2World_SetGravity(worldId: B2WorldId, gravity: B2Vec2);

  // --- Explosion ---

  fn b2DefaultExplosionDef() -> B2ExplosionDef;
  fn b2World_Explode(worldId: B2WorldId, def: *B2ExplosionDef);

  // --- Body Lifecycle ---

  fn b2DefaultBodyDef() -> B2BodyDef;
  fn b2CreateBody(worldId: B2WorldId, def: *B2BodyDef) -> B2BodyId;
  fn b2DestroyBody(bodyId: B2BodyId);
  fn b2Body_IsValid(bodyId: B2BodyId) -> Int32;

  // --- Body Properties ---

  fn b2Body_GetType(bodyId: B2BodyId) -> Int32;
  fn b2Body_SetType(bodyId: B2BodyId, bodyType: Int32);
  fn b2Body_GetPosition(bodyId: B2BodyId) -> B2Pos;
  fn b2Body_GetRotation(bodyId: B2BodyId) -> B2Rot;
  fn b2Body_GetTransform(bodyId: B2BodyId) -> B2WorldTransform;
  fn b2Body_SetTransform(bodyId: B2BodyId, position: B2Pos, rotation: B2Rot);
  fn b2Body_GetLinearVelocity(bodyId: B2BodyId) -> B2Vec2;
  fn b2Body_GetAngularVelocity(bodyId: B2BodyId) -> Float32;
  fn b2Body_SetLinearVelocity(bodyId: B2BodyId, linearVelocity: B2Vec2);
  fn b2Body_SetAngularVelocity(bodyId: B2BodyId, angularVelocity: Float32);

  // --- Body Forces & Impulses ---

  fn b2Body_ApplyForce(bodyId: B2BodyId, force: B2Vec2, point: B2Pos, wake: Int32);
  fn b2Body_ApplyForceToCenter(bodyId: B2BodyId, force: B2Vec2, wake: Int32);
  fn b2Body_ApplyTorque(bodyId: B2BodyId, torque: Float32, wake: Int32);
  fn b2Body_ApplyLinearImpulse(bodyId: B2BodyId, impulse: B2Vec2, point: B2Pos, wake: Int32);
  fn b2Body_ApplyLinearImpulseToCenter(bodyId: B2BodyId, impulse: B2Vec2, wake: Int32);
  fn b2Body_ApplyAngularImpulse(bodyId: B2BodyId, impulse: Float32, wake: Int32);

  // --- Body Mass ---

  fn b2Body_GetMass(bodyId: B2BodyId) -> Float32;
  fn b2Body_GetRotationalInertia(bodyId: B2BodyId) -> Float32;
  fn b2Body_SetMassData(bodyId: B2BodyId, massData: B2MassData);
  fn b2Body_GetMassData(bodyId: B2BodyId) -> B2MassData;
  fn b2Body_ApplyMassFromShapes(bodyId: B2BodyId);

  // --- Body Sleep ---

  fn b2Body_IsAwake(bodyId: B2BodyId) -> Int32;
  fn b2Body_SetAwake(bodyId: B2BodyId, awake: Int32);
  fn b2Body_EnableSleep(bodyId: B2BodyId, enableSleep: Int32);
  fn b2Body_IsEnabled(bodyId: B2BodyId) -> Int32;
  fn b2Body_Disable(bodyId: B2BodyId);
  fn b2Body_Enable(bodyId: B2BodyId);

  // --- Body Shape/Joint Enumeration ---

  fn b2Body_GetShapeCount(bodyId: B2BodyId) -> Int32;
  fn b2Body_GetShapes(bodyId: B2BodyId, shapeArray: *B2ShapeId, capacity: Int32) -> Int32;
  fn b2Body_GetJointCount(bodyId: B2BodyId) -> Int32;
  fn b2Body_GetJoints(bodyId: B2BodyId, jointArray: *B2JointId, capacity: Int32) -> Int32;
  fn b2Body_GetContactCapacity(bodyId: B2BodyId) -> Int32;
  fn b2Body_GetContactData(bodyId: B2BodyId, contactData: *B2ContactData, capacity: Int32) -> Int32;
  fn b2Body_ComputeAABB(bodyId: B2BodyId) -> B2AABB;

  // --- Shape Lifecycle ---

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

  // --- Shape Properties ---

  fn b2Shape_SetDensity(shapeId: B2ShapeId, density: Float32);
  fn b2Shape_GetDensity(shapeId: B2ShapeId) -> Float32;
  fn b2Shape_SetFriction(shapeId: B2ShapeId, friction: Float32);
  fn b2Shape_GetFriction(shapeId: B2ShapeId) -> Float32;
  fn b2Shape_SetRestitution(shapeId: B2ShapeId, restitution: Float32);
  fn b2Shape_GetRestitution(shapeId: B2ShapeId) -> Float32;
  fn b2Shape_SetSensor(shapeId: B2ShapeId, sensor: Int32);

  // --- Shape Contact/Sensor Data ---

  fn b2Shape_GetContactCapacity(shapeId: B2ShapeId) -> Int32;
  fn b2Shape_GetContactData(shapeId: B2ShapeId, contactData: *B2ContactData, capacity: Int32) -> Int32;
  fn b2Shape_GetSensorCapacity(shapeId: B2ShapeId) -> Int32;
  fn b2Shape_GetSensorData(shapeId: B2ShapeId, visitorIds: *B2ShapeId, capacity: Int32) -> Int32;

  // --- Filters ---

  fn b2DefaultFilter() -> B2Filter;
  fn b2DefaultQueryFilter() -> B2QueryFilter;

  // --- Polygon Factories ---

  fn b2MakePolygon(hull: *B2Hull, radius: Float32) -> B2Polygon;
  fn b2MakeSquare(halfWidth: Float32) -> B2Polygon;
  fn b2MakeBox(halfWidth: Float32, halfHeight: Float32) -> B2Polygon;
  fn b2MakeRoundedBox(halfWidth: Float32, halfHeight: Float32, radius: Float32) -> B2Polygon;
  fn b2MakeOffsetBox(halfWidth: Float32, halfHeight: Float32, center: B2Vec2, rotation: B2Rot) -> B2Polygon;
  fn b2ComputeHull(points: *B2Vec2, count: Int32) -> B2Hull;

  // --- Chain Shapes ---

  fn b2DefaultChainDef() -> B2ChainDef;
  fn b2CreateChain(bodyId: B2BodyId, def: *B2ChainDef) -> B2ChainId;
  fn b2DestroyChain(chainId: B2ChainId);
  fn b2Chain_GetSegmentCount(chainId: B2ChainId) -> Int32;
  fn b2Chain_GetSegments(chainId: B2ChainId, segmentArray: *B2ShapeId, capacity: Int32) -> Int32;

  // --- Joint Creation (one per type) ---

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

  // --- Joint Common ---

  fn b2DestroyJoint(jointId: B2JointId, wakeAttached: Int32);
  fn b2Joint_IsValid(jointId: B2JointId) -> Int32;
  fn b2Joint_GetType(jointId: B2JointId) -> Int32;
  fn b2Joint_GetBodyA(jointId: B2JointId) -> B2BodyId;
  fn b2Joint_GetBodyB(jointId: B2JointId) -> B2BodyId;

  // --- Joint-Specific Accessors ---

  fn b2DistanceJoint_SetLength(jointId: B2JointId, length: Float32);
  fn b2DistanceJoint_GetLength(jointId: B2JointId) -> Float32;
  fn b2DistanceJoint_EnableSpring(jointId: B2JointId, enable: Int32);
  fn b2DistanceJoint_EnableLimit(jointId: B2JointId, enable: Int32);
  fn b2DistanceJoint_EnableMotor(jointId: B2JointId, enable: Int32);

  fn b2RevoluteJoint_EnableLimit(jointId: B2JointId, enable: Int32);
  fn b2RevoluteJoint_EnableMotor(jointId: B2JointId, enable: Int32);
  fn b2RevoluteJoint_SetMotorSpeed(jointId: B2JointId, motorSpeed: Float32);
  fn b2RevoluteJoint_GetAngle(jointId: B2JointId) -> Float32;

  // --- Event Retrieval (transient — copy immediately) ---

  fn b2World_GetBodyEvents(worldId: B2WorldId) -> B2BodyEvents;
  fn b2World_GetSensorEvents(worldId: B2WorldId) -> B2SensorEvents;
  fn b2World_GetContactEvents(worldId: B2WorldId) -> B2ContactEvents;
  fn b2World_GetJointEvents(worldId: B2WorldId) -> B2JointEvents;

  // --- Contact Data ---

  fn b2Contact_IsValid(contactId: B2ContactId) -> Int32;
  fn b2Contact_GetData(contactId: B2ContactId) -> B2ContactData;

  // --- Spatial Queries ---

  fn b2World_CastRayClosest(worldId: B2WorldId, origin: B2Pos, translation: B2Vec2, filter: B2QueryFilter) -> B2RayResult;

  // --- Debug Draw ---

  fn b2World_Draw(worldId: B2WorldId, draw: *B2DebugDraw);

  // --- Snapshot ---

  fn b2World_Snapshot(worldId: B2WorldId, image: *UInt8, capacity: Int32) -> Int32;

} // extern "C"
