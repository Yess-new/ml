@tool
extends CanvasLayer
## SÍMBOLOS DE ACCIÓN del overworld (abajo a la derecha), como en Mario & Luigi: un bloque por hermano con su botón,
## el símbolo de lo que hará ese botón ahora (saltar, hablar...) y su vida.
##  · Es un autoload (ActionHUD). Para cambiar su aspecto abre ui/action_hud.tscn y toca el Inspector: se ve en el editor.
##  · Se oculta solo en combate, con el menú de pausa abierto, sin héroes en la habitación y (si quieres) en diálogos/cinemáticas.
##  · Del hermano que no está en el grupo (GameState.party) no se muestra nada.
##  · ACCIONES: &"saltar" (por defecto) y &"hablar" (con un NPC al lado). Para forzar otra desde código:
##      ActionHUD.set_override(&"mario", &"hablar")   ·   ActionHUD.set_override(&"mario", &"")  (quitar)
##    Para añadir una acción nueva con su dibujo: añádela en "Iconos extra" (nombre -> imagen) y úsala con set_override.

@export var ver_en_editor: bool = false:   ## mostrar una vista previa en el editor (apagado: solo se ve al jugar)
	set(v):
		ver_en_editor = v
		_redraw()

@export_group("Posición y tamaño")
@export var escala: float = 1.2:   ## tamaño de todo el HUD
	set(v):
		escala = v
		_redraw()
@export var margen: Vector2 = Vector2(40, 64):   ## px desde la esquina de abajo a la derecha hasta el bloque de Mario
	set(v):
		margen = v
		_redraw()
@export var separacion: Vector2 = Vector2(-112, 24):   ## dónde va el bloque de Luigi respecto al de Mario
	set(v):
		separacion = v
		_redraw()
@export var luigi_delante: bool = true   ## el bloque de Luigi se dibuja encima del de Mario (como en el juego)

@export_group("Mario")
@export var stats_mario: CharacterStats = preload("res://data/mario_stats.tres")   ## de aquí salen su vida y su botón
@export var color_mario: Color = Color(0.86, 0.2, 0.18):   ## color de su base
	set(v):
		color_mario = v
		_redraw()
@export var letra_mario: String = "":   ## letra del botón (vacío = la tecla real de su salto, p. ej. Z)
	set(v):
		letra_mario = v
		_redraw()

@export_group("Luigi")
@export var stats_luigi: CharacterStats = preload("res://data/luigi_stats.tres")
@export var color_luigi: Color = Color(0.2, 0.68, 0.24):
	set(v):
		color_luigi = v
		_redraw()
@export var letra_luigi: String = "":   ## vacío = la tecla real de su salto (p. ej. X)
	set(v):
		letra_luigi = v
		_redraw()

@export_group("Iconos")
@export var icono_saltar: Texture2D:   ## imagen para "saltar" (vacío = flecha dibujada por código)
	set(v):
		icono_saltar = v
		_redraw()
@export var icono_hablar: Texture2D:   ## imagen para "hablar" (vacío = globo dibujado por código)
	set(v):
		icono_hablar = v
		_redraw()
@export var iconos_extra: Dictionary = {}   ## acciones nuevas: nombre (StringName) -> Texture2D (se usan con set_override)
@export var tamano_icono: float = 58.0:   ## px que mide el símbolo
	set(v):
		tamano_icono = v
		_redraw()
@export var color_icono: Color = Color.WHITE   ## color de los símbolos dibujados por código

@export_group("Vida")
@export var mostrar_vida: bool = true:
	set(v):
		mostrar_vida = v
		_redraw()
@export var color_corazon: Color = Color(0.93, 0.16, 0.22)
@export var color_numero: Color = Color(1.0, 0.85, 0.25)
@export var color_fondo_vida: Color = Color(0.1, 0.1, 0.14, 0.85)

@export_group("Comportamiento")
@export var ocultar_en_dialogos: bool = true      ## esconder mientras hay un globo de texto abierto
@export var ocultar_en_cinematicas: bool = true   ## esconder durante las cinemáticas
@export var rebote: float = 3.0                   ## px que flota el símbolo arriba y abajo
@export var velocidad_rebote: float = 3.0
@export var fundido: float = 8.0                  ## rapidez al aparecer/desaparecer (más = más rápido)

