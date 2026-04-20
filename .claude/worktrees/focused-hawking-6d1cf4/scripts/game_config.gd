# =============================================================================
# game_config.gd
# AutoLoad name: GameConfig
# =============================================================================
# Central store for ALL game state that multiple systems need to read/write.
#
# OS ANALOGY:
#   GameConfig is the kernel's process-control-block table — one authoritative
#   record of every resource (patties, burgers, HP, score) so no two systems
#   can disagree about what exists.
#
# KITCHEN PIPELINE (one turn = one round click):
#   raw patty → [Cook Chef places on grill]
#             → patties_cooking  (set this turn)
#             → cooked_patties   (promoted next turn via advance_pipeline())
#             → [Prep Chef picks up, assembles]
#             → assembled_burgers (on waiter_table)
#             → [Waiter picks up, walks to plate]
#             → Customer fed ✓
# =============================================================================

class_name GameConfigNode
extends Node

# ---------------------------------------------------------------------------
# Per-turn NPC role allocations — set by OS menu before every round
# ---------------------------------------------------------------------------

var chef_cook_count      : int = 0
var chef_prep_count      : int = 0
var waiter_plate1_count  : int = 0
var waiter_plate2_count  : int = 0
var waiter_plate3_count  : int = 0

# ---------------------------------------------------------------------------
# Kitchen pipeline state — persists across turns
# ---------------------------------------------------------------------------

## Patties placed on the grill THIS turn — become cooked next turn.
var patties_cooking   : int = 0

## Cooked patties waiting on the grill for a Prep chef to pick up.
var cooked_patties    : int = 0

## Assembled burgers on the waiter_table, ready for any Waiter to pick up.
var assembled_burgers : int = 0

# ---------------------------------------------------------------------------
# Player / game state
# ---------------------------------------------------------------------------

var player_hp     : int = MAX_HP
var current_round : int = 0
var score         : int = 0   # total customers successfully served

const MAX_HP     : int = 3
const MAX_PLATES : int = 3

# ---------------------------------------------------------------------------
# Turn allocation API — called by OS menu on Start Round
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Pipeline API — called by RoundManager at the start of each NPC turn phase
# ---------------------------------------------------------------------------

## Promotes last round's cooking patties to cooked status.
## Called ONCE per round before NPCs execute.
func advance_pipeline() -> void:
	cooked_patties  += patties_cooking
	patties_cooking  = 0
	print("GameConfig: pipeline advanced — cooked=%d assembled=%d" \
		  % [cooked_patties, assembled_burgers])

# ---------------------------------------------------------------------------
# HP / score helpers
# ---------------------------------------------------------------------------

func deduct_hp(amount: int = 1) -> void:
	player_hp = maxi(0, player_hp - amount)

func is_game_over() -> bool:
	return player_hp <= 0

func add_score(amount: int = 1) -> void:
	score += amount

# ---------------------------------------------------------------------------
# Plate-node helpers
# ---------------------------------------------------------------------------

## Returns the plate Node2D for a 1-based index (1, 2, or 3).
## Each plate instance belongs to its own unique group ("plate1", "plate2", "plate3").
func get_plate_node(index: int) -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	if index < 1 or index > MAX_PLATES:
		return null
	var node := tree.get_first_node_in_group("plate%d" % index)
	return node as Node2D

## Returns how many CustomerFSM nodes are currently assigned to a given plate.
func customers_at_plate(plate: Node2D) -> int:
	if plate == null:
		return 0
	var tree := get_tree()
	if tree == null:
		return 0
	var count := 0
	for node in tree.get_nodes_in_group("customers"):
		if node is CustomerFSM and node.assigned_plate == plate:
			count += 1
	return count

## Finds the plate with the fewest customers currently assigned.
func find_least_occupied_plate() -> Node2D:
	var best_plate : Node2D = null
	var best_count : int    = 99

	for i in range(1, MAX_PLATES + 1):
		var plate := get_plate_node(i)
		if plate == null:
			continue
		var c := customers_at_plate(plate)
		if c < best_count:
			best_count = c
			best_plate = plate

	return best_plate
