# Reusing Chef.gd script for testing purposes.
extends CharacterBody2D # I think this calls a function or class that enables usage.
@export var speed = 400
func get_input():
	var input_direction = Input.get_vector("left", "right", "up", "down")
	velocity = input_direction * speed # velocity must be a built-in keyword in Godot.Z
	# It is highlighting which indicates I cannot define it as a standard var variable.
	
func _physics_process(delta: float) -> void: # This is how the funciton autofills as.
	get_input()
	move_and_slide() # build-in-function that enables movement and sliding in game.

#extends AnimatedSprite2D
#
#
## Called when the node enters the scene tree for the first time.
#func _ready() -> void:
	#pass # Replace with function body.
#
#
## Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta: float) -> void:
	#pass
