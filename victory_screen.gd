class_name VictoryScreen
extends CanvasLayer
## PANTALLAS DE VICTORIA (portadas del prototipo HTML: "EXPERIENCIA, NIVELES Y ESCENA DE VICTORIA"). Las crea Battle al ganar un combate.
##
## ESCENA 1 · Los hermanos saltan a sus plataformas, sube la bandera de experiencia ("EXP +N"), y abajo salen las monedas (izquierda)
##            y los objetos conseguidos (derecha). Z / X salta la animación.
## ESCENA 2 · Quien sube de nivel ve su pantalla: todos los atributos suben (1-3 puntos al azar, ver data/hero_growth.gd) y después
##            ELIGES un atributo (↑↓) y paras la ruleta (Z / X) para ganar un bonus de 1 a 5 (¡el 5 es el sector pequeño!). C: elegir otro.
##
## Los hermanos que se ven son COPIAS de los del combate (con su sprite y su animación "victory" si la tienen).
## Todo se dibuja por código sobre un lienzo de 640×420 (como el HTML), escalado a la ventana.
## Cambia colores, tiempos y textos en las constantes y funciones _draw_* de este script.

signal finished   ## ya se ha visto todo: el combate puede cerrarse

const W := 640.0
const H := 420.0
const VICT := {"land": 55, "flag0": 80, "flag1": 170, "end": 250}   ## fotogramas (60 = 1 s)
const PLAT := {
	&"luigi": {"cx": 185.0, "cy": 262.0, "rx": 124.0, "ry": 46.0, "col": "3fd6a3", "dark": "17604a", "lite": "8ff2cf", "from": Vector2(-40, 300)},
	&"mario": {"cx": 468.0, "cy": 196.0, "rx": 124.0, "ry": 44.0, "col": "f2552c", "dark": "7a1c0a", "lite": "ff9a72", "from": Vector2(W + 40.0, 150)},
}
const WHEEL_STEP := 0.1   ## radianes que gira la ruleta por fotograma

var heroes: Array = []        ## [{ id, name, lv0, exp0, need0, exp1, need1, ups: Array[int], src: BattleHero, node: BattleHero }]
var exp_total := 0
var coins0 := 0
var coins_got := 0
var items: Dictionary = {}
var _mode := &"victory"       ## victory · levelup · done
var _t := 0                   ## fotogramas de la escena 1
var _acc := 0.0
var _clock := 0
var _queue: Array = []        ## subidas de nivel pendientes: [{ hid, lv }]
var _lu: Dictionary = {}      ## la subida en curso
var _fade := {}               ## { f, len, cb }
var _s := 1.0
var _ox := 0.0
var _bg: Node2D
var _hero_root: Node2D
var _fg: Node2D
var _veil: ColorRect
var _font: SystemFont

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Verdana", "Arial", "Segoe UI"])
	_font.font_weight = 800
	_bg = Node2D.new()
	_bg.draw.connect(_draw_layer.bind(_bg, 0))
	add_child(_bg)
	_hero_root = Node2D.new()
	add_child(_hero_root)
	_fg = Node2D.new()
	_fg.draw.connect(_draw_layer.bind(_fg, 1))
	add_child(_fg)
	_veil = ColorRect.new()
	_veil.color = Color.BLACK
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.modulate.a = 0.0
	add_child(_veil)
	for h in heroes:
		var src: BattleHero = h["src"]
		var d := src.duplicate() as BattleHero
		d.alive = true
		d.anim_override = &"victory"
		d.flash = 0
		d.visible = true
		_hero_root.add_child(d)
		h["node"] = d
	_layout()
	_fade_in()

## Lo llama Battle justo después de crearla.
func setup(data: Dictionary, battle_heroes: Array) -> void:
	exp_total = int(data["exp"])
	coins0 = int(data["coins0"])
	coins_got = int(data["got"])
	items = data["items"]
	for hv in data["heroes"]:
		var h: Dictionary = (hv as Dictionary).duplicate()
		for bh in battle_heroes:
			if (bh as BattleHero).stats.id == h["id"]:
				h["src"] = bh
				h["name"] = (bh as BattleHero).display_name
		if h.has("src"):
			heroes.append(h)

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	_s = vp.y / H
	_ox = (vp.x - W * _s) * 0.5

func _p(v: Vector2) -> Vector2:
	return Vector2(_ox, 0.0) + v * _s

# ───────────────────────────── bucle ─────────────────────────────

