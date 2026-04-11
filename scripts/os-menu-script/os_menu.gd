# os_menu.gd
# Attach to: OSMenuScreen (Control) in os_menu.tscn
# Place at:  res://scripts/ui/os_menu.gd
#
# Responsibilities:
#   - Applies the terminal dark theme to every node in the scene
#   - Handles algorithm column selection (one active at a time)
#   - Updates the left stats panel live as SpinBox values change
#   - Provides a clean public API so OSManager can push/pull data
#   - Start Round button stub — wire to OSManager.start_round() later
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

# Stamina cost per unit (waiters + chefs) allocated under each algorithm
const ALGO_COSTS := { "FIFO": 5, "SJF": 15, "SJCF": 25 }

# ---------------------------------------------------------------------------
# Runtime state  (OSManager will push updates via the public API below)
# ---------------------------------------------------------------------------
var current_algo  : String = "FIFO"
var stamina       : int    = 100
var serviced      : int    = 0
var unserviced    : int    = 3
var _round_num    : int    = 1

# ---------------------------------------------------------------------------
# Node references — uses % (unique name) shorthand for key nodes
# ---------------------------------------------------------------------------
@onready var stamina_val    : Label  = %StaminaVal
@onready var waiters_val    : Label  = %WaitersVal
@onready var chefs_val      : Label  = %ChefsVal
@onready var unserviced_val : Label  = %UnservicedVal
@onready var serviced_val   : Label  = %ServicedVal
@onready var round_label    : Label  = %RoundLabel
@onready var start_btn      : Button = %StartRoundBtn
@onready var background		: ColorRect = $Background
# Algorithm PanelContainers
@onready var algo_panels := {
	"FIFO": $CenterContainer/OSWindow/OSVBox/BodyRow/FIFOPanel,
	"SJF":  $CenterContainer/OSWindow/OSVBox/BodyRow/SJFPanel,
	"SJCF": $CenterContainer/OSWindow/OSVBox/BodyRow/SJCFPanel,
}

# SpinBox refs — keyed by algo name for clean iteration
@onready var waiters_spin := {
	"FIFO": %FIFOWaiters,
	"SJF":  %SJFWaiters,
	"SJCF": %SJCFWaiters,
}
@onready var chefs_spin := {
	"FIFO": %FIFOChefs,
	"SJF":  %SJFChefs,
	"SJCF": %SJCFChefs,
}

