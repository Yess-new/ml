@tool
class_name IntroSequence
extends Resource
## La HISTORIA de la introducción: una lista de diapositivas (IntroSlide) que se muestran en orden.
## Edítala en el Inspector (abre res://intro/historia_intro.tres) o desde la escena story_intro.tscn → Sequence.

@export var slides: Array[IntroSlide] = []
@export var music: AudioStream   ## música de toda la introducción (opcional)
@export_range(-40.0, 6.0) var music_volume_db: float = -6.0
@export var loop_music: bool = true   ## la música se repite hasta que acaba la introducción