func _process(delta: float) -> void:
	_layout()
	var ok := false
	for h in heroes:
		if Input.is_action_just_pressed((h["src"] as BattleHero).action()):
			ok = true
	var up := Input.is_action_just_pressed(&"ui_up")
	var down := Input.is_action_just_pressed(&"ui_down")
	var cancel := Input.is_action_just_pressed(&"cancel")
	_acc += minf(delta, 0.1)
	var first := true
	while _acc >= 1.0 / 60.0:
		_acc -= 1.0 / 60.0
		_step(ok and first, up and first, down and first, cancel and first)
		first = false
	_place_heroes()
	_bg.queue_redraw()
	_fg.queue_redraw()
	_veil.modulate.a = _fade_alpha()

func _step(ok: bool, up: bool, down: bool, cancel: bool) -> void:
	_clock += 1
	if not _fade.is_empty():
		_fade["f"] = int(_fade["f"]) + 1
		if _fade["phase"] == "out" and int(_fade["f"]) >= int(_fade["len"]):
			var cb: Callable = _fade["cb"]
			_fade = {"f": 0, "len": 18, "phase": "hold" if _mode == &"done" else "in", "cb": Callable()}
			if cb.is_valid():
				cb.call()
		elif _fade["phase"] == "in" and int(_fade["f"]) >= int(_fade["len"]):
			_fade = {}
		return   # mientras funde, todo espera
	match _mode:
		&"victory":
			_update_victory(ok)
		&"levelup":
			_update_levelup(ok, up, down, cancel)

func _fade_alpha() -> float:
	if _fade.is_empty():
		return 0.0
	var q := clampf(float(_fade["f"]) / float(_fade["len"]), 0.0, 1.0)
	match _fade["phase"]:
		"out":
			return q
		"in":
			return 1.0 - q
	return 1.0

func _fade_through(cb: Callable) -> void:
	if _fade.is_empty():
		_fade = {"f": 0, "len": 18, "phase": "out", "cb": cb}

func _fade_in() -> void:
	_fade = {"f": 0, "len": 18, "phase": "in", "cb": Callable()}

# ───────────────────────────── escena 1: plataformas ─────────────────────────────

func _update_victory(ok: bool) -> void:
	_t += 1
	if ok and _t > 40 and _t < int(VICT["end"]):
		_t = int(VICT["end"])   # Z/X salta la animación
	if _t >= int(VICT["end"]) + 45:
		_mode = &"transition"
		var any_up := false
		for h in heroes:
			if not (h["ups"] as Array).is_empty():
				any_up = true
		if any_up:
			_fade_through(_begin_levelups)
		else:
			_finish()

func _finish() -> void:
	_mode = &"done"
	_fade_through(func() -> void: finished.emit())

# ───────────────────────────── escena 2: subida de nivel ─────────────────────────────

func _begin_levelups() -> void:
	_queue.clear()
	for h in heroes:
		for lv in h["ups"]:
			_queue.append({"hid": h["id"], "lv": int(lv)})
	_next_levelup()

func _hero(id: StringName) -> Dictionary:
	for h in heroes:
		if h["id"] == id:
			return h
	return {}

func _next_levelup() -> void:
	if _queue.is_empty():
		_finish()
		return
	var q: Dictionary = _queue.pop_front()
	var h: Dictionary = _hero(q["hid"])
	var src: BattleHero = h["src"]
	var inc = HeroGrowth.roll(q["hid"])
	var old := {}
	for s in HeroGrowth.STATS:
		var k: StringName = s["k"]
		old[k] = HeroGrowth.value(src.stats, k)
		_gain(src, k, int(inc[k]))   # todos suben
	_lu = {"hid": q["hid"], "lv": q["lv"], "old": old, "inc": inc, "t": 0, "stage": "intro", "sel": 0, "th": 0.0, "n": 0, "bonus": {}}
	_mode = &"levelup"

## Sube un atributo (queda guardado para siempre) y, si el héroe sigue en el combate, también a él (PV/PT actuales suben lo mismo).
func _gain(src: BattleHero, k: StringName, n: int) -> void:
	HeroGrowth.add(src.stats.id, k, n)
	src.set(k, int(src.get(k)) + n)
	if k == &"max_hp":
		src.hp += n
	elif k == &"max_tp":
		src.tp += n

