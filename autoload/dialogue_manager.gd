extends Node
## AUTOLOAD "DialogueManager": conversaciones con los NPC del overworld (overworld/npc.gd) y el globo de texto (ui/dialogue_box.tscn).
##  - Cada fotograma busca el NPC más cercano con el que Mario puede hablar y le enciende el globito de la tecla.
##  - Mario empieza a hablar al pulsar su botón de salto (Z) junto a un NPC (lo hace hero.gd: en vez de saltar).
##  - Mientras se habla, los hermanos no se mueven ni saltan (blocks_input()). Z completa / pasa / cierra el globo.
##  - Señales: dialogue_started(npc), dialogue_finished(npc). El NPC también emite "talked" al terminar.
##  - Desde código: DialogueManager.say(nodo, ["Texto", "Otro globo"], "Nombre") muestra un globo sin NPC (carteles, eventos...).

signal dialogue_started(npc: Node2D)
signal dialogue_finished(npc: Node2D)
signal option_chosen(npc: Node2D, option: DialogueOption)   ## el jugador eligió una opción de una pregunta

## MEMORIA DEL MUNDO: marcas que ponen las opciones elegidas (DialogueOption.set_flag) y que los NPC consultan (NPC → Variants).
## Viven mientras el juego está abierto (se conservan al cambiar de escena).
var flags := {}

func set_flag(flag: StringName, value: String = "true") -> void:
	flags[flag] = value

func get_flag(flag: StringName) -> String:
	return String(flags.get(flag, ""))

## ¿La marca coincide? value vacío = basta con que exista y no sea "false".
func flag_matches(flag: StringName, value: String = "") -> bool:
	if flag == &"":
		return false
	var v := get_flag(flag)
	if value != "":
		return v == value
	return v != "" and v != "false"

var _node: DialogueNode = null            # tramo que se está mostrando
var _node_opts: Array[DialogueOption] = []   # sus opciones (las que salen en el globo, en orden)
var _speaker := ""                         # nombre por defecto de quien habla

const BOX_SCENE := "res://ui/dialogue_box.tscn"

var box: DialogueBox
var npc: Node2D = null          # con quién se habla ahora (null = nadie)
var _guard_frame := -1          # fotograma en que se abrió o cerró: esa pulsación de Z no salta ni avanza
var _prompted: NPC = null
var cutscene_active := 0        ## cinemáticas en curso (las pone Cutscene): mientras > 0, los hermanos no obedecen y no se habla con NPCs

func _ready() -> void:
	box = (load(BOX_SCENE) as PackedScene).instantiate() as DialogueBox
	add_child(box)

func is_talking() -> bool:
	return npc != null

## ¿Los hermanos deben ignorar los controles? (hablando, o la Z que acaba de abrir/cerrar el globo)
func blocks_input() -> bool:
	if npc != null or cutscene_active > 0 or Engine.get_physics_frames() == _guard_frame:
		return true
	var pm := get_node_or_null("/root/PauseMenu")   # menú de pausa abierto (o cerrado hace un instante: esa pulsación no salta)
	return pm != null and (bool(pm.get("is_open")) or bool(pm.call("recently_closed")))

## ¿Se puede empezar a hablar? (no durante un cambio de habitación ni una cinemática)
func can_talk() -> bool:
	if npc != null or cutscene_active > 0:
		return false
	var st := get_tree().root.get_node_or_null("SceneTransition")
	return st == null or not bool(st.get("busy"))

## El NPC más cercano con el que este héroe puede hablar ahora (o null).
func npc_near(hero: Node2D) -> NPC:
	if hero == null or not can_talk():
		return null
	var best: NPC = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("npcs"):
		var c := n as NPC
		if c == null or not c.is_visible_in_tree() or not c.can_talk_to(hero):
			continue
		var d := hero.global_position.distance_to(c.global_position)
		if d < best_d:
			best_d = d
			best = c
	return best

## Empieza a hablar con un NPC.
func start(n: NPC) -> void:
	if n == null or npc != null:
		return
	npc = n
	n.talking = true
	_guard_frame = Engine.get_physics_frames()
	_speaker = n.display_name
	_run(n.current_node())
	dialogue_started.emit(n)

