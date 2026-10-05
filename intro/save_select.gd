extends Control
## ELEGIR FICHERO: 4 ficheros de guardado. Vacío → Nueva partida. Con datos → Continuar / Borrar.
## Nueva partida empieza en "Start Scene" (por ahora test_zone.tscn) y crea el fichero con los datos iniciales.

signal _answered

@export_file("*.tscn") var start_scene: String = "res://overworld/test_zone.tscn"   ## dónde empieza una partida nueva
@export_file("*.tscn") var back_scene: String = "res://intro/title_screen.tscn"
@export var title_text: String = "Elige un fichero"
@export var empty_text: String = "— Vacío —"
@export var font: Font
@export_range(16, 48) var font_size: int = 26
@export var bg_top: Color = Color(0.03, 0.04, 0.14)
@export var bg_bottom: Color = Color(0.16, 0.08, 0.3)
@export var fade_time: float = 0.6
@export_group("Música")
@export var music: AudioStream   ## música de este menú (vacío = silencio)
@export_range(-40.0, 6.0) var music_volume_db: float = -6.0
@export var loop_music: bool = true

var _list: VBoxContainer
var _slots: Array[Button] = []
var _modal: Control
var _answer := -1
var _opts := 0
var _busy := false

func _ready() -> void:
	SaveSlots.start_scene = start_scene
	IntroUI.full_rect(self)
	var g := Gradient.new()
	g.set_color(0, bg_top)
	g.set_color(1, bg_bottom)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var bg := TextureRect.new()
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	IntroUI.full_rect(bg)
	add_child(bg)
	var center := CenterContainer.new()
	IntroUI.full_rect(center)
	add_child(center)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 14)
	center.add_child(_list)
	_list.add_child(IntroUI.label(title_text, font_size + 14, Color.WHITE, font))
	for i in SaveSlots.COUNT:
		var b := _slot_button(i)
		_list.add_child(b)
		_slots.append(b)
	var hint := IntroUI.label("↑↓ elegir   ·   Z / Enter aceptar   ·   C volver", 14, Color(1, 1, 1, 0.5))
	_list.add_child(hint)
	_refresh()
	if music != null:
		var mp := AudioStreamPlayer.new()
		mp.stream = music
		mp.volume_db = music_volume_db
		add_child(mp)
		if loop_music:
			IntroUI.loop(mp)
		mp.play()
	_slots[0].call_deferred("grab_focus")

func _slot_button(i: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(780, 92)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", font_size)
	if font != null:
		b.add_theme_font_override("font", font)
	b.add_theme_color_override("font_color", Color(0.88, 0.9, 1.0))
	b.add_theme_color_override("font_focus_color", IntroUI.GOLD)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	for st in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.08, 0.1, 0.24, 0.88)
		s.border_color = IntroUI.GOLD if st == "focus" else Color(0.35, 0.4, 0.7)
		s.set_border_width_all(3 if st == "focus" else 2)
		s.set_corner_radius_all(10)
		s.content_margin_left = 28
		s.content_margin_right = 28
		b.add_theme_stylebox_override(st, s)
	b.pressed.connect(_on_slot.bind(i))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE   # solo teclado
	return b

func _refresh() -> void:
	for i in SaveSlots.COUNT:
		var head := "Fichero %d" % (i + 1)
		var sm := SaveSlots.summary(i)
		_slots[i].text = "%s\n%s" % [head, empty_text if sm.is_empty() else sm]

func _on_slot(i: int) -> void:
	if _busy:
		return
	_busy = true
	if not SaveSlots.exists(i):
		if await _ask("Fichero %d" % (i + 1), PackedStringArray(["Nueva partida", "Cancelar"])) == 0:
			SaveSlots.begin(get_tree(), i, true, fade_time)
			return
	else:
		var r := await _ask("Fichero %d" % (i + 1), PackedStringArray(["Continuar", "Borrar", "Cancelar"]))
		if r == 0:
			SaveSlots.begin(get_tree(), i, false, fade_time)
			return
		if r == 1 and await _ask("¿Borrar el fichero %d?" % (i + 1), PackedStringArray(["No", "Sí, borrar"])) == 1:
			SaveSlots.erase(i)
			_refresh()
	_busy = false
	_slots[i].grab_focus()

## Pregunta con botones; devuelve el índice elegido (Esc = la última opción).
func _ask(text: String, options: PackedStringArray) -> int:
	_opts = options.size()
	_modal = ColorRect.new()
	(_modal as ColorRect).color = Color(0, 0, 0, 0.72)
	IntroUI.full_rect(_modal)
	add_child(_modal)
	var center := CenterContainer.new()
	IntroUI.full_rect(center)
	_modal.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	box.add_child(IntroUI.label(text, font_size + 4, Color.WHITE, font))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var first: Button = null
	for k in options.size():
		var b := IntroUI.button(options[k], font_size, font)
		b.custom_minimum_size = Vector2(200, 52)
		b.pressed.connect(func() -> void:
			_answer = k
			_answered.emit())
		row.add_child(b)
		if first == null:
			first = b
	for s in _slots:
		s.focus_mode = Control.FOCUS_NONE
	first.call_deferred("grab_focus")
	_answer = -1
	await _answered
	var r := _answer
	_modal.queue_free()
	_modal = null
	for s in _slots:
		s.focus_mode = Control.FOCUS_ALL
	return r

func _unhandled_input(e: InputEvent) -> void:
	if IntroUI.press_focused(self, e):   # Z / X aceptan
		return
	if not IntroUI.cancel(e):   # C / Esc vuelven
		return
	get_viewport().set_input_as_handled()
	if _modal != null:
		_answer = _opts - 1   # última opción (Cancelar / No)
		_answered.emit()
	elif not _busy:
		_busy = true
		ScreenFade.go(get_tree(), back_scene, fade_time)
