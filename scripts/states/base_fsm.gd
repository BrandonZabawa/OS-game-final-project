# =============================================================================
# base_fsm.gd
# =============================================================================
# PURPOSE: The shared "spine" for every NPC type (Chef, Waiter, Customer).
#
# WHY A BASE CLASS?
#   All three NPC types need the same low-level capabilities:
#     - Moving through the level via NavigationAgent2D (A* pathfinding)
#     - Playing animations via AnimatedSprite2D
#     - Transitioning between named integer states safely
#     - Emitting signals so the RoundManager can react without tight coupling
#
#   By putting these in BaseFSM, each subclass only has to define *what* its
#   states mean, not *how* navigation or animation works.  This mirrors the
#   OS-scheduling metaphor: the kernel (BaseFSM) provides syscalls; each
#   process (subclass) just calls them.
# =============================================================================

class_name BaseFSM
extends CharacterBody2D

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal state_changed(old_state: int, new_state: int)
signal destination_reached()
signal turn_complete(npc: BaseFSM)

# ---------------------------------------------------------------------------
# Exported configuration
# ---------------------------------------------------------------------------

@export var move_speed: float = 100.0

# ---------------------------------------------------------------------------
# Child-node references
# ---------------------------------------------------------------------------

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var current_state: int  = -1
var previous_state: int = -1
var _is_moving: bool    = false

var _arrival_state     : int  = -1
var _finish_on_arrival : bool = false

var is_turn_active: bool = false
var current_role: String = ""

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	if nav_agent == null:
		push_error("%s: NavigationAgent2D child missing — add one to this NPC's scene" % name)
		return
	nav_agent.navigation_finished.connect(_on_navigation_finished)
	_on_ready()

func _physics_process(delta: float) -> void:
	if _is_moving:
		_process_navigation()

	if _arrival_state >= 0 and not _is_moving and has_reached_target():
		var s              := _arrival_state
		var finish         := _finish_on_arrival
		_arrival_state     = -1
		_finish_on_arrival = false
		change_state(s)
		if finish:
			_finish_turn()
		return

	_process_state(delta)

# ---------------------------------------------------------------------------
# Overridable hooks
# ---------------------------------------------------------------------------

func _on_ready() -> void:
	pass

func _process_state(_delta: float) -> void:
	pass

func _on_state_enter(_state: int) -> void:
	pass

# ---------------------------------------------------------------------------
# Turn-based execution
# ---------------------------------------------------------------------------

func execute_turn(role: String) -> void:
	if is_turn_active:
		push_warning("%s: execute_turn() called while already active — skipping" % name)
		return
	is_turn_active = true
	current_role   = role
	_run_turn(role)

func _run_turn(_role: String) -> void:
	_finish_turn()

func _finish_turn() -> void:
	is_turn_active = false
	turn_complete.emit(self)

# ---------------------------------------------------------------------------
# State machine API
# ---------------------------------------------------------------------------

func change_state(new_state: int) -> void:
	if new_state == current_state:
		return
	previous_state = current_state
	current_state  = new_state
	state_changed.emit(previous_state, current_state)
	_on_state_enter(new_state)

# ---------------------------------------------------------------------------
# Navigation API
# ---------------------------------------------------------------------------

func move_to(target_pos: Vector2) -> void:
	if nav_agent == null:
		return
	nav_agent.target_position = target_pos
	_is_moving = true

func move_to_state(target_pos: Vector2, on_arrival: int) -> void:
	_arrival_state = on_arrival
	move_to(target_pos)

func move_to_idle(target_pos: Vector2, idle_state: int) -> void:
	_finish_on_arrival = true
	move_to_state(target_pos, idle_state)

func has_reached_target() -> bool:
	if nav_agent == null:
		return true
	return nav_agent.is_navigation_finished()

func _process_navigation() -> void:
	if nav_agent == null or nav_agent.is_navigation_finished():
		return
	var next_pos:  Vector2 = nav_agent.get_next_path_position()
	var direction: Vector2 = (next_pos - global_position).normalized()
	velocity = direction * move_speed
	move_and_slide()

func _on_navigation_finished() -> void:
	_is_moving  = false
	velocity    = Vector2.ZERO
	destination_reached.emit()

# ---------------------------------------------------------------------------
# Animation helper
# ---------------------------------------------------------------------------

