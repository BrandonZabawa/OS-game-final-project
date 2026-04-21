# =============================================================================
# waiter_fsm.gd
# =============================================================================
# PURPOSE: Waiter NPC that picks up assembled burgers and delivers them to
#          a specific plate assigned by the player each round.
#
# COMMITMENT RULE (per design spec):
#   Once a Waiter starts walking to a plate it CANNOT change destination
#   mid-turn.  The player reassigns the waiter only on the NEXT round via
#   the OS menu.  This mirrors preemption policy in scheduling: a non-
#   preemptive dispatcher commits until the job is done.
#
# STATE FLOW:
#   IDLE
#    └─► WALK_TO_WAITER_TABLE  (go to burger staging counter)
#          └─► PICKUP_BURGER   (pick up assembled burger from counter)
#                └─► WALK_TO_PLATE  (committed — no re-routing)
#                      └─► DELIVER_BURGER  (serve customer, emit signals)
#                            └─► RETURN_TO_IDLE  ──► IDLE
#
# IF no assembled burger is available:
#   IDLE → (emit turn_complete immediately — stays IDLE)
#
# IF no customer is waiting at the assigned plate:
#   IDLE → (emit turn_complete — burger stays on counter for next round)
# =============================================================================

class_name WaiterFSM
extends BaseFSM

enum State {
	IDLE,
	WALK_TO_WAITER_TABLE,
	PICKUP_BURGER,
	WALK_TO_PLATE,
	DELIVER_BURGER,
	RETURN_TO_IDLE,
}

@export var waiter_table_node : Node2D
@export var idle_position     : Vector2 = Vector2.ZERO

var target_plate    : Node2D      = null
var target_customer : CustomerFSM = null

const ACTION_DELAY : float = 0.35

signal burger_delivered(waiter: WaiterFSM, plate: Node2D)

var _state_gen : int = 0

func change_state(new_state: int) -> void:
	_state_gen += 1
	super.change_state(new_state)

func _on_ready() -> void:
	if waiter_table_node == null:
		waiter_table_node = get_tree().get_first_node_in_group("waiter_table") as Node2D
	change_state(State.IDLE)

func _on_state_enter(state: int) -> void:
	var gen := _state_gen

	match state:

		State.IDLE:
			play_anim("idle")

		State.WALK_TO_WAITER_TABLE:
			play_anim("walk")
			var table := _get_waiter_table()
			if table:
				move_to_state(table.global_position, State.PICKUP_BURGER)
			else:
				push_error("WaiterFSM (%s): waiter_table_node not set!" % name)
				_finish_turn()

		State.PICKUP_BURGER:
			play_anim("pickup")
			await get_tree().create_timer(ACTION_DELAY).timeout
			if _state_gen != gen: return
			GameConfig.assembled_burgers -= 1
			print("WaiterFSM (%s): picked up burger — assembled_burgers=%d" \
				  % [name, GameConfig.assembled_burgers])
			change_state(State.WALK_TO_PLATE)

		State.WALK_TO_PLATE:
			play_anim("walk")
			if target_plate:
				move_to_state(target_plate.global_position, State.DELIVER_BURGER)
			else:
				push_warning("WaiterFSM (%s): target_plate is null — returning to idle" % name)
				change_state(State.RETURN_TO_IDLE)

		State.DELIVER_BURGER:
			play_anim("place")
			await get_tree().create_timer(ACTION_DELAY).timeout
			if _state_gen != gen: return
			if target_customer and is_instance_valid(target_customer):
				target_customer.receive_meal()
				GameConfig.add_score()
				print("WaiterFSM (%s): delivered burger to customer — score=%d" \
					  % [name, GameConfig.score])
			burger_delivered.emit(self, target_plate)
			change_state(State.RETURN_TO_IDLE)

		State.RETURN_TO_IDLE:
			play_anim("walk")
			target_plate    = null
			target_customer = null
			move_to_idle(idle_position, State.IDLE)

func _run_turn(role: String) -> void:
	if role == "idle" or role.is_empty():
		_finish_turn()
		return

	# Direct group lookup — each plate owns its own unique group name.
	target_plate = get_tree().get_first_node_in_group(role) as Node2D
	if target_plate == null:
		push_warning("WaiterFSM (%s): no node found in group '%s'" % [name, role])
		_finish_turn()
		return

	print("WaiterFSM (%s): assigned to '%s' at %s" % [name, role, str(target_plate.global_position)])
	change_state(State.WALK_TO_WAITER_TABLE)

func is_available() -> bool:
	return current_state == State.IDLE and not is_turn_active

func _get_waiter_table() -> Node2D:
	if waiter_table_node:
		return waiter_table_node
	return get_tree().get_first_node_in_group("waiter_table") as Node2D

func _find_waiting_customer_at(plate: Node2D) -> CustomerFSM:
	for node in get_tree().get_nodes_in_group("customers"):
		if node is CustomerFSM \
		and node.assigned_plate == plate \
		and node.current_state == CustomerFSM.State.WAITING:
			return node as CustomerFSM
	return null
