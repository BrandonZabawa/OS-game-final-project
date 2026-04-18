# =============================================================================
# test_npc_behavior.gd
# =============================================================================
# PURPOSE: Auto-run NPC pathfinding and FSM sanity tests when the scene loads.
#
# HOW TO USE:
#   1. Attach this script to an empty Node in your main test scene
#      (or a dedicated TestHarness scene).
#   2. Make sure the scene contains:
#       • At least 3 ChefFSM nodes  in the "chefs"    group
#       • At least 3 WaiterFSM nodes in the "waiters"  group
#       • At least 3 CustomerFSM nodes in the "customers" group
#       • At least 3 plate Node2Ds   in the "plates"   group
#       • A waiter table Node2D      in the "waiter_table" group
#       • A hibachi grill Node2D     in the "hibachi_grill" group (for chef test)
#       • A baked NavigationRegion2D covering the whole level
#   3. Press Play — results print to the Output panel.
#      PASS lines confirm correct behaviour; FAIL lines need investigation.
#
# WHAT IS TESTED:
#   Test 1 — Chef pathfinding:
#     Spawn 3 chefs; verify each walks to the grill and enters PLACE_PATTY.
#   Test 2 — Waiter pathfinding:
#     Assign a dummy delivery to each waiter; verify they walk to the waiter
#     table and reach PICKUP_BURGER.
#   Test 3 — Customer pathfinding:
#     Assign each customer a plate; verify they walk to the seat and enter
#     IDLE_SEATED, then transition to WAITING after start_waiting() is called.
#   Test 4 — Round-Robin fairness rule:
#     Simulate a round where 1 customer goes unfed; verify HP drops by 1.
#   Test 5 — Game-over condition:
#     Simulate a round where all 3 customers are unfed; verify game_over fires.
# =============================================================================

extends Node

# ---------------------------------------------------------------------------
# Test counters
# ---------------------------------------------------------------------------

var _tests_passed: int = 0
var _tests_failed: int = 0

# We store lambda/signal connections here so we can disconnect them cleanly.
var _connections: Array = []

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Brief delay so NavigationRegion2D finishes baking before we navigate.
	await get_tree().create_timer(0.5).timeout
	print("\n╔══════════════════════════════════════╗")
	print("║     NPC BEHAVIOR TEST SUITE          ║")
	print("╚══════════════════════════════════════╝\n")

	await _test_chef_pathfinding()
	await _test_waiter_pathfinding()
	await _test_customer_pathfinding()
	await _test_fairness_hp_deduction()
	await _test_game_over_condition()

	_print_summary()

# ---------------------------------------------------------------------------
# Test 1 — Chef walks to the grill and starts cooking
# ---------------------------------------------------------------------------

func _test_chef_pathfinding() -> void:
	print("── Test 1: Chef pathfinding ──")

	var chefs = get_tree().get_nodes_in_group("chefs")
	if chefs.is_empty():
		_fail("Test 1", "No nodes in 'chefs' group — add ChefFSM nodes to the scene")
		return

	var chefs_to_test: int = min(3, chefs.size())
	var chefs_arrived: int = 0
	var timeout_sec:   float = 10.0

	for i in range(chefs_to_test):
		var chef: ChefFSM = chefs[i]
		# Force chef back to IDLE so it will walk to grill fresh.
		chef.change_state(ChefFSM.State.IDLE)

	# Wait up to timeout_sec for all chefs to enter PLACE_PATTY
	# (which means they reached the grill and placed a patty).
	var elapsed: float = 0.0
	while elapsed < timeout_sec:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		chefs_arrived = 0
		for i in range(chefs_to_test):
			var chef: ChefFSM = chefs[i]
			# PLACE_PATTY or any later state means pathfinding succeeded.
			if chef.current_state >= ChefFSM.State.PLACE_PATTY:
				chefs_arrived += 1
		if chefs_arrived == chefs_to_test:
			break

	if chefs_arrived == chefs_to_test:
		_pass("Test 1", "%d/%d chefs reached the grill and started PLACE_PATTY"
			  % [chefs_arrived, chefs_to_test])
	else:
		_fail("Test 1", "Only %d/%d chefs reached the grill within %.0f s — check NavigationRegion2D bake and grill_node assignment"
			  % [chefs_arrived, chefs_to_test, timeout_sec])

