class_name BattleUI
extends CanvasLayer
## INTERFAZ DEL COMBATE (ui/battle_ui.tscn). Todo son NODOS de la escena: muévelos, cámbiales estilos/texturas o reemplázalos.
## Este script solo los RELLENA cada fotograma con el estado del combate (Combate/battle.gd). Los busca por su nombre:
##   Cards         → HeroCard (ui/hero_card.tscn), una por hermano, en el orden del árbol. Cada tarjeta se mueve libremente,
##                   y sus textos (Name, HP, TP) también: están con "Hijos editables" activado (clic derecho en la tarjeta).
##   DodgeHud      → DodgeButton (ui/dodge_button.tscn), uno por hermano; se ve durante los ataques enemigos.
##   ActionMenu    → menú sobre el héroe de turno. Dentro: ActionName (Label) y Blocks con los ActionBlock (su orden = orden del menú).
##   TargetArrow   → flecha sobre el objetivo (cambia su forma o pon un Sprite2D dentro).
##   ItemPanel     → lista de objetos (Panel libre): ItemDesc (descripción) e ItemRows con un Label por objeto (Row1, Row2...),
##                   en el orden de BattleItems.ORDER. Colócalos donde quieras. Si faltan filas, se copia la última y se coloca
##                   a la misma distancia que había entre las dos últimas (o item_row_spacing).
##   MessagePanel  → cuadro de mensajes (Panel libre): Message (Label), muévelo/redimensiónalo dentro del panel.
## Si borras alguno, simplemente no se muestra. Ningún nodo se busca por su posición: solo por nombre/tipo.

@export var action_menu_follows_hero: bool = true            ## el menú de acciones se coloca sobre el héroe de turno
@export var action_menu_offset: Vector2 = Vector2.ZERO       ## ajuste extra del menú (px del mundo) sobre su sitio: justo encima de la cabeza del héroe
@export var action_menu_gap: float = 40.0                    ## hueco entre la cabeza del héroe y los bloques; el saltito de elegir llega justo hasta ahí
@export var mario_dodge_shift: float = 48.0                  ## px que el icono de esquivar de Mario va más adelante (a la derecha) que el de Luigi
@export var flee_hint: String = "Huir"                      ## texto junto al botón que aparece al machacar para huir
@export var flee_button_gap: float = 20.0                    ## hueco entre la cabeza del hermano y su botón de huida
@export var block_bump: float = 16.0                         ## cuánto sube (px) el bloque al recibir el golpe
## CELEBRACIONES: nodo "Celebrations" con 4 RankBadge (Ok, Good, Great, Excellent). Muévelos donde quieras y ponles tu Texture.
## Su sonido y duración están en Combate/hit_fx_default.tres (sección "Celebraciones").
@export_group("Cursor (botón del hermano)")
## El botón de acción del hermano de turno (ui/action_cursor.tscn: cámbiale el estilo o ponle una imagen) hace de cursor: aparece junto al bloque
## elegido, y al confirmar viaja hasta el enemigo (o hasta la fila de la lista de objetos / tándems); al volver con cancelar, regresa.
@export var use_cursor: bool = true                          ## false = vuelve la flechita amarilla de siempre
@export var cursor_scale: float = 1.0                        ## tamaño del botón
@export var cursor_speed: float = 0.3                        ## cuánto se acerca por fotograma a su sitio (0..1; más = más rápido)
@export var cursor_menu_offset: Vector2 = Vector2(0.0, 4.0)  ## junto al bloque: respecto a su esquina de abajo a la izquierda (px)
@export var cursor_row_offset: Vector2 = Vector2(6.0, 0.0)   ## en las listas: respecto al borde izquierdo de la fila, a media altura (px)
@export var cursor_target_offset: Vector2 = Vector2(0.0, -34.0)   ## sobre el objetivo: respecto a su cabeza (px)
@export var cursor_bob: float = 4.0                          ## px que sube y baja al apuntar
@export_group("Ruleta de acciones")
@export var wheel_pop_frames: int = 16                       ## al empezar el turno, los bloques salen del centro: fotogramas que tarda (0 = sin efecto)
@export var wheel_pop_scale: float = 0.3                     ## tamaño con el que salen (1 = el normal)
@export var wheel_pop_overshoot: float = 1.2                 ## cuánto se pasan antes de asentarse (0 = sin rebote)
@export var wheel_pop_on_back: bool = false                  ## true = también al volver al menú con cancelar
@export var wheel_radius: Vector2 = Vector2(101.0, 39.0)      ## radio de la elipse de la ruleta (px): x = ancho, y = profundidad (alto)
@export var wheel_front_scale: float = 1.0                   ## tamaño del bloque de delante (el elegido, justo sobre el héroe)
@export var wheel_back_scale: float = 0.8                  ## tamaño del bloque más lejano (el de atrás)
@export var wheel_speed: float = 0.25                        ## cuánto gira por fotograma hacia el bloque elegido (0..1; más = más rápido)
@export var float_amount: float = 8.0                        ## el bloque elegido flota: px que sube y baja (0 = no flota)
@export var float_speed: float = 4.0                         ## velocidad de ese flotar (más = más rápido)
@export var name_gap: float = 2.0                            ## hueco (px) entre el nombre de la acción y el bloque más alto
@export_group("")
@export var arrow_offset: Vector2 = Vector2(0, -24)          ## flecha: respecto a la cabeza del objetivo
@export var arrow_bob: float = 5.0                           ## px que sube y baja la flecha
@export var item_color: Color = Color.WHITE
@export var item_selected_color: Color = Color("ffe14d")
@export var item_empty_color: Color = Color("7f8aa8")
@export var warn_color: Color = Color("ffb3b3")
@export var item_row_spacing: Vector2 = Vector2(0, 31)       ## separación de las filas de objetos que se crean solas (si faltan)

