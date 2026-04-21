class_name RoundManagerNode
extends Node

signal round_complete(round_num: int)
signal hp_changed(new_hp: int)
signal game_over()
signal game_won()

@export var customer_scene : PackedScene

const GROUP_CHEFS     : String = "chefs"
const GROUP_WAITERS   : String = "waiters"
const GROUP_CUSTOMERS : String = "customers"
const GROUP_PLATES    : String = "plates"
const GROUP_DEATH_SFX : String = "death_sound"

const SPAWN_INTERVAL : int = 3
const MAX_PLATES     : int = 3

var _turns_remaining : int  = 0
var _round_active    : bool = false

func _ready() -> void:
	pass

func start_game() -> void:
	GameConfig.player_hp         = GameConfig.MAX_HP
	GameConfig.score             = 0
	GameConfig.current_round     = 0
	GameConfig.patties_cooking   = 0
	GameConfig.cooked_patties    = 0
	GameConfig.assembled_burgers = 0

	await get_tree().physics_frame

	_spawn_customer_batch()
	_register_existing_customers()
	_register_waiters()
	print("RoundManager: game started")

func execute_round(
	chef_cook  : int,
	chef_prep  : int,
	waiter_p1  : int,
	waiter_p2  : int,
	waiter_p3  : int
) -> void:
	if _round_active:
		push_warning("RoundManager: execute_round() called while already active")
		return

	_round_active            = true
	GameConfig.current_round += 1
	var round_num            := GameConfig.current_round

	print("RoundManager: === Round %d starting ===" % round_num)

	GameConfig.set_turn_allocations(chef_cook, chef_prep, waiter_p1, waiter_p2, waiter_p3)
	GameConfig.advance_pipeline()

	# Shuffle customers at round START so they walk while waiters are running.
	# By the time patience is ticked at round END they've had a full round to arrive.
	_shuffle_seated_customers()

	await _execute_npc_turns(chef_cook, chef_prep, waiter_p1, waiter_p2, waiter_p3)

	# Tick patience for every active customer — deduct HP for each timeout.
	var timed_out := _tick_all_customers()
	for _i in range(timed_out):
		GameConfig.deduct_hp(1)
		hp_changed.emit(GameConfig.player_hp)
		print("RoundManager: customer timed out — HP now %d" % GameConfig.player_hp)

	if GameConfig.is_game_over():
		_trigger_game_over()
		_round_active = false
		return

	if round_num % SPAWN_INTERVAL == 0:
		_spawn_customer_batch()

	_round_active = false
	round_complete.emit(round_num)
	print("RoundManager: === Round %d complete ===" % round_num)

	if round_num >= 12 and not GameConfig.is_game_won():
		_trigger_game_won()

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

func _tick_all_customers() -> int:
	var timed_out := 0
	for node in get_tree().get_nodes_in_group(GROUP_CUSTOMERS):
		if node is CustomerFSM:
			if (node as CustomerFSM).tick_patience():
				timed_out += 1
	return timed_out

func _shuffle_seated_customers() -> void:
	for node in get_tree().get_nodes_in_group(GROUP_CUSTOMERS):
		if node is CustomerFSM:
			(node as CustomerFSM).shuffle_plate()

func _spawn_customer_batch() -> void:
	if customer_scene == null:
		push_warning("RoundManager: customer_scene not set")
		return

	var plates : Array = get_tree().get_nodes_in_group(GROUP_PLATES)
	if plates.is_empty():
		push_error("RoundManager: no nodes in '%s' group!" % GROUP_PLATES)
		return

	plates.sort_custom(func(a, b): return a.name < b.name)

	var spawn_root : Node = get_tree().get_first_node_in_group("customer_spawn")
	if spawn_root == null:
		spawn_root = plates[0]

	var spawned := 0
	for plate in plates:
		if GameConfig.customers_at_plate(plate as Node2D) > 0:
			continue

		var customer : CustomerFSM = customer_scene.instantiate() as CustomerFSM
		if customer == null:
			push_error("RoundManager: customer_scene is not CustomerFSM!")
			return

		var kitchen_root := get_tree().current_scene
		if kitchen_root == null:
			customer.queue_free()
			return

		kitchen_root.add_child(customer)
		customer.global_position = spawn_root.global_position
		customer.assigned_plate  = plate as Node2D
		customer.plate_index     = plates.find(plate) + 1
		customer.add_to_group(GROUP_CUSTOMERS)

		customer.customer_fed.connect(_on_customer_fed)
		customer.customer_timed_out.connect(_on_customer_timed_out)

		customer.walk_to_seat()
		spawned += 1

		if spawned >= MAX_PLATES:
			break

	print("RoundManager: spawned %d customer(s)" % spawned)

func _register_existing_customers() -> void:
	for node in get_tree().get_nodes_in_group(GROUP_CUSTOMERS):
		if not (node is CustomerFSM):
			continue
		var c := node as CustomerFSM
		if not c.customer_fed.is_connected(_on_customer_fed):
			c.customer_fed.connect(_on_customer_fed)
		if not c.customer_timed_out.is_connected(_on_customer_timed_out):
			c.customer_timed_out.connect(_on_customer_timed_out)
		if c.assigned_plate == null:
			c.assigned_plate = GameConfig.find_least_occupied_plate()
			c.walk_to_seat()

func _register_waiters() -> void:
	for node in get_tree().get_nodes_in_group(GROUP_WAITERS):
		if not (node is WaiterFSM):
			continue
		var w := node as WaiterFSM
		if not w.burger_delivered.is_connected(_on_burger_delivered):
			w.burger_delivered.connect(_on_burger_delivered)

func _on_burger_delivered(_waiter: WaiterFSM, plate: Node2D) -> void:
	for node in get_tree().get_nodes_in_group(GROUP_CUSTOMERS):
		if node is CustomerFSM:
			var c := node as CustomerFSM
			if c.assigned_plate == plate:
				c.receive_meal()
				return

func _on_customer_fed(customer: CustomerFSM) -> void:
	GameConfig.add_score(1)
	hp_changed.emit(GameConfig.player_hp)
	print("RoundManager: '%s' fed — score=%d" % [customer.name, GameConfig.score])
	if GameConfig.is_game_won():
		_trigger_game_won()

func _on_customer_timed_out(customer: CustomerFSM) -> void:
	print("RoundManager: '%s' timed out — HP=%d" % [customer.name, GameConfig.player_hp])

func _trigger_game_over() -> void:
	for node in get_tree().get_nodes_in_group(GROUP_DEATH_SFX):
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D:
			node.play()
	print("RoundManager: GAME OVER — score=%d" % GameConfig.score)
	game_over.emit()

func _trigger_game_won() -> void:
	print("RoundManager: GAME WON — score=%d" % GameConfig.score)
	game_won.emit()

func get_current_round() -> int:  return GameConfig.current_round
func get_player_hp()     -> int:  return GameConfig.player_hp
func get_score()         -> int:  return GameConfig.score
func is_round_active()   -> bool: return _round_active
