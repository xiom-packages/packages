module xiom.control.trajectory

pub type Waypoint = {
  x: Float64;
  y: Float64;
  z: Float64;
  time: Float64;
}

pub type Trajectory = {
  waypoints: Vec[Waypoint];
  duration: Float64;
}

pub fn trajectory_new() -> Trajectory {
  var waypoints = Vec[Waypoint].new();
  return Trajectory{ waypoints: waypoints, duration: 0.0 };
}

pub fn trajectory_add_waypoint(traj: &mut Trajectory, wp: Waypoint) {
  traj.waypoints.push(wp);
  if wp.time > traj.duration {
    traj.duration = wp.time;
  };
}

pub fn trajectory_duration(traj: &Trajectory) -> Float64 {
  return traj.duration;
}

pub fn trajectory_interpolate(traj: &Trajectory, t: Float64) -> (Float64, Float64, Float64) {
  if traj.waypoints.len() == 0 {
    return (0.0, 0.0, 0.0);
  };
  if traj.waypoints.len() == 1 {
    var w = traj.waypoints[0];
    return (w.x, w.y, w.z);
  };

  if t <= traj.waypoints[0].time {
    var w = traj.waypoints[0];
    return (w.x, w.y, w.z);
  };
  if t >= traj.waypoints[traj.waypoints.len() - 1].time {
    var w = traj.waypoints[traj.waypoints.len() - 1];
    return (w.x, w.y, w.z);
  };

  var i: Int = 0;
  while i < traj.waypoints.len() - 1 {
    var w0 = traj.waypoints[i];
    var w1 = traj.waypoints[i + 1];
    if t >= w0.time && t <= w1.time {
      var segment_t = w1.time - w0.time;
      if segment_t <= 0.0 {
        return (w0.x, w0.y, w0.z);
      };
      var alpha: Float64 = (t - w0.time) / segment_t;
      var x = w0.x + alpha * (w1.x - w0.x);
      var y = w0.y + alpha * (w1.y - w0.y);
      var z = w0.z + alpha * (w1.z - w0.z);
      return (x, y, z);
    };
    i = i + 1;
  };

  var last = traj.waypoints[traj.waypoints.len() - 1];
  return (last.x, last.y, last.z);
}
