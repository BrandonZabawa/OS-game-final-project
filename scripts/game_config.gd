# =============================================================================
# game_config.gd
# AutoLoad name: GameConfig
# =============================================================================

class_name GameConfigNode
extends Node

var chef_cook_count      : int = 0
var chef_prep_count      : int = 0
var waiter_plate1_count  : int = 0
var waiter_plate2_count  : int = 0
var waiter_plate3_count  : int = 0

var patties_cooking   : int = 0
var cooked_patties    : int = 0
var assembled_burgers : int = 0

var player_hp     : int = MAX_HP
var current_round : int = 0
var score         : int = 0

const MAX_HP     : int = 3
const MAX_PLATES : int = 3

func set_turn_allocations(
	cooks : int,
	preps : int,
	w1    : int,
	w2    : int,
	w3    : int
) -> void:
	chef_cook_count     = cooks
	chef_prep_count     = preps
	waiter_plate1_count = w1
	waiter_plate2_count = w2
	waiter_plate3_count = w3
	print("GameConfig: allocations — cook=%d prep=%d plate1=%d plate2=%d plate3=%d" \
		  % [cooks, preps, w1, w2, w3])

func advance_pipeline() -> void:
	cooked_patties  += patties_cooking
	patties_cooking  = 0

func deduct_hp(amount: int = 1) -> void:
	player_hp = maxi(0, player_hp - amount)

func is_game_over() -> bool:
	return player_hp <= 0

func add_score(amount: int = 1) -> void:
	score += amount

func get_plate_node(index: int) -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var plates : Array = tree.get_nodes_in_group("plates")
	for plate in plates:
		if plate.name == "plate%d" % index:
			return plate as Node2D
	return null

func customers_at_plate(plate: Node2D) -> int:
	if plate == null:
		return 0
	var tree := get_tree()
	if tree == null:
		return 0
	var count := 0
	for node in tree.get_nodes_in_group("customers"):
		if node is CustomerFSM:
			var c := node as CustomerFSM
			if c.assigned_plate == plate \
			and c.current_state not in [CustomerFSM.State.FED, CustomerFSM.State.LEAVING]:
				count += 1
	return count

# TODO: Check find_least_occupied_plate() if its causing bug with waiterfsm and customerfsm when using os-mech script
func find_least_occupied_plate() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null # TODO: find out why execution did not stop at null when it called return null
	var plates : Array = tree.get_nodes_in_group("plates")
	if plates.is_empty():
		return null

	var best_plate : Node2D = null
	var best_count : int    = 99 #TODO: find out why this value is rediculously high and for what purpose

	for plate in plates:
		var c := customers_at_plate(plate as Node2D)
		if c < best_count:
			best_count = c
			best_plate = plate as Node2D

	return best_plate
