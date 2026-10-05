class_name MenuStyle
extends Resource
## ASPECTO del menú de pausa: colores, fuente, textos y animación. Se edita en ui/pause_menu_style.tres (o crea otro y arrástralo
## a PauseMenu → Style). Las medidas (en píxeles) son del lienzo de diseño del prototipo (PauseMenu → Design Size).

@export_group("Fuente")
@export var font: Font                                ## vacío = la fuente por defecto de Godot
@export_range(0.5, 2.0, 0.05) var font_scale: float = 1.0   ## multiplica todos los tamaños de letra
@export_group("Marco y fondo")
@export var frame_dark := Color("4a2f18")
@export var frame_wood := Color("8a5a2e")
@export var cloth_base := Color("d6e6cf")
@export var cloth_stripe := Color(0.275, 0.51, 0.314, 0.14)
@export var cloth_checks: bool = true                 ## mantel a cuadros (false = solo rayas)
@export var background_texture: Texture2D             ## si pones una imagen, sustituye al marco de madera y al mantel
@export_group("Paneles")
@export var pill_bg := Color("1c2458")                ## monedas, tiempo y cuadro de descripción
@export var pill_border := Color("e8ecff")
@export var panel_bg := Color("fbf6e6")
@export var panel_border := Color("8a7a50")
@export var select_fill := Color("ffe28a")            ## fila seleccionada
@export var select_fill_dim := Color("e8e2cc")        ## fila seleccionada cuando hay que elegir hermano
@export var cursor_outline := Color("ffb400")         ## borde del apartado seleccionado
@export var cursor_outline_inside := Color("9aa6d6")  ## …y cuando ya estás dentro de él
@export var arrow_fill := Color("ffd23a")
@export var arrow_outline := Color("3b2a00")
@export_group("Texto")
@export var text_dark := Color("2a2140")
@export var text_light := Color.WHITE
@export var text_note := Color("ffe98a")              ## avisos temporales («No te quedan…»)
@export var text_dim := Color("9a9380")               ## objetos agotados
@export var text_keys := Color(0.86, 0.89, 1.0, 0.6)  ## ayuda de teclas
@export var text_red := Color("9c1d17")
@export var number_fill := Color("ffd23a")            ## números amarillos con borde
@export var number_outline := Color("3b2a00")
@export_group("Pasaportes")
@export var passport_tilt: float = 0.025              ## inclinación (radianes) de las tarjetas
@export var passport_paper := Color("f5f1e4")
@export var passport_photo_bg := Color("fffdf2")
@export var passport_pill_alpha: float = 0.4          ## opacidad de las filas dentro del pasaporte
@export_group("Animación")
@export_range(0, 40, 1) var open_frames: int = 10     ## fotogramas que tarda en aparecer (0 = de golpe)
@export_range(0.0, 1.0, 0.05) var open_start_scale: float = 0.92
@export var note_seconds: float = 1.8                 ## cuánto dura un aviso temporal
@export_group("Textos")
@export var t_passport := "PASAPORTE"
@export var t_level := "NV"
@export var t_exp := "EXP"
@export var t_hp := "PV"
@export var t_tp := "PT"
@export var t_power := "Fuerza"
@export var t_defense := "Defensa"
@export var t_speed := "Velocidad"
@export var t_stache := "Bigote"
@export var t_consumables := "Consumibles"
@export var t_ribbons := "Listones (aumentan los PM)"
@export var t_key_items := "Objetos clave"
@export var t_bp_title := "PUNTOS DE MEDALLA (PM) — compartidos"
@export var t_no_gear := "— nada —"
@export var t_no_badges := "— sin medallas —"
@export var t_take_off := "— Quitarse la pieza —"
@export var t_equipped := "(puesta)"
@export var t_unknown_room := "Zona actual"
