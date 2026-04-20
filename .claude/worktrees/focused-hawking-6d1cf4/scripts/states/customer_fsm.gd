# =============================================================================
# customer_fsm.gd
# =============================================================================
# PURPOSE: Customer NPC with a randomly assigned patience tier that counts
#          down each round.  Models "processes" in an OS scheduler — some jobs
#          have a long burst time (HIGH patience) and some are short (LOW).
#
# PATIENCE TIERS (randomly assigned on spawn):
#   LOW    — 5 turns  before leaving.  Forces the player to act fast.
#   MEDIUM — 10 turns before leaving.  Standard pressure.
#   HIGH   — 30 turns before leaving.  Allows deep pipeline build-up.
#
# STATE FLOW:
#   SPAWNING → WALK_TO_SEAT → IDLE_SEATED → WAITING
#           → FED (celebrate → LEAVING → queue_free)
#           → LEAVING (patience expired → queue_free)
# =============================================================================

class_name CustomerFSM
extends BaseFSM

enum PatienceTier { LOW, MEDIUM, HIGH }

const PATIENCE_TURNS : Dictionary = {
	PatienceTier.LOW    : 5,
	PatienceTier.MEDIUM : 10,
	PatienceTier.HIGH   : 30,
}

enum State {
	SPAWNING,
	WALK_TO_SEAT,
	IDLE_SEATED,
	WAITING,
	FED,
	LEAVING,
}

@export var plate_index : int = 1

var assigned_plate  : Node2D       = null
var patience_tier   : PatienceTier = PatienceTier.MEDIUM
var turns_remaining : int          = 10
var _has_been_fed   : bool         = false

@onready var patience_label : Label               = $PatienceLabel
@onready var _audio_ding    : AudioStreamPlayer2D = $AudioStreamPlayer2D

signal customer_fed(customer: CustomerFSM)
signal customer_timed_out(customer: CustomerFSM)

var _state_gen : int = 0

func change_state(new_state: int) -> void:
	_state_gen += 1
	super.change_state(new_state)

func _on_ready() -> void:
	_assign_random_patience()
	_has_been_fed = false
	_update_label()
	change_state(State.SPAWNING)

func _on_state_enter(state: int) -> void:
	var gen := _state_gen

	match state:

		State.SPAWNING:
			play_anim("idle")

		State.WALK_TO_SEAT:
			play_anim("walk")
			if assigned_plate:
				move_to_state(assigned_plate.global_position, State.IDLE_SEATED)
			else:
				push_error("CustomerFSM (%s): assigned_plate is null!" % name)

		State.IDLE_SEATED:
			play_anim("idle")

		State.WAITING:
			play_anim("waiting")
			_has_been_fed = false

		State.FED:
			_has_been_fed = true
			play_anim("happy")
			if _audio_ding and is_instance_valid(_audio_ding):
				_audio_ding.play()
			customer_fed.emit(self)
			await get_tree().create_timer(1.0).timeout
			if _state_gen != gen: return
			change_state(State.LEAVING)

		State.LEAVING:
			play_anim("walk")
			await get_tree().create_timer(1.5).timeout
			if _state_gen != gen: return
			queue_free()

func start_waiting() -> void:
	if current_state == State.IDLE_SEATED:
		change_state(State.WAITING)
	else:
		push_warning("CustomerFSM (%s): start_waiting() called before seated (state=%d)" \
					 % [name, current_state])

func receive_meal() -> void:
	if current_state == State.WAITING:
		change_state(State.FED)
	else:
		push_warning("CustomerFSM (%s): receive_meal() called outside WAITING (state=%d)" \
					 % [name, current_state])

func tick_patience() -> bool:
	if current_state != State.WAITING:
		return false

	turns_remaining -= 1
	_update_label()
	print("CustomerFSM (%s): %d turns remaining" % [name, turns_remaining])

	if turns_remaining <= 0:
		customer_timed_out.emit(self)
		change_state(State.LEAVING)
		return true

	return false

func walk_to_seat() -> void:
	change_state(State.WALK_TO_SEAT)

func is_seated() -> bool:
	return current_state in [State.IDLE_SEATED, State.WAITING, State.FED]

func is_fed() -> bool:
	return _has_been_fed

func _assign_random_patience() -> void:
	var roll := randi() % 3
	match roll:
		0:
			patience_tier   = PatienceTier.LOW
			turns_remaining = PATIENCE_TURNS[PatienceTier.LOW]
		1:
			patience_tier   = PatienceTier.MEDIUM
			turns_remaining = PATIENCE_TURNS[PatienceTier.MEDIUM]
		_:
			patience_tier   = PatienceTier.HIGH
			turns_remaining = PATIENCE_TURNS[PatienceTier.HIGH]
	print("CustomerFSM (%s): patience tier=%s turns=%d" \
		  % [name, PatienceTier.keys()[patience_tier], turns_remaining])

func _update_label() -> void:
	if patience_label == null:
		return
	patience_label.text = str(turns_remaining)

	if turns_remaining <= 3:
		patience_label.add_theme_color_override("font_color", Color.RED)
	elif turns_remaining <= 7:
		patience_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		patience_label.add_theme_color_override("font_color", Color.WHITE)
