@tool
class_name BattleActor
extends Node2D
## BASE de todo lo que lucha (héroes y enemigos). Cada actor es una ESCENA con esta estructura:
##
##   Actor (este script)        ← su posición = su SITIO en el combate (los PIES). Muévelo en el editor.
##   ├─ Shadow (Sprite2D)       ← sombra en el suelo (opcional). Sigue al actor pero NO sube cuando salta.
##   └─ Visual (Node2D)         ← todo lo que se mueve con las animaciones de combate (saltos, embestidas, giros).
##       └─ Sprite (AnimatedSprite2D) ← TUS animaciones. Pon el origen en los pies (desactiva Centered o usa Offset).
##
## ANIMACIONES que se reproducen solas si existen en el SpriteFrames (si falta alguna, se usa "idle"):
##   idle · jump (en el aire) · hurt (al recibir daño) · fallen / defeated (caído) · hammer · run · victory · tell · attack
## Sin SpriteFrames (o sin textura en Shadow) se dibuja un dibujo PROVISIONAL, también en el editor.

@export var body_size: Vector2 = Vector2(34, 80):   ## ancho y alto del cuerpo: dónde aterrizan los saltos, dónde apunta la flecha, dónde salen los números
	set(v):
		body_size = v
		queue_redraw()
## Botón: calcula Body Size a partir del sprite (primer fotograma de "idle", solo la parte visible, sin bordes transparentes).
## También puedes ajustarlo a mano arrastrando la caja naranja que aparece al seleccionar el personaje.
@warning_ignore("unused_private_class_variable")   # es un botón del Inspector: lo usa el editor, no el código
@export_tool_button("Ajustar Body Size al sprite", "Rect2") var _fit_body_button: Callable = fit_body_to_sprite
@export var visual_scale: float = 1.035   ## tamaño del actor en combate (1.0 = normal, 1.5 = 50% más grande). Escala Visual y Shadow al jugar; body_width/height ya lo incluyen
@export var placeholder_color: Color = Color(0.85, 0.3, 0.3):   ## color del dibujo provisional (si no hay sprite)
	set(v):
		placeholder_color = v
		queue_redraw()

var display_name := ""
var max_hp := 1
var hp := 1
var max_tp := 0
var tp := 0
var power := 10       ## fuerza
var defense := 0      ## defensa
var turn_speed := 0   ## velocidad: orden de turnos (más alto = antes)
var stache := 0       ## bigote: % de crítico
var alive := true
var offset := Vector2.ZERO          ## desplazamiento de la animación de combate respecto a su sitio
var advance := Vector2.ZERO         ## cuánto ha avanzado en su turno (lo mueve el combate; se suma a offset)
var spin := 0.0                     ## giro (radianes)
var flash := 0                      ## fotogramas de parpadeo tras recibir daño
var shadow_y := NAN                 ## si no es NAN: altura (y del mundo) a la que se queda la sombra aunque el actor vuele (ataque tándem)
var anim_override: StringName = &"" ## si no está vacío, fuerza esa animación (lo usan el combate y los patrones)

var visual: Node2D
var sprite: AnimatedSprite2D
var shadow: Node2D
var _visual_base := Vector2.ZERO
var _shadow_base := Vector2.ZERO

func _ready() -> void:
	visual = get_node_or_null("Visual") as Node2D
	sprite = get_node_or_null("Visual/Sprite") as AnimatedSprite2D
	shadow = get_node_or_null("Shadow") as Node2D
	if visual:
		_visual_base = visual.position
	if shadow:
		_shadow_base = shadow.position

func is_hero() -> bool:
	return false

## ¿Tiene pinchos (saltar encima hiere)? Lo sobrescriben los enemigos y las dianas.
func is_spiked() -> bool:
	return false

## Calcula body_size a partir de lo que se VE del personaje: todos los sprites visibles dentro de Visual (AnimatedSprite2D con
## el primer fotograma de "idle", o Sprite2D con su textura / fotograma / región), menos el martillo. Solo cuenta la parte no
## transparente y tiene en cuenta posición, escala, Offset, Centered y Flip. Ancho = ancho del dibujo; alto = de los pies (y = 0)
## hasta lo más alto. Se puede deshacer con Ctrl+Z.
func fit_body_to_sprite() -> void:
	var vis := get_node_or_null("Visual") as Node2D
	if vis == null:
		push_warning("[%s] No tiene nodo Visual." % name)
		return
	# de coordenadas de Visual a coordenadas del personaje, SIN la escala de combate (visual_scale se aplica aparte al jugar)
	var vis_to_me := Transform2D(0.0, vis.position)
	var total := Rect2()
	var found := false
	for n in [vis] + vis.find_children("*", "Node2D", true, false):
		if n is Node2D and (n as Node2D).name == "HammerPivot":
			continue
		if _under_hammer(n, vis) or not (n as CanvasItem).visible:
			continue
		var lr := _sprite_local_rect(n)
		if lr.size == Vector2.ZERO:
			continue
		var xf: Transform2D = vis_to_me * (vis.get_global_transform().affine_inverse() * (n as Node2D).get_global_transform())
		var r := xf * lr
		total = r if not found else total.merge(r)
		found = true
	if not found:
		push_warning("[%s] No hay ningún sprite visible con imagen dentro de Visual." % name)
		return
	var new_size := Vector2(roundf(total.size.x), roundf(maxf(-total.position.y, 1.0)))
	var anim := "visible"
	var ei = Engine.get_singleton(&"EditorInterface") if Engine.has_singleton(&"EditorInterface") else null
	if ei:   # en el editor: con deshacer
		var ur = ei.get_editor_undo_redo()
		ur.create_action("Ajustar Body Size de %s al sprite" % name)
		ur.add_do_property(self, &"body_size", new_size)
		ur.add_undo_property(self, &"body_size", body_size)
		ur.commit_action()
	else:
		body_size = new_size
	print("[%s] Body Size = %s (ajustado a lo %s del sprite)" % [name, new_size, anim])

