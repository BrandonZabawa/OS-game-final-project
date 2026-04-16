# =============================================================================
# round_manager.gd
# =============================================================================
# PURPOSE: The "OS kernel" that orchestrates the entire Round-Robin game loop.
#
# AUTOLOAD SETUP (required):
#   Project > Project Settings > AutoLoad tab
#   Path: res://scripts/round_manager.gd   Node Name: RoundManager
#
# OS SCHEDULING ANALOGY:
#   RoundManager IS the scheduler. It defines the time quantum, enforces
#   Round-Robin fairness across customers (processes), deducts HP for
#   starvation, and declares game over when the system runs out of health.
#
# FAIRNESS RULE:
#   At round end, find the maximum feed count among all customers.
#   Any customer below that max is "underfed".
#   - 1-2 underfed -> -1 HP each
#   - 3+ underfed  -> instant game over
# =============================================================================

class_name RoundManagerNode
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal round_started(round_number: int)
signal round_ended(round_number: int)
signal hp_changed(new_hp: int)
signal game_over()
signal game_won()

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const MAX_ROUNDS:          int   = 3
const ROUND_DURATION:      float = 60.0
const MAX_HP:              int   = 3
const CUSTOMERS_PER_ROUND: int   = 3

# All group names are const — var would allow silent mutation that breaks queries.
const GROUP_CHEFS:      String = "chefs"
const GROUP_WAITERS:    String = "waiters"
const GROUP_CUSTOMERS:  String = "customers"
const GROUP_PLATES:     String = "plates"
const GROUP_DEATH_SFX:  String = "death_sound"
const GROUP_WAITER_TBL: String = "waiter_table"

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

var current_round : int = 0
var player_hp     : int = MAX_HP

var _active_customers : Array      = []
var _feed_counts      : Dictionary = {}
var _round_timer      : Timer

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# NOTE: Do NOT add_to_group(GROUP_CUSTOMERS) here.
	# RoundManager is the scheduler — adding itself to the customers group
	# would poison every get_nodes_in_group("customers") query and crash
	# when the code tries to call walk_to_seat() on the manager itself.

	_round_timer           = Timer.new()
	_round_timer.one_shot  = true
	_round_timer.wait_time = ROUND_DURATION
	_round_timer.timeout.connect(_on_round_timer_expired)
	add_child(_round_timer)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func start_next_round() -> void:
	current_round += 1
	if current_round > MAX_ROUNDS:
		push_warning("RoundManager: start_next_round() called after all rounds complete")
		return

	print("RoundManager: -- Round %d starting --" % current_round)
	_active_customers.clear()
	_feed_counts.clear()

	# Defer one physics frame before querying groups.
	# Reason: when called from kitchen_scene._ready(), the NavigationServer
	# has not yet processed its first tick — navmesh isn't baked, so any
	# move_to() call inside walk_to_seat() silently fails. One frame is
	# enough for the server to catch up.
	await get_tree().physics_frame

	_assign_customers_to_plates()

	# Give customers time to walk to their seats before the round starts.
	await get_tree().create_timer(2.0).timeout

	for customer in _active_customers:
		customer.start_waiting()
		if not customer.customer_fed.is_connected(_on_customer_fed):
			customer.customer_fed.connect(_on_customer_fed)

	round_started.emit(current_round)
	_round_timer.start()
	print("RoundManager: round timer started (%.0f s)" % ROUND_DURATION)


func dispatch_waiter_for_burger(_chef: ChefFSM) -> void:
	var waiters         := get_tree().get_nodes_in_group(GROUP_WAITERS)
	var free_waiter     : WaiterFSM   = null
	var hungry_customer : CustomerFSM = null

	for w in waiters:
		if w is WaiterFSM and w.is_available():
			free_waiter = w
			break

	if free_waiter == null:
		push_warning("RoundManager: no free waiter available for burger delivery")
		return

	for c in _active_customers:
		if c.current_state == CustomerFSM.State.WAITING:
			hungry_customer = c
			break

	if hungry_customer == null:
		push_warning("RoundManager: no hungry customer found")
		return

	free_waiter.assign_delivery(hungry_customer.assigned_plate, hungry_customer)
	print("RoundManager: dispatched waiter %s to customer at plate %d" \
		  % [free_waiter.name, hungry_customer.plate_index])


