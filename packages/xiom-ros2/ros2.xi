// XIOM -- ROS 2 (Robot Operating System) Middleware Bindings
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Pure SPEC package -- all FFI calls return Err until the C bridge is linked.
// Phase 3: Robotics middleware. Opaque Int handles for rcl/rclc primitives.
//
// Dependencies: ROS 2 (system-installed via apt/choco)
// Compile (when bridge ready): xiom --link rcl ros2.xi

module xiom.ros2

// ===========================================================================
// Types -- opaque Int handles for FFI safety
// ===========================================================================

pub type Node        = Int;
pub type Publisher   = Int;
pub type Subscriber  = Int;
pub type Service     = Int;
pub type Message     = Int;

// ===========================================================================
// ROS 2 C FFI Declarations (rcl + rclc)
// ===========================================================================

extern "C" {
  fn rcl_init() -> Int;
  fn rcl_shutdown(context: Int);
  fn rcl_create_node(name: Int, namespace: Int, context: Int) -> Int;
  fn rcl_destroy_node(node: Int) -> Int;
  fn rcl_create_publisher(node: Int, topic: Int, qos_profile: Int) -> Int;
  fn rcl_destroy_publisher(publisher: Int, node: Int) -> Int;
  fn rcl_publish(publisher: Int, message: Int) -> Int;
  fn rcl_create_subscription(node: Int, topic: Int, qos_profile: Int, callback: Int) -> Int;
  fn rcl_destroy_subscription(subscription: Int, node: Int) -> Int;
  fn rcl_spin_once(node: Int, timeout_ms: Int) -> Int;
  fn rcl_create_service(node: Int, service_name: Int, callback: Int) -> Int;
  fn rcl_destroy_service(service: Int, node: Int) -> Int;
}

// ===========================================================================
// Safe Wrappers: Initialisation / Shutdown
// ===========================================================================

pub fn init() -> Result[Node, Str]
  ensures: result.is_ok() || result.is_err();
{
  return Err("stub: ROS 2 C bridge not linked");
}

pub fn shutdown(context: Int)
  requires: context > 0;
{
  // stub: no-op until C bridge is linked
}

// ===========================================================================
// Safe Wrappers: Node Lifecycle
// ===========================================================================

pub fn create_node(name: Str) -> Result[Node, Str]
  requires: name.len() > 0;
  ensures: result.is_ok() || result.is_err();
{
  return Err("stub: ROS 2 C bridge not linked");
}

pub fn destroy_node(node: Node) -> Result[Int, Str]
  requires: node > 0;
{
  return Err("stub: ROS 2 C bridge not linked");
}

// ===========================================================================
// Safe Wrappers: Publisher
// ===========================================================================

pub fn create_publisher(node: Node, topic: Str) -> Result[Publisher, Str]
  requires: node > 0;
  requires: topic.len() > 0;
{
  return Err("stub: ROS 2 C bridge not linked");
}

pub fn destroy_publisher(publisher: Publisher, node: Node) -> Result[Int, Str]
  requires: publisher > 0;
  requires: node > 0;
{
  return Err("stub: ROS 2 C bridge not linked");
}

pub fn publish(publisher: Publisher, message: Message) -> Result[Int, Str]
  requires: publisher > 0;
  requires: message > 0;
{
  return Err("stub: ROS 2 C bridge not linked");
}

// ===========================================================================
// Safe Wrappers: Subscriber
// ===========================================================================

pub fn create_subscription(node: Node, topic: Str) -> Result[Subscriber, Str]
  requires: node > 0;
  requires: topic.len() > 0;
{
  return Err("stub: ROS 2 C bridge not linked");
}

pub fn destroy_subscription(subscriber: Subscriber, node: Node) -> Result[Int, Str]
  requires: subscriber > 0;
  requires: node > 0;
{
  return Err("stub: ROS 2 C bridge not linked");
}

// ===========================================================================
// Safe Wrappers: Event Loop (spin)
// ===========================================================================

pub fn spin_once(node: Node, timeout_ms: Int) -> Result[Int, Str]
  requires: node > 0;
  requires: timeout_ms >= 0;
{
  return Err("stub: ROS 2 C bridge not linked");
}

// ===========================================================================
// Safe Wrappers: Service
// ===========================================================================

pub fn create_service(node: Node, service_name: Str) -> Result[Service, Str]
  requires: node > 0;
  requires: service_name.len() > 0;
{
  return Err("stub: ROS 2 C bridge not linked");
}

pub fn destroy_service(service: Service, node: Node) -> Result[Int, Str]
  requires: service > 0;
  requires: node > 0;
{
  return Err("stub: ROS 2 C bridge not linked");
}
