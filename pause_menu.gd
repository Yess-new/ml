extends CanvasLayer
## MENÚ DE PAUSA del overworld (autoload "PauseMenu", escena ui/pause_menu.tscn). Se abre con Enter (acción "menu") y se cierra con Enter o C.
## Port del menú del prototipo HTML: portada con los pasaportes y los apartados Objetos, Equipo, Medallas, Estado y Mapa.
##
## TODO SE EDITA SIN CÓDIGO:
##   - Aspecto (colores, fuente, textos, animación)  -> Style (ui/pause_menu_style.tres)
##   - Apartados (orden, nombre, icono, activar)     -> Sections (recursos MenuSection)
##   - Hermanos que salen (orden en pantalla)        -> Heroes (sus CharacterStats; el retrato se pone ahí: Portrait)
##   - Equipo / medallas / objetos clave             -> archivos .tres en data/gear, data/badges, data/key_items
##   - Ranuras de equipo (Zapatos, Martillo...)      -> Gear Slots
##   - Objetos consumibles                           -> Combate/battle_items.gd (los mismos que en combate)
##   - Teclas                                        -> las acciones del Input Map que pongas en Actions
## Desde código: PauseMenu.open() / PauseMenu.close() / PauseMenu.is_open, y las señales opened / closed.

signal opened
signal closed

@export var style: MenuStyle
@export var sections: Array[MenuSection] = []
@export var heroes: Array[CharacterStats] = []        ## en el orden en que se dibujan los pasaportes (izquierda a derecha)
@export var key_items: Array[KeyItemDef] = []
## Ranuras de equipo: { "id": el mismo que el Slot de las piezas GearDef, "name": lo que se ve }
@export var gear_slots: Array[Dictionary] = [{"id": &"boots", "name": "Zapatos"}, {"id": &"hammer", "name": "Martillo"}, {"id": &"shirt", "name": "Camisa"}]
## Iconos propios por objeto consumible (id -> Texture2D). Los que falten usan un dibujo provisional.
@export var item_icons: Dictionary = {}
@export var ribbon_names: Dictionary = {&"blue": "Listón azul", &"silver": "Listón de plata", &"gold": "Listón de oro"}
@export var ribbon_colors: Dictionary = {&"blue": Color("3a70e0"), &"silver": Color("d5dde9"), &"gold": Color("f7c531")}
@export_group("General")
@export var design_size: Vector2 = Vector2(640, 410)   ## lienzo de diseño: el menú se escala para llenar la pantalla
@export var pause_game: bool = true                    ## congela el overworld mientras está abierto
@export var show_coins: bool = true
@export var show_time: bool = true
@export var enabled: bool = true                       ## false = Enter no abre el menú (p. ej. durante una escena propia)
@export_group("Acciones (Input Map)")
@export var open_action: StringName = &"menu"
@export var back_action: StringName = &"cancel"
@export var left_action: StringName = &"ui_left"
@export var right_action: StringName = &"ui_right"
@export var up_action: StringName = &"ui_up"
@export var down_action: StringName = &"ui_down"
@export_group("Ayuda de teclas (abajo a la derecha)")
@export var hint_sections := "↑↓ elegir · Z abrir · C / Enter cerrar"
@export var hint_items := "↑↓ elegir · Z usar · C volver"
@export var hint_items_target := "↑↓ ◄► hermano · Z dar · C volver"
@export var hint_gear := "◄► hermano · ↑↓ pieza · Z cambiar · C volver"
@export var hint_gear_pick := "↑↓ elegir · Z equipar · C volver"
@export var hint_badges := "◄► hermano · Z cambiar medallas · C volver"
@export var hint_badges_pick := "↑↓ elegir · Z poner / quitar · C volver"
@export var hint_stats := "◄► hermano · ↑↓ estadística · C volver"
@export var hint_map := "C volver · Enter cerrar"

var is_open: bool = false
var canvas: Control

var _sec: int = 0
var _in_sec: bool = false
var _idx: int = 0
var _hero: int = 0
var _stage: StringName = &"list"   # list | target | pick
var _pick: int = 0
var _note_t: float = 0.0
var _note_text: String = ""
var _t: int = 0
var _open_t: int = 0
var _open_frame: int = -1
var _close_frame: int = -100
var _secs: Array[MenuSection] = []
var _roster: Array[CharacterStats] = []   # lista completa de Heroes mientras el menú está abierto con menos hermanos
var _bold: FontVariation
var _base: Transform2D = Transform2D.IDENTITY
var _fit: float = 1.0

