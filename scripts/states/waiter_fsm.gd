# =============================================================================
# waiter_fsm.gd
# =============================================================================
# PURPOSE: Controls a Waiter NPC that collects finished burgers from the
#          Chef's drop-off table and delivers them to a Customer's plate node.
#
# OS SCHEDULING ANALOGY:
#   The Waiter models an OS I/O dispatcher — it sits idle until a resource
#   (burger) is available, then moves that resource from a staging buffer
#   (waiter table) to its final destination (customer plate), completing
#   the "job" for that customer process.
#
# STATE FLOW:
#   IDLE  ──► (assign_delivery() called by RoundManager)
#     └─► WALK_TO_WAITER_TABLE   (navigate to Chef's drop-off)
#           └─► PICKUP_BURGER    (brief pickup action)
#                 └─► WALK_TO_PLATE  (navigate to assigned plate node)
#                       └─► DELIVER_BURGER  (place on plate, notify customer)
#                             └─► RETURN_TO_IDLE
#                                   └─► IDLE  (loop — ready for next delivery)
# =============================================================================

class_name WaiterFSM
extends BaseFSM

# ---------------------------------------------------------------------------
# State enum
# ---------------------------------------------------------------------------

enum State {
	IDLE,
	WALK_TO_WAITER_TABLE,   # Head to the Chef's drop-off table
	PICKUP_BURGER,          # Pick up the assembled burger
	WALK_TO_PLATE,          # Navigate to the target customer's plate
	DELIVER_BURGER,         # Place burger on plate, notify CustomerFSM
	RETURN_TO_IDLE,         # Return to standby position
}

# ---------------------------------------------------------------------------
# Exported node references
# ---------------------------------------------------------------------------

## The waiter-side table Node2D where Chefs leave finished burgers.
## Must be the SAME node referenced by ChefFSM.waiter_table_node.
#@export var waiter_table_node: Node2D
var waiter_table_node

## World position the Waiter returns to between deliveries.
@export var idle_position: Vector2 = Vector2.ZERO

# ---------------------------------------------------------------------------
# Runtime delivery context
# (Set externally by RoundManager before calling assign_delivery())
# ---------------------------------------------------------------------------

## The plate node this delivery is headed to.
var target_plate:    Node2D     = null

## The CustomerFSM waiting at that plate — we call receive_meal() on it
## once the burger is placed.
var target_customer: CustomerFSM = null

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const ACTION_DELAY: float = 0.35

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted once the burger lands on the plate.
## RoundManager listens to update feed-count tracking.
signal burger_delivered(waiter: WaiterFSM, plate: Node2D)

# ---------------------------------------------------------------------------
# BaseFSM hooks
# ---------------------------------------------------------------------------

func _on_ready() -> void:
	waiter_table_node = get_tree().get_first_node_in_group("raw_patty")
	change_state(State.IDLE)

func _on_state_enter(state: int) -> void:
	match state:

		State.IDLE:
			play_anim("idle")
			# The Waiter stands by. RoundManager calls assign_delivery() to
			# wake this NPC when a burger is ready and a customer needs feeding.

		State.WALK_TO_WAITER_TABLE:
			play_anim("walk")
			if waiter_table_node:
				move_to(waiter_table_node.global_position)
			else:
				push_error("WaiterFSM: waiter_table_node not assigned!")

		State.PICKUP_BURGER:
			play_anim("pickup")
			await get_tree().create_timer(ACTION_DELAY).timeout
			change_state(State.WALK_TO_PLATE)

		State.WALK_TO_PLATE:
			play_anim("walk")
			if target_plate:
				#move_to(target_plate.global_position)
				move_to(waiter_table_node.global_position)
			else:
				# Safety fallback — no plate assigned, return to idle.
				push_warning("WaiterFSM: target_plate is null, returning to idle")
				change_state(State.RETURN_TO_IDLE)

		State.DELIVER_BURGER:
			play_anim("place")
			await get_tree().create_timer(ACTION_DELAY).timeout
			# Tell the CustomerFSM it has been fed — triggers FED state + ding sound.
			if target_customer:
				target_customer.receive_meal()
			burger_delivered.emit(self, target_plate)
			change_state(State.RETURN_TO_IDLE)

		State.RETURN_TO_IDLE:
			play_anim("walk")
			#move_to(idle_position)
			move_to(waiter_table_node.global_position)
			# Clear delivery context so stale references don't persist.
			target_plate    = null
			target_customer = null

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

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Called by RoundManager when a burger is ready and a customer needs feeding.
## plate  — the Node2D plate the burger should land on.
## customer — the CustomerFSM waiting there (we call receive_meal() on arrival).
func assign_delivery(plate: Node2D, customer: CustomerFSM) -> void:
	if current_state != State.IDLE:
		# Waiter is already busy — RoundManager should check is_available() first.
		push_warning("WaiterFSM: assign_delivery called while not IDLE (state=%d)" % current_state)
		return
	target_plate    = plate
	target_customer = customer
	change_state(State.WALK_TO_WAITER_TABLE)

## Returns true when the Waiter is free to take a new delivery.
func is_available() -> bool:
	return current_state == State.IDLE


func _on_navigation_agent_2d_velocity_computed(safe_velocity: Vector2) -> void:
	pass # Replace with function body.
