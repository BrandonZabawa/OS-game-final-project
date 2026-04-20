# =============================================================================
# chef_fsm.gd
# =============================================================================
# PURPOSE: Chef NPC with two distinct turn roles assigned by the player.
#
# ROLES (set each round via OS menu → RoundManager → execute_turn()):
#
#   "cook"  — Pickup raw patty → walk to hibachi grill → place patty.
#             The patty cooks for exactly 1 round (it becomes available in
#             GameConfig.cooked_patties next turn via advance_pipeline()).
#             Once cooked, patties CANNOT burn — they wait indefinitely.
#
#   "prep"  — Walk to hibachi grill → pick up a cooked patty
#             (GameConfig.cooked_patties must be > 0) → walk to prep table
#             → assemble burger (add top + bottom bun) → walk to waiter table
#             → place assembled burger (increments GameConfig.assembled_burgers).
#             If no cooked patty is available, the chef idles this turn.
#
# OS ANALOGY:
#   The Cook chef is a CPU doing compute-bound work (placing a job in the
#   pipeline).  The Prep chef is doing I/O-bound work — it can only proceed
#   when upstream resources (cooked patties) are ready.  Together they model
#   a two-stage pipeline with a one-round latency between stages.
#
# STATE FLOW (cook role):
#   IDLE → WALK_TO_GRILL → COOK_PLACE → RETURN_TO_IDLE
#
# STATE FLOW (prep role, patty available):
#   IDLE → WALK_TO_GRILL → PREP_PICKUP → WALK_TO_PREP → PREP_ASSEMBLE
#        → WALK_TO_WAITER_TABLE → PREP_PLACE → RETURN_TO_IDLE
#
# STATE FLOW (prep role, NO patty):
#   IDLE → (emit turn_complete immediately, stays IDLE)
# =============================================================================

class_name ChefFSM
extends BaseFSM

enum State {
	IDLE,
	WALK_TO_GRILL,
	COOK_PLACE,
	PREP_PICKUP,
	WALK_TO_PREP,
	PREP_ASSEMBLE,
	WALK_TO_WAITER_TABLE,
	PREP_PLACE,
	RETURN_TO_IDLE,
}

@export var grill_node        : Node2D
@export var prep_area_node    : Node2D
@export var waiter_table_node : Node2D
@export var idle_position     : Vector2 = Vector2.ZERO

const ACTION_DELAY        : float = 0.30
const ASSEMBLY_STEP_DELAY : float = 0.35

var _state_gen : int = 0

func change_state(new_state: int) -> void:
	_state_gen += 1
	super.change_state(new_state)

func _on_ready() -> void:
	current_role = "idle"
	_resolve_node_refs()
	change_state(State.IDLE)

func _on_state_enter(state: int) -> void:
	var gen := _state_gen

	match state:

		State.IDLE:
			play_anim("idle")

		State.WALK_TO_GRILL:
			play_anim("walk")
			var target := _get_node_or_group(grill_node, "hibatchi_grill")
			if target:
				var next := State.COOK_PLACE if current_role == "cook" else State.PREP_PICKUP
				move_to_state(target.global_position, next)
			else:
				push_error("ChefFSM: grill_node not set and no node in 'hibatchi_grill' group!")
				_finish_turn()

		State.COOK_PLACE:
			play_anim("place")
			await get_tree().create_timer(ACTION_DELAY).timeout
			if _state_gen != gen: return
			GameConfig.patties_cooking += 1
			print("ChefFSM (%s): placed raw patty — patties_cooking=%d" \
				  % [name, GameConfig.patties_cooking])
			change_state(State.RETURN_TO_IDLE)

		State.PREP_PICKUP:
			play_anim("pickup")
			await get_tree().create_timer(ACTION_DELAY).timeout
			if _state_gen != gen: return
			GameConfig.cooked_patties -= 1
			print("ChefFSM (%s): picked up cooked patty — cooked_patties=%d" \
				  % [name, GameConfig.cooked_patties])
			change_state(State.WALK_TO_PREP)

		State.WALK_TO_PREP:
			play_anim("walk")
			var target := _get_node_or_group(prep_area_node, "prep_area")
			if target:
				move_to_state(target.global_position, State.PREP_ASSEMBLE)
			else:
				push_error("ChefFSM: prep_area_node not set and no node in 'prep_area' group!")
				_finish_turn()

		State.PREP_ASSEMBLE:
			play_anim("assemble")
			for step in ["bottom_bun", "patty", "top_bun"]:
				await get_tree().create_timer(ASSEMBLY_STEP_DELAY).timeout
				if _state_gen != gen: return
				print("ChefFSM (%s): assembly step — %s" % [name, step])
			change_state(State.WALK_TO_WAITER_TABLE)

		State.WALK_TO_WAITER_TABLE:
			play_anim("walk")
			var target := _get_node_or_group(waiter_table_node, "waiter_table")
			if target:
				move_to_state(target.global_position, State.PREP_PLACE)
			else:
				push_error("ChefFSM: waiter_table_node not set and no node in 'waiter_table' group!")
				_finish_turn()

		State.PREP_PLACE:
			play_anim("place")
			await get_tree().create_timer(ACTION_DELAY).timeout
			if _state_gen != gen: return
			GameConfig.assembled_burgers += 1
			print("ChefFSM (%s): placed assembled burger — assembled_burgers=%d" \
				  % [name, GameConfig.assembled_burgers])
			change_state(State.RETURN_TO_IDLE)

		State.RETURN_TO_IDLE:
			play_anim("walk")
			move_to_idle(idle_position, State.IDLE)

