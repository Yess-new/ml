class_name BadgeDef
extends Resource
## Una MEDALLA. Se equipa gastando puntos de medalla (PM) comunes a los dos hermanos. Crea una nueva en data/badges/.
## El EFECTO se programa donde se use: GameState.has_badge(hero_id, &"id") (p. ej. Doble Filo en el cálculo de daño).

@export var id: StringName = &""
@export var display_name: String = "Medalla"
@export var bp: int = 1                              ## coste en PM
@export_multiline var description: String = ""
@export var color: Color = Color(0.878, 0.278, 0.247)
@export var icon: Texture2D                          ## icono propio (opcional; si no, un círculo de color)