func _update_levelup(ok: bool, up: bool, down: bool, cancel: bool) -> void:
	var L := _lu
	var n := HeroGrowth.STATS.size()
	L["t"] = int(L["t"]) + 1
	var t: int = L["t"]
	match L["stage"]:
		"intro":
			if t >= 45:
				L["stage"] = "rows"
				L["t"] = 0
		"rows":
			if t >= n * 9 + 45:
				L["stage"] = "tally"
				L["t"] = 0
		"tally":
			if t >= 36:
				L["stage"] = "pick"
				L["t"] = 0
		"pick":   # elegir qué atributo recibe el bonus
			if up:
				L["sel"] = (int(L["sel"]) + n - 1) % n
			if down:
				L["sel"] = (int(L["sel"]) + 1) % n
			if ok and t > 12:
				L["stage"] = "roulette"
				L["t"] = 0
				L["th"] = randf() * TAU
				L["n"] = 0
		"roulette":   # la ruleta gira; el timing decide el número (1-5)
			L["th"] = float(L["th"]) + WHEEL_STEP
			if cancel:   # arrepentirse y elegir otro atributo
				L["stage"] = "pick"
				L["t"] = 0
				return
			if ok and t > 18:
				var k: StringName = HeroGrowth.STATS[int(L["sel"])]["k"]
				var got: int = int(HeroGrowth.wheel_pick(float(L["th"])))
				L["n"] = got
				_gain((_hero(L["hid"]))["src"], k, got)
				L["bonus"] = {"k": k, "n": got}
				L["stage"] = "result"
				L["t"] = 0
		"result":
			if t >= 110:
				L["stage"] = "leaving"
				if _queue.is_empty():
					_finish()
				else:
					_fade_through(_next_levelup)

# ───────────────────────────── colocar a los hermanos ─────────────────────────────

func _place_heroes() -> void:
	for h in heroes:
		var d: BattleHero = h["node"]
		d.visible = false
	if _mode == &"victory" or _mode == &"transition" and not _lu.has("hid"):
		for h in heroes:
			var P: Dictionary = _plat(h["id"])
			var lp := clampf(float(_t) / float(VICT["land"]), 0.0, 1.0)
			var from: Vector2 = P["from"]
			var gx: float = float(P["cx"]) + 8.0
			var gy: float = float(P["cy"]) - 2.0
			var hx := from.x + (gx - from.x) * _ease_out(lp)
			var hy := from.y + (gy - from.y) * lp - sin(lp * PI) * 110.0
			var landed := _t >= int(VICT["land"])
			var lvl_up := not (h["ups"] as Array).is_empty()
			var bob := 0.0
			if landed:
				bob = -absf(sin(float(_t - int(VICT["land"])) / 9.0)) * (14.0 if (lvl_up and _t > int(VICT["flag1"])) else 5.0)
			_put(h["node"], Vector2(hx, hy), bob, 0.9)
	elif _mode == &"levelup" and _lu.has("hid"):
		var st: String = _lu["stage"]
		var wheel_on := st in ["roulette", "result", "leaving"]
		if not wheel_on:
			var si := _ease_out(clampf(float(_lu["t"]) / 30.0, 0.0, 1.0)) if st == "intro" else 1.0
			var bob2 := -absf(sin(float(_clock) / 11.0)) * 9.0 * si
			_put(_hero(_lu["hid"])["node"], Vector2(158.0 + 12.0, 262.0 + 62.0), bob2, 1.8 * si)

func _put(d: BattleHero, virt: Vector2, bob: float, sc: float) -> void:
	d.visible = sc > 0.01
	d.scale = Vector2.ONE * sc * _s / 1.543
	d.position = _p(virt)
	d.offset = Vector2(0.0, bob * _s / maxf(d.scale.y, 0.001))

func _plat(id: StringName) -> Dictionary:
	return PLAT.get(id, PLAT[&"mario"])

# ───────────────────────────── dibujo ─────────────────────────────

func _ease_out(p: float) -> float:
	return 1.0 - (1.0 - p) * (1.0 - p)

func _ease_in_out(p: float) -> float:
	return 2.0 * p * p if p < 0.5 else 1.0 - pow(-2.0 * p + 2.0, 2.0) / 2.0

func _draw_layer(c: Node2D, layer_i: int) -> void:
	var vp := get_viewport().get_visible_rect().size
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if layer_i == 0:
		if _mode == &"levelup" and _lu.has("hid"):
			_draw_levelup_bg(c, vp)
		else:
			_draw_victory_bg(c, vp)
	c.draw_set_transform(Vector2(_ox, 0.0), 0.0, Vector2(_s, _s))
	if _mode == &"levelup" and _lu.has("hid"):
		_draw_levelup(c, layer_i)
	elif layer_i == 0:
		_draw_victory_scene(c)
	else:
		_draw_victory_front(c)

