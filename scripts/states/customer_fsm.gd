# =============================================================================
# customer_fsm.gd
# =============================================================================
# PURPOSE: Controls a Customer NPC that walks to their assigned plate, waits
#          for food during the round, and reacts to being fed or ignored.
#
# OS SCHEDULING ANALOGY:
#   Customers model "jobs" queued in the ready-queue waiting for a CPU time
#   slice.  When the round (scheduling cycle) starts they enter WAITING —
#   just like a process waiting to be scheduled.  Getting fed = being
#   dispatched.  Being left unfed = starvation, which is exactly the fairness
#   problem Round-Robin is designed to prevent.
#
# STATE FLOW:
#   SPAWNING
#     └─► WALK_TO_SEAT  (navigate to assigned plate node position)
#           └─► IDLE_SEATED  (wait for RoundManager to call start_waiting())
#                 └─► WAITING  (hungry — waiting for WaiterFSM to call receive_meal())
#                       ├─► FED      (meal arrived — ding! → LEAVING → queue_free)
#                       └─► LEAVING  (round ended unfed → silent exit → queue_free)
# =============================================================================

class_name CustomerFSM
extends BaseFSM

# ---------------------------------------------------------------------------
# State enum
# ---------------------------------------------------------------------------

enum State {
	SPAWNING,       # Just instantiated, not yet assigned a seat
	WALK_TO_SEAT,   # Walking to their plate position
	IDLE_SEATED,    # Seated, waiting for round to start
	WAITING,        # Round active — hungry, waiting for food
	FED,            # Meal delivered — celebrate then leave
	LEAVING,        # Walking off / fading out before queue_free
}

# ---------------------------------------------------------------------------
# Exported configuration
# ---------------------------------------------------------------------------

## Which plate slot this customer maps to (1–7, matching your plate nodes).
## Set this in the Inspector or via RoundManager before calling walk_to_seat().
@export var plate_index: int = 1

# ---------------------------------------------------------------------------
# Runtime context
# (Assigned by RoundManager before walk_to_seat() is called)
# ---------------------------------------------------------------------------

## The plate Node2D this customer is assigned to — Waiter delivers here.
var assigned_plate: Node2D = null

# ---------------------------------------------------------------------------
# Internal flags
# ---------------------------------------------------------------------------

var _has_been_fed: bool = false

# ---------------------------------------------------------------------------
# Child-node references
# ---------------------------------------------------------------------------

## AudioStreamPlayer2D for the positive "ding" on a successful delivery.
## Must be a direct child node named "AudioStreamPlayer2D" in the scene.
@onready var _audio_ding: AudioStreamPlayer2D = $AudioStreamPlayer2D

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## How long the customer celebrates before leaving after being fed.
const FED_CELEBRATE_DURATION:  float = 1.0

## How long the leaving animation plays before queue_free() is called.
const LEAVING_EXIT_DURATION:   float = 1.5

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Fired when a meal is successfully delivered to this customer.
## RoundManager listens to update the feed-count for fairness checking.
signal customer_fed(customer: CustomerFSM)

## Fired when check_fed_status() finds the customer was not fed this round.
## RoundManager uses this to deduct HP from the player OS.
signal customer_timed_out(customer: CustomerFSM)

# ---------------------------------------------------------------------------
# BaseFSM hooks
# ---------------------------------------------------------------------------

func _on_ready() -> void:
	_has_been_fed = false
	change_state(State.SPAWNING)

func _on_state_enter(state: int) -> void:
	match state:

		State.SPAWNING:
			play_anim("idle")
			# The customer stands at their spawn point.
			# RoundManager calls walk_to_seat() once the assigned_plate is set.

		State.WALK_TO_SEAT:
			play_anim("walk")
			if assigned_plate:
				move_to(assigned_plate.global_position)
			else:
				push_error("CustomerFSM: assigned_plate not set before walk_to_seat()")

		State.IDLE_SEATED:
			play_anim("idle")
			# Seated and calm — waiting for RoundManager to call start_waiting()
			# when the player clicks the Start button.

		State.WAITING:
			play_anim("waiting")   # e.g. impatient tap / look-around animation
			_has_been_fed = false  # Reset each round so fairness tracking is fresh

		State.FED:
			_has_been_fed = true
			play_anim("happy")
			# Play positive ding — confirms to the player a delivery succeeded.
			if _audio_ding:
				_audio_ding.play()
			customer_fed.emit(self)
			# Brief celebration before exiting the scene.
			await get_tree().create_timer(FED_CELEBRATE_DURATION).timeout
			change_state(State.LEAVING)

		State.LEAVING:
			play_anim("walk")
			# The customer walks off-screen (or fades).  After the exit duration
			# the node is freed — RoundManager no longer references it.
			await get_tree().create_timer(LEAVING_EXIT_DURATION).timeout
			queue_free()

func _process_state(_delta: float) -> void:
	match current_state:

		State.WALK_TO_SEAT:
			if has_reached_target():
				change_state(State.IDLE_SEATED)

		# All other states are timer-driven; nothing to poll here.

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Called by RoundManager when the round timer starts.
## Only transitions if the customer is already seated — guards against
## calling this before walk_to_seat() has finished.
func start_waiting() -> void:
	if current_state == State.IDLE_SEATED:
		change_state(State.WAITING)
	else:
		push_warning("CustomerFSM: start_waiting() called before customer is seated (state=%d)" % current_state)

## Called by WaiterFSM when a burger is delivered to this customer's plate.
## Transitions to FED — only valid while WAITING.
func receive_meal() -> void:
	if current_state == State.WAITING:
		change_state(State.FED)
	else:
		push_warning("CustomerFSM: receive_meal() called outside of WAITING state (state=%d)" % current_state)

## Called by RoundManager at round end to apply the fairness / HP penalty rule.
## Returns true  → customer was fed (no penalty).
## Returns false → customer was NOT fed (fires customer_timed_out signal).
func check_fed_status() -> bool:
	if not _has_been_fed and current_state == State.WAITING:
		customer_timed_out.emit(self)
		# Silently leave — no celebration sound on an unfed exit.
		change_state(State.LEAVING)
		return false
	return true

## Assigns this customer to a plate and begins walking to it.
## RoundManager calls this after spawn so the seat assignment is clean.
func walk_to_seat() -> void:
	change_state(State.WALK_TO_SEAT)

## Returns true once the customer has reached their seat and is seated.
func is_seated() -> bool:
	return current_state == State.IDLE_SEATED or \
		   current_state == State.WAITING or \
		   current_state == State.FED
