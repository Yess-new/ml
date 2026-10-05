class_name SaveMenu
extends CanvasLayer
## MENÚ DE GUARDADO (el que sale al golpear un SaveBlock). Diseño tipo "cuaderno": marco marrón, borde azul, panel verde con la lista de
## opciones a la izquierda, y a la derecha las monedas, el reloj y los dos hermanos.
##   1) Guardar y seguir / Guardar y salir / Volver al juego
##   2) Elegir fichero (el que estás jugando sale seleccionado). Si el fichero ya tiene datos y NO es el tuyo, pregunta si quieres sobrescribirlo.
##   3) "¡Partida guardada!"  → sigues jugando, o sales al título.
## Teclas: ↑↓ elegir · Z / X aceptar · C volver. Congela el juego mientras está abierto.
## Se abre solo desde SaveBlock, o a mano: SaveMenu.open(get_tree())

static var is_open: bool = false

signal closed

var title: String = "GUARDAR"
var exit_scene: String = "res://intro/title_screen.tscn"   ## a dónde vas con "Guardar y salir"
var scene_to_save: String = ""                              ## escena en la que continuar (vacío = la actual)

const DW := 640.0
const DH := 370.0
const C_WOOD := Color("b8693a")
const C_WOOD_D := Color("7a3f1d")
const C_BLUE := Color("2f6df0")
const C_BLUE_D := Color("1a3f9e")
const C_PANEL := Color("a3c5ac")
const C_LINE := Color("8db398")
const C_TEXT := Color("56665e")
const C_TEXT_SEL := Color("2f3d36")
const C_CREAM := Color("e9e7dd")
const C_ARROW := Color("ffd23a")
const MENU_ITEMS := ["Guardar y seguir.", "Guardar y salir.", "Volver al juego."]

var _canvas: Control
var _font: Font
var _stage: StringName = &"menu"   # menu | file | confirm | done
var _idx: int = 0
var _after: StringName = &"continue"   # continue | exit
var _pending: int = -1
var _saved_slot: int = -1
var _t: int = 0
var _done_t: int = 0
var _open_frame: int = -1
var _closing: bool = false

## Abre el menú (si no hay otro abierto).
static func open(tree: SceneTree, menu_title: String = "GUARDAR") -> SaveMenu:
	if is_open:
		return null
	var m := SaveMenu.new()
	m.title = menu_title
	tree.root.add_child(m)
	return m

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 101
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.draw.connect(_paint)
	add_child(_canvas)
	var pm := get_node_or_null("/root/PauseMenu")   # misma fuente que el menú de pausa, si tiene
	if pm != null and pm.get("style") != null and pm.style.get("font") != null:
		_font = pm.style.font
	if _font == null:
		_font = ThemeDB.fallback_font
	if scene_to_save == "":
		var cs := get_tree().current_scene
		scene_to_save = cs.scene_file_path if cs != null else ""
	is_open = true
	_open_frame = Engine.get_process_frames()
	get_tree().paused = true

func _exit_tree() -> void:
	is_open = false

# ─────────────────────────── lógica ───────────────────────────

func _pressed(a: StringName) -> bool:
	return InputMap.has_action(a) and Input.is_action_just_pressed(a)

func _held(a: StringName) -> bool:
	return InputMap.has_action(a) and Input.is_action_pressed(a)

func _process(_d: float) -> void:
	if _closing:   # espera a soltar las teclas: así la Z / C que cierra no hace saltar a nadie al reanudar
		if not (_held(&"jump_mario") or _held(&"jump_luigi") or _held(&"cancel")):
			_finish()
		return
	_t += 1
	_canvas.queue_redraw()
	if Engine.get_process_frames() == _open_frame:
		return
	var ok := _pressed(&"jump_mario") or _pressed(&"jump_luigi")
	var back := _pressed(&"cancel")
	var ud := int(_pressed(&"ui_down")) - int(_pressed(&"ui_up"))
	match _stage:
		&"menu":
			_idx = posmod(_idx + ud, MENU_ITEMS.size())
			if back:
				_close()
			elif ok:
				if _idx == 2:
					_close()
				else:
					_after = &"continue" if _idx == 0 else &"exit"
					_stage = &"file"
					_idx = maxi(SaveSlots.current_slot, 0)   # por defecto, el fichero que estás jugando
		&"file":
			_idx = posmod(_idx + ud, SaveSlots.COUNT)
			if back:
				_stage = &"menu"
				_idx = 0 if _after == &"continue" else 1
			elif ok:
				if SaveSlots.exists(_idx) and _idx != SaveSlots.current_slot:
					_pending = _idx   # ya hay datos y no es tu fichero: confirmar
					_stage = &"confirm"
					_idx = 1
				else:
					_save(_idx)
		&"confirm":
			_idx = posmod(_idx + ud, 2)
			if back or (ok and _idx == 1):
				_stage = &"file"
				_idx = _pending
			elif ok:
				_save(_pending)
		&"done":
			_done_t += 1
			if _done_t > 70 or ok:
				if _after == &"exit":
					_exit_to_title()
				else:
					_close()

