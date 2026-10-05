class_name Battle
extends Node2D
## COMBATE estilo Mario & Luigi, adaptado del prototipo HTML (startCombatNow, nextTurn, animateAttack, animateHammer, beginFlee...).
## Escena: Combate/battle.tscn · Interfaz: ui/battle_ui.tscn (solo dibuja; lee el estado de aquí).
##
## - Todo va por FOTOGRAMAS de física (60 por segundo), igual que el prototipo: así las ventanas de timing son exactas.
## - TURNOS por velocidad (turn_speed): cada ronda actúan todos los vivos de mayor a menor velocidad (a igualdad, primero los héroes).
## - Cada hermano usa SU botón (Z = Mario, X = Luigi, de su CharacterStats): confirmar, golpear con timing y saltar para esquivar.
##
## ESCENA (todo se ve y se mueve en el editor):
##   Battle (este script)
##   ├─ Background       ← fondo: un degradado (Color) y un Sprite2D (Image) para TU imagen. Pon lo que quieras aquí.
##   ├─ EnemySpots       ← Marker2D donde aparecen los enemigos cuando el combate viene del overworld (Spot1, Spot2...).
##   ├─ Actors           ← ordena por Y. Los héroes (BattleHero) en el orden de la lista; colócalos donde quieras.
##   │   ├─ Mario, Luigi (Combate/actores/*_battle.tscn)
##   │   └─ Goomba (Combate/enemigos/goomba_battle.tscn) ← enemigo de PRUEBA, para probar la escena sola (F6)
##   └─ BattleUI (ui/battle_ui.tscn)
## - Probar sola: abre battle.tscn y pulsa F6 (lucha contra los enemigos colocados en Actors).
## - Desde el juego: GameState.start_battle([escena_del_enemigo, ...], escena_de_vuelta). Los enemigos colocados se
##   sustituyen por esos, en los EnemySpots.

@export var damage_number_scene: PackedScene = preload("res://Combate/damage_number.tscn")   ## números flotantes (-5, ¡Crítico!...)
## Si solo lucha UN héroe (el otro con "In Battle" desactivado), al empezar el combate se coloca a media altura entre los
## sitios de los dos héroes (solo cambia su posición vertical). Desactívalo para que se quede en su sitio de la escena.
@export var center_single_hero: bool = true
## Ataques tándem disponibles. Si lo dejas vacío se cargan solos todos los .tres de Combate/tandems/.
@export var tandems: Array[TandemData] = []
## Bloques del menú de acciones que NO están disponibles en este combate (marcados = desaparecen del menú). Además, la historia
## puede bloquearlos con Battle.lock_ability(&"jump") (ids: item, flee, jump, hammer, tandem). Si no quedara ninguno, se ignora.
@export_flags("Objetos", "Huir", "Saltar", "Martillo", "Tándem") var disabled_actions: int = 0
const ACTION_FLAGS := [&"item", &"flee", &"jump", &"hammer", &"tandem"]

## Bloqueo por la historia (se guarda en GameState.flags). Desde cualquier script: Battle.lock_ability(&"jump") / Battle.unlock_ability(&"tandem:splash").
static func ability_enabled(id: StringName) -> bool:
	return not GameState.has_flag(StringName("lock:" + String(id)))
static func lock_ability(id: StringName) -> void:
	GameState.set_flag(StringName("lock:" + String(id)), true)
static func unlock_ability(id: StringName) -> void:
	GameState.set_flag(StringName("lock:" + String(id)), false)

## ¿Se muestra el bloque de esta acción en el menú?
func action_enabled(id: StringName) -> bool:
	var i := ACTION_FLAGS.find(id)
	if i >= 0 and (disabled_actions & (1 << i)) != 0:
		return false
	if not ability_enabled(id):
		return false
	if id == &"tandem" and tandems.is_empty():   # sin ningún ataque tándem disponible, el bloque sobra
		return false
	return true
## Estilo de los efectos de golpe (estrella de daño, destello, TOTAL, hundimiento y temblor del enemigo). Si lo dejas vacío se usa
## Combate/hit_fx_default.tres: ábrelo en el Inspector para cambiar valores o arrastrar tus propios sprites.
@export var fx: HitFxStyle
const FX_DEFAULT := "res://Combate/hit_fx_default.tres"
const TANDEM_DIR := "res://Combate/tandems/"

const LUNGE := preload("res://Combate/patrones/lunge_pattern.gd")
const SEL_JUMP := 10   ## fotogramas del saltito al elegir acción
const MENU_FADE := 5   ## fotogramas que tardan los bloques en desvanecerse tras el golpe (la cámara espera a que acaben)
## Salto: ventanas en fotogramas desde que empieza (contacto con el enemigo en el 42).
const ATK := {"hit_from": 34, "hit_to": 50, "perfect_from": 40, "perfect_to": 44, "contact": 42, "duration": 74,
	"p_duration": 104, "bounce_from": 66, "bounce_to": 78, "bounce_contact": 72}
## Salto de ataque (fotogramas): avanzar → salto 1 (contacto al final) → salto 2 → vuelta de un salto / andando.
const JUMP := {"walk": 20, "walk_frac": 0.25, "j1": 45, "j2": 50, "win": 3, "late": 4, "h1": 250.0, "h2": 250.0, "h3": 110.0, "spin_end": 0.8,
	"back_jump": 38, "drop": 16, "pause": 6, "back_walk": 44, "land_back": 34.0}
## Ataque TÁNDEM «Splash Bros.» (del prototipo HTML). Fotogramas (60 = 1 s): walk (se colocan) · crouch+hop (salto de Mario) · ring1/w1 (ventana 1, Mario) ·
## rise (Mario sube girando) · fall/w2 (ventana 2, Luigi lo atrapa) · carry (vuelan juntos) · hover+drop/w3 (ventana 3, Mario al caer) · reb (rebotan) ·
## fail/fail_hold (si falla una ventana) · pause+home (vuelven andando). w* = holgura de cada ventana (±fotogramas).
## cost = PT que paga quien lo elige · dmg = daño base · spike = daño a cada hermano si el enemigo tiene pinchos.
## Distancias: xs = escala horizontal respecto al prototipo (640 px → esta pantalla) · hop_h/rise_h/carry_arc/hover_h/reb_arc = alturas (px) · bob = altura de los pasos.
## Martillo: sacar → caminar → cargar (ventana win desde que empieza la carga) → golpe → volver.
const HAMMER := {"draw": 18, "walk": 34, "raise": 30, "win_from": 30, "win_to": 42, "late": 4, "swing": 9, "hold": 12, "back": 28}
const HAMMER_DMG := {&"strong": 3, &"early": 2, &"miss": 1}
const FLEE := {"need": 6, "step": 9.0, "drift": 0.45, "exit_x": -60.0, "end_delay": 50}
const END_DELAY := {&"win": 150, &"lose": 150, &"fled": 20}
const CRIT_MULT := 1.5
## Cámara y avance en el turno de un hermano.
const ADVANCE_DIST := 48.0   ## cuánto avanza (px) el hermano al que le toca
const CAM_ZOOM := 1.1        ## zoom de la cámara durante su turno (1.0 = normal)
const CAM_FOLLOW := 0.6      ## 0 = no se mueve, 1 = centrada del todo en el personaje (limitada por el borde del fondo)
const RETREAT_DIST := 30.0   ## cuánto retrocede (px) el hermano que NO tiene el turno
const FOCUS_TIME := 0.3      ## segundos que tarda en avanzar / retroceder y luego en acercarse la cámara
const INTRO_ZOOM := 0.85     ## zoom con el que empieza el combate (alejada)
const INTRO_TIME := 2.0      ## segundos que tarda la cámara en llegar a su sitio; hasta entonces no pasa nada
const SPIKES := {"power": 10, "stache": 0}   ## daño de los pinchos al saltar sobre un enemigo spiked

@onready var actors_root: Node2D = $Actors
@onready var ui: BattleUI = $BattleUI
@onready var enemy_spots: Node = get_node_or_null("EnemySpots")
@onready var cam: Camera2D = get_node_or_null("Camera") as Camera2D
var _hero_tween: Tween   ## avance / retroceso de los hermanos
var _cam_tween: Tween    ## movimiento de la cámara

var actions: Array[StringName] = []   ## orden del menú (el de los bloques de la UI)