const RIBBON_ORDER: Array[StringName] = [&"blue", &"silver", &"gold"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	if style == null:
		style = MenuStyle.new()
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw.connect(_paint)
	add_child(canvas)
	visible = false

# ---------------------------------------------- abrir / cerrar ----------------------------------------------

## ¿Se puede abrir ahora? (overworld, sin diálogo, cinemática ni cambio de habitación)
func can_open() -> bool:
	if not enabled or is_open or get_tree().paused or heroes.is_empty():
		return false
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path == GameState.BATTLE_SCENE:
		return false
	if get_tree().get_nodes_in_group("overworld_heroes").is_empty():
		return false
	var dm := get_node_or_null("/root/DialogueManager")
	if dm != null and (bool(dm.call("blocks_input")) or bool(dm.call("is_talking"))):
		return false
	var st := get_node_or_null("/root/SceneTransition")
	return st == null or not bool(st.get("busy"))

func open() -> void:
	if not can_open():
		return
	_secs.clear()
	for s in sections:
		if s != null and s.enabled:
			_secs.append(s)
	if _secs.is_empty():
		return
	# Solo salen los hermanos que andan en esta parte de la historia (GameState.party): sin pasaporte ni datos del que falta.
	if _roster.is_empty():
		_roster = heroes.duplicate()
	var present: Array[CharacterStats] = []
	for h in _roster:
		if GameState.has_hero(h.id):
			present.append(h)
	if present.is_empty():
		return
	heroes = present
	_sec = clampi(_sec, 0, _secs.size() - 1)
	_in_sec = false
	_stage = &"list"
	_note_t = 0.0
	_t = 0
	_open_t = 0
	_open_frame = Engine.get_process_frames()
	is_open = true
	visible = true
	if pause_game:
		get_tree().paused = true
	opened.emit()
	canvas.queue_redraw()

func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	if not _roster.is_empty():
		heroes = _roster.duplicate()   # lista completa otra vez (la próxima apertura vuelve a filtrar)
		_roster.clear()
	_close_frame = Engine.get_physics_frames()
	if pause_game:
		get_tree().paused = false
	closed.emit()

## ¿Se cerró hace un instante? (los héroes lo usan para que la tecla que cierra no haga saltar)
func recently_closed() -> bool:
	return Engine.get_physics_frames() - _close_frame <= 3

func _process(delta: float) -> void:
	if not is_open:
		if Input.is_action_just_pressed(open_action):
			open()
		return
	_t += 1
	_open_t += 1
	if _note_t > 0.0:
		_note_t -= delta
	_update()
	if is_open:
		canvas.queue_redraw()

# ---------------------------------------------- datos ----------------------------------------------

func _wrap_i(i: int, n: int) -> int:
	return ((i % n) + n) % n

func _hid(i: int) -> StringName:
	return heroes[i].id

func _kind() -> String:
	return _secs[_sec].kind

func _note(text: String) -> void:
	_note_text = text
	_note_t = style.note_seconds

func _inv(id: StringName) -> int:
	return int(GameState.inventory.get(id, 0))

func _item_rows() -> Array:
	var rows: Array = []
	for id in BattleItems.ORDER:
		rows.append({"kind": &"use", "id": id})
	for id in RIBBON_ORDER:
		rows.append({"kind": &"ribbon", "id": id})
	for k in key_items:
		if k != null:
			rows.append({"kind": &"key", "k": k})
	return rows

## Un héroe temporal (sin escena) para reutilizar las reglas de objetos del combate (BattleItems).
func _tmp_hero(i: int) -> BattleHero:
	var h := BattleHero.new()
	h.stats = heroes[i]
	h.setup(GameState.hp_of(heroes[i]), GameState.tp_of(heroes[i]))
	return h

func _store_hero(i: int, h: BattleHero) -> void:
	GameState.hero_hp[heroes[i].id] = h.hp
	GameState.hero_tp[heroes[i].id] = h.tp
	GameState.changed.emit()

func _can_use(id: StringName, i: int) -> bool:
	var h := _tmp_hero(i)
	var r := BattleItems.can_use(id, h)
	h.free()
	return r

func _stats_of(i: int) -> Dictionary:
	var s := heroes[i]
	return {"hp": GameState.hp_of(s), "max_hp": s.max_hp, "tp": GameState.tp_of(s), "max_tp": s.max_tp,
		"power": s.power + GameState.gear_bonus(s.id, &"power"), "defense": s.defense + GameState.gear_bonus(s.id, &"defense"),
		"speed": s.turn_speed, "stache": s.stache}

func _stat_rows() -> Array:
	return [
		{"k": &"hp", "label": style.t_hp},
		{"k": &"tp", "label": style.t_tp},
		{"k": &"power", "label": style.t_power},
		{"k": &"defense", "label": style.t_defense},
		{"k": &"speed", "label": style.t_speed},
		{"k": &"stache", "label": style.t_stache},
	]

func _stat_desc(i: int, k: StringName) -> String:
	var s := heroes[i]
	var st := _stats_of(i)
	match k:
		&"hp": return "Puntos de vida. Si llegan a 0, el hermano cae en combate."
		&"tp": return "Puntos tándem. Se gastan al usar ataques Bros."
		&"power": return "Aumenta el daño de saltos, martillazos y ataques Bros. Base %d + equipo %d." % [s.power, GameState.gear_bonus(s.id, &"power")]
		&"defense": return "Reduce el daño que hacen los enemigos (y los pinchos). Base %d + equipo %d." % [s.defense, GameState.gear_bonus(s.id, &"defense")]
		&"speed": return "Decide el orden de los turnos en combate: actúa antes quien tenga más."
		&"stache": return "Probabilidad de golpe crítico (daño x1,5): %d %%. Descuento en tiendas: %d %%." % [st["stache"], floori(int(st["stache"]) / 2.0)]
	return ""

func _gear_options(i: int, slot: StringName) -> Array:   # índices de GameState.gear_bag; -1 = quitarse la pieza
	var o: Array = [-1]
	for n in GameState.gear_bag.size():
		var g: Dictionary = GameState.gear_bag[n]
		var d := GameState.gear_def(g["id"])
		if d != null and d.slot == slot and (g["by"] == &"" or g["by"] == _hid(i)):
			o.append(n)
	return o

func _gear_text(d: GearDef) -> String:
	var p: Array = []
	if d.power != 0:
		p.append("FUE%+d" % d.power)
	if d.defense != 0:
		p.append("DEF%+d" % d.defense)
	return " ".join(p)

func _badge_name(b: Dictionary) -> String:
	var d := GameState.badge_def(b["id"])
	return d.display_name if d != null else String(b["id"])

func _hero_name(id: StringName) -> String:
	for h in heroes:
		if h.id == id:
			return h.display_name
	return String(id)

# ---------------------------------------------- lógica de los menús ----------------------------------------------

func _confirm_pressed() -> bool:
	for h in heroes:
		if Input.is_action_just_pressed(h.jump_action):
			return true
	return false

func _update() -> void:
	var ok := _confirm_pressed()
	var back := Input.is_action_just_pressed(back_action)
	var ud := int(Input.is_action_just_pressed(down_action)) - int(Input.is_action_just_pressed(up_action))
	var lr := int(Input.is_action_just_pressed(right_action)) - int(Input.is_action_just_pressed(left_action))
	if Input.is_action_just_pressed(open_action) and Engine.get_process_frames() != _open_frame:
		close()
		return
	var n_heroes := heroes.size()
	if not _in_sec:
		if ud != 0:
			_sec = _wrap_i(_sec + ud, _secs.size())
		if back:
			close()
		elif ok:
			_in_sec = true
			_idx = 0
			_hero = 0
			_stage = &"list"
			_pick = 0
			_note_t = 0.0
		return
	match _kind():
		"items":
			var rows := _item_rows()
			_idx = clampi(_idx, 0, rows.size() - 1)
			var row: Dictionary = rows[_idx]
			if _stage == &"list":
				if ud != 0:
					_idx = _wrap_i(_idx + ud, rows.size())
				if back:
					_leave()
					return
				if ok:
					_items_use(row)
			else:   # elegir a quién dárselo
				if ud != 0 or lr != 0:
					_hero = _wrap_i(_hero + (ud if ud != 0 else lr), n_heroes)
				if back:
					_stage = &"list"
					return
				if ok:
					var id: StringName = row["id"]
					var h := _tmp_hero(_hero)
					if not BattleItems.can_use(id, h):
						_note(BattleItems.why_not(id, h))
					else:
						GameState.inventory[id] = _inv(id) - 1
						var r := BattleItems.apply(id, h)
						_store_hero(_hero, h)
						_note("%s usa %s: %s." % [h.display_name, BattleItems.item_name(id), r])
						_stage = &"list"
					h.free()
		"gear":
			var slot: StringName = gear_slots[clampi(_idx, 0, gear_slots.size() - 1)]["id"]
			if _stage == &"list":
				if lr != 0:
					_hero = _wrap_i(_hero + lr, n_heroes)
				if ud != 0:
					_idx = _wrap_i(_idx + ud, gear_slots.size())
				if back:
					_leave()
					return
				if ok:
					_stage = &"pick"
					var opts := _gear_options(_hero, slot)
					_pick = maxi(0, opts.find(GameState.equipped_index(_hid(_hero), slot)))
			else:
				var opts2 := _gear_options(_hero, slot)
				_pick = clampi(_pick, 0, opts2.size() - 1)
				if ud != 0:
					_pick = _wrap_i(_pick + ud, opts2.size())
				if back:
					_stage = &"list"
					return
				if ok:
					var cur := GameState.equipped_index(_hid(_hero), slot)
					var g: int = opts2[_pick]
					if cur >= 0:
						GameState.gear_bag[cur]["by"] = &""
					if g >= 0:
						GameState.gear_bag[g]["by"] = _hid(_hero)
					var who := heroes[_hero].display_name
					if g >= 0:
						_note("%s se equipa %s." % [who, GameState.gear_def(GameState.gear_bag[g]["id"]).display_name])
					else:
						_note("%s se quita %s." % [who, GameState.gear_def(GameState.gear_bag[cur]["id"]).display_name if cur >= 0 else "nada"])
					GameState.changed.emit()
					_stage = &"list"
		"stats":
			if lr != 0:
				_hero = _wrap_i(_hero + lr, n_heroes)
			if ud != 0:
				_idx = _wrap_i(_idx + ud, _stat_rows().size())
			if back:
				_leave()
		"badges":
			var bag := GameState.badge_bag
			var nm := heroes[_hero].display_name
			if _stage == &"list":
				if lr != 0:
					_hero = _wrap_i(_hero + lr, n_heroes)
				if back:
					_leave()
					return
				if ok:
					if bag.is_empty():
						_note("Todavía no tenéis medallas. Se venden en la tienda del castillo.")
					else:
						_stage = &"pick"
						_pick = 0
			else:   # elegir qué medalla poner / quitar a este hermano
				_pick = clampi(_pick, 0, maxi(bag.size() - 1, 0))
				if ud != 0:
					_pick = _wrap_i(_pick + ud, bag.size())
				if back:
					_stage = &"list"
					return
				if ok:
					var b: Dictionary = bag[_pick]
					var cost := int(b["bp"])
					var bname := _badge_name(b)
					if b["by"] == _hid(_hero):
						b["by"] = &""
						_note("%s se quita %s (recupera %d PM: %d/%d libres)." % [nm, bname, cost, GameState.bp_left(), GameState.bp_max])
					elif b["by"] != &"":
						_note("La lleva %s. Quítasela primero." % _hero_name(b["by"]))
					elif GameState.bp_left() < cost:
						_note("Faltan puntos de medalla: cuesta %d PM y solo quedan %d libres. Quitad otra medalla o buscad más listones." % [cost, GameState.bp_left()])
					else:
						b["by"] = _hid(_hero)
						_note("%s se pone %s (%d PM): quedan %d/%d PM libres." % [nm, bname, cost, GameState.bp_left(), GameState.bp_max])
					GameState.changed.emit()
		_:   # mapa
			if back:
				_leave()

func _leave() -> void:
	_in_sec = false
	_note_t = 0.0

func _items_use(row: Dictionary) -> void:
	var kind: StringName = row["kind"]
	if kind == &"key":
		_note("Los objetos clave no se usan: solo se consultan.")
	elif kind == &"ribbon":   # listón: se gasta y aumenta los PM comunes
		var id: StringName = row["id"]
		if not GameState.use_ribbon(id):
			_note("No te quedan %s." % ribbon_names.get(id, id))
		else:
			_note("¡Usáis %s! +%d PM: ahora tenéis %d PM en total." % [ribbon_names.get(id, id), GameState.RIBBON_BP[id], GameState.bp_max])
	else:
		var id2: StringName = row["id"]
		if _inv(id2) <= 0:
			_note("No te quedan %s." % BattleItems.item_name(id2))
			return
		var first := -1
		for i in heroes.size():
			if _can_use(id2, i):
				first = i
				break
		if first < 0:
			_note("Fuera de combate nadie está caído: guárdalo para las batallas." if id2 == &"oneup" else String(BattleItems.DEFS[id2]["none"]))
		else:
			_stage = &"target"
			_hero = first

func _desc() -> String:
	if _note_t > 0.0:
		return _note_text
	var S := _secs[_sec]
	if not _in_sec:
		return S.description
	match S.kind:
		"items":
			var rows := _item_rows()
			var row: Dictionary = rows[clampi(_idx, 0, rows.size() - 1)]
			if row["kind"] == &"key":
				return "%s — %s" % [row["k"].display_name, row["k"].description]
			if row["kind"] == &"ribbon":
				var rid: StringName = row["id"]
				return "%s (te quedan %d) — Con Z lo usáis para aumentar en %d los puntos de medalla (PM) que compartís. Ahora: %d PM." % [ribbon_names.get(rid, rid), int(GameState.ribbon_inv.get(rid, 0)), GameState.RIBBON_BP[rid], GameState.bp_max]
			var iid: StringName = row["id"]
			if _stage == &"target":
				var s := heroes[_hero]
				return "¿A quién le das %s? %s: PV %d/%d · PT %d/%d." % [BattleItems.item_name(iid), s.display_name, GameState.hp_of(s), s.max_hp, GameState.tp_of(s), s.max_tp]
			return "%s (te quedan %d) — %s" % [BattleItems.item_name(iid), _inv(iid), BattleItems.DEFS[iid]["desc"]]
		"gear":
			var slot: Dictionary = gear_slots[clampi(_idx, 0, gear_slots.size() - 1)]
			var cur := GameState.equipped_index(_hid(_hero), slot["id"])
			var cd := GameState.gear_def(GameState.gear_bag[cur]["id"]) if cur >= 0 else null
			var who := heroes[_hero].display_name
			if _stage == &"list":
				return "%s de %s: %s" % [slot["name"], who, ("%s — %s" % [cd.display_name, cd.description]) if cd != null else "nada equipado."]
			var opts := _gear_options(_hero, slot["id"])
			var gi: int = opts[clampi(_pick, 0, opts.size() - 1)]
			var gd := GameState.gear_def(GameState.gear_bag[gi]["id"]) if gi >= 0 else null
			var st := _stats_of(_hero)
			var dp := (gd.power if gd else 0) - (cd.power if cd else 0)
			var dd := (gd.defense if gd else 0) - (cd.defense if cd else 0)
			return "%s  Fuerza %d → %d · Defensa %d → %d." % [("%s — %s" % [gd.display_name, gd.description]) if gd else "Quitarse la pieza actual.", st["power"], int(st["power"]) + dp, st["defense"], int(st["defense"]) + dd]
		"stats":
			var r: Dictionary = _stat_rows()[clampi(_idx, 0, 5)]
			return "%s — %s: %s" % [heroes[_hero].display_name, r["label"], _stat_desc(_hero, r["k"])]
		"badges":
			var bag := GameState.badge_bag
			var nm := heroes[_hero].display_name
			if _stage == &"pick" and not bag.is_empty():
				var b: Dictionary = bag[clampi(_pick, 0, bag.size() - 1)]
				var bd := GameState.badge_def(b["id"])
				return "%s — %s Cuesta %d PM; quedan %d de %d PM libres." % [_badge_name(b), bd.description if bd else "", int(b["bp"]), GameState.bp_left(), GameState.bp_max]
			if bag.is_empty():
				return "Todavía no tenéis medallas. Se venden en la tienda del castillo."
			return "PM comunes: %d de %d en uso. Z para poner o quitar medallas de %s. Listones sin usar: %d azul, %d plata, %d oro (en Objetos)." % [GameState.bp_used(), GameState.bp_max, nm, int(GameState.ribbon_inv.get(&"blue", 0)), int(GameState.ribbon_inv.get(&"silver", 0)), int(GameState.ribbon_inv.get(&"gold", 0))]
	return "%s — la zona actual. Las marcas de colores sois vosotros; los círculos rosas, los NPC; lo dorado, las puertas." % _room_name()

func _hint() -> String:
	if not _in_sec:
		return hint_sections
	match _kind():
		"items": return hint_items if _stage == &"list" else hint_items_target
		"gear": return hint_gear if _stage == &"list" else hint_gear_pick
		"badges": return hint_badges if _stage == &"list" else hint_badges_pick
		"stats": return hint_stats
	return hint_map

func _room_name() -> String:
	var scene := get_tree().current_scene
	if scene != null:
		var v: Variant = scene.get("room_name")
		if v != null and String(v) != "":
			return String(v)
		return String(scene.name).capitalize()
	return style.t_unknown_room

# ---------------------------------------------- dibujo: utilidades ----------------------------------------------

func _font() -> Font:
	return style.font if style.font != null else ThemeDB.fallback_font

func _bold_font() -> Font:
	if _bold == null or _bold.base_font != _font():
		_bold = FontVariation.new()
		_bold.base_font = _font()
		_bold.variation_embolden = 0.5
	return _bold

## Texto en coordenadas del lienzo de diseño. (x, y) = línea de base; align: 0 izquierda, 1 centro, 2 derecha.
func _txt(s: String, x: float, y: float, size: float, col: Color, align: int = 0, bold: bool = false) -> void:
	var f: Font = _bold_font() if bold else _font()
	var fs := maxi(1, roundi(size * style.font_scale))
	var w := 600.0
	var px := x
	var ha := HORIZONTAL_ALIGNMENT_LEFT
	if align == 1:
		px = x - w * 0.5
		ha = HORIZONTAL_ALIGNMENT_CENTER
	elif align == 2:
		px = x - w
		ha = HORIZONTAL_ALIGNMENT_RIGHT
	canvas.draw_string(f, Vector2(px, y), s, ha, w, fs, col)

## Números amarillos con borde oscuro (como en los pasaportes).
func _num(s: String, x: float, y: float, size: float, align: int = 2) -> void:
	var f := _bold_font()
	var fs := maxi(1, roundi(size * style.font_scale))
	var w := 300.0
	var px := x
	var ha := HORIZONTAL_ALIGNMENT_LEFT
	if align == 1:
		px = x - w * 0.5
		ha = HORIZONTAL_ALIGNMENT_CENTER
	elif align == 2:
		px = x - w
		ha = HORIZONTAL_ALIGNMENT_RIGHT
	canvas.draw_string_outline(f, Vector2(px, y), s, ha, w, fs, 4, style.number_outline)
	canvas.draw_string(f, Vector2(px, y), s, ha, w, fs, style.number_fill)

func _text_w(s: String, size: float, bold: bool = false) -> float:
	var f: Font = _bold_font() if bold else _font()
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(1, roundi(size * style.font_scale))).x

