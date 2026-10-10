extends Control
## Input belongs to this board. Rules and networking never depend on UI nodes.
## Primary touch uses Godot mouse emulation, preventing double submissions.
const Rules = preload("res://scripts/engine.gd")
const Network = preload("res://scripts/network.gd")
const Card = preload("res://scripts/card_view.gd")
const BattleFx = preload("res://scripts/battle_fx.gd")
const GOLD = Color("bda36c")
const PAPER = Color("ece0c2")
const BLUE = Color("66b5ba")
const RED = Color("d87e6b")
const ENEMY_BASE = Rect2(360,78,590,66)
const OWN_BASE = Rect2(360,648,590,70)
const LANES = [Rect2(35,160,1220,112),Rect2(35,280,1220,112),Rect2(35,400,1220,112),Rect2(35,520,1220,112)]
var rules = Rules.new()
var preview = Rules.new()
var net = Network.new()
var cards: Dictionary
var deck: Array
var settings = {"name":"指挥官","ip":"127.0.0.1","port":47653,"fullscreen":false,"animations":true,"sound":true}
var font = SystemFont.new()
var panel_styles: Dictionary = {}
var map_lines: Array = []
var screen = "menu"
var state: Dictionary = {}
var multiplayer_game = false
var widgets = Control.new()
var pieces = Control.new()
var fx = Control.new()
var card_nodes: Dictionary = {}
var card_tweens: Dictionary = {}
var homes: Dictionary = {}
var unit_rects: Dictionary = {}
var selected: Dictionary = {}
var marked: Array = []
var skill_mode = ""
var command_ally = -1
var press: Dictionary = {}
var press_active = false
var press_position = Vector2.ZERO
var pointer = Vector2.ZERO
var dragging = false
var aiming = false
var ghost = null
var hovered = -1
var action_list: Array = []
var action_keys: Dictionary = {}
var playable_uids: Dictionary = {}
var hud: Dictionary = {}
var detail = null
var toast: Label
var status = ""
var ai_clock = 0.0
var action_busy = 0.0
var battle_fx
var fields: Dictionary = {}
var collection_counts: Dictionary = {}
var collection_label: Label

func _ready() -> void:
	font.font_names = PackedStringArray(["Microsoft YaHei","Noto Sans CJK SC","SimHei"])
	for i in range(9):
		var points = PackedVector2Array()
		for j in range(41): points.append(Vector2(j*40,440+sin(j*0.23+i*0.17)*150+i*29))
		map_lines.append(points)
	var theme_value = Theme.new()
	theme_value.default_font = font
	theme_value.default_font_size = 19
	theme = theme_value
	cards = rules.cards
	deck = rules.default_deck.duplicate()
	_load_settings()
	for layer in [widgets,pieces,fx]:
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(layer)
	pieces.z_index = 10
	fx.z_index = 80
	add_child(net)
	net.state_changed.connect(_network_state)
	net.status_changed.connect(_message)
	battle_fx = BattleFx.new(); battle_fx.board = self; battle_fx.z_index = 70
	add_child(battle_fx)
	toast = _label("",Vector2(140,725),Vector2(1120,38),20,PAPER,fx)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu()
	if settings.fullscreen: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	var args = OS.get_cmdline_user_args()
	if "--ui-probe" in args:
		var index = args.find("--ui-probe")
		var path = args[index+1] if index+1 < args.size() else "user://ui-probe.json"
		var probe = preload("res://scripts/ui_probe.gd").new()
		add_child(probe)
		probe.run.call_deferred(self,path)

