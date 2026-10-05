class_name EnemyData
extends Resource
## ESTADÍSTICAS de un tipo de enemigo (equivale a ENEMY_TYPES del prototipo HTML). Un .tres por enemigo en Combate/enemigos/,
## editable desde el Inspector. Mismas estadísticas que los héroes: power (fuerza), defense, turn_speed (orden de turno), stache (crítico %).
## Su ASPECTO (sprites, tamaño) está en su escena de combate (p. ej. goomba_battle.tscn), que apunta a este .tres.

@export var display_name: String = "Goomba"
@export var max_hp: int = 30
@export var power: int = 9
@export var defense: int = 0
@export var turn_speed: int = 3
@export var stache: int = 3
@export_group("Recompensas")
@export var coin_reward: int = 3
@export var exp_reward: int = 2
@export var drops: Dictionary = {"mushroom": 0.18, "syrup": 0.12}   ## id de objeto -> probabilidad de soltarlo (0..1)
@export_group("Diálogos")
# (se muestran en combate: ver BattleDialogue)
@export var dialogues: Array[BattleDialogue] = []   ## lo que dice en combate (al empezar, con poca vida, al ser derrotado...). Ver BattleDialogue
@export_group("Combate")
@export var pattern: GDScript                    ## script de su ataque (Combate/patrones/*.gd). Vacío = embestida (lunge)
@export var spiked: bool = false                 ## pinchos: saltarle encima hiere al héroe; solo el martillo le hace daño
