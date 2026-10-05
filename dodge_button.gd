class_name DodgeButton
extends HBoxContainer
## BOTÓN DE ESQUIVA de un hermano (ui/dodge_button.tscn): se ve durante el ataque enemigo, con su tecla y su color, y se encoge al pulsarlo.
## "Circle" (PanelContainer) es el botón: cambia su estilo o ponle una imagen dentro. "Key" muestra la tecla y "Hint" el texto.

@export var pressed_scale: float = 0.85
@export var use_hero_color: bool = true   ## pinta el botón del color de la camisa del hermano

var _circle: Control
var _key: Label

func _ready() -> void:
	_circle = find_child("Circle", true, false) as Control
	_key = find_child("Key", true, false) as Label

var _hint: Label
var _hint_default := ""
var _icon: Control   ## símbolo del martillo (se dibuja por código) junto al texto, solo en la esquiva con martillo
@export var hammer_hint: String = "Martillo"   ## texto cuando el ataque se esquiva con martillo (mantener y soltar)

## kind: &"jump" (saltar, lo normal) o &"hammer" (martillo: se ve el símbolo de un martillo y el texto cambia).
func set_kind(kind: StringName) -> void:
	if _hint == null:
		_hint = find_child("Hint", true, false) as Label
		if _hint:
			_hint_default = _hint.text
	var hammer := kind == &"hammer"
	if _icon == null and hammer:
		_icon = Control.new()
		_icon.custom_minimum_size = Vector2(34, 34)
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon.draw.connect(_draw_hammer_icon)
		add_child(_icon)
		move_child(_icon, 1)   # entre el botón y el texto
	if _icon:
		_icon.visible = hammer
	if _hint:
		_hint.text = hammer_hint if hammer else _hint_default

func _draw_hammer_icon() -> void:
	var c := Vector2(17, 17)
	var xf := Transform2D(-0.6, c)   # inclinado, como un martillo en reposo
	_icon.draw_set_transform_matrix(xf)
	_icon.draw_rect(Rect2(-3, -4, 6, 20), Color("8a5a2b"))               # mango
	_icon.draw_rect(Rect2(-3, -4, 6, 20), Color("3a2410"), false, 1.5)
	_icon.draw_rect(Rect2(-13, -15, 26, 12), Color("b8c0ca"))            # cabeza
	_icon.draw_rect(Rect2(-13, -15, 26, 12), Color("2e3640"), false, 2.0)
	_icon.draw_set_transform_matrix(Transform2D.IDENTITY)

func show_hero(h: BattleHero, key_text: String) -> void:
	if _key:
		_key.text = key_text
	if _circle:
		_circle.pivot_offset = _circle.size / 2.0
		_circle.scale = Vector2.ONE * (pressed_scale if Input.is_action_pressed(h.action()) else 1.0)
		if use_hero_color:
			_circle.self_modulate = h.stats.shirt_color if h.alive else h.stats.shirt_color.darkened(0.6)
	modulate.a = 1.0 if h.alive else 0.4
