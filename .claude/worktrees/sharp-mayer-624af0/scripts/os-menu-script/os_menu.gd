# os_menu.gd
# Attach to: OSMenuScreen (Control) in os_menu.tscn
# Place at:  res://scripts/ui/os_menu.gd
#
# Responsibilities:
#   - Applies the terminal dark theme to every node in the scene
#   - Handles algorithm column selection (one active at a time)
#   - Updates the left stats panel live as SpinBox values change
#   - Provides a clean public API so RoundManager can push/pull data
#   - Start Round button wired to RoundManager.start_next_round()
extends Control

# ---------------------------------------------------------------------------
# Color palette (mirrors the HTML prototype)
# ---------------------------------------------------------------------------
const C_BG       := Color("#0a0c0f")
const C_PANEL    := Color("#0f1318")
const C_BORDER   := Color("#1e3a2f")
const C_ACCENT   := Color("#00ff88")
const C_WARN     := Color("#ffb300")
const C_DANGER   := Color("#ff4444")
const C_TEXT     := Color("#c8ffd4")
const C_MUTED    := Color("#4a7a5a")
const C_HEADER   := Color("#071a10")
const C_SELECTED := Color("#071a10")

const ALGO_COSTS := { "FIFO": 5, "SJF": 15, "SJCF": 25 }

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------
var current_algo : String = "FIFO"
var stamina      : int    = 100
var serviced     : int    = 0
var unserviced   : int    = 3
var _round_num   : int    = 1

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var stamina_val    : Label  = %StaminaVal
@onready var waiters_val    : Label  = %WaitersVal
@onready var chefs_val      : Label  = %ChefsVal
@onready var unserviced_val : Label  = %UnservicedVal
@onready var serviced_val   : Label  = %ServicedVal
@onready var round_label    : Label  = %RoundLabel
@onready var start_btn      : Button = %StartRoundBtn

@onready var os_window    : PanelContainer = $CenterContainer/OSWindow
@onready var title_bar    : PanelContainer = $CenterContainer/OSWindow/OSVBox/TitleBar
@onready var title_lbl    : Label          = $CenterContainer/OSWindow/OSVBox/TitleBar/TitleHBox/TitleLabel
@onready var serviced_key : Label          = $CenterContainer/OSWindow/OSVBox/FooterRow/ServicedBox/ServicedRow/ServicedKey
@onready var title_sep    : HSeparator     = $CenterContainer/OSWindow/OSVBox/TitleSep
@onready var footer_sep   : HSeparator     = $CenterContainer/OSWindow/OSVBox/FooterSep
@onready var vsep1        : VSeparator     = $CenterContainer/OSWindow/OSVBox/BodyRow/VSep1
@onready var vsep2        : VSeparator     = $CenterContainer/OSWindow/OSVBox/BodyRow/VSep2
@onready var vsep3        : VSeparator     = $CenterContainer/OSWindow/OSVBox/BodyRow/VSep3

@onready var algo_panels : Dictionary = {
	"FIFO": $CenterContainer/OSWindow/OSVBox/BodyRow/FIFOPanel,
	"SJF":  $CenterContainer/OSWindow/OSVBox/BodyRow/SJFPanel,
	"SJCF": $CenterContainer/OSWindow/OSVBox/BodyRow/SJCFPanel,
}

@onready var waiters_spin : Dictionary = {
	"FIFO": %FIFOWaiters,
	"SJF":  %SJFWaiters,
	"SJCF": %SJCFWaiters,
}

@onready var chefs_spin : Dictionary = {
	"FIFO": [%FIFOChefPrepNum, %FIFOChefCookNum],
	"SJF":  [%SJFChefPrepNum,  %SJFChefCookNum],
	"SJCF": [%SJCFChefPrepNum, %SJCFChefCookNum],
}

@onready var algo_name_labels : Dictionary = {
	"FIFO": $CenterContainer/OSWindow/OSVBox/BodyRow/FIFOPanel/FIFOVBox/FIFOHeader/FIFOName,
	"SJF":  $CenterContainer/OSWindow/OSVBox/BodyRow/SJFPanel/SJFVBox/SJFHeader/SJFName,
	"SJCF": $CenterContainer/OSWindow/OSVBox/BodyRow/SJCFPanel/SJCFVBox/SJCFHeader/SJCFName,
}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_apply_theme()
	_connect_signals()
	_select_algo("FIFO")
	_refresh_stats()


