@tool
class_name BattleHero
extends BattleActor
## Un hermano en combate. ESCENA (Combate/actores/mario_battle.tscn, luigi_battle.tscn):
##
##   Mario (este script)          ← "Stats": su CharacterStats (data/*_stats.tres). Vida/PT actuales: GameState.
##   ├─ Shadow (Sprite2D)
##   └─ Visual (Node2D)
##       ├─ Sprite (AnimatedSprite2D)    ← animaciones: idle, jump, hurt, fallen, hammer, run, victory
##       └─ HammerPivot (Node2D)         ← colócalo en la MANO. El combate lo gira (0 = martillo horizontal hacia delante).
##           └─ Hammer (Sprite2D)        ← tu sprite del martillo, con el mango en el origen del pivote y apuntando a la DERECHA.
##
## Los héroes miran a la derecha (los enemigos están a la derecha).

const DODGE_JUMP_H := 170.0   ## altura del salto de esquiva (px), como en el prototipo
const DODGE_SPEED := 0.035   ## cuánto baja "jump" por fotograma (1 → 0 en ~29 fotogramas)

@export var stats: CharacterStats:
	set(v):
		stats = v
		queue_redraw()
## ¿Participa en el combate? Desactívalo y este héroe NO aparece: el combate se juega solo con los demás (sin su turno,
## sin su tarjeta de vida ni su botón de esquiva, los enemigos no le atacan y no recibe experiencia).
## En el editor se le marca con "FUERA DEL COMBATE".
@export var in_battle: bool = true:
	set(v):
		in_battle = v
		queue_redraw()

var jump := 0.0       ## salto de esquiva: 1 al saltar, baja a 0
var bounce := 0.0     ## rebote al aplastar a un enemigo
var bounce_from := 0.0 ## altura (px) a la que cayó sobre el enemigo: el rebote parte de ahí (enemigos altos como Bowser)
var sel_hop := 0.0    ## saltito al elegir acción (0..1)
var sel_hop_h := 34.0 ## altura (px) de ese saltito: la fija la interfaz para que la cabeza llegue al bloque
var hammer = null     ## martillo en mano: { "angle", "scale", "glow" } o null
var out := false      ## ya salió de la pantalla al huir
var run_t := 0        ## animación de carrera al huir

var hammer_pivot: Node2D
var hammer_sprite: Sprite2D

func _ready() -> void:
	super()
	hammer_pivot = get_node_or_null("Visual/HammerPivot") as Node2D
	hammer_sprite = get_node_or_null("Visual/HammerPivot/Hammer") as Sprite2D
	if not Engine.is_editor_hint() and hammer_pivot:
		hammer_pivot.visible = false

func setup(hp_now: int, tp_now: int) -> void:
	display_name = stats.display_name
	max_hp = HeroGrowth.value(stats, &"max_hp")   # base + lo ganado al subir de nivel (data/hero_growth.gd)
	max_tp = HeroGrowth.value(stats, &"max_tp")
	hp = clampi(hp_now, 0, max_hp)
	tp = clampi(tp_now, 0, max_tp)
	power = HeroGrowth.value(stats, &"power") + GameState.gear_bonus(stats.id, &"power")        # + lo que da el equipo puesto (menú de pausa)
	defense = HeroGrowth.value(stats, &"defense") + GameState.gear_bonus(stats.id, &"defense")
	turn_speed = HeroGrowth.value(stats, &"turn_speed")
	stache = HeroGrowth.value(stats, &"stache")
	alive = hp > 0

func is_hero() -> bool:
	return true

## Acción del Input Map de este hermano (Z para Mario, X para Luigi): confirmar, saltar y golpear.
func action() -> StringName:
	return stats.jump_action

## Altura actual del salto de esquiva (px).
func air_height() -> float:
	return sin(clampf(jump, 0.0, 1.0) * PI) * DODGE_JUMP_H

