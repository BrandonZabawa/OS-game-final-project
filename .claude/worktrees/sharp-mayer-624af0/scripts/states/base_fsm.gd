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

## Fired every time the state machine transitions.
## Old/new values let external nodes (e.g. RoundManager) react to changes
## without polling every frame.
signal state_changed(old_state: int, new_state: int)

## Fired the moment NavigationAgent2D reports its path is complete.
## Subclasses listen for this instead of polling has_reached_target() every
## frame, which keeps _process_state() lean.
signal destination_reached()

# ---------------------------------------------------------------------------
# Exported configuration
# ---------------------------------------------------------------------------

## Walking speed in pixels per second.  Each subclass can override this in
## the Inspector so Chefs can be slower (carrying food) than Waiters, etc.
@export var move_speed: float = 100.0

# ---------------------------------------------------------------------------
# Child-node references
# ---------------------------------------------------------------------------

# NavigationAgent2D must be a direct child of this node in the scene tree.
# It handles pathfinding on the baked NavigationRegion2D NavMesh.
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

# AnimatedSprite2D must also be a direct child.
# It holds all animation frames (idle, walk, place, pickup, etc.).
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var current_state: int  = -1   # Active state index (enum value from subclass)
var previous_state: int = -1   # Last state — useful for "return to previous" logic
var _is_moving: bool    = false # True while the nav agent has an active path

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Wire NavigationAgent2D callbacks.
	# velocity_computed fires after avoidance is resolved — we apply the safe
	# velocity here so NPCs don't clip through each other.
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	nav_agent.navigation_finished.connect(_on_navigation_finished)

	# Give each subclass a chance to do its own _ready work without
	# needing to call super._ready() (which Godot beginners often forget).
	_on_ready()

func _physics_process(delta: float) -> void:
	# Step the navigation each physics tick when actively moving.
	if _is_moving:
		_process_navigation()
	# Delegate per-frame logic to the subclass.
	_process_state(delta)

# ---------------------------------------------------------------------------
# Overridable hooks (called by base; implement in subclasses)
# ---------------------------------------------------------------------------

## Additional _ready setup — override instead of calling super._ready().
func _on_ready() -> void:
	pass

## Per-frame state logic.  Check has_reached_target() here to trigger
## transitions after movement completes.
func _process_state(_delta: float) -> void:
	pass

## Runs once when entering a new state.  Put one-shot setup here (timers,
## play_anim calls, nav targets) so _process_state stays side-effect-free.
func _on_state_enter(_state: int) -> void:
	pass

# ---------------------------------------------------------------------------
# State machine API (call from subclasses)
# ---------------------------------------------------------------------------

## Transition to new_state.  No-ops if already in that state.
## Fires state_changed signal BEFORE calling _on_state_enter so listeners
## can read the new value immediately.
func change_state(new_state: int) -> void:
	if new_state == current_state:
		return
	previous_state = current_state
	current_state  = new_state
	state_changed.emit(previous_state, current_state)
	_on_state_enter(new_state)   # Subclass reacts to the new state

# ---------------------------------------------------------------------------
# Navigation API
# ---------------------------------------------------------------------------

## Tell this NPC to walk to a world-space position.
## The NavigationAgent2D will compute an avoidance-aware path automatically.
func move_to(target_pos: Vector2) -> void:
	nav_agent.target_position = target_pos
	_is_moving = true

## Returns true once the nav agent has finished its current path.
## Use this inside _process_state() to trigger the next state after arrival.
func has_reached_target() -> bool:
	return nav_agent.is_navigation_finished()

## Internal: called each physics frame while _is_moving == true.
## Feeds the next waypoint direction to the nav agent so it can compute
## avoidance-safe velocity via velocity_computed signal.
func _process_navigation() -> void:
	if nav_agent.is_navigation_finished():
		return
	var next_pos:       Vector2 = nav_agent.get_next_path_position()
	var direction:      Vector2 = (next_pos - global_position).normalized()
	var desired_vel:    Vector2 = direction * move_speed
	# set_velocity triggers the avoidance calculation; result comes back via
	# _on_velocity_computed so we never apply velocity directly here.
	nav_agent.set_velocity(desired_vel)

## Called by NavigationAgent2D after avoidance is resolved.
## Applies the safe (non-clipping) velocity and slides the CharacterBody2D.
func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()

## Called by NavigationAgent2D when path is fully complete.
## Stops movement and fires destination_reached for any listener.
func _on_navigation_finished() -> void:
	_is_moving  = false
	velocity    = Vector2.ZERO
	destination_reached.emit()

# ---------------------------------------------------------------------------
# Animation helper
# ---------------------------------------------------------------------------

## Plays an animation by name if (a) the sprite exists and (b) the animation
## exists in its SpriteFrames resource.  Silent no-op otherwise — subclasses
## can call this freely without null-checking.
func play_anim(anim_name: String) -> void:
	if anim_sprite == null:
		return
	if anim_sprite.sprite_frames == null:
		return
	if anim_sprite.sprite_frames.has_animation(anim_name):
		anim_sprite.play(anim_name)
