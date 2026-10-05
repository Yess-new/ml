@tool
class_name BattleEnemy
extends BattleActor
## Un enemigo en combate. ESCENA (Combate/enemigos/goomba_battle.tscn):
##
##   Goomba (este script)      ← "Data": su EnemyData (estadísticas, recompensas, ataque).
##   ├─ Shadow (Sprite2D)
##   └─ Visual (Node2D)
##       └─ Sprite (AnimatedSprite2D) ← animaciones: idle, tell (aviso), attack, hurt, defeated
##
## Los enemigos miran a la IZQUIERDA (hacia los héroes). Para un enemigo nuevo: duplica goomba_battle.tscn, cambia Data y Sprite.

@export var data: EnemyData

## ¿Se puede elegir su CUERPO como objetivo? Si tiene dianas (nodos Hittable hijos) y esto está desactivado, solo se eligen ellas.
@export var body_targetable: bool = true

var spark := 0   ## destello al pincharse un héroe con él
var hittables: Array = []   ## sus dianas (Hittable): las engancha el combate al empezar o las crea un patrón

func is_spiked() -> bool:
	return data != null and data.spiked

func setup() -> void:
	display_name = data.display_name
	max_hp = data.max_hp
	hp = data.max_hp
	power = data.power
	defense = data.defense
	turn_speed = data.turn_speed
	stache = data.stache

## Cuánto reacciona al recibir un golpe (hundimiento y temblor, valores en Combate/hit_fx_default.tres). 1 = normal, 0 = nada.
@export var react_scale: float = 1.0

var _react_t := 0
var _react_len := 1
var _react_power := 1.0
var _react_squash := 0.14
var _react_shake := 0.03

## Lo llama el combate al hacerle daño: se hunde (aplastándose contra el suelo, con los pies fijos) y tiembla de lado, todo en
## porcentaje de su tamaño, así que se ve bien con cualquier Body Size / Visual Scale.
func hit_react(fx: HitFxStyle, dmg: int) -> void:
	if fx == null or react_scale <= 0.0:
		return
	_react_len = maxi(1, fx.react_frames)
	_react_t = _react_len
	_react_power = clampf(0.6 + dmg / 10.0, 0.6, 1.5) * react_scale
	_react_squash = fx.squash
	_react_shake = fx.shake

func tick() -> void:
	super()
	if spark > 0:
		spark -= 1
	if _react_t > 0:
		_react_t -= 1

func _process(delta: float) -> void:
	super(delta)
	if Engine.is_editor_hint() or visual == null or _react_t <= 0:
		return
	var t := 1.0 - float(_react_t) / float(_react_len)   # 0 → 1 durante la reacción
	var env := (1.0 - t) * (1.0 - t) * _react_power   # se asienta rápido: la deformación baja al cuadrado
	var wob := cos(t * PI * 2.5)   # se aplasta de golpe, se estira un poco y se asienta (muelle amortiguado)
	var sy := 1.0 - _react_squash * wob * env
	var sx := 1.0 + (1.0 - sy) * 0.5   # al aplastarse se ensancha un poco
	visual.scale = Vector2(visual_scale * sx, visual_scale * sy)
	visual.position.x += sin(t * PI * 6.0) * _react_shake * body_width() * env
	if shadow:
		shadow.scale = Vector2(visual_scale * sx, visual_scale)

func _is_visible_now() -> bool:
	if not alive:   # vencido: desaparece (o se queda con su animación "defeated" si la tiene)
		return has_art() and sprite.sprite_frames.has_animation(&"defeated")
	return super()

func _auto_anim() -> StringName:
	if not alive:
		return &"defeated"
	if flash > 0:
		return &"hurt"
	return &"idle"

func _draw() -> void:
	super()
	if spark > 0 and alive:
		draw_circle(offset + advance + Vector2(0, -body_height()), 10.0 + spark, Color(1, 0.95, 0.4, spark / 16.0))

## Provisional estilo Goomba, con body_size y placeholder_color.
