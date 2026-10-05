class_name IntroUI
extends RefCounted
## Pequeñas ayudas para los menús de inicio (botones con el mismo estilo).

const GOLD := Color(1.0, 0.86, 0.3)

static func button(text: String, size: int = 30, font: Font = null) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(320, 56)
	b.add_theme_font_size_override("font_size", size)
	if font != null:
		b.add_theme_font_override("font", font)
	b.add_theme_color_override("font_color", Color(0.85, 0.87, 0.95))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_color_override("font_pressed_color", GOLD)
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(s, empty)
	var f := StyleBoxFlat.new()
	f.bg_color = Color(1, 1, 1, 0.08)
	f.border_color = GOLD
	f.border_width_left = 4
	f.border_width_right = 4
	f.set_corner_radius_all(6)
	b.add_theme_stylebox_override("focus", f)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE   # los menús se controlan SOLO con el teclado
	return b

## ¿Se pulsó una tecla de aceptar? Z (Mario), X (Luigi), Enter (menu) o Espacio.
static func confirm(e: InputEvent) -> bool:
	if not e.is_pressed() or e.is_echo():
		return false
	for a in [&"jump_mario", &"jump_luigi", &"menu", &"ui_accept"]:
		if InputMap.has_action(a) and e.is_action_pressed(a):
			return true
	return false

## ¿Se pulsó una tecla de volver? C (cancel) o Esc.
static func cancel(e: InputEvent) -> bool:
	if not e.is_pressed() or e.is_echo():
		return false
	for a in [&"cancel", &"ui_cancel"]:
		if InputMap.has_action(a) and e.is_action_pressed(a):
			return true
	return false

## Pulsa el botón que tiene el foco. Úsalo para Z y X (Enter y Espacio ya los entiende el botón solo).
static func press_focused(node: Node, e: InputEvent) -> bool:
	if not (e.is_action_pressed(&"jump_mario") or e.is_action_pressed(&"jump_luigi")):
		return false
	var b := node.get_viewport().gui_get_focus_owner() as Button
	if b == null:
		return false
	node.get_viewport().set_input_as_handled()
	b.pressed.emit()
	return true

static func label(text: String, size: int, color: Color = Color.WHITE, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(2, floori(size / 8.0)))
	if font != null:
		l.add_theme_font_override("font", font)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

## Hace que la música de un reproductor se repita sin fin (pone el loop del propio audio si lo tiene, y si no, la vuelve a empezar al acabar).
## Llámalo después de poner el stream y antes de play().
static func loop(p: AudioStreamPlayer) -> void:
	if p == null or p.stream == null:
		return
	if "loop" in p.stream:   # OGG / MP3
		p.stream = p.stream.duplicate()
		p.stream.set("loop", true)
	if not p.finished.is_connected(p.play):   # WAV y demás: al acabar, otra vez
		p.finished.connect(p.play)

static func full_rect(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