# ---------------------------------------------------------------------------
# Theme
# ---------------------------------------------------------------------------
func _apply_theme() -> void:
	_set_panel_style(os_window, C_PANEL,  C_BORDER, 1, 0, 4)
	_set_panel_style(title_bar, C_HEADER, C_BORDER, 0, 1, 0)

	title_lbl.add_theme_color_override("font_color", C_ACCENT)
	title_lbl.add_theme_font_size_override("font_size", 13)

	round_label.add_theme_color_override("font_color", C_MUTED)
	round_label.add_theme_font_size_override("font_size", 10)

	_style_stat_key_val("StatsBox/StaminaRow/StaminaKey",       "StatsBox/StaminaRow/StaminaVal",       C_ACCENT)
	_style_stat_key_val("StatsBox/WaitersRow/WaitersKey",       "StatsBox/WaitersRow/WaitersVal",       C_ACCENT)
	_style_stat_key_val("StatsBox/ChefsRow/ChefsKey",           "StatsBox/ChefsRow/ChefsVal",           C_ACCENT)
	_style_stat_key_val("StatsBox/UnservicedRow/UnservicedKey", "StatsBox/UnservicedRow/UnservicedVal", C_WARN)

	serviced_key.add_theme_color_override("font_color", C_MUTED)
	serviced_key.add_theme_font_size_override("font_size", 10)
	serviced_val.add_theme_color_override("font_color", C_ACCENT)
	serviced_val.add_theme_font_size_override("font_size", 14)

	for algo in algo_panels.keys():
		_style_algo_panel(algo, false)
		_style_algo_labels(algo)
		_style_spinbox(waiters_spin[algo] as SpinBox)
		for chef_box in chefs_spin[algo]:
			_style_spinbox(chef_box as SpinBox)

	_style_separator(title_sep)
	_style_separator(footer_sep)
	_style_separator(vsep1)
	_style_separator(vsep2)
	_style_separator(vsep3)

	_style_start_btn()


func _style_stat_key_val(key_rel: String, val_rel: String, val_color: Color) -> void:
	var base    := "CenterContainer/OSWindow/OSVBox/BodyRow/"
	var key_lbl := get_node(base + key_rel) as Label
	var val_lbl := get_node(base + val_rel) as Label
	key_lbl.add_theme_color_override("font_color", C_MUTED)
	key_lbl.add_theme_font_size_override("font_size", 10)
	val_lbl.add_theme_color_override("font_color", val_color)
	val_lbl.add_theme_font_size_override("font_size", 14)


func _style_algo_labels(algo: String) -> void:
	var panel : PanelContainer = algo_panels[algo] as PanelContainer
	var vbox  : VBoxContainer  = panel.get_node(algo + "VBox") as VBoxContainer

	var name_lbl  := vbox.get_node(algo + "Header/" + algo + "Name")  as Label
	var badge_lbl := vbox.get_node(algo + "Header/" + algo + "Badge") as Label
	var cost_lbl  := vbox.get_node(algo + "CostLabel")                as Label

	name_lbl.add_theme_color_override("font_color", C_MUTED)
	name_lbl.add_theme_font_size_override("font_size", 11)

	badge_lbl.add_theme_color_override("font_color", C_MUTED)
	badge_lbl.add_theme_font_size_override("font_size", 9)

	cost_lbl.add_theme_color_override("font_color", C_MUTED)
	cost_lbl.add_theme_font_size_override("font_size", 9)

	var waiters_lbl := vbox.get_node(
		algo + "Inputs/" + algo + "WaitersRow/" + algo + "WaitersLabel"
	) as Label
	waiters_lbl.add_theme_color_override("font_color", C_MUTED)
	waiters_lbl.add_theme_font_size_override("font_size", 9)

	var chef_prep_lbl := vbox.get_node(
		algo + "Inputs/" + algo + "ChefPrep/" + algo + "ChefsPrepLabel"
	) as Label
	chef_prep_lbl.add_theme_color_override("font_color", C_MUTED)
	chef_prep_lbl.add_theme_font_size_override("font_size", 9)

	var chef_cook_lbl := vbox.get_node(
		algo + "Inputs/" + algo + "ChefCook/" + algo + "ChefsCookLabel"
	) as Label
	chef_cook_lbl.add_theme_color_override("font_color", C_MUTED)
	chef_cook_lbl.add_theme_font_size_override("font_size", 9)