var heroes: Array[BattleHero] = []
var enemies: Array[BattleEnemy] = []
var hittables: Array = []          ## dianas vivas (Hittable): partes de enemigos, bolas de energía, proyectiles... (ver Combate/hittable.gd)
var phase: StringName = &"start"   ## estado actual (ver _physics_process)
var frame := 0                     ## fotogramas desde que empezó la fase
var actor: BattleActor = null      ## a quién le toca
var target: BattleActor = null
var queue: Array[BattleActor] = [] ## lo que queda de la ronda
var message := ""
var warn := ""                     ## aviso temporal (p. ej. "No te quedan champiñones")
var warn_t := 0
var fade_out := 0                  ## fotogramas que le quedan al desvanecimiento de los bloques tras el golpe (corre en paralelo al siguiente paso)
var menu_index := 2
var list_index := 0
var target_index := 0
var act_kind: StringName = &"jump"
var item_id: StringName = &""
var pattern: EnemyPattern = null
var att: Dictionary = {}           ## estado del ataque de héroe en curso
var result: StringName = &""       ## &"win" | &"lose" | &"fled"
var shake := 0
var flee_turn := 0
var flee_count := 0
var flee_end := -1
var ring: Dictionary = {}          ## anillo de timing del tándem (lo dibuja ui/timing_ring.gd); vacío = no hay
var bursts: Array = []             ## destellos del tándem
var shell: Dictionary = {}         ## concha en juego (tándem Concha Verde): { pos, rot, dir }
var popups: Array = []             ## textos de valoración (OK!, GOOD!...) de los tándems
var hit_stars: Array = []          ## estrellas con el daño que recibe un enemigo: { pos, text, t, out, len, total } (las dibuja ui/timing_ring.gd)
var impacts: Array = []            ## destellos al golpear a un enemigo: { pos, t, odd }
var atk_active := false            ## ¿hay un ataque de un hermano en curso? (sus estrellas se quedan hasta que termina y sale el TOTAL)
var atk_total := 0                 ## daño total que lleva ese ataque
var atk_hits := 0                  ## golpes que lleva ese ataque
var atk_last := Vector2.ZERO       ## dónde salió la última estrella (ahí aparece el TOTAL)
var rank_fx: Dictionary = {}       ## celebración en pantalla (OK/GOOD/GREAT/EXCELLENT): { pos, level, t } (la dibuja ui/timing_ring.gd)
var _sfx: AudioStreamPlayer
var _rank_streams := {}
var combo: Dictionary = {}         ## contador de golpes sobre el enemigo: { pos, n }
var tandem: TandemAttack = null    ## ataque tándem en curso (su script lleva la animación)
var chosen_tandem: TandemData = null
var tandem_index := 0              ## fila elegida en el menú de tándems (▲▼)

# ───────────────────────────── diálogos de combate ─────────────────────────────

## Diálogos de este combate (BattleDialogue): salen al empezar, al empezar una ronda, con un enemigo herido o derrotado, al caer un héroe,
## al ganar o al perder. Los enemigos también pueden llevar los suyos (EnemyData → Dialogues). Ver Combate/dialogos/battle_dialogue.gd.
@export var dialogues: Array[BattleDialogue] = []

signal dialogue_option_chosen(option: DialogueOption)    ## el jugador eligió una opción en una pregunta del combate
signal dialogue_action(action: StringName)               ## una opción con "Action" fue elegida (los nombres especiales ya los atiende el combate)

var round_n := 0                      ## ronda actual (1 = la primera)
var _round_started := false
var _dlg: BattleDialogueRunner
var _dlg_queue: Array = []            ## [[BattleDialogue, personaje], ...] por mostrar
var _dlg_after: Callable              ## qué hacer cuando acaban todos
var _dlg_fired := {}                  ## diálogos ya dichos en este combate
var _dlg_actions: Array[StringName] = []
var _dlg_options: Array = []          ## opciones elegidas (DialogueOption) cuyas consecuencias se aplican al terminar
var _start_dlg_done := false
var _end_dlg_done := false

# ───────────────────────────── inicio ─────────────────────────────

func _ready() -> void:
	_apply_background()
	var hero_ys: Array[float] = []   # altura (y) de TODOS los héroes colocados, también los desactivados
	for c in actors_root.get_children():   # los actores colocados en la escena
		if c is BattleHero:
			hero_ys.append((c as Node2D).position.y)
			var bh := c as BattleHero
			# desactivado en el Inspector, o ausente en esta parte de la historia (GameState.party): no participa (se quita de la escena)
			if not bh.in_battle or (bh.stats != null and not GameState.has_hero(bh.stats.id)):
				actors_root.remove_child(c)
				c.queue_free()
				continue
			heroes.append(c)
		elif c is BattleEnemy:
			enemies.append(c)
	# Un solo héroe (el otro está desactivado): al empezar, se coloca a media altura entre los sitios de los héroes,
	# en vez de quedarse en su sitio de siempre (que está pensado para ir acompañado y queda descolocado).
	if center_single_hero and heroes.size() == 1 and hero_ys.size() > 1:
		var sum := 0.0
		for y in hero_ys:
			sum += y
		heroes[0].position.y = sum / hero_ys.size()
	if not GameState.battle_enemies.is_empty():   # viene del overworld: sus enemigos sustituyen a los de prueba
		for e in enemies:
			actors_root.remove_child(e)
			e.queue_free()
		enemies.clear()
		var spots: Array = enemy_spots.get_children() if enemy_spots else []
		for i in GameState.battle_enemies.size():
			var e := (GameState.battle_enemies[i] as PackedScene).instantiate() as BattleEnemy
			if i < spots.size():
				e.position = (spots[i] as Node2D).position
			elif not spots.is_empty():
				e.position = (spots[-1] as Node2D).position + Vector2(40.0, 70.0) * (i - spots.size() + 1)
			actors_root.add_child(e)
			enemies.append(e)
	for e in enemies:   # las dianas (Hittable) puestas como hijas de un enemigo en su escena se enganchan a él
		for c in e.get_children():
			if c is Hittable:
				(c as Hittable).attach(e, self, (c as Hittable).position)
	for h in heroes:
		if h.stats == null:
			push_error("[Battle] %s no tiene 'Stats' (CharacterStats) asignado." % h.name)
			continue
		h.setup(GameState.hp_of(h.stats), GameState.tp_of(h.stats))
	for e in enemies:
		if e.data == null:
			push_error("[Battle] %s no tiene 'Data' (EnemyData) asignado." % e.name)
			continue
		e.setup()
	var names: PackedStringArray = []
	for e in enemies:
		names.append(e.display_name)
	say("¡%s aparece!" % " y ".join(names))
	_load_tandems()
	var avail: Array[TandemData] = []   # solo los ataques tándem activados (Enabled del recurso y no bloqueados por la historia)
	for td in tandems:
		if td.enabled and ability_enabled(StringName("tandem:" + String(td.id))):
			avail.append(td)
	tandems = avail
	if fx == null:
		fx = (load(FX_DEFAULT) as HitFxStyle) if ResourceLoader.exists(FX_DEFAULT) else HitFxStyle.new()
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "RankSfx"
	add_child(_sfx)
	ui.setup(self)
	_dlg = BattleDialogueRunner.new()
	_dlg.name = "Dialogue"
	_dlg.battle = self
	add_child(_dlg)
	actions = ui.action_ids()
	if cam:   # entrada: la cámara empieza alejada y se acerca despacio a su sitio
		cam.zoom = Vector2.ONE * INTRO_ZOOM
		_cam_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_cam_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		_cam_tween.tween_property(cam, "zoom", Vector2.ONE, INTRO_TIME)

# ───────────────────────────── bucle ─────────────────────────────

func _physics_process(_delta: float) -> void:
	frame += 1
	_tick_common()
	match phase:
		&"start":
			if not _cam_busy():   # nada empieza hasta que la cámara llega a su sitio
				if not _start_dlg_done:
					_start_dlg_done = true
					if _play_dialogues(_collect_dialogues(BattleDialogue.When.START), next_turn):
						return
				next_turn()
		&"dialogue":
			_dlg.update()
		&"menu":
			_menu()
		&"menu_hop":
			_menu_hop()
		&"total_wait":
			if not _has_total():
				next_turn()
		&"menu_in":
			_menu_in()
		&"target":
			_target()
		&"items":
			_items()
		&"item_target":
			_item_target()
		&"item_use":
			if frame > 50:
				next_turn()
		&"jump_anim":
			_animate_jump()
		&"spike_anim":
			_animate_spike()
		&"hammer_anim":
			_animate_hammer()
		&"tandems":
			_tandem_menu()
		&"tandem_anim":
			if tandem.update():
				_tp_end()
		&"enemy_tell":
			_enemy_tell()
		&"enemy_attack":
			if pattern.update():
				pattern = null
				next_turn()
		&"flee":
			_animate_flee()
		&"end":
			if frame >= END_DELAY[result]:
				if not _end_dlg_done and result != &"fled":   # últimas palabras antes de la pantalla de victoria / de salir
					_end_dlg_done = true
					var w := BattleDialogue.When.VICTORY if result == &"win" else BattleDialogue.When.DEFEAT
					if _play_dialogues(_collect_dialogues(w), _resume_end):
						return
				if result == &"win" and not victory_data.is_empty():
					_show_victory()
				else:
					_finish()
	if shake > 0:
		shake -= 1
		actors_root.position = Vector2(randf_range(-3, 3), randf_range(-3, 3))
	else:
		actors_root.position = Vector2.ZERO
	if warn_t > 0:
		warn_t -= 1
	ui.refresh()

func set_phase(p: StringName) -> void:
	phase = p
	frame = 0

