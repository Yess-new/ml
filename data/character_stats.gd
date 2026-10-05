class_name CharacterStats
extends Resource
## Estadísticas base de un personaje. Se editan en los .tres de data/characters/ desde el inspector (sin tocar código).
## Valores tomados del prototipo HTML (HERO_DEFS).

@export var id: StringName = &"mario"
@export var display_name: String = "Mario"
@export var max_hp: int = 30
@export var max_tp: int = 20
@export var power: int = 10        ## fuerza base (el equipo suma encima)
@export var defense: int = 3       ## defensa base
@export var turn_speed: int = 10   ## velocidad = orden de turno en combate (no la de caminar)
@export var stache: int = 12       ## bigote: probabilidad de crítico (%) y descuento en tiendas (bigote / 2 %)
@export var jump_action: StringName = &"jump_mario"   ## acción del Input Map que hace saltar a este hermano
@export var shirt_color: Color = Color(0.878, 0.278, 0.247, 1)
@export var portrait: Texture2D          ## imagen para el pasaporte del menú (vacío = se dibuja un recuadro de color)
@export var portrait_scale: float = 0.95 ## tamaño de esa imagen respecto al recuadro del pasaporte (1 = llena el recuadro)
@export var portrait_offset: Vector2 = Vector2.ZERO   ## ajuste fino (px del lienzo del menú)