func _style_algo_panel(algo: String, selected: bool) -> void:
	var style             := StyleBoxFlat.new()
	style.bg_color         = C_SELECTED if selected else C_PANEL
	style.border_color     = C_ACCENT   if selected else C_BORDER
	style.border_width_top = 2 if selected else 0
	style.border_width_left   = 0
	style.border_width_right  = 1
	style.border_width_bottom = 0
	(algo_panels[algo] as Control).add_theme_stylebox_override("panel", style)


func _set_panel_style(
	node               : Control,
	bg                 : Color,
	border             : Color,
	border_all         : int,
	border_bottom_only : int,
	radius             : int
) -> void:
	var style         := StyleBoxFlat.new()
	style.bg_color     = bg
	style.border_color = border

	if border_all > 0:
		style.set_border_width_all(border_all)
	if border_bottom_only > 0:
		style.border_width_bottom = border_bottom_only

	style.corner_radius_top_left     = radius
	style.corner_radius_top_right    = radius
	style.corner_radius_bottom_left  = radius
	style.corner_radius_bottom_right = radius

	node.add_theme_stylebox_override("panel", style)


func _style_spinbox(spinbox: SpinBox) -> void:
	var style         := StyleBoxFlat.new()
	style.bg_color     = C_PANEL
	style.border_color = C_BORDER
	style.set_border_width_all(1)
	spinbox.get_line_edit().add_theme_stylebox_override("normal", style)
	spinbox.get_line_edit().add_theme_stylebox_override("focus",  style)
	spinbox.get_line_edit().add_theme_color_override("font_color", C_TEXT)
	spinbox.get_line_edit().add_theme_font_size_override("font_size", 13)


func _style_separator(sep: Control) -> void:
	var style      := StyleBoxLine.new()
	style.color     = C_BORDER
	style.thickness = 1
	if sep is HSeparator:
		sep.add_theme_stylebox_override("separator", style)
	elif sep is VSeparator:
		sep.add_theme_stylebox_override("separator", style)


func _style_start_btn() -> void:
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

	var disabled_style := StyleBoxFlat.new()
	disabled_style.bg_color     = Color(0, 0, 0, 0)
	disabled_style.border_color = C_MUTED
	disabled_style.set_border_width_all(1)

	start_btn.add_theme_stylebox_override("normal",   normal)
	start_btn.add_theme_stylebox_override("hover",    hover)
	start_btn.add_theme_stylebox_override("pressed",  hover)
	start_btn.add_theme_stylebox_override("disabled", disabled_style)
	start_btn.add_theme_color_override("font_color",          C_ACCENT)
	start_btn.add_theme_color_override("font_hover_color",    Color("#000000"))
	start_btn.add_theme_color_override("font_pressed_color",  Color("#000000"))
	start_btn.add_theme_color_override("font_disabled_color", C_MUTED)
	start_btn.add_theme_font_size_override("font_size", 12)


# ---------------------------------------------------------------------------
# Signal wiring
# ---------------------------------------------------------------------------
func _connect_signals() -> void:
	for algo in algo_panels.keys():
		(algo_panels[algo] as Control).gui_input.connect(_on_algo_panel_input.bind(algo))
		(waiters_spin[algo] as SpinBox).value_changed.connect(_on_input_changed)
		for chef_box in chefs_spin[algo]:
			(chef_box as SpinBox).value_changed.connect(_on_input_changed)

	start_btn.pressed.connect(_on_start_round_pressed)


