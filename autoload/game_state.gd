extends Node
## AUTOLOAD "GameState": estado global de la partida (equivale a coins, inventory, bpMax, ribbonInv, badgeBag... del HTML).
## Registrar en Project Settings → Autoload con el nombre GameState.

signal changed   ## se emite cuando cambia algo (monedas, inventario, PM...) para que la UI se refresque

const RIBBON_BP := {&"blue": 1, &"silver": 3, &"gold": 10}   ## PM que da cada listón al usarlo

var coins: int = 0
var bp_max: int = 5                                                    ## puntos de medalla COMUNES a los dos hermanos
var inventory: Dictionary = {&"mushroom": 3, &"syrup": 2, &"oneup": 1}  ## id de objeto -> cantidad
var ribbon_inv: Dictionary = {&"blue": 0, &"silver": 0, &"gold": 0}    ## listones sin usar
var badge_bag: Array[Dictionary] = []   ## medallas: { "id": StringName, "bp": int, "by": StringName }  (by = &"mario" | &"luigi" | &"" si está en la bolsa)
var gear_bag: Array[Dictionary] = []    ## equipo: { "id": StringName, "by": StringName }

func add_coins(n: int) -> void:
	coins += n
	changed.emit()

## Gasta un listón y suma sus PM. Devuelve false si no queda ninguno.
func use_ribbon(kind: StringName) -> bool:
	if ribbon_inv.get(kind, 0) <= 0:
		return false
	ribbon_inv[kind] -= 1
	bp_max += RIBBON_BP[kind]
	changed.emit()
	return true

func bp_used() -> int:
	var n := 0
	for b in badge_bag:
		if b["by"] != &"":
			n += int(b["bp"])
	return n

func bp_left() -> int:
	return bp_max - bp_used()

# ───────────────────────────── catálogo de equipo y medallas (se leen de data/gear y data/badges) ─────────────────────────────

const GEAR_DIR := "res://data/gear"        ## cada .tres (GearDef) de esta carpeta es una pieza de equipo: añadir un archivo = añadir una pieza
const BADGE_DIR := "res://data/badges"     ## cada .tres (BadgeDef) de esta carpeta es una medalla
## Equipo con el que empieza la partida: [id de la pieza, quién la lleva puesta (&"" = en la bolsa)]
const START_GEAR := [[&"bootsBasic", &"mario"], [&"bootsBasic", &"luigi"], [&"hammerWood", &"mario"], [&"hammerWood", &"luigi"],
	[&"shirtCotton", &"mario"], [&"shirtCotton", &"luigi"], [&"bootsSpike", &""], [&"bootsRubber", &""], [&"hammerIron", &""], [&"shirtPadded", &""]]

var gear_defs: Dictionary = {}     ## id -> GearDef
var badge_defs: Dictionary = {}    ## id -> BadgeDef
var play_time: float = 0.0         ## segundos jugados (el reloj del menú)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # el reloj sigue corriendo con el menú abierto
	_scan_defs(GEAR_DIR, gear_defs)
	_scan_defs(BADGE_DIR, badge_defs)
	if gear_bag.is_empty():
		for e in START_GEAR:
			gear_bag.append({"id": e[0], "by": e[1]})

func _process(delta: float) -> void:
	play_time += delta

func _scan_defs(dir: String, into: Dictionary) -> void:
	for f in DirAccess.get_files_at(dir):
		var file := f.trim_suffix(".remap")   # en el juego exportado los recursos aparecen como .tres.remap
		if not file.ends_with(".tres"):
			continue
		var r := load(dir + "/" + file)
		if r != null and r.get("id") != null and r.id != &"":
			into[r.id] = r

## Da una medalla (p. ej. al comprarla en una tienda): GameState.add_badge(&"doubleEdge"). Empieza en la bolsa (sin equipar).
func add_badge(id: StringName) -> bool:
	var d := badge_def(id)
	if d == null:
		push_warning("[GameState] No existe la medalla '%s' (data/badges)." % id)
		return false
	badge_bag.append({"id": id, "bp": d.bp, "by": &""})
	changed.emit()
	return true

func gear_def(id: StringName) -> GearDef:
	return gear_defs.get(id) as GearDef

func badge_def(id: StringName) -> BadgeDef:
	return badge_defs.get(id) as BadgeDef

