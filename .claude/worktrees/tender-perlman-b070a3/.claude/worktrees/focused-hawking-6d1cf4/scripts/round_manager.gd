# =============================================================================
# round_manager.gd
# AutoLoad name: RoundManager
# =============================================================================
# PURPOSE: Turn-based orchestrator — the OS kernel of the whole game.
#
# TURN FLOW (one "round" = one player click of Start Round):
#   1. OS menu shown → player assigns chefs (Cook/Prep) and waiters (Plate1/2/3)
#   2. Player clicks "Start Round" → OS menu calls RoundManager.execute_round()
#   3. RoundManager:
#        a. advance_pipeline()   — last round's cooking → cooked
#        b. assign roles to chefs + waiters
#        c. execute_turn() on every NPC simultaneously
#        d. wait for ALL turn_complete signals
#        e. tick_patience() on every waiting customer
#        f. check for timed-out customers → HP penalty → game over?
#        g. every SPAWN_INTERVAL rounds → spawn new customers
#   4. Emit round_complete → OS menu returns for next allocation
#
# CUSTOMER SPAWNING:
#   Initial batch spawns on start_game().
#   A new batch spawns every SPAWN_INTERVAL rounds (default 3).
#   Each batch fills whichever plates have no waiting customer up to MAX_PLATES.
#
# HP RULES:
#   Each customer who times out  → -1 HP.
#   HP reaches 0                 → game_over signal (kitchen_scene shows overlay).
# =============================================================================

class_name RoundManagerNode
extends Node

# ---------------------------------------------------------------------------
# Signals (connect in kitchen_scene.gd)
# ---------------------------------------------------------------------------

signal round_complete(round_num: int)
signal hp_changed(new_hp: int)
signal game_over()
signal game_won()

# ---------------------------------------------------------------------------
# Inspector
# ---------------------------------------------------------------------------

## Drag customer.tscn here in the Inspector on the AutoLoad node.
@export var customer_scene : PackedScene

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const GROUP_CHEFS     : String = "chefs"
const GROUP_WAITERS   : String = "waiters"
const GROUP_CUSTOMERS : String = "customers"
const GROUP_PLATES    : String = "plates"
const GROUP_DEATH_SFX : String = "death_sound"

const SPAWN_INTERVAL  : int  = 3    ## new customers every N rounds
const MAX_PLATES      : int  = 3

# ---------------------------------------------------------------------------
# Runtime
# ---------------------------------------------------------------------------

var _turns_remaining : int  = 0
var _round_active    : bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	pass   # AutoLoad — no scene setup needed

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Called once by kitchen_scene._ready() to start the very first round.
func start_game() -> void:
	GameConfig.player_hp     = GameConfig.MAX_HP
	GameConfig.score         = 0
	GameConfig.current_round = 0
	GameConfig.patties_cooking   = 0
	GameConfig.cooked_patties    = 0
	GameConfig.assembled_burgers = 0

	await get_tree().physics_frame   # let nav server bake

	_spawn_customer_batch()
	# Connect existing customers who were pre-placed in the scene
	_register_existing_customers()

	print("RoundManager: game started — waiting for player allocation")


## Called by OS menu's Start Round button with the player's allocations.
func execute_round(
	chef_cook  : int,
	chef_prep  : int,
	waiter_p1  : int,
	waiter_p2  : int,
	waiter_p3  : int
) -> void:
	if _round_active:
		push_warning("RoundManager: execute_round() called while round already active")
		return

	_round_active            = true
	GameConfig.current_round += 1
	var round_num            := GameConfig.current_round

	print("RoundManager: === Round %d starting ===" % round_num)

	# Apply allocations
	GameConfig.set_turn_allocations(chef_cook, chef_prep, waiter_p1, waiter_p2, waiter_p3)

	# Promote last round's cooking patties to cooked
	GameConfig.advance_pipeline()

	# Execute all NPC turns, wait for all to finish
	await _execute_npc_turns(chef_cook, chef_prep, waiter_p1, waiter_p2, waiter_p3)

	# Tick customer patience timers
	var timed_out := _tick_all_customers()

	# Apply HP penalties
	for _i in range(timed_out):
		GameConfig.deduct_hp(1)
		hp_changed.emit(GameConfig.player_hp)
		print("RoundManager: customer timed out — HP=%d" % GameConfig.player_hp)

	if GameConfig.is_game_over():
		_trigger_game_over()
		_round_active = false
		return

	# Spawn new customers every SPAWN_INTERVAL rounds
	if round_num % SPAWN_INTERVAL == 0:
		_spawn_customer_batch()

	_round_active = false
	round_complete.emit(round_num)
	print("RoundManager: === Round %d complete ===" % round_num)

# ---------------------------------------------------------------------------
# NPC turn execution
# ---------------------------------------------------------------------------