func _wrap(text: String, max_w: float, size: float) -> Array[String]:
	var lines: Array[String] = []
	var cur := ""
	for word in text.split(" "):
		var tryl := word if cur == "" else cur + " " + word
		if _text_w(tryl, size) > max_w and cur != "":
			lines.append(cur)
			cur = word
		else:
			cur = tryl
	if cur != "":
		lines.append(cur)
	return lines

func _rr_pts(r: Rect2, rad: float) -> PackedVector2Array:
	rad = clampf(rad, 0.0, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [r.position + Vector2(rad, rad), Vector2(r.end.x - rad, r.position.y + rad), r.end - Vector2(rad, rad), Vector2(r.position.x + rad, r.end.y - rad)]
	for c in 4:
		for k in 7:
			var a := PI + c * PI * 0.5 + k * (PI * 0.5 / 6.0)
			pts.append(corners[c] + Vector2(cos(a), sin(a)) * rad)
	return pts

func _rr(r: Rect2, rad: float, fill: Color, border: Color = Color(0, 0, 0, 0), bw: float = 0.0) -> void:
	var pts := _rr_pts(r, rad)
	if fill.a > 0.0:
		canvas.draw_colored_polygon(pts, fill)
	if border.a > 0.0 and bw > 0.0:
		pts.append(pts[0])
		canvas.draw_polyline(pts, border, bw, true)

func _ellipse(c: Vector2, rx: float, ry: float, fill: Color, border: Color = Color(0, 0, 0, 0), bw: float = 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * i / 28.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	canvas.draw_colored_polygon(pts, fill)
	if border.a > 0.0 and bw > 0.0:
		pts.append(pts[0])
		canvas.draw_polyline(pts, border, bw, true)

func _tex(t: Texture2D, r: Rect2) -> void:
	if t != null:
		canvas.draw_texture_rect(t, r, false)

func _arrow_right(x: float, y: float, h: float) -> void:   # flecha amarilla que señala a la derecha (centro vertical y)
	var pts := PackedVector2Array([Vector2(x, y - h * 0.5), Vector2(x + h * 0.75, y), Vector2(x, y + h * 0.5)])
	canvas.draw_colored_polygon(pts, style.arrow_fill)
	pts.append(pts[0])
	canvas.draw_polyline(pts, style.arrow_outline, 2.0, true)

func _hero_main(i: int) -> Color:
	return heroes[i].shirt_color

func _hero_dark(i: int) -> Color:
	return heroes[i].shirt_color.darkened(0.45)

func _hero_soft(i: int) -> Color:
	var c := heroes[i].shirt_color.lightened(0.6)
	c.a = style.passport_pill_alpha
	return c

func _set_xf(local: Transform2D) -> void:
	canvas.draw_set_transform_matrix(_base * local)

# ---------------------------------------------- dibujo: marco y estructura ----------------------------------------------

func _paint() -> void:
	if not is_open or _secs.is_empty():
		return
	var sz := canvas.size
	_fit = minf(sz.x / design_size.x, sz.y / design_size.y)
	var k := 1.0
	if style.open_frames > 0:
		var p := clampf(float(_open_t) / float(style.open_frames), 0.0, 1.0)
		k = 1.0 - (1.0 - p) * (1.0 - p)
	var sc := _fit * lerpf(style.open_start_scale, 1.0, k)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	canvas.modulate = Color(1, 1, 1, k)
	_draw_frame(sz, _fit)
	var origin := (sz - design_size * sc) * 0.5
	_base = Transform2D(Vector2(sc, 0), Vector2(0, sc), origin)
	_set_xf(Transform2D.IDENTITY)
	var W := design_size.x
	# Arriba: monedas (centro) y tiempo jugado (derecha)
	if show_coins:
		_draw_coins(232.0)
	if show_time:
		_draw_clock(W)
	# Izquierda: apartados
	for i in _secs.size():
		_draw_section_tab(i)
	# Centro: contenido
	if not _in_sec:
		_draw_home()
	else:
		match _kind():
			"items": _draw_items()
			"gear": _draw_gear()
			"badges": _draw_badges()
			"stats": _draw_stats()
			_: _draw_map()
	# Abajo: descripción de lo seleccionado
	_rr(Rect2(16, 346, W - 32, 62), 10, style.pill_bg, style.pill_border, 3)
	var col := style.text_note if _note_t > 0.0 else style.text_light
	var lines := _wrap(_desc(), W - 60, 13)
	for i in mini(2, lines.size()):
		_txt(lines[i], 30, 368 + i * 17, 13, col)
	_txt(_hint(), W - 28, 402, 10, style.text_keys, 2)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	canvas.modulate = Color.WHITE

func _draw_frame(sz: Vector2, s: float) -> void:
	if style.background_texture != null:
		canvas.draw_texture_rect(style.background_texture, Rect2(Vector2.ZERO, sz), false)
		return
	canvas.draw_rect(Rect2(Vector2.ZERO, sz), style.frame_dark)
	_rr(Rect2(Vector2(5, 5) * s, sz - Vector2(10, 10) * s), 14.0 * s, style.frame_wood)
	var cloth := Rect2(Vector2(11, 11) * s, sz - Vector2(22, 22) * s)
	canvas.draw_rect(cloth, style.cloth_base)
	var x := cloth.position.x
	while x < cloth.end.x:
		canvas.draw_rect(Rect2(x, cloth.position.y, minf(15.0 * s, cloth.end.x - x), cloth.size.y), style.cloth_stripe)
		x += 30.0 * s
	if style.cloth_checks:
		var y := cloth.position.y
		while y < cloth.end.y:
			canvas.draw_rect(Rect2(cloth.position.x, y, cloth.size.x, minf(15.0 * s, cloth.end.y - y)), style.cloth_stripe)
			y += 30.0 * s

func _draw_coins(x: float) -> void:
	_rr(Rect2(x, 16, 176, 38), 19, style.pill_bg, style.pill_border, 3)
	_ellipse(Vector2(x + 30, 35), 10, 13, Color("f0b732"), Color("7a4a10"), 2)
	canvas.draw_rect(Rect2(x + 28, 28, 4, 14), Color("7a4a10"))
	_num(str(GameState.coins), x + 158, 44, 22)

func _draw_clock(W: float) -> void:
	_rr(Rect2(W - 178, 16, 158, 38), 19, Color("f4ecd0"), Color("a07a2a"), 3)
	var c := Vector2(W - 156, 35)
	canvas.draw_arc(c, 10, 0, TAU, 24, Color("3b2a00"), 2.0, true)
	var ang := fmod(GameState.play_time, 60.0) / 60.0 * TAU
	canvas.draw_line(c, c + Vector2(sin(ang), -cos(ang)) * 7.0, Color("3b2a00"), 2.0, true)
	var t := int(GameState.play_time)
	_txt("%02d:%02d:%02d" % [floori(t / 3600.0), floori(t / 60.0) % 60, t % 60], W - 32, 42, 18, Color("3b2a00"), 2, true)

func _draw_section_tab(i: int) -> void:
	var S := _secs[i]
	var y := 64.0 + i * 56.0
	var sel := _sec == i
	var fill := Color(1, 1, 1, 0.75 if sel else 0.3)
	_rr(Rect2(22, y, 78, 50), 10, fill, (style.cursor_outline_inside if _in_sec else style.cursor_outline) if sel else Color(0, 0, 0, 0), 3)
	if S.icon != null:
		_tex(S.icon, Rect2(61 - 14, y + 5, 28, 28))
	else:
		_section_icon(S.kind, 61, y + 19)
	_txt(S.display_name, 61, y + 44, 10, style.text_dark, 1, true)
	if sel and not _in_sec:
		_arrow_right(8.0 + sin(_t / 8.0) * 2.0, y + 25, 22)

# ---------------------------------------------- dibujo: iconos ----------------------------------------------

func _section_icon(kind: String, cx: float, cy: float) -> void:
	match kind:
		"items":
			_item_icon(&"mushroom", Rect2(cx - 11, cy - 11, 22, 22))
		"gear":
			canvas.draw_line(Vector2(cx - 9, cy + 11), Vector2(cx + 3, cy - 3), Color("8a5a2b"), 4.0, true)
			_rr(Rect2(cx - 3, cy - 13, 17, 12), 3, Color("9aa3ad"), Color("3a3f45"), 2)
		"badges":
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(cx - 7, cy - 13), Vector2(cx - 1, cy - 1), Vector2(cx - 10, cy - 1)]), Color("3a6fd8"))
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(cx + 7, cy - 13), Vector2(cx + 1, cy - 1), Vector2(cx + 10, cy - 1)]), Color("e0473f"))
			_ellipse(Vector2(cx, cy + 4), 8, 8, Color("f0b732"), Color("7a4a10"), 2)
			_ellipse(Vector2(cx - 2, cy + 2), 2.5, 2.5, Color("fff4b8"))
		"stats":
			_rr(Rect2(cx - 13, cy - 10, 16, 20), 3, Color("43b047"))
			_rr(Rect2(cx - 3, cy - 10, 16, 20), 3, Color("e0473f"))
			canvas.draw_rect(Rect2(cx + 2, cy - 6, 7, 8), Color.WHITE)
		_:
			var pts := PackedVector2Array([Vector2(cx - 13, cy - 8), Vector2(cx - 4, cy - 11), Vector2(cx + 4, cy - 8), Vector2(cx + 13, cy - 11), Vector2(cx + 13, cy + 9), Vector2(cx + 4, cy + 12), Vector2(cx - 4, cy + 9), Vector2(cx - 13, cy + 12)])
			canvas.draw_colored_polygon(pts, Color("f3e3b0"))
			pts.append(pts[0])
			canvas.draw_polyline(pts, Color("7a5a2a"), 1.5, true)
			canvas.draw_line(Vector2(cx + 3, cy + 1), Vector2(cx + 10, cy + 8), Color("e0473f"), 2.0)
			canvas.draw_line(Vector2(cx + 10, cy + 1), Vector2(cx + 3, cy + 8), Color("e0473f"), 2.0)

