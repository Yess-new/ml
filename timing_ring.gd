extends Node2D
## ANILLO DE TIMING del ataque tándem: dibuja el anillo que se cierra sobre un personaje (con el botón que hay que pulsar) y los
## destellos al acertar. Lo crea battle_ui.gd; lee el estado de Battle (ring y bursts). Se dibuja por código, sin escena.
##   ring   = { pos (mundo), q (0 → 1, se cierra), color, key (letra del botón), badge (mundo: dónde va la chapa del botón) }
##   bursts = [ { pos, color, t (fotogramas) } ]

var battle   ## Battle (Combate/battle.gd)
var _box := StyleBoxFlat.new()

func _ready() -> void:
	_box.set_corner_radius_all(7)
	_box.set_border_width_all(3)
	_box.border_color = Color.WHITE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if battle == null:
		return
	var xf: Transform2D = battle.get_global_transform_with_canvas()   # mundo del combate → pantalla (la UI no sigue a la cámara)
	var sc: float = xf.get_scale().x
	var r: Dictionary = battle.ring
	if not r.is_empty():
		var p: Vector2 = xf * (r["pos"] as Vector2)
		var col: Color = r["color"]
		var rad: float = (8.0 + 36.0 * (1.0 - float(r["q"]))) * sc
		draw_arc(p, rad, 0.0, TAU, 56, Color.WHITE, 9.0 * sc, true)
		draw_arc(p, rad, 0.0, TAU, 56, col, 5.0 * sc, true)
		var bp: Vector2 = xf * (r["badge"] as Vector2)
		var rect := Rect2(bp - Vector2(18.0, 16.0) * sc, Vector2(36.0, 32.0) * sc)
		_box.bg_color = col
		draw_style_box(_box, rect)
		var font := ThemeDB.fallback_font
		draw_string(font, bp + Vector2(-18.0, 8.0) * sc, str(r["key"]), HORIZONTAL_ALIGNMENT_CENTER, 36.0 * sc, int(22.0 * sc), Color.WHITE)
	for b in battle.bursts:   # destello: anillo que se expande y rayos
		var k: float = float(int(b["t"])) / 16.0
		var bc: Color = b["color"]
		bc.a = 1.0 - k
		var bpos: Vector2 = xf * (b["pos"] as Vector2)
		var br: float = (12.0 + k * 56.0) * sc
		draw_arc(bpos, br, 0.0, TAU, 40, bc, maxf(1.0, 6.0 * (1.0 - k)) * sc, true)
		for i in 8:
			var dir := Vector2.from_angle(TAU * i / 8.0)
			draw_line(bpos + dir * br * 0.55, bpos + dir * br * 1.15, bc, maxf(1.0, 4.0 * (1.0 - k)) * sc, true)
	if not battle.shell.is_empty():   # concha (tándem Concha Verde): { pos, rot }
		var sp2: Vector2 = xf * (battle.shell["pos"] as Vector2)
		var sr: float = float(battle.shell["rot"])
		for i in 3:   # estela de humo
			var tp: Vector2 = sp2 - (battle.shell.get("dir", Vector2.RIGHT) as Vector2) * (14.0 + i * 12.0) * sc
			draw_circle(tp, (6.0 - i * 1.5) * sc, Color(1, 1, 1, 0.55 - i * 0.15))
		draw_set_transform(sp2, sr, Vector2.ONE * sc)
		draw_circle(Vector2.ZERO, 15.0, Color("ffffff"))
		draw_circle(Vector2.ZERO, 12.5, Color("3fae3a"))
		draw_circle(Vector2(-3.0, -3.0), 7.0, Color("5fd35a"))
		for i in 3:
			var a := TAU * i / 3.0 + 0.5
			draw_line(Vector2.ZERO, Vector2.from_angle(a) * 12.0, Color("2a7a28"), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var font2 := ThemeDB.fallback_font
	if not battle.combo.is_empty():   # contador de golpes sobre el enemigo
		var cp: Vector2 = xf * (battle.combo["pos"] as Vector2)
		var pts := PackedVector2Array()
		for i in 16:
			var rr := (30.0 if i % 2 == 0 else 19.0) * sc
			pts.append(cp + Vector2.from_angle(TAU * i / 16.0 - PI / 2.0) * rr)
		draw_colored_polygon(pts, Color("ffcf24"))
		draw_polyline(PackedVector2Array(pts) + PackedVector2Array([pts[0]]), Color("8a3b00"), 3.0 * sc, true)
		var ct := str(battle.combo["n"])
		draw_string_outline(font2, cp + Vector2(-20.0, 11.0) * sc, ct, HORIZONTAL_ALIGNMENT_CENTER, 40.0 * sc, int(32.0 * sc), 8, Color("5a2400"))
		draw_string(font2, cp + Vector2(-20.0, 11.0) * sc, ct, HORIZONTAL_ALIGNMENT_CENTER, 40.0 * sc, int(32.0 * sc), Color.WHITE)
	var fx: HitFxStyle = battle.fx
	for im in battle.impacts:   # destello al golpear a un enemigo (su sprite, o uno provisional por código)
		var ik: float = float(int(im["t"])) / float(maxi(1, fx.impact_frames))
		var ip: Vector2 = xf * (im["pos"] as Vector2)
		var ia := 1.0 - ik
		var isc: float = (0.5 + ik) * fx.impact_scale * sc
		if fx.impact_texture:
			var isz := fx.impact_texture.get_size() * isc
			draw_texture_rect(fx.impact_texture, Rect2(ip - isz * 0.5, isz), false, Color(1, 1, 1, ia))
		else:
			var icol: Color = fx.impact_color_a if im["odd"] else fx.impact_color_b
			var ipts := PackedVector2Array()
			for i in 24:
				ipts.append(ip + Vector2.from_angle(TAU * i / 24.0) * (44.0 if i % 2 == 0 else 17.0) * isc)
			draw_colored_polygon(ipts, Color(icol, ia * 0.9))
			draw_circle(ip, 15.0 * isc, Color(1, 1, 1, ia))
	var nfont: Font = fx.font if fx.font else font2
	for hs in battle.hit_stars:   # daño a un enemigo: estrella con el número. Se queda mientras dura el ataque; al acabar se desvanece (y sale el TOTAL)
		var is_total: bool = hs["total"]
		var out: int = int(hs["out"])
		var kk: float = 0.0 if out < 0 else float(out) / float(int(hs["len"]))
		var pop: float = minf(1.0, float(int(hs["t"])) / 6.0)
		var fade: float = maxf(0.0, (kk - 0.75) / 0.25)
		var rise: float = 0.0 if is_total else kk * 18.0
		var hp: Vector2 = xf * (hs["pos"] as Vector2) + Vector2(0.0, -rise * sc)
		var rs := (0.6 + 0.4 * pop) * (1.0 - fade * 0.3) * (fx.total_scale if is_total else 1.0) * fx.star_scale
		var al := 1.0 - fade
		var scol: Color = fx.total_color if is_total else fx.star_color
		var stex: Texture2D = fx.total_texture if (is_total and fx.total_texture) else fx.star_texture
		if stex:
			var ssz := stex.get_size() * sc * rs
			draw_texture_rect(stex, Rect2(hp - ssz * 0.5, ssz), false, Color(1, 1, 1, al))
		else:
			var hpts := PackedVector2Array()
			for i in 16:
				hpts.append(hp + Vector2.from_angle(TAU * i / 16.0 - PI / 2.0) * (30.0 if i % 2 == 0 else 19.0) * sc * rs)
			draw_colored_polygon(hpts, Color(scol, al))
			draw_polyline(hpts + PackedVector2Array([hpts[0]]), Color(fx.star_outline, al), 3.0 * sc, true)
		var hfs := int(fx.number_size * sc * rs)
		var hw := 90.0 * sc
		var ncol: Color = fx.total_number_color if is_total else fx.number_color
		var ny: float = (4.0 if is_total else 10.0) * sc * rs   # el TOTAL lleva el número un poco más arriba, con la palabra debajo
		draw_string_outline(nfont, hp + Vector2(-hw * 0.5, ny), str(hs["text"]), HORIZONTAL_ALIGNMENT_CENTER, hw, hfs, 8, Color(fx.number_outline, al))
		draw_string(nfont, hp + Vector2(-hw * 0.5, ny), str(hs["text"]), HORIZONTAL_ALIGNMENT_CENTER, hw, hfs, Color(ncol, al))
		if is_total and fx.total_text != "":
			var tfs := int(fx.number_size * 0.5 * sc * rs)
			var ty: float = ny + 15.0 * sc * rs
			draw_string_outline(nfont, hp + Vector2(-hw * 0.5, ty), fx.total_text, HORIZONTAL_ALIGNMENT_CENTER, hw, tfs, 6, Color(fx.number_outline, al))
			draw_string(nfont, hp + Vector2(-hw * 0.5, ty), fx.total_text, HORIZONTAL_ALIGNMENT_CENTER, hw, tfs, Color(1, 1, 1, al))
	# (las celebraciones OK / GOOD / GREAT / EXCELLENT son nodos RankBadge en ui/battle_ui.tscn → Celebrations)
	for pu in battle.popups:   # valoraciones (OK! GOOD! GREAT! LUCKY!): suben y se desvanecen
		var k2: float = float(int(pu["t"])) / float(int(pu["life"]))
		var pc: Color = pu["color"]
		pc.a = 1.0 - maxf(0.0, (k2 - 0.6) / 0.4)
		var pp: Vector2 = xf * (pu["pos"] as Vector2) + Vector2(0.0, -k2 * 22.0 * sc)
		var fs := int(34.0 * sc)
		draw_string_outline(font2, pp + Vector2(-80.0 * sc, 0.0), str(pu["text"]), HORIZONTAL_ALIGNMENT_CENTER, 160.0 * sc, fs, 9, Color(0.1, 0.05, 0.0, pc.a))
		draw_string(font2, pp + Vector2(-80.0 * sc, 0.0), str(pu["text"]), HORIZONTAL_ALIGNMENT_CENTER, 160.0 * sc, fs, pc)