## Esquiva: durante el turno enemigo, cada hermano salta con su botón. Y efectos de todos los fotogramas.
func _tick_common() -> void:
	var dodging := (phase == &"enemy_tell" or phase == &"enemy_attack") and pattern != null and pattern.defense_kind() == &"jump"
	# Detalle: mientras un hermano elige su acción, el OTRO puede saltar con su botón (sin efecto en el juego).
	var choosing := phase in [&"menu", &"menu_hop", &"menu_in", &"target", &"items", &"item_target", &"tandems"]
	var guarding := (phase == &"enemy_tell" or phase == &"enemy_attack") and pattern != null and pattern.defense_kind() == &"hammer"
	for h in heroes:
		h.guard_update(guarding)   # esquiva con martillo: mantener = cargar, soltar = golpear
		var idle_hop := choosing and h != actor
		if (dodging or idle_hop) and h.alive and h.jump <= 0.0 and h.bounce <= 0.0 and Input.is_action_just_pressed(h.action()):   # sin saltar de nuevo mientras rebota
			h.jump = 1.0
		h.tick()
	for e in enemies:
		e.tick()
	for hb in hittables.duplicate():
		if is_instance_valid(hb):
			(hb as Hittable).tick()
	if fade_out > 0:
		fade_out -= 1
	for st in hit_stars:
		st["t"] = int(st["t"]) + 1
		if int(st["out"]) >= 0:   # out = -1: la estrella se queda (ataque en curso); si no, cuenta hasta desvanecerse
			st["out"] = int(st["out"]) + 1
	hit_stars = hit_stars.filter(func(s): return int(s["out"]) < int(s["len"]))
	if not rank_fx.is_empty():
		rank_fx["t"] = int(rank_fx["t"]) + 1
		if int(rank_fx["t"]) >= fx.rank_frames:
			rank_fx = {}
	for im in impacts:
		im["t"] = int(im["t"]) + 1
	impacts = impacts.filter(func(i): return int(i["t"]) < fx.impact_frames)

# ───────────────────────────── turnos ─────────────────────────────

## Empieza el ataque de un hermano: sus estrellas de daño se quedan hasta que acabe, y entonces sale el TOTAL.
func _atk_begin() -> void:
	_atk_end()
	atk_active = true
	atk_total = 0
	atk_hits = 0

func _atk_end() -> void:
	for hh in heroes:   # el atacante se dibujaba por detrás de enemigos más adelantados (orden por y): vuelve a su capa normal
		hh.z_index = 0
	if not atk_active:
		return
	atk_active = false
	for st in hit_stars:   # las estrellas que se habían quedado se desvanecen rápido
		if int(st["out"]) < 0:
			st["out"] = 0
			st["len"] = 16
	if fx.total_enabled and atk_hits >= fx.total_min_hits and atk_total > 0:
		add_star(atk_last, str(atk_total), false, true, fx.total_frames)

## Estrella con un texto sobre un enemigo. held = se queda hasta que acabe el ataque; total = la grande del TOTAL.
func add_star(pos: Vector2, text: String, held := false, total := false, life := -1) -> void:
	hit_stars.append({"pos": pos, "text": text, "t": 0, "out": -1 if held else 0, "len": fx.star_frames if life < 0 else life, "total": total})

func _has_total() -> bool:
	for st in hit_stars:
		if st["total"]:
			return true
	return false

## Nivel de celebración (0 OK · 1 GOOD · 2 GREAT · 3 EXCELLENT) del golpe nº i (desde 0) de un ataque con n golpes:
## 1 golpe → EXCELLENT · 2 → GOOD, EXCELLENT · 3 → GOOD, GREAT, EXCELLENT · 4 → los cuatro · más de 4 → los niveles se repiten.
static func rank_level(i: int, n: int) -> int:
	if n > 4:
		return clampi(int(float(i) * 4.0 / float(n)), 0, 3)
	return clampi(3 - (n - 1 - i) * (2 if n == 2 else 1), 0, 3)

## Muestra la celebración de ese nivel sobre el enemigo (y suena). Solo se llama al ACERTAR un golpe; si fallas no sale nada.
## pos = sitio del mundo; si no se da, arriba a la izquierda del objetivo.
func celebrate(level: int, pos := Vector2.INF) -> void:
	level = clampi(level, 0, 3)
	var p := pos
	var explicit := pos != Vector2.INF   # un tándem da su propio sitio; si no, arriba a la izquierda del enemigo (+ el ajuste del BattleUI)
	if p == Vector2.INF:
		var t: BattleActor = target
		p = t.position + t.offset + Vector2(-t.body_width() * 0.35, -t.body_height() * 1.05) if t else Vector2.ZERO
	rank_fx = {"pos": p, "level": level, "t": 0, "explicit": explicit}
	var st := _rank_stream(level)
	if st and _sfx:
		_sfx.stream = st
		_sfx.volume_db = fx.rank_volume_db
		_sfx.play()

func _rank_stream(level: int) -> AudioStream:
	if fx.rank_sounds.size() > level and fx.rank_sounds[level] != null:
		return fx.rank_sounds[level]
	if not _rank_streams.has(level):
		var path := "res://Audio/combate/rank_%s.wav" % ["ok", "good", "great", "excellent"][level]
		_rank_streams[level] = load(path) if ResourceLoader.exists(path) else null
	return _rank_streams[level]

func next_turn() -> void:
	_atk_end()
	if _has_total():   # el combate no sigue hasta que el número total desaparece
		set_phase(&"total_wait")
		return
	for h in heroes:
		h.offset = Vector2.ZERO
		h.spin = 0.0
	if _boundary_dialogues():   # enemigo herido o derrotado, héroe caído: hablan antes de seguir
		return
	if _check_end():
		return
	var alive_q: Array[BattleActor] = []
	for qa in queue:
		if qa.alive:
			alive_q.append(qa)
	queue = alive_q
	if queue.is_empty() and not _round_started:   # empieza una ronda nueva
		round_n += 1
		_round_started = true
		if _play_dialogues(_collect_dialogues(BattleDialogue.When.ROUND), next_turn):
			return
	_round_started = false
	var c: BattleActor = null
	var guard := 0
	while (c == null or not c.alive) and guard < 200:
		if queue.is_empty():
			queue = _turn_order()
		c = queue.pop_front()
		guard += 1
	actor = c
	_focus(c as BattleHero if c is BattleHero else null)
	if c is BattleHero:
		menu_index = maxi(0, actions.find(&"jump"))   # empieza en Salto, como en el prototipo
		set_phase(&"menu")
	else:
		_start_enemy_turn(c as BattleEnemy)

## Al hermano de turno (h) lo adelanta un poco y la cámara se acerca a su NUEVA posición; el resto vuelve a su sitio.
## Con h = null (turno enemigo, fin, huida) todos vuelven atrás y la cámara se aleja.
func _focus(h: BattleHero) -> void:
	# 1) los hermanos: el de turno AVANZA y el otro RETROCEDE (si no es turno de un héroe, todos vuelven a su sitio)
	if _hero_tween:
		_hero_tween.kill()
	_hero_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hero_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	for hh in heroes:
		var to := Vector2.ZERO
		if h != null:
			to = Vector2(ADVANCE_DIST, 0.0) if hh == h else Vector2(-RETREAT_DIST, 0.0)
		_hero_tween.tween_property(hh, "advance", to, FOCUS_TIME)
	if cam == null:
		return
	# 2) la cámara: si hay un hermano de turno, se acerca DESPUÉS de que avance; si no, vuelve a la vez
	var vs := get_viewport_rect().size
	var center := vs * 0.5
	var zoom := 1.0
	var pos := center
	if h != null:
		zoom = CAM_ZOOM
		var spot := h.position + Vector2(ADVANCE_DIST, -h.body_height() * 0.5)   # el centro del personaje ya adelantado
		pos = center.lerp(spot, CAM_FOLLOW)
		var half := vs / (2.0 * zoom)   # mitad de lo que ve la cámara: no se sale del fondo
		pos = pos.clamp(half, vs - half)
	_move_cam(pos, zoom, FOCUS_TIME if h != null else 0.0)

## Cuando el hermano ataca, la cámara vuelve a su posición original (el personaje se queda adelantado).
func _camera_home() -> void:
	if cam:
		_move_cam(get_viewport_rect().size * 0.5, 1.0, 0.0)

func _move_cam(pos: Vector2, zoom: float, delay: float) -> void:
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_cam_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_cam_tween.tween_property(cam, "position", pos, FOCUS_TIME).set_delay(delay)
	_cam_tween.tween_property(cam, "zoom", Vector2.ONE * zoom, FOCUS_TIME).set_delay(delay)

func _cam_busy() -> bool:
	return _cam_tween != null and _cam_tween.is_valid() and _cam_tween.is_running()

## Ronda: vivos ordenados de mayor a menor velocidad; a igual velocidad, en el orden de la lista (primero los héroes).
func _turn_order() -> Array[BattleActor]:
	var list: Array[BattleActor] = []
	for h in heroes:
		if h.alive:
			list.append(h)
	for e in enemies:
		if e.alive:
			list.append(e)
	var idx := {}
	for i in list.size():
		idx[list[i]] = i
	list.sort_custom(func(a: BattleActor, b: BattleActor) -> bool:
		return a.turn_speed > b.turn_speed or (a.turn_speed == b.turn_speed and idx[a] < idx[b]))
	return list

func _check_end() -> bool:
	if phase == &"end":
		return true
	for a in _all():
		if a.hp <= 0:
			a.alive = false
	var win := living(enemies).is_empty()
	var lose := living(heroes).is_empty()
	if not win and not lose:
		return false
	result = &"win" if win else &"lose"
	_focus(null)
	if win:
		_grant_victory()
		for h in heroes:
			if h.alive:
				h.anim_override = &"victory"
	else:
		say("%s %s..." % [_party_name(), "ha caído" if heroes.size() == 1 else "han caído"])
	set_phase(&"end")
	return true