## Icono de un consumible (22x22). Si hay textura propia en Item Icons, se usa esa.
func _item_icon(id: StringName, r: Rect2) -> void:
	if item_icons.get(id) is Texture2D:
		_tex(item_icons[id], r)
		return
	var c := r.get_center()
	match id:
		&"mushroom", &"oneup":
			var cap := Color("e0473f") if id == &"mushroom" else Color("43b047")
			_rr(Rect2(c.x - 5, c.y + 1, 10, 9), 3, Color("f6e8c8"), Color("7a5a2a"), 1.5)
			_ellipse(Vector2(c.x, c.y - 1), 10, 8, cap, Color("26314a"), 1.5)
			_ellipse(Vector2(c.x - 4, c.y - 3), 2.2, 2.2, Color.WHITE)
			_ellipse(Vector2(c.x + 4, c.y - 2), 2.2, 2.2, Color.WHITE)
		&"syrup":
			_rr(Rect2(c.x - 6, c.y - 3, 12, 14), 4, Color("d98a1c"), Color("7a4a10"), 1.5)
			_rr(Rect2(c.x - 3, c.y - 10, 6, 8), 2, Color("f6e8c8"), Color("7a4a10"), 1.5)
		_:
			_rr(r.grow(-2), 5, Color("9aa6b8"), Color("26314a"), 1.5)
			_txt(String(id).left(1).to_upper(), c.x, c.y + 4, 11, Color.WHITE, 1, true)