var battle   ## Battle (Combate/battle.gd)
var _cards: Array[HeroCard] = []
var _dodges: Array[DodgeButton] = []
var _blocks: Array[ActionBlock] = []
const TIMING_RING := preload("res://ui/timing_ring.gd")   ## anillo de timing del ataque tándem (se dibuja por código)
var _ring: Node2D
var _wheel: Control        ## contenedor libre donde los bloques giran en ruleta
var _wheel_pos := 0.0      ## posición (fraccionaria) de la ruleta: cuál bloque está delante
var _rows: Array[Label] = []
const FLEE_BUTTON := preload("res://ui/dodge_button.tscn")   ## mismo botón que el de esquivar, para la huida
var _flee_btns: Array[DodgeButton] = []
var _msg: Label
var _msg_panel: Control
var _msg_color := Color.WHITE
var _action_menu: Control
var _action_name: Label
var _arrow: Node2D
var _item_panel: Control
var _item_desc: Label
var _dodge_hud: Control
const ACTION_CURSOR := preload("res://ui/action_cursor.tscn")
var _cursor: DodgeButton
var _cursor_pos := Vector2.ZERO   ## centro actual del cursor (pantalla)
var _cursor_on := false
var _ranks: Array[RankBadge] = []   ## celebraciones, de peor a mejor (Ok, Good, Great, Excellent)

## ¿Hay nodos de celebración en la escena? (si no, el anillo dibuja unas provisionales por código)
func has_rank_nodes() -> bool:
	return not _ranks.is_empty()