func _run_turn(role: String) -> void:
	current_role = role

	match role:

		"cook":
			change_state(State.WALK_TO_GRILL)

		"prep":
			if GameConfig.cooked_patties <= 0:
				print("ChefFSM (%s): no cooked patties — skipping prep turn" % name)
				change_state(State.IDLE)
				_finish_turn()
			else:
				change_state(State.WALK_TO_GRILL)

		_:
			change_state(State.IDLE)
			_finish_turn()

func _resolve_node_refs() -> void:
	if grill_node == null:
		grill_node = get_tree().get_first_node_in_group("hibatchi_grill") as Node2D
	if prep_area_node == null:
		prep_area_node = get_tree().get_first_node_in_group("prep_area") as Node2D
	if waiter_table_node == null:
		waiter_table_node = get_tree().get_first_node_in_group("waiter_table") as Node2D

func _get_node_or_group(exported_node: Node2D, group: String) -> Node2D:
	if exported_node != null:
		return exported_node
	return get_tree().get_first_node_in_group(group) as Node2D
## =============================================================================
## chef_fsm.gd
## =============================================================================
## PURPOSE: Chef NPC with two distinct turn roles assigned by the player.
##
## ROLES (set each round via OS menu → RoundManager → execute_turn()):
##
##   "cook"  — Pickup raw patty → walk to hibachi grill → place patty.
##             The patty cooks for exactly 1 round (it becomes available in
##             GameConfig.cooked_patties next turn via advance_pipeline()).
##             Once cooked, patties CANNOT burn — they wait indefinitely.
##
##   "prep"  — Walk to hibachi grill → pick up a cooked patty
##             (GameConfig.cooked_patties must be > 0) → walk to prep table
##             → assemble burger (add top + bottom bun) → walk to waiter table
##             → place assembled burger (increments GameConfig.assembled_burgers).
##             If no cooked patty is available, the chef idles this turn.
##
## OS ANALOGY:
##   The Cook chef is a CPU doing compute-bound work (placing a job in the
##   pipeline).  The Prep chef is doing I/O-bound work — it can only proceed
##   when upstream resources (cooked patties) are ready.  Together they model
##   a two-stage pipeline with a one-round latency between stages.
##
## STATE FLOW (cook role):
##   IDLE → WALK_TO_GRILL → COOK_PLACE → RETURN_TO_IDLE
##
## STATE FLOW (prep role, patty available):
##   IDLE → WALK_TO_GRILL → PREP_PICKUP → WALK_TO_PREP → PREP_ASSEMBLE
##        → WALK_TO_WAITER_TABLE → PREP_PLACE → RETURN_TO_IDLE
##
## STATE FLOW (prep role, NO patty):
##   IDLE → (emit turn_complete immediately, stays IDLE)
## =============================================================================
#
#class_name ChefFSM
#extends BaseFSM
#
## ---------------------------------------------------------------------------
## State enum
## ---------------------------------------------------------------------------
#
#enum State {
	#IDLE,
	#WALK_TO_GRILL,
	#COOK_PLACE,             # cook role: place raw patty on grill
	#PREP_PICKUP,            # prep role: pick up cooked patty from grill
	#WALK_TO_PREP,
	#PREP_ASSEMBLE,          # prep role: assemble burger with buns
	#WALK_TO_WAITER_TABLE,
	#PREP_PLACE,             # prep role: place assembled burger on counter
	#RETURN_TO_IDLE,
#}
#
## ---------------------------------------------------------------------------
## Inspector-configurable node references
## Drag your scene nodes into these slots. Group queries are used as fallbacks.
## ---------------------------------------------------------------------------
#
#@export var grill_node        : Node2D   ## Hibachi grill node
#@export var prep_area_node    : Node2D   ## Prep/assembly counter
#@export var waiter_table_node : Node2D   ## Staging counter for assembled burgers
#@export var idle_position     : Vector2 = Vector2.ZERO
#
## ---------------------------------------------------------------------------
## Constants
## ---------------------------------------------------------------------------
#
#const ACTION_DELAY        : float = 0.30
#const ASSEMBLY_STEP_DELAY : float = 0.35
#
## ---------------------------------------------------------------------------
## Runtime
## ---------------------------------------------------------------------------
#
##var current_role  : String = "idle"
#var _state_gen    : int    = 0
#
## ---------------------------------------------------------------------------
## Stale-coroutine guard
## ---------------------------------------------------------------------------
#
#func change_state(new_state: int) -> void:
	#_state_gen += 1
	#super.change_state(new_state)