func _under_hammer(n: Node, vis: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != vis:
		if p.name == "HammerPivot":
			return true
		p = p.get_parent()
	return false

## Caja (en coordenadas locales del nodo) de la parte NO transparente que dibuja un Sprite2D o AnimatedSprite2D. Vacía si no dibuja nada.
func _sprite_local_rect(n: Node) -> Rect2:
	var tex: Texture2D = null
	var region := Rect2()
	var centered := true
	var off := Vector2.ZERO
	var flip := false
	if n is AnimatedSprite2D:
		var a := n as AnimatedSprite2D
		if a.sprite_frames == null:
			return Rect2()
		var anim: StringName = &"idle" if a.sprite_frames.has_animation(&"idle") else a.animation
		if not a.sprite_frames.has_animation(anim) or a.sprite_frames.get_frame_count(anim) == 0:
			return Rect2()
		tex = a.sprite_frames.get_frame_texture(anim, 0)
		if tex == null:
			return Rect2()
		region = Rect2(Vector2.ZERO, tex.get_size())
		centered = a.centered
		off = a.offset
		flip = a.flip_h
	elif n is Sprite2D:
		var s := n as Sprite2D
		tex = s.texture
		if tex == null:
			return Rect2()
		var full := s.region_rect if s.region_enabled else Rect2(Vector2.ZERO, tex.get_size())
		var fsize := full.size / Vector2(maxi(s.hframes, 1), maxi(s.vframes, 1))   # un fotograma de la cuadrícula
		region = Rect2(full.position + fsize * Vector2(s.frame_coords), fsize)
		centered = s.centered
		off = s.offset
		flip = s.flip_h
	else:
		return Rect2()
	var used := Rect2(Vector2.ZERO, region.size)
	var img := tex.get_image()
	if img:
		var sub := img.get_region(Rect2i(region))
		var u := sub.get_used_rect()   # solo los píxeles no transparentes
		if u.size.x > 0 and u.size.y > 0:
			used = Rect2(u)
	var origin := off - (region.size * 0.5 if centered else Vector2.ZERO)
	var r := Rect2(origin + used.position, used.size)
	if flip:   # espejo respecto al centro del fotograma
		var c := origin.x + region.size.x * 0.5
		r.position.x = 2.0 * c - r.end.x
	return r

func body_width() -> float:
	return body_size.x * visual_scale

func body_height() -> float:
	return body_size.y * visual_scale

## Dónde está su cabeza ahora (mundo): hacia ahí apunta la cola de los globos de diálogo del combate.
func head_global_position() -> Vector2:
	return global_position + offset + advance + Vector2(0.0, -body_height() - hop())

## Altura extra a la que se dibuja (saltos de esquiva, rebotes...). La sobrescriben los héroes.
func hop() -> float:
	return 0.0

## Un fotograma de efectos comunes (lo llama el combate).
func tick() -> void:
	if flash > 0:
		flash -= 1

func _process(_delta: float) -> void:
	queue_redraw()
	if Engine.is_editor_hint():
		return   # en el editor no se toca nada: así puedes mover Visual, Shadow, Sprite...
	if visual:
		visual.scale = Vector2.ONE * visual_scale
		visual.position = _visual_base + offset + advance + Vector2(0, -hop())
		visual.rotation = spin
		visual.visible = _is_visible_now()
	if shadow:
		shadow.scale = Vector2.ONE * visual_scale
		shadow.position = _shadow_base + offset + advance
		if not is_nan(shadow_y):
			shadow.position.y = _shadow_base.y + (shadow_y - position.y)
		shadow.visible = alive or is_hero()
	_update_anim()

func _is_visible_now() -> bool:
	return not (flash > 0 and int(flash / 3.0) % 2 == 0)

## Animación que toca según el estado (la sobrescriben héroes y enemigos).
func _auto_anim() -> StringName:
	return &"idle"

func _update_anim() -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var want := anim_override if anim_override != &"" else _auto_anim()
	var frames := sprite.sprite_frames
	if not frames.has_animation(want):
		want = &"idle" if frames.has_animation(&"idle") else &"default"
	if not frames.has_animation(want):
		return
	if sprite.animation != want or not sprite.is_playing():
		sprite.play(want)

## ¿Tiene arte propio? Si no, se dibuja el provisional.
func has_art() -> bool:
	return sprite != null and sprite.sprite_frames != null

func _shadow_has_art() -> bool:
	return shadow is Sprite2D and (shadow as Sprite2D).texture != null

## Transformación (local) con la que se dibuja el provisional: la del nodo Visual.
func _visual_xform() -> Transform2D:
	if visual:
		return visual.transform
	return Transform2D(spin, Vector2.ONE * visual_scale, 0.0, offset + advance + Vector2(0, -hop()))

func _draw() -> void:
	if not _shadow_has_art() and (alive or is_hero()):
		var sp := shadow.position if shadow else offset + advance
		_ellipse(sp + Vector2(0, 2), body_width() * 0.65, 7.0 * visual_scale, Color(0, 0, 0, 0.3))
	if has_art():
		return
	if not Engine.is_editor_hint() and visual and not visual.visible:
		return
	draw_set_transform_matrix(_visual_xform())
	_draw_placeholder()
	draw_set_transform(Vector2.ZERO)

## Dibujo provisional (en coordenadas de Visual, pies en 0,0).
func _draw_placeholder() -> void:
	draw_rect(Rect2(-body_size.x / 2, -body_size.y, body_size.x, body_size.y), placeholder_color)

func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)
