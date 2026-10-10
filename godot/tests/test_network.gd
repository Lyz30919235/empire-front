extends SceneTree

const Network = preload("res://scripts/network.gd")
var host_node
var guest_node
var deck: Array
var failures: Array = []
var host_errors: Array = []
var guest_errors: Array = []
var checks: int = 0
var host_live_batches = 0
var guest_live_batches = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func tick(count: int = 5) -> void:
	for i in range(count): await create_timer(0.002).timeout

func wait_for(predicate: Callable, label: String, limit: int = 500) -> bool:
	for i in range(limit):
		if predicate.call(): return true
		await tick(1)
	check(false, "超时：" + label)
	return false

func raw_connect(hello: Dictionary) -> Dictionary:
	var socket = StreamPeerTCP.new()
	check(socket.connect_to_host("127.0.0.1", host_node.port) == OK, "原始TCP连接")
	await wait_for(func(): socket.poll(); return socket.get_status() == StreamPeerTCP.STATUS_CONNECTED, "原始TCP就绪")
	socket.put_data((JSON.stringify(hello) + "\n").to_utf8_buffer())
	return {"socket": socket, "buffer": PackedByteArray()}

func raw_read(peer: Dictionary, kind: String) -> Dictionary:
	for i in range(500):
		peer.socket.poll()
		var count = peer.socket.get_available_bytes()
		if count > 0:
			var result = peer.socket.get_data(count)
			if result[0] == OK: peer.buffer.append_array(result[1])
		while peer.buffer.find(10) >= 0:
			var end = peer.buffer.find(10)
			var message = JSON.parse_string(peer.buffer.slice(0, end).get_string_from_utf8())
			peer.buffer = peer.buffer.slice(end + 1)
			if message is Dictionary and message.get("type") == kind: return message
		await tick(1)
	check(false, "原始TCP未收到" + kind)
	return {}

func hello() -> Dictionary:
	return {"type": "hello", "version": Network.VERSION, "password": "test-room", "name": "TCP测试", "deck": deck}

func public_payload(value) -> bool:
	if value is Dictionary:
		for key in value:
			if key in ["hand", "deck", "action", "token", "password", "cards"]: return false
			if not public_payload(value[key]): return false
	elif value is Array:
		for item in value:
			if not public_payload(item): return false
	return true

func baseline(label: String) -> void:
	for node in [host_node, guest_node]:
		check(node.state.get("event_mode") == "baseline" and node.state.get("events", [1]).is_empty(), label)

func synced(revision: int) -> bool:
	return guest_node.state.get("revision", -1) == revision and host_node.state.get("revision", -1) == revision

func assert_views() -> void:
	# JSON数字解码为float；将本地主机视图也经JSON规范化后比较嵌套值。
	var a = JSON.parse_string(JSON.stringify(host_node.state))
	var b = guest_node.state
	check(not a.players[1].has("hand") and not b.players[0].has("hand"), "仅自己的手牌可见")
	for player in range(2):
		check(not a.players[player].has("deck") and not b.players[player].has("deck"), "双方牌库隐藏")
		for key in ["hp", "mana", "board", "deck_count", "hand_count"]:
			check(a.players[player][key] == b.players[player][key], "双方公共状态同步：" + key)
	for key in ["turn", "round", "winner", "revision", "log", "match_id", "events", "event_mode"]:
		check(a[key] == b[key], "双方对局同步：" + key)
	check(public_payload(a.events) and public_payload(b.events), "公开事件不携带手牌牌库及凭证")
	for event in a.events:
		check(event.match_id == a.match_id and int(event.revision) == int(a.revision), "事件属于当前对局和动作")
	for player in range(2):
		for unit in a.players[player].board:
			check(unit.has("slot"), "公开单位包含真实槽位")

