class_name BattleDialogueRunner
extends Node
## Muestra las conversaciones del combate con el MISMO globo del overworld (ui/dialogue_box.tscn) y la misma lógica de
## preguntas de DialogueManager, pero sin NPC: la cola del globo apunta a un personaje del combate.
## Lo crea Battle (Combate/battle.gd) y llama a update() cada fotograma de física mientras la fase es "dialogue".
##   · Z / X (el botón de cualquier hermano): completa el texto / pasa de globo / elige la opción marcada.
##   · ◄ ► ▲ ▼: cambian de opción en una pregunta.

var battle                      ## Battle
var box: DialogueBox
var active := false
var actions: Array[StringName] = []   ## "Action" de las opciones elegidas en la conversación en curso
var chosen: Array[DialogueOption] = []   ## las opciones elegidas, en orden (Battle aplica sus consecuencias)

var _node: DialogueNode = null
var _opts: Array[DialogueOption] = []
var _target: Node2D = null
var _speaker := ""
var _guard := -1
var _on_done: Callable

const BOX_SCENE := "res://ui/dialogue_box.tscn"

func _ready() -> void:
	box = (load(BOX_SCENE) as PackedScene).instantiate() as DialogueBox
	add_child(box)

## Empieza una conversación. on_done(actions: Array[StringName]) se llama al terminar.
func start(node: DialogueNode, target: Node2D, speaker: String, on_done: Callable) -> void:
	_target = target
	_speaker = speaker
	_on_done = on_done
	actions = []
	chosen = []
	active = true
	_guard = Engine.get_physics_frames()
	_run(node)

func _run(node: DialogueNode) -> void:
	_node = node
	_opts.clear()
	var texts := PackedStringArray()
	for o in node.options:
		if o != null:
			_opts.append(o)
			texts.append(o.text)
	var who := node.speaker_name if node.speaker_name != "" else _speaker
	box.open(_target_for(node), node.lines, who, texts)

## Si quien habla (Speaker Name) es un personaje del combate, la cola le apunta a él.
func _target_for(node: DialogueNode) -> Node2D:
	var nm := node.speaker_name.strip_edges().to_lower()
	if nm != "" and battle != null:
		for a in battle._all():
			if (a as BattleActor).display_name.to_lower() == nm:
				return a
	return _target

func update() -> void:
	if not active or Engine.get_physics_frames() == _guard:
		return
	if box.wants_choice():
		if Input.is_action_just_pressed(&"ui_left") or Input.is_action_just_pressed(&"ui_up"):
			box.move_choice(-1)
		if Input.is_action_just_pressed(&"ui_right") or Input.is_action_just_pressed(&"ui_down"):
			box.move_choice(1)
		if _pressed():
			_choose(box.choice)
	elif _pressed():
		if box.advance():
			_after_node()

func _pressed() -> bool:
	if battle != null:
		for h in battle.heroes:
			if Input.is_action_just_pressed((h as BattleHero).action()):
				return true
	return Input.is_action_just_pressed(&"jump_mario") or Input.is_action_just_pressed(&"jump_luigi")

func _choose(i: int) -> void:
	if i < 0 or i >= _opts.size():
		return
	var o := _opts[i]
	_guard = Engine.get_physics_frames()
	if o.set_flag != &"":
		DialogueManager.set_flag(o.set_flag, o.flag_value)   # las mismas marcas que usan los NPC del overworld
		GameState.set_flag(o.set_flag, o.flag_value != "false")   # y las de las cinemáticas (GameState.flags)
	if o.action != &"":
		actions.append(o.action)
	chosen.append(o)
	if battle != null:
		battle.dialogue_option_chosen.emit(o)
	if o.reply != null:
		_run(o.reply)
	else:
		box.close()
		_finish()

func _after_node() -> void:
	if _node != null and _node.options.is_empty() and _node.next != null:
		_guard = Engine.get_physics_frames()
		_run(_node.next)
	else:
		_finish()

func _finish() -> void:
	active = false
	_node = null
	var cb := _on_done
	_on_done = Callable()
	if cb.is_valid():
		cb.call(actions, chosen)

## Cierra el globo ya (por si el combate acaba de golpe).
func force_close() -> void:
	if active:
		box.close()
		active = false
		_on_done = Callable()