func _all() -> Array[BattleActor]:
	var list: Array[BattleActor] = []
	list.append_array(heroes)
	list.append_array(enemies)
	return list

func living(list: Array) -> Array:
	return list.filter(func(a: BattleActor) -> bool: return a.alive)

# ───────────────────────────── menú del héroe ─────────────────────────────

func _menu() -> void:
	var h := actor as BattleHero
	say("%s — ◄ ►: elegir acción · %s: confirmar" % [h.display_name, key_of(h.action())])
	if Input.is_action_just_pressed(&"ui_left"):
		menu_index = wrapi(menu_index - 1, 0, actions.size())
	if Input.is_action_just_pressed(&"ui_right"):
		menu_index = wrapi(menu_index + 1, 0, actions.size())
	if Input.is_action_just_pressed(h.action()):
		set_phase(&"menu_hop")   # primero salta y golpea el bloque; luego los bloques se desvanecen y, al acabar, se aplica la acción

func _menu_hop() -> void:
	var h := actor as BattleHero
	h.sel_hop = float(frame) / SEL_JUMP
	if frame >= SEL_JUMP:
		h.sel_hop = 0.0
		fade_out = MENU_FADE   # los bloques se desvanecen en paralelo (lo dibuja la UI); el siguiente paso empieza YA
		_camera_home()
		_select_action(actions[menu_index])

## Transición inversa: al volver al menú, la cámara se acerca primero y, cuando llega, los bloques aparecen (MENU_FADE fotogramas).
func _back_to_menu(h: BattleHero) -> void:
	_focus(h)
	set_phase(&"menu_in")

func _menu_in() -> void:
	if frame >= MENU_FADE:   # los bloques reaparecen a la vez que la cámara se acerca; no se espera a que termine
		set_phase(&"menu")

func _select_action(id: StringName) -> void:
	match id:
		&"item":
			list_index = 0
			set_phase(&"items")
		&"flee":
			_begin_flee()
		&"tandem":
			var why := _tandem_block_reason(actor as BattleHero)
			if why != "" or tandems.is_empty():   # no se puede usar: avisa y vuelve al menú
				spawn_text(actor, why if why != "" else "¡Sin ataques!", Color("8fd3ff"), -20.0)
				_back_to_menu(actor as BattleHero)
			else:
				tandem_index = clampi(tandem_index, 0, tandems.size() - 1)
				set_phase(&"tandems")
		_:
			act_kind = id
			target_index = 0
			set_phase(&"target")

## Todo lo que se puede elegir como objetivo: los enemigos (su cuerpo, salvo que Body Targetable esté desactivado) y sus dianas
## (Hittable) activas y elegibles. Si un enemigo no tiene ninguna diana elegible, siempre se puede elegir su cuerpo.
func target_list() -> Array:
	var list: Array = []
	for e in living(enemies):
		var be := e as BattleEnemy
		var parts: Array = []
		for hb in be.hittables:
			if is_instance_valid(hb) and (hb as Hittable).targetable():
				parts.append(hb)
		if be.body_targetable or parts.is_empty():
			list.append(be)
		list.append_array(parts)
	return list

## Objetivos del menú actual: los tándems siempre van contra el enemigo entero; el resto, contra cualquier diana.
func current_targets() -> Array:
	return living(enemies) if act_kind == &"tandem" else target_list()

## Crea una diana al vuelo (para patrones): owner = el enemigo dueño, rel = sitio de sus PIES respecto a los pies del dueño.
func spawn_hittable(owner_enemy: BattleEnemy, mode: int, rel: Vector2, size: Vector2, label := "", color := Color(0.55, 0.8, 1.0)) -> Hittable:
	var hb := Hittable.new()
	hb.mode = mode as Hittable.Mode
	hb.body_size = size
	hb.label = label
	hb.placeholder_color = color
	hb.attach(owner_enemy, self, rel)
	return hb

func _target() -> void:
	var h := actor as BattleHero
	var es := current_targets()
	target_index = clampi(target_index, 0, es.size() - 1)
	say("Elige objetivo — ◄ ►: cambiar · %s: confirmar · %s: volver" % [key_of(h.action()), key_of(&"cancel")])
	if Input.is_action_just_pressed(&"ui_left"):
		target_index = wrapi(target_index - 1, 0, es.size())
	if Input.is_action_just_pressed(&"ui_right"):
		target_index = wrapi(target_index + 1, 0, es.size())
	if Input.is_action_just_pressed(&"cancel"):
		if act_kind == &"tandem":
			set_phase(&"tandems")   # vuelve a la lista de tándems
		else:
			_back_to_menu(h)   # vuelve al menú: la cámara se acerca y luego reaparecen los bloques
	elif Input.is_action_just_pressed(h.action()):
		var t: BattleActor = es[target_index]
		if act_kind == &"hammer":
			_begin_hammer(h, t)
		elif act_kind == &"tandem":
			_begin_tandem(h, t as BattleEnemy)
		elif t.is_spiked():
			_begin_spike(h, t)
		else:
			_begin_jump(h, t)

# ───────────────────────────── objetos ─────────────────────────────

func _items() -> void:
	var h := actor as BattleHero
	var n := BattleItems.ORDER.size()
	say("Objetos — ▲ ▼: elegir · %s: usar · %s: volver" % [key_of(h.action()), key_of(&"cancel")])
	if Input.is_action_just_pressed(&"ui_up"):
		list_index = wrapi(list_index - 1, 0, n)
	if Input.is_action_just_pressed(&"ui_down"):
		list_index = wrapi(list_index + 1, 0, n)
	if Input.is_action_just_pressed(&"cancel"):
		_back_to_menu(h)
	elif Input.is_action_just_pressed(h.action()):
		var id: StringName = BattleItems.ORDER[list_index]
		var first := -1
		for i in heroes.size():
			if BattleItems.can_use(id, heroes[i]):
				first = i
				break
		if int(GameState.inventory.get(id, 0)) <= 0:
			_warn("No te quedan %s." % BattleItems.item_name(id))
		elif first < 0:
			_warn(BattleItems.DEFS[id]["none"])
		else:
			item_id = id
			target_index = first
			set_phase(&"item_target")

func _item_target() -> void:
	var h := actor as BattleHero
	say("¿A quién? — ◄ ►: cambiar · %s: usar · %s: volver" % [key_of(h.action()), key_of(&"cancel")])
	if Input.is_action_just_pressed(&"ui_left"):
		target_index = wrapi(target_index - 1, 0, heroes.size())
	if Input.is_action_just_pressed(&"ui_right"):
		target_index = wrapi(target_index + 1, 0, heroes.size())
	if Input.is_action_just_pressed(&"cancel"):
		set_phase(&"items")
	elif Input.is_action_just_pressed(h.action()):
		var t := heroes[target_index]
		if BattleItems.can_use(item_id, t):
			GameState.inventory[item_id] = int(GameState.inventory.get(item_id, 0)) - 1
			GameState.changed.emit()
			var r := BattleItems.apply(item_id, t)
			spawn_text(t, r, Color("7dff9a"))
			say("%s usa %s%s — %s" % [h.display_name, BattleItems.item_name(item_id), "" if t == h else " en " + t.display_name, r])
			set_phase(&"item_use")
		else:
			_warn(BattleItems.why_not(item_id, t))

# ───────────────────────────── salto ─────────────────────────────

func _begin_jump(h: BattleHero, t: BattleActor) -> void:
	_atk_begin()
	actor = h
	target = t
	h.z_index = 1   # durante el ataque se dibuja POR DELANTE de los enemigos (si no, pasaba por detrás de los más adelantados)
	var dd: float = t.position.x - h.position.x - ADVANCE_DIST - 4.0
	att = {"dist": dd, "hold": (t.position.y - t.body_height()) - h.position.y,
		"walk": dd * JUMP["walk_frac"], "c1": JUMP["walk"] + JUMP["j1"], "c2": JUMP["walk"] + JUMP["j1"] + JUMP["j2"],
		"r1": &"", "r2": &"", "done1": false, "done2": false, "fail_f": -1, "fail_c": 0, "end_f": 9999}
	_camera_home()
	set_phase(&"jump_anim")

