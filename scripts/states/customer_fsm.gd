# =============================================================================
# customer_fsm.gd
# =============================================================================
# PURPOSE: Controls a Customer NPC that walks to their assigned plate, waits
#          for food during the round, and reacts to being fed or ignored.
#
# OS SCHEDULING ANALOGY:
#   Customers model "jobs" in the ready-queue waiting for a CPU time slice.
#   Getting fed = being dispatched. Being unfed = starvation.
#
# STATE FLOW:
#   SPAWNING -> WALK_TO_SEAT -> IDLE_SEATED -> WAITING
#            -> FED (celebrate, then LEAVING -> queue_free)
#            -> LEAVING (unfed exit -> queue_free)
#
# STALE-COROUTINE GUARD:
#   _state_gen is incremented on every change_state() call. Each coroutine
#   captures `gen = _state_gen` at entry and checks before any post-await
#   side-effect. A mismatch means the state changed mid-wait — bail silently.
#   (Same pattern as ChefFSM — prevents ghost transitions from FED/LEAVING
#   timers firing after the customer has already been freed or re-entered.)
# =============================================================================

class_name CustomerFSM
extends BaseFSM

# ---------------------------------------------------------------------------
# State enum
# ---------------------------------------------------------------------------

enum State {
	SPAWNING,
	WALK_TO_SEAT,
	IDLE_SEATED,
	WAITING,
	FED,
	LEAVING,
}

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var plate_index: int = 1

# ---------------------------------------------------------------------------
# Runtime context (set by RoundManager before walk_to_seat())
# ---------------------------------------------------------------------------

var assigned_plate: Node2D = null

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

var _has_been_fed : bool = false

# Stale-coroutine guard — incremented on every state change.
var _state_gen    : int  = 0

# ---------------------------------------------------------------------------
# Child-node references
# ---------------------------------------------------------------------------

@onready var _audio_ding: AudioStreamPlayer2D = $AudioStreamPlayer2D

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const FED_CELEBRATE_DURATION : float = 1.0
const LEAVING_EXIT_DURATION  : float = 1.5

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal customer_fed(customer: CustomerFSM)
signal customer_timed_out(customer: CustomerFSM)

# ---------------------------------------------------------------------------
# Override change_state to track generation
# ---------------------------------------------------------------------------

func change_state(new_state: int) -> void:
	_state_gen += 1
	super.change_state(new_state)

# ---------------------------------------------------------------------------
# BaseFSM hooks
# ---------------------------------------------------------------------------

func _on_ready() -> void:
	_has_been_fed = false
	change_state(State.SPAWNING)


func _on_state_enter(state: int) -> void:
	var gen := _state_gen  # capture generation for stale-guard checks below

	match state:

		State.SPAWNING:
			play_anim("idle")
			# Waits here until RoundManager calls walk_to_seat().

		State.WALK_TO_SEAT:
			play_anim("walk")
			if assigned_plate:
				move_to(assigned_plate.global_position)
			else:
				push_error("CustomerFSM: assigned_plate not set before walk_to_seat()")

		State.IDLE_SEATED:
			play_anim("idle")
			# Seated and calm — waits for RoundManager.start_waiting().

		State.WAITING:
			play_anim("waiting")
			_has_been_fed = false

		State.FED:
			_has_been_fed = true
			play_anim("happy")
			if _audio_ding:
				_audio_ding.play()
			customer_fed.emit(self)
			await get_tree().create_timer(FED_CELEBRATE_DURATION).timeout
			if _state_gen != gen:
				return  # state changed during celebration — don't double-transition
			change_state(State.LEAVING)

		State.LEAVING:
			play_anim("walk")
			await get_tree().create_timer(LEAVING_EXIT_DURATION).timeout
			if _state_gen != gen:
				return  # already freed or re-entered — don't call queue_free twice
			queue_free()


func _process_state(_delta: float) -> void:
	match current_state:
		State.WALK_TO_SEAT:
			if has_reached_target():
				change_state(State.IDLE_SEATED)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func start_waiting() -> void:
	if current_state == State.IDLE_SEATED:
		change_state(State.WAITING)
	else:
		push_warning("CustomerFSM: start_waiting() called before seated (state=%d)" % current_state)


func receive_meal() -> void:
	if current_state == State.WAITING:
		change_state(State.FED)
	else:
		push_warning("CustomerFSM: receive_meal() called outside WAITING (state=%d)" % current_state)


func check_fed_status() -> bool:
	if not _has_been_fed and current_state == State.WAITING:
		customer_timed_out.emit(self)
		change_state(State.LEAVING)
		return false
	return true


func walk_to_seat() -> void:
	change_state(State.WALK_TO_SEAT)


func is_seated() -> bool:
	return current_state == State.IDLE_SEATED or \
		   current_state == State.WAITING or \
		   current_state == State.FED