func hop() -> float:
	# rebote: parte de la altura a la que cayó sobre el enemigo (bounce_from) y desde ahí sube y baja
	return air_height() + bounce_from * bounce + sin(bounce * PI) * maxf(60.0, 150.0 - bounce_from * 0.5) + sin(clampf(sel_hop, 0.0, 1.0) * PI) * sel_hop_h

## ESQUIVA CON MARTILLO (ataques enemigos con defense_kind() == &"hammer"): MANTÉN el botón para sacar y CARGAR el martillo y
## SUÉLTALO para golpear. El martillo solo golpea (y devuelve / para el ataque) durante GUARD_HIT_FRAMES tras soltar.
const GUARD_RAISE := 14        ## fotogramas manteniendo el botón hasta tenerlo del todo levantado (cargado)
const GUARD_SWING := 3         ## fotogramas que tarda el martillo en bajar al soltar
const GUARD_HIT_FRAMES := 12   ## fotogramas (desde que suelta) con el martillo golpeando
const GUARD_RECOVER := 10      ## fotogramas de recuperación tras el golpe (no puede volver a sacarlo)
var guard_state := 0           ## 0 = nada · 1 = cargando (botón mantenido) · 2 = golpeando · 3 = recuperándose
var guard_t := 0               ## fotogramas en el estado actual
var guard_charged := false     ## ¿lo soltó ya del todo cargado? Si no, el martillazo no vale (tocar el botón no basta)

## Un fotograma de la esquiva con martillo. "active" = el ataque enemigo actual se defiende con martillo.
func guard_update(active: bool) -> void:
	if not active or not alive:
		if guard_state != 0:
			guard_state = 0
			hammer = null
		return
	var held := Input.is_action_pressed(action())
	match guard_state:
		0:
			if Input.is_action_just_pressed(action()):
				guard_state = 1
				guard_t = 0
				hammer = {"angle": 2.0, "scale": 1.0, "glow": false}
		1:
			guard_t += 1
			var q := minf(1.0, float(guard_t) / GUARD_RAISE)
			hammer["angle"] = lerpf(2.0, -2.0, 1.0 - (1.0 - q) * (1.0 - q)) + (sin(guard_t * 1.4) * 0.04 if q >= 1.0 else 0.0)
			hammer["glow"] = q >= 1.0   # ya está cargado: suéltalo
			if not held:   # suelta: golpea (solo hace efecto si estaba del todo cargado)
				guard_charged = q >= 1.0
				guard_state = 2
				guard_t = 0
				hammer["glow"] = false
		2:
			guard_t += 1
			hammer["angle"] = lerpf(float(hammer["angle"]), 0.05, minf(1.0, float(guard_t) / GUARD_SWING))
			hammer["glow"] = hammer_hitting()
			if guard_t >= GUARD_HIT_FRAMES + GUARD_RECOVER:
				guard_state = 3
				guard_t = 0
		3:
			guard_state = 0
			hammer = null

## ¿Está su martillo golpeando ahora mismo (puede devolver / parar un ataque)?
func hammer_hitting() -> bool:
	return guard_state == 2 and guard_charged and guard_t <= GUARD_HIT_FRAMES

func tick() -> void:
	super()
	if jump > 0.0:
		jump = maxf(0.0, jump - DODGE_SPEED)
	if bounce > 0.0:
		bounce = maxf(0.0, bounce - 0.04)

func _process(delta: float) -> void:
	super(delta)
	if Engine.is_editor_hint() or hammer_pivot == null:
		return
	hammer_pivot.visible = hammer != null and hammer_sprite != null and hammer_sprite.texture != null
	if hammer != null:
		hammer_pivot.rotation = float(hammer["angle"])
		hammer_pivot.scale = Vector2.ONE * float(hammer["scale"])
		if hammer_sprite:
			hammer_sprite.modulate = Color(1.6, 1.5, 0.6) if hammer["glow"] else Color.WHITE   # brilla: ¡ahora!

func _is_visible_now() -> bool:
	return alive and super()