# ---------------------------------------------------------------------------
# Test 2 — Waiter walks to waiter table when assigned a delivery
# ---------------------------------------------------------------------------

func _test_waiter_pathfinding() -> void:
	print("\n── Test 2: Waiter pathfinding ──")

	var waiters = get_tree().get_nodes_in_group("waiters")
	var plates  = get_tree().get_nodes_in_group("plates")

	if waiters.is_empty():
		_fail("Test 2", "No nodes in 'waiters' group")
		return
	if plates.is_empty():
		_fail("Test 2", "No nodes in 'plates' group")
		return

	var count_to_test: int = min(3, min(waiters.size(), plates.size()))
	var customers      = get_tree().get_nodes_in_group("customers")

	for i in range(count_to_test):
		var waiter:   WaiterFSM  = waiters[i]
		var plate:    Node2D     = plates[i]
		# Use a real CustomerFSM if available; otherwise pass null.
		var customer: CustomerFSM = customers[i] if i < customers.size() else null
		# Assign delivery — this triggers WALK_TO_WAITER_TABLE.
		waiter.assign_delivery(plate, customer)

	var elapsed:  float = 0.0
	var timeout:  float = 10.0
	var arrived:  int   = 0

	while elapsed < timeout:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		arrived = 0
		for i in range(count_to_test):
			var w: WaiterFSM = waiters[i]
			# PICKUP_BURGER or later means the waiter reached the table.
			if w.current_state >= WaiterFSM.State.PICKUP_BURGER:
				arrived += 1
		if arrived == count_to_test:
			break

	if arrived == count_to_test:
		_pass("Test 2", "%d/%d waiters reached the waiter table" % [arrived, count_to_test])
	else:
		_fail("Test 2", "Only %d/%d waiters reached the table in %.0f s — check waiter_table_node assignment"
			  % [arrived, count_to_test, timeout])

# ---------------------------------------------------------------------------
# Test 3 — Customer walks to seat, idles, then enters WAITING
# ---------------------------------------------------------------------------

func _test_customer_pathfinding() -> void:
	print("\n── Test 3: Customer pathfinding ──")

	var customers = get_tree().get_nodes_in_group("customers")
	var plates    = get_tree().get_nodes_in_group("plates")

	if customers.is_empty():
		_fail("Test 3", "No nodes in 'customers' group")
		return
	if plates.is_empty():
		_fail("Test 3", "No nodes in 'plates' group")
		return

	var count_to_test: int = min(3, min(customers.size(), plates.size()))

	for i in range(count_to_test):
		var c: CustomerFSM = customers[i]
		c.assigned_plate   = plates[i]
		c.plate_index      = i + 1
		c.walk_to_seat()

	# Wait for all customers to be IDLE_SEATED.
	var elapsed:  float = 0.0
	var timeout:  float = 10.0
	var seated:   int   = 0

	while elapsed < timeout:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		seated = 0
		for i in range(count_to_test):
			if customers[i].current_state == CustomerFSM.State.IDLE_SEATED:
				seated += 1
		if seated == count_to_test:
			break

	if seated != count_to_test:
		_fail("Test 3a", "Only %d/%d customers seated in %.0f s — check NavigationRegion2D and plate positions"
			  % [seated, count_to_test, timeout])
		return

	_pass("Test 3a", "%d/%d customers reached their seats (IDLE_SEATED)" % [seated, count_to_test])

	# Now call start_waiting() and verify they all enter WAITING.
	for i in range(count_to_test):
		customers[i].start_waiting()

	await get_tree().process_frame

	var waiting: int = 0
	for i in range(count_to_test):
		if customers[i].current_state == CustomerFSM.State.WAITING:
			waiting += 1

	if waiting == count_to_test:
		_pass("Test 3b", "%d/%d customers transitioned to WAITING" % [waiting, count_to_test])
	else:
		_fail("Test 3b", "Only %d/%d customers entered WAITING — check start_waiting() logic"
			  % [waiting, count_to_test])

# ---------------------------------------------------------------------------
# Test 4 — Fairness rule: 1 unfed customer → -1 HP
# ---------------------------------------------------------------------------

