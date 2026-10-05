class_name BattleItems
extends RefCounted
## OBJETOS usables en combate (equivale a ITEMS del prototipo HTML). Las cantidades están en GameState.inventory.
## Objeto nuevo = añadir su id a ORDER, sus textos a DEFS y su efecto en can_use() / apply().

const ORDER: Array[StringName] = [&"mushroom", &"syrup", &"oneup"]
const DEFS := {
	&"mushroom": {"name": "Champiñón", "desc": "Recupera 10 PV.", "none": "Todos tienen la vida al máximo."},
	&"syrup": {"name": "Jarabe", "desc": "Recupera 10 PT.", "none": "Todos tienen los PT al máximo."},
	&"oneup": {"name": "Champiñón de vida extra", "desc": "Revive a un aliado caído con toda su vida.", "none": "Ningún aliado ha caído."},
}

static func item_name(id: StringName) -> String:
	return DEFS[id]["name"]

static func can_use(id: StringName, h: BattleHero) -> bool:
	match id:
		&"mushroom":
			return h.alive and h.hp < h.max_hp
		&"syrup":
			return h.alive and h.tp < h.max_tp
		&"oneup":
			return not h.alive
	return false

## Por qué no se puede usar en h.
static func why_not(id: StringName, h: BattleHero) -> String:
	match id:
		&"mushroom":
			return ("%s ya tiene la vida al máximo." % h.display_name) if h.alive else ("%s ha caído." % h.display_name)
		&"syrup":
			return ("%s ya tiene los PT al máximo." % h.display_name) if h.alive else ("%s ha caído." % h.display_name)
		&"oneup":
			return "%s no ha caído." % h.display_name
	return ""

## Aplica el efecto y devuelve el texto que se muestra (p. ej. "+10 PV").
static func apply(id: StringName, h: BattleHero) -> String:
	match id:
		&"mushroom":
			var n := mini(10, h.max_hp - h.hp)
			h.hp += n
			return "+%d PV" % n
		&"syrup":
			var n2 := mini(10, h.max_tp - h.tp)
			h.tp += n2
			return "+%d PT" % n2
		&"oneup":
			h.alive = true
			h.hp = h.max_hp
			return "¡Revive!"
	return ""