func run() -> void:
	deck = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/cards.json")).default_deck
	host_node = Network.new()
	guest_node = Network.new()
	root.add_child(host_node)
	root.add_child(guest_node)
	host_node.status_changed.connect(func(message): host_errors.append(message))
	guest_node.status_changed.connect(func(message): guest_errors.append(message))
	host_node.state_changed.connect(func(value, _lobby):
		if value.get("event_mode") == "live": host_live_batches += 1)
	guest_node.state_changed.connect(func(value, _lobby):
		if value.get("event_mode") == "live": guest_live_batches += 1)
	check(host_node.host(0, "test-room", "房主", deck).is_empty(), "启动房间")
	check(host_node.port > 0 and host_node.online and host_node.seat == 0, "房主公开端口与席位")
	for field in ["password", "version"]:
		var message = hello()
		message[field] = "wrong"
		var raw = await raw_connect(message)
		var error = await raw_read(raw, "error")
		check(str(error.get("message", "")).contains("口令" if field == "password" else "版本"), "验证" + field)
		raw.socket.disconnect_from_host()
	check(host_node._slots[1] == null, "认证失败不占席位")
	check(guest_node.join("127.0.0.1", host_node.port, "test-room", "访客", deck).is_empty(), "加入房间")
	if not await wait_for(func(): return guest_node.online and guest_node.lobby[1] != null, "访客欢迎"): finish(); return
	check(guest_node.seat == 1 and guest_node.state.is_empty(), "访客席位与等待状态")
	var first_token = guest_node._token
	var intruder = await raw_connect(hello())
	check(str((await raw_read(intruder, "error")).get("message", "")).contains("满"), "拒绝第三人")
	intruder.socket.disconnect_from_host()
	host_node.ready_up()
	guest_node.ready_up()
	if not await wait_for(func(): return synced(0), "双方准备进入整备"): finish(); return
	check(host_node.game.phase == "mulligan", "整备阶段")
	baseline("开局只有基线不播放事件")
	assert_views()
	var old_uid = host_node.state.players[0].hand[0].uid
	host_node.send_action({"type": "mulligan", "cards": [old_uid]})
	guest_node.send_action({"type": "mulligan", "cards": []})
	if not await wait_for(func(): return synced(2), "同时确认换牌"): finish(); return
	check(host_node.game.phase == "battle" and guest_node.state.mulligan_done == [true, true], "双方换牌完成")
	check(not host_node.state.players[0].hand.any(func(card): return card.uid == old_uid), "换牌移除原编号")
	assert_views()
	guest_node._write(guest_node._client, {"type": "action", "revision": 0, "action": {"type": "end"}})
	await tick(15)
	check(guest_errors.any(func(message): return message.contains("更新")) and host_node.game.revision == 2, "旧revision拒绝且无修改")
	baseline("旧revision纠正不重播历史动作")
	var live_before = [host_live_batches, guest_live_batches]
	guest_node.send_action({"type": "end"})
	await tick(15)
	check(guest_errors.any(func(message): return message.contains("回合")) and host_node.game.revision == 2, "非法回合拒绝")
	host_node.send_action({"type": "play", "hand": 999999, "lane": 3})
	check(host_node.game.revision == 2, "非法牌编号无资源修改")
	await tick()
	check(live_before == [host_live_batches, guest_live_batches], "被拒动作不发送live事件")
	# 暂时停用自动重连，验证断线时的暂停及保留席位。
	guest_node._active = false
	guest_node._client.disconnect_from_host()
	await wait_for(func(): return not host_node.lobby[1].online, "服务器识别断线")
	host_node.send_action({"type": "end"})
	check(host_node.game.revision == 2 and host_errors.back().contains("断线"), "断线暂停")
	intruder = await raw_connect(hello())
	check(str((await raw_read(intruder, "error")).get("message", "")).contains("满"), "断线席位防占用")
	intruder.socket.disconnect_from_host()
	guest_node._active = true
	guest_node._disconnected()
	if not await wait_for(func(): return guest_node.online and host_node.lobby[1].online, "自动token重连"): finish(); return
	check(guest_node._token == first_token and guest_node.seat == 1 and guest_node.state.revision == 2, "重连保持token席位与revision")
	baseline("重连只恢复基线不重播")
	host_node.send_action({"type": "end"})
	await wait_for(func(): return synced(3), "重连后操作同步")
	assert_views()
	# 完整权威对战：包括部署、技能、移动、攻击，双方每次等待同一revision。
	var actions = 0
	while host_node.game.winner == null and actions < 1600:
		var revision = host_node.game.revision
		var player = host_node.game.turn
		var action = host_node.game.ai_action(player)
		var batch_counts = [host_live_batches, guest_live_batches]
		(host_node if player == 0 else guest_node).send_action(action)
		if not await wait_for(func(): return synced(revision + 1), "完整对战动作" + str(action), 250): break
		check(host_live_batches == batch_counts[0] + 1 and guest_live_batches == batch_counts[1] + 1, "成功动作双端各接收一次live批次")
		assert_views()
		actions += 1
	check(host_node.game.winner != null, "完整TCP对战结束（%d动作）" % actions)
	print("[联机] 完整TCP对战：%d动作，胜方=%s" % [actions, str(host_node.game.winner)])
	var finished_match = host_node.state.match_id
	host_node.ready_up()
	guest_node.ready_up()
	await wait_for(func(): return synced(0) and host_node.state.winner == null, "双方再战")
	check(host_node.game.phase == "mulligan", "再战重新整备")
	check(host_node.state.match_id != finished_match and host_node.state.match_id == guest_node.state.match_id, "再战使用双端一致的新match_id")
	baseline("再战基线清空旧局事件")
	host_node.send_action({"type": "mulligan", "cards": []})
	await wait_for(func(): return synced(1), "单方确认整备")
	guest_node._active = false
	guest_node._client.disconnect_from_host()
	await wait_for(func(): return not host_node.lobby[1].online, "整备断线")
	guest_node._active = true
	guest_node._disconnected()
	await wait_for(func(): return guest_node.online and host_node.lobby[1].online, "整备重连")
	check(guest_node.state.mulligan_done == [true, false], "重连保留换牌确认")
	guest_node.send_action({"type": "mulligan", "cards": []})
	await wait_for(func(): return synced(2), "整备恢复进入对战")
	host_node.send_action({"type": "concede"})
	await wait_for(func(): return synced(3), "撤退同步")
	check(host_node.game.winner == 1, "主动撤退")
	host_node.ready_up()
	guest_node.ready_up()
	await wait_for(func(): return synced(0), "部署验证新对局")
	host_node.send_action({"type": "mulligan", "cards": []})
	guest_node.send_action({"type": "mulligan", "cards": []})
	await wait_for(func(): return synced(2), "部署验证整备完成")
	host_node.game.players[0].hand = [{"uid": 9000, "card": "light_cavalry"}]
	host_node.game.players[0].mana = 10
	host_node._broadcast()
	await tick()
	var before = JSON.stringify(host_node.game.view(0))
	host_node.send_action({"type": "play", "hand": 9000, "lane": 2, "slot": 0})
	check(host_errors.back().contains("后方") and JSON.stringify(host_node.game.view(0)) == before, "非法前线部署资源不变")
	host_node.send_action({"type": "play", "hand": 9000.5, "lane": 3, "slot": 0})
	check(JSON.stringify(host_node.game.view(0)) == before, "非法非整数编号无修改")
	host_node.send_action({"type": "play", "hand": 9000, "lane": 3, "slot": 0})
	await wait_for(func(): return synced(3), "后方部署TCP同步")
	assert_views()
	check(not guest_node.state.events.is_empty() and guest_node.state.event_mode == "live", "部署发送公开live事件")
	check(int(guest_node.state.players[0].board[0].slot) == 0, "精确部署槽位TCP同步")
	var deployed = host_node.game.players[0].board[0].uid
	host_node.send_action({"type": "move", "unit": deployed, "lane": 2, "slot": 4})
	await wait_for(func(): return synced(4), "部署后移动TCP同步")
	check(guest_node.state.players[0].board[0].lane == 2, "访客收到前线移动")
	check(int(guest_node.state.players[0].board[0].slot) == 4, "访客收到精确移动槽位")
	assert_views()
	host_node.game.summon(1,"infantry",2,false,1)
	host_node._broadcast()
	await tick()
	assert_views()
	check(guest_node.state.players[0].board[0].lane == guest_node.state.players[1].board[0].lane and guest_node.state.players[0].board[0].slot != guest_node.state.players[1].board[0].slot, "同一战线双方共处的不同真实槽位同步")
	# 满24槽、满手牌、满公开日志及单线7目标，检查真实状态/事件帧仍在64KiB内。
	for player in range(2): host_node.game.players[player].board.clear()
	for lane in range(4):
		for slot in range(5):
			var owner = 0 if lane == 3 else 1
			var unit = host_node.game.summon(owner,"medium_tank",lane,false,slot)
			unit.hp = 50; unit.max_hp = 50
	for owner in range(2):
		for slot in [5,6]:
			var key = "carrier" if owner == 0 and slot == 5 else "medium_tank"
			var unit = host_node.game.summon(owner,key,host_node.game.home_lane(owner),false,slot)
			unit.hp = 50; unit.max_hp = 50; unit.actions = 2
		while host_node.game.players[owner].hand.size() < 10:
			host_node.game.players[owner].hand.append({"uid":host_node.game.next_id,"card":"medium_tank"})
			host_node.game.next_id += 1
	for i in range(70): host_node.game.note("满场帧边界：公开战报、单位与技能同步 %d" % i)
	host_node._broadcast()
	await tick()
	var carrier = host_node.game.players[0].board.filter(func(unit): return unit.card == "carrier")[0]
	host_node.send_action({"type":"skill","unit":carrier.uid,"lane":0})
	await wait_for(func(): return synced(5), "满场单线技能事件同步")
	assert_views()
	check(host_node.state.players[0].board.size() + host_node.state.players[1].board.size() == 24, "最大24槽真实公开状态")
	for node in [host_node, guest_node]:
		var frame = (JSON.stringify({"type":"state","lobby":node.lobby,"state":node.state}) + "\n").to_utf8_buffer()
		check(frame.size() <= Network.MAX_FRAME, "满场公开事件帧不超过64KiB")
	# 分片的NDJSON必须等到换行才解析，不得因TCP分包丢失消息。
	var fragmented = StreamPeerTCP.new()
	fragmented.connect_to_host("127.0.0.1", host_node.port)
	await wait_for(func(): fragmented.poll(); return fragmented.get_status() == StreamPeerTCP.STATUS_CONNECTED, "分片TCP连接")
	var bytes = (JSON.stringify(hello()) + "\n").to_utf8_buffer()
	fragmented.put_data(bytes.slice(0, 13))
	await tick()
	fragmented.put_data(bytes.slice(13))
	var fragmented_error = await raw_read({"socket": fragmented, "buffer": PackedByteArray()}, "error")
	check(str(fragmented_error.get("message", "")).contains("满"), "分片JSON完整重组")
	fragmented.disconnect_from_host()
	# 大帧与非法JSON在尚未认证的TCP连接上验证，不能占席。
	for payload in ["[]\n", "x".repeat(Network.MAX_FRAME + 1)]:
		var socket = StreamPeerTCP.new()
		socket.connect_to_host("127.0.0.1", host_node.port)
		await wait_for(func(): socket.poll(); return socket.get_status() == StreamPeerTCP.STATUS_CONNECTED, "恶意帧连接")
		socket.put_data(payload.to_utf8_buffer())
		var response = await raw_read({"socket": socket, "buffer": PackedByteArray()}, "error")
		check(not str(response.get("message", "")).is_empty(), "拒绝非法JSON或大帧")
		socket.disconnect_from_host()
	finish()

func finish() -> void:
	host_node.close()
	guest_node.close()
	print("NETWORK TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