func setup(b) -> void:
	battle = b
	var cel := find_child("Celebrations", true, false)
	if cel:
		for c in cel.get_children():
			if c is RankBadge:
				_ranks.append(c)
				c.visible = false
	_msg_panel = find_child("MessagePanel", true, false) as Control
	_msg = find_child("Message", true, false) as Label
	var mario_row := find_child("MarioDodge", true, false) as Container   # el icono de Mario más adelante (a la derecha) que el de Luigi
	if mario_row and mario_dodge_shift > 0.0:
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(mario_dodge_shift, 0.0)
		mario_row.add_child(pad)
		mario_row.move_child(pad, 0)
	if _msg:
		_msg_color = _msg.get_theme_color("font_color")
	_action_menu = find_child("ActionMenu", true, false) as Control
	_action_name = find_child("ActionName", true, false) as Label
	_arrow = find_child("TargetArrow", true, false) as Node2D
	_item_panel = find_child("ItemPanel", true, false) as Control
	_item_desc = find_child("ItemDesc", true, false) as Label
	_dodge_hud = find_child("DodgeHud", true, false) as Control
	for c in find_children("*", "", true, false):   # dentro de contenedores o sueltos, da igual
		if c is HeroCard:
			_cards.append(c)
		elif c is ActionBlock:
			_blocks.append(c)
		elif c is DodgeButton:
			_dodges.append(c)
	var keep: Array[ActionBlock] = []   # bloques de acciones desactivadas: desaparecen (si no quedara ninguno, se ignora)
	for ab in _blocks:
		if battle.action_enabled(ab.action_id):
			keep.append(ab)
	if not keep.is_empty() and keep.size() < _blocks.size():
		for ab in _blocks:
			if not keep.has(ab):
				ab.get_parent().remove_child(ab)
				ab.queue_free()
		_blocks = keep
	if not _blocks.is_empty():   # los bloques salen de su contenedor y pasan a una ruleta que los coloca en una elipse
		_wheel = Control.new()
		_wheel.name = "ActionWheel"
		_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_wheel)
		for ab in _blocks:
			ab.reparent(_wheel, false)
			ab.reset_size()
		_wheel.visible = false
	for i in _cards.size():   # sobran tarjetas/botones si hay menos héroes
		_cards[i].visible = i < battle.heroes.size()
	for i in _dodges.size():
		_dodges[i].visible = i < battle.heroes.size()
	_setup_item_rows()
	_ring = TIMING_RING.new() as Node2D   # anillo de timing (tándem): va el último para dibujarse por encima de todo
	_ring.set("battle", battle)
	add_child(_ring)
	if use_cursor:   # cursor: el botón del hermano (encima de todo)
		_cursor = ACTION_CURSOR.instantiate() as DodgeButton
		add_child(_cursor)
		_cursor.visible = false
	for i in battle.heroes.size():   # botón de huida: uno por hermano, sobre su cabeza, solo en su turno de machacar
		var fb := FLEE_BUTTON.instantiate() as DodgeButton
		add_child(fb)
		fb.visible = false
		var hint := fb.find_child("Hint", true, false) as Label
		if hint:
			hint.text = flee_hint
		_flee_btns.append(fb)

## CURSOR: el botón del hermano de turno. Junto al bloque elegido en el menú; en las listas (objetos / tándems), junto a la fila elegida;
## al elegir objetivo, sobre el enemigo (o el hermano, con objetos). Siempre se DESLIZA hasta su sitio, así que al confirmar viaja de uno a otro
## y al cancelar (C) vuelve por donde vino.
func _update_cursor(ph: StringName, fade_a: float) -> void:
	if _cursor == null:
		return
	var h := battle.actor as BattleHero
	var goal := Vector2.ZERO
	var alpha := 1.0
	var visible_now := h != null
	var bob := 0.0
	if visible_now and (ph == &"menu" or ph == &"menu_hop" or ph == &"menu_in"):
		if _blocks.is_empty():
			visible_now = false
		else:
			var blk := _blocks[clampi(battle.menu_index, 0, _blocks.size() - 1)]
			var corner := blk.position + blk.size * 0.5 + Vector2(-blk.size.x * blk.scale.x, blk.size.y * blk.scale.y) * 0.5
			goal = corner + cursor_menu_offset
			alpha = fade_a
	elif visible_now and (ph == &"items" or ph == &"tandems"):
		var idx: int = battle.list_index if ph == &"items" else battle.tandem_index
		if _rows.is_empty():
			visible_now = false
		else:
			var row := _rows[clampi(idx, 0, _rows.size() - 1)]
			goal = row.global_position + Vector2(0.0, row.size.y * 0.5) + cursor_row_offset
	elif visible_now and (ph == &"target" or ph == &"item_target"):
		var tgt: BattleActor = null
		if ph == &"target":
			var es: Array = battle.current_targets()
			if not es.is_empty():
				tgt = es[clampi(battle.target_index, 0, es.size() - 1)]
		else:
			tgt = battle.heroes[battle.target_index]
		if tgt == null:
			visible_now = false
		else:
			goal = _screen(tgt.position + tgt.advance + Vector2(0, -tgt.body_height())) + cursor_target_offset * battle.get_global_transform_with_canvas().get_scale()
			bob = sin(Time.get_ticks_msec() / 120.0) * cursor_bob
	else:
		visible_now = false
	if not visible_now:
		_cursor.visible = false
		_cursor_on = false
		return
	if not _cursor_on:   # primera vez que sale: aparece directamente en su sitio
		_cursor_pos = goal
		_cursor_on = true
	else:
		_cursor_pos = _cursor_pos.lerp(goal, cursor_speed)
	_cursor.visible = true
	_cursor.show_hero(h, battle.key_of(h.action()))
	_cursor.modulate.a *= alpha
	_cursor.pivot_offset = _cursor.size * 0.5
	_cursor.scale = Vector2.ONE * cursor_scale
	_cursor.position = _cursor_pos + Vector2(0.0, bob) - _cursor.size * 0.5