func _execute_npc_turns(
	cook_count : int,
	prep_count : int,
	w1_count   : int,
	w2_count   : int,
	w3_count   : int
) -> void:
	_turns_remaining = 0

	var chefs   : Array = get_tree().get_nodes_in_group(GROUP_CHEFS)
	var waiters : Array = get_tree().get_nodes_in_group(GROUP_WAITERS)

	# --- Assign chef roles ---
	var cooks_left := cook_count
	var preps_left := prep_count

	for node in chefs:
		if not (node is ChefFSM):
			continue
		var chef := node as ChefFSM
		var role := "idle"

		if cooks_left > 0:
			role = "cook"
			cooks_left -= 1
		elif preps_left > 0:
			role = "prep"
			preps_left -= 1

		_dispatch_turn(chef, role)

	# --- Assign waiter plates ---
	# Build a flat list: [plate1 × w1_count, plate2 × w2_count, plate3 × w3_count]
	var plate_roles : Array[String] = []
	for _i in range(w1_count): plate_roles.append("plate1")
	for _i in range(w2_count): plate_roles.append("plate2")
	for _i in range(w3_count): plate_roles.append("plate3")

	var role_idx := 0
	for node in waiters:
		if not (node is WaiterFSM):
			continue
		var waiter := node as WaiterFSM
		var role   := "idle"

		if role_idx < plate_roles.size():
			role = plate_roles[role_idx]
			role_idx += 1

		_dispatch_turn(waiter, role)

	# Wait until all dispatched turns finish
	while _turns_remaining > 0:
		await get_tree().process_frame


func _dispatch_turn(npc: BaseFSM, role: String) -> void:
	if npc.is_turn_active:
		return
	_turns_remaining += 1
	npc.turn_complete.connect(_on_turn_complete, CONNECT_ONE_SHOT)
	npc.execute_turn(role)


func _on_turn_complete(_npc: BaseFSM) -> void:
	_turns_remaining = maxi(0, _turns_remaining - 1)

# ---------------------------------------------------------------------------
# Customer patience tick
# ---------------------------------------------------------------------------

func _tick_all_customers() -> int:
	var timed_out := 0
	for node in get_tree().get_nodes_in_group(GROUP_CUSTOMERS):
		if node is CustomerFSM:
			if (node as CustomerFSM).tick_patience():
				timed_out += 1
	return timed_out

# ---------------------------------------------------------------------------
# Customer spawning
# ---------------------------------------------------------------------------

func _spawn_customer_batch() -> void:
	if customer_scene == null:
		push_warning("RoundManager: customer_scene not set — cannot spawn customers")
		return

	var plates : Array = get_tree().get_nodes_in_group(GROUP_PLATES)
	if plates.is_empty():
		push_error("RoundManager: no plate nodes in '%s' group!" % GROUP_PLATES)
		return

	plates.sort_custom(func(a, b): return a.name < b.name)

	# Find a spawn-point node (tag a Node2D "customer_spawn" in your scene)
	var spawn_root : Node = get_tree().get_first_node_in_group("customer_spawn")
	if spawn_root == null:
		# Fallback: spawn at first plate position offset upward
		spawn_root = plates[0]

	var spawned := 0
	for plate in plates:
		if GameConfig.customers_at_plate(plate as Node2D) > 0:
			continue   # plate already occupied

		var customer : CustomerFSM = customer_scene.instantiate() as CustomerFSM
		if customer == null:
			push_error("RoundManager: customer_scene did not instantiate as CustomerFSM!")
			return

		# Add to current scene — find the kitchen root
		var kitchen_root := get_tree().current_scene
		if kitchen_root == null:
			push_error("RoundManager: no current_scene to add customer to!")
			customer.queue_free()
			return

		kitchen_root.add_child(customer)
		customer.global_position = spawn_root.global_position

		customer.assigned_plate = plate as Node2D
		customer.plate_index    = plates.find(plate) + 1
		customer.add_to_group(GROUP_CUSTOMERS)

		customer.customer_fed.connect(_on_customer_fed)
		customer.customer_timed_out.connect(_on_customer_timed_out)

		customer.walk_to_seat()
		spawned += 1

		if spawned >= MAX_PLATES:
			break

	print("RoundManager: spawned %d new customer(s)" % spawned)


func _register_existing_customers() -> void:
	# Connect signals for any customers pre-placed in the scene (not spawned by us)
	for node in get_tree().get_nodes_in_group(GROUP_CUSTOMERS):
		if not (node is CustomerFSM):
			continue
		var c := node as CustomerFSM
		if not c.customer_fed.is_connected(_on_customer_fed):
			c.customer_fed.connect(_on_customer_fed)
		if not c.customer_timed_out.is_connected(_on_customer_timed_out):
			c.customer_timed_out.connect(_on_customer_timed_out)

		# Assign the least-occupied plate if not already assigned
		if c.assigned_plate == null:
			c.assigned_plate = GameConfig.find_least_occupied_plate()
			c.walk_to_seat()

# ---------------------------------------------------------------------------
# Customer event handlers
# ---------------------------------------------------------------------------

func _on_customer_fed(customer: CustomerFSM) -> void:
	print("RoundManager: customer '%s' fed — score=%d" % [customer.name, GameConfig.score])


func _on_customer_timed_out(customer: CustomerFSM) -> void:
	print("RoundManager: customer '%s' timed out — HP=%d" \
		  % [customer.name, GameConfig.player_hp])

# ---------------------------------------------------------------------------
# Game over / win
# ---------------------------------------------------------------------------

func _trigger_game_over() -> void:
	# Play death sound if present
	for node in get_tree().get_nodes_in_group(GROUP_DEATH_SFX):
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
			node.play()
	print("RoundManager: GAME OVER — HP=%d score=%d" \
		  % [GameConfig.player_hp, GameConfig.score])
	game_over.emit()

# ---------------------------------------------------------------------------
# Accessors (for HUD / OS menu display)
# ---------------------------------------------------------------------------

func get_current_round() -> int:  return GameConfig.current_round
func get_player_hp()     -> int:  return GameConfig.player_hp
func get_score()         -> int:  return GameConfig.score
func is_round_active()   -> bool: return _round_active
