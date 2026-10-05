class_name HeroCard
extends Panel
## TARJETA de un hermano en combate (ui/hero_card.tscn): nombre, PV y PT. Es un Panel (no un contenedor), así que sus
## textos Name, HP y TP se mueven y redimensionan LIBREMENTE en el editor. Cambia su estilo (Theme Overrides > Styles > Panel),
## fuentes y colores; puedes añadir un retrato (TextureRect) u otros nodos: el script solo usa Name, HP y TP (búscalos por nombre,
## pueden estar donde quieras dentro de la tarjeta). Si no quieres el recuadro, pon un StyleBoxEmpty en el Panel.

@export var low_hp_color: Color = Color("ff6b6b")   ## color de los PV cuando quedan pocos (≤ 40 %)
@export var active_color: Color = Color("ffe14d")   ## color del nombre cuando es su turno

var _name_label: Label
var _hp_label: Label
var _tp_label: Label
var _hp_color := Color.WHITE
var _name_color := Color.WHITE

func _ready() -> void:
	_name_label = find_child("Name", true, false) as Label
	_hp_label = find_child("HP", true, false) as Label
	_tp_label = find_child("TP", true, false) as Label
	if _hp_label:
		_hp_color = _hp_label.get_theme_color("font_color")
	if _name_label:
		_name_color = _name_label.get_theme_color("font_color")

func show_hero(h: BattleHero, active: bool) -> void:
	if _name_label:
		_name_label.text = h.display_name
		_name_label.add_theme_color_override("font_color", active_color if active else _name_color)
	if _hp_label:
		_hp_label.text = "PV %d / %d" % [h.hp, h.max_hp]
		_hp_label.add_theme_color_override("font_color", low_hp_color if h.hp <= h.max_hp * 0.4 else _hp_color)
	if _tp_label:
		_tp_label.text = "PT %d / %d" % [h.tp, h.max_tp]
	modulate.a = 1.0 if h.alive else 0.45
