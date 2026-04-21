extends Control

const C_BG     := Color("#0a0c0f")
const C_PANEL  := Color("#0f1318")
const C_BORDER := Color("#1e3a2f")
const C_ACCENT := Color("#00ff88")
const C_WARN   := Color("#ffb300")
const C_DANGER := Color("#ff4444")
const C_TEXT   := Color("#c8ffd4")
const C_MUTED  := Color("#4a7a5a")
const C_HEADER := Color("#071a10")

@onready var round_label : Label   = %RoundLabel
@onready var hp_label    : Label   = %HPLabel
@onready var score_label : Label   = %ScoreLabel

@onready var cook_spin   : SpinBox = %CookSpin
@onready var prep_spin   : SpinBox = %PrepSpin
@onready var plate1_spin : SpinBox = %Plate1Spin
@onready var plate2_spin : SpinBox = %Plate2Spin
@onready var plate3_spin : SpinBox = %Plate3Spin

@onready var start_btn   : Button  = %StartRoundBtn

@onready var os_window  : PanelContainer = $CenterContainer/OSWindow
@onready var title_bar  : PanelContainer = $CenterContainer/OSWindow/OSVBox/TitleBar
@onready var title_sep  : HSeparator     = $CenterContainer/OSWindow/OSVBox/TitleSep
@onready var footer_sep : HSeparator     = $CenterContainer/OSWindow/OSVBox/FooterSep
@onready var vsep1      : VSeparator     = $CenterContainer/OSWindow/OSVBox/BodyRow/VSep1
@onready var vsep2      : VSeparator     = $CenterContainer/OSWindow/OSVBox/BodyRow/VSep2
@onready var body_row   : HBoxContainer  = $CenterContainer/OSWindow/OSVBox/BodyRow

var _chef_status_labels   : Array[Label] = []
var _waiter_status_labels : Array[Label] = []

func _ready() -> void:
	_apply_theme()
	_connect_signals()
	_build_status_queue_panel()
	refresh_status_queue()
	_refresh_display()

func _connect_signals() -> void:
	start_btn.pressed.connect(_on_start_round_pressed)
	for spin in [cook_spin, prep_spin, plate1_spin, plate2_spin, plate3_spin]:
		spin.value_changed.connect(_on_spin_changed)
	if not RoundManager.round_complete.is_connected(_on_round_complete):
		RoundManager.round_complete.connect(_on_round_complete)
	# Update HP display the moment it changes — don't wait for round to fully end.
	if not RoundManager.hp_changed.is_connected(_on_hp_changed):
		RoundManager.hp_changed.connect(_on_hp_changed)
	if not RoundManager.game_over.is_connected(_on_game_over):
		RoundManager.game_over.connect(_on_game_over)
	if not RoundManager.game_won.is_connected(_on_game_won):
		RoundManager.game_won.connect(_on_game_won)

func _on_spin_changed(_v: float) -> void:
	_refresh_display()
	_dispatch_waiters_from_spins()

func _on_round_complete(_round_num: int) -> void:
	refresh_status_queue()
	_refresh_display()

func _on_hp_changed(_new_hp: int) -> void:
	_refresh_display()

func _on_game_over() -> void:
	_refresh_display()
	start_btn.disabled = true

func _on_game_won() -> void:
	_refresh_display()
	start_btn.disabled = true

func _on_start_round_pressed() -> void:
	var cook := int(cook_spin.value)
	var prep := int(prep_spin.value)
	var p1   := int(plate1_spin.value)
	var p2   := int(plate2_spin.value)
	var p3   := int(plate3_spin.value)

	start_btn.disabled = true
	await RoundManager.execute_round(cook, prep, p1, p2, p3)

	_reset_spins()
	refresh_status_queue()
	_refresh_display()

	# Only re-enable if the game is still running.
	if not GameConfig.is_game_over() and not GameConfig.is_game_won():
		start_btn.disabled = false

func _dispatch_waiters_from_spins() -> void:
	if RoundManager.is_round_active():
		return
	var tree := get_tree()
	if tree == null:
		return

	var waiters : Array = tree.get_nodes_in_group("waiters")
	waiters.sort_custom(func(a, b): return a.name < b.name)

	var roles : Array[String] = []
	for _i in range(int(plate1_spin.value)): roles.append("plate1")
	for _i in range(int(plate2_spin.value)): roles.append("plate2")
	for _i in range(int(plate3_spin.value)): roles.append("plate3")

	var role_idx := 0
	for node in waiters:
		if not (node is WaiterFSM):
			continue
		var waiter := node as WaiterFSM
		if role_idx < roles.size():
			var role := roles[role_idx]
			if waiter.is_turn_active:
				waiter.redirect_to(role)
			else:
				waiter.execute_turn(role)
			role_idx += 1
		else:
			# Spin decreased — send active waiter back to idle position.
			if waiter.is_turn_active:
				waiter.return_to_idle_position()

