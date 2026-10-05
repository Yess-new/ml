@tool
class_name RankBadge
extends Control
## UNA CELEBRACIÓN (OK! / GOOD! / GREAT! / EXCELLENT!). En ui/battle_ui.tscn hay un nodo "Celebrations" con 4 de estos, EN ORDEN de peor a mejor:
## Ok, Good, Great, Excellent. Cada uno sale en pantalla justo donde lo coloques en el editor (muévelo/redimensiónalo como quieras).
##
## PARA PONER TU PROPIO SPRITE: selecciona el nodo y arrastra tu imagen al campo "Texture" del Inspector (se escala para llenar el
## nodo: agranda o encoge el nodo para cambiar su tamaño). Sin textura se ve el texto provisional, con su color y tamaño.
## Se anima solo: entra grande y se asienta, se queda un rato (Combate/hit_fx_default.tres → Rank Frames) y se desvanece.

@export var texture: Texture2D:
	set(v):
		texture = v
		_refresh()
@export var text: String = "OK!":
	set(v):
		text = v
		_refresh()
@export var text_color: Color = Color(0.55, 0.9, 1.0):
	set(v):
		text_color = v
		_refresh()
@export var outline_color: Color = Color(0.12, 0.05, 0.0):
	set(v):
		outline_color = v
		_refresh()
@export var font_size: int = 40:
	set(v):
		font_size = v
		_refresh()
@export var tilt_degrees: float = -7.0   ## inclinación del cartel
@export var pop_scale: float = 0.5       ## cuánto más grande empieza al aparecer (0 = sin rebote)

var _sprite: TextureRect
var _label: Label

func _ready() -> void:
	_build()
	_refresh()
	if not Engine.is_editor_hint():
		visible = false   # en el juego solo se ve cuando toca; en el editor se ve para que lo coloques
	else:
		rotation_degrees = tilt_degrees

func _build() -> void:
	if _sprite == null:
		_sprite = TextureRect.new()
		_sprite.name = "Sprite"
		_sprite.set_anchors_preset(Control.PRESET_FULL_RECT)
		_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_sprite)   # sin owner: no se guarda en la escena, se crea al abrirla
	if _label == null:
		_label = Label.new()
		_label.name = "Label"
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.add_theme_constant_override("outline_size", 12)
		add_child(_label)

func _refresh() -> void:
	if _sprite == null or _label == null:
		return
	_sprite.texture = texture
	_sprite.visible = texture != null
	_label.visible = texture == null
	_label.text = text
	_label.add_theme_color_override("font_color", text_color)
	_label.add_theme_color_override("font_outline_color", outline_color)
	_label.add_theme_font_size_override("font_size", font_size)

## La anima el BattleUI: t = fotogramas desde que salió, life = lo que dura en total.
func play(t: int, life: int) -> void:
	pivot_offset = size * 0.5
	rotation_degrees = tilt_degrees
	scale = Vector2.ONE * (1.0 + pop_scale * maxf(0.0, 1.0 - float(t) / 8.0))
	var k := float(t) / float(maxi(1, life))
	modulate.a = 1.0 - maxf(0.0, (k - 0.7) / 0.3)