var _vista: Control
var _t := 0.0
var _alpha := 1.0
var _overrides := {}                       # id del héroe -> acción forzada
var _state := {}                           # id -> {action, pop, press, visible, hp}

func _ready() -> void:
	layer = 40   # encima del juego, debajo del menú de pausa y de los globos de texto
	_vista = get_node_or_null("Vista") as Control
	if _vista == null:
		_vista = Control.new()
		_vista.name = "Vista"
		add_child(_vista)
	_vista.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _vista.draw.is_connected(_on_vista_draw):
		_vista.draw.connect(_on_vista_draw)
	for id in [&"mario", &"luigi"]:
		_state[id] = {"action": &"saltar", "pop": 0.0, "press": 0.0, "visible": true, "hp": 0}

## Fuerza la acción que muestra un hermano (&"" = volver a la automática).
func set_override(hero_id: StringName, action: StringName) -> void:
	if action == &"":
		_overrides.erase(hero_id)
	else:
		_overrides[hero_id] = action

func _redraw() -> void:
	if _vista:
		_vista.queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	if Engine.is_editor_hint():
		_redraw()
		return
	var visible_now := _should_show()
	_alpha = move_toward(_alpha, 1.0 if visible_now else 0.0, delta * fundido)
	var heroes := _heroes()
	for id in [&"mario", &"luigi"]:
		var st: Dictionary = _state[id]
		var h: Hero = heroes.get(id)
		st["visible"] = h != null
		if h == null:
			continue
		var a := _action_for(id, h)
		if a != st["action"]:
			st["action"] = a
			st["pop"] = 1.0
		st["pop"] = maxf(0.0, float(st["pop"]) - delta * 4.0)
		st["press"] = maxf(0.0, float(st["press"]) - delta * 6.0)
		if show and Input.is_action_just_pressed(h.talk_action()):
			st["press"] = 1.0
		var s := _stats(id)
		st["hp"] = GameState.hp_of(s) if s else 0
	_redraw()

## ¿Se ve el HUD ahora?
func _should_show() -> bool:
	if _heroes().is_empty():
		return false
	var pm := get_node_or_null("/root/PauseMenu")
	if pm and bool(pm.get("is_open")):
		return false
	var dm := get_node_or_null("/root/DialogueManager")
	if dm:
		if ocultar_en_cinematicas and int(dm.get("cutscene_active")) > 0:
			return false
		if ocultar_en_dialogos and bool(dm.call("is_talking")):
			return false
	var st := get_node_or_null("/root/SceneTransition")
	if st and bool(st.get("busy")):
		return false
	return true

## Mario y Luigi que andan ahora en la habitación: {&"mario": Hero, &"luigi": Hero}
func _heroes() -> Dictionary:
	var out := {}
	for n in get_tree().get_nodes_in_group("overworld_heroes"):
		var h := n as Hero
		if h == null or not h.is_visible_in_tree() or h.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		out[h.hero_id()] = h
	return out

## Qué haría ahora el botón de este hermano.
func _action_for(id: StringName, h: Hero) -> StringName:
	if _overrides.has(id):
		return _overrides[id]
	var dm := get_node_or_null("/root/DialogueManager")
	if dm and not h.is_follower() and h._grounded and dm.call("npc_near", h) != null:
		return &"hablar"
	return &"saltar"

func _stats(id: StringName) -> CharacterStats:
	return stats_mario if id == &"mario" else stats_luigi

## Letra del botón: la escrita en el Inspector o la tecla real de su acción de salto.
func _letter(id: StringName) -> String:
	var custom := letra_mario if id == &"mario" else letra_luigi
	if custom != "":
		return custom
	var s := _stats(id)
	var action: StringName = s.jump_action if s else (&"jump_mario" if id == &"mario" else &"jump_luigi")
	if id == &"luigi":
		action = &"jump_luigi"
	if InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				var k := ev as InputEventKey
				var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
				return OS.get_keycode_string(code)
	return "A" if id == &"mario" else "B"