func _build_status_queue_panel() -> void:
	if body_row == null:
		push_error("os_menu: body_row not found")
		return

	var panel := PanelContainer.new()
	panel.name = "StatusPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_panel(panel, C_PANEL, C_BORDER, 1, 0, 0)
	body_row.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var header_lbl := Label.new()
	header_lbl.text = "NPC STATUS"
	header_lbl.add_theme_color_override("font_color", C_ACCENT)
	header_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(header_lbl)

	var sep := HSeparator.new()
	_style_sep(sep)
	vbox.add_child(sep)

	var chef_section := Label.new()
	chef_section.text = "── CHEFS ──"
	chef_section.add_theme_color_override("font_color", C_MUTED)
	chef_section.add_theme_font_size_override("font_size", 9)
	vbox.add_child(chef_section)

	_chef_status_labels.clear()
	for i in range(3):
		var row := HBoxContainer.new()
		vbox.add_child(row)
		var name_lbl := Label.new()
		name_lbl.text = "Chef %d" % (i + 1)
		name_lbl.custom_minimum_size = Vector2(60, 0)
		name_lbl.add_theme_color_override("font_color", C_TEXT)
		name_lbl.add_theme_font_size_override("font_size", 10)
		row.add_child(name_lbl)
		var status_lbl := Label.new()
		status_lbl.text = "Available"
		status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
		status_lbl.add_theme_color_override("font_color", C_ACCENT)
		status_lbl.add_theme_font_size_override("font_size", 10)
		row.add_child(status_lbl)
		_chef_status_labels.append(status_lbl)

	var sep2 := HSeparator.new()
	_style_sep(sep2)
	vbox.add_child(sep2)

	var waiter_section := Label.new()
	waiter_section.text = "── WAITERS ──"
	waiter_section.add_theme_color_override("font_color", C_MUTED)
	waiter_section.add_theme_font_size_override("font_size", 9)
	vbox.add_child(waiter_section)

	_waiter_status_labels.clear()
	for i in range(3):
		var row := HBoxContainer.new()
		vbox.add_child(row)
		var name_lbl := Label.new()
		name_lbl.text = "Waiter %d" % (i + 1)
		name_lbl.custom_minimum_size = Vector2(60, 0)
		name_lbl.add_theme_color_override("font_color", C_TEXT)
		name_lbl.add_theme_font_size_override("font_size", 10)
		row.add_child(name_lbl)
		var status_lbl := Label.new()
		status_lbl.text = "Available"
		status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
		status_lbl.add_theme_color_override("font_color", C_ACCENT)
		status_lbl.add_theme_font_size_override("font_size", 10)
		row.add_child(status_lbl)
		_waiter_status_labels.append(status_lbl)

func refresh_status_queue() -> void:
	var tree := get_tree()
	if tree == null:
		return

	var waiters : Array = tree.get_nodes_in_group("waiters")
	waiters.sort_custom(func(a, b): return a.name < b.name)

	for i in range(_waiter_status_labels.size()):
		var lbl    := _waiter_status_labels[i]
		var status := "Available"
		var color  := C_ACCENT

		if i < waiters.size():
			var waiter := waiters[i] as WaiterFSM
			if waiter == null or not is_instance_valid(waiter):
				status = "—"
				color  = C_MUTED
			elif waiter.is_turn_active:
				var role := waiter.current_role
				if role in ["plate1", "plate2", "plate3"]:
					status = "On Plate " + role.trim_prefix("plate")
					color  = C_TEXT
				else:
					status = "Busy"
					color  = C_WARN
			else:
				var role := waiter.current_role
				if role in ["plate1", "plate2", "plate3"]:
					status = "Plate %s ✓" % role.trim_prefix("plate")
					color  = C_MUTED
				else:
					status = "Available"
					color  = C_ACCENT
		else:
			status = "—"
			color  = C_MUTED

		lbl.text = status
		lbl.add_theme_color_override("font_color", color)

