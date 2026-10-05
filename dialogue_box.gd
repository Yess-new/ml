class_name DialogueBox
extends CanvasLayer
## GLOBO DE TEXTO del overworld (ui/dialogue_box.tscn), como en el prototipo HTML: cuadrado tipo cómic, el texto sale LETRA A LETRA,
## como mucho "lines_per_page" líneas por globo. Z: completa el texto → pasa al siguiente globo → cierra.
## El globo ajusta su ALTO (solo el vertical) a las líneas que tenga cada página: de min_lines a lines_per_page (máximo 4).
## PREGUNTAS: si se abre con opciones, salen debajo del último texto (en una fila si caben, si no una debajo de otra) con un cursor; ◄ ► ▲ ▼ eligen.
## Lo abre y lo cierra el autoload DialogueManager; este script solo lo dibuja.
##
## NODOS (se buscan por nombre: mþvelos, cámbiales estilo, fuente y colores en el editor):
##   Box (Panel)               ← el globo. Su ANCHO es el que ves aquí; el alto lo pone el script según las líneas.
##   ├─ Inner (Panel)          ← filete interior (decorativo; bórralo si no lo quieres)
##   ├─ Text (Label)           ← el texto. Su ANCHO, su fuente y su tamaño de letra deciden dónde se parte cada línea. Las opciones copian su estilo.
##   ├─ Name (Label)           ← nombre de quien habla (se oculta si el NPC no tiene nombre)
##   ├─ More (Polygon2D)       ← ▼ que parpadea cuando el globo está completo (se coloca solo en la esquina de abajo a la derecha)
##   └─ Cursor (Polygon2D)     ← cursor de las opciones (►). Cambia su forma o ponle un Sprite2D con tu manita; su punta (origen) toca la opción.
##   TailBorder, Tail (Polygon2D) ← la cola que apunta al NPC (la forma se calcula sola; cambia sus colores)

@export var chars_per_second: float = 33.0   ## velocidad del texto (el prototipo: 0,55 letras por fotograma ≈ 33/s)
@export_range(1, 4) var lines_per_page: int = 4   ## líneas como máximo por globo (no soporta más de 4)
@export_range(1, 4) var min_lines: int = 1         ## líneas mínimas: el globo nunca es más bajo que esto
@export var screen_margin: float = 12.0      ## separación mínima del globo al borde de la pantalla
@export_group("Opciones de las preguntas")
@export var option_gap: float = 40.0         ## px entre una opción y la siguiente (cuando van en fila)
@export var option_indent: float = 30.0      ## px de hueco a la izquierda de cada opción para el cursor
@export var cursor_bob: float = 3.0          ## px que se mueve el cursor de un lado a otro
@export_group("Posición del globo")
@export_enum("Encima de la cabeza", "Debajo de los pies") var bubble_side: int = 0   ## dónde sale el globo respecto al NPC (cada NPC puede cambiarlo en su Inspector)
@export var bubble_gap: float = 28.0                ## px entre la cabeza (o los pies) del NPC y el borde del globo. La cola mide lo mismo (hasta tail_length)
@export var bubble_offset: Vector2 = Vector2.ZERO   ## desplazamiento extra del globo en px (x → derecha, y → abajo)
@export var auto_flip: bool = true           ## si el globo no cabe en pantalla en ese lado, sale por el otro
@export var show_name: bool = false          ## enseñar el nombre de quien habla encima del globo
@export_group("Cola")
@export var tail_length: float = 22.0        ## largo de la cola
@export var tail_width: float = 28.0         ## ancho de la cola donde toca el globo
@export var tail_border: float = 4.0         ## grosor del borde de la cola (igual que el del globo)
@export var blink_time: float = 0.3          ## s que el ▼ está encendido / apagado

var active := false
var choice := 0              ## opción elegida ahora (si hay pregunta)
var _box: Control
var _text: Label
var _name: Label
var _more: CanvasItem
var _cursor: Node2D
var _tail: Polygon2D
var _tail_border: Polygon2D
var _pages: Array[String] = []
var _page := 0
var _chars := 0.0
var _t := 0.0
var _target: Node2D = null   # el NPC (para la cola)
var _opts: PackedStringArray = PackedStringArray()   # opciones de la pregunta (salen en el último globo)
var _opt_labels: Array[Label] = []
var _opt_pos: Array[Vector2] = []

func _ready() -> void:
	_box = find_child("Box", true, false) as Control
	_text = find_child("Text", true, false) as Label
	_name = find_child("Name", true, false) as Label
	_more = find_child("More", true, false) as CanvasItem
	_cursor = find_child("Cursor", true, false) as Node2D
	_tail = find_child("Tail", true, false) as Polygon2D
	_tail_border = find_child("TailBorder", true, false) as Polygon2D
	if _cursor:
		_cursor.visible = false
	visible = false