# ───────────────────────────── dibujo ─────────────────────────────

func _on_vista_draw() -> void:
	if Engine.is_editor_hint() and not ver_en_editor:
		return   # en el editor no se dibuja (se ve encima del Inspector y estorba)
	var size := _vista.size
	var a := 1.0 if Engine.is_editor_hint() else _alpha
	if a <= 0.01:
		return
	var mario_pos := size - margen - Vector2(52, 52) * escala
	var luigi_pos := mario_pos + separacion * escala
	var order: Array = [[&"mario", mario_pos], [&"luigi", luigi_pos]]
	if not luigi_delante:
		order.reverse()
	var solo := false
	if not Engine.is_editor_hint():
		solo = int(_state[&"mario"]["visible"]) + int(_state[&"luigi"]["visible"]) == 1
	for e in order:
		var id: StringName = e[0]
		var pos: Vector2 = e[1]
		if Engine.is_editor_hint():
			_draw_block(id, pos, &"saltar" if id == &"mario" else &"hablar", 0.0, 0.0, _stats(id).max_hp if _stats(id) else 30, a)
			continue
		var st: Dictionary = _state[id]
		if not st["visible"]:
			continue
		if solo:
			pos = mario_pos   # un solo hermano: ocupa el sitio principal
		_draw_block(id, pos, st["action"], st["pop"], st["press"], st["hp"], a)

## Un bloque: base de color, símbolo de la acción, letra del botón y vida.
func _draw_block(id: StringName, c: Vector2, action: StringName, pop: float, press: float, hp: int, a: float) -> void:
	var v := _vista
	var k := escala
	var col := color_mario if id == &"mario" else color_luigi
	var squash := 1.0 - 0.18 * press
	# base (elipse de color con brillo)
	var base_c := c + Vector2(0, 22) * k
	_ellipse(v, base_c + Vector2(0, 4) * k, Vector2(48, 20) * k * Vector2(1.0, squash), Color(0, 0, 0, 0.35 * a))
	_ellipse(v, base_c, Vector2(46, 19) * k * Vector2(1.0, squash), Color(col.darkened(0.35), a))
	_ellipse(v, base_c - Vector2(0, 4) * k * squash, Vector2(40, 14) * k * Vector2(1.0, squash), Color(col, a))
	_ellipse(v, base_c - Vector2(8, 9) * k * squash, Vector2(18, 5) * k, Color(col.lightened(0.45), 0.8 * a))
	# símbolo (flota; da un salto al cambiar de acción; se hunde al pulsar)
	var bob := sin(_t * velocidad_rebote + (0.0 if id == &"mario" else 1.7)) * rebote
	var icon_scale := (1.0 + 0.35 * sin(pop * PI)) * (1.0 - 0.12 * press)
	var icon_c := c + Vector2(0, -16 + bob + 10.0 * press) * k
	_draw_icon(action, icon_c, tamano_icono * k * icon_scale, a)
	# letra del botón
	var lc := base_c + Vector2(40, 2) * k
	v.draw_circle(lc, 13 * k, Color(0.12, 0.12, 0.16, a))
	v.draw_circle(lc, 11 * k, Color(1, 1, 1, a))
	_text_center(_letter(id), lc + Vector2(0, 1) * k, int(16 * k), Color(0.12, 0.12, 0.16, a))
	# vida
	if mostrar_vida:
		var hp_r := Rect2(base_c + Vector2(-40, 20) * k, Vector2(80, 26) * k)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(color_fondo_vida, color_fondo_vida.a * a)
		sb.set_corner_radius_all(int(13 * k))
		sb.border_color = Color(col.darkened(0.2), a)
		sb.set_border_width_all(maxi(1, int(2 * k)))
		v.draw_style_box(sb, hp_r)
		_heart(v, hp_r.position + Vector2(18, 13) * k, 9 * k, Color(color_corazon, a))
		_text_center(str(hp), hp_r.position + Vector2(52, 14) * k, int(17 * k), Color(color_numero, a), true)

