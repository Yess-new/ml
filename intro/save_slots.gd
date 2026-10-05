class_name SaveSlots
extends RefCounted
## FICHEROS DE GUARDADO (4). Se guardan en user://fichero_1.json ... fichero_4.json.
## GameState no se toca: aquí se lee/escribe su estado (monedas, niveles, objetos...).

const COUNT := 4
const VERSION := 1

static var start_scene: String = "res://overworld/test_zone.tscn"   ## dónde empieza una partida nueva (lo fija save_select.tscn)
static var current_slot: int = -1                                  ## fichero en uso (-1 = ninguno)

static func path(i: int) -> String:
	return "user://fichero_%d.json" % (i + 1)

static func exists(i: int) -> bool:
	return FileAccess.file_exists(path(i))

static func read(i: int) -> Dictionary:
	if not exists(i):
		return {}
	var f := FileAccess.open(path(i), FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

static func write(i: int, data: Dictionary) -> bool:
	var f := FileAccess.open(path(i), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true

static func erase(i: int) -> void:
	if exists(i):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path(i)))

## Lo que se guarda de la partida actual en este momento (llámalo cuando quieras guardar: SaveSlots.save_current(escena)).
static func capture(scene: String) -> Dictionary:
	var inv := {}
	for k in GameState.inventory:
		inv[String(k)] = int(GameState.inventory[k])
	var lv := {}
	var xp := {}
	for k in GameState.hero_level:
		lv[String(k)] = int(GameState.hero_level[k])
	for k in GameState.hero_exp:
		xp[String(k)] = int(GameState.hero_exp[k])
	return {"version": VERSION, "saved_at": Time.get_unix_time_from_system(), "scene": scene,
		"play_time": GameState.play_time, "coins": GameState.coins, "levels": lv, "exp": xp, "inventory": inv}

static func save_current(scene: String) -> bool:
	return current_slot >= 0 and write(current_slot, capture(scene))

## Pone el progreso de GameState como el de una partida nueva.
static func reset_progress() -> void:
	GameState.coins = 0
	GameState.hero_level = {&"mario": 1, &"luigi": 1}
	GameState.hero_exp = {&"mario": 0, &"luigi": 0}
	GameState.hero_hp.clear()
	GameState.hero_tp.clear()
	GameState.flags.clear()
	GameState.inventory = {&"mushroom": 3, &"syrup": 2, &"oneup": 1}
	GameState.play_time = 0.0
	GameState.set_party(&"both")

static func new_game_data() -> Dictionary:
	reset_progress()
	return capture(start_scene)

## Carga un fichero guardado en GameState y devuelve la escena en la que continuar.
static func apply(d: Dictionary) -> String:
	reset_progress()
	GameState.coins = int(d.get("coins", 0))
	GameState.play_time = float(d.get("play_time", 0.0))
	for k in d.get("levels", {}):
		GameState.hero_level[StringName(k)] = int(d["levels"][k])
	for k in d.get("exp", {}):
		GameState.hero_exp[StringName(k)] = int(d["exp"][k])
	var inv: Dictionary = d.get("inventory", {})
	if not inv.is_empty():
		GameState.inventory = {}
		for k in inv:
			GameState.inventory[StringName(k)] = int(inv[k])
	return String(d.get("scene", start_scene))

## Empieza a jugar con el fichero i (nueva partida: lo crea con los datos iniciales).
static func begin(tree: SceneTree, i: int, new_game: bool, fade: float = 0.8) -> void:
	current_slot = i
	var scene := start_scene
	if new_game:
		write(i, new_game_data())
	else:
		scene = apply(read(i))
	if not ResourceLoader.exists(scene):
		scene = start_scene
	ScreenFade.go(tree, scene, fade)

## Texto de resumen para la lista de ficheros.
static func summary(i: int) -> String:
	var d := read(i)
	if d.is_empty():
		return ""
	var lv: Dictionary = d.get("levels", {})
	var secs := int(d.get("play_time", 0.0))
	var date := ""
	if d.has("saved_at"):
		date = Time.get_datetime_string_from_unix_time(int(d["saved_at"]), true).left(16)
	return "Mario Nv %d  ·  Luigi Nv %d  ·  %d:%02d h  ·  %d monedas\n%s" % [int(lv.get("mario", 1)), int(lv.get("luigi", 1)),
		floori(secs / 3600.0), floori((secs % 3600) / 60.0), int(d.get("coins", 0)), date]