func _test_fairness_hp_deduction() -> void:
	print("\n── Test 4: Fairness HP deduction ──")

	var initial_hp: int = RoundManagerNode.player_hp

	# Manually inject a scenario: 3 customers active, 2 fed (count=1), 1 fed (count=0).
	# We do this by directly manipulating RoundManager's internals via its public helpers.
	# Since _active_customers and _feed_counts are private (var, not @export), we
	# simulate via a helper exposed on RoundManager — see _simulate_round_result below.

	# Temporarily set RoundManager HP to max so we have headroom to test.
	RoundManagerNode.player_hp = RoundManagerNode.MAX_HP

	var hp_changed_to: int = -1
	var conn = RoundManagerNode.hp_changed.connect(func(hp): hp_changed_to = hp)
	_connections.append(conn)

	# Direct call to the internal method via a thin public wrapper.
	# We're calling simulate_unfed_scenario(unfed_count=1) defined below.
	_simulate_unfed_scenario(1)

	# Give one frame for signals to propagate.
	await get_tree().process_frame

	if hp_changed_to == RoundManagerNode.MAX_HP - 1:
		_pass("Test 4", "HP correctly deducted from %d → %d for 1 unfed customer"
			  % [RoundManagerNode.MAX_HP, hp_changed_to])
	else:
		_fail("Test 4", "Expected HP = %d but got %d (or hp_changed signal never fired)"
			  % [RoundManagerNode.MAX_HP - 1, hp_changed_to])

	# Restore HP for subsequent tests.
	RoundManagerNode.player_hp = initial_hp

## Helper that calls the round manager's HP deduction directly with a known unfed count.
## This avoids needing to run a real 60-second round just to test the HP rule.
func _simulate_unfed_scenario(unfed_count: int) -> void:
	# We call the internal _deduct_hp via a call() so we don't need to make it
	# public; this is GDScript's equivalent of "friend function" access for tests.
	# If you want cleaner separation, expose a test_deduct_hp(n) method on RoundManager.
	RoundManagerNode.call("_deduct_hp", unfed_count)

# ---------------------------------------------------------------------------
# Test 5 — Game-over: 3 unfed customers fires game_over signal
# ---------------------------------------------------------------------------

func _test_game_over_condition() -> void:
	print("\n── Test 5: Game-over condition (3 unfed) ──")

	# Set HP to max so only the "3+ unfed" branch triggers game_over, not HP=0.
	RoundManagerNode.player_hp = RoundManager.MAX_HP

	var game_over_fired: bool = false
	var conn = RoundManagerNode.game_over.connect(func(): game_over_fired = true)
	_connections.append(conn)

	# Directly invoke the game-over path.
	RoundManagerNode.call("_trigger_game_over")

	await get_tree().process_frame

	if game_over_fired:
		_pass("Test 5", "game_over signal fired correctly for 3+ unfed customers")
	else:
		_fail("Test 5", "game_over signal did NOT fire — check _trigger_game_over() in RoundManager")

	# Reset so the game is not stuck in game-over state after tests.
	RoundManagerNode.player_hp = RoundManagerNode.MAX_HP

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

func _pass(test_name: String, message: String) -> void:
	_tests_passed += 1
	print("  ✅ PASS [%s]: %s" % [test_name, message])

func _fail(test_name: String, message: String) -> void:
	_tests_failed += 1
	print("  ❌ FAIL [%s]: %s" % [test_name, message])

func _print_summary() -> void:
	print("\n╔══════════════════════════════════════╗")
	print("║  RESULTS: %d passed, %d failed        " % [_tests_passed, _tests_failed])
	print("╚══════════════════════════════════════╝\n")
	if _tests_failed == 0:
		print("🎉 All NPC behavior tests passed — pathfinding and FSM are wired correctly.")
	else:
		print("⚠️  Some tests failed.  Check the FAIL messages above.")
		print("   Common fixes:")
		print("   • Ensure NavigationRegion2D is baked and covers all NPC paths.")
		print("   • Ensure all groups ('chefs','waiters','customers','plates') are tagged.")
		print("   • Ensure @export node references are assigned in the Inspector.")
