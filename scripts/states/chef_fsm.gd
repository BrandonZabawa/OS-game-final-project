# =============================================================================
# chef_fsm.gd
# =============================================================================
# PURPOSE: Controls a Chef NPC through the full burger pipeline.
#
# OS SCHEDULING ANALOGY:
#   The Chef models a CPU executing a multi-step job with a blocking I/O wait
#   (the 5-second cook timer).  While the patty cooks the Chef is "blocked",
#   just like a process waiting on a disk read.  Once cooking completes the
#   Chef is "unblocked" and resumes execution (picks up patty → assembles
#   burger → delivers to waiter table).
#
# STATE FLOW:
#   IDLE
#     └─► WALK_TO_GRILL        (navigate to hibachi grill node)
#           └─► PLACE_PATTY    (put raw patty on grill — brief action)
#                 └─► WAIT_COOK  (BLOCKED 5 s — cook timer fires _on_cook_finished)
#                       └─► PICKUP_PATTY  (take cooked patty off grill)
#                             └─► WALK_TO_PREP  (navigate to assembly counter)
#                                   └─► ASSEMBLE_BURGER  (3 sub-steps w/ delays)
#                                         └─► WALK_TO_WAITER_TABLE
#                                               └─► PLACE_BURGER  ──► burger_ready signal
#                                                     └─► RETURN_TO_IDLE  ──► IDLE (loop)
# =============================================================================

class_name ChefFSM
extends BaseFSM

# ---------------------------------------------------------------------------
# State enum
# ---------------------------------------------------------------------------

enum State {
	IDLE,
	WALK_TO_GRILL,
	PLACE_PATTY,
	WAIT_COOK,            # Blocked — patty cooking (5 s)
	PICKUP_PATTY,
	WALK_TO_PREP,
	ASSEMBLE_BURGER,      # 3-step sequence: bottom-bun → patty → top-bun
	WALK_TO_WAITER_TABLE,
	PLACE_BURGER,
	RETURN_TO_IDLE,
}

# ---------------------------------------------------------------------------
# Exported node references
# (Drag the actual scene nodes into these slots in the Godot Inspector)
# ---------------------------------------------------------------------------

## The hibachi grill Node2D — Chef walks here to cook patties.
#@export var grill_node:        Node2D
var grill_node #= get_tree().get_first_node_in_group("hibatchi_grill")
## Counter/prep area Node2D — Chef walks here to assemble the burger.
@export var prep_area_node:    Node2D

## Waiter-side table Node2D — Chef drops the finished burger here for the Waiter.
@export var waiter_table_node: Node2D

## World position the Chef returns to when not on a task (set in Inspector).
@export var idle_position:     Vector2 = Vector2.ZERO

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Patties take exactly 5 seconds to cook — matching the TODO requirement.
const COOK_TIME:     float = 5.0

## Short pause (seconds) for "placing" or "picking up" actions — gives the
## animation a beat to play before the state transitions forward.
const ACTION_DELAY:  float = 0.35

## Pause between each assembly sub-step so the player can see the sequence.
const ASSEMBLY_STEP_DELAY: float = 0.4

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

## Timer node created at runtime for the cook wait — no scene setup required.
var _cook_timer:     Timer

## Tracks how many assembly sub-steps have completed (0–3).
## 0 = none, 1 = bottom-bun placed, 2 = patty placed, 3 = top-bun (complete).
var _assembly_step:  int = 0

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the burger is placed on the waiter-side table and is ready
## for a Waiter to pick up.  RoundManager or WaiterFSM listens to this.
signal burger_ready(chef: ChefFSM)

# ---------------------------------------------------------------------------
# BaseFSM hooks
# ---------------------------------------------------------------------------

func _on_ready() -> void:
	# Build cook timer in code — avoids requiring a Timer node in the scene.
	#grill_node = get_node("/root/KitchenLevel")
	grill_node = get_tree().get_first_node_in_group("hibatchi_grill")
	_cook_timer             = Timer.new()
	_cook_timer.one_shot    = true
	_cook_timer.wait_time   = COOK_TIME
	_cook_timer.timeout.connect(_on_cook_finished)
	add_child(_cook_timer)

	# Begin the pipeline immediately when the Chef spawns.
	change_state(State.IDLE)

