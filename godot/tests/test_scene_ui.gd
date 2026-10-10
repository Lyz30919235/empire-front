extends SceneTree
## Deterministic scene integration: use the board's actual input handler and
## authoritative rules, with animations and the solo AI disabled.
const Rules = preload("res://scripts/engine.gd")
const Card = preload("res://scripts/card_view.gd")
var ui
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("SCENE_UI: " + message)

func _mouse(pos: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = pos
	event.global_position = pos
	event.pressed = pressed
	ui._input(event)

func _motion(pos: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	event.global_position = pos
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	ui._input(event)

func _escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	ui._input(event)

func _center(uid: int) -> Vector2:
	var node = ui.card_nodes[uid]
	return node.get_global_transform() * (node.size / 2)

func _lane(lane_value: int) -> Vector2:
	return Vector2(110, ui.LANES[ui._row_for_lane(lane_value)].get_center().y)

func _drag(uid: int, destination: Vector2) -> void:
	_mouse(_center(uid), true)
	_motion(destination)
	_mouse(destination, false)

func _click(uid: int) -> void:
	var pos := _center(uid)
	_mouse(pos, true)
	_mouse(pos, false)

func _reset(p: int = 0, hand: Array = []) -> void:
	ui.rules = Rules.new([], [], 731)
	ui.rules.phase = "battle"
	ui.rules.mulligan_done = [true, true]
	ui.rules.turn = p
	ui.selected = {}
	ui.marked.clear()
	ui.skill_mode = ""
	ui.hovered = -1
	for player in ui.rules.players:
		player.hand.clear()
		player.board.clear()
		player.mana = 10
		player.max_mana = 10
	for key in hand:
		ui.rules.players[p].hand.append({"uid":ui.rules.next_id,"card":key})
		ui.rules.next_id += 1
	ui._accept_state(ui.rules.view(p))

func _sync(p: int = 0) -> void:
	ui._accept_state(ui.rules.view(p))

func _hand_uid(p: int = 0) -> int:
	return int(ui.rules.players[p].hand[0].uid)

func _drain_fx() -> void:
	for i in range(80):
		if not ui.battle_fx.is_busy(): return
		await create_timer(0.025).timeout
	_check(false,"effect queue drains within two seconds")

func _run() -> void:
	ui = load("res://main.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	ui.settings.animations = false
	ui.settings.sound = false
	ui.set_process(false)
	ui.deck = ui.rules.default_deck.duplicate()
	ui._solo()
	_check(ui.state.phase == "mulligan" and ui.card_nodes.size() == 4, "solo renders four opening cards")
	var initial_uid := int(ui.state.players[0].hand[0].uid)
	_click(initial_uid)
	_check(ui.marked == [initial_uid] and ui.card_nodes[initial_uid].marked, "click marks the mulligan card")
	_click(initial_uid)
	_check(ui.marked.is_empty(), "second click keeps the mulligan card")
	_click(initial_uid)
	ui.hud.confirm.pressed.emit()
	_check(ui.state.phase == "battle" and ui.marked.is_empty(), "confirm button starts battle and clears marks")
	_check(not ui.card_nodes.has(initial_uid), "replaced card leaves the visible opening hand")

	_reset(0, ["infantry"])
	var hand_uid := _hand_uid()
	var before: int = ui.rules.revision
	_drag(hand_uid, _lane(2))
	_check(ui.rules.revision == before and ui.rules.players[0].mana == 10 and ui.rules.players[0].hand.size() == 1, "invalid frontline deployment preserves hand, mana and revision")
	_drag(hand_uid, _lane(3))
	_check(ui.rules.players[0].hand.is_empty() and ui.rules.players[0].mana == 8, "rear deployment consumes the card and exactly its cost")
	_check(ui.rules.players[0].board.size() == 1 and ui.rules.players[0].board[0].lane == 3, "rear deployment creates a unit in global lane three")
	_check(ui.ghost == null and not ui.dragging and ui.press.is_empty(), "release clears drag visuals and input state")

	_reset()
	var moving = ui.rules.summon(0, "infantry", 3)
	moving.actions = 2
	_sync()
	_drag(int(moving.uid), _lane(1))
	_check(moving.lane == 3 and moving.actions == 2, "jumping two lanes is rejected without spending actions")
	_drag(int(moving.uid), _lane(2))
	_check(moving.lane == 2 and moving.actions == 1, "adjacent movement spends exactly one action")

	_reset()
	var attacker = ui.rules.summon(0, "infantry", 2)
	attacker.actions = 2
	var defender = ui.rules.summon(1, "heavy_cavalry", 1)
	_sync()
	_drag(int(attacker.uid), _center(int(defender.uid)))
	_check(defender.hp == 4 and attacker.actions == 1, "dragging onto an enemy executes attack damage and action cost")

	_reset(0, ["fireball"])
	defender = ui.rules.summon(1, "heavy_cavalry", 0)
	_sync()
	_drag(_hand_uid(), _center(int(defender.uid)))
	_check(defender.hp == 1 and ui.rules.players[0].mana == 6 and ui.rules.players[0].hand.is_empty(), "targeted spell uses enemy hit target and spends exact mana")

	_reset(0, ["infantry"])
	hand_uid = _hand_uid()
	_mouse(_center(hand_uid), true)
	_motion(_lane(3))
	_check(ui.dragging and ui.ghost != null, "mouse motion creates a drag ghost")
	_escape()
	_mouse(_lane(3), false)
	_check(ui.rules.players[0].board.is_empty() and ui.rules.players[0].mana == 10 and ui.rules.players[0].hand.size() == 1, "Escape followed by release never deploys the cancelled card")
	_check(ui.selected.is_empty() and ui.ghost == null and ui.card_nodes[hand_uid].modulate.a == 1.0, "Escape restores original opacity and clears selection")
	_mouse(_center(hand_uid), true)
	_motion(Vector2(1390, 540))
	_mouse(Vector2(1390, 540), false)
	_check(not ui.dragging and ui.ghost == null and ui.press.is_empty() and ui.card_nodes[hand_uid].modulate.a == 1.0, "releasing over the side panel clears drag state and original opacity")
	_check(ui.rules.players[0].board.is_empty() and ui.rules.players[0].mana == 10, "releasing over the side panel never deploys or spends mana")
	_escape()

	_reset(1, ["infantry"])
	_check(ui._target(Vector2(110, 576)).lane == 0 and ui._target(Vector2(110, 216)).lane == 3, "player one maps rear and enemy rear to reversed global lanes")
	_drag(_hand_uid(1), Vector2(110, 576))
	_check(ui.rules.players[1].board.size() == 1 and ui.rules.players[1].board[0].lane == 0 and ui.rules.players[1].mana == 8, "player one rear drag deploys to global zero")
	var own = ui.rules.players[1].board[0]
	own.actions = 2
	_sync(1)
	_drag(int(own.uid), _lane(1))
	_check(own.lane == 1 and own.actions == 1, "player one movement preserves reversed lane mapping")

	# Fixed positions and precise placement use the same public slot geometry.
	_reset(0,["infantry"])
	_drag(_hand_uid(),ui._slot_rect(3,6).get_center())
	_check(ui.rules.players[0].board[0].slot == 6,"hand drag chooses exact defender-exclusive slot six")
	for slot in [0,1,2,3,4,5]: ui.rules.summon(0,"scout",3,false,slot)
	_sync()
	_check(ui.unit_rects.size() == 7,"rear renders five public and two exclusive cards")
	var positions: Dictionary = {}
	for info in ui.unit_rects.values():
		positions[info.rect.position.x] = true
		_check(info.rect.end.x <= 1255 and info.rect.size == Vector2(147,98),"seven-slot card remains within board bounds")
	_check(positions.size() == 7,"all rear cards occupy distinct fixed columns")
	_reset()
	var ally = ui.rules.summon(0,"infantry",2,false,1)
	var foe = ui.rules.summon(1,"scout",2,false,4)
	ally.actions = 2
	_sync()
	_check(ui.unit_rects[int(ally.uid)].rect == ui._slot_rect(2,1) and ui.unit_rects[int(foe.uid)].rect == ui._slot_rect(2,4),"both owners share one lane without reordering slots")
	var source_pos = ui.card_nodes[int(ally.uid)].position
	_mouse(_center(int(ally.uid)),true); _motion(_center(int(foe.uid)))
	_check(ui.aiming and ui.ghost == null and ui.card_nodes[int(ally.uid)].position == source_pos and ui.card_nodes[int(ally.uid)].modulate.a == 1.0,"unit aiming preserves card position and opacity without a ghost")
	_sync()
	_check(ui.aiming and ui.press_active,"unchanged state broadcast preserves a live aiming gesture")
	_escape(); _mouse(_center(int(foe.uid)),false)
	_check(ally.actions == 2,"cancelled arrow followed by release does not attack")
	_drag(int(ally.uid),ui._slot_rect(1,3).get_center())
	_check(ally.lane == 1 and ally.slot == 3 and ally.actions == 1,"blue move arrow selects precise adjacent public slot")
	_check(ui._target(ui._slot_rect(0,5).get_center()).slot == 5,"enemy rear exclusive slot remains a precise target")
	_click(int(ally.uid)); _click(int(foe.uid))
	_check(ally.actions == 0 and foe.hp < foe.max_hp,"click selection then enemy click retains attack interaction")

	# Success-only events, lethal counterattacks, duplicate packets and switches.
	_reset()
	var striker = ui.rules.summon(0,"infantry",2,false,0)
	var counter = ui.rules.summon(1,"archer",1,false,2)
	striker.hp = 1; striker.actions = 1; counter.hp = 1
	_sync(); await _drain_fx()
	ui.settings.animations = true; ui.settings.sound = true
	var count = ui.battle_fx.played_events
	_drag(int(striker.uid),_center(int(counter.uid)))
	await _drain_fx()
	_check(ui.battle_fx.played_events > count and ui.battle_fx.sound_count > 0 and ui.battle_fx.visual_count > 0,"successful action produces both sounds and visuals")
	_check(ui.battle_fx.event_counts.get("counter",0) > 0 and ui.battle_fx.event_counts.get("death",0) >= 2,"lethal counterattack keeps both death locations and event sequence")
	count = ui.battle_fx.played_events
	_sync(); await _drain_fx()
	_check(ui.battle_fx.played_events == count,"duplicate revision never replays success feedback")
	var baseline = ui.rules.view(0); baseline.event_mode = "baseline"; baseline.events = []
	ui._accept_state(baseline); await _drain_fx()
	_check(ui.battle_fx.played_events == count and not ui.battle_fx.is_busy(),"reconnect baseline clears effects without replay")
	_reset(0,["infantry"])
	count = ui.battle_fx.played_events
	_drag(_hand_uid(),ui._slot_rect(2,0).get_center()); await _drain_fx()
	_check(ui.battle_fx.played_events == count,"rejected deployment emits no audiovisual success")
	ui.settings.animations = false
	var sounds = ui.battle_fx.sound_count; var visual = ui.battle_fx.visual_count
	_drag(_hand_uid(),ui._slot_rect(3,0).get_center()); await _drain_fx()
	_check(ui.battle_fx.sound_count > sounds and ui.battle_fx.visual_count == visual,"sound remains enabled with animation disabled")
	_reset(0,["infantry"]); ui.settings.animations = true; ui.settings.sound = false
	sounds = ui.battle_fx.sound_count; visual = ui.battle_fx.visual_count
	_drag(_hand_uid(),ui._slot_rect(3,0).get_center()); await _drain_fx()
	_check(ui.battle_fx.sound_count == sounds and ui.battle_fx.visual_count > visual,"animation remains enabled with sound disabled")
	ui.settings.animations = false; ui.settings.sound = false
	_check(ui.battle_fx.PROFILES.size() == ui.cards.size(),"all twenty-six cards have explicit audiovisual profiles")
	for key in ui.cards: _check(ui.battle_fx.PROFILES.has(key),"card profile exists: "+key)
	var next_match = Rules.new([],[],777)
	next_match.phase = "battle"; next_match.mulligan_done = [true,true]; next_match.turn = 0
	next_match.players[0].mana = 10
	next_match.players[0].hand = [{"uid":400,"card":"infantry"}]; next_match.next_id = 401
	next_match.act(0,{"type":"play","hand":400,"lane":3,"slot":6})
	count = ui.battle_fx.played_events
	ui.rules = next_match; ui._accept_state(next_match.view(0)); await _drain_fx()
	_check(ui.battle_fx.played_events > count,"new match first live action is not lost to old revision cursor")
	var burst = next_match.view(0); burst.revision += 1; burst.events = []
	var position = next_match.position(0,next_match.players[0].board[0])
	for i in range(80): burst.events.append({"match_id":burst.match_id,"revision":burst.revision,"index":i,"kind":"damage","owner":0,"card":"arrows","source":position,"target":position,"amount":1})
	count = ui.battle_fx.played_events
	var started = Time.get_ticks_msec()
	ui._accept_state(burst); await _drain_fx()
	_check(ui.battle_fx.played_events == count+80 and Time.get_ticks_msec()-started < 1000,"eighty-effect chain remains complete and under one second")
	ui.settings.animations = true; ui.battle_fx.clear()
	burst.revision += 1
	burst.events = [{"match_id":burst.match_id,"revision":burst.revision,"index":0,"kind":"spell","owner":0,"card":"arrows","source":{"base":true,"owner":0},"lane":2,"targets":[{"uid":900,"owner":1,"card":"infantry","lane":2,"slot":0},{"uid":901,"owner":1,"card":"infantry","lane":2,"slot":4}]}]
	ui._accept_state(burst)
	_check(ui.battle_fx.visuals.size() == 2 and ui.battle_fx.visuals[0].to == ui._slot_rect(2,0).get_center() and ui.battle_fx.visuals[1].to == ui._slot_rect(2,4).get_center(),"lane spell preserves separate published target positions")
	await _drain_fx(); ui.battle_fx.clear()
	burst.revision += 1; burst.events[0].revision = burst.revision; burst.events[0].targets = []
	ui._accept_state(burst)
	_check(ui.battle_fx.visuals.size() == 1 and ui.battle_fx.visuals[0].to == ui.LANES[ui._row_for_lane(2)].get_center(),"empty lane spell still shows its selected line")
	await _drain_fx(); ui.settings.animations = false

	ui.deck = ui.rules.default_deck.duplicate()
	ui._collection()
	await process_frame
	var scroll: ScrollContainer
	for child in ui.widgets.get_children():
		if child is ScrollContainer:
			scroll = child
	var grid = scroll.get_child(0)
	_check(grid.get_child_count() == 26, "collection presents all twenty-six cards")
	var distinct: Dictionary = {}
	for holder in grid.get_children():
		var card = holder.get_child(0)
		_check(card.get_script() == Card and card.card_mode == "detail", "collection entry uses the real detailed card component")
		distinct[card.get_card_key()] = true
	_check(distinct.size() == 26 and ui._deck_size() == 30, "collection cards are distinct and default deck has thirty cards")
	var scout_holder = grid.get_child(0)
	var scout_row = scout_holder.get_child(1)
	var plus = scout_row.get_child(2)
	var minus = scout_row.get_child(0)
	plus.pressed.emit()
	_check(ui._deck_size() == 30 and ui.collection_counts.scout == 2, "full deck refuses an additional card")
	minus.pressed.emit()
	_check(ui._deck_size() == 29, "remove button reduces deck size")
	var original_deck = ui.deck.duplicate()
	ui._save_collection()
	_check(ui.screen == "collection" and ui.deck == original_deck, "incomplete deck cannot be saved and does not alter the active deck")
	plus.pressed.emit()
	_check(ui._deck_size() == 30 and ui.collection_counts.scout == 2, "add button fills the thirtieth slot")
	# Create space with another entry, then verify the same-name cap separately.
	grid.get_child(1).get_child(1).get_child(0).pressed.emit()
	plus.pressed.emit()
	_check(ui._deck_size() == 29 and ui.collection_counts.scout == 2, "same-name two-copy cap holds even with an empty deck slot")

	ui.net.close()
	ui.queue_free()
	await process_frame
	print("SCENE_UI_TEST: %d checks; %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