func _ribbon_icon(cx: float, cy: float, id: StringName, s: float) -> void:
	var col: Color = ribbon_colors.get(id, Color.WHITE)
	var dark := col.darkened(0.45)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(cx, cy), Vector2(cx - 7 * s, cy + 12 * s), Vector2(cx - 1 * s, cy + 9 * s)]), dark)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(cx, cy), Vector2(cx + 7 * s, cy + 12 * s), Vector2(cx + 1 * s, cy + 9 * s)]), dark)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(cx, cy), Vector2(cx - 10 * s, cy - 6 * s), Vector2(cx - 10 * s, cy + 5 * s)]), col)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(cx, cy), Vector2(cx + 10 * s, cy - 6 * s), Vector2(cx + 10 * s, cy + 5 * s)]), col)
	_ellipse(Vector2(cx, cy), 3.5 * s, 3.5 * s, col, dark, 1.5)

# ---------------------------------------------- dibujo: pasaportes ----------------------------------------------

## Empieza el pasaporte del héroe i en (x, y, w, h) con inclinación tilt. Lo que se dibuje después va en coordenadas del pasaporte
## hasta llamar a _end_passport().
func _begin_passport(i: int, x: float, y: float, w: float, h: float, tilt: float) -> void:
	var s := heroes[i]
	var main := _hero_main(i)
	var dark := _hero_dark(i)
	_set_xf(Transform2D(0.0, Vector2(x + w / 2.0, y + h / 2.0)) * Transform2D(tilt, Vector2.ZERO) * Transform2D(0.0, Vector2(-w / 2.0, -h / 2.0)))
	_rr(Rect2(7, -5, w - 2, h), 12, style.passport_paper)
	_rr(Rect2(3, 4, w, h), 14, Color(0, 0, 0, 0.18))
	_rr(Rect2(0, 0, w, h), 14, main, dark, 3)
	_txt(style.t_passport, 16, 20, 10, dark, 0, true)
	_rr(Rect2(12, 26, 118, 24), 12, dark)
	_txt(s.display_name.to_upper(), 71, 44, 15, Color.WHITE, 1, true)
	var lv := int(GameState.hero_level.get(s.id, 1))
	_txt(style.t_level, 30, 78, 12, dark, 0, true)
	_num(str(lv), 74, 80, 22)
	_txt("%s %d / %d" % [style.t_exp, int(GameState.hero_exp.get(s.id, 0)), GameState.exp_need(lv)], 16, 100, 10, dark, 0, true)
	canvas.draw_rect(Rect2(w - 80, 10, 66, 78), style.passport_photo_bg)
	canvas.draw_rect(Rect2(w - 80, 10, 66, 78), Color("8a7a50"), false, 2.0)
	var photo := Rect2(w - 76, 14, 58, 70)
	canvas.draw_rect(photo, main.lightened(0.7))
	if s.portrait != null:
		var ts := s.portrait.get_size()
		var f := minf(photo.size.x / ts.x, photo.size.y / ts.y) * s.portrait_scale
		var rs := ts * f
		_tex(s.portrait, Rect2(Vector2(photo.get_center().x - rs.x * 0.5, photo.end.y - rs.y - 2) + s.portrait_offset, rs))
	else:
		_ellipse(Vector2(photo.get_center().x, photo.position.y + 22), 13, 13, Color("f4c9a0"))
		_rr(Rect2(photo.get_center().x - 17, photo.position.y + 36, 34, 30), 6, main)

