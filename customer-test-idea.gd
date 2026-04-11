extends CharacterBody2D

# ─────────────────────────────────────────────
#  Customer – autonomous NPC
#  State machine:
#    IDLE → WALKING_TO_COUNTER → WAITING →
#    WALKING_TO_PLATE → DONE → queue_free()
# ─────────────────────────────────────────────

const SPEED := 45.0
const ARRIVE_THRESHOLD := 3.0

enum CustomerState { IDLE, WALKING_TO_COUNTER, WAITING, WALKING_TO_PLATE, DONE }

var customer_state: CustomerState = CustomerState.IDLE
var target_pos: Vector2           = Vector2.ZERO
var held_item: Node2D             = null
var plate_node: Node2D            = null
var bob_time: float               = 0.0

@onready var body_sprite: Sprite2D = $Sprite2D
@onready var held_slot: Node2D     = $HeldItemSlot


signal food_picked_up
signal delivered_to_plate
signal customer_done          # fired just before queue_free


# ── Core loop ────────────────────────────────

func _physics_process(delta: float) -> void:
	match customer_state:
		CustomerState.WALKING_TO_COUNTER, CustomerState.WALKING_TO_PLATE:
			_move_toward(delta)
		_:
			velocity = Vector2.ZERO
			if body_sprite:
				body_sprite.offset.y = 0.0
	move_and_slide()


func _move_toward(delta: float) -> void:
	var dir := target_pos - global_position
	if dir.length() <= ARRIVE_THRESHOLD:
		velocity        = Vector2.ZERO
		global_position = target_pos
		_on_arrived()
		return

	velocity = dir.normalized() * SPEED
	bob_time += delta * 9.0
	if body_sprite:
		body_sprite.offset.y = sin(bob_time) * 1.5
		body_sprite.flip_h   = dir.x < -0.1


func _on_arrived() -> void:
	match customer_state:
		CustomerState.WALKING_TO_COUNTER:
			customer_state = CustomerState.WAITING
		CustomerState.WALKING_TO_PLATE:
			_deliver_food()


# ── Public API called by GameManager ─────────

## Kick off the customer – send them to wait at the counter.
func start_order(counter_pos: Vector2) -> void:
	target_pos     = counter_pos
	customer_state = CustomerState.WALKING_TO_COUNTER


## Called by GameManager when the chef places food on the counter.
## Hands the food node to this customer and points them at their plate.
func receive_food(item: Node2D, plate: Node2D) -> void:
	if customer_state != CustomerState.WAITING:
		return
	held_item  = item
	plate_node = plate
	item.reparent(held_slot)
	item.position = Vector2.ZERO
	food_picked_up.emit()
	target_pos     = plate.global_position
	customer_state = CustomerState.WALKING_TO_PLATE


# ── Internal ─────────────────────────────────

func _deliver_food() -> void:
	if held_item != null and plate_node != null:
		held_item.reparent(plate_node)
		held_item.position = Vector2.ZERO
		held_item = null
	delivered_to_plate.emit()
	customer_state = CustomerState.DONE

	# Brief pause so the player can see the delivery, then despawn
	get_tree().create_timer(0.8).timeout.connect(_despawn)


func _despawn() -> void:
	customer_done.emit()
	queue_free()
