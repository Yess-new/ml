class_name HeroGrowth
extends RefCounted
## CRECIMIENTO DE LOS HERMANOS al subir de nivel (como LEVEL_GAIN del prototipo HTML).
## Lo que ganan se guarda como "bonus" encima de sus estadísticas base (data/*_stats.tres), dentro de GameState.flags[&"stat_bonus"],
## así que se conserva entre combates y habitaciones. BattleHero.setup() lo suma al empezar cada combate.
##
## Para cambiar cuánto sube cada atributo: edita GAIN (mínimo, máximo). Todos suben siempre al menos el mínimo.

## Atributos que suben: clave (propiedad de CharacterStats) y nombre en pantalla (en este orden salen).
const STATS := [
	{"k": &"max_hp", "label": "PV"}, {"k": &"max_tp", "label": "PT"}, {"k": &"power", "label": "FUERZA"},
	{"k": &"defense", "label": "DEFENSA"}, {"k": &"turn_speed", "label": "VELOCIDAD"}, {"k": &"stache", "label": "BIGOTE"},
]

## [mínimo, máximo] que sube cada atributo al subir de nivel. Mario: más fuerza y bigote · Luigi: más defensa.
const GAIN := {
	&"mario": {&"max_hp": [2, 4], &"max_tp": [1, 2], &"power": [1, 3], &"defense": [1, 2], &"turn_speed": [1, 2], &"stache": [1, 3]},
	&"luigi": {&"max_hp": [2, 4], &"max_tp": [1, 3], &"power": [1, 2], &"defense": [1, 3], &"turn_speed": [1, 2], &"stache": [1, 2]},
}
const DEFAULT_GAIN := [1, 3]   ## para un héroe que no esté en GAIN

## Ruleta del bonus: [número, grados]. El 5 es el sector más pequeño (hay que parar la ruleta con buen timing).
const WHEEL := [[1, 55], [3, 45], [2, 50], [4, 40], [2, 45], [5, 40], [3, 40], [1, 45]]
const WHEEL_SPEED := 6.0   ## radianes por segundo (el HTML: 0,1 rad por fotograma a 60 fps)

static func _key(id: StringName, stat: StringName) -> String:
	return "%s:%s" % [id, stat]

## Lo ganado hasta ahora en este atributo (suma encima del base).
static func bonus(id: StringName, stat: StringName) -> int:
	var d: Dictionary = GameState.flags.get(&"stat_bonus", {})
	return int(d.get(_key(id, stat), 0))

## Estadística base + lo ganado al subir de nivel (sin el equipo).
static func value(s: CharacterStats, stat: StringName) -> int:
	return int(s.get(stat)) + bonus(s.id, stat)

## Suma n a un atributo.
static func add(id: StringName, stat: StringName, n: int) -> void:
	var d: Dictionary = GameState.flags.get(&"stat_bonus", {})
	d[_key(id, stat)] = int(d.get(_key(id, stat), 0)) + n
	GameState.flags[&"stat_bonus"] = d

## Tira cuánto sube cada atributo en una subida de nivel (aleatorio entre su mínimo y máximo): { stat: n }.
static func roll(id: StringName) -> Dictionary:
	var out := {}
	var table: Dictionary = GAIN.get(id, {})
	for s in STATS:
		var r: Array = table.get(s["k"], DEFAULT_GAIN)
		out[s["k"]] = randi_range(int(r[0]), int(r[1]))
	return out

## Número de la ruleta que queda bajo la flecha (arriba) con la rueda girada th radianes.
static func wheel_pick(th: float) -> int:
	var a := fposmod(-PI / 2.0 - th, TAU)
	var acc := 0.0
	for w in WHEEL:
		acc += deg_to_rad(float(w[1]))
		if a < acc:
			return int(w[0])
	return int(WHEEL[-1][0])