func _end_passport() -> void:
	_set_xf(Transform2D.IDENTITY)

func _passport_x(i: int) -> float:
	if heroes.size() == 1:
		return 249.0   # un solo pasaporte: centrado en la zona de contenido (a la derecha de los apartados)
	return 122.0 + i * 254.0

func _tilt_of(i: int) -> float:
	return style.passport_tilt if i % 2 == 1 else -style.passport_tilt

# ---------------------------------------------- dibujo: apartados ----------------------------------------------

func _draw_home() -> void:   # portada: los pasaportes con nivel, PV y PT
	for i in heroes.size():
		_begin_passport(i, _passport_x(i), 70, 240, 266, _tilt_of(i))
		var st := _stats_of(i)
		var dark := _hero_dark(i)
		var pairs: Array = [[style.t_hp, "%d / %d" % [st["hp"], st["max_hp"]]], [style.t_tp, "%d / %d" % [st["tp"], st["max_tp"]]]]
		for r in 2:
			var y := 132.0 + r * 54.0
			_rr(Rect2(10, y - 24, 220, 36), 16, _hero_soft(i))
			_txt(pairs[r][0], 22, y, 14, dark, 0, true)
			_num(pairs[r][1], 218, y + 2, 22)
		_txt("%s %d  ·  %s %d" % [style.t_power, st["power"], style.t_defense, st["defense"]], 120, 236, 11, dark, 1, true)
		_end_passport()

func _draw_stats() -> void:
	var rows := _stat_rows()
	for i in heroes.size():
		_begin_passport(i, _passport_x(i), 70, 240, 266, _tilt_of(i))
		var st := _stats_of(i)
		for j in rows.size():
			var k: StringName = rows[j]["k"]
			var v := "%d/%d" % [st["hp"], st["max_hp"]] if k == &"hp" else ("%d/%d" % [st["tp"], st["max_tp"]] if k == &"tp" else str(st[k]))
			var bonus := GameState.gear_bonus(_hid(i), k) if (k == &"power" or k == &"defense") else 0
			var y := 118.0 + j * 26.0
			_rr(Rect2(10, y - 17, 220, 24), 12, _hero_soft(i), Color.WHITE if (_hero == i and _idx == j) else Color(0, 0, 0, 0), 3)
			_txt(rows[j]["label"], 20, y, 12, _hero_dark(i), 0, true)
			if bonus != 0:
				_txt("%+d equipo" % bonus, 176, y - 1, 10, Color("fffbe0"), 2, true)
			_num(v, 220, y + 1, 16)
		_end_passport()