#
## ---------------------------------------------------------------------------
## BaseFSM hooks
## ---------------------------------------------------------------------------
#
#func _on_ready() -> void:
	#current_role = "idle"
	#_resolve_node_refs()
	#change_state(State.IDLE)
#
#
#func _on_state_enter(state: int) -> void:
	#var gen := _state_gen
#
	#match state:
#
		#State.IDLE:
			#play_anim("idle")
#
		#State.WALK_TO_GRILL:
			#play_anim("walk")
			#var target := _get_node_or_group(grill_node, "hibatchi_grill")
			#if target:
				#var next := State.COOK_PLACE if current_role == "cook" else State.PREP_PICKUP
				#move_to_state(target.global_position, next)
			#else:
				#push_error("ChefFSM: grill_node not set and no node in 'hibatchi_grill' group!")
				#_finish_turn()
#
		#State.COOK_PLACE:
			#play_anim("place")
			#await get_tree().create_timer(ACTION_DELAY).timeout
			#if _state_gen != gen: return
			#GameConfig.patties_cooking += 1
			#print("ChefFSM (%s): placed raw patty — patties_cooking=%d" \
				  #% [name, GameConfig.patties_cooking])
			#change_state(State.RETURN_TO_IDLE)
#
		#State.PREP_PICKUP:
			#play_anim("pickup")
			#await get_tree().create_timer(ACTION_DELAY).timeout
			#if _state_gen != gen: return
			#GameConfig.cooked_patties -= 1
			#print("ChefFSM (%s): picked up cooked patty — cooked_patties=%d" \
				  #% [name, GameConfig.cooked_patties])
			#change_state(State.WALK_TO_PREP)
#
		#State.WALK_TO_PREP:
			#play_anim("walk")
			#var target := _get_node_or_group(prep_area_node, "prep_area")
			#if target:
				#move_to_state(target.global_position, State.PREP_ASSEMBLE)
			#else:
				#push_error("ChefFSM: prep_area_node not set and no node in 'prep_area' group!")
				#_finish_turn()
#
		#State.PREP_ASSEMBLE:
			#play_anim("assemble")
			## Three sub-steps: bottom bun → patty → top bun
			#for step in ["bottom_bun", "patty", "top_bun"]:
				#await get_tree().create_timer(ASSEMBLY_STEP_DELAY).timeout
				#if _state_gen != gen: return
				#print("ChefFSM (%s): assembly step — %s" % [name, step])
			#change_state(State.WALK_TO_WAITER_TABLE)
#
		#State.WALK_TO_WAITER_TABLE:
			#play_anim("walk")
			#var target := _get_node_or_group(waiter_table_node, "waiter_table")
			#if target:
				#move_to_state(target.global_position, State.PREP_PLACE)
			#else:
				#push_error("ChefFSM: waiter_table_node not set and no node in 'waiter_table' group!")
				#_finish_turn()
#
		#State.PREP_PLACE:
			#play_anim("place")
			#await get_tree().create_timer(ACTION_DELAY).timeout
			#if _state_gen != gen: return
			#GameConfig.assembled_burgers += 1
			#print("ChefFSM (%s): placed assembled burger — assembled_burgers=%d" \
				  #% [name, GameConfig.assembled_burgers])
			#change_state(State.RETURN_TO_IDLE)
#
		#State.RETURN_TO_IDLE:
			#play_anim("walk")
			#move_to_idle(idle_position, State.IDLE)   # base handles change_state + _finish_turn
#
## ---------------------------------------------------------------------------
## Turn execution (called by RoundManager)
## ---------------------------------------------------------------------------
#
#func _run_turn(role: String) -> void:
	#current_role = role
#
	#match role:
#
		#"cook":
			## Always possible — raw patties are infinite.
			#change_state(State.WALK_TO_GRILL)
			## _finish_turn() called after RETURN_TO_IDLE navigation completes.
#
		#"prep":
			#if GameConfig.cooked_patties <= 0:
				#print("ChefFSM (%s): no cooked patties — skipping prep turn" % name)
				#change_state(State.IDLE)
				#_finish_turn()
			#else:
				#change_state(State.WALK_TO_GRILL)
#
		#_:
			## No role assigned — sit idle this round.
			#change_state(State.IDLE)
			#_finish_turn()
#
## ---------------------------------------------------------------------------
## Helpers
## ---------------------------------------------------------------------------
#
#func _resolve_node_refs() -> void:
	#if grill_node == null:
		#grill_node = get_tree().get_first_node_in_group("hibatchi_grill") as Node2D
	#if prep_area_node == null:
		#prep_area_node = get_tree().get_first_node_in_group("prep_area") as Node2D
	#if waiter_table_node == null:
		#waiter_table_node = get_tree().get_first_node_in_group("waiter_table") as Node2D
#
#
#func _get_node_or_group(exported_node: Node2D, group: String) -> Node2D:
	#if exported_node != null:
		#return exported_node
	#return get_tree().get_first_node_in_group(group) as Node2D
