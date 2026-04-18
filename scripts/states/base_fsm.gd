# =============================================================================
# base_fsm.gd
# =============================================================================
# PURPOSE: Shared spine for every NPC (Chef, Waiter, Customer).
#
# Provides:
#   - NavigationAgent2D pathfinding (move_to / has_reached_target)
#   - AnimatedSprite2D animation helper (play_anim)
#   - State machine (change_state / _on_state_enter / _process_state)
#   - Turn-based execution hook (execute_turn / turn_complete signal)
#
# OS ANALOGY:
#   BaseFSM is the kernel providing syscalls. Subclasses are processes that
#   call those syscalls to do their work without caring about implementation.
# =============================================================================

class_name BaseFSM
extends CharacterBody2D

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Fired on every state transition.
signal state_changed(old_state: int, new_state: int)

## Fired when NavigationAgent2D completes its current path.
signal destination_reached()

## Fired by an NPC when its turn action is fully complete.
## RoundManager listens to this to know when all NPCs are done.
signal turn_complete(npc: BaseFSM)

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var move_speed: float = 100.0

# ---------------------------------------------------------------------------
# Child node references
# ---------------------------------------------------------------------------

@onready var nav_agent  : NavigationAgent2D = $NavigationAgent2D
@onready var anim_sprite: AnimatedSprite2D  = $AnimatedSprite2D

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var current_state  : int  = -1
var previous_state : int  = -1
var _is_moving     : bool = false

## True while this NPC is executing a turn — prevents double-dispatch.
var is_turn_active : bool = false

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	nav_agent.navigation_finished.connect(_on_navigation_finished)
	_on_ready()


func _physics_process(delta: float) -> void:
	if _is_moving:
		_process_navigation()
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
# Turn-based hook
# ---------------------------------------------------------------------------

## Called by RoundManager each round with the role this NPC should perform.
## Override in subclasses. Must eventually emit turn_complete(self).
func execute_turn(role: String) -> void:
	if is_turn_active:
		push_warning("%s: execute_turn() called while already active — skipping" % name)
		return
	is_turn_active = true
	_run_turn(role)


## Internal coroutine — override in subclasses with actual turn logic.
## Must call _finish_turn() when done.
func _run_turn(_role: String) -> void:
	_finish_turn()


## Call this at the end of every turn path to clean up and signal completion.
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
	nav_agent.target_position = target_pos
	_is_moving = true


func has_reached_target() -> bool:
	return nav_agent.is_navigation_finished()


func _process_navigation() -> void:
	if nav_agent.is_navigation_finished():
		return
	var next_pos    : Vector2 = nav_agent.get_next_path_position()
	var direction   : Vector2 = (next_pos - global_position).normalized()
	nav_agent.set_velocity(direction * move_speed)


func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()


func _on_navigation_finished() -> void:
	_is_moving = false
	velocity   = Vector2.ZERO
	destination_reached.emit()

# ---------------------------------------------------------------------------
# Animation helper
# ---------------------------------------------------------------------------

func play_anim(anim_name: String) -> void:
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return
	if anim_sprite.sprite_frames.has_animation(anim_name):
		anim_sprite.play(anim_name)