## Filas de objetos: los Label que haya dentro de ItemRows, en orden. Si hay menos que objetos, se copian.
func _setup_item_rows() -> void:
	var root := find_child("ItemRows", true, false)
	if root == null:
		return
	for c in root.get_children():
		if c is Label:
			_rows.append(c)
	if _rows.is_empty():
		return
	var n := maxi(BattleItems.ORDER.size(), battle.tandems.size())   # el mismo panel sirve para objetos y para tándems
	while _rows.size() < n:
		var last := _rows[-1]
		var step := item_row_spacing if _rows.size() < 2 else last.position - _rows[-2].position
		var row := last.duplicate() as Label
		row.name = "Row%d" % (_rows.size() + 1)
		root.add_child(row)
		if not root is Container:
			row.position = last.position + step
		_rows.append(row)
	for i in _rows.size():
		_rows[i].visible = i < n

var _pop_t := 9999
var _was_in_menu := false

## Progreso (0 → 1, con un pequeño rebote) de la salida de los bloques desde el centro.
func _pop_value() -> float:
	if wheel_pop_frames <= 0 or _pop_t >= wheel_pop_frames:
		return 1.0
	var x := float(_pop_t) / float(wheel_pop_frames) - 1.0   # ease-out-back
	var c := wheel_pop_overshoot
	return 1.0 + (c + 1.0) * x * x * x + c * x * x

## Posición del mundo (combate) → pantalla, teniendo en cuenta la cámara (la UI está en un CanvasLayer y no la sigue).
func _screen(world: Vector2) -> Vector2:
	return battle.get_global_transform_with_canvas() * world

## Orden de las acciones del menú (el de los bloques en la escena).
func action_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for b in _blocks:
		ids.append(b.action_id)
	if ids.is_empty():
		ids.assign([&"item", &"flee", &"jump", &"hammer"])
	return ids

func action_name(i: int) -> String:
	return _blocks[i].display_name if i < _blocks.size() else String(battle.actions[i])

## RULETA: los bloques giran sobre una elipse (vista desde arriba). El elegido queda DELANTE, justo encima del héroe
## (grande y brillante); los demás van detrás (más pequeños, más oscuros y más arriba). Al cambiar de selección gira.
func _layout_wheel(h: BattleHero, pulse: float, bump: float, pop := 1.0) -> void:
	var n := _blocks.size()
	if n == 0:
		return
	var d := wrapf(float(battle.menu_index) - _wheel_pos, -n / 2.0, n / 2.0)   # el camino más corto hasta el elegido
	_wheel_pos = float(battle.menu_index) if absf(d) < 0.002 else _wheel_pos + d * wheel_speed
	var head := _screen(h.position + h.advance + Vector2(0, -h.body_height() - action_menu_gap) + action_menu_offset)
	var bsize := _blocks[0].size
	var cy := head.y - bsize.y * wheel_front_scale * 0.5 - wheel_radius.y   # centro de la elipse: el bloque de delante apoya su borde de abajo en "head"
	var top := INF   # borde de arriba del bloque que queda más alto
	var floating: bool = battle.phase == &"menu"   # el elegido flota mientras se elige (no mientras salta a golpearlo)
	for i in n:
		var a := PI / 2.0 - (float(i) - _wheel_pos) * TAU / n   # PI/2 = delante (abajo); al pulsar ► el siguiente llega desde la derecha
		var s := sin(a)
		var depth := (s + 1.0) * 0.5   # 1 = delante, 0 = detrás del todo
		var blk := _blocks[i]
		var center := Vector2(head.x + cos(a) * wheel_radius.x, cy + s * wheel_radius.y)
		center = Vector2(head.x, cy).lerp(center, pop)   # al aparecer: todos juntos en el centro, y se van separando
		blk.set_wheel(depth, pulse if i == battle.menu_index else 0.0, wheel_back_scale, wheel_front_scale)
		blk.scale *= lerpf(wheel_pop_scale, 1.0, pop)   # y creciendo hasta su tamaño
		var lift := bump if i == battle.menu_index else 0.0
		if floating and i == battle.menu_index:   # efecto flotante: sube y baja suavemente
			lift += (sin(Time.get_ticks_msec() / 1000.0 * float_speed) * 0.5 + 0.5) * float_amount
		blk.position = center - blk.size * 0.5 - Vector2(0.0, lift)
		top = minf(top, center.y - blk.size.y * blk.scale.y * 0.5)
	if _action_menu and action_menu_follows_hero:   # el nombre de la acción, justo encima del bloque más alto
		var label_h := _action_name.size.y if _action_name else _action_menu.size.y
		_action_menu.position = Vector2(head.x - _action_menu.size.x * 0.5, top - label_h - name_gap)