## Salto estilo Mario & Luigi: avanza un poco → salto alto al enemigo (pulsa al caer) → si acierta, rebota alto
## (pulsa al caer otra vez) → si acierta de nuevo, vuelve a su sitio de UN salto. Si falla en cualquier momento,
## cae cerca del enemigo y vuelve ANDANDO.
func _animate_jump() -> void:
	var h := actor as BattleHero
	var f := frame
	var d: float = att["dist"]
	var hd: float = att["hold"]
	var wk: float = att["walk"]
	var c1: int = att["c1"]
	var c2: int = att["c2"]
	var land := Vector2(d - JUMP["land_back"], 0.0)   # donde aterriza si falla: cerca del enemigo, en su fila
	var off := Vector2.ZERO
	var gy := 0.0   # cuánto ha bajado el SUELO bajo el héroe (la sombra se queda en el suelo, no sube con el salto)
	var full: float = hd + target.body_height()   # distancia vertical entre el suelo del héroe y el del enemigo
	var pressed := Input.is_action_just_pressed(h.action())
	# ── entrada: pulsaciones y resultados ──
	if att["r1"] == &"" and f > JUMP["walk"]:
		if pressed:
			att["r1"] = &"hit" if f >= c1 - JUMP["win"] else &"miss"
		elif f >= c1 + JUMP["late"]:
			att["r1"] = &"miss"
		if att["r1"] != &"": att["rf1"] = maxi(f, c1)
	if att["r1"] != &"" and not att["done1"] and f >= c1:
		att["done1"] = true
		_resolve_jump_hit(1)
	if att["done1"] and att["r1"] == &"hit" and att["r2"] == &"" and f > c1 + 6:
		if pressed:
			att["r2"] = &"hit" if f >= c2 - JUMP["win"] else &"miss"
		elif f >= c2 + JUMP["late"]:
			att["r2"] = &"miss"
		if att["r2"] != &"": att["rf2"] = maxi(f, c2)
	if att["r2"] != &"" and not att["done2"] and f >= c2:
		att["done2"] = true
		_resolve_jump_hit(2)
	# ── movimiento ──
	h.spin = 0.0
	if f <= JUMP["walk"]:   # avanza un poco (andando)
		var p := ease_in_out(float(f) / JUMP["walk"])
		off = Vector2(wk * p, -absf(sin(p * PI * 3.0)) * 2.0)
	elif f <= c1:   # primer salto, alto, hacia el enemigo
		var p1: float = float(f - int(JUMP["walk"])) / float(JUMP["j1"])
		off = Vector2(lerpf(wk, d, p1), hd * p1 - parabola(p1) * JUMP["h1"])   # x constante + y parabólica = parábola real
		gy = full * p1
	elif att["r1"] == &"hit" and f <= c2:   # segundo salto, alto, encima del enemigo
		var p2: float = float(f - c1) / float(JUMP["j2"])
		off = Vector2(d, hd - parabola(p2) * JUMP["h2"])
		gy = full
		h.spin = TAU * ease_out(minf(1.0, p2 / float(JUMP["spin_end"])))   # giro de 360º, completo antes de caer
	elif (att["r1"] == &"" and f > c1) or (att["r1"] == &"hit" and att["r2"] == &"" and f > c2):
		# margen tras el contacto: se queda sobre el enemigo esperando la pulsación
		off = Vector2(d, hd)
		gy = full
	else:
		if att["r1"] == &"miss":
			att["fail_f"] = att["rf1"]
		elif att["r2"] == &"miss":
			att["fail_f"] = att["rf2"]
		if att["fail_f"] >= 0:   # fallo: rebota y cae cerca del enemigo, y luego vuelve andando
			var e: int = f - int(att["fail_f"])
			if e <= JUMP["drop"]:
				var pd: float = float(e) / float(JUMP["drop"])
				off = Vector2(d, hd).lerp(land, pd) + Vector2(0.0, -parabola(pd) * 22.0)
				gy = full * (1.0 - pd)
			else:
				var pw := minf(1.0, float(e - JUMP["drop"] - JUMP["pause"]) / JUMP["back_walk"]) if e > JUMP["drop"] + JUMP["pause"] else 0.0
				var q := ease_in_out(pw)
				off = land * (1.0 - q) + Vector2(0.0, -absf(sin(q * PI * 5.0)) * 3.0 * (1.0 if pw < 1.0 else 0.0))
				if pw >= 1.0 and int(att["end_f"]) == 9999:
					att["end_f"] = f + 4
		else:   # acierta los dos: vuelve a su sitio de UN salto
			var pb := minf(1.0, float(f - c2) / JUMP["back_jump"])
			off = Vector2(d, hd) * (1.0 - pb) + Vector2(0.0, -parabola(pb) * JUMP["h3"])
			gy = full * (1.0 - pb)
			if pb >= 1.0 and int(att["end_f"]) == 9999:
				att["end_f"] = f + 6
	h.offset = off
	h.shadow_y = h.position.y + gy
	# ── mensajes ──
	if f <= JUMP["walk"]:
		say("%s avanza..." % h.display_name)
	elif att["r1"] == &"" and f <= c1:
		say("¡Pulsa %s justo al caer sobre %s!" % [key_of(h.action()), target.display_name])
	elif att["r1"] == &"hit" and att["r2"] == &"" and f <= c2:
		say("¡Rebota! Pulsa %s otra vez al caer" % key_of(h.action()))
	if f >= att["end_f"]:
		h.offset = Vector2.ZERO
		h.shadow_y = NAN
		next_turn()

## Resultado de un golpe del salto (n = 1 primer salto, 2 rebote): daño y mensaje.
func _resolve_jump_hit(n: int) -> void:
	var h := actor
	var hit: bool = att["r%d" % n] == &"hit"
	var d := strike(h, target, 2 if hit else 1)
	if hit:
		celebrate(rank_level(n - 1, 2))   # el salto tiene 2 golpes
		say(("%s conecta el salto — ¡buen golpe! (-%d PV)" if n == 1 else "¡Rebote perfecto! Otro golpe (-%d PV)") % ([h.display_name, d] if n == 1 else [d]))
	else:
		say("%s falla el timing... golpe débil (-%d PV)" % [h.display_name, d])

## Saltar sobre un enemigo con pinchos: no le hace daño, te hiere y sales rebotado dando vueltas.
func _begin_spike(h: BattleHero, t: BattleActor) -> void:
	actor = h
	target = t
	h.z_index = 1
	att = {"dist": t.position.x - h.position.x - ADVANCE_DIST - 4.0, "hold": (t.position.y - t.body_height()) - h.position.y}
	_camera_home()
	set_phase(&"spike_anim")

func _animate_spike() -> void:
	var h := actor as BattleHero
	var f := frame
	var d: float = att["dist"]
	var hd: float = att["hold"]
	var full: float = hd + target.body_height()
	if f <= 14:
		h.offset = Vector2(0, f / 14.0 * 6.0)
		h.shadow_y = h.position.y
		say("%s toma impulso..." % h.display_name)
	elif f <= 42:
		var p := (f - 14) / 28.0
		h.offset = Vector2(d * ease_out(p), hd * p - sin(p * PI) * 34.0)
		h.shadow_y = h.position.y + full * p
	else:
		var p2 := minf(1.0, (f - 42) / 50.0)
		h.offset = Vector2(d * (1.0 - ease_out(p2)), hd * (1.0 - p2) - sin(p2 * PI) * 70.0)
		h.spin = PI * 4.0 * ease_out(p2)
		h.shadow_y = h.position.y + full * (1.0 - p2)
	if f == 42:
		if target is BattleEnemy:
			(target as BattleEnemy).spark = 16
		var sd := _strike_raw(SPIKES["power"], SPIKES["stache"], h, 3)
		say("¡Los pinchos hieren a %s! (-%d PV) — solo el martillo le hace daño" % [h.display_name, sd])
	if f >= 92:
		h.offset = Vector2.ZERO
		h.spin = 0.0
		h.shadow_y = NAN
		next_turn()

# ───────────────────────────── martillo ─────────────────────────────

func _begin_hammer(h: BattleHero, t: BattleActor) -> void:
	_atk_begin()
	actor = h
	target = t
	h.z_index = 1
	att = {"dx": (t.position.x - t.body_width() * 0.5 - 44.0) - h.position.x - ADVANCE_DIST, "dy": t.position.y - h.position.y,
		"res": &"", "swing_at": -1, "from": 0.0, "done": false}
	h.hammer = {"angle": 2.6, "scale": 0.0, "glow": false}
	_camera_home()
	set_phase(&"hammer_anim")

func _animate_hammer() -> void:
	var h := actor as BattleHero
	var f := frame
	var hm: Dictionary = h.hammer
	var dx: float = att["dx"]
	var dy: float = att["dy"]
	var cs: int = HAMMER["draw"] + HAMMER["walk"]   # inicio de la carga
	if f <= HAMMER["draw"]:   # saca el martillo
		var p := ease_out(float(f) / HAMMER["draw"])
		hm["scale"] = p
		hm["angle"] = 2.6 - 1.5 * p
		say("%s saca su martillo..." % h.display_name)
	elif f <= cs:   # se coloca frente al enemigo
		var p2 := ease_in_out(float(f - HAMMER["draw"]) / HAMMER["walk"])
		h.offset = Vector2(dx * p2, dy * p2 - absf(sin(p2 * PI * 4.0)) * 4.0)
		hm["angle"] = 1.1
		say("%s se coloca frente a %s..." % [h.display_name, target.display_name])
	elif att["swing_at"] < 0:   # carga: ventana de acción
		var rel := f - cs
		h.offset = Vector2(dx, dy)
		hm["angle"] = 1.1 - 3.1 * ease_out(minf(1.0, float(rel) / HAMMER["raise"])) + (sin(f * 1.2) * 0.04 if rel > HAMMER["raise"] else 0.0)
		hm["glow"] = rel >= HAMMER["win_from"] and rel <= HAMMER["win_to"]
		say("%s carga el martillo — ¡pulsa %s cuando brille!" % [h.display_name, key_of(h.action())])
		if Input.is_action_just_pressed(h.action()):
			att["res"] = &"early" if rel < HAMMER["win_from"] else (&"strong" if rel <= HAMMER["win_to"] + HAMMER["late"] else &"miss")
		elif rel > HAMMER["win_to"] + HAMMER["late"]:
			att["res"] = &"miss"
		if att["res"] != &"":
			att["swing_at"] = f
			att["from"] = hm["angle"]
			hm["glow"] = false
	else:   # golpe y vuelta
		var s: int = f - att["swing_at"]
		var S: int = HAMMER["swing"]
		var hold: int = HAMMER["hold"]
		if s <= S:
			var from: float = att["from"]
			hm["angle"] = from + (0.05 - from) * ease_in(float(s) / S)
		if s == S and not att["done"]:   # el daño se aplica cuando el martillo toca al enemigo
			att["done"] = true
			var dmg := strike(h, target, HAMMER_DMG[att["res"]])
			shake = 6
			if att["res"] == &"strong":
				celebrate(rank_level(0, 1))   # el martillo es un solo golpe; si falla o llega pronto, no hay celebración
			match att["res"]:
				&"strong":
					say("¡Golpe de martillo perfecto! (-%d PV)" % dmg)
				&"early":
					say("%s golpea demasiado pronto... poca fuerza (-%d PV)" % [h.display_name, dmg])
				_:
					say("%s falla el timing... golpe mínimo (-%d PV)" % [h.display_name, dmg])
		if s > S and s <= S + hold:
			hm["angle"] = 0.05
		if s > S + hold:
			var p3 := minf(1.0, float(s - S - hold) / HAMMER["back"])
			var q := ease_in_out(p3)
			h.offset = Vector2(dx * (1.0 - q), dy * (1.0 - q) - absf(sin(q * PI * 4.0)) * 4.0 * (1.0 if p3 < 1.0 else 0.0))
			hm["angle"] = 0.05 + 1.05 * p3
			hm["scale"] = 1.0 - ease_in(maxf(0.0, (p3 - 0.6) / 0.4))
		if s >= S + hold + HAMMER["back"]:
			h.offset = Vector2.ZERO
			h.hammer = null
			next_turn()

