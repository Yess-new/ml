class_name DamageNumber
extends Node2D
## Número / texto flotante del combate (-5, +10 PV, ¡Crítico!...). ESCENA: Combate/damage_number.tscn
## Cambia la fuente, el tamaño o el contorno en su nodo "Text" (Label). Sube despacio y desaparece solo.

@export var life := 50          ## fotogramas que dura
@export var rise_speed := 0.5   ## px por fotograma que sube

var _max_life := 50

func setup(text: String, color: Color) -> void:
	var l := get_node_or_null("Text") as Label
	if l:
		l.text = text
		l.add_theme_color_override("font_color", color)

func _ready() -> void:
	_max_life = life
	z_index = 100

func _physics_process(_delta: float) -> void:
	life -= 1
	position.y -= rise_speed
	modulate.a = clampf(float(life) / _max_life * 2.0, 0.0, 1.0)
	if life <= 0:
		queue_free()