## Índice en gear_bag de la pieza que lleva puesta hero_id en esa ranura (-1 si ninguna).
func equipped_index(hero_id: StringName, slot: StringName) -> int:
	for i in gear_bag.size():
		var d := gear_def(gear_bag[i]["id"])
		if gear_bag[i]["by"] == hero_id and d != null and d.slot == slot:
			return i
	return -1

## Suma de lo que da el equipo puesto: stat = &"power" o &"defense".
func gear_bonus(hero_id: StringName, stat: StringName) -> int:
	var n := 0
	for g in gear_bag:
		if g["by"] == hero_id:
			var d := gear_def(g["id"])
			if d != null:
				n += int(d.get(stat))
	return n

## ¿Lleva puesta esta medalla? (úsalo para programar su efecto: GameState.has_badge(&"mario", &"doubleEdge"))
func has_badge(hero_id: StringName, badge_id: StringName) -> bool:
	for b in badge_bag:
		if b["by"] == hero_id and b["id"] == badge_id:
			return true
	return false

# ───────────────────────────── héroes (se conservan entre combates) ─────────────────────────────

var hero_hp: Dictionary = {}    ## id del héroe -> PV actuales (si no está: PV al máximo)
var hero_tp: Dictionary = {}    ## id del héroe -> PT actuales (si no está: PT al máximo)
var hero_level: Dictionary = {&"mario": 1, &"luigi": 1}
var hero_exp: Dictionary = {&"mario": 0, &"luigi": 0}   ## experiencia acumulada hacia el siguiente nivel

func hp_of(s: CharacterStats) -> int:
	return int(hero_hp.get(s.id, s.max_hp))

func tp_of(s: CharacterStats) -> int:
	return int(hero_tp.get(s.id, s.max_tp))

## PX que hacen falta para pasar del nivel lv al siguiente (como el prototipo: 10, 20, 40, 80...).
func exp_need(lv: int) -> int:
	return 10 * (1 << (lv - 1))

## Suma experiencia a un héroe. Devuelve cuántos niveles ha subido.
func add_exp(id: StringName, n: int) -> int:
	var lv := int(hero_level.get(id, 1))
	var e := int(hero_exp.get(id, 0)) + n
	var ups := 0
	while e >= exp_need(lv):
		e -= exp_need(lv)
		lv += 1
		ups += 1
	hero_level[id] = lv
	hero_exp[id] = e
	changed.emit()
	return ups

# ───────────────────────────── progreso (eventos, cinemáticas vistas...) ─────────────────────────────

var flags: Dictionary = {}   ## id -> valor. P. ej. las cinemáticas "solo una vez" guardan aquí que ya se vieron

func has_flag(id: StringName) -> bool:
	return bool(flags.get(id, false))

func set_flag(id: StringName, value: Variant = true) -> void:
	flags[id] = value
	changed.emit()

# ───────────────────────────── quién anda (PartyMode) ─────────────────────────────

const PARTIES := [&"both", &"mario", &"luigi"]
var party: StringName = &"both"   ## quién anda en esta parte de la historia: both (los dos), mario o luigi

## Cambia quién anda (lo usa PartyMode al entrar en una habitación). Se conserva al cambiar de habitación.
func set_party(p: StringName) -> void:
	if not PARTIES.has(p):
		push_warning("[GameState] party '%s' no existe: usa both, mario o luigi." % p)
		return
	if party == p:
		return
	party = p
	changed.emit()

## ¿Anda este hermano ahora? (id = mario o luigi)
func has_hero(id: StringName) -> bool:
	return party == &"both" or party == id

# ───────────────────────────── combate ─────────────────────────────

const BATTLE_SCENE := "res://Combate/battle.tscn"

var battle_enemies: Array = []           ## PackedScene de enemigos del próximo combate (vacío = usa los colocados en battle.tscn)
var battle_return_scene: String = ""     ## escena a la que volver al terminar ("" = repetir el combate: modo prueba)
var last_battle_result: StringName = &"" ## &"win" | &"lose" | &"fled" del último combate

## Empieza un combate contra "enemies" (Array de PackedScene, p.ej. preload("res://Combate/enemigos/goomba_battle.tscn"))
## y, al terminar, vuelve a return_scene. Cada enemigo se coloca en un marcador de EnemySpots.
func start_battle(enemies: Array, return_scene: String = "") -> void:
	battle_enemies = enemies
	battle_return_scene = return_scene
	get_tree().change_scene_to_file(BATTLE_SCENE)