func _on_state_enter(state: int) -> void:
	match state:

		State.IDLE:
			play_anim("idle")
			# Small idle beat before re-entering the cooking pipeline.
			# Using a lambda so we don't flood the scene with extra Timer nodes.
			await get_tree().create_timer(0.5).timeout
			change_state(State.WALK_TO_GRILL)

		State.WALK_TO_GRILL:
			play_anim("walk")
			# Navigate to the hibachi grill.  _process_state monitors arrival.
			if grill_node:
				move_to(grill_node.global_position)
			else:
				push_error("ChefFSM: grill_node not assigned!")

		State.PLACE_PATTY:
			# Visual beat: play place animation, then short delay before cooking.
			play_anim("place")
			await get_tree().create_timer(ACTION_DELAY).timeout
			change_state(State.WAIT_COOK)

		State.WAIT_COOK:
			# Chef is "blocked" here — just stands by the grill.
			# The cook timer will fire _on_cook_finished() after COOK_TIME seconds.
			play_anim("idle")
			_cook_timer.start()

		State.PICKUP_PATTY:
			# Patty is done — pick it up with a brief animation beat.
			play_anim("pickup")
			await get_tree().create_timer(ACTION_DELAY).timeout
			change_state(State.WALK_TO_PREP)

		State.WALK_TO_PREP:
			play_anim("walk")
			if prep_area_node:
				move_to(prep_area_node.global_position)
			else:
				push_error("ChefFSM: prep_area_node not assigned!")

		State.ASSEMBLE_BURGER:
			_assembly_step = 0
			play_anim("assemble")
			# Run the three-step assembly as a coroutine so the state machine
			# doesn't block _physics_process while waiting between steps.
			_run_assembly_sequence()

		State.WALK_TO_WAITER_TABLE:
			play_anim("walk")
			if waiter_table_node:
				move_to(waiter_table_node.global_position)
			else:
				push_error("ChefFSM: waiter_table_node not assigned!")

		State.PLACE_BURGER:
			play_anim("place")
			await get_tree().create_timer(ACTION_DELAY).timeout
			# Signal the RoundManager / WaiterFSM that a burger is waiting.
			burger_ready.emit(self)
			change_state(State.RETURN_TO_IDLE)

		State.RETURN_TO_IDLE:
			play_anim("walk")
			move_to(idle_position)

func _process_state(_delta: float) -> void:
	# Only movement-completion checks live here — keeps each case a single line.
	match current_state:

		State.WALK_TO_GRILL:
			if has_reached_target():
				change_state(State.PLACE_PATTY)

		State.WALK_TO_PREP:
			if has_reached_target():
				change_state(State.ASSEMBLE_BURGER)

		State.WALK_TO_WAITER_TABLE:
			if has_reached_target():
				change_state(State.PLACE_BURGER)

		State.RETURN_TO_IDLE:
			if has_reached_target():
				change_state(State.IDLE)

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Runs the three-step burger assembly as a coroutine.
## Steps: (1) bottom bun → (2) cooked patty → (3) top bun.
## Each step has an ASSEMBLY_STEP_DELAY beat so the animation is visible.
## After all three steps complete the Chef heads to the waiter table.
func _run_assembly_sequence() -> void:
	var step_names := ["bottom_bun", "patty", "top_bun"]
	for step_name in step_names:
		await get_tree().create_timer(ASSEMBLY_STEP_DELAY).timeout
		_assembly_step += 1
		# You can hook a visual/audio cue here per step, e.g.:
		#   $AssemblyParticles.emitting = true
		#   $StepAudio.play()
		print("ChefFSM: assembly step %d (%s) complete" % [_assembly_step, step_name])

	# All three sub-steps done — carry burger to waiter table.
	change_state(State.WALK_TO_WAITER_TABLE)

## Callback fired by the 5-second cook timer.
## Transitions the Chef out of the WAIT_COOK (blocked) state.
func _on_cook_finished() -> void:
	print("ChefFSM: patty cooked — transitioning to PICKUP_PATTY")
	change_state(State.PICKUP_PATTY)


func _on_navigation_agent_2d_velocity_computed(safe_velocity: Vector2) -> void:
	pass # Replace with function body.
