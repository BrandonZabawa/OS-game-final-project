# =============================================================================
# customer_fsm.gd
# =============================================================================

class_name CustomerFSM
extends BaseFSM

enum State {
	SPAWNING,
	WALK_TO_SEAT,
	WAITING,
	FED,
	LEAVING,
}

@export var plate_index : int = 1

var assigned_plate  : Node2D = null
var turns_remaining : int    = 1

signal customer_fed(customer: CustomerFSM)
signal customer_timed_out(customer: CustomerFSM)

var _state_gen : int = 0

func change_state(new_state: int) -> void:
	_state_gen += 1
	super.change_state(new_state)

func _on_ready() -> void:
	change_state(State.SPAWNING)

func _on_state_enter(state: int) -> void:
	var gen := _state_gen

	match state:

		State.SPAWNING:
			pass

		State.WALK_TO_SEAT:
			if assigned_plate:
				move_to_state(assigned_plate.global_position, State.WAITING)
			else:
				push_error("CustomerFSM (%s): assigned_plate is null!" % name)

		State.WAITING:
			pass

		State.FED:
			customer_fed.emit(self)
			await get_tree().create_timer(0.5).timeout
			if _state_gen != gen: return
			queue_free()

		State.LEAVING:
			await get_tree().create_timer(0.5).timeout
			if _state_gen != gen: return
			queue_free()

func receive_meal() -> void:
	if current_state in [State.WAITING, State.WALK_TO_SEAT]:
		change_state(State.FED)
	else:
		push_warning("CustomerFSM (%s): receive_meal() ignored (state=%d)" \
					 % [name, current_state])

func tick_patience() -> bool:
	if current_state not in [State.WAITING, State.WALK_TO_SEAT]:
		return false
	turns_remaining -= 1
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
