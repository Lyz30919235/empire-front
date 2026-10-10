extends Node
## Exercises this game's own controls and captures only its own viewport.
var checks = 0
var failures: Array = []
var app
var output_dir: String

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message); push_error(message)

func wait_view() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	if app != null and app.battle_fx != null:
		for i in range(80):
			if not app.battle_fx.is_busy(): break
			await get_tree().create_timer(0.025).timeout
		check(not app.battle_fx.is_busy(),"bounded audiovisual batch completes")

func capture(name: String) -> void:
	print("CAPTURE ",name)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image_value = get_viewport().get_texture().get_image()
	check(not image_value.is_empty(),"viewport image exists: "+name)
	check(image_value.save_png(output_dir.path_join(name)) == OK,"save viewport: "+name)

func mouse(button: int, down: bool, pos: Vector2) -> void:
	var event = InputEventMouseButton.new()
	event.button_index = button; event.pressed = down; event.position = get_viewport().get_final_transform()*pos
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func drag(from: Vector2, to: Vector2) -> void:
	mouse(MOUSE_BUTTON_LEFT,true,from)
	await get_tree().process_frame
	var event = InputEventMouseMotion.new(); event.position = get_viewport().get_final_transform()*to; event.relative = get_viewport().get_final_transform().basis_xform(to-from); event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	await get_tree().process_frame
	mouse(MOUSE_BUTTON_LEFT,false,to)
	await wait_view()

func aim(from: Vector2, to: Vector2) -> void:
	mouse(MOUSE_BUTTON_LEFT,true,from)
	var event = InputEventMouseMotion.new()
	event.position = get_viewport().get_final_transform()*to
	event.global_position = event.position; event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event); Input.flush_buffered_events()
	await get_tree().process_frame

func click(pos: Vector2) -> void:
	print("CLICK ",pos)
	var motion = InputEventMouseMotion.new()
	motion.position = get_viewport().get_final_transform()*pos
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	mouse(MOUSE_BUTTON_LEFT,true,pos)
	mouse(MOUSE_BUTTON_LEFT,false,pos)
	await wait_view()