func _load_settings() -> void:
	var path = "user://settings.json"
	if not FileAccess.file_exists(path):
		var home_path = OS.get_environment("USERPROFILE")
		if home_path.is_empty(): home_path = OS.get_environment("HOME")
		if not home_path.is_empty(): path = home_path.path_join(".empire_front/settings.json")
	if FileAccess.file_exists(path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			for key in settings:
				if data.has(key) and typeof(data[key]) == typeof(settings[key]): settings[key] = data[key]
			if data.get("port") is float: settings.port = int(data.port)
			if rules.validate_deck(data.get("deck")).is_empty(): deck = data.deck.duplicate()
	settings.port = clampi(int(settings.port),1,65535)

func _save_settings() -> void:
	var data = settings.duplicate()
	data.deck = deck
	var file = FileAccess.open("user://settings.json",FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(data,"  "))

func _style(fill: Color, border: Color = GOLD) -> StyleBoxFlat:
	var key = "%d/%d" % [fill.to_rgba32(),border.to_rgba32()]
	if panel_styles.has(key): return panel_styles[key]
	var box = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	box.content_margin_left = 12
	box.content_margin_right = 12
	panel_styles[key] = box
	return box

func _label(text_value: String, pos: Vector2, dimensions: Vector2, pixels: int = 20, color: Color = PAPER, parent = null) -> Label:
	var node = Label.new()
	node.text = text_value
	node.position = pos
	node.size = dimensions
	node.add_theme_font_size_override("font_size",pixels)
	node.add_theme_color_override("font_color",color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else widgets).add_child(node)
	return node

func _button(text_value: String, rect: Rect2, callback: Callable, parent = null) -> Button:
	var node = Button.new()
	node.text = text_value
	node.position = rect.position
	node.size = rect.size
	node.add_theme_stylebox_override("normal",_style(Color("25332f")))
	node.add_theme_stylebox_override("hover",_style(Color("3e5147"),PAPER))
	node.add_theme_stylebox_override("pressed",_style(Color("587265"),BLUE))
	node.add_theme_stylebox_override("disabled",_style(Color("252b28"),Color("51584c")))
	node.add_theme_color_override("font_color",PAPER)
	node.pressed.connect(callback)
	(parent if parent != null else widgets).add_child(node)
	return node

func _field(key: String, value: String, rect: Rect2, secret = false) -> LineEdit:
	var node = LineEdit.new()
	node.text = value
	node.secret = secret
	node.position = rect.position
	node.size = rect.size
	node.max_length = 64 if secret else 80
	node.add_theme_stylebox_override("normal",_style(Color("172420"),Color("687b65")))
	node.add_theme_color_override("font_color",PAPER)
	widgets.add_child(node)
	fields[key] = node
	return node

func _clear_screen(next_screen: String) -> void:
	_cancel_drag()
	if battle_fx != null: battle_fx.clear()
	for tween_value in card_tweens.values():
		if tween_value.is_valid(): tween_value.kill()
	card_tweens.clear()
	screen = next_screen
	for layer in [widgets,pieces]:
		for child in layer.get_children():
			layer.remove_child(child)
			child.queue_free()
	card_nodes.clear(); homes.clear(); unit_rects.clear(); hud.clear(); fields.clear()
	detail = null; selected = {}; skill_mode = ""; hovered = -1
	toast.text = ""
	toast.position = Vector2(140,725)
	queue_redraw()

func _menu() -> void:
	_clear_screen("menu")
	_label("帝国",Vector2(180,170),Vector2(700,105),88)
	_label("四 线 战 令",Vector2(187,282),Vector2(720,65),44,GOLD)
	_label("IMPERIAL FRONT  /  GODOT EDITION",Vector2(190,365),Vector2(790,45),22,BLUE)
	_label("四线推进 · 德系二次元卡牌 · 双人战役",Vector2(190,430),Vector2(850,45),24)
	_label("部署于后方，逐线向前。每一次行动都改变战局。",Vector2(190,494),Vector2(870,55),21,Color("b4baa1"))
	_button("单人练习",Rect2(1040,285,340,68),_solo)
	_button("双人联机",Rect2(1040,373,340,68),_connection_menu)
	_button("图鉴与组牌",Rect2(1040,461,340,68),_collection)
	_button("设置与规则",Rect2(1040,549,340,68),_settings_menu)
	_button("退出",Rect2(1040,662,340,54),func(): get_tree().quit())
	_label("26 张完整插画  /  30 张构筑牌组  /  原生 GDScript",Vector2(190,900),Vector2(1000,35),18,GOLD)
	var art = Card.new()
	art.position = Vector2(560,588); art.size = Vector2(260,300); art.rotation = -0.08
	art.configure(cards.heavy_tank,{},"detail")
	pieces.add_child(art)

func _connection_menu() -> void:
	_clear_screen("connect")
	_label("双人战役",Vector2(180,135),Vector2(800,70),48)
	_label("一人创建房间，另一人输入主机 IP。双方使用相同的 2.1 版游戏。",Vector2(180,225),Vector2(1260,50),22,GOLD)
	for i in range(4): _label(["指挥官名称","主机 IP","TCP 端口","房间口令（可留空）"][i],Vector2(220,340+i*80),Vector2(310,50))
	_field("name",str(settings.name),Rect2(530,340,670,50)).max_length = 18
	_field("ip",str(settings.ip),Rect2(530,420,670,50))
	_field("port",str(settings.port),Rect2(530,500,670,50))
	_field("password","",Rect2(530,580,670,50),true)
	_button("创建房间",Rect2(530,700,310,65),func(): _connect_game(true))
	_button("加入房间",Rect2(890,700,310,65),func(): _connect_game(false))
	_button("返回",Rect2(180,860,220,52),_menu)
	toast.position.y = 795

func _connect_game(host_value: bool) -> void:
	var port_text = fields.port.text.strip_edges()
	if not port_text.is_valid_int() or int(port_text) < 1 or int(port_text) > 65535: _message("端口必须是 1 至 65535 的整数。"); return
	settings.name = fields.name.text.strip_edges().left(18)
	if settings.name.is_empty(): settings.name = "指挥官"
	settings.ip = fields.ip.text.strip_edges(); settings.port = int(port_text)
	var password = fields.password.text
	_save_settings()
	multiplayer_game = true
	marked.clear()
	_lobby()
	var error = net.host(settings.port,password,settings.name,deck) if host_value else net.join(settings.ip,settings.port,password,settings.name,deck)
	if not error.is_empty(): multiplayer_game = false; _connection_menu(); _message(error)

func _lobby() -> void:
	_clear_screen("lobby")
	_label("战役集结",Vector2(180,135),Vector2(950,75),48)
	_label("双方准备后进入开局换牌。掉线时保留席位并暂停战斗。",Vector2(180,235),Vector2(1250,45),22,GOLD)
	hud.lobby = _label("等待另一位指挥官…",Vector2(250,355),Vector2(1100,240),28)
	_label("房间 TCP 端口：%d" % settings.port,Vector2(250,580),Vector2(1100,42),20,BLUE)
	_button("准备 / 再战",Rect2(580,650,420,65),func(): net.ready_up())
	_button("重新连接",Rect2(890,860,240,52),func(): net.retry())
	_button("返回主菜单",Rect2(180,860,240,52),_leave)
	toast.position.y = 760
	_update_lobby(net.lobby)

func _update_lobby(slots: Array) -> void:
	if not hud.has("lobby"): return
	var lines = []
	for i in range(2):
		var slot = slots[i] if i < slots.size() else null
		lines.append("席位 %d     %s" % [i+1,"等待加入" if slot == null else "%s     %s     %s" % [slot.name,"已准备" if slot.ready else "未准备","在线" if slot.online else "等待重连"]])
	hud.lobby.text = "\n\n".join(lines)

func _network_state(new_state: Dictionary, slots: Array) -> void:
	if not multiplayer_game: return
	if new_state.is_empty():
		if screen != "lobby": _lobby()
		_update_lobby(slots)
		return
	if screen != "battle": _battle()
	_accept_state(new_state)

func _solo() -> void:
	net.close(); multiplayer_game = false
	rules = Rules.new([deck,rules.default_deck],[str(settings.name),"训练指挥官"])
	rules.act(1,rules.ai_action(1))
	marked.clear()
	_battle()
	_accept_state(rules.view(0))

func _leave() -> void:
	net.close(); multiplayer_game = false; state = {}
	_menu()

func _battle() -> void:
	_clear_screen("battle")
	hud.enemy = _label("",Vector2(378,91),Vector2(556,47),22)
	hud.own = _label("",Vector2(378,663),Vector2(556,45),22)
	hud.turn = _label("",Vector2(42,16),Vector2(1050,46),25)
	hud.resources = _label("",Vector2(45,665),Vector2(300,50),23,BLUE)
	hud.enemy_hand = _label("",Vector2(1000,89),Vector2(250,45),19,GOLD)
	hud.hand = _label("",Vector2(44,725),Vector2(240,32),18,GOLD)
	hud.tip = _label("",Vector2(1290,402),Vector2(284,110),18)
	hud.tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.skill = _button("发动技能",Rect2(1290,520,280,52),_begin_skill)
	hud.medium = _button("制造中型坦克 · 3 点",Rect2(1290,582,280,48),func(): _manufacture("medium_tank"))
	hud.log = _label("",Vector2(1290,650),Vector2(280,140),17,Color("b9bca4"))
	hud.log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.end = _button("结束回合",Rect2(1290,850,280,65),func(): _send({"type":"end"}))
	hud.rematch = _button("再战",Rect2(1290,790,280,48),func():
		if multiplayer_game: net.ready_up()
		else: _solo())
	hud.retry = _button("重新连接",Rect2(1290,790,280,48),func(): net.retry())
	hud.concede = _button("认输 / 撤退",Rect2(1290,936,280,42),func(): _send({"type":"concede"}))
	hud.confirm = _button("确认换牌",Rect2(530,680,380,62),_confirm_mulligan)
	hud.keep = _button("全部保留",Rect2(965,688,240,48),func(): marked.clear(); _confirm_mulligan())
	_button("返回 / 离开房间",Rect2(1300,22,270,38),_leave)
	detail = Card.new(); detail.position = Vector2(1290,90); detail.size = Vector2(280,295); detail.visible = false
	pieces.add_child(detail)

func _accept_state(new_state: Dictionary) -> void:
	var same_state = not state.is_empty() and state.get("match_id") == new_state.get("match_id") and state.get("revision") == new_state.get("revision") and state.get("players") == new_state.get("players") and state.get("phase") == new_state.get("phase") and state.get("turn") == new_state.get("turn") and state.get("winner") == new_state.get("winner") and state.get("mulligan_done") == new_state.get("mulligan_done")
	if same_state and new_state.get("event_mode","live") != "baseline":
		if multiplayer_game and not _network_available(): _cancel_drag()
		_refresh_hud(); battle_fx.consume(new_state,settings); return
	state = new_state.duplicate(true)
	preview.players = state.players.duplicate(true); preview.phase = state.phase
	preview.mulligan_done = state.mulligan_done.duplicate(); preview.turn = int(state.turn); preview.winner = state.winner
	action_list = preview.legal_actions(int(state.you))
	action_keys.clear(); playable_uids.clear()
	for action in action_list:
		action_keys[_action_key(action)] = true
		playable_uids[int(action.get("hand",action.get("unit",-1)))] = true
	_cancel_drag()
	_sync_cards(); _refresh_hud()
	battle_fx.consume(state,settings)
	queue_redraw()

func _network_available() -> bool:
	if not net.online: return false
	for slot in net.lobby:
		if slot == null or not slot.online: return false
	return true

func _is_turn() -> bool:
	return not state.is_empty() and state.phase == "battle" and state.winner == null and state.turn == state.you and (not multiplayer_game or _network_available())

func _refresh_hud() -> void:
	var p = int(state.you)
	var me = state.players[p]; var enemy = state.players[1-p]
	hud.enemy.text = "%s     基地 %d / 30" % [enemy.name,enemy.hp]
	hud.own.text = "%s     基地 %d / 30" % [me.name,me.hp]
	hud.resources.text = "召唤点  %d / %d" % [me.mana,me.max_mana]
	hud.enemy_hand.text = "敌手牌 %d · 牌堆 %d" % [enemy.hand_count,enemy.deck_count]
	hud.hand.text = "手牌 %d · 牌堆 %d" % [me.hand_count,me.deck_count]
	hud.end.disabled = not _is_turn(); hud.end.text = "结束回合" if _is_turn() else "等待对手"
	hud.confirm.visible = state.phase == "mulligan" and state.winner == null; hud.keep.visible = hud.confirm.visible
	hud.confirm.disabled = bool(state.mulligan_done[p]) or (multiplayer_game and not _network_available()); hud.keep.disabled = hud.confirm.disabled
	hud.confirm.text = "等待对方确认…" if state.mulligan_done[p] else "替换 %d 张并确认" % marked.size()
	hud.rematch.visible = state.winner != null
	hud.retry.visible = multiplayer_game and not _network_available() and state.winner == null
	hud.retry.disabled = net.is_host
	hud.concede.disabled = state.winner != null or (multiplayer_game and not _network_available())
	var title = "第 %d 轮  /  %s的回合" % [state.round,state.players[int(state.turn)].name]
	if state.phase == "mulligan": title = "开局整备  /  点击任意初始卡牌，再确认替换"
	if multiplayer_game and not _network_available(): title = "连接中断：战役暂停，等待自动重连"
	if state.winner != null: title = "战役结束  /  " + ("平局" if state.winner == -1 else ("你获得胜利" if state.winner == p else "基地失守"))
	hud.turn.text = title
	hud.log.text = "战 报\n\n" + "\n".join(state.log.slice(maxi(0,state.log.size()-3)))
	_refresh_selection()

func _global_lane(row: int) -> int:
	return row if int(state.get("you",0)) == 0 else 3-row

func _row_for_lane(lane_value: int) -> int:
	return lane_value if int(state.get("you",0)) == 0 else 3-lane_value

func _slot_rect(lane_value: int, slot: int) -> Rect2:
	var column = slot+1 if slot < 5 else (0 if slot == 5 else 6)
	return Rect2(166+column*157,LANES[_row_for_lane(lane_value)].position.y+7,147,98)

func _lane_slots(lane_value: int) -> Array:
	return [0,1,2,3,4,5,6] if lane_value in [0,3] else [0,1,2,3,4]

func _sync_cards() -> void:
	var alive = {}; unit_rects.clear()
	var p = int(state.you); var hand = state.players[p].hand
	var mulligan = state.phase == "mulligan" and state.winner == null
	for row in range(4):
		var lane_value = _global_lane(row); var units = []
		for owner in range(2):
			for u in state.players[owner].board:
				if int(u.lane) == lane_value: units.append([owner,u])
		for item in units:
			var u = item[1]
			var rect = _slot_rect(lane_value,int(u.get("slot",0)))
			unit_rects[int(u.uid)] = {"rect":rect,"owner":item[0],"data":u}
			_put_card(u,"unit",rect,0.0,item[0] == p,alive)
	var step = minf(173,1040.0/maxi(1,hand.size()-1)); var width = (hand.size()-1)*step+166
	for i in range(hand.size()):
		var h = hand[i]; var angle = 0.0 if mulligan else (i-(hand.size()-1)/2.0)*0.018
		var pos = Vector2(645-(hand.size()*245-35)/2+i*245,332) if mulligan else Vector2(645-width/2+i*step,760+abs(i-(hand.size()-1)/2.0)*1.2)
		_put_card(h,"mulligan" if mulligan else "hand",Rect2(pos,Vector2(210,300) if mulligan else Vector2(166,225)),angle,true,alive)
	for uid in card_nodes.keys():
		if not alive.has(uid):
			if card_tweens.has(uid) and card_tweens[uid].is_valid(): card_tweens[uid].kill()
			card_tweens.erase(uid)
			var node = card_nodes[uid]; card_nodes.erase(uid); homes.erase(uid)
			if settings.animations:
				var t = node.create_tween().set_parallel()
				t.tween_property(node,"modulate:a",0.0,0.18); t.tween_property(node,"scale",Vector2(0.7,0.7),0.18)
				t.chain().tween_callback(node.queue_free)
			else: node.queue_free()
	if selected.has("uid") and not alive.has(int(selected.uid)): selected = {}; skill_mode = ""
	_update_visuals()

func _put_card(data: Dictionary, mode: String, rect: Rect2, angle: float, friendly: bool, alive: Dictionary) -> void:
	var uid = int(data.uid); alive[uid] = true
	var fresh = not card_nodes.has(uid)
	var node = Card.new() if fresh else card_nodes[uid]
	if fresh:
		pieces.add_child(node); card_nodes[uid] = node
		node.position = rect.position+Vector2(0,20); node.scale = Vector2(0.94,0.94)
	node.configure(cards[data.card],data,mode,friendly)
	node.size = rect.size; node.pivot_offset = rect.size/2
	node.z_index = 2 if mode == "unit" else 4+int(rect.position.x/180)
	homes[uid] = {"position":rect.position,"rotation":angle,"z":node.z_index}
	if card_tweens.has(uid) and card_tweens[uid].is_valid(): card_tweens[uid].kill()
	if settings.animations:
		var t = node.create_tween().set_parallel()
		card_tweens[uid] = t
		t.tween_property(node,"position",rect.position,0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(node,"rotation",angle,0.22); t.tween_property(node,"scale",Vector2.ONE,0.22)
	else: node.position = rect.position; node.rotation = angle; node.scale = Vector2.ONE

func _update_visuals() -> void:
	for uid in card_nodes:
		card_nodes[uid].set_visual(int(selected.get("uid",-1)) == uid,uid in marked,playable_uids.has(uid))

func _inspect(data: Dictionary) -> void:
	if detail != null:
		detail.configure(cards[data.card],data,"detail",not unit_rects.has(int(data.uid)) or unit_rects[int(data.uid)].owner == state.you)
		detail.visible = true

func _refresh_selection() -> void:
	var uid = int(selected.get("uid",-1)); var data = unit_rects.get(uid,{}).get("data",{})
	var key = cards.get(data.get("card",""),{}).get("skill","")
	hud.skill.disabled = not _is_turn() or key.is_empty() or not _has_skill(uid)
	hud.skill.text = "制造轻型坦克 · 2 点" if key == "manufacture" else "发动技能"
	hud.medium.visible = key == "manufacture"; hud.medium.disabled = not _is_turn() or not _has_skill(uid,"medium_tank")
	var tip = "手牌拖至己方后方空槽部署。按住单位拉箭头：红色攻击，蓝色移至相邻空槽；也可选中后点击目标。"
	if not skill_mode.is_empty(): tip = "选择目标战线" if skill_mode in ["charge","airstrike"] else ("选择另一名友军，再选择攻击目标" if command_ally == -1 else "选择敌军或敌方基地")
	elif not data.is_empty(): tip = "行动 %d  /  冷却 %d\n%s" % [data.actions,data.cooldown,cards[data.card].text]
	hud.tip.text = tip+("\n右键 / Esc 取消" if not selected.is_empty() else "")
	_update_visuals()

func _has_skill(uid: int, option: String = "") -> bool:
	for a in action_list:
		if a.type == "skill" and int(a.unit) == uid and (option.is_empty() or a.get("option") == option): return true
	return false

func _begin_skill() -> void:
	var uid = int(selected.get("uid",-1))
	if not unit_rects.has(uid): return
	var key = cards[unit_rects[uid].data.card].get("skill","")
	if key == "manufacture": _manufacture("light_tank"); return
	if key in ["repair","rally"]: _send({"type":"skill","unit":uid}); return
	skill_mode = key; command_ally = -1
	_refresh_selection(); queue_redraw()

func _manufacture(option: String) -> void:
	_send({"type":"skill","unit":int(selected.get("uid",-1)),"option":option,"lane":int(state.get("home_lane",3))})

func _confirm_mulligan() -> void:
	_send({"type":"mulligan","cards":marked.duplicate()})

func _send(action: Dictionary) -> void:
	if state.is_empty(): return
	if settings.animations and battle_fx.is_busy(): _message("指令正在呈现，请稍候。"); return
	if multiplayer_game and not _network_available(): _message("等待双方连接恢复。"); return
	if multiplayer_game: net.send_action(action)
	else:
		var error = rules.act(int(state.you),action)
		if not error.is_empty(): _message(error); return
		_accept_state(rules.view(int(state.you)))
	action_busy = 0.23 if settings.animations else 0.0
	if action.type == "mulligan": marked.clear()
	skill_mode = ""; command_ally = -1
	_refresh_selection()

func _hit_card(pos: Vector2) -> Dictionary:
	var list = card_nodes.values()
	list.sort_custom(func(a,b): return a.z_index > b.z_index)
	for node in list:
		if node.modulate.a < 0.5: continue
		var local = node.get_global_transform().affine_inverse()*pos
		if Rect2(Vector2.ZERO,node.size).has_point(local): return {"uid":int(node.data.uid),"kind":"unit" if node.card_mode == "unit" else "hand","data":node.data}
	return {}

func _target(pos: Vector2) -> Dictionary:
	for uid in unit_rects:
		if unit_rects[uid].rect.has_point(pos): return {"target":uid,"owner":unit_rects[uid].owner,"lane":int(unit_rects[uid].data.lane),"slot":int(unit_rects[uid].data.get("slot",0))}
	if ENEMY_BASE.has_point(pos): return {"target":"base","owner":1-int(state.you)}
	if OWN_BASE.has_point(pos): return {"target":"base","owner":int(state.you)}
	for row in range(4):
		if LANES[row].has_point(pos):
			var lane_value = _global_lane(row)
			for slot in _lane_slots(lane_value):
				if _slot_rect(lane_value,slot).has_point(pos): return {"lane":lane_value,"slot":slot}
			return {"lane":lane_value}
	return {}

func _drop_action(source: Dictionary, dst: Dictionary) -> Dictionary:
	if source.is_empty() or dst.is_empty(): return {}
	var uid = int(source.uid)
	if source.kind == "hand":
		var c = cards[source.data.card]; var a = {"type":"play","hand":uid}
		if c.kind == "unit" or c.get("target") == "lane":
			if not dst.has("lane"): return {}
			a.lane = dst.lane
			if dst.has("slot") and c.kind == "unit": a.slot = dst.slot
		elif c.get("target") in ["enemy","friendly"]:
			var owner = int(state.you) if c.target == "friendly" else 1-int(state.you)
			if not dst.has("target") or dst.get("owner") != owner: return {}
			a.target = dst.target
		return a
	if dst.has("target") and dst.get("owner") == 1-int(state.you): return {"type":"attack","unit":uid,"target":dst.target}
	if dst.has("lane") and not dst.has("target"):
		var a = {"type":"move","unit":uid,"lane":dst.lane}
		if dst.has("slot"): a.slot = dst.slot
		return a
	return {}

func _legal(action: Dictionary) -> bool:
	return not action.is_empty() and action_keys.has(_action_key(action))

func _action_key(action: Dictionary) -> String:
	# JSON transports numbers as floats. Normalize IDs for both seats.
	var target = action.get("target", "")
	if preview.integer(target): target = str(int(target))
	return "%s/%d/%d/%d/%s/%d/%s/%s" % [action.get("type",""),int(action.get("hand",-1)),int(action.get("unit",-1)),int(action.get("lane",-1)),str(target),int(action.get("ally",-1)),action.get("option",""),str(int(action.slot)) if action.has("slot") else "auto"]

func _drop(source: Dictionary, pos: Vector2) -> void:
	var a = _drop_action(source,_target(pos))
	if a.is_empty(): _message("将卡牌拖向合法战线、单位或基地。"); return
	if _legal(a): _send(a); return
	if not _is_turn(): _message("请等待你的回合。"); return
	if a.type == "play" and cards[source.data.card].cost > state.players[int(state.you)].mana: _message("召唤点不足。"); return
	if a.type == "play" and cards[source.data.card].kind == "unit":
		var error = preview.deploy_error(int(state.you),int(a.lane),a.get("slot"))
		if a.has("slot") and int(a.lane) == int(state.home_lane): error = preview.explicit_slot_error(int(state.you),int(a.lane),a)
		_message(error if not error.is_empty() else "该位置无法部署单位。"); return
	if a.type == "attack": _message(preview.attack_error(int(state.you),source.data,a.target)); return
	if a.type == "move" and a.has("slot"):
		var error = preview.explicit_slot_error(int(state.you),int(a.lane),a)
		if not error.is_empty(): _message(error); return
	_message("请选择相邻战线的可用空槽，并确保有剩余行动。" if a.type == "move" else "目标不合法，操作未执行。")

func _click(pos: Vector2) -> void:
	var hit = _hit_card(pos)
	if state.phase == "mulligan":
		if not hit.is_empty() and not state.mulligan_done[int(state.you)]:
			if hit.uid in marked: marked.erase(hit.uid)
			else: marked.append(hit.uid)
			_inspect(hit.data); _update_visuals(); _refresh_hud()
		return
	if not skill_mode.is_empty():
		var dst = _target(pos); var a = {"type":"skill","unit":int(selected.uid)}
		if skill_mode in ["charge","airstrike"] and dst.has("lane"): a.lane = dst.lane
		elif skill_mode == "command":
			if command_ally == -1:
				if dst.get("owner") == state.you and dst.get("target") is int and int(dst.target) != int(selected.uid): command_ally = int(dst.target); _refresh_selection()
				else: _message("先选择另一名友军。")
				return
			if dst.has("target") and dst.get("owner") == 1-int(state.you): a.ally = command_ally; a.target = dst.target
		if _legal(a): _send(a)
		else: _message("这个目标不能发动当前技能。")
		return
	if not hit.is_empty():
		_inspect(hit.data)
		if hit.kind == "hand" or unit_rects[hit.uid].owner == state.you:
			if not selected.is_empty() and int(selected.uid) != int(hit.uid):
				var a = _drop_action(selected,_target(pos))
				if _legal(a): _send(a); return
			selected = hit; _refresh_selection()
		elif not selected.is_empty(): _drop(selected,pos)
	elif not selected.is_empty(): _drop(selected,pos)
	queue_redraw()

func _pointer_down(pos: Vector2) -> void:
	pointer = pos; press_position = pos; press = _hit_card(pos); dragging = false; aiming = false; press_active = true

func _pointer_move(pos: Vector2) -> void:
	pointer = pos
	if not press.is_empty() and state.phase == "battle" and skill_mode.is_empty() and press_position.distance_to(pos) > 8:
		if press.kind == "unit" and unit_rects[press.uid].owner != state.you: return
		if not dragging:
			dragging = true; selected = press.duplicate(); _inspect(press.data)
			aiming = press.kind == "unit"
			if not aiming:
				ghost = Card.new(); ghost.configure(cards[press.data.card],press.data,"hand",true); ghost.size = Vector2(172,240); ghost.modulate.a = 0.9
				fx.add_child(ghost); card_nodes[int(press.uid)].modulate.a = 0.33
		if ghost != null: ghost.position = pos-ghost.size/2
		_refresh_selection()
	elif press.is_empty(): _hover(pos)
	queue_redraw()

func _pointer_up(pos: Vector2) -> void:
	if not press_active: return
	var source = press.duplicate(); var was_dragging = dragging
	_cancel_drag()
	if was_dragging: _drop(source,pos)
	else: _click(pos)

func _cancel_drag() -> void:
	if ghost != null: ghost.queue_free(); ghost = null
	if not press.is_empty() and card_nodes.has(int(press.uid)): card_nodes[int(press.uid)].modulate.a = 1.0
	press = {}; dragging = false; aiming = false; press_active = false
	queue_redraw()

func _hover(pos: Vector2) -> void:
	if action_busy > 0: return
	var hit = _hit_card(pos); var uid = int(hit.get("uid",-1))
	if uid == hovered: return
	for old_uid in card_nodes:
		var node = card_nodes[old_uid]; node.hovered = old_uid == uid
		if homes.has(old_uid):
			var home = homes[old_uid]
			node.position = home.position+(Vector2(0,-32) if old_uid == uid and node.card_mode == "hand" else Vector2.ZERO)
			node.z_index = 40 if old_uid == uid else home.z; node.rotation = 0 if old_uid == uid else home.rotation
	hovered = uid
	if not hit.is_empty(): _inspect(hit.data)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		settings.fullscreen = not settings.fullscreen
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		_save_settings()
	if screen != "battle" or state.is_empty(): return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_drag(); selected = {}; skill_mode = ""; command_ally = -1; _refresh_selection(); get_viewport().set_input_as_handled()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed: _cancel_drag(); selected = {}; skill_mode = ""; _refresh_selection()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.position.x >= 1270 or (state.phase == "mulligan" and event.position.y > 650):
				if not event.pressed and not press.is_empty():
					_cancel_drag()
					_message("已取消拖动。")
					get_viewport().set_input_as_handled()
				return
			if event.pressed: _pointer_down(event.position)
			else: _pointer_up(event.position)
	if event is InputEventMouseMotion: _pointer_move(event.position)

func _process(delta: float) -> void:
	if screen != "battle" or state.is_empty(): return
	action_busy = maxf(0,action_busy-delta)
	if multiplayer_game: return
	if state.phase == "battle" and state.winner == null and state.turn != state.you:
		ai_clock += delta
		if ai_clock > 0.55 and action_busy == 0:
			ai_clock = 0
			var error = rules.act(1,rules.ai_action(1))
			if not error.is_empty(): rules.act(1,{"type":"end"})
			_accept_state(rules.view(0))
	else: ai_clock = 0

func _message(text_value: String) -> void:
	status = text_value
	if toast == null: return
	toast.text = text_value
	if screen == "battle" and not state.is_empty(): _refresh_hud()
	var captured = text_value
	get_tree().create_timer(4.5).timeout.connect(func():
		if is_instance_valid(toast) and toast.text == captured: toast.text = "")

func _collection() -> void:
	_clear_screen("collection"); collection_counts = {}
	for key in deck: collection_counts[key] = collection_counts.get(key,0)+1
	_label("军备图鉴与牌组",Vector2(70,45),Vector2(1050,75),42)
	collection_label = _label("",Vector2(75,120),Vector2(1220,45),23,GOLD)
	_button("保存牌组并返回",Rect2(1250,54,290,55),_save_collection)
	_button("恢复默认牌组",Rect2(1250,123,290,45),func(): deck = rules.default_deck.duplicate(); _collection())
	var scroll = ScrollContainer.new(); scroll.position = Vector2(65,195); scroll.size = Vector2(1475,740); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	widgets.add_child(scroll)
	var grid = GridContainer.new(); grid.columns = 5
	grid.add_theme_constant_override("h_separation",30); grid.add_theme_constant_override("v_separation",26); scroll.add_child(grid)
	for key in cards:
		var holder = VBoxContainer.new(); holder.custom_minimum_size = Vector2(270,368); grid.add_child(holder)
		var node = Card.new(); node.custom_minimum_size = Vector2(270,300); node.configure(cards[key],{},"detail"); holder.add_child(node)
		var row = HBoxContainer.new(); holder.add_child(row)
		var minus = Button.new(); minus.text = "−"; minus.custom_minimum_size = Vector2(60,42); row.add_child(minus)
		var count = Label.new(); count.custom_minimum_size = Vector2(110,42); count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; row.add_child(count)
		var plus = Button.new(); plus.text = "+"; plus.custom_minimum_size = Vector2(60,42); row.add_child(plus)
		count.text = "%d / 2" % int(collection_counts.get(key,0))
		minus.pressed.connect(func(): collection_counts[key] = maxi(0,int(collection_counts.get(key,0))-1); count.text = "%d / 2" % int(collection_counts[key]); _collection_total())
		plus.pressed.connect(func():
			if _deck_size() >= 30: _message("牌组已满30张，请先移除一张。"); return
			collection_counts[key] = mini(2,int(collection_counts.get(key,0))+1); count.text = "%d / 2" % int(collection_counts[key]); _collection_total())
	_collection_total(); toast.position.y = 955

func _deck_size() -> int:
	var total = 0
	for value in collection_counts.values(): total += int(value)
	return total

func _collection_total() -> void:
	collection_label.text = "牌组 %d / 30 张   ·   同名最多2张   ·   所有卡牌均配有完整插画" % _deck_size()

func _save_collection() -> void:
	if _deck_size() != 30: _message("牌组需要恰好30张，现在有%d张。" % _deck_size()); return
	var candidate = []
	for key in collection_counts:
		for _i in range(int(collection_counts[key])): candidate.append(key)
	var error = rules.validate_deck(candidate)
	if not error.is_empty(): _message(error); return
	deck = candidate; _save_settings(); _menu()

func _settings_menu() -> void:
	_clear_screen("settings")
	_label("设置与作战规则",Vector2(90,65),Vector2(1240,75),42)
	_label("指挥官名称",Vector2(100,167),Vector2(300,45)); _field("name",str(settings.name),Rect2(350,167,500,48)).max_length = 18
	for i in range(3):
		var key = ["animations","sound","fullscreen"][i]; var node = CheckButton.new()
		node.position = Vector2(1050,165+i*60); node.size = Vector2(390,52)
		node.text = {"animations":"卡牌动画","sound":"战斗音效","fullscreen":"全屏（F11）"}[key]; node.button_pressed = settings[key]
		node.toggled.connect(func(value):
			settings[key] = value
			if key == "fullscreen": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED))
		widgets.add_child(node)
	var text_value = "① 开局双方各获4张手牌。点击任意牌标记替换；先抽取替代牌，再把旧牌放回并洗牌。\n\n② 每线中央5个共用槽，敌我可共处；两端后方另各有2个守方专属槽。手牌单位仅部署于己方后方。点空槽指定位置，点战线标签自动落位。\n\n③ 移动消耗1行动，进入相邻战线的可用空槽；建筑不能移动。普通单位每回合1行动，迅捷2，突袭部署即可行动。\n\n④ 近战射程1，远程2，超远程3。无需清空敌军才能攻击基地；须符合射程及嘲讽规则。飞行可直击基地。\n\n⑤ 嘲讽保护同线单位，敌后方嘲讽保护基地。防御抵扣伤害，装弹需要等待。详细效果见图鉴。\n\n⑥ 拖动手牌部署或施法；按住己方单位拉箭头，红色攻击敌军或基地、蓝色移至相邻空槽。单位卡保持原位，也可点击选择再点目标。\n\n⑦ 选中单位后点技能按钮，再按提示选目标。箭雨选一条战线，仅伤害该线敌军。Esc或右键取消；战斗音效与动画可分别关闭。\n\n⑧ 基地30生命，归零即败。召唤点上限每回合增加，最多10；空牌堆抽牌造成逐次增加的疲劳伤害。"
	var rule_label = _label(text_value,Vector2(100,300),Vector2(1400,565),20); rule_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button("保存并返回",Rect2(110,895,320,57),func():
		settings.name = fields.name.text.strip_edges().left(18)
		if settings.name.is_empty(): settings.name = "指挥官"
		_save_settings(); _menu())

func _panel(rect: Rect2, fill: Color, border: Color = GOLD) -> void:
	draw_style_box(_style(fill,border),rect)

func _text(value: String, pos: Vector2, pixels: int, color: Color = PAPER) -> void:
	draw_string(font,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,color)

func _draw() -> void:
	if font == null: return
	draw_rect(Rect2(0,0,1600,1000),Color("111c1c"))
	for x in range(0,1600,64): draw_line(Vector2(x,0),Vector2(x,1000),Color(0.55,0.64,0.49,0.045))
	for y in range(0,1000,64): draw_line(Vector2(0,y),Vector2(1600,y),Color(0.55,0.64,0.49,0.045))
	for points in map_lines: draw_polyline(points,Color(0.65,0.72,0.55,0.035),1.0,true)
	if screen != "battle" or state.is_empty(): _panel(Rect2(95,92,1410,817),Color(0.07,0.12,0.11,0.78),Color("455748")); return
	_panel(Rect2(1274,73,312,867),Color("1a2524"),Color("6b7052")); _panel(ENEMY_BASE,Color("422f2c"),RED); _panel(OWN_BASE,Color("233f3a"),BLUE)
	for row in range(4):
		var lane_value = _global_lane(row)
		var counts = [0,0]
		for owner in range(2):
			for u in state.players[owner].board:
				if int(u.lane) == lane_value: counts[owner] += 1
		_panel(LANES[row],Color("293832") if row > 1 else Color("352f28"),Color("6f7958"))
		_text(["敌方后方","敌方前线","己方前线","己方后方"][row],LANES[row].position+Vector2(12,40),18,BLUE if row > 1 else RED)
		_text("我 %d · 敌 %d" % [counts[int(state.you)],counts[1-int(state.you)]],LANES[row].position+Vector2(12,68),15,GOLD)
		for slot in _lane_slots(lane_value):
			var rect = _slot_rect(lane_value,slot)
			var exclusive = slot >= 5
			var color = (BLUE if row == 3 else RED) if exclusive else Color("758473")
			_panel(rect,Color(0.85,0.84,0.65,0.035),color.darkened(0.25))
			_text("守方专属" if exclusive else "共用 %d" % [slot+1],rect.position+Vector2(25,55),14,color)
	if state.phase == "mulligan":
		draw_rect(Rect2(35,155,1220,580),Color(0.03,0.06,0.07,0.9)); _text("开 局 整 备",Vector2(470,240),38,GOLD)
		_text("点击任意卡牌标记替换。旧牌在抽取替代牌后回到牌堆。",Vector2(335,291),20,PAPER)
	if not selected.is_empty() and _is_turn():
		for row in range(4):
			var lane_value = _global_lane(row)
			for slot in _lane_slots(lane_value):
				if _legal(_drop_action(selected,{"lane":lane_value,"slot":slot})): draw_rect(_slot_rect(lane_value,slot).grow(2),BLUE,false,3)
		for uid in unit_rects:
			var info = unit_rects[uid]
			if _legal(_drop_action(selected,{"target":uid,"owner":info.owner,"lane":info.data.lane})): draw_rect(info.rect.grow(2),RED if selected.kind == "unit" else GOLD,false,3)
		if _legal(_drop_action(selected,{"target":"base","owner":1-int(state.you)})): draw_rect(ENEMY_BASE,RED,false,3)

func _draw_aim(layer: Control) -> void:
	if not dragging: return
	var start = unit_rects.get(int(press.get("uid",-1)),{}).get("rect",Rect2(press_position,Vector2.ZERO)).get_center() if aiming else press_position
	var destination = _target(pointer)
	var action = _drop_action(press,destination)
	var legal = _legal(action)
	var color = RED if action.get("type") == "attack" else BLUE
	if not legal: color = Color("8f9283")
	var end = pointer
	if legal and destination.has("target"):
		end = ENEMY_BASE.get_center() if destination.target is String else unit_rects[int(destination.target)].rect.get_center()
	elif legal and destination.has("slot"): end = _slot_rect(int(destination.lane),int(destination.slot)).get_center()
	var direction = (end-start).normalized()
	var points = PackedVector2Array()
	for i in range(25):
		var t = float(i)/24.0
		points.append(start.lerp(end,t)+Vector2(0,-sin(t*PI)*35))
	layer.draw_polyline(points,Color(color,0.9),5,true)
	layer.draw_colored_polygon(PackedVector2Array([end,end-direction.rotated(0.5)*23,end-direction.rotated(-0.5)*23]),color)