func _refresh_display() -> void:
	round_label.text = "ROUND %02d" % GameConfig.current_round
	hp_label.text    = "HP: %d/%d"  % [GameConfig.player_hp, GameConfig.MAX_HP]
	score_label.text = "SCORE: %d"  % GameConfig.score

	var hp_color : Color
	match GameConfig.player_hp:
		3: hp_color = C_ACCENT
		2: hp_color = C_WARN
		_: hp_color = C_DANGER
	hp_label.add_theme_color_override("font_color", hp_color)

	var any_alloc := (cook_spin.value + prep_spin.value
		+ plate1_spin.value + plate2_spin.value + plate3_spin.value) > 0
	start_btn.disabled = not any_alloc or RoundManager.is_round_active() or GameConfig.is_game_over() or GameConfig.is_game_won()

func _reset_spins() -> void:
	for spin in [cook_spin, prep_spin, plate1_spin, plate2_spin, plate3_spin]:
		spin.value = 0

func update_hp_display(new_hp: int) -> void:
	GameConfig.player_hp = new_hp
	_refresh_display()

func _apply_theme() -> void:
	_style_panel(os_window, C_PANEL,  C_BORDER, 1, 0, 4)
	_style_panel(title_bar, C_HEADER, C_BORDER, 0, 1, 0)
	_style_sep(title_sep)
	_style_sep(footer_sep)
	_style_sep(vsep1)
	if vsep2: _style_sep(vsep2)
	_style_label(round_label, C_MUTED,  10)
	_style_label(hp_label,    C_ACCENT, 12)
	_style_label(score_label, C_ACCENT, 12)
	for spin in [cook_spin, prep_spin, plate1_spin, plate2_spin, plate3_spin]:
		_style_spinbox(spin)
	_style_start_btn()

func _style_panel(node: Control, bg: Color, border: Color,
				  all_w: int, bottom_w: int, radius: int) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color     = bg
	s.border_color = border
	if all_w    > 0: s.set_border_width_all(all_w)
	if bottom_w > 0: s.border_width_bottom = bottom_w
	s.corner_radius_top_left     = radius
	s.corner_radius_top_right    = radius
	s.corner_radius_bottom_left  = radius
	s.corner_radius_bottom_right = radius
	node.add_theme_stylebox_override("panel", s)

func _style_label(lbl: Label, color: Color, size: int) -> void:
	if lbl == null: return
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", size)

func _style_spinbox(spin: SpinBox) -> void:
	if spin == null: return
	var s := StyleBoxFlat.new()
	s.bg_color     = C_PANEL
	s.border_color = C_BORDER
	s.set_border_width_all(1)
	var le := spin.get_line_edit()
	le.add_theme_stylebox_override("normal", s)
	le.add_theme_stylebox_override("focus",  s)
	le.add_theme_color_override("font_color", C_TEXT)
	le.add_theme_font_size_override("font_size", 13)

func _style_sep(sep: Control) -> void:
	if sep == null: return
	var s := StyleBoxLine.new()
	s.color     = C_BORDER
	s.thickness = 1
	sep.add_theme_stylebox_override("separator", s)

func _style_start_btn() -> void:
	if start_btn == null: return
	var normal := StyleBoxFlat.new()
	normal.bg_color     = Color(0, 0, 0, 0)
	normal.border_color = C_ACCENT
	normal.set_border_width_all(1)
	normal.corner_radius_top_left     = 2
	normal.corner_radius_top_right    = 2
	normal.corner_radius_bottom_left  = 2
	normal.corner_radius_bottom_right = 2
	var hover := StyleBoxFlat.new()
	hover.bg_color = C_ACCENT
	hover.set_border_width_all(0)
	var disabled := StyleBoxFlat.new()
	disabled.bg_color     = Color(0, 0, 0, 0)
	disabled.border_color = C_MUTED
	disabled.set_border_width_all(1)
	start_btn.add_theme_stylebox_override("normal",   normal)
	start_btn.add_theme_stylebox_override("hover",    hover)
	start_btn.add_theme_stylebox_override("pressed",  hover)
	start_btn.add_theme_stylebox_override("disabled", disabled)
	start_btn.add_theme_color_override("font_color",          C_ACCENT)
	start_btn.add_theme_color_override("font_hover_color",    Color.BLACK)
	start_btn.add_theme_color_override("font_pressed_color",  Color.BLACK)
	start_btn.add_theme_color_override("font_disabled_color", C_MUTED)
	start_btn.add_theme_font_size_override("font_size", 12)