## Conversación con preguntas sin NPC (carteles, eventos...): target = a quién apunta la cola.
func ask(target: Node2D, node: DialogueNode, speaker: String = "") -> void:
	if npc != null or node == null:
		return
	npc = target
	_guard_frame = Engine.get_physics_frames()
	_speaker = speaker
	_run(node)
	dialogue_started.emit(target)

## Muestra un tramo de conversación (sus globos y, al final, su pregunta con las opciones).
func _run(node: DialogueNode) -> void:
	_node = node
	_node_opts.clear()
	var texts := PackedStringArray()
	for o in node.options:
		if o != null:
			_node_opts.append(o)
			texts.append(o.text)
	box.open(npc, node.lines, node.speaker_name if node.speaker_name != "" else _speaker, texts)

## El jugador confirmó la opción i: anota sus marcas, avisa y muestra SU respuesta (si tiene).
func _choose(i: int) -> void:
	if i < 0 or i >= _node_opts.size():
		return
	var o := _node_opts[i]
	_guard_frame = Engine.get_physics_frames()
	if o.set_flag != &"":
		set_flag(o.set_flag, o.flag_value)
	option_chosen.emit(npc, o)
	if npc is NPC:
		(npc as NPC).answered.emit(o)
	if o.reply != null:
		_run(o.reply)
	else:
		box.close()
		_finish()

## El globo se cerró al terminar un tramo: sigue con el siguiente (Next) o termina la conversación.
func _after_node() -> void:
	if _node != null and _node.options.is_empty() and _node.next != null:
		_guard_frame = Engine.get_physics_frames()
		_run(_node.next)
	else:
		_finish()

## Muestra un globo sin NPC (target = a quién apunta la cola: un cartel, Mario...).
func say(target: Node2D, messages: PackedStringArray, speaker: String = "") -> void:
	if npc != null:
		return
	npc = target
	_guard_frame = Engine.get_physics_frames()
	box.open(target, messages, speaker)
	dialogue_started.emit(target)

func _physics_process(_delta: float) -> void:
	_update_prompt()
	if npc == null:
		return
	if not is_instance_valid(npc):   # el NPC desapareció (cambio de escena...)
		box.close()
		npc = null
		return
	if Engine.get_physics_frames() == _guard_frame:
		return
	if box.wants_choice():   # pregunta: ◄ ► ▲ ▼ cambian de opción, Z elige
		if Input.is_action_just_pressed(&"ui_left") or Input.is_action_just_pressed(&"ui_up"):
			box.move_choice(-1)
		if Input.is_action_just_pressed(&"ui_right") or Input.is_action_just_pressed(&"ui_down"):
			box.move_choice(1)
		if Input.is_action_just_pressed(_talk_action()):
			_choose(box.choice)
	elif Input.is_action_just_pressed(_talk_action()):
		if box.advance():
			_after_node()

## Avanza el globo como si el jugador pulsara Z (para globos que pasan solos). Devuelve true si se ha cerrado.
func advance() -> bool:
	if npc == null:
		return true
	if box.advance():
		_finish()
		return true
	return false

## ¿El globo actual ya muestra todo su texto?
func page_complete() -> bool:
	return box.active and box.page_complete()

## Cierra el globo ya (al saltar una cinemática).
func force_close() -> void:
	if npc == null:
		return
	box.close()
	_finish()

func _finish() -> void:
	_node = null
	var n := npc
	npc = null
	_guard_frame = Engine.get_physics_frames()
	if n is NPC:
		(n as NPC).talking = false
		(n as NPC).notify_talked()
	dialogue_finished.emit(n)

## Enciende el globito de la tecla solo en el NPC más cercano con el que Mario puede hablar.
func _update_prompt() -> void:
	var target: NPC = null
	var mario := _mario()
	if mario and npc == null:
		target = npc_near(mario)
	if _prompted and is_instance_valid(_prompted) and _prompted != target:
		_prompted.show_prompt = false
	if target:
		target.show_prompt = true
	_prompted = target

func _mario() -> Node2D:
	for h in get_tree().get_nodes_in_group("overworld_heroes"):
		if h is Hero and not (h as Hero).is_follower():
			return h as Node2D
	return null

func _talk_action() -> StringName:
	var m := _mario()
	if m is Hero:
		return (m as Hero).talk_action()
	return &"jump_mario"
