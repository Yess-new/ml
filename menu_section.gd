class_name MenuSection
extends Resource
## Un APARTADO de la columna izquierda del menú de pausa (PauseMenu → Sections). Reordena el array para reordenar el menú,
## desactiva uno con Enabled, o cambia su nombre, descripción e icono.

## Qué contenido tiene: Objetos (consumibles, listones, clave), Equipo, Medallas, Estado o Mapa.
@export_enum("items", "gear", "badges", "stats", "map") var kind: String = "items"
@export var display_name: String = "Apartado"
@export_multiline var description: String = ""      ## lo que sale abajo al estar el cursor sobre el apartado
@export var icon: Texture2D                           ## icono propio (si no, se dibuja el provisional)
@export var enabled: bool = true
