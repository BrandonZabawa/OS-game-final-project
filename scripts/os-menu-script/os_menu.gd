# =============================================================================
# os_menu.gd
# Attach to: OSMenuScreen (Control node) in os_menu.tscn
# =============================================================================
# PURPOSE: Player allocation UI for each round.
#
# LAYOUT (two columns, matching the old FIFO/SJF/SJCF structure):
#
#   ┌─────────────────────────────────────────────┐
#   │  KITCHEN OS  ·  ROUND 01  ·  ♥♥♥  SCORE: 0 │
#   ├──────────────────┬──────────────────────────┤
#   │     CHEFS        │        WAITERS            │
#   │  Cook   [ 0 ↕ ]  │  Plate 1  [ 0 ↕ ]        │
#   │  Prep   [ 0 ↕ ]  │  Plate 2  [ 0 ↕ ]        │
#   │                  │  Plate 3  [ 0 ↕ ]        │
#   ├──────────────────┴──────────────────────────┤
#   │              [ START ROUND ]                 │
#   └─────────────────────────────────────────────┘
#
# SCENE SETUP (nodes you must create in os_menu.tscn — exact names matter):
#   Control (root)
#   └─ CenterContainer
#      └─ OSWindow (PanelContainer)
#         └─ OSVBox (VBoxContainer)
#            ├─ TitleBar (PanelContainer)
#            │  └─ TitleHBox (HBoxContainer)
#            │     ├─ TitleLabel (Label)
#            │     ├─ RoundLabel (Label) — unique name %RoundLabel
#            │     ├─ HPLabel (Label)    — unique name %HPLabel
#            │     └─ ScoreLabel (Label) — unique name %ScoreLabel
#            ├─ TitleSep (HSeparator)
#            ├─ BodyRow (HBoxContainer)
#            │  ├─ ChefsPanel (PanelContainer)
#            │  │  └─ ChefsVBox (VBoxContainer)
#            │  │     ├─ ChefsHeader (Label)
#            │  │     ├─ CookRow (HBoxContainer)
#            │  │     │  ├─ CookLabel (Label)
#            │  │     │  └─ CookSpin (SpinBox) — unique %CookSpin
#            │  │     └─ PrepRow (HBoxContainer)
#            │  │        ├─ PrepLabel (Label)
#            │  │        └─ PrepSpin (SpinBox) — unique %PrepSpin
#            │  ├─ VSep1 (VSeparator)
#            │  └─ WaitersPanel (PanelContainer)
#            │     └─ WaitersVBox (VBoxContainer)
#            │        ├─ WaitersHeader (Label)
#            │        ├─ Plate1Row (HBoxContainer)
#            │        │  ├─ Plate1Label (Label)
#            │        │  └─ Plate1Spin (SpinBox) — unique %Plate1Spin
#            │        ├─ Plate2Row (HBoxContainer)
#            │        │  ├─ Plate2Label (Label)
#            │        │  └─ Plate2Spin (SpinBox) — unique %Plate2Spin
#            │        └─ Plate3Row (HBoxContainer)
#            │           ├─ Plate3Label (Label)
#            │           └─ Plate3Spin (SpinBox) — unique %Plate3Spin
#            ├─ FooterSep (HSeparator)
#            └─ StartRoundBtn (Button) — unique %StartRoundBtn
# =============================================================================

extends Control

# ---------------------------------------------------------------------------
# Color palette (terminal dark theme)
# ---------------------------------------------------------------------------

const C_BG      := Color("#0a0c0f")
const C_PANEL   := Color("#0f1318")
const C_BORDER  := Color("#1e3a2f")
const C_ACCENT  := Color("#00ff88")
const C_WARN    := Color("#ffb300")
const C_DANGER  := Color("#ff4444")
const C_TEXT    := Color("#c8ffd4")
const C_MUTED   := Color("#4a7a5a")
const C_HEADER  := Color("#071a10")

# ---------------------------------------------------------------------------
# Node references (unique names — set up these nodes in the .tscn editor)
# ---------------------------------------------------------------------------

@onready var round_label : Label  = %RoundLabel
@onready var hp_label    : Label  = %HPLabel
@onready var score_label : Label  = %ScoreLabel

@onready var cook_spin   : SpinBox = %CookSpin
@onready var prep_spin   : SpinBox = %PrepSpin
@onready var plate1_spin : SpinBox = %Plate1Spin
@onready var plate2_spin : SpinBox = %Plate2Spin
@onready var plate3_spin : SpinBox = %Plate3Spin

