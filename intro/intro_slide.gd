@tool
class_name IntroSlide
extends Resource
## UNA DIAPOSITIVA de la introducción (historia). Se edita en el Inspector, dentro de IntroSequence → Slides.
## La imagen de fondo se queda fija mientras pasan los textos de "Texts" (cada elemento = un cuadro de texto; se pasa con Aceptar).

@export_group("Texto")
@export_multiline var texts: PackedStringArray = []   ## Cada elemento es un cuadro de texto que se escribe letra a letra
@export_enum("Abajo", "Centro", "Arriba") var text_position: int = 0
@export_enum("Centrado", "Izquierda") var text_align: int = 0
@export var text_color: Color = Color.WHITE
@export_range(10, 80) var font_size: int = 28
@export_range(5.0, 200.0) var type_speed: float = 35.0   ## letras por segundo
@export var auto_advance: float = 0.0   ## segundos de espera tras escribir el texto para pasar solo. 0 = espera a que pulses Aceptar

@export_group("Fondo")
@export var background: Texture2D   ## imagen de fondo (vacío = solo el color)
@export var bg_color: Color = Color.BLACK
@export_enum("Cubrir pantalla", "Entera", "Tamaño original") var fit: int = 0
@export_range(0.5, 2.0) var zoom_to: float = 1.08   ## zoom lento hasta este valor (1 = quieto)
@export var pan: Vector2 = Vector2.ZERO   ## desplazamiento lento (px) durante la diapositiva
@export var drift_seconds: float = 20.0   ## cuánto dura ese zoom / desplazamiento
@export_range(0.0, 1.0) var darken: float = 0.35   ## oscurece el fondo para que se lea el texto

@export_group("Transiciones")
@export var fade_in: float = 1.0   ## segundos aclarando desde negro al empezar
@export var fade_out: float = 0.8  ## segundos oscureciendo hasta negro al acabar

@export_group("Sonido")
@export var music: AudioStream   ## música que empieza con esta diapositiva (vacío = sigue la que suena)