# ───────────────────────────── tándem ─────────────────────────────
## Los ataques TÁNDEM son recursos (Combate/tandem_data.gd) con su propio script de animación (Combate/tandems/tandem_attack.gd).
## Aquí solo está el menú, el pago de PT y el arranque/final; cada ataque programa su secuencia en su script.
## Para añadir uno nuevo, mira los comentarios de tandem_data.gd.

## Todos los .tres de Combate/tandems/ (si "Tandems" del Inspector está vacío).
func _load_tandems() -> void:
	if not tandems.is_empty():
		return
	var dir := DirAccess.open(TANDEM_DIR)
	if dir == null:
		return
	var files := dir.get_files()
	files.sort()
	for fname in files:
		var path := fname.trim_suffix(".remap")   # en el juego exportado los recursos terminan en .remap
		if path.ends_with(".tres"):
			var res := load(TANDEM_DIR + path) as TandemData
			if res != null:
				tandems.append(res)

## "" si se puede usar; si no, el motivo (texto corto que sale sobre el héroe).
func _tandem_block_reason(h: BattleHero, d: TandemData = null) -> String:
	if heroes.size() < 2:
		return "¡Faltan hermanos!"
	for hh in heroes:
		if not hh.alive:
			return "¡Faltan hermanos!"
	if d != null and h.tp < d.cost:
		return "¡Sin PT!"
	return ""

func _begin_tandem(h: BattleHero, t: BattleEnemy) -> void:
	var d: TandemData = chosen_tandem
	_atk_begin()
	actor = h
	target = t
	for hz in heroes:
		hz.z_index = 1
	h.tp -= d.cost   # paga solo quien elige el ataque
	spawn_text(h, "-%d PT" % d.cost, Color("8fd3ff"))
	if _hero_tween:
		_hero_tween.kill()
	for hh in heroes:   # sin avance ni retroceso del turno: parten de su sitio
		hh.advance = Vector2.ZERO
		hh.offset = Vector2.ZERO
		hh.spin = 0.0
		hh.hammer = null
	ring = {}
	bursts = []
	shell = {}
	popups = []
	combo = {}
	_camera_home()
	tandem = d.attack.new() as TandemAttack
	tandem.start(self, d, h, t)
	set_phase(&"tandem_anim")

func _tp_end() -> void:
	for hh in heroes:
		hh.offset = Vector2.ZERO
		hh.spin = 0.0
		hh.shadow_y = NAN
		hh.anim_override = &""
	ring = {}
	bursts = []
	shell = {}
	popups = []
	combo = {}
	tandem = null
	next_turn()

## Menú de ataques tándem: ▲▼ elegir · botón: usar · cancelar: volver.
func _tandem_menu() -> void:
	var h := actor as BattleHero
	var n: int = tandems.size()
	say("Bros. — ▲ ▼: elegir · %s: usar · %s: volver" % [key_of(h.action()), key_of(&"cancel")])
	if Input.is_action_just_pressed(&"ui_up"):
		tandem_index = wrapi(tandem_index - 1, 0, n)
	if Input.is_action_just_pressed(&"ui_down"):
		tandem_index = wrapi(tandem_index + 1, 0, n)
	if Input.is_action_just_pressed(&"cancel"):
		_back_to_menu(h)
	elif Input.is_action_just_pressed(h.action()):
		var d: TandemData = tandems[tandem_index]
		var why := _tandem_block_reason(h, d)
		if why != "":
			_warn(why)
			spawn_text(h, why, Color("8fd3ff"), -20.0)
		else:
			chosen_tandem = d
			act_kind = &"tandem"
			target_index = 0
			set_phase(&"target")

# ───────────────────────────── turno enemigo ─────────────────────────────

func _start_enemy_turn(e: BattleEnemy) -> void:
	var script: GDScript = e.data.pattern if e.data.pattern != null else LUNGE
	pattern = script.new() as EnemyPattern
	pattern.battle = self
	pattern.enemy = e
	if pattern.targeted():
		var hs := living(heroes)
		pattern.target = hs[randi() % hs.size()]
	actor = e
	target = pattern.target
	pattern.setup()
	say(pattern.start_message())
	set_phase(&"enemy_tell")

func _enemy_tell() -> void:
	var n := pattern.tell_frames()
	pattern.tell(minf(1.0, float(frame) / n))
	if frame >= n:
		pattern.begin()
		set_phase(&"enemy_attack")

# ───────────────────────────── huir ─────────────────────────────
## Microjuego del prototipo: los dos corren a la izquierda; hay que machacar el botón de cada hermano POR TURNOS
## (need pulsaciones y pasa al otro). Mientras, el otro avanza despacio solo.

func _begin_flee() -> void:
	_focus(null)
	for h in heroes:
		h.offset = Vector2.ZERO
		h.out = false
		h.run_t = 0
		h.anim_override = &"run" if h.alive else &""
	flee_turn = heroes.find(living(heroes)[0])
	flee_count = 0
	flee_end = -1
	set_phase(&"flee")

func _animate_flee() -> void:
	if flee_end >= 0:   # ya escaparon: pequeña pausa
		flee_end += 1
		if flee_end >= FLEE["end_delay"]:
			result = &"fled"
			set_phase(&"end")
		return
	var cur := heroes[flee_turn]
	if not cur.alive or cur.out:
		_pass_flee_turn()
		cur = heroes[flee_turn]
	for h in living(heroes):
		var hh := h as BattleHero
		if hh.out:
			continue
		if hh == cur:
			if Input.is_action_just_pressed(hh.action()):
				hh.offset.x -= FLEE["step"]
				hh.run_t = 10
				flee_count += 1
		else:
			hh.offset.x -= FLEE["drift"]
		if hh.run_t > 0:
			hh.run_t -= 1
		var running := hh.run_t > 0 if hh == cur else true
		hh.offset.y = -absf(sin(frame * (0.55 if hh == cur else 0.2))) * (5.0 if hh == cur else 2.0) if running else 0.0
		if hh.position.x + hh.offset.x < FLEE["exit_x"]:
			hh.out = true
	if living(heroes).all(func(a: BattleActor) -> bool: return (a as BattleHero).out):
		flee_end = 0
		say("¡%s %s!" % [_party_name(), "ha escapado" if heroes.size() == 1 else "han escapado"])
		return
	if cur.out or flee_count >= FLEE["need"]:
		_pass_flee_turn()
		cur = heroes[flee_turn]
	say("¡Huyendo! Machaca %s para que %s corra" % [key_of(cur.action()), cur.display_name])

func _pass_flee_turn() -> void:
	for k in range(1, heroes.size() + 1):
		var h := heroes[(flee_turn + k) % heroes.size()]
		if h.alive and not h.out:
			flee_turn = heroes.find(h)
			break
	flee_count = 0

# ───────────────────────────── diálogos ─────────────────────────────
## Conversaciones en pleno combate (BattleDialogue). La fase "dialogue" detiene todo; BattleDialogueRunner enseña el globo del
## overworld y sus preguntas. Se comprueban en los "cortes" entre turnos (next_turn), al empezar y al acabar.

## Todos los diálogos que pueden salir: los del combate y los de los enemigos presentes, como [BattleDialogue, EnemyData dueño o null].
func _dialogue_pool() -> Array:
	var out: Array = []
	for d in dialogues:
		if d != null:
			out.append([d, null])
	var seen: Array = []
	for e in enemies:
		if e.data == null or seen.has(e.data):
			continue
		seen.append(e.data)
		for d in e.data.dialogues:
			if d != null:
				out.append([d, e.data])
	return out

