# =============================================================================
# base_fsm.gd
# =============================================================================
# PURPOSE: The shared "spine" for every NPC type (Chef, Waiter, Customer).
#
# WHY A BASE CLASS?
#   All three NPC types need the same low-level capabilities:
#     - Moving through the level (direct threshold movement — no navmesh needed)
#     - Playing animations via AnimatedSprite2D
#     - Transitioning between named integer states safely
#     - Emitting signals so the RoundManager can react without tight coupling
# =============================================================================

class_name BaseFSM
extends CharacterBody2D

signal state_changed(old_state: int, new_state: int)
signal destination_reached()
signal turn_complete(npc: BaseFSM)

@export var move_speed: float = 100.0

# NavigationAgent2D kept for scene compatibility but NOT used for pathfinding.
# Direct movement is used instead so no baked navmesh is required.
@onready var nav_agent   : NavigationAgent2D = $NavigationAgent2D if has_node("NavigationAgent2D") else null
@onready var anim_sprite : AnimatedSprite2D  = $AnimatedSprite2D  if has_node("AnimatedSprite2D")  else null

# NavigationAgent2D kept for scene compatibility but NOT used for pathfinding.
# Direct movement is used instead so no baked navmesh is required.
@onready var nav_agent   : NavigationAgent2D = $NavigationAgent2D if has_node("NavigationAgent2D") else null
@onready var anim_sprite : AnimatedSprite2D  = $AnimatedSprite2D  if has_node("AnimatedSprite2D")  else null

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const ARRIVAL_THRESHOLD : float = 6.0

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var current_state  : int     = -1
var previous_state : int     = -1
var _is_moving     : bool    = false
var _move_target   : Vector2 = Vector2.ZERO

var _arrival_state     : int  = -1
var _finish_on_arrival : bool = false

var is_turn_active : bool   = false
var current_role   : String = ""

# ---------------------------------------------------------------------------
# Godot lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_on_ready()

func _physics_process(delta: float) -> void:
	#print("_is_moving: ", _is_moving, "\n")
	#print("Arrival state: ", _arrival_state, "\n")
	#print("_finish_on_arrival: ", _finish_on_arrival, "\n")
	#print("delta: ", delta, "\n")
	if _is_moving:
		_process_navigation()

	# Arrival check: _process_navigation() sets _is_moving=false when within
	# ARRIVAL_THRESHOLD, so this fires exactly one frame after we stop.
	if _arrival_state >= 0 and not _is_moving:
		var s      := _arrival_state
		var finish := _finish_on_arrival
		print("[BaseFSM] %s: arrived — entering state %d (finish_turn=%s)" % [name, s, str(finish)])
		_arrival_state     = -1
		_finish_on_arrival = false
		change_state(s)
		if finish:
			call_deferred("_finish_turn")
		return
	_process_state(delta)

# ---------------------------------------------------------------------------
# Overridable hooks (implement in subclasses)
# ---------------------------------------------------------------------------

func _on_ready() -> void:
	pass

func _process_state(_delta: float) -> void:
	pass

func _on_state_enter(_state: int) -> void:
	pass

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
	if not is_turn_active:
		push_warning("%s: _finish_turn() called when no turn was active — skipping" % name)
		return
	is_turn_active = false
	call_deferred("_deferred_turn_complete")

func _deferred_turn_complete() -> void:
	turn_complete.emit(self)

func _deferred_turn_complete() -> void:
	turn_complete.emit(self)

func change_state(new_state: int) -> void:
	if new_state == current_state:
		return
	previous_state = current_state
	current_state  = new_state
	state_changed.emit(previous_state, current_state)
	_on_state_enter(new_state)

func move_to(target_pos: Vector2) -> void:
	_move_target = target_pos
	_is_moving   = true

func move_to_state(target_pos: Vector2, on_arrival: int) -> void:
	_arrival_state = on_arrival
	move_to(target_pos)

func move_to_idle(target_pos: Vector2, idle_state: int) -> void:
	_finish_on_arrival = true
	move_to_state(target_pos, idle_state)

func has_reached_target() -> bool:
	return global_position.distance_to(_move_target) <= ARRIVAL_THRESHOLD

#TODO: look at _process_navigation() below and tweak it. This could be the reason the pathfinding is off (wrong)
func _process_navigation() -> void:
	var diff : Vector2 = _move_target - global_position
	var dist : float   = diff.length()

	if dist <= ARRIVAL_THRESHOLD:
		_is_moving = false
		velocity   = Vector2.ZERO
		move_and_slide()
		destination_reached.emit()
		return

	velocity = diff.normalized() * move_speed
	move_and_slide()

	velocity = diff.normalized() * move_speed
	move_and_slide()

func play_anim(anim_name: String) -> void:
	if anim_sprite == null:
		return
	if anim_sprite.sprite_frames == null:
		return
	if anim_sprite.sprite_frames.has_animation(anim_name):
		anim_sprite.play(anim_name)
