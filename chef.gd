# New code from Godot 2D game-engine tutorial
extends CharacterBody2D # I think this calls a function or class that enables usage.
@export var speed = 400
func get_input():
	var input_direction = Input.get_vector("left", "right", "up", "down")
	velocity = input_direction * speed # velocity must be a built-in keyword in Godot.Z
	# It is highlighting which indicates I cannot define it as a standard var variable.
	
func _physics_process(delta: float) -> void: # This is how the funciton autofills as.
	get_input()
	move_and_slide() # build-in-function that enables movement and sliding in game.

'''
Old code Claude gave me for the Chef movement.
Want this here as example of extra stuff I either do/dont need.
Will analyze and refactor this later to be simpler, and readable.
If not useful or readable, I simply will disregard it, and delete it.
'''
#extends CharacterBody2D
#
#const SPEED = 150.0
##var GRAVITY = ProjectSettings.get_setting("physics/2d/default_gravity")
#var GRAVITY = Input.get_vector("left", "right", "up", "down")
#func _physics_process(delta: float) -> void:
	## Gravity
	#if not is_on_floor():
		#velocity.y += GRAVITY * delta
#
	## WASD Input
	#var direction := Vector2.ZERO
	#direction.x = Input.get_axis("ui_left", "ui_right")
	#direction.y = Input.get_axis("ui_up", "ui_down")
#
	#if direction.x != 0:
		#velocity.x = direction.x * SPEED
	#else:
		#velocity.x = move_toward(velocity.x, 0, SPEED)
#
	## Only move vertically with input if you want to test
	## vertical boundaries too, otherwise remove this block
	#if direction.y != 0:
		#velocity.y = direction.y * SPEED
#
	#move_and_slide()
