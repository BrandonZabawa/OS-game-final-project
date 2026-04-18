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

# ---------------------------------------------------------------------------
# State enum
# ---------------------------------------------------------------------------

enum State {
	IDLE,
	WALK_TO_WAITER_TABLE,
	PICKUP_BURGER,
	WALK_TO_PLATE,
	DELIVER_BURGER,
	RETURN_TO_IDLE,
}

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var waiter_table_node : Node2D
@export var idle_position     : Vector2 = Vector2.ZERO

# ---------------------------------------------------------------------------
# Runtime delivery context (set by RoundManager before execute_turn)
# ---------------------------------------------------------------------------

## 1-based plate number assigned by the player this round (1, 2, or 3).
var assigned_plate_index : int        = 0

## Resolved plate Node2D — set at turn start from assigned_plate_index.
var target_plate         : Node2D     = null

## Customer waiting at that plate — receives the meal on delivery.
var target_customer      : CustomerFSM = null

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const ACTION_DELAY : float = 0.35

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal burger_delivered(waiter: WaiterFSM, plate: Node2D)

# ---------------------------------------------------------------------------
# Runtime
# ---------------------------------------------------------------------------

var _state_gen : int = 0

func change_state(new_state: int) -> void:
	_state_gen += 1
	super.change_state(new_state)

# ---------------------------------------------------------------------------
# BaseFSM hooks
# ---------------------------------------------------------------------------

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
				move_to(table.global_position)
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
				move_to(target_plate.global_position)
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
			move_to(idle_position)


func _process_state(_delta: float) -> void:
	match current_state:

		State.WALK_TO_WAITER_TABLE:
			if has_reached_target():
				change_state(State.PICKUP_BURGER)

		State.WALK_TO_PLATE:
			if has_reached_target():
				change_state(State.DELIVER_BURGER)

		State.RETURN_TO_IDLE:
			if has_reached_target():
				change_state(State.IDLE)
				_finish_turn()

# ---------------------------------------------------------------------------
# Turn execution
# ---------------------------------------------------------------------------

func _run_turn(role: String) -> void:
	# role = "plate1", "plate2", or "plate3"
	var plate_num := _role_to_plate_index(role)

	if plate_num == 0:
		# No plate assigned — stay idle
		_finish_turn()
		return

	assigned_plate_index = plate_num
	target_plate         = GameConfig.get_plate_node(plate_num)

	if target_plate == null:
		push_warning("WaiterFSM (%s): no plate node for index %d" % [name, plate_num])
		_finish_turn()
		return

	if GameConfig.assembled_burgers <= 0:
		print("WaiterFSM (%s): no assembled burgers — skipping delivery turn" % name)
		_finish_turn()
		return

	# Find a waiting customer at the assigned plate
	target_customer = _find_waiting_customer_at(target_plate)
	if target_customer == null:
		print("WaiterFSM (%s): no waiting customer at plate %d — skipping" \
			  % [name, plate_num])
		_finish_turn()
		return

	# Commit to the delivery — cannot re-route mid-turn
	change_state(State.WALK_TO_WAITER_TABLE)

# ---------------------------------------------------------------------------
# Public API (for RoundManager / Inspector assignment)
# ---------------------------------------------------------------------------

func is_available() -> bool:
	return current_state == State.IDLE and not is_turn_active

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _role_to_plate_index(role: String) -> int:
	match role:
		"plate1": return 1
		"plate2": return 2
		"plate3": return 3
		_:        return 0


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
