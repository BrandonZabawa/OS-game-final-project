# =============================================================================
# game_config.gd
# =============================================================================
# PURPOSE: Central store for settings driven by the OS-game-mechanic menu.
#
# Add to Project ▸ AutoLoad as "GameConfig".
#
# WHY THIS EXISTS:
#   Your TODO says "each sprite that populates is impacted by the number
#   allocated on the OS-game-mechanic menu" for Waiters, Chefs, and Customers.
#   GameConfig is the single source of truth for those counts so every system
#   (RoundManager, test runner, spawn logic) reads from one place.
#
# USAGE IN YOUR MENU SCENE:
#   GameConfig.set_npc_counts(chef_count, waiter_count, customer_count)
# =============================================================================

class_name GameConfigNode
extends Node

# ---------------------------------------------------------------------------
# Default NPC counts (clamped to MIN_COUNT–MAX_COUNT)
# ---------------------------------------------------------------------------

var chef_count     : int = 1
var waiter_count   : int = 1
var customer_count : int = 3

const MIN_COUNT : int = 1
const MAX_COUNT : int = 3

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

## Update all three counts at once — called from the OS menu UI on Start Round.
func set_npc_counts(chefs: int, waiters: int, customers: int) -> void:
	chef_count     = clamp(chefs,     MIN_COUNT, MAX_COUNT)
	waiter_count   = clamp(waiters,   MIN_COUNT, MAX_COUNT)
	customer_count = clamp(customers, MIN_COUNT, MAX_COUNT)
	print("GameConfig: counts updated — chefs=%d  waiters=%d  customers=%d" \
		  % [chef_count, waiter_count, customer_count])


func set_chef_count(value: int)     -> void: chef_count     = clamp(value, MIN_COUNT, MAX_COUNT)
func set_waiter_count(value: int)   -> void: waiter_count   = clamp(value, MIN_COUNT, MAX_COUNT)
func set_customer_count(value: int) -> void: customer_count = clamp(value, MIN_COUNT, MAX_COUNT)