func on_burger_delivered(waiter: WaiterFSM, _plate: Node2D) -> void:
	print("RoundManager: burger delivered by waiter=%s" % waiter.name)


func get_time_remaining() -> float:
	return _round_timer.time_left


func is_round_active() -> bool:
	return not _round_timer.is_stopped()


func get_current_round() -> int:
	return current_round


func get_player_hp() -> int:
	return player_hp


func get_max_hp() -> int:
	return MAX_HP

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _assign_customers_to_plates() -> void:
	# Strict type filter: only CustomerFSM nodes count.
	# Any other node accidentally in the "customers" group (mistagged,
	# RoundManager itself if add_to_group was accidentally left in, etc.)
	# is silently skipped rather than crashing the cast downstream.
	var raw_customers := get_tree().get_nodes_in_group(GROUP_CUSTOMERS)
	var all_customers : Array[CustomerFSM] = []
	for node in raw_customers:
		if node is CustomerFSM:
			all_customers.append(node as CustomerFSM)

	var all_plates := get_tree().get_nodes_in_group(GROUP_PLATES)

	if all_plates.is_empty():
		push_error("RoundManager: no nodes in group '%s' — tag your plate nodes in the Inspector!" % GROUP_PLATES)
		return
	if all_customers.is_empty():
		push_error("RoundManager: no CustomerFSM nodes in group '%s' — add customers to the group in the Inspector!" % GROUP_CUSTOMERS)
		return

	all_plates.shuffle()

	var count := mini(CUSTOMERS_PER_ROUND, mini(all_customers.size(), all_plates.size()))

	for i in range(count):
		var customer : CustomerFSM = all_customers[i]
		customer.assigned_plate = all_plates[i]
		customer.plate_index    = i + 1
		customer.walk_to_seat()
		_active_customers.append(customer)
		_feed_counts[customer.get_instance_id()] = 0

	print("RoundManager: assigned %d customers to plates" % count)


func _on_customer_fed(customer: CustomerFSM) -> void:
	var id := customer.get_instance_id()
	if _feed_counts.has(id):
		_feed_counts[id] += 1
		print("RoundManager: customer %d feed count -> %d" % [id, _feed_counts[id]])


func _on_round_timer_expired() -> void:
	print("RoundManager: round %d timer expired — evaluating fairness" % current_round)
	round_ended.emit(current_round)
	_evaluate_round_fairness()


func _evaluate_round_fairness() -> void:
	var max_fed     : int = 0
	var unfed_count : int = 0

	for customer in _active_customers:
		var fed : int = _feed_counts.get(customer.get_instance_id(), 0)
		max_fed = maxi(max_fed, fed)

	for customer in _active_customers:
		var fed : int = _feed_counts.get(customer.get_instance_id(), 0)
		if fed < max_fed or fed == 0:
			unfed_count += 1
			print("RoundManager: customer %d underfed (fed=%d, max=%d)" \
				  % [customer.get_instance_id(), fed, max_fed])

	print("RoundManager: round %d — unfed count = %d" % [current_round, unfed_count])

	if unfed_count >= 3:
		print("RoundManager: 3+ underfed customers — GAME OVER")
		_trigger_game_over()
		return

	if unfed_count > 0:
		_deduct_hp(unfed_count)

	if player_hp <= 0:
		_trigger_game_over()
		return

	if current_round >= MAX_ROUNDS:
		print("RoundManager: all rounds cleared — GAME WON")
		game_won.emit()
		return

	print("RoundManager: next round in 3 s...")
	await get_tree().create_timer(3.0).timeout
	start_next_round()


func _deduct_hp(amount: int) -> void:
	player_hp = maxi(0, player_hp - amount)
	print("RoundManager: HP -%d -> HP = %d" % [amount, player_hp])
	hp_changed.emit(player_hp)


func _trigger_game_over() -> void:
	for node in get_tree().get_nodes_in_group(GROUP_DEATH_SFX):
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
			node.play()
	print("RoundManager: GAME OVER — HP = %d" % player_hp)
	game_over.emit()