func _on_algo_panel_input(event: InputEvent, algo: String) -> void:
	if event is InputEventMouseButton \
	and event.pressed \
	and event.button_index == MOUSE_BUTTON_LEFT:
		_select_algo(algo)


func _on_input_changed(_value: float) -> void:
	_refresh_stats()


func _on_start_round_pressed() -> void:
	# Push allocation choices into GameConfig so RoundManager
	# spawns the correct number of NPCs this round.
	GameConfigNode.new().set_npc_counts(
		get_allocated_chefs(),
		get_allocated_waiters(),
		unserviced
	)

	# Kick off the next round in the OS kernel.
	RoundManagerNode.new().start_next_round()

	# Sync the round counter display with what RoundManager reports.
	_round_num = RoundManagerNode.new().get_current_round()
	round_label.text = "ROUND %02d" % _round_num

	# Reflect any stamina cost from the chosen algorithm.
	var w    := get_allocated_waiters()
	var c    := get_allocated_chefs()
	var cost : int = ALGO_COSTS.get(current_algo, 0)
	stamina = max(0, stamina - cost * (w + c))

	# Reset all spinboxes for the next round's allocation.
	for algo in waiters_spin.keys():
		(waiters_spin[algo] as SpinBox).value = 0
		for chef_box in chefs_spin[algo]:
			(chef_box as SpinBox).value = 0

	_refresh_stats()


# ---------------------------------------------------------------------------
# Selection logic
# ---------------------------------------------------------------------------
func _select_algo(algo: String) -> void:
	current_algo = algo
	for a in algo_panels.keys():
		var is_selected : bool = (a == algo)
		_style_algo_panel(a, is_selected)
		(algo_name_labels[a] as Label).add_theme_color_override(
			"font_color",
			C_ACCENT if is_selected else C_MUTED
		)
		(waiters_spin[a] as SpinBox).editable   = is_selected
		(waiters_spin[a] as SpinBox).modulate.a = 1.0 if is_selected else 0.35
		for chef_box in chefs_spin[a]:
			(chef_box as SpinBox).editable   = is_selected
			(chef_box as SpinBox).modulate.a = 1.0 if is_selected else 0.35
	_refresh_stats()


# ---------------------------------------------------------------------------
# Live stats refresh
# ---------------------------------------------------------------------------
func _refresh_stats() -> void:
	var total_w := 0
	var total_c := 0
	for algo in waiters_spin.keys():
		total_w += int((waiters_spin[algo] as SpinBox).value)
		for chef_box in chefs_spin[algo]:
			total_c += int((chef_box as SpinBox).value)

	var cost      : int = ALGO_COSTS.get(current_algo, 0)
	var spent     : int = min(stamina, (total_w + total_c) * cost)
	var remaining : int = max(0, stamina - spent)

	waiters_val.text    = str(total_w)
	chefs_val.text      = str(total_c)
	stamina_val.text    = str(remaining)
	serviced_val.text   = str(serviced)
	unserviced_val.text = str(unserviced)

	var sta_color : Color
	if remaining < 25:
		sta_color = C_DANGER
	elif remaining < 55:
		sta_color = C_WARN
	else:
		sta_color = C_ACCENT
	stamina_val.add_theme_color_override("font_color", sta_color)

	start_btn.disabled = (total_w == 0 and total_c == 0)


# ---------------------------------------------------------------------------
# Public API — RoundManager calls these to push/pull data
# ---------------------------------------------------------------------------

## Called by RoundManager at the start of each new round to sync state.
func sync_from_manager(
	new_stamina    : int,
	new_unserviced : int,
	new_serviced   : int,
	round          : int
) -> void:
	stamina    = new_stamina
	unserviced = new_unserviced
	serviced   = new_serviced
	_round_num = round
	round_label.text = "ROUND %02d" % _round_num
	_refresh_stats()


func get_selected_algo() -> String:
	return current_algo


func get_allocated_waiters() -> int:
	return int((waiters_spin[current_algo] as SpinBox).value)


func get_allocated_chefs() -> int:
	var total := 0
	for chef_box in chefs_spin[current_algo]:
		total += int((chef_box as SpinBox).value)
	return total