func play_anim(anim_name: String) -> void:
	if anim_sprite == null:
		return
	if anim_sprite.sprite_frames == null:
		return
	if anim_sprite.sprite_frames.has_animation(anim_name):
		anim_sprite.play(anim_name)

## =============================================================================
## base_fsm.gd
## =============================================================================
## PURPOSE: The shared "spine" for every NPC type (Chef, Waiter, Customer).
##
## WHY A BASE CLASS?
##   All three NPC types need the same low-level capabilities:
##     - Moving through the level via NavigationAgent2D (A* pathfinding)
##     - Playing animations via AnimatedSprite2D
##     - Transitioning between named integer states safely
##     - Emitting signals so the RoundManager can react without tight coupling
##
##   By putting these in BaseFSM, each subclass only has to define *what* its
##   states mean, not *how* navigation or animation works.  This mirrors the
##   OS-scheduling metaphor: the kernel (BaseFSM) provides syscalls; each
##   process (subclass) just calls them.
## =============================================================================
#
#class_name BaseFSM
#extends CharacterBody2D
#
## ---------------------------------------------------------------------------
## Signals
## ---------------------------------------------------------------------------
#
### Fired every time the state machine transitions.
### Old/new values let external nodes (e.g. RoundManager) react to changes
### without polling every frame.
#signal state_changed(old_state: int, new_state: int)
#
### Fired the moment NavigationAgent2D reports its path is complete.
### Subclasses listen for this instead of polling has_reached_target() every
### frame, which keeps _process_state() lean.
#signal destination_reached()
#
### Fired by an NPC when its turn action is fully complete.
### RoundManager listens to this (CONNECT_ONE_SHOT) to count down _turns_remaining.
#signal turn_complete(npc: BaseFSM)
#
## ---------------------------------------------------------------------------
## Exported configuration
## ---------------------------------------------------------------------------
#
### Walking speed in pixels per second.  Each subclass can override this in
### the Inspector so Chefs can be slower (carrying food) than Waiters, etc.
#@export var move_speed: float = 100.0
#
## ---------------------------------------------------------------------------
## Child-node references
## ---------------------------------------------------------------------------
#
## NavigationAgent2D must be a direct child of this node in the scene tree.
## It handles pathfinding on the baked NavigationRegion2D NavMesh.
#@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
#
## AnimatedSprite2D must also be a direct child.
## It holds all animation frames (idle, walk, place, pickup, etc.).
#@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
#
## ---------------------------------------------------------------------------
## Internal state
## ---------------------------------------------------------------------------
#
#var current_state: int  = -1   # Active state index (enum value from subclass)
#var previous_state: int = -1   # Last state — useful for "return to previous" logic
#var _is_moving: bool    = false # True while the nav agent has an active path
#
## Arrival-state system — set by move_to_state() / move_to_idle().
## The base _physics_process auto-transitions when navigation finishes.
#var _arrival_state     : int  = -1   # State to enter on arrival; -1 means no pending transition
#var _finish_on_arrival : bool = false # Also call _finish_turn() after the state transition
#
### True while this NPC is executing a turn — prevents double-dispatch.
#var is_turn_active: bool = false
#
### The role string passed to the most recent execute_turn() call.
### Subclasses and os_menu.gd read this to display current activity.
#var current_role: String = ""
#
## ---------------------------------------------------------------------------
## Godot lifecycle
## ---------------------------------------------------------------------------
#
#func _ready() -> void:
	#if nav_agent == null:
		#push_error("%s: NavigationAgent2D child missing — add one to this NPC's scene" % name)
		#return
	#nav_agent.navigation_finished.connect(_on_navigation_finished)
	## Wire signals BEFORE _on_ready() so subclasses can safely call move_to().
	#_on_ready()
#
#func _physics_process(delta: float) -> void:
	#if _is_moving:
		#_process_navigation()
#
	## Auto-transition when navigation finishes and a destination state was set.
	## This replaces the has_reached_target() boilerplate in every subclass.
	#if _arrival_state >= 0 and not _is_moving and has_reached_target():
		#var s              := _arrival_state
		#var finish         := _finish_on_arrival
		#_arrival_state     = -1
		#_finish_on_arrival = false
		#change_state(s)
		#if finish:
			#_finish_turn()
		#return   # skip _process_state this frame — we just transitioned
#
	#_process_state(delta)