func _dlg_key(d: BattleDialogue, ctx: BattleActor) -> String:
	var who_id := ctx.get_instance_id() if ctx != null else 0
	if d.when == BattleDialogue.When.HERO_LOW_HP and d.who.strip_edges() == "":
		who_id = 0   # "un héroe" cualquiera: sale una sola vez, no una por héroe
	return "%d:%d:%d" % [d.get_instance_id(), who_id, round_n if d.when == BattleDialogue.When.ROUND else 0]

## Los diálogos que tocan ahora para ese momento (when) y personaje (ctx), sin repetir los ya dichos.
func _collect_dialogues(when: int, ctx: BattleActor = null) -> Array:
	var out: Array = []
	for it in _dialogue_pool():
		var d: BattleDialogue = it[0]
		var from_data: EnemyData = it[1]
		if d.when != when or d.as_node() == null:
			continue
		if from_data != null and (when == BattleDialogue.When.LOW_HP or when == BattleDialogue.When.ENEMY_DEFEATED):
			if not (ctx is BattleEnemy and (ctx as BattleEnemy).data == from_data):   # el de un enemigo solo habla por él
				continue
		var who := d.who.strip_edges().to_lower()
		if who != "" and ctx != null and ctx.display_name.to_lower() != who:
			continue
		if when == BattleDialogue.When.ROUND:
			if d.round_every > 0:
				if round_n < d.round_number or (round_n - d.round_number) % d.round_every != 0:
					continue
			elif round_n != d.round_number:
				continue
		elif when == BattleDialogue.When.LOW_HP:
			if ctx == null or not ctx.alive or ctx.hp * 100 > d.hp_percent * ctx.max_hp:
				continue
		elif when == BattleDialogue.When.HERO_LOW_HP:
			if ctx == null or not ctx.alive or ctx.hp * 100 > d.hero_hp_percent * ctx.max_hp:
				continue
		if d.require_flag != &"" and not DialogueManager.flag_matches(d.require_flag, d.require_value):
			continue
		if d.unless_flag != &"" and DialogueManager.flag_matches(d.unless_flag, d.unless_value):
			continue
		if _dlg_fired.has(_dlg_key(d, ctx)):
			continue
		if d.repeat == 1 and GameState.has_flag(d.persist_key()):
			continue
		out.append([d, ctx, from_data])
	return out

## Corte entre turnos: ¿algún enemigo herido o derrotado, o héroe caído, con algo que decir? Devuelve true si empieza a hablar.
func _boundary_dialogues() -> bool:
	if phase == &"end":
		return false
	for a in _all():
		if a.hp <= 0:
			a.alive = false
	var list: Array = []
	for e in enemies:
		if e.data == null:
			continue
		list.append_array(_collect_dialogues(BattleDialogue.When.ENEMY_DEFEATED if not e.alive else BattleDialogue.When.LOW_HP, e))
	for h in heroes:
		if not h.alive:
			list.append_array(_collect_dialogues(BattleDialogue.When.HERO_DOWN, h))
		else:
			list.append_array(_collect_dialogues(BattleDialogue.When.HERO_LOW_HP, h))
	return _play_dialogues(list, next_turn)

## Empieza a mostrar esos diálogos uno tras otro; al acabar todos se llama a "after". Devuelve false si no había ninguno.
func _play_dialogues(list: Array, after: Callable) -> bool:
	if list.is_empty() or _dlg == null:
		return false
	_dlg_queue = list.duplicate()
	_dlg_after = after
	_dlg_actions.clear()
	_dlg_options.clear()
	_focus(null)
	set_phase(&"dialogue")
	_dlg_next()
	return true

func _dlg_next() -> void:
	while not _dlg_queue.is_empty():
		var it: Array = _dlg_queue.pop_front()
		var d: BattleDialogue = it[0]
		var ctx: BattleActor = it[1]
		var key := _dlg_key(d, ctx)
		if _dlg_fired.has(key):
			continue
		_dlg_fired[key] = true
		if d.repeat == 1:
			GameState.set_flag(d.persist_key(), true)
		_dlg.start(d.as_node(), _dlg_target(d, ctx, it[2]), d.speaker, _dlg_done)
		return
	_dlg_end()

func _dlg_done(acts: Array, opts: Array = []) -> void:
	for a in acts:
		_dlg_actions.append(a)
	for o in opts:
		_dlg_options.append(o)
		dialogue_option_chosen.emit(o)
		if (o as DialogueOption).end_battle > 0:   # el combate acaba: los diálogos que quedaban ya no tienen sentido
			_dlg_queue.clear()
	for a in acts:
		if a == &"end_win" or a == &"end_lose" or a == &"end_fled":
			_dlg_queue.clear()
	_dlg_next()

## A quién apunta la cola del globo.
func _dlg_target(d: BattleDialogue, ctx: BattleActor, from_data: EnemyData = null) -> Node2D:
	var mine: Array = []   # los enemigos de este tipo, si el diálogo es de un enemigo (EnemyData)
	if from_data != null:
		for e in enemies:
			if e.data == from_data:
				mine.append(e)
	match d.points_to:
		1:
			return _hero_named(&"mario")
		2:
			return _hero_named(&"luigi")
		3:
			return _first_of(mine if not mine.is_empty() else enemies)
		4:
			return null
	if not mine.is_empty() and ctx is BattleHero:   # un diálogo del enemigo sobre un héroe lo dice el enemigo
		return _first_of(mine)
	if ctx != null:
		return ctx
	if not mine.is_empty() and d.when != BattleDialogue.When.VICTORY:
		return _first_of(mine)
	if d.when == BattleDialogue.When.VICTORY:
		return _first_of(heroes)
	return _first_of(enemies)

func _first_of(list: Array) -> Node2D:
	var l := living(list)
	if not l.is_empty():
		return l[0]
	return list[0] if not list.is_empty() else null

func _hero_named(id: StringName) -> Node2D:
	for h in heroes:
		if h.stats != null and String(h.stats.id).to_lower() == String(id):
			return h
	return heroes[0] if not heroes.is_empty() else null

## Terminaron todos los diálogos de este corte: se atienden las acciones de las opciones y el combate sigue.
func _dlg_end() -> void:
	var cb := _dlg_after
	_dlg_after = Callable()
	var acts := _dlg_actions.duplicate()
	_dlg_actions.clear()
	var opts := _dlg_options.duplicate()
	_dlg_options.clear()
	var finishing := result != &""   # ya está acabando el combate: las consecuencias de combate no hacen nada
	var end_kind := 0   # 1 victoria · 2 derrota · 3 huida
	for a in acts:
		dialogue_action.emit(a)
		if finishing:
			continue
		match a:
			&"end_win":
				end_kind = 1
			&"end_lose":
				end_kind = 2
			&"end_fled":
				end_kind = 3
			&"heal_heroes":
				for h in heroes:
					h.hp = h.max_hp
					h.alive = true
	if not finishing:
		for o in opts:
			var op := o as DialogueOption
			if op.end_battle > 0:
				end_kind = op.end_battle
			_apply_option(op)
	match end_kind:
		1:   # victoria: los enemigos caen y todo sigue su curso normal (diálogos de derrota, recompensas...)
			for e in enemies:
				e.hp = 0
				e.alive = false
		2:   # derrota: los héroes se rinden / pierden. Sin más diálogos; se pasa a la escena elegida (o la de siempre)
			_end_early(&"lose", "%s %s..." % [_party_name(), "se rinde" if heroes.size() == 1 else "se rinden"])
			return
		3:
			_end_early(&"fled", "")
			return
	if cb.is_valid():
		cb.call()

## Termina el combate ya (rendirse, huir por una conversación).
func _end_early(res: StringName, msg: String) -> void:
	_focus(null)
	result = res
	_end_dlg_done = true
	if msg != "":
		say(msg)
	set_phase(&"end")
	frame = maxi(0, int(END_DELAY[res]) - 30)   # una pausa corta antes de salir

## Consecuencias de una opción elegida en un diálogo de combate (DialogueOption → "Consecuencias en combate").
func _apply_option(o: DialogueOption) -> void:
	if o.heroes_hp_percent != 0:
		for h in heroes:
			_change_hp(h, o.heroes_hp_percent)
	if o.enemies_hp_percent != 0:
		for e in enemies:
			if e.alive:
				_change_hp(e, o.enemies_hp_percent)
	if o.coins > 0:
		GameState.add_coins(o.coins)
	elif o.coins < 0:
		GameState.add_coins(-mini(GameState.coins, -o.coins))
	if o.give_item != &"" and o.item_count != 0:
		GameState.inventory[o.give_item] = maxi(0, int(GameState.inventory.get(o.give_item, 0)) + o.item_count)
		GameState.changed.emit()
	if o.go_to_scene != "":
		GameState.battle_return_scene = o.go_to_scene
		GameState.flags.erase(&"ow_return")   # no volvemos a donde estaba el enemigo: nada que recolocar

## Cura o hiere a un personaje en % de su vida máxima (con número flotante). Curar a un caído lo levanta.
func _change_hp(a: BattleActor, percent: int) -> void:
	var d := roundi(float(a.max_hp) * float(percent) / 100.0)
	if d == 0:
		d = 1 if percent > 0 else -1
	a.hp = clampi(a.hp + d, 0, a.max_hp)
	if a.hp > 0 and d > 0:
		a.alive = true
	spawn_text(a, "%+d" % d, Color(0.45, 1.0, 0.5) if d > 0 else Color(1.0, 0.45, 0.4))