func _draw_gear() -> void:
	for i in heroes.size():
		_begin_passport(i, _passport_x(i), 70, 240, 266, _tilt_of(i))
		for j in gear_slots.size():
			var y := 104.0 + j * 40.0
			var ei := GameState.equipped_index(_hid(i), gear_slots[j]["id"])
			var d := GameState.gear_def(GameState.gear_bag[ei]["id"]) if ei >= 0 else null
			var sel := _hero == i and _idx == j
			_rr(Rect2(10, y, 220, 34), 10, _hero_soft(i), Color.WHITE if sel else Color(0, 0, 0, 0), 3)
			_txt(String(gear_slots[j]["name"]).to_upper(), 20, y + 12, 9, _hero_dark(i), 0, true)
			_txt(d.display_name if d != null else style.t_no_gear, 20, y + 28, 12, Color.WHITE, 0, true)
			if d != null:
				_txt(_gear_text(d), 220, y + 28, 10, Color("fffbe0"), 2, true)
		var st := _stats_of(i)
		_txt(style.t_power, 20, 246, 12, _hero_dark(i), 0, true)
		_txt(style.t_defense, 128, 246, 12, _hero_dark(i), 0, true)
		_num(str(st["power"]), 110, 248, 17)
		_num(str(st["defense"]), 220, 248, 17)
		_end_passport()
	if _stage != &"pick":
		return
	var slot: Dictionary = gear_slots[clampi(_idx, 0, gear_slots.size() - 1)]
	var opts := _gear_options(_hero, slot["id"])
	_dim()
	_rr(Rect2(196, 90, 340, 40 + opts.size() * 28), 12, style.panel_bg, style.pill_bg, 3)
	_txt("%s para %s" % [slot["name"], heroes[_hero].display_name], 212, 112, 13, style.pill_bg, 0, true)
	for k in opts.size():
		var y := 138.0 + k * 28.0
		var sel := _pick == k
		if sel:
			_rr(Rect2(206, y - 18, 320, 25), 8, style.select_fill)
		var gi: int = opts[k]
		if gi < 0:
			_txt(style.t_take_off, 216, y, 12, style.text_dark, 0, sel)
			continue
		var g: Dictionary = GameState.gear_bag[gi]
		var d := GameState.gear_def(g["id"])
		_txt(d.display_name + ("  " + style.t_equipped if g["by"] != &"" else ""), 216, y, 12, style.text_dark, 0, sel)
		_txt(_gear_text(d), 516, y, 11, style.text_red, 2, true)

func _dim() -> void:   # oscurece el contenido detrás de una ventana emergente
	_rr(Rect2(108, 62, 516, 278), 10, Color(0, 0, 0, 0.35))

func _draw_items() -> void:
	var rows := _item_rows()
	_rr(Rect2(116, 66, 300, 272), 12, style.panel_bg, style.panel_border, 2)
	var y := 88.0
	for i in rows.size():
		var r: Dictionary = rows[i]
		var kind: StringName = r["kind"]
		var prev: StringName = rows[i - 1]["kind"] if i > 0 else &""
		if i == 0:
			_txt(style.t_consumables.to_upper(), 130, y, 10, Color("8a5a2e"), 0, true)
			y += 8
		elif kind != prev:
			y += 8
			_txt((style.t_ribbons if kind == &"ribbon" else style.t_key_items).to_upper(), 130, y, 10, Color("8a5a2e"), 0, true)
			y += 8
		var sel := _idx == i
		var n := 1
		var nm := ""
		if kind == &"use":
			n = _inv(r["id"])
			nm = BattleItems.item_name(r["id"])
		elif kind == &"ribbon":
			n = int(GameState.ribbon_inv.get(r["id"], 0))
			nm = String(ribbon_names.get(r["id"], r["id"]))
		else:
			nm = r["k"].display_name
		var empty := kind != &"key" and n <= 0
		if sel:
			_rr(Rect2(124, y, 284, 24), 8, style.select_fill_dim if _stage == &"target" else style.select_fill)
		if kind == &"use":
			_item_icon(r["id"], Rect2(132, y + 1, 22, 22))
		elif kind == &"ribbon":
			_ribbon_icon(143, y + 12, r["id"], 0.8)
		elif r["k"].icon != null:
			_tex(r["k"].icon, Rect2(132, y + 1, 22, 22))
		else:
			_section_icon("map" if r["k"].id == &"map" else "stats", 143, y + 12)
		var tc := style.text_dim if empty else style.text_dark
		_txt(nm, 162, y + 17, 12, tc, 0, sel)
		if kind != &"key":
			_txt("x%d" % n, 398, y + 17, 13, tc, 2, true)
		y += 26
	# A la derecha: los hermanos (a quién se le da el objeto)
	for i in heroes.size():
		var s := heroes[i]
		var y0 := 72.0 + i * 134.0
		var sel := _stage == &"target" and _hero == i
		_rr(Rect2(428, y0, 190, 124), 12, _hero_main(i), Color.WHITE if sel else _hero_dark(i), 4 if sel else 2)
		_rr(Rect2(436, y0 + 8, 42, 50), 6, style.passport_photo_bg)
		if s.portrait != null:
			var ts := s.portrait.get_size()
			var f := minf(38.0 / ts.x, 46.0 / ts.y)
			_tex(s.portrait, Rect2(Vector2(457.0 - ts.x * f * 0.5, y0 + 56 - ts.y * f), ts * f))
		_txt(s.display_name, 484, y0 + 26, 14, Color.WHITE, 0, true)
		_txt(style.t_hp, 444, y0 + 78, 12, _hero_dark(i), 0, true)
		_txt(style.t_tp, 444, y0 + 106, 12, _hero_dark(i), 0, true)
		_num("%d / %d" % [GameState.hp_of(s), s.max_hp], 604, y0 + 80, 17)
		_num("%d / %d" % [GameState.tp_of(s), s.max_tp], 604, y0 + 108, 17)
		if sel:
			_arrow_right(412.0 + sin(_t / 8.0) * 2.0, y0 + 62, 16)

func _draw_badges() -> void:   # arriba, UN panel con los PM comunes; debajo, las medallas que lleva cada héroe
	var used := GameState.bp_used()
	var free := GameState.bp_left()
	var bx := 134.0
	var bw := 466.0
	var unit := bw / maxf(1.0, float(GameState.bp_max))
	_rr(Rect2(122, 66, 490, 44), 12, style.panel_bg, style.panel_border, 2)
	_txt(style.t_bp_title, 134, 83, 11, style.text_dark, 0, true)
	_txt("%d / %d en uso  ·  %d libres" % [used, GameState.bp_max, free], 600, 83, 12, Color("7a4a10"), 2, true)
	_rr(Rect2(bx, 90, bw, 12), 6, Color("ece4c8"))
	var x := bx
	for i in heroes.size():
		for b in GameState.badge_bag:
			if b["by"] == _hid(i):
				var wd := unit * int(b["bp"])
				canvas.draw_rect(Rect2(x, 90, wd, 12), _hero_main(i))
				canvas.draw_rect(Rect2(x + wd - 1.5, 90, 1.5, 12), Color(1, 1, 1, 0.7))
				x += wd
	_rr(Rect2(bx, 90, bw, 12), 6, Color(0, 0, 0, 0), style.panel_border, 2)
	for i in heroes.size():
		_begin_passport(i, _passport_x(i), 118, 240, 222, _tilt_of(i) * 0.8)
		var worn: Array = []
		var mine := 0
		for b in GameState.badge_bag:
			if b["by"] == _hid(i):
				worn.append(b)
				mine += int(b["bp"])
		if _hero == i:
			_rr(Rect2(10, 104, 220, 112), 10, Color(0, 0, 0, 0), Color.WHITE, 3)
		if worn.is_empty():
			_txt(style.t_no_badges, 120, 166, 12, Color("fffbe0"), 1, true)
		for j in mini(3, worn.size()):
			var b: Dictionary = worn[j]
			var bd := GameState.badge_def(b["id"])
			var y := 110.0 + j * 34.0
			_rr(Rect2(16, y, 208, 30), 9, _hero_soft(i))
			_badge_icon(bd, Vector2(34, y + 15), 10.0, _hero_dark(i))
			_txt(_badge_name(b).replace("Medalla ", ""), 52, y + 19, 11, Color.WHITE, 0, true)
			_txt("%d PM" % int(b["bp"]), 214, y + 19, 10, Color("fffbe0"), 2, true)
		if mine > 0:
			_txt("Usa %d PM" % mine, 18, 212, 10, _hero_dark(i), 0, true)
		_end_passport()
	if _stage != &"pick":
		return
	var bag := GameState.badge_bag
	var n := mini(bag.size(), 6)
	_dim()
	_rr(Rect2(176, 90, 380, 44 + n * 28), 12, style.panel_bg, style.pill_bg, 3)
	_txt("Medallas para %s  (%d PM libres de %d)" % [heroes[_hero].display_name, free, GameState.bp_max], 192, 112, 13, style.pill_bg, 0, true)
	for k in n:
		var b: Dictionary = bag[k]
		var y := 138.0 + k * 28.0
		var sel := _pick == k
		if sel:
			_rr(Rect2(186, y - 18, 360, 25), 8, style.select_fill)
		_badge_icon(GameState.badge_def(b["id"]), Vector2(202, y - 6), 8.0, style.pill_bg)
		var tag := ""
		if b["by"] == _hid(_hero):
			tag = "  " + style.t_equipped
		elif b["by"] != &"":
			tag = "  (la lleva %s)" % _hero_name(b["by"])
		_txt(_badge_name(b) + tag, 218, y, 12, style.text_dark, 0, sel)
		_txt("%d PM" % int(b["bp"]), 538, y, 11, style.text_red, 2, true)

