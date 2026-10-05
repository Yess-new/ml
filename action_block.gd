@tool
class_name ActionBlock
extends PanelContainer
## UN BLOQUE de acción del menú de combate (ui/action_block.tscn). En battle_ui.tscn hay uno por acción dentro de ActionMenu/Blocks:
## el ORDEN de los bloques es el orden del menú (reordénalos en el árbol), y "Action Id" dice qué hace cada uno:
##   item (Objeto) · flee (Huir) · jump (Salto) · hammer (Martillo)
## Pon tu imagen en "Icon"; si no hay, se ve la primera letra del nombre.

@export var action_id: StringName = &"jump"
@export var display_name: String = "Salto":
	set(v):
		display_name = v
		_apply()
@export var icon: Texture2D:
	set(v):
		icon = v
		_apply()
@export var color: Color = Color("ff5a4a"):   ## color de fondo del bloque
	set(v):
		color = v
		_apply()
@export var selected_scale: float = 1.3       ## tamaño del bloque elegido
@export var unselected_tint: Color = Color(0.6, 0.6, 0.6, 0.85)

func _ready() -> void:
	_apply()

func _apply() -> void:
	if not is_inside_tree():
		return
	var icon_rect := get_node_or_null("Icon") as TextureRect
	var letter := get_node_or_null("Letter") as Label
	if icon_rect:
		icon_rect.texture = icon
	if letter:
		letter.text = display_name.substr(0, 1) if icon == null else ""
	var sb := get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		var s := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
		s.bg_color = color
		add_theme_stylebox_override("panel", s)

var _rest_y := NAN      ## posición Y de reposo que le da el contenedor
var _bump_applied := 0.0

## Empuja el bloque hacia arriba px píxeles (el golpe del héroe). El contenedor lo recoloca si cambia el diseño:
## lo detectamos comparando con lo último que pusimos.
func set_bump(px: float) -> void:
	if is_nan(_rest_y) or not is_equal_approx(position.y, _rest_y - _bump_applied):
		_rest_y = position.y
	position.y = _rest_y - px
	_bump_applied = px

## Modo RULETA: depth 1 = delante (grande, brillante), 0 = detrás del todo (pequeño, oscuro). pulse: el saltito del héroe.
func set_wheel(depth: float, pulse: float, back_scale: float, front_scale: float) -> void:
	pivot_offset = size / 2.0
	scale = Vector2.ONE * (lerpf(back_scale, front_scale, depth) + 0.15 * sin(pulse * PI))
	modulate = unselected_tint.lerp(Color.WHITE, depth * depth)
	z_index = roundi(depth * 10.0)

## pulse: 0..1, el saltito del héroe al golpear el bloque.
func set_selected(on: bool, pulse: float = 0.0) -> void:
	pivot_offset = size / 2.0
	scale = Vector2.ONE * ((selected_scale + 0.15 * sin(pulse * PI)) if on else 1.0)
	modulate = Color.WHITE if on else unselected_tint
	z_index = 1 if on else 0