func _draw_icon(action: StringName, c: Vector2, size: float, a: float) -> void:
	var tex: Texture2D = null
	match action:
		&"saltar": tex = icono_saltar
		&"hablar": tex = icono_hablar
		_: tex = iconos_extra.get(action) as Texture2D
	if tex:
		var ts := tex.get_size()
		var f := size / maxf(ts.x, ts.y)
		_vista.draw_texture_rect(tex, Rect2(c - ts * f * 0.5, ts * f), false, Color(1, 1, 1, a))
		return
	if action == &"hablar":
		_draw_talk(c, size, a)
	else:
		_draw_jump(c, size, a)

## Flecha de salto (como la de Mario & Luigi): gruesa, con sombra y contorno.
func _draw_jump(c: Vector2, s: float, a: float) -> void:
	var u := s / 60.0
	var pts := PackedVector2Array([Vector2(0, -30), Vector2(26, -2), Vector2(11, -2), Vector2(11, 26), Vector2(-11, 26), Vector2(-11, -2), Vector2(-26, -2)])
	var shade := PackedVector2Array()
	var body := PackedVector2Array()
	for p in pts:
		shade.append(c + (p + Vector2(4, 4)) * u)
		body.append(c + p * u)
	_vista.draw_colored_polygon(shade, Color(0, 0, 0, 0.35 * a))
	_vista.draw_colored_polygon(body, Color(color_icono, a))
	# cara de sombra a la derecha (volumen)
	var side := PackedVector2Array([c + Vector2(0, -30) * u, c + Vector2(26, -2) * u, c + Vector2(11, -2) * u, c + Vector2(11, 26) * u, c + Vector2(2, 26) * u, c + Vector2(2, -22) * u])
	_vista.draw_colored_polygon(side, Color(color_icono.darkened(0.25), a))
	body.append(body[0])
	_vista.draw_polyline(body, Color(0.15, 0.15, 0.2, a), maxf(2.0, 2.5 * u), true)

## Globo de hablar: bocadillo blanco con tres puntos.
func _draw_talk(c: Vector2, s: float, a: float) -> void:
	var u := s / 60.0
	var outline := Color(0.15, 0.15, 0.2, a)
	var tail := PackedVector2Array([c + Vector2(-12, 10) * u, c + Vector2(-20, 28) * u, c + Vector2(2, 14) * u])
	_ellipse(_vista, c + Vector2(3, 3) * u, Vector2(30, 21) * u, Color(0, 0, 0, 0.35 * a))
	_vista.draw_colored_polygon(tail, outline)
	_ellipse(_vista, c, Vector2(30, 21) * u, outline)
	_ellipse(_vista, c, Vector2(27, 18) * u, Color(color_icono, a))
	var inner_tail := PackedVector2Array([c + Vector2(-10, 9) * u, c + Vector2(-16, 22) * u, c + Vector2(0, 13) * u])
	_vista.draw_colored_polygon(inner_tail, Color(color_icono, a))
	for i in 3:
		_vista.draw_circle(c + Vector2(-11 + i * 11, 0) * u, 3.6 * u, outline)

func _ellipse(v: Control, c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		var ang := TAU * i / 32.0
		pts.append(c + Vector2(cos(ang) * r.x, sin(ang) * r.y))
	v.draw_colored_polygon(pts, col)

func _heart(v: Control, c: Vector2, r: float, col: Color) -> void:
	v.draw_circle(c + Vector2(-r * 0.5, -r * 0.25), r * 0.55, col)
	v.draw_circle(c + Vector2(r * 0.5, -r * 0.25), r * 0.55, col)
	v.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.02, -r * 0.05), c + Vector2(r * 1.02, -r * 0.05), c + Vector2(0, r * 0.95)]), col)

func _text_center(t: String, c: Vector2, size: int, col: Color, outline := false) -> void:
	var font := ThemeDB.fallback_font
	var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var p := c + Vector2(-ts.x * 0.5, ts.y * 0.32)
	if outline:
		_vista.draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(2, int(size / 5.0)), Color(0, 0, 0, col.a))
	_vista.draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