func _ell(c: CanvasItem, ctr: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		pts.append(ctr + Vector2(cos(a) * rx, sin(a) * ry))
	c.draw_colored_polygon(pts, col)

func _ell_line(c: CanvasItem, ctr: Vector2, rx: float, ry: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 41:
		var a := TAU * i / 40.0
		pts.append(ctr + Vector2(cos(a) * rx, sin(a) * ry))
	c.draw_polyline(pts, col, w, true)

func _rr(c: CanvasItem, r: Rect2, rad: int, fill: Color, border := Color(0, 0, 0, 0), bw := 0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(rad)
	sb.set_border_width_all(bw)
	sb.border_color = border
	sb.anti_aliasing = true
	c.draw_style_box(sb, r)

func _text(c: CanvasItem, s: String, pos: Vector2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, outline := Color(0, 0, 0, 0), ow := 0) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	var p := Vector2(x, pos.y)
	if ow > 0:
		c.draw_string_outline(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ow, outline)
	c.draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _orange_num(c: CanvasItem, s: String, pos: Vector2, size: int, align := HORIZONTAL_ALIGNMENT_RIGHT) -> void:
	_text(c, s, pos, size, Color("ffb21a"), align, Color("4a1c00"), maxi(3, int(size * 0.17)))

func _yellow_num(c: CanvasItem, s: String, pos: Vector2, size: int, align := HORIZONTAL_ALIGNMENT_RIGHT) -> void:
	_text(c, s, pos, size, Color("ffd23a"), align, Color("3b2a00"), 4)

func _gold_star(c: CanvasItem, ctr: Vector2, r: float, rot: float, fill: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := rot + i * PI / 5.0 - PI / 2.0
		var rr2 := r * 0.5 if i % 2 == 1 else r
		pts.append(ctr + Vector2(cos(a), sin(a)) * rr2)
	c.draw_colored_polygon(pts, fill)
	var line := pts.duplicate()
	line.append(pts[0])
	c.draw_polyline(line, Color("7a5300"), 2.0, true)

func _item_icon(c: CanvasItem, id: StringName, p: Vector2) -> void:   # icono de 22x22, origen arriba-izquierda
	if id == &"syrup":
		_rr(c, Rect2(p + Vector2(3, 7), Vector2(16, 14)), 4, Color("e8a317"))
		c.draw_rect(Rect2(p + Vector2(6, 11), Vector2(10, 5)), Color("fff3c4"))
		c.draw_rect(Rect2(p + Vector2(6, 2), Vector2(10, 6)), Color("7a4a10"))
	else:
		c.draw_rect(Rect2(p + Vector2(6, 12), Vector2(10, 9)), Color("f4e3c1"))
		var col := Color("43b047") if id == &"oneup" else Color("e0473f")
		var pts := PackedVector2Array()
		for i in 21:
			var a := PI + PI * i / 20.0
			pts.append(p + Vector2(11, 13) + Vector2(cos(a), sin(a)) * 10.5)
		c.draw_colored_polygon(pts, col)
		c.draw_circle(p + Vector2(6, 9), 2.4, Color.WHITE)
		c.draw_circle(p + Vector2(15, 8), 2.2, Color.WHITE)
		c.draw_circle(p + Vector2(11, 4), 1.8, Color.WHITE)

func _item_label(id: StringName) -> String:
	return BattleItems.item_name(id) if BattleItems.DEFS.has(id) else String(id)

# ── escena 1 ──

func _draw_victory_bg(c: Node2D, vp: Vector2) -> void:
	var xmin := -_ox / _s
	var xmax := W + _ox / _s
	# cielo en degradado: franjas
	var top := Color("a983c2")
	var mid := Color("cdb6e3")
	var bot := Color("efe6f8")
	var steps := 24
	for i in steps:
		var q := float(i) / steps
		var col := top.lerp(mid, q / 0.6) if q < 0.6 else mid.lerp(bot, (q - 0.6) / 0.4)
		c.draw_rect(Rect2(0, vp.y * q, vp.x, vp.y / steps + 1.0), col)
	c.draw_set_transform(Vector2(_ox, 0.0), 0.0, Vector2(_s, _s))
	for e in [[90, 70, 80, 34], [300, 105, 100, 40], [520, 55, 90, 36], [610, 125, 60, 30], [180, 150, 70, 26]]:
		_ell(c, Vector2(e[0], e[1]), e[2], e[3], Color(1, 1, 1, 0.14))
	var tt := float(_t)
	var bands := [[Color("f7f2fc"), 232.0, 9.0], [Color("ebe1f6"), 262.0, 6.0]]
	for bi in 2:
		var pts := PackedVector2Array([Vector2(xmin, H + 40.0)])
		var x := xmin
		while x <= xmax:
			pts.append(Vector2(x, float(bands[bi][1]) + sin(x / 36.0 + tt / 50.0 + bi * 2.0) * float(bands[bi][2])))
			x += 8.0
		pts.append(Vector2(xmax, H + 40.0))
		c.draw_colored_polygon(pts, bands[bi][0])
	c.draw_rect(Rect2(xmin, 300, xmax - xmin, H), Color("ebe1f6"))
	for e2 in [[80, 330, 90, 18], [330, 300, 110, 20], [560, 340, 80, 16]]:
		_ell(c, Vector2(e2[0], e2[1]), e2[2], e2[3], Color(0.745, 0.667, 0.882, 0.25))

func _draw_victory_scene(c: Node2D) -> void:   # plataformas, astas y banderas (por debajo de los hermanos)
	var t := _t
	for h in heroes:
		var P := _plat(h["id"])
		var ctr := Vector2(float(P["cx"]), float(P["cy"]))
		var rx: float = P["rx"]
		var ry: float = P["ry"]
		var dark := Color(String(P["dark"]))
		var col := Color(String(P["col"]))
		var lite := Color(String(P["lite"]))
		var lvl_up := not (h["ups"] as Array).is_empty()
		var p0: float = float(h["exp0"]) / float(h["need0"])
		var p1 := 1.0 if lvl_up else float(h["exp1"]) / float(h["need1"])
		var pf := p0 + (p1 - p0) * _ease_in_out(clampf(float(t - int(VICT["flag0"])) / float(int(VICT["flag1"]) - int(VICT["flag0"])), 0.0, 1.0))
		_ell(c, ctr + Vector2(0, 9), rx, ry, dark)
		_ell(c, ctr, rx, ry, col)
		for r in range(-3, 4):   # "escamas"
			for q in range(-6, 7):
				var ec := ctr + Vector2(q * 22.0 + (11.0 if (r + 3) % 2 == 1 else 0.0), r * 14.0)
				if absf((ec.x - ctr.x) / (rx - 8.0)) ** 2 + absf((ec.y - ctr.y) / (ry - 6.0)) ** 2 < 1.0:
					_ell_line(c, ec, 9.0, 5.0, Color(lite.r, lite.g, lite.b, 0.55), 2.0)
		_ell_line(c, ctr, rx, ry, dark, 4.0)
		# asta con su bola y la bandera: su altura marca cuánta experiencia falta
		var bx := ctr.x - rx * 0.78
		var by := ctr.y - 2.0
		var tx := bx - 16.0
		var ty := by - 150.0
		var k := 0.12 + 0.76 * pf
		var fx := bx + (tx - bx) * k
		var fy := by + (ty - by) * k
		c.draw_line(Vector2(bx, by), Vector2(tx, ty), Color("3b3b47"), 5.0, true)
		c.draw_circle(Vector2(tx, ty - 4), 10.0, Color("8a5a2b"))
		c.draw_arc(Vector2(tx, ty - 4), 10.0, 0, TAU, 24, Color("3a2410"), 2.5, true)
		_ell(c, Vector2(bx, by + 1), 11.0, 5.0, Color("c98a3a"))
		var wv := sin(float(t) / 7.0 + bx) * 3.0
		var flag := PackedVector2Array([Vector2(fx, fy - 12), Vector2(fx + 56, fy - 22 + wv), Vector2(fx + 56, fy + 8 + wv), Vector2(fx, fy + 16)])
		c.draw_colored_polygon(flag, Color("f8b232"))
		var fl := flag.duplicate()
		fl.append(flag[0])
		c.draw_polyline(fl, Color("7a4300"), 2.0, true)
		_ell(c, Vector2(fx + 28, fy - 3 + wv / 2.0), 9.0, 6.0, Color.WHITE)
		# sombra del hermano
		var landed := t >= int(VICT["land"])
		var lp := clampf(float(t) / float(VICT["land"]), 0.0, 1.0)
		var from: Vector2 = P["from"]
		var gx := ctr.x + 8.0
		var gy := ctr.y - 2.0
		var hx := from.x + (gx - from.x) * _ease_out(lp)
		_ell(c, Vector2(gx if landed else hx, gy + (2.0 if landed else 4.0)), 20.0 - (0.0 if landed else 4.0), 6.0, Color(0, 0, 0, 0.2))

func _draw_victory_front(c: Node2D) -> void:   # EXP, destellos, monedas y objetos (por encima de los hermanos)
	var t := _t
	for h in heroes:
		var P := _plat(h["id"])
		var cx: float = P["cx"]
		var cy: float = P["cy"]
		var ry: float = P["ry"]
		var lvl_up := not (h["ups"] as Array).is_empty()
		if t >= int(VICT["land"]):
			var q := _ease_out(clampf(float(t - int(VICT["land"])) / 12.0, 0.0, 1.0))
			var sc := 0.4 + 0.6 * q
			var by := cy + ry - 8.0
			c.draw_set_transform(Vector2(_ox, 0.0) + Vector2(cx, by) * _s * (1.0 - sc), 0.0, Vector2(_s, _s) * sc)
			var a := q
			_rr(c, Rect2(cx - 104, cy + 22, 62, 22), 10, Color(0.184, 0.184, 0.227, a))
			_text(c, "EXP", Vector2(cx - 73, cy + 38), 13, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER)
			_text(c, "+", Vector2(cx - 32, cy + 40), 20, Color(1, 0.82, 0.23, a))
			_orange_num(c, str(exp_total), Vector2(cx + 108, cy + 42), 40)
			c.draw_set_transform(Vector2(_ox, 0.0), 0.0, Vector2(_s, _s))
		if lvl_up and t > int(VICT["flag1"]):
			var kk := float(t - int(VICT["flag1"]))
			var p0: float = float(h["exp0"]) / float(h["need0"])
			var bx := cx - float(P["rx"]) * 0.78
			var by2 := cy - 2.0
			var fxx := bx + (bx - 16.0 - bx) * 0.88
			var fyy := by2 + (by2 - 150.0 - by2) * 0.88
			for i in 6:
				var ang := float(i) / 6.0 * TAU + kk / 20.0
				var rr2 := 26.0 + fmod(kk * 1.6 + i * 9.0, 30.0)
				var sp := Vector2(fxx + 22.0 + cos(ang) * rr2, fyy + sin(ang) * rr2)
				var s2 := 4.0 + (i % 3) * 2.0
				var al := 0.9 - fmod(kk * 1.6 + i * 9.0, 30.0) / 40.0
				var sp_pts := PackedVector2Array([sp + Vector2(0, -s2), sp + Vector2(s2 * 0.35, -s2 * 0.35), sp + Vector2(s2, 0), sp + Vector2(s2 * 0.35, s2 * 0.35),
					sp + Vector2(0, s2), sp + Vector2(-s2 * 0.35, s2 * 0.35), sp + Vector2(-s2, 0), sp + Vector2(-s2 * 0.35, -s2 * 0.35)])
				c.draw_colored_polygon(sp_pts, Color(1, 0.965, 0.659, clampf(al, 0.0, 1.0)))
			_text(c, "¡SUBE DE NIVEL!", Vector2(cx + 20.0, cy - 84.0 + sin(kk / 6.0) * 3.0), 15, Color("ffe566"), HORIZONTAL_ALIGNMENT_CENTER, Color("3b1a00"), 4)
			p0 = p0
	# monedas: abajo a la izquierda
	var mq := _ease_out(clampf(float(t - 25) / 26.0, 0.0, 1.0))
	var shown := roundi(coins0 + coins_got * clampf(float(t - 55) / 60.0, 0.0, 1.0))
	var ox := -(1.0 - mq) * 280.0
	_rr(c, Rect2(-22 + ox, 350, 292, 62), 18, Color("ffb23a"), Color("7a3a00"), 3)
	c.draw_circle(Vector2(28 + ox, 332), 17.0, Color("d9a441"))
	c.draw_arc(Vector2(28 + ox, 332), 17.0, 0, TAU, 24, Color("7a4a10"), 2.0, true)
	c.draw_rect(Rect2(18 + ox, 313, 20, 5), Color("7a4a10"))
	_text(c, "$", Vector2(28 + ox, 338), 15, Color("ffe566"), HORIZONTAL_ALIGNMENT_CENTER)
	_yellow_num(c, str(shown), Vector2(175 + ox, 394), 34)
	_orange_num(c, "+" + str(coins_got), Vector2(258 + ox, 394), 24)
	# objetos: abajo a la derecha (solo si ha caído alguno)
	var ids := items.keys()
	if not ids.is_empty():
		var iq := _ease_out(clampf(float(t - 95) / 26.0, 0.0, 1.0))
		var ix := (1.0 - iq) * 300.0
		_rr(c, Rect2(372 + ix, 350, 290, 62), 18, Color("ffb23a"), Color("7a3a00"), 3)
		_text(c, "¡OBJETO CONSEGUIDO!", Vector2(386 + ix, 366), 10, Color("7a3a00"))
		for i in mini(2, ids.size()):
			var id: StringName = ids[i]
			var y := 372.0 + i * 20.0
			_item_icon(c, id, Vector2(388 + ix, y - 4))
			_text(c, "%s  ×%d" % [_item_label(id), int(items[id])], Vector2(416 + ix, y + 12), 13, Color("2a1400"))

# ── escena 2 ──

func _lv_colors() -> Array:
	var green: bool = _lu["hid"] == &"luigi"
	return [Color("1fb04a") if green else Color("e8140c"), Color("7be89b") if green else Color("ff7a6b"), Color("0d6a2a") if green else Color("8a0a06"), green]

func _draw_levelup_bg(c: Node2D, vp: Vector2) -> void:
	for i in 24:
		var q := float(i) / 24.0
		c.draw_rect(Rect2(0, vp.y * q, vp.x, vp.y / 24.0 + 1.0), Color("5f4283").lerp(Color("3d2a58"), q))
	c.draw_set_transform(Vector2(_ox, 0.0), 0.0, Vector2(_s, _s))
	for e in [[560, 90, 110, 40], [80, 330, 120, 46], [330, 200, 150, 50], [600, 300, 100, 40]]:
		_ell(c, Vector2(e[0], e[1]), e[2], e[3], Color(0.549, 0.412, 0.686, 0.35))
	var xmin := -_ox / _s
	var xmax := W + _ox / _s
	var off := fmod(float(_clock) / 4.0, 44.0)
	var x := xmin - 44.0 + off
	while x < xmax + 44.0:
		_gold_star(c, Vector2(x, 16), 13.0, 0.15, Color("e0a80e"))
		_gold_star(c, Vector2(x + 22.0, H - 14.0), 12.0, -0.1, Color("e0a80e"))
		x += 44.0

func _draw_levelup(c: Node2D, layer_i: int) -> void:
	if layer_i == 0:
		_draw_lu_back(c)
	else:
		_draw_lu_front(c)

func _draw_lu_back(c: Node2D) -> void:   # estrella grande del hermano
	var L := _lu
	var cols := _lv_colors()
	var st: String = L["stage"]
	var si := _ease_out(clampf(float(L["t"]) / 30.0, 0.0, 1.0)) if st == "intro" else 1.0
	var wob := sin(float(_clock) / 25.0) * 0.05
	var rot := wob + (1.0 - si) * 1.2
	var pts := PackedVector2Array()
	for i in 10:
		var a := i * PI / 5.0 - PI / 2.0 + rot
		var r := (84.0 if i % 2 == 1 else 142.0) * si
		pts.append(Vector2(158, 262) + Vector2(cos(a), sin(a)) * r)
	c.draw_colored_polygon(pts, cols[0])
	var line := pts.duplicate()
	line.append(pts[0])
	c.draw_polyline(line, cols[1], 3.0, true)

func _draw_lu_front(c: Node2D) -> void:
	var L := _lu
	var cols := _lv_colors()
	var col_d: Color = cols[2]
	var green: bool = cols[3]
	var st: String = L["stage"]
	var t: int = L["t"]
	var n := HeroGrowth.STATS.size()
	var h := _hero(L["hid"])
	var src: BattleHero = h["src"]
	# título
	_text(c, String(h["name"]).to_upper(), Vector2(218, 58), 36, Color("a6f0b6") if green else Color("ffa79a"), HORIZONTAL_ALIGNMENT_LEFT, Color("3b1414"), 8)
	var ty := minf(1.0, float(t) / 20.0) if st == "intro" else 1.0
	_text(c, "¡SUBE DE NIVEL!", Vector2(118, 104), 32, Color(1, 0.84, 0.2, ty), HORIZONTAL_ALIGNMENT_LEFT, Color(0.1, 0.14, 0.31, ty), 8)
	_text(c, "NV", Vector2(96, 178), 15, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, col_d, 4)
	_yellow_num(c, str(L["lv"]), Vector2(176, 184), 40, HORIZONTAL_ALIGNMENT_LEFT)
	# atributos: "actual + subida"
	for i in n:
		var s: Dictionary = HeroGrowth.STATS[i]
		var k: StringName = s["k"]
		var y := 172.0 + i * 37.0
		var appear := -1.0 if st == "intro" else ((float(t) - i * 9.0) / 10.0 if st == "rows" else 1.0)
		if appear <= 0.0:
			continue
		var q := _ease_out(clampf(appear, 0.0, 1.0))
		var ox := (1.0 - q) * 90.0
		var inc: int = int(L["inc"][k])
		var base: int = int(L["old"][k])
		var tally := _ease_in_out(clampf(float(t) / 26.0, 0.0, 1.0)) if st == "tally" else (0.0 if st == "rows" else 1.0)
		var bonus: Dictionary = L["bonus"]
		var is_b: bool = (not bonus.is_empty()) and bonus["k"] == k
		var bonus_t := (_ease_out(clampf(float(t) / 24.0, 0.0, 1.0)) if st == "result" else 1.0) if is_b else 0.0
		var main := base + roundi(inc * tally) + (roundi(int(bonus["n"]) * bonus_t) if is_b else 0)
		var chosen := st in ["pick", "roulette", "result", "leaving"] and int(L["sel"]) == i
		var a := q
		if chosen:
			var sw := sin(float(_clock) / 7.0) * 3.0
			_rr(c, Rect2(318 + ox, y - 24, 306, 34), 10, Color(0, 0, 0, 0), Color(1, 1, 1, a), 3)
			c.draw_colored_polygon(PackedVector2Array([Vector2(304 + sw + ox, y - 14), Vector2(316 + sw + ox, y - 7), Vector2(304 + sw + ox, y)]), Color("ffd23a"))
		_rr(c, Rect2(326 + ox, y - 19, 112, 24), 5, Color(0.788, 0.769, 0.831, a))
		_text(c, String(s["label"]), Vector2(334 + ox, y - 2), 12, Color(0.29, 0.271, 0.376, a))
		_yellow_num(c, str(main), Vector2(540 + ox, y + 3), 24)
		var plus := 0.0
		var val := 0
		var pc := Color("ffe566")
		if tally < 1.0:
			plus = 1.0 - tally
			val = inc
		elif is_b and (st == "result" or st == "leaving"):
			plus = 1.0
			val = int(bonus["n"])
			pc = Color("7dffb0")
		if plus > 0.0:
			_text(c, "+", Vector2(562 + ox, y), 15, Color(pc.r, pc.g, pc.b, a * plus), HORIZONTAL_ALIGNMENT_CENTER)
			_yellow_num(c, str(val), Vector2(612 + ox, y + 3), 24)
	# ruleta del bonus
	if st in ["roulette", "result", "leaving"]:
		_draw_wheel(c, green, st, t)
	# texto de ayuda
	var sel: Dictionary = HeroGrowth.STATS[int(L["sel"])]
	var msg := ""
	match st:
		"rows", "tally":
			msg = "¡Todos los atributos suben!"
		"pick":
			msg = "¡Bonus! Elige un atributo (↑↓) y pulsa Z o X para girar la ruleta"
		"roulette":
			msg = "¡Pulsa Z o X para parar la ruleta! ¡Busca el 5!  ·  C: elegir otro atributo"
		"result", "leaving":
			msg = ("¡PERFECTO! +%d %s" if int(L["n"]) >= 5 else "+%d %s") % [int(L["n"]), sel["label"]]
	if msg != "":
		_text(c, msg, Vector2(W / 2.0, 388), 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, Color("1a1030"), 5)
	src = src

func _draw_wheel(c: Node2D, green: bool, st: String, t: int) -> void:
	var L := _lu
	var R := 108.0
	var q := _ease_out(clampf(float(t) / 14.0, 0.0, 1.0)) if st == "roulette" else 1.0
	var ctr := Vector2(158, 262)
	c.draw_set_transform(Vector2(_ox, 0.0) + ctr * _s * (1.0 - q), 0.0, Vector2(_s, _s) * q)
	_ell(c, ctr + Vector2(4, 6), R + 8.0, R + 8.0, Color(0, 0, 0, 0.35))
	_ell(c, ctr, R + 7.0, R + 7.0, Color.WHITE)
	var a0: float = float(L["th"])
	var i := 0
	for w in HeroGrowth.WHEEL:
		var num: int = int(w[0])
		var a1 := a0 + deg_to_rad(float(w[1]))
		var mid := (a0 + a1) * 0.5
		var five := num == 5
		var col: Color
		if five:
			col = Color("ffd23a")
		elif i % 2 == 1:
			col = Color("22a552") if green else Color("e8442f")
		else:
			col = Color("63d68b") if green else Color("ff8a5c")
		var pts := PackedVector2Array([ctr])
		var steps := maxi(2, int((a1 - a0) / 0.08))
		for j in steps + 1:
			var ang := a0 + (a1 - a0) * j / steps
			pts.append(ctr + Vector2(cos(ang), sin(ang)) * R)
		c.draw_colored_polygon(pts, col)
		var edge := pts.duplicate()
		edge.append(ctr)
		c.draw_polyline(edge, Color("2a2140"), 2.0, true)
		_text(c, str(num), ctr + Vector2(cos(mid), sin(mid)) * R * 0.68 + Vector2(0, 9), 30 if five else 24, Color("b3320a") if five else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, Color("2a2140"), 5)
		a0 = a1
		i += 1
	_ell(c, ctr, 30.0, 30.0, Color("2a2140"))
	_ell(c, ctr, 26.0, 26.0, Color.WHITE)
	_text(c, "?" if st == "roulette" else str(L["n"]), ctr + Vector2(0, 11), 30, Color("2a2140"), HORIZONTAL_ALIGNMENT_CENTER)
	var arrow := PackedVector2Array([ctr + Vector2(0, -R + 10), ctr + Vector2(-14, -R - 16), ctr + Vector2(14, -R - 16)])
	c.draw_colored_polygon(arrow, Color("ffd23a"))
	var al := arrow.duplicate()
	al.append(arrow[0])
	c.draw_polyline(al, Color("2a2140"), 3.0, true)
	c.draw_set_transform(Vector2(_ox, 0.0), 0.0, Vector2(_s, _s))