# Header name labels — for accent color on selection
@onready var algo_name_labels := {
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
# Theme — all visual styling applied here so the .tscn stays clean
# ---------------------------------------------------------------------------
func _apply_theme() -> void:
	# Root background (proper way to assign the color theme in Godot)
	#@onready var background: ColorRect = $Background
	assert(background != null, "OSMenu: $Background node not found — check the node name in the scene tree")
	background.color = C_BG 

	# Main window panel
	_set_panel_style(
		$CenterContainer/OSWindow,
		C_PANEL, C_BORDER, 1, 0, 4
	)

	# Title bar panel
	_set_panel_style(
		$CenterContainer/OSWindow/OSVBox/TitleBar,
		C_HEADER, C_BORDER, 0, 1, 0
	)

	# Title label
	var title_lbl := $CenterContainer/OSWindow/OSVBox/TitleBar/TitleHBox/TitleLabel as Label
	title_lbl.add_theme_color_override("font_color", C_ACCENT)
	title_lbl.add_theme_font_size_override("font_size", 13)

	# Round badge
	round_label.add_theme_color_override("font_color", C_MUTED)
	round_label.add_theme_font_size_override("font_size", 10)

	# Stat key/value labels
	_style_stat_key_val("StatsBox/StaminaRow/StaminaKey",   "StatsBox/StaminaRow/StaminaVal",   C_ACCENT)
	_style_stat_key_val("StatsBox/WaitersRow/WaitersKey",   "StatsBox/WaitersRow/WaitersVal",   C_ACCENT)
	_style_stat_key_val("StatsBox/ChefsRow/ChefsKey",       "StatsBox/ChefsRow/ChefsVal",       C_ACCENT)
	_style_stat_key_val("StatsBox/UnservicedRow/UnservicedKey", "StatsBox/UnservicedRow/UnservicedVal", C_WARN)

	# Footer serviced row
	var s_key := $CenterContainer/OSWindow/OSVBox/FooterRow/ServicedBox/ServicedRow/ServicedKey as Label
	s_key.add_theme_color_override("font_color", C_MUTED)
	s_key.add_theme_font_size_override("font_size", 10)
	serviced_val.add_theme_color_override("font_color", C_ACCENT)
	serviced_val.add_theme_font_size_override("font_size", 14)

	# Algo panels
	for algo in algo_panels.keys():
		_style_algo_panel(algo, false)
		_style_algo_labels(algo)
		_style_spinbox(waiters_spin[algo])
		_style_spinbox(chefs_spin[algo])

	# Separators
	_style_separator($CenterContainer/OSWindow/OSVBox/TitleSep)
	_style_separator($CenterContainer/OSWindow/OSVBox/FooterSep)
	for sep_name in ["VSep1", "VSep2", "VSep3"]:
		_style_separator($CenterContainer/OSWindow/OSVBox/BodyRow.get_node(sep_name))

	# Start Round button
	_style_start_btn()

func _style_stat_key_val(key_rel: String, val_rel: String, val_color: Color) -> void:
	var base := "CenterContainer/OSWindow/OSVBox/BodyRow/"
	var key_lbl := get_node(base + key_rel) as Label
	var val_lbl := get_node(base + val_rel) as Label
	key_lbl.add_theme_color_override("font_color", C_MUTED)
	key_lbl.add_theme_font_size_override("font_size", 10)
	val_lbl.add_theme_color_override("font_color", val_color)
	val_lbl.add_theme_font_size_override("font_size", 14)

func _style_algo_labels(algo: String) -> void:
	# No type for panel and vbox.
	# Im currently unsure if they must have some type or not. Still new to GDScript
	var panel = algo_panels[algo]
	var vbox  = panel.get_node(algo + "VBox")

	# Algorithm name
	var name_lbl := vbox.get_node(algo + "Header/" + algo + "Name") as Label
	name_lbl.add_theme_color_override("font_color", C_MUTED)
	name_lbl.add_theme_font_size_override("font_size", 11)

	# Stamina cost badge
	var badge_lbl := vbox.get_node(algo + "Header/" + algo + "Badge") as Label
	badge_lbl.add_theme_color_override("font_color", C_MUTED)
	badge_lbl.add_theme_font_size_override("font_size", 9)

	# Description label at the bottom
	var cost_lbl := vbox.get_node(algo + "CostLabel") as Label
	cost_lbl.add_theme_color_override("font_color", C_MUTED)
	cost_lbl.add_theme_font_size_override("font_size", 9)

	# Input row labels
	for row_prefix in ["Waiters", "Chefs"]:
		var lbl := vbox.get_node(
			algo + "Inputs/" + algo + row_prefix + "Row/" + algo + row_prefix + "Label"
		) as Label
		lbl.add_theme_color_override("font_color", C_MUTED)
		lbl.add_theme_font_size_override("font_size", 9)

func _style_algo_panel(algo: String, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color            = C_SELECTED if selected else C_PANEL
	style.border_color        = C_ACCENT   if selected else C_BORDER
	style.border_width_top    = 2 if selected else 0
	style.border_width_left   = 0
	style.border_width_right  = 1
	style.border_width_bottom = 0
	algo_panels[algo].add_theme_stylebox_override("panel", style)

func _set_panel_style(
	node: Control,
	bg: Color, border: Color,
	border_all: int, border_bottom_only: int,
	radius: int
) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
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
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#070d09")
	style.border_color = C_BORDER
	style.set_border_width_all(1)
	spinbox.get_line_edit().add_theme_stylebox_override("normal", style)
	spinbox.get_line_edit().add_theme_stylebox_override("focus",  style)
	spinbox.get_line_edit().add_theme_color_override("font_color", C_TEXT)
	spinbox.get_line_edit().add_theme_font_size_override("font_size", 13)

func _style_separator(sep: Control) -> void:
	var style := StyleBoxLine.new()
	style.color     = C_BORDER
	style.thickness = 1
	if sep is HSeparator:
		sep.add_theme_stylebox_override("separator", style)
	elif sep is VSeparator:
		sep.add_theme_stylebox_override("separator", style)

func _style_start_btn() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
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
	disabled_style.bg_color = Color(0, 0, 0, 0)
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
		# Clicking the whole panel selects the algorithm
		algo_panels[algo].gui_input.connect(_on_algo_panel_input.bind(algo))
		# Any spinbox change triggers a live stats refresh
		waiters_spin[algo].value_changed.connect(_on_input_changed)
		chefs_spin[algo].value_changed.connect(_on_input_changed)

	start_btn.pressed.connect(_on_start_round_pressed)

func _on_algo_panel_input(event: InputEvent, algo: String) -> void:
	if event is InputEventMouseButton \
	and event.pressed \
	and event.button_index == MOUSE_BUTTON_LEFT:
		_select_algo(algo)

func _on_input_changed(_value: float) -> void:
	_refresh_stats()

func _on_start_round_pressed() -> void:
	# --- Stub ---
	# Replace the body of this function with:
	#   OSManager.start_round(current_algo, get_allocated_waiters(), get_allocated_chefs())
	# when OSManager is ready.  Everything below is placeholder simulation only.
	_round_num += 1
	round_label.text = "ROUND %02d" % _round_num

	var w := get_allocated_waiters()
	var c := get_allocated_chefs()
	var cost = ALGO_COSTS.get(current_algo, 0)
	stamina = max(0, stamina - cost * (w + c))

	var newly_serviced = min(unserviced, w)
	serviced   += newly_serviced
	unserviced  = max(0, unserviced - newly_serviced)

	# Reset inputs for next round
	for algo in waiters_spin.keys():
		waiters_spin[algo].value = 0
		chefs_spin[algo].value   = 0

	_refresh_stats()

# ---------------------------------------------------------------------------
# Selection logic
# ---------------------------------------------------------------------------
func _select_algo(algo: String) -> void:
	current_algo = algo
	for a in algo_panels.keys():
		var is_selected = (a == algo)
		_style_algo_panel(a, is_selected)
		algo_name_labels[a].add_theme_color_override(
			"font_color",
			C_ACCENT if is_selected else C_MUTED
		)
		# Dim + lock inputs on unselected panels
		waiters_spin[a].editable  = is_selected
		chefs_spin[a].editable    = is_selected
		waiters_spin[a].modulate.a = 1.0 if is_selected else 0.35
		chefs_spin[a].modulate.a   = 1.0 if is_selected else 0.35
	_refresh_stats()

# ---------------------------------------------------------------------------
# Live stats refresh  (called on every input change and on algo switch)
# ---------------------------------------------------------------------------
func _refresh_stats() -> void:
	var total_w := 0
	var total_c := 0
	for algo in waiters_spin.keys():
		total_w += int(waiters_spin[algo].value)
		total_c += int(chefs_spin[algo].value)

	var cost      = ALGO_COSTS.get(current_algo, 0)
	var spent     = min(stamina, (total_w + total_c) * cost)
	var remaining = max(0, stamina - spent)

	waiters_val.text    = str(total_w)
	chefs_val.text      = str(total_c)
	stamina_val.text    = str(remaining)
	serviced_val.text   = str(serviced)
	unserviced_val.text = str(unserviced)

	# Stamina color reflects urgency
	var sta_color: Color
	if remaining < 25:
		sta_color = C_DANGER
	elif remaining < 55:
		sta_color = C_WARN
	else:
		sta_color = C_ACCENT
	stamina_val.add_theme_color_override("font_color", sta_color)

	# Disable Start Round if nothing is allocated
	start_btn.disabled = (total_w == 0 and total_c == 0)

# ---------------------------------------------------------------------------
# Public API  — OSManager calls these to push/pull data
# ---------------------------------------------------------------------------

## Called by OSManager at the start of each new round to sync state.
func sync_from_manager(new_stamina: int, new_unserviced: int, new_serviced: int, round: int) -> void:
	stamina    = new_stamina
	unserviced = new_unserviced
	serviced   = new_serviced
	_round_num = round
	round_label.text = "ROUND %02d" % _round_num
	_refresh_stats()

## Returns which algorithm the player has selected.
func get_selected_algo() -> String:
	return current_algo

## Returns the waiter count allocated under the active algorithm.
func get_allocated_waiters() -> int:
	return int(waiters_spin[current_algo].value)

## Returns the chef count allocated under the active algorithm.
func get_allocated_chefs() -> int:
	return int(chefs_spin[current_algo].value)
