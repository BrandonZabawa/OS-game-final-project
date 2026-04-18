# kitchen_scene.gd
# Attach to the ROOT node of your kitchen scene (kitchen-level.tscn).
#
# This is the only entry point into the round loop — it tells RoundManager
# to start once the scene is fully in the tree. All NPC spawning, group
# queries, and navigation baking happen AFTER this script's _ready() returns.
extends Node2D

func _ready() -> void:
	# RoundManager is an AutoLoad singleton (Project > Project Settings > AutoLoad).
	# Calling start_next_round() here is safe because:
	#   1. AutoLoads are initialized before any scene _ready() fires.
	#   2. start_next_round() defers one physics frame internally before
	#      querying groups, so NavigationServer has time to bake the navmesh.
	RoundManager.start_next_round()