## Lo llama el combate en cada fotograma.
func refresh() -> void:
	if battle == null:
		return
	var ph: StringName = battle.phase
	var rk: Dictionary = battle.rank_fx
	for i in _ranks.size():   # solo se ve la celebración activa
		var on: bool = not rk.is_empty() and int(rk["level"]) == i
		_ranks[i].visible = on
		if on:
			_ranks[i].play(int(rk["t"]), battle.fx.rank_frames)
	# El cuadro de texto solo aparece al elegir enemigo, y dice su nombre (nada de narración del combate).
	var picking: bool = ph == &"target"
	if _msg_panel:
		_msg_panel.visible = picking
	if _msg and picking:
		var pick: Array = battle.current_targets()
		if not pick.is_empty():
			_msg.text = (pick[clampi(battle.target_index, 0, pick.size() - 1)] as BattleActor).display_name
		_msg.add_theme_color_override("font_color", _msg_color)
	var choosing: bool = ph in [&"menu", &"menu_hop", &"menu_fade", &"menu_in", &"target", &"items", &"item_target", &"tandems"]
	for i in mini(_cards.size(), battle.heroes.size()):
		_cards[i].show_hero(battle.heroes[i], choosing and battle.actor == battle.heroes[i])

	var dodging: bool = ph == &"enemy_tell" or ph == &"enemy_attack"
	if _dodge_hud:
		_dodge_hud.visible = dodging
	if dodging:
		for i in mini(_dodges.size(), battle.heroes.size()):
			var h: BattleHero = battle.heroes[i]
			_dodges[i].set_kind(battle.pattern.defense_kind() if battle.pattern != null else &"jump")   # martillo: otro símbolo
			_dodges[i].show_hero(h, battle.key_of(h.action()))

	var fading: bool = battle.fade_out > 0 and ph != &"menu" and ph != &"menu_hop" and ph != &"menu_in"
	var in_menu: bool = ph == &"menu" or ph == &"menu_hop" or ph == &"menu_in" or fading
	var fade_a := 1.0
	if in_menu and not _was_in_menu:   # los bloques acaban de aparecer: empieza el efecto de salir del centro
		_pop_t = 0 if (ph == &"menu" or wheel_pop_on_back) else 9999
	_was_in_menu = in_menu
	_pop_t += 1
	if fading:   # tras el golpe, los bloques se desvanecen mientras ya empieza el siguiente paso
		fade_a = clampf(float(battle.fade_out) / float(Battle.MENU_FADE), 0.0, 1.0)
	elif ph == &"menu_in":   # al volver (cancelar), aparecen igual de rápido, cuando la cámara ya llegó
		fade_a = clampf(float(battle.frame) / float(Battle.MENU_FADE), 0.0, 1.0)
	if _wheel:
		_wheel.modulate.a = fade_a
	if _action_menu:
		_action_menu.modulate.a = fade_a
		_action_menu.visible = in_menu
		if in_menu:
			var h2: BattleHero = battle.actor
			var pulse: float = clampf(h2.sel_hop * 1.6 - 0.6, 0.0, 1.0) if ph == &"menu_hop" else 0.0
			h2.sel_hop_h = action_menu_gap + 4.0   # la cabeza llega al bloque en lo alto del salto
			var t: float = clampf(h2.sel_hop, 0.0, 1.0) if ph == &"menu_hop" else 0.0
			var bump: float = sin(clampf((t - 0.5) / 0.5, 0.0, 1.0) * PI) * block_bump   # golpe: desde lo alto del salto
			if _action_name:
				_action_name.text = action_name(battle.menu_index)
			_layout_wheel(h2, pulse, bump, _pop_value())
	if _wheel:
		_wheel.visible = in_menu
		if not in_menu:
			_wheel_pos = float(battle.menu_index)   # al volver a abrir el menú ya está colocada

	if _arrow:
		var tgt: BattleActor = null
		if ph == &"target":
			var es: Array = battle.current_targets()
			if not es.is_empty():
				tgt = es[clampi(battle.target_index, 0, es.size() - 1)]
		elif ph == &"item_target":
			tgt = battle.heroes[battle.target_index]
		_arrow.visible = tgt != null and _cursor == null
		if tgt and _cursor == null:
			_arrow.position = _screen(tgt.position + tgt.advance + Vector2(0, -tgt.body_height()) + arrow_offset) + Vector2(0, sin(Time.get_ticks_msec() / 120.0) * arrow_bob)
			_arrow.scale = battle.get_global_transform_with_canvas().get_scale()

	_update_cursor(ph, fade_a)

	# Huida: solo se ve el botón del hermano al que le toca machacar, encima de él.
	var fleeing: bool = ph == &"flee" and battle.flee_end < 0
	for i in mini(_flee_btns.size(), battle.heroes.size()):
		var fh: BattleHero = battle.heroes[i]
		var fb := _flee_btns[i]
		fb.visible = fleeing and i == battle.flee_turn and fh.alive and not fh.out
		if fb.visible:
			fb.show_hero(fh, battle.key_of(fh.action()))
			var top: Vector2 = _screen(fh.position + fh.advance + fh.offset + Vector2(0, -fh.body_height() - flee_button_gap))
			fb.position = top - Vector2(fb.size.x / 2.0, fb.size.y)

	var listing: bool = ph == &"items" or ph == &"item_target"
	var listing_tandem: bool = ph == &"tandems"
	if _item_panel:
		_item_panel.visible = listing or listing_tandem
	if listing_tandem and not battle.tandems.is_empty():   # lista de ataques tándem: nombre + coste en PT, gris si no se puede usar
		var th: BattleHero = battle.actor
		var ti: int = clampi(battle.tandem_index, 0, battle.tandems.size() - 1)
		if _item_desc:
			_item_desc.text = (battle.tandems[ti] as TandemData).description
		for i in _rows.size():
			_rows[i].visible = i < battle.tandems.size()
			if i >= battle.tandems.size():
				continue
			var td: TandemData = battle.tandems[i]
			_rows[i].text = ("      " if use_cursor else ("► " if i == ti else "   ")) + "%s   %d PT" % [td.display_name, td.cost]
			var ok: bool = battle._tandem_block_reason(th, td) == ""
			_rows[i].add_theme_color_override("font_color", item_selected_color if i == ti else (item_color if ok else item_empty_color))
	if listing:
		for i in _rows.size():
			_rows[i].visible = i < BattleItems.ORDER.size()
		var sel: StringName = BattleItems.ORDER[battle.list_index]
		if _item_desc:
			_item_desc.text = BattleItems.DEFS[sel]["desc"]
		for i in mini(_rows.size(), BattleItems.ORDER.size()):
			var id: StringName = BattleItems.ORDER[i]
			var count := int(GameState.inventory.get(id, 0))
			_rows[i].text = ("      " if use_cursor else ("► " if i == battle.list_index else "   ")) + "%s   ×%d" % [BattleItems.item_name(id), count]
			_rows[i].add_theme_color_override("font_color", item_selected_color if i == battle.list_index else (item_color if count > 0 else item_empty_color))