func _badge_icon(bd: BadgeDef, c: Vector2, r: float, outline: Color) -> void:
	if bd != null and bd.icon != null:
		_tex(bd.icon, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))
	else:
		_ellipse(c, r, r, bd.color if bd != null else Color.GRAY, outline, 2)

# ---------------------------------------------- dibujo: mapa de la zona ----------------------------------------------

var _map_b: Rect2 = Rect2()
var _map_k: float = 1.0
var _map_o: Vector2 = Vector2.ZERO

func _mp(world: Vector2) -> Vector2:
	return _map_o + (world - _map_b.position) * _map_k

func _mr(r: Rect2) -> Rect2:
	return Rect2(_mp(r.position), r.size * _map_k)

func _draw_map() -> void:
	_rr(Rect2(116, 66, 506, 272), 12, style.panel_bg, style.panel_border, 2)
	var scene := get_tree().current_scene
	var walls: Array[Rect2] = []
	var plats: Array = []
	var doors: Array[Rect2] = []
	var b := Rect2()
	var has := false
	for w in get_tree().get_nodes_in_group("solid_walls"):
		if w.has_method("camera_rect"):
			var r: Rect2 = w.call("camera_rect")
			if r.size != Vector2.ZERO:
				walls.append(r)
				b = r if not has else b.merge(r)
				has = true
	for n in get_tree().get_nodes_in_group("platforms"):
		var surf := n as HeightSurface
		if surf != null:
			var fp := surf.footprint()
			plats.append({"r": fp, "h": surf.ground_height_at(fp.get_center()), "ramp": surf is HeightRamp})
			b = fp if not has else b.merge(fp)
			has = true
	var who: Array = []
	for h in get_tree().get_nodes_in_group("overworld_heroes"):
		who.append(h)
		var hp := Rect2((h as Node2D).global_position - Vector2(40, 40), Vector2(80, 80))
		b = hp if not has else b.merge(hp)
		has = true
	if scene != null:
		for d in scene.find_children("*", "Area2D", true, false):
			if d is RoomDoor:
				var dr := Rect2((d as Node2D).global_position - Vector2(14, 14), Vector2(28, 28))
				for c in d.get_children():
					if c is CollisionShape2D and (c as CollisionShape2D).shape is RectangleShape2D:
						var sz: Vector2 = ((c as CollisionShape2D).shape as RectangleShape2D).size * (c as CollisionShape2D).global_scale.abs()
						dr = Rect2((c as CollisionShape2D).global_position - sz * 0.5, sz)
						break
				doors.append(dr)
	if not has:
		return
	_map_b = b.grow(30.0)
	_map_k = minf(480.0 / _map_b.size.x, 214.0 / _map_b.size.y)
	var mw := _map_b.size.x * _map_k
	var mh := _map_b.size.y * _map_k
	_map_o = Vector2(369.0 - mw * 0.5, 92.0)
	_txt(_room_name().to_upper(), 128, 84, 12, style.text_dark, 0, true)
	canvas.draw_rect(Rect2(_map_o, Vector2(mw, mh)), Color("c9d9b0"))
	plats.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return float(a["h"]) < float(c["h"]))
	for p in plats:
		var hz := clampf(float(p["h"]), 0.0, 200.0)
		var col := Color("d6cba0") if p["ramp"] else Color((90.0 + hz * 0.5) / 255.0, (170.0 + hz * 0.3) / 255.0, (70.0 + hz * 0.4) / 255.0)
		canvas.draw_rect(_mr(p["r"]), col)
		canvas.draw_rect(_mr(p["r"]), Color(0.16, 0.27, 0.12, 0.6), false, 1.0)
	for w in walls:
		canvas.draw_rect(_mr(w), Color("b9ab90"))
	for d in doors:
		canvas.draw_rect(_mr(d), Color("f0b732"))
	for n in get_tree().get_nodes_in_group("npcs"):
		if n is Node2D and (n as Node2D).is_visible_in_tree():
			_ellipse(_mp((n as Node2D).global_position), 4.5, 4.5, Color("ff6fae"), Color.WHITE, 1.5)
	var blink := floori(_t / 18.0) % 2 == 0
	for h in who:
		var col2 := Color("43b047") if h is Luigi else Color("e0473f")
		_ellipse(_mp((h as Node2D).global_position), 7.0 if blink else 5.0, 7.0 if blink else 5.0, col2, Color.WHITE, 2)
	canvas.draw_rect(Rect2(_map_o, Vector2(mw, mh)), Color("5a4a28"), false, 2.0)
	# leyenda
	var ly := _map_o.y + mh + 16.0
	var lx := 132.0
	for e in [[Color("e0473f"), "Mario"], [Color("43b047"), "Luigi"], [Color("ff6fae"), "NPC"], [Color("f0b732"), "Puerta"], [Color("b9ab90"), "Muro"], [Color("d6cba0"), "Rampa"]]:
		if (e[1] == "Mario" and not GameState.has_hero(&"mario")) or (e[1] == "Luigi" and not GameState.has_hero(&"luigi")):
			continue   # el hermano que falta tampoco sale en la leyenda
		canvas.draw_rect(Rect2(lx, ly - 8, 9, 9), e[0])
		_txt(e[1], lx + 13, ly, 10, style.text_dark)
		lx += 18.0 + _text_w(e[1], 10) + 14.0
