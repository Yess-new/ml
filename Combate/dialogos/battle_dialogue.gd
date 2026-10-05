@tool
class_name BattleDialogue
extends Resource
## UN DIÁLOGO DE COMBATE: una conversación (la misma de los NPC del overworld: DialogueNode, con globos, preguntas y respuestas)
## que sale en un momento concreto de la pelea. El combate se detiene mientras se habla.
##
## DÓNDE PONERLO (Inspector):
##   · Escena del combate (Combate/battle.tscn → nodo Battle → Dialogues): valen para todos los combates de esa escena.
##   · Enemigo (su EnemyData .tres → Dialogues): salen siempre que ese enemigo esté en el combate (y "When" lo permita).
##
## CUÁNDO SALE (When):
##   Al empezar el combate · Al empezar una ronda (Round Number, y Round Every para repetirlo) · Enemigo con poca vida (Hp Percent) ·
##   Enemigo derrotado · Héroe caído · Un héroe con poca vida (Hero Hp Percent, por defecto 15 %) ·
##   Al ganar (antes de la pantalla de victoria) · Al perder.
##   "Who" limita a un personaje concreto por su nombre (p. ej. "Goomba", "Mario"). Vacío = cualquiera.
##
## PREGUNTAS: igual que en el overworld. Las marcas de las opciones (Set Flag) las recuerdan los NPC. Además, el campo Action de
## una opción puede hacer cosas en el combate: "end_win" (el combate termina con victoria), "end_fled" (termina como si huyeran),
## "heal_heroes" (cura a los héroes del todo). Cualquier otro nombre solo se emite en la señal Battle.dialogue_action.
##
## En la conversación, el nombre del hablante (Speaker Name) puede ser el de un personaje del combate ("Mario", "Goomba"...):
## entonces la cola del globo apunta a ese personaje.

enum When { START, ROUND, LOW_HP, ENEMY_DEFEATED, HERO_DOWN, VICTORY, DEFEAT, HERO_LOW_HP }

@export_enum("Al empezar el combate", "Al empezar una ronda", "Enemigo con poca vida", "Enemigo derrotado", "Héroe caído", "Al ganar (antes de la victoria)", "Al perder", "Un héroe con poca vida") var when: int = 0:
	set(v):
		when = v
		notify_property_list_changed()
@export var round_number: int = 2        ## ronda en la que sale (1 = la primera)
@export var round_every: int = 0         ## si es > 0, se repite cada tantas rondas a partir de Round Number (0 = solo una vez)
@export_range(1, 99) var hp_percent: int = 50   ## sale cuando al enemigo le queda ese % de vida (o menos)
@export_range(1, 99) var hero_hp_percent: int = 15   ## sale cuando a un héroe le queda ese % de vida (o menos), pero sigue en pie
@export var who: String = ""             ## nombre del personaje (enemigo o héroe) al que se refiere. Vacío = cualquiera
@export_group("Qué dice")
@export var conversation: DialogueNode   ## la conversación (globos, preguntas, respuestas). Si está vacía se usan Lines
@export_multiline var lines: PackedStringArray = PackedStringArray()   ## atajo: solo textos, sin preguntas
@export var speaker: String = ""         ## nombre mostrado por defecto
@export_enum("El personaje implicado", "Mario", "Luigi", "Primer enemigo", "Nadie (narrador sin cola)") var points_to: int = 0   ## a quién apunta la cola del globo
@export_group("Cuándo se repite")
@export_enum("Una vez por combate", "Una vez en toda la partida") var repeat: int = 0
@export var id: StringName = &""         ## nombre único (solo para "Una vez en toda la partida"; vacío = se calcula del texto)
@export_group("Condiciones")
@export var require_flag: StringName = &""   ## solo sale si esta marca existe (o vale Require Value)
@export var require_value: String = ""
@export var unless_flag: StringName = &""    ## no sale si esta marca existe (o vale Unless Value)
@export var unless_value: String = ""

func _validate_property(p: Dictionary) -> void:
	var n: StringName = p.name
	if n == &"round_number" or n == &"round_every":
		if when != When.ROUND:
			p.usage = PROPERTY_USAGE_NO_EDITOR
	elif n == &"hp_percent":
		if when != When.LOW_HP:
			p.usage = PROPERTY_USAGE_NO_EDITOR
	elif n == &"hero_hp_percent":
		if when != When.HERO_LOW_HP:
			p.usage = PROPERTY_USAGE_NO_EDITOR
	elif n == &"who":
		if when in [When.START, When.ROUND, When.VICTORY, When.DEFEAT]:
			p.usage = PROPERTY_USAGE_NO_EDITOR

## La conversación que se va a mostrar (Conversation, o un tramo hecho con Lines). null = no hay nada que decir.
func as_node() -> DialogueNode:
	if conversation != null:
		return conversation
	if lines.is_empty():
		return null
	var n := DialogueNode.new()
	n.lines = lines
	return n

## Clave para "una vez en toda la partida".
func persist_key() -> StringName:
	var k := String(id)
	if k == "":
		k = "%s#%d" % [resource_path, hash(",".join(lines))]
	return StringName("bdlg:" + k)