@onready var start_btn   : Button  = %StartRoundBtn

# Panel/separator style targets (full paths from root — adjust if hierarchy differs)
@onready var os_window   : PanelContainer = $CenterContainer/OSWindow
@onready var title_bar   : PanelContainer = $CenterContainer/OSWindow/OSVBox/TitleBar
@onready var title_sep   : HSeparator     = $CenterContainer/OSWindow/OSVBox/TitleSep
@onready var footer_sep  : HSeparator     = $CenterContainer/OSWindow/OSVBox/FooterSep
@onready var vsep1       : VSeparator     = $CenterContainer/OSWindow/OSVBox/BodyRow/VSep1

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_apply_theme()
	_connect_signals()
	_refresh_display()


# ---------------------------------------------------------------------------
# Signal wiring
# ---------------------------------------------------------------------------

func _connect_signals() -> void:
	start_btn.pressed.connect(_on_start_round_pressed)

	for spin in [cook_spin, prep_spin, plate1_spin, plate2_spin, plate3_spin]:
		spin.value_changed.connect(_on_spin_changed)


func _on_spin_changed(_v: float) -> void:
	_refresh_display()


func _on_start_round_pressed() -> void:
	var cook  := int(cook_spin.value)
	var prep  := int(prep_spin.value)
	var p1    := int(plate1_spin.value)
	var p2    := int(plate2_spin.value)
	var p3    := int(plate3_spin.value)

	# Disable button so the player can't double-fire during NPC animation
	start_btn.disabled = true

	# Kick off the round — RoundManager is an AutoLoad singleton
	await RoundManager.execute_round(cook, prep, p1, p2, p3)

	# Round complete — reset spinboxes and re-enable for next allocation
	_reset_spins()
	_refresh_display()
	start_btn.disabled = false


# ---------------------------------------------------------------------------
# Display refresh
# ---------------------------------------------------------------------------

func _refresh_display() -> void:
	round_label.text = "ROUND %02d" % GameConfig.current_round
	hp_label.text    = "HP: %d / %d" % [GameConfig.player_hp, GameConfig.MAX_HP]
	score_label.text = "SCORE: %d"   % GameConfig.score

	# Color HP label by urgency
	var hp_color : Color
	match GameConfig.player_hp:
		3:     hp_color = C_ACCENT
		2:     hp_color = C_WARN
		_:     hp_color = C_DANGER
	hp_label.add_theme_color_override("font_color", hp_color)

	# Disable Start if nothing is allocated
	var any_alloc := (cook_spin.value + prep_spin.value
		+ plate1_spin.value + plate2_spin.value + plate3_spin.value) > 0
	start_btn.disabled = not any_alloc or RoundManager.is_round_active()


func _reset_spins() -> void:
	for spin in [cook_spin, prep_spin, plate1_spin, plate2_spin, plate3_spin]:
		spin.value = 0

# ---------------------------------------------------------------------------
# Public API — called by kitchen_scene when RoundManager signals hp_changed
# ---------------------------------------------------------------------------

func update_hp_display(new_hp: int) -> void:
	GameConfig.player_hp = new_hp
	_refresh_display()

# ---------------------------------------------------------------------------
# Theme
# ---------------------------------------------------------------------------

func _apply_theme() -> void:
	_style_panel(os_window, C_PANEL,  C_BORDER, 1, 0, 4)
	_style_panel(title_bar, C_HEADER, C_BORDER, 0, 1, 0)

	_style_sep(title_sep)
	_style_sep(footer_sep)
	_style_sep(vsep1)

	_style_label(round_label, C_MUTED,  10)
	_style_label(hp_label,    C_ACCENT, 12)
	_style_label(score_label, C_ACCENT, 12)

	for spin in [cook_spin, prep_spin, plate1_spin, plate2_spin, plate3_spin]:
		_style_spinbox(spin)

	_style_start_btn()


func _style_panel(node: Control, bg: Color, border: Color,
				  all_w: int, bottom_w: int, radius: int) -> void:
	var s         := StyleBoxFlat.new()
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
	var s         := StyleBoxFlat.new()
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
	var s      := StyleBoxLine.new()
	s.color     = C_BORDER
	s.thickness = 1
	var key := "separator"
	sep.add_theme_stylebox_override(key, s)


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