func run(board, report_path: String) -> void:
	app = board
	app.set_process(false)
	app.settings.fullscreen = false; app.settings.animations = true; app.settings.sound = true
	Input.use_accumulated_input = false
	output_dir = report_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(output_dir)
	await wait_view()
	check(app.screen == "menu","main menu")
	await capture("Godot主菜单预览.png")
	await click(Vector2(1210,319))
	check(app.screen == "battle","real menu button starts solo")
	print("SOLO_SCREEN ",app.screen)
	if app.screen != "battle": get_tree().quit(1); return
	app.set_process(false)
	await wait_view()
	check(app.state.phase == "mulligan","opening phase")
	check(app.card_nodes.size() == 4,"four opening cards")
	var uid = int(app.state.players[0].hand[0].uid)
	var pos = app.card_nodes[uid].position+Vector2(85,100)
	mouse(MOUSE_BUTTON_LEFT,true,pos); mouse(MOUSE_BUTTON_LEFT,false,pos)
	await wait_view()
	check(uid in app.marked,"pointer selects replacement")
	await capture("Godot开局换牌预览.png")
	await click(Vector2(720,711))
	await wait_view()
	check(app.state.phase == "battle","mulligan starts battle")
	check(app.rules.players[0].hand.filter(func(h): return int(h.uid) == uid).is_empty(),"marked card replaced")
	app.rules.players[0].mana = 10; app.rules.players[0].max_mana = 10
	app.rules.players[0].hand = [{"uid":1000,"card":"light_cavalry"},{"uid":1001,"card":"fireball"},{"uid":1002,"card":"heal"},{"uid":1003,"card":"arrows"},{"uid":1004,"card":"heavy_tank"}]
	app.rules.next_id = 2000
	app._accept_state(app.rules.view(0)); await wait_view()
	var initial_mana = int(app.rules.players[0].mana)
	var initial_effects = app.battle_fx.played_events
	var hand_position = app.card_nodes[1000].position+Vector2(80,100)
	await drag(hand_position,Vector2(1100,452))
	check(app.rules.players[0].mana == initial_mana and app.rules.players[0].board.is_empty(),"illegal front deployment changes nothing")
	check(app.battle_fx.played_events == initial_effects,"rejected action produces no audiovisual events")
	hand_position = app.card_nodes[1000].position+Vector2(80,100)
	await drag(hand_position,Vector2(1100,572))
	check(app.rules.players[0].board.size() == 1,"drag deploys at rear")
	if app.rules.players[0].board.is_empty():
		print("PROBE SOURCE STATE: ",app.status," viewport ",get_viewport().get_final_transform())
		get_tree().quit(1)
		return
	var unit_value = app.rules.players[0].board[0]
	check(int(unit_value.lane) == 3,"rear lane 3")
	check(int(unit_value.actions) == 2,"swift assault deploys with two actions")
	var unit_position = app.unit_rects[int(unit_value.uid)].rect.get_center()
	await drag(unit_position,Vector2(1100,330))
	check(int(unit_value.lane) == 3,"cannot skip a lane")
	unit_position = app.unit_rects[int(unit_value.uid)].rect.get_center()
	await aim(unit_position,app._slot_rect(2,2).get_center())
	check(app.aiming and app.ghost == null,"blue movement uses arrow without card ghost")
	await capture("Godot移动箭头预览.png")
	mouse(MOUSE_BUTTON_LEFT,false,app._slot_rect(2,2).get_center()); await wait_view()
	check(int(unit_value.lane) == 2,"adjacent movement")
	check(int(unit_value.slot) == 2,"movement chooses precise public slot")
	check(int(unit_value.actions) == 1,"swift movement leaves one action")
	var enemy = app.rules.summon(1,"infantry",1)
	app._accept_state(app.rules.view(0)); await wait_view()
	unit_position = app.unit_rects[int(unit_value.uid)].rect.get_center()
	var enemy_position = app.unit_rects[int(enemy.uid)].rect.get_center()
	var original_position = app.card_nodes[int(unit_value.uid)].position
	await aim(unit_position,enemy_position)
	check(app.aiming and app.card_nodes[int(unit_value.uid)].position == original_position and app.card_nodes[int(unit_value.uid)].modulate.a == 1.0,"red attack arrow leaves card in place and opaque")
	await capture("Godot攻击箭头预览.png")
	mouse(MOUSE_BUTTON_LEFT,false,enemy_position); await wait_view()
	check(int(enemy.hp) == 3,"drag attack resolves damage")
	check(int(unit_value.actions) == 0,"swift move and attack exhaust two actions")
	app.rules.players[0].mana = 10
	app._accept_state(app.rules.view(0)); await wait_view()
	await drag(app.card_nodes[1001].position+Vector2(80,100),enemy_position)
	check(app.rules.players[1].board.is_empty(),"targeted spell removes enemy")
	check(app.battle_fx.event_counts.get("death",0) > 0 and app.battle_fx.event_counts.get("damage",0) > 0,"lethal spell shows hit and captured death positions")
	check(app.battle_fx.sound_count > 0 and app.battle_fx.visual_count > 0,"real-window probe plays battle sounds and effects")
	var played = app.battle_fx.played_events
	app._accept_state(app.rules.view(0)); await wait_view()
	check(app.battle_fx.played_events == played,"duplicate state does not replay effects")
	# Exercise the actual factory button, including its rear-only placement.
	app.rules.players[0].board.clear()
	var factory = app.rules.summon(0,"factory",3)
	check(int(factory.actions) == 0,"ordinary building sleeps on deployment")
	app.rules.start_turn(0,false)
	check(int(factory.actions) == 1,"ordinary building refreshes one action")
	app.rules.players[0].mana = 10
	app._accept_state(app.rules.view(0)); await wait_view()
	await click(app.unit_rects[int(factory.uid)].rect.get_center())
	check(not app.hud.skill.disabled,"factory button enabled")
	await click(Vector2(1430,545))
	check(app.rules.players[0].board.filter(func(u): return u.card == "light_tank" and u.lane == 3).size() == 1,"actual button manufactures at rear")
	check(int(factory.actions) == 0,"manufacture exhausts ordinary one action")
	# A curated battle preview uses the real engine and real card nodes.
	app.rules.players[0].board.clear(); app.rules.players[1].board.clear()
	for key in ["heavy_tank","scout","factory"]: app.rules.summon(0,key,3)
	for slot in [1,2,3]: app.rules.summon(0,"infantry",3,false,slot)
	app.rules.summon(1,"archer",3,false,4)
	for key in ["light_cavalry","archer"]: app.rules.summon(0,key,2)
	for key in ["heavy_cavalry","infantry"]: app.rules.summon(1,key,1)
	for key in ["artillery","tower"]: app.rules.summon(1,key,0)
	for owner in range(2):
		for u in app.rules.players[owner].board: u.actions = 2 if "迅捷" in u.tags else 1
	app.rules.players[0].mana = 8; app.rules.players[0].max_mana = 10
	app.rules.players[0].hand = []
	for key in ["light_tank","banner","arrows","heal","plane","merchant"]:
		app.rules.players[0].hand.append({"uid":app.rules.next_id,"card":key}); app.rules.next_id += 1
	app.settings.animations = true
	app._accept_state(app.rules.view(0)); await wait_view()
	for card_node in app.card_nodes.values(): check(card_node.scale.is_equal_approx(Vector2.ONE),"entry animation settles")
	var rear_count = 0
	for info in app.unit_rects.values():
		if int(info.data.lane) == 3: rear_count += 1; check(info.rect.end.x <= 1255,"seven-slot rear fits board")
	check(rear_count == 7,"battle preview contains all seven rear slots with mixed owners")
	app._click(app.unit_rects[int(app.rules.players[0].board[0].uid)].rect.get_center())
	app.toast.text = ""
	await capture("Godot战场预览.png")
	for dimensions in [Vector2i(1120,700),Vector2i(1600,1000),Vector2i(1920,1080)]:
		get_window().size = dimensions
		await wait_view()
		if dimensions == Vector2i(1120,700): await capture("Godot最小窗口七槽预览.png")
		check(app._target(Vector2(1100,572)).get("lane") == 3,"logical lane stable on resize %s" % dimensions)
		var source_uid = int(app.rules.players[0].board[0].uid)
		await click(app.unit_rects[source_uid].rect.get_center())
		check(int(app.selected.get("uid",-1)) == source_uid,"real pointer selects unit on resize %s" % dimensions)
		var escape = InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
		Input.parse_input_event(escape); Input.flush_buffered_events()
		check(app.selected.is_empty(),"escape cancels on resize %s" % dimensions)
	get_window().size = Vector2i(1440,900)
	app.deck = app.rules.default_deck.duplicate()
	app._collection(); await wait_view()
	check(app._deck_size() == 30,"deck has 30 cards")
	check(app.cards.size() == 26,"26 definitions")
	var collection_scroll
	for child in app.widgets.get_children():
		if child is ScrollContainer: collection_scroll = child
	var first_row = collection_scroll.get_child(0).get_child(0).get_child(1)
	await click(first_row.get_child(0).get_global_rect().get_center())
	check(app._deck_size() == 29,"real minus button removes one")
	await click(first_row.get_child(2).get_global_rect().get_center())
	check(app._deck_size() == 30,"real plus button restores one")
	await capture("Godot图鉴预览.png")
	app._settings_menu(); await wait_view()
	await capture("Godot设置预览.png")
	app._menu(); await wait_view()
	var file = FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"game_version":ProjectSettings.get_setting("application/config/version"),"executable_sha256":FileAccess.get_sha256(OS.get_executable_path()),"cards":app.cards.size(),"renderer":DisplayServer.get_name(),"effects":{"played":app.battle_fx.played_events,"sound_count":app.battle_fx.sound_count,"visual_count":app.battle_fx.visual_count,"kinds":app.battle_fx.event_counts},"passed":failures.is_empty()},"  "))
	print("UI_PROBE ",checks," checks; failures: ",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