func _save(slot: int) -> void:
	SaveSlots.current_slot = slot
	SaveSlots.write(slot, SaveSlots.capture(scene_to_save))
	_saved_slot = slot
	_stage = &"done"
	_done_t = 0

func _close() -> void:
	_closing = true
	_canvas.visible = false

func _finish() -> void:
	get_tree().paused = false
	closed.emit()
	queue_free()

func _exit_to_title() -> void:
	get_tree().paused = false
	_closing = false
	is_open = false
	ScreenFade.go(get_tree(), exit_scene, 0.8)
	queue_free()

# ─────────────────────────── datos a mostrar ───────────────────────────

## Lo que se ve a la derecha: la partida actual, o el fichero resaltado al elegir fichero.
func _info() -> Dictionary:
	if _stage == &"file" or _stage == &"confirm":
		var slot := _idx if _stage == &"file" else _pending
		var d := SaveSlots.read(slot)
		if d.is_empty():
			return {"empty": true}
		var lv: Dictionary = d.get("levels", {})
		return {"empty": false, "coins": int(d.get("coins", 0)), "secs": int(d.get("play_time", 0.0)),
			"mario": int(lv.get("mario", 1)), "luigi": int(lv.get("luigi", 1))}
	return {"empty": false, "coins": GameState.coins, "secs": int(GameState.play_time),
		"mario": int(GameState.hero_level.get(&"mario", 1)), "luigi": int(GameState.hero_level.get(&"luigi", 1))}

func _message() -> String:
	match _stage:
		&"menu": return "¿Quieres guardar tu partida?"
		&"file": return "¿En qué fichero quieres guardar? (el que estás jugando sale seleccionado)"
		&"confirm": return "El fichero %d ya tiene datos. ¿Quieres sobrescribirlo?" % (_pending + 1)
		_: return "¡Partida guardada en el fichero %d!" % (_saved_slot + 1)

func _hint() -> String:
	match _stage:
		&"done": return "Z continuar"
		&"menu": return "↑↓ elegir · Z aceptar · C volver"
	return "↑↓ elegir · Z aceptar · C atrás"

# ─────────────────────────── dibujo ───────────────────────────

func _txt(s: String, x: float, y: float, size: int, col: Color, align: int = 0) -> void:
	var w := 560.0
	var px := x
	var ha := HORIZONTAL_ALIGNMENT_LEFT
	if align == 1:
		px = x - w * 0.5
		ha = HORIZONTAL_ALIGNMENT_CENTER
	elif align == 2:
		px = x - w
		ha = HORIZONTAL_ALIGNMENT_RIGHT
	_canvas.draw_string(_font, Vector2(px, y), s, ha, w, size, col)

