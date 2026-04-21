# =============================================================================
# kitchen_scene.gd
# Attach to: the ROOT node of kitchen-level.tscn
# =============================================================================
# PURPOSE: Entry point for the kitchen scene.
#
#   1. Connects RoundManager signals.
#   2. Calls RoundManager.start_game() after the nav server is ready.
#   3. Handles the game-over overlay (programmatic — no extra .tscn needed).
# =============================================================================

extends Node2D

# ---------------------------------------------------------------------------
# Game-over overlay (built in code — no separate scene required)
# ---------------------------------------------------------------------------

var _game_over_shown : bool = false
var _game_won_shown  : bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Connect RoundManager signals
	RoundManager.hp_changed.connect(_on_hp_changed)
	RoundManager.game_over.connect(_on_game_over)
	RoundManager.game_won.connect(_on_game_won)
	RoundManager.round_complete.connect(_on_round_complete)

	# Start the game — one physics frame defer is inside start_game() already
	RoundManager.start_game()


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_hp_changed(new_hp: int) -> void:
	print("KitchenScene: HP changed -> %d" % new_hp)
	# If an OS menu is open in the scene you can call its update here:
	# var menu := get_node_or_null("OSMenu")
	# if menu: menu.update_hp_display(new_hp)


func _on_round_complete(round_num: int) -> void:
	print("KitchenScene: round %d complete" % round_num)


func _on_game_over() -> void:
	if _game_over_shown:
		return
	_game_over_shown = true
	_show_game_over_overlay()

func _on_game_won() -> void:
	if _game_won_shown:
		return
	_game_won_shown = true
	_show_win_overlay()

# ---------------------------------------------------------------------------
# Game-over overlay (black screen + "GAME OVER" text + score)
# ---------------------------------------------------------------------------

func _show_game_over_overlay() -> void:
	# CanvasLayer ensures the overlay sits above ALL 2D/3D content
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)

	# Full-screen black background
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)

	# "GAME OVER" label — centered
	var title := Label.new()
	title.text = "GAME OVER"
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title.position      -= Vector2(200, 60)
	title.custom_minimum_size = Vector2(400, 80)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color.RED)
	canvas.add_child(title)

	# Score line
	var score_lbl := Label.new()
	score_lbl.text = "Final Score: %d customers served" % GameConfig.score
	score_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	score_lbl.position      -= Vector2(200, -20)
	score_lbl.custom_minimum_size = Vector2(400, 40)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_lbl.add_theme_font_size_override("font_size", 24)
	score_lbl.add_theme_color_override("font_color", Color.WHITE)
	canvas.add_child(score_lbl)

	# Restart hint
	var hint := Label.new()
	hint.text = "Press F5 to restart"
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hint.position      -= Vector2(200, -60)
	hint.custom_minimum_size = Vector2(400, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	canvas.add_child(hint)

func _show_win_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)

	var title := Label.new()
	title.text = "Winner!!!"
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title.position      -= Vector2(200, 60)
	title.custom_minimum_size = Vector2(400, 80)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color.GREEN)
	canvas.add_child(title)

	var score_lbl := Label.new()
	score_lbl.text = "Final Score: %d customers served" % GameConfig.score
	score_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	score_lbl.position      -= Vector2(200, -20)
	score_lbl.custom_minimum_size = Vector2(400, 40)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_lbl.add_theme_font_size_override("font_size", 24)
	score_lbl.add_theme_color_override("font_color", Color.WHITE)
	canvas.add_child(score_lbl)

	var hint := Label.new()
	hint.text = "Press F5 to restart"
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hint.position      -= Vector2(200, -60)
	hint.custom_minimum_size = Vector2(400, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	canvas.add_child(hint)
