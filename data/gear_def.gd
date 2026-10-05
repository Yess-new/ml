class_name GearDef
extends Resource
## Una pieza de EQUIPO (zapatos, martillo, camisa...). Crea una nueva con clic derecho en data/gear/ → Nuevo recurso → GearDef,
## y aparece sola en el menú y en la bolsa (GameState.gear_bag decide quién la tiene al empezar).

@export var id: StringName = &""                    ## identificador único (sin espacios): el que usa GameState.gear_bag
@export var display_name: String = "Pieza"
@export var slot: StringName = &"boots"             ## ranura: debe coincidir con el id de una de las ranuras del menú (PauseMenu → Gear Slots)
@export var power: int = 0                           ## suma a la FUERZA del que la lleva
@export var defense: int = 0                         ## suma a la DEFENSA del que la lleva
@export_multiline var description: String = ""
@export var icon: Texture2D                          ## icono propio (opcional)
