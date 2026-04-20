# =============================================================================
# waiter_fsm.gd
# =============================================================================

class_name WaiterFSM
extends BaseFSM

enum State {
	IDLE,
	WALK_TO_PATTY,
	WALK_TO_PLATE,
	DELIVER_BURGER,
	RETURN_TO_IDLE,
}

var assigned_plate_index : int    = 0
var target_plate         : Node2D = null

const ACTION_DELAY : float = 0.5

signal burger_delivered(waiter: WaiterFSM, plate: Node2D)

var _state_gen : int = 0

func change_state(new_state: int) -> void:
	_state_gen += 1
	super.change_state(new_state)

func _on_ready() -> void:
	add_to_group("waiters")
	change_state(State.IDLE)

func _on_state_enter(state: int) -> void:
	var gen := _state_gen

	match state:

		State.IDLE:
			pass

		State.WALK_TO_PATTY:
			var patty := get_tree().get_first_node_in_group("cook_patty") as Node2D
			if patty:
				move_to_state(patty.global_position, State.WALK_TO_PLATE)
			else:
				push_warning("WaiterFSM (%s): no node in 'cook_patty' group — check editor" % name)
				_finish_turn()

		State.WALK_TO_PLATE:
			if target_plate:
				move_to_state(target_plate.global_position, State.DELIVER_BURGER)
			else:
				push_warning("WaiterFSM (%s): target_plate is null" % name)
				_finish_turn()

		State.DELIVER_BURGER:
			await get_tree().create_timer(ACTION_DELAY).timeout
			if _state_gen != gen: return
			var customer := _find_customer_at(target_plate)
			if customer:
				customer.receive_meal()
				GameConfig.add_score()
				print("WaiterFSM (%s): served customer at plate %d — score=%d" \
					  % [name, assigned_plate_index, GameConfig.score])
			else:
				print("WaiterFSM (%s): arrived at plate %d but no customer found" \
					  % [name, assigned_plate_index])
			burger_delivered.emit(self, target_plate)
			change_state(State.RETURN_TO_IDLE)

		State.RETURN_TO_IDLE:
			target_plate = null
			change_state(State.IDLE)
			_finish_turn()

func _run_turn(role: String) -> void:
	var plate_num := _role_to_plate_index(role)
	print("WaiterFSM (%s): turn started — role='%s' plate_num=%d" % [name, role, plate_num])

	if plate_num == 0:
		print("WaiterFSM (%s): no plate assigned — idle this turn" % name)
		_finish_turn()
		return

	assigned_plate_index = plate_num
	target_plate         = GameConfig.get_plate_node(plate_num)
	print("WaiterFSM (%s): target_plate = %s" % [name, str(target_plate)])

	if target_plate == null:
		push_warning("WaiterFSM (%s): plate node %d not found — ensure plate nodes have 'plates' group set in editor" \
					 % [name, plate_num])
		_finish_turn()
		return

	change_state(State.WALK_TO_PATTY)

func is_available() -> bool:
	return current_state == State.IDLE and not is_turn_active

func _role_to_plate_index(role: String) -> int:
	match role:
		"plate1": return 1
		"plate2": return 2
		"plate3": return 3
		_:        return 0

func _find_customer_at(plate: Node2D) -> CustomerFSM:
	if plate == null:
		return null
	for node in get_tree().get_nodes_in_group("customers"):
		if node is CustomerFSM:
			var c := node as CustomerFSM
			if c.assigned_plate == plate \
			and c.current_state in [CustomerFSM.State.WAITING, CustomerFSM.State.WALK_TO_SEAT]:
				return c
	return null
