extends Control
## CONFIGURACIÓN (por ahora vacía: aquí irán las opciones que me digas). Esc o "Volver" regresan al título.

@export_file("*.tscn") var back_scene: String = "res://intro/title_screen.tscn"
@export var title_text: String = "Configuración"
@export_multiline var placeholder_text: String = "(Próximamente)"
@export var back_text: String = "Volver"
@export var font: Font
@export var bg_top: Color = Color(0.03, 0.04, 0.14)
@export var bg_bottom: Color = Color(0.16, 0.08, 0.3)
@export var fade_time: float = 0.6

var _busy := false

func _ready() -> void:
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
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 40)
	center.add_child(col)
	col.add_child(IntroUI.label(title_text, 52, Color.WHITE, font))
	col.add_child(IntroUI.label(placeholder_text, 26, Color(1, 1, 1, 0.6), font))
	var back := IntroUI.button(back_text, 30, font)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_back)
	col.add_child(back)
	back.call_deferred("grab_focus")

func _unhandled_input(e: InputEvent) -> void:
	if IntroUI.press_focused(self, e):
		return
	if IntroUI.cancel(e):
		_back()

func _back() -> void:
	if _busy:
		return
	_busy = true
	ScreenFade.go(get_tree(), back_scene, fade_time)
