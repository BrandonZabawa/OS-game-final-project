class_name WaiterFSM
extends BaseFSM

enum State {
	IDLE,
	WALK_TO_PLATE,
	DELIVER_BURGER,
	RETURN_TO_IDLE,
}

@export var idle_position : Vector2 = Vector2.ZERO

var target_plate : Node2D = null

const ACTION_DELAY : float = 0.35

signal burger_delivered(waiter: WaiterFSM, plate: Node2D)

var _state_gen : int = 0

func change_state(new_state: int) -> void:
	_state_gen += 1
	super.change_state(new_state)

func _on_ready() -> void:
	change_state(State.IDLE)

func _on_state_enter(state: int) -> void:
	var gen := _state_gen

	match state:

		State.IDLE:
			play_anim("idle")

		State.WALK_TO_PLATE:
			play_anim("walk")
			if target_plate:
				var offset := _npc_group_slot_offset("waiters", 18.0)
				move_to_state(target_plate.global_position + offset, State.DELIVER_BURGER)
			else:
				push_warning("WaiterFSM (%s): target_plate is null" % name)
				change_state(State.RETURN_TO_IDLE)

		State.DELIVER_BURGER:
			play_anim("place")
			await get_tree().create_timer(ACTION_DELAY).timeout
			if _state_gen != gen: return
			burger_delivered.emit(self, target_plate)
			change_state(State.RETURN_TO_IDLE)

		State.RETURN_TO_IDLE:
			play_anim("walk")
			target_plate = null
			move_to_idle(idle_position, State.IDLE)

func _run_turn(role: String) -> void:
	if role == "idle" or role.is_empty():
		_finish_turn()
		return

	target_plate = get_tree().get_first_node_in_group(role) as Node2D
	if target_plate == null:
		push_warning("WaiterFSM (%s): no node in group '%s'" % [name, role])
		_finish_turn()
		return

	print("WaiterFSM (%s): moving to '%s' at %s" % [name, role, str(target_plate.global_position)])
	change_state(State.WALK_TO_PLATE)

# Interrupts current movement and redirects to a new plate immediately.
# Called by os_menu when the player adjusts a spinbox mid-movement.
func redirect_to(role: String) -> void:
	if role.is_empty():
		return
	var plate := get_tree().get_first_node_in_group(role) as Node2D
	if plate == null or plate == target_plate:
		return
	_is_moving         = false
	_arrival_state     = -1
	_finish_on_arrival = false
	is_turn_active     = true
	current_role       = role
	target_plate       = plate
	# Reset current_state so the same-state guard in change_state is bypassed.
	# Without this, a waiter already in WALK_TO_PLATE would skip _on_state_enter
	# and never call move_to_state with the new target, leaving it frozen.
	current_state      = -1
	change_state(State.WALK_TO_PLATE)

func return_to_idle_position() -> void:
	_is_moving         = false
	_arrival_state     = -1
	_finish_on_arrival = false
	target_plate       = null
	# Same guard bypass as redirect_to — waiter may already be in RETURN_TO_IDLE.
	current_state      = -1
	change_state(State.RETURN_TO_IDLE)

func is_available() -> bool:
	return current_state == State.IDLE and not is_turn_active