## Abre el globo con los mensajes (cada uno empieza en un globo nuevo; los largos se reparten solos en globos de como mucho
## lines_per_page líneas). Con "options" el último globo es una pregunta y salen las opciones.
func open(target: Node2D, messages: PackedStringArray, speaker: String = "", options: PackedStringArray = PackedStringArray()) -> void:
	_target = target
	_opts = options
	choice = 0
	_pages.clear()
	var rows := _option_rows()
	for i in messages.size():
		var cap := lines_per_page
		if i == messages.size() - 1 and rows > 0:
			cap = maxi(1, lines_per_page - rows)   # la pregunta deja sitio a sus opciones: entre las dos, como mucho 4 líneas
		_pages.append_array(_paginate(messages[i], cap))
	if _pages.is_empty():
		_pages.append("...")
	_page = 0
	_chars = 0.0
	_t = 0.0
	active = true
	visible = true
	if _name:
		_name.text = speaker
		_name.visible = show_name and speaker != ""
	_show_page()
	_place()

func close() -> void:
	active = false
	visible = false
	_target = null
	_clear_options()
	_opts = PackedStringArray()

## Z: completa el globo, pasa al siguiente o cierra. Devuelve true si se ha cerrado.
## Si es una pregunta con el texto completo, NO hace nada (elige DialogueManager con la opción actual, choice).
func advance() -> bool:
	if not active:
		return true
	if _chars < _total():
		_chars = _total()
		_text.visible_characters = -1
		return false
	if wants_choice():
		return false
	if _page < _pages.size() - 1:
		_page += 1
		_show_page()
		return false
	close()
	return true

## ¿El globo actual ya muestra todo su texto?
func page_complete() -> bool:
	return _chars >= _total()

## ¿Está esperando que el jugador elija una opción? (último globo, con todo el texto escrito)
func wants_choice() -> bool:
	return active and not _opts.is_empty() and _page == _pages.size() - 1 and page_complete()

## Mueve el cursor de las opciones (d = +1 siguiente, -1 anterior).
func move_choice(d: int) -> void:
	if _opts.is_empty():
		return
	choice = wrapi(choice + d, 0, _opts.size())

func _show_page() -> void:
	_chars = 0.0
	_t = 0.0
	_clear_options()
	if _text:
		_text.text = _pages[_page]
		_text.visible_characters = 0
	_resize(_page_lines(_pages[_page]) + (_option_rows() if _page == _pages.size() - 1 else 0))

func _page_lines(p: String) -> int:
	return p.count("\n") + 1

func _total() -> int:
	return _text.get_total_character_count() if _text else 0

# ── tamaño del globo (solo vertical) ──

func _line_h() -> float:
	if _text == null:
		return 30.0
	return _text.get_theme_font("font").get_height(_text.get_theme_font_size("font_size")) + float(_text.get_theme_constant("line_spacing"))

## Ajusta el alto del globo a n líneas (entre min_lines y el máximo, más las filas de opciones).
func _resize(n: int) -> void:
	if _box == null or _text == null:
		return
	n = clampi(n, min_lines, lines_per_page + _option_rows())
	var pad_top := _text.offset_top
	var pad_bottom := -_text.offset_bottom
	_box.size = Vector2(_box.size.x, pad_top + float(n) * _line_h() + pad_bottom)
	if _more:
		(_more as Node2D).position = Vector2(_box.size.x - 28.0, _box.size.y - 24.0)

# ── opciones ──