## Tras las últimas palabras (victoria / derrota) vuelve a la fase final sin reiniciar su cuenta.
func _resume_end() -> void:
	phase = &"end"

# ───────────────────────────── final ─────────────────────────────

## Recompensas (como grantVictory del prototipo): PX para los dos, monedas y objetos que sueltan los enemigos.
func _grant_victory() -> void:
	var exp_total := 0
	var coins := 0
	var got := {}
	for e in enemies:
		exp_total += e.data.exp_reward
		coins += e.data.coin_reward
		for k in e.data.drops:
			if randf() < float(e.data.drops[k]):
				got[StringName(k)] = int(got.get(StringName(k), 0)) + 1
	var coins0: int = GameState.coins
	GameState.add_coins(coins)
	var parts: PackedStringArray = ["¡Victoria! +%d PX · +%d monedas" % [exp_total, coins]]
	for id in got:
		GameState.inventory[id] = int(GameState.inventory.get(id, 0)) + got[id]
		parts.append("+%d %s" % [got[id], BattleItems.item_name(id) if BattleItems.DEFS.has(id) else String(id)])
	var hd: Array = []
	for h in heroes:
		var id: StringName = h.stats.id
		var lv0: int = int(GameState.hero_level.get(id, 1))
		var exp0: int = int(GameState.hero_exp.get(id, 0))
		var need0: int = GameState.exp_need(lv0)
		var ups: Array = []
		if GameState.add_exp(id, exp_total) > 0:
			parts.append("¡%s sube al nivel %d!" % [h.display_name, GameState.hero_level[id]])
			for l in range(lv0 + 1, int(GameState.hero_level[id]) + 1):
				ups.append(l)
		var lv1: int = int(GameState.hero_level.get(id, 1))
		hd.append({"id": id, "lv0": lv0, "exp0": exp0, "need0": need0,
			"exp1": int(GameState.hero_exp.get(id, 0)), "need1": GameState.exp_need(lv1), "ups": ups})
	victory_data = {"exp": exp_total, "coins0": coins0, "got": coins, "items": got, "heroes": hd}
	say(" · ".join(parts))

var victory_data: Dictionary = {}

func _show_victory() -> void:
	set_phase(&"victory_screen")
	var vs := VictoryScreen.new()
	vs.setup(victory_data, heroes)   # antes de añadirla: su _ready copia a los hermanos
	add_child(vs)
	vs.finished.connect(_finish)

## FONDO según el enemigo que tocaste en el overworld (OverworldEnemy → Battle Background). Si no puso ninguno, se queda el de esta escena.
## La imagen nueva ocupa el mismo hueco que la anterior (mismo centro y tamaño en pantalla).
func _apply_background() -> void:
	var bg: Variant = GameState.flags.get(&"battle_bg")
	GameState.flags.erase(&"battle_bg")   # solo vale para este combate
	if not (bg is Dictionary) or not (bg as Dictionary).has("texture"):
		return
	var d := bg as Dictionary
	var holder := get_node_or_null("Background") as Node2D
	if holder == null:
		holder = Node2D.new()
		holder.name = "Background"
		holder.z_index = -10
		add_child(holder)
		move_child(holder, 0)
	var spr: Sprite2D = null
	for c in holder.get_children():   # el fondo normal (su Sprite2D) se sustituye por el de la habitación
		if c is Sprite2D and spr == null:
			spr = c as Sprite2D
		elif c is CanvasItem:
			(c as CanvasItem).visible = false
	if spr == null:
		spr = Sprite2D.new()
		spr.name = "Image"
		holder.add_child(spr)
	var bg_cam := get_node_or_null("Camera") as Camera2D
	var center: Vector2 = bg_cam.position if bg_cam != null else Vector2(576.0, 324.0)   # el centro de la pantalla del combate
	spr.texture = d["texture"]
	spr.centered = bool(d["centered"])
	spr.offset = d["offset"]
	spr.position = center + (d["position"] as Vector2)
	spr.rotation = float(d["rotation"])
	spr.scale = d["scale"]
	spr.modulate = d["modulate"]
	spr.flip_h = bool(d["flip_h"])
	spr.flip_v = bool(d["flip_v"])
	spr.texture_filter = int(d["filter"]) as CanvasItem.TextureFilter
	spr.visible = true

func _finish() -> void:
	if result == &"lose":   # como el prototipo: tras perder, vuelven con la vida y los PT al máximo
		for h in heroes:
			GameState.hero_hp.erase(h.stats.id)
			GameState.hero_tp.erase(h.stats.id)
	else:   # tras ganar o huir se conservan (los caídos se levantan con 1 PV)
		for h in heroes:
			GameState.hero_hp[h.stats.id] = maxi(1, h.hp)
			GameState.hero_tp[h.stats.id] = h.tp
	GameState.last_battle_result = result
	GameState.battle_enemies = []
	var back := GameState.battle_return_scene
	GameState.battle_return_scene = ""
	set_phase(&"done")
	if back != "":
		get_tree().change_scene_to_file(back)
	else:
		get_tree().reload_current_scene()   # modo prueba: vuelve a empezar el combate

# ───────────────────────────── daño ─────────────────────────────
## Fórmula del prototipo: base × (fuerza / 10) × 10 / (10 + defensa del objetivo), mínimo 1. Bigote = % de crítico (×1,5).

func enemy_base() -> int:
	return 10 + randi() % 4

func strike(attacker: BattleActor, tgt: BattleActor, base: float) -> int:
	if tgt is Hittable:   # una diana decide qué pasa (dañar a su dueño, destruirse, devolverse...)
		return (tgt as Hittable).take_hit(self, attacker, base)
	return _strike_raw(attacker.power, attacker.stache, tgt, base, Vector2.INF, attacker)

## at = dónde sale la estrella de daño (por defecto, a media altura del objetivo). who = quién ataca (para las medallas).
func _strike_raw(att_power: int, stache: int, tgt: BattleActor, base: float, at := Vector2.INF, who: BattleActor = null) -> int:
	var d := maxi(1, roundi(base * (att_power / 10.0) * (10.0 / (10.0 + tgt.defense))))
	if randf() * 100.0 < stache:
		d = ceili(d * CRIT_MULT)
		spawn_text(tgt, "¡Crítico!", Color("ffd84a"), -26.0)
	# Medalla Doble Filo (data/badges/double_edge.tres): quien la lleva hace el doble de daño... y recibe el doble.
	if who is BattleHero and GameState.has_badge((who as BattleHero).stats.id, &"doubleEdge"):
		d *= 2
	if tgt is BattleHero and GameState.has_badge((tgt as BattleHero).stats.id, &"doubleEdge"):
		d *= 2
	tgt.hp = maxi(0, tgt.hp - d)
	tgt.flash = 14
	if tgt is BattleEnemy:   # a un enemigo: el daño sale en una estrella de impacto (salto, martillo, tándem...)
		# por defecto, arriba a la derecha del enemigo (en proporción a su tamaño, para que valga con cualquier Body Size)
		var sp: Vector2 = tgt.position + tgt.offset + Vector2(tgt.body_width() * 0.3, -tgt.body_height() * 0.75) if at == Vector2.INF else at
		if atk_active:
			atk_total += d
			atk_hits += 1
			atk_last = sp
		add_star(sp + Vector2(randf_range(-8.0, 8.0), 0.0), str(d), atk_active)
		impacts.append({"pos": sp, "t": 0, "odd": atk_hits % 2 == 1 or not atk_active})
		(tgt as BattleEnemy).hit_react(fx, d)
	else:
		spawn_text(tgt, "-%d" % d, Color("ff6b6b"))
	return d

func spawn_text(who: BattleActor, text: String, color: Color, dy := 0.0) -> void:
	if damage_number_scene == null:
		return
	var n := damage_number_scene.instantiate()
	n.position = who.position + who.offset + who.advance + Vector2(0, -who.body_height() - 18.0 + dy)
	add_child(n)
	if n.has_method("setup"):
		n.setup(text, color)

# ───────────────────────────── utilidades ─────────────────────────────

func say(t: String) -> void:
	message = t

## Nombres de los héroes que participan ("Mario y Luigi", o solo "Mario" si Luigi no está en el combate).
func _party_name() -> String:
	var names: PackedStringArray = []
	for h in heroes:
		names.append(h.display_name)
	return " y ".join(names)

func _warn(t: String) -> void:
	warn = t
	warn_t = 90

## Tecla asignada a una acción del Input Map (para los mensajes).
func key_of(action: StringName) -> String:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			return OS.get_keycode_string(k.physical_keycode if k.physical_keycode != 0 else k.keycode)
	return String(action)

## Arco parabólico de un salto: 0 al despegar, 1 en el punto más alto (p = 0.5), 0 al aterrizar.
static func parabola(p: float) -> float:
	return 4.0 * p * (1.0 - p)

static func ease_out(p: float) -> float:
	return 1.0 - (1.0 - p) * (1.0 - p)

static func ease_in(p: float) -> float:
	return p * p

static func ease_in_out(p: float) -> float:
	return 2.0 * p * p if p < 0.5 else 1.0 - 2.0 * (1.0 - p) * (1.0 - p)