#
## ---------------------------------------------------------------------------
## Overridable hooks (called by base; implement in subclasses)
## ---------------------------------------------------------------------------
#
### Additional _ready setup — override instead of calling super._ready().
#func _on_ready() -> void:
	#pass
#
### Per-frame state logic.  Check has_reached_target() here to trigger
### transitions after movement completes.
#func _process_state(_delta: float) -> void:
	## TODO: add code to ensure states are processed correctly per NPC sprite.
	#pass
#
### Runs once when entering a new state.  Put one-shot setup here (timers,
### play_anim calls, nav targets) so _process_state stays side-effect-free.
#func _on_state_enter(_state: int) -> void:
	## TODO: add entering state code to transition between states for each sprite
	#pass
#
## ---------------------------------------------------------------------------
## Turn-based execution (called by RoundManager each round)
## ---------------------------------------------------------------------------
#
### Entry point called by RoundManager. Prevents double-dispatch via is_turn_active.
### Subclasses implement _run_turn() with the actual per-role logic.
#func execute_turn(role: String) -> void:
	#if is_turn_active:
		#push_warning("%s: execute_turn() called while already active — skipping" % name)
		#return
	#is_turn_active = true
	#current_role   = role
	#_run_turn(role)
#
#
### Override in subclasses. Must eventually call _finish_turn().
#func _run_turn(_role: String) -> void:
	#_finish_turn()
#
#
### Call at the end of every turn path (success or skip) to signal completion.
#func _finish_turn() -> void:
	#is_turn_active = false
	#turn_complete.emit(self)
#
## ---------------------------------------------------------------------------
## State machine API (call from subclasses)
## ---------------------------------------------------------------------------
#
### Transition to new_state.  No-ops if already in that state.
### Fires state_changed signal BEFORE calling _on_state_enter so listeners
### can read the new value immediately.
#func change_state(new_state: int) -> void:
	#if new_state == current_state:
		#return
	#previous_state = current_state
	#current_state  = new_state
	#state_changed.emit(previous_state, current_state)
	#_on_state_enter(new_state)   # Subclass reacts to the new state
#
## ---------------------------------------------------------------------------
## Navigation API
## ---------------------------------------------------------------------------
#
### Tell this NPC to walk to a world-space position.
#func move_to(target_pos: Vector2) -> void:
	#if nav_agent == null:
		#return
	#nav_agent.target_position = target_pos
	#_is_moving = true
#
### Walk to pos, then automatically change_state(on_arrival) when navigation finishes.
### Use this in _on_state_enter() for walk states instead of plain move_to().
#func move_to_state(target_pos: Vector2, on_arrival: int) -> void:
	#_arrival_state = on_arrival
	#move_to(target_pos)
#
### Walk to pos, change_state(idle_state), then emit turn_complete.
### Use this for the final return-to-idle leg at the end of every turn.
#func move_to_idle(target_pos: Vector2, idle_state: int) -> void:
	#_finish_on_arrival = true
	#move_to_state(target_pos, idle_state)
#
### Returns true once the nav agent has finished its current path.
### Use this inside _process_state() to trigger the next state after arrival.
#func has_reached_target() -> bool:
	#if nav_agent == null:
		#return true   # No nav agent = treat as already arrived so logic doesn't hang
	#return nav_agent.is_navigation_finished()
#
### Internal: called each physics frame while _is_moving == true.
#func _process_navigation() -> void:
	#if nav_agent == null or nav_agent.is_navigation_finished():
		#return
	#var next_pos:  Vector2 = nav_agent.get_next_path_position()
	#var direction: Vector2 = (next_pos - global_position).normalized()
	#velocity = direction * move_speed
	#move_and_slide()
#
### Called by NavigationAgent2D when path is fully complete.
### Stops movement and fires destination_reached for any listener.
#func _on_navigation_finished() -> void:
	#_is_moving  = false
	#velocity    = Vector2.ZERO
	#destination_reached.emit()
#
## ---------------------------------------------------------------------------
## Animation helper
## ---------------------------------------------------------------------------
#
### Plays an animation by name if (a) the sprite exists and (b) the animation
### exists in its SpriteFrames resource.  Silent no-op otherwise — subclasses
### can call this freely without null-checking.
#func play_anim(anim_name: String) -> void:
	#if anim_sprite == null:
		#return
	#if anim_sprite.sprite_frames == null:
		#return
	#if anim_sprite.sprite_frames.has_animation(anim_name):
		#anim_sprite.play(anim_name)