func _opt_widths() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if _text == null:
		return out
	var font := _text.get_theme_font("font")
	var fs := _text.get_theme_font_size("font_size")
	for o in _opts:
		out.append(font.get_string_size(o, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + option_indent)
	return out

## Filas que ocupan las opciones: 1 si caben todas en una fila, si no una por opción.
func _option_rows() -> int:
	if _opts.is_empty() or _text == null:
		return 0
	var total := 0.0
	for w in _opt_widths():
		total += w
	total += option_gap * float(_opts.size() - 1)
	return 1 if total <= _text.size.x else _opts.size()

func _clear_options() -> void:
	for l in _opt_labels:
		if is_instance_valid(l):
			l.queue_free()
	_opt_labels.clear()
	_opt_pos.clear()
	if _cursor:
		_cursor.visible = false

## Crea las opciones (copian el estilo del texto) justo debajo de las líneas del último globo.
func _build_options() -> void:
	_clear_options()
	var lh := _line_h()
	var widths := _opt_widths()
	var y0 := _text.offset_top + float(_page_lines(_pages[_page])) * lh
	var x := _text.offset_left
	var inline := _option_rows() == 1
	var y := y0
	for i in _opts.size():
		var l := Label.new()
		l.text = _opts[i]
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_override("font", _text.get_theme_font("font"))
		l.add_theme_font_size_override("font_size", _text.get_theme_font_size("font_size"))
		l.add_theme_color_override("font_color", _text.get_theme_color("font_color"))
		_box.add_child(l)
		l.position = Vector2(x + option_indent, y)
		_opt_labels.append(l)
		_opt_pos.append(Vector2(x + option_indent - 8.0, y + lh * 0.5))   # donde toca la punta del cursor
		if inline:
			x += widths[i] + option_gap
		else:
			y += lh

func _process(delta: float) -> void:
	if not active or _text == null:
		return
	_t += delta
	var total := _total()
	if _chars < total:
		_chars = minf(total, _chars + chars_per_second * delta)
		_text.visible_characters = int(_chars)
	var asking := wants_choice()
	if asking and _opt_labels.is_empty():
		_build_options()
	if _more:
		_more.visible = _chars >= total and not asking and fmod(_t, blink_time * 2.0) < blink_time
	if _cursor:
		_cursor.visible = asking and not _opt_pos.is_empty()
		if _cursor.visible:
			_cursor.position = _opt_pos[clampi(choice, 0, _opt_pos.size() - 1)] + Vector2(sin(_t * 9.0) * cursor_bob - 2.0, 0.0)
	_place()

## Parte un mensaje en líneas que caben en el ancho de Text (con su fuente) y las agrupa en globos de "cap" líneas.
func _paginate(msg: String, cap: int) -> Array[String]:
	var out: Array[String] = []
	if _text == null:
		out.append(msg)
		return out
	var font := _text.get_theme_font("font")
	var fs := _text.get_theme_font_size("font_size")
	var width := _text.size.x
	var lines: PackedStringArray = []
	for para in msg.split("\n"):
		var cur := ""
		for w in para.split(" ", false):
			var attempt := w if cur == "" else cur + " " + w
			if cur != "" and font.get_string_size(attempt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
				lines.append(cur)
				cur = w
			else:
				cur = attempt
		lines.append(cur)
	var per := clampi(cap, 1, 4)
	for i in range(0, lines.size(), per):
		out.append("\n".join(lines.slice(i, i + per)))
	return out

## Coloca el globo (arriba / abajo según dónde esté el NPC) y la cola apuntando a su cabeza.
func _place() -> void:
	if _box == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var head := vs * 0.5
	var feet := head
	if _target and is_instance_valid(_target):
		var ct := get_viewport().get_canvas_transform()
		var hw_pos: Vector2 = _target.call("head_global_position") if _target.has_method("head_global_position") else _target.global_position
		var zv: Variant = _target.get("z")
		var feet_pos: Vector2 = _target.global_position + Vector2(0.0, -float(zv) if (zv is float or zv is int) else 0.0)
		head = ct * hw_pos
		feet = ct * feet_pos
	# Ajustes: los de este script, y los de cada NPC si los cambia en su Inspector (bubble_side / bubble_gap / bubble_offset).
	var side := bubble_side
	var gap := bubble_gap
	var off := bubble_offset
	if _target and is_instance_valid(_target):
		var s_v: Variant = _target.get("bubble_side")
		if s_v is int and int(s_v) > 0:
			side = int(s_v) - 1
		var g_v: Variant = _target.get("bubble_gap")
		if (g_v is float or g_v is int) and float(g_v) >= 0.0:
			gap = float(g_v)
		var o_v: Variant = _target.get("bubble_offset")
		if o_v is Vector2:
			off += o_v as Vector2
	var above := side == 0
	if auto_flip:
		if above and head.y - gap - _box.size.y < screen_margin:
			above = false      # no cabe encima de la cabeza: sale debajo de los pies
		elif not above and feet.y + gap + _box.size.y > vs.y - screen_margin:
			above = true
	if _target == null or not is_instance_valid(_target):   # sin personaje (narrador): globo abajo en el centro y sin cola
		_box.position = Vector2((vs.x - _box.size.x) * 0.5, vs.y - _box.size.y - screen_margin * 2.0) + off
		if _tail:
			_tail.visible = false
		if _tail_border:
			_tail_border.visible = false
		return
	if _tail:
		_tail.visible = true
	if _tail_border:
		_tail_border.visible = true
	var anchor := head if above else feet
	var pos := Vector2(anchor.x - _box.size.x * 0.5, anchor.y - gap - _box.size.y if above else anchor.y + gap) + off
	pos.x = clampf(pos.x, screen_margin, maxf(screen_margin, vs.x - _box.size.x - screen_margin))
	pos.y = clampf(pos.y, screen_margin, maxf(screen_margin, vs.y - _box.size.y - screen_margin))
	_box.position = pos
	if _tail == null:
		return
	var r := Rect2(_box.position, _box.size)
	var below_box := above   # globo encima del NPC: la cola sale por el borde de abajo (y apunta hacia abajo)
	var dir := 1.0 if below_box else -1.0
	var edge := r.end.y if below_box else r.position.y
	var hw := tail_width * 0.5
	var bx := clampf(anchor.x, r.position.x + 24.0 + hw, r.end.x - 24.0 - hw)
	var room := absf(anchor.y - edge) - 2.0
	var length := clampf(room, 6.0, tail_length)
	var tip := Vector2(clampf(anchor.x, r.position.x + 30.0, r.end.x - 30.0), edge + dir * length)
	var inset := tail_border + 1.0   # la base entra en el globo para tapar su borde
	_tail.polygon = PackedVector2Array([Vector2(bx - hw, edge - dir * inset), Vector2(bx + hw, edge - dir * inset), tip])
	if _tail_border:
		var b := tail_border
		_tail_border.polygon = PackedVector2Array([Vector2(bx - hw - b, edge - dir * 1.0), Vector2(bx + hw + b, edge - dir * 1.0), tip + Vector2(0, dir * b * 1.4)])