func _auto_anim() -> StringName:
	if not alive:
		return &"fallen"
	if flash > 0:
		return &"hurt"
	if hammer != null:
		return &"hammer"
	if hop() > 4.0 or offset.y < -8.0:
		return &"jump"
	return &"idle"

func _shirt() -> Color:
	return stats.shirt_color if stats else placeholder_color

func _draw() -> void:
	super()
	if Engine.is_editor_hint():
		if not in_battle:   # aviso en el editor: este héroe no entra en el combate
			var font := ThemeDB.fallback_font
			var txt := "FUERA DEL COMBATE"
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			var top := Vector2(-w * 0.5, -body_size.y - 22.0)
			draw_rect(Rect2(top + Vector2(-6, -16), Vector2(w + 12, 22)), Color(0.75, 0.1, 0.1, 0.85))
			draw_string(font, top, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
			draw_line(Vector2(-body_size.x * 0.7, -body_size.y), Vector2(body_size.x * 0.7, 0), Color(0.9, 0.1, 0.1), 4.0)
			draw_line(Vector2(body_size.x * 0.7, -body_size.y), Vector2(-body_size.x * 0.7, 0), Color(0.9, 0.1, 0.1), 4.0)
		return
	if not alive:   # caído: tumbado con estrellitas (el provisional; con sprite, usa la animación "fallen")
		if not has_art():
			draw_set_transform(offset + Vector2(-36, -14), -PI / 2.0)
			_draw_placeholder()
			draw_set_transform(Vector2.ZERO)
		var t := Time.get_ticks_msec() / 260.0
		for i in 2:
			draw_circle(offset + Vector2(-40 + cos(t + i * PI) * 10, -38 + sin(t + i * PI) * 4), 4.0, Color("fff700"))
		return
	if hammer != null and (hammer_sprite == null or hammer_sprite.texture == null) and _is_visible_now():
		_draw_placeholder_hammer()

func _draw_placeholder() -> void:
	var shirt := _shirt()
	var blue := Color("2b4fc9")
	var skin := Color("f4c9a0")
	var brown := Color("5a3a1c")
	draw_rect(Rect2(-14, -20, 11, 18), blue)            # piernas
	draw_rect(Rect2(3, -20, 11, 18), blue)
	_ellipse(Vector2(-9, -2), 9.0, 5.0, brown)          # zapatos
	_ellipse(Vector2(10, -2), 9.0, 5.0, brown)
	draw_rect(Rect2(-17, -46, 34, 28), shirt)           # camisa
	draw_rect(Rect2(-13, -38, 26, 20), blue)            # peto
	draw_circle(Vector2(0, -60), 15.0, skin)            # cabeza
	draw_rect(Rect2(-16, -78, 30, 12), shirt)           # gorra
	draw_rect(Rect2(2, -68, 19, 5), shirt)              # visera (mira a la derecha)
	draw_circle(Vector2(8, -62), 2.5, Color.BLACK)      # ojo
	draw_circle(Vector2(15, -58), 4.0, skin)            # nariz
	draw_rect(Rect2(3, -55, 14, 4), Color("3b2414"))    # bigote

func _draw_placeholder_hammer() -> void:
	var sc: float = hammer["scale"]
	if sc <= 0.01:
		return
	var pivot := hammer_pivot.position if hammer_pivot else Vector2(12, -34)
	var xf := _visual_xform() * Transform2D(float(hammer["angle"]), Vector2.ONE * sc, 0.0, pivot)
	draw_set_transform_matrix(xf)
	draw_rect(Rect2(0, -2.5, 34, 5), Color("8a5a2b"))   # mango
	var head := Rect2(28, -11, 16, 22)
	draw_rect(head, Color("9aa3ad"))                     # cabeza
	if hammer["glow"]:
		draw_rect(head.grow(3), Color("ffe14d"), false, 3.0)
	draw_rect(head, Color("3a3f45"), false, 2.0)
	draw_set_transform(Vector2.ZERO)