func _rr(r: Rect2, rad: float, fill: Color, border: Color = Color(0, 0, 0, 0), bw: float = 0.0) -> void:
	rad = clampf(rad, 0.0, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [r.position + Vector2(rad, rad), Vector2(r.end.x - rad, r.position.y + rad), r.end - Vector2(rad, rad), Vector2(r.position.x + rad, r.end.y - rad)]
	for c in 4:
		for k in 7:
			var a := PI + c * PI * 0.5 + k * (PI * 0.5 / 6.0)
			pts.append(corners[c] + Vector2(cos(a), sin(a)) * rad)
	if fill.a > 0.0:
		_canvas.draw_colored_polygon(pts, fill)
	if border.a > 0.0 and bw > 0.0:
		pts.append(pts[0])
		_canvas.draw_polyline(pts, border, bw, true)

func _ell(c: Vector2, rx: float, ry: float, fill: Color, border: Color = Color(0, 0, 0, 0), bw: float = 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	_canvas.draw_colored_polygon(pts, fill)
	if border.a > 0.0 and bw > 0.0:
		pts.append(pts[0])
		_canvas.draw_polyline(pts, border, bw, true)

func _arrow(x: float, y: float, h: float) -> void:
	var pts := PackedVector2Array([Vector2(x, y - h * 0.5), Vector2(x + h * 0.9, y), Vector2(x, y + h * 0.5)])
	_canvas.draw_colored_polygon(pts, C_ARROW)
	pts.append(pts[0])
	_canvas.draw_polyline(pts, Color("8a5a10"), 2.0, true)

func _paint() -> void:
	var sz := _canvas.size
	var s := minf(sz.x / DW, sz.y / DH)
	_canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.72))
	_canvas.draw_set_transform((sz - Vector2(DW, DH) * s) * 0.5, 0.0, Vector2(s, s))
	# marco
	_rr(Rect2(0, 0, DW, DH), 14, C_WOOD, C_WOOD_D, 3)
	_rr(Rect2(20, 16, DW - 40, DH - 30), 16, C_BLUE, C_BLUE_D, 3)
	_rr(Rect2(33, 42, DW - 66, DH - 70), 8, C_PANEL, C_LINE, 2)
	# adornos del panel (rayas suaves)
	_canvas.draw_line(Vector2(316, 52), Vector2(316, 270), C_LINE, 2.0)
	_canvas.draw_rect(Rect2(66, 76, 240, 196), Color(1, 1, 1, 0.0))
	_rr(Rect2(66, 76, 242, 196), 8, Color(1, 1, 1, 0.06), C_LINE, 2)
	# pestaña con el título
	_rr(Rect2(350, 5, 148, 34), 8, C_CREAM, Color("c5c2b4"), 2)
	_txt(title, 424, 30, 21, Color("7a7c76"), 1)
	# botón decorativo
	_rr(Rect2(262, 40, 74, 44), 6, Color("2a2d38"), Color("15171e"), 2)
	_ell(Vector2(299, 36), 20, 15, Color("d8dae0"), Color("7c808c"), 2)
	_ell(Vector2(299, 36), 12, 8, Color("f4f5f8"))
	# lista de opciones
	_draw_list()
	# derecha: monedas, reloj y hermanos
	_draw_right()
	# barra de mensaje
	_rr(Rect2(50, 282, DW - 100, 48), 10, C_CREAM, Color("c5c2b4"), 2)
	_txt(_message(), 66, 304, 15, Color("4a4f4a"))
	_txt(_hint(), DW - 66, 322, 11, Color("8a8d86"), 2)
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_list() -> void:
	var sel_x := 38.0 + sin(_t / 8.0) * 2.0
	match _stage:
		&"file":
			for i in SaveSlots.COUNT:
				var y := 100.0 + i * 46.0
				var sel := _idx == i
				var d := SaveSlots.exists(i)
				var tag := "  (en juego)" if i == SaveSlots.current_slot else ""
				_txt("Fichero %d%s" % [i + 1, tag], 86, y, 19, C_TEXT_SEL if sel else C_TEXT)
				_txt("con datos" if d else "vacío", 86, y + 17, 12, Color("74847a"))
				if sel:
					_arrow(sel_x, y - 6, 22)
		&"confirm":
			_txt("Fichero %d." % (_pending + 1), 86, 100, 17, C_TEXT)
			for i in 2:
				var y := 150.0 + i * 38.0
				var sel := _idx == i
				_txt(["Sí, sobrescribir.", "No."][i], 86, y, 19, C_TEXT_SEL if sel else C_TEXT)
				if sel:
					_arrow(sel_x, y - 6, 22)
		&"done":
			_txt("Fichero %d." % (_saved_slot + 1), 86, 110, 19, C_TEXT_SEL)
			_txt("Guardado.", 86, 140, 17, C_TEXT)
		_:
			for i in MENU_ITEMS.size():
				var y := 106.0 + i * 40.0
				var sel := _idx == i
				_txt(MENU_ITEMS[i], 86, y, 19, C_TEXT_SEL if sel else C_TEXT)
				if sel:
					_arrow(sel_x, y - 6, 22)

func _draw_right() -> void:
	var info := _info()
	var empty: bool = info["empty"]
	var coins := "--" if empty else str(info["coins"])
	# monedero (pastilla oscura con dos monedas)
	_rr(Rect2(330, 60, 126, 38), 19, Color("3a3d46"), Color("15171e"), 3)
	for cx in [350.0, 436.0]:
		_ell(Vector2(cx, 79), 8, 11, Color("f6c035"), Color("8a5a10"), 2)
	_txt(coins, 393, 88, 22, Color("ffe27a"), 1)
	# tapa blanca y reloj
	_ell(Vector2(472, 79), 14, 22, Color("eeeeea"), Color("b0b0aa"), 2)
	_ell(Vector2(528, 90), 38, 38, Color("f4ecd0"), Color("b88a2c"), 4)
	_ell(Vector2(528, 90), 30, 30, Color("e6ddba"), Color("d0c08a"), 1)
	var secs := 0 if empty else int(info["secs"])
	var clock := "--:--" if empty else "%02d:%02d" % [floori(secs / 3600.0), floori((secs % 3600) / 60.0)]
	_txt(clock, 528, 98, 20, Color("4a4a42"), 1)
	# los dos hermanos
	var heroes := [["MARIO", "mario", Color("e0473f")], ["LUIGI", "luigi", Color("43b047")]]
	for i in 2:
		var x := 344.0 + i * 104.0
		var r := Rect2(x, 142, 92, 128)
		_rr(r, 10, Color(1, 1, 1, 0.1), C_LINE, 2)
		var col: Color = heroes[i][2]
		if empty:
			_txt("—", r.get_center().x, 214, 26, Color("8fa797"), 1)
			continue
		_rr(Rect2(x + 8, 150, 76, 22), 11, col.darkened(0.15))
		_txt(heroes[i][0], x + 46, 166, 13, Color.WHITE, 1)
		_txt("Nv", x + 46, 198, 14, C_TEXT, 1)
		_txt(str(info[heroes[i][1]]), x + 46, 238, 36, C_TEXT_SEL, 1)
