module xiom.control.state_machine

pub enum StateMachineState {
  Idle,
  Running,
  Paused,
  Error(code: Int),
  Complete,
}

pub type Transition = {
  from: Int;
  to: Int;
  condition: Int;
}

pub type StateMachine = {
  current: Int;
  states: Vec[Str];
  transitions: Vec[Transition];
  state_data: Vec[Int];
}

pub fn sm_new() -> StateMachine {
  var states = Vec[Str].new();
  var transitions = Vec[Transition].new();
  var state_data = Vec[Int].new();
  return StateMachine{
    current: 0,
    states: states,
    transitions: transitions,
    state_data: state_data,
  };
}

pub fn sm_add_state(sm: &mut StateMachine, name: Str) -> Int {
  var id = sm.states.len();
  sm.states.push(name);
  sm.state_data.push(0);
  return id;
}

pub fn sm_add_transition(sm: &mut StateMachine, from: Int, to: Int, condition: Int) {
  var t = Transition{ from: from, to: to, condition: condition };
  sm.transitions.push(t);
}

pub fn sm_current(sm: &StateMachine) -> Int {
  return sm.current;
}

pub fn sm_can_transition(sm: &StateMachine, condition: Int) -> Bool {
  var i = 0;
  while i < sm.transitions.len() {
    var t = sm.transitions[i];
    if t.from == sm.current && t.condition == condition {
      return true;
    };
    i = i + 1;
  };
  return false;
}

pub fn sm_transition(sm: &mut StateMachine, condition: Int) -> Bool {
  if !sm_can_transition(sm, condition) {
    return false;
  };
  var i = 0;
  while i < sm.transitions.len() {
    var t = sm.transitions[i];
    if t.from == sm.current && t.condition == condition {
      sm.current = t.to;
      return true;
    };
    i = i + 1;
  };
  return false;
}
