extends Node

signal state_changed(state: Dictionary, lobby: Array)
signal status_changed(message: String)
signal seat_assigned(seat: int)

const EngineScript = preload("res://scripts/engine.gd")
const VERSION = "2.1"
const MAX_FRAME = 65536
var seat: int = -1
var online: bool = false
var is_host: bool = false
var port: int = 47653
var game = null
var lobby: Array = [null, null]
var state: Dictionary = {}
var _server = TCPServer.new()
var _peers: Array = []
var _slots: Array = [null, null]
var _client = null
var _buffer = PackedByteArray()
var _hello: Dictionary = {}
var _token: String = ""
var _password: String = ""
var _ip: String = ""
var _active: bool = false
var _hello_sent: bool = false
var _next_retry: int = 0
var _attempts: int = 0
var _last_ping: int = 0
var _connect_since: int = 0
var _last_received: int = 0

func _deck_error(deck: Array) -> String:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/cards.json"))
	if deck.size() != 30: return "牌组必须恰好30张。"
	var counts: Dictionary = {}
	for key in deck:
		if not key is String or not data.cards.has(key): return "牌组包含未知卡牌。"
		counts[key] = counts.get(key, 0) + 1
		if counts[key] > 2: return "同名卡牌最多放入两张。"
	return ""

func host(port_value: int, password: String, player_name: String, deck: Array) -> String:
	close()
	var error = _deck_error(deck)
	if not error.is_empty(): return error
	if port_value < 0 or port_value > 65535: return "端口无效。"
	port = port_value
	if port == 0:
		for attempt in range(30):
			port = randi_range(49152, 64000)
			if _server.listen(port) == OK: break
		if not _server.is_listening(): return "无法创建房间，请检查端口是否被占用。"
	elif _server.listen(port) != OK: return "无法创建房间，请检查端口是否被占用。"
	_password = password
	is_host = true
	online = true
	_active = true
	seat = 0
	_slots[0] = {"name": player_name.strip_edges().left(18), "deck": deck.duplicate(), "ready": false, "online": true, "token": _new_token()}
	seat_assigned.emit(seat)
	_broadcast()
	return ""

func join(ip: String, port_value: int, password: String, player_name: String, deck: Array) -> String:
	close()
	var error = _deck_error(deck)
	if not error.is_empty(): return error
	if port_value < 1 or port_value > 65535: return "端口无效。"
	_ip = ip
	port = port_value
	_hello = {"type": "hello", "version": VERSION, "password": password, "name": player_name, "deck": deck}
	_active = true
	_connect()
	return ""

func _new_token() -> String:
	return Crypto.new().generate_random_bytes(24).hex_encode()

func _connect() -> void:
	_client = StreamPeerTCP.new()
	_connect_since = Time.get_ticks_msec()
	_last_received = _connect_since
	_buffer.clear()
	_hello_sent = false
	if _client.connect_to_host(_ip, port) != OK:
		_disconnected()
	else: status_changed.emit("正在连接房间…")

func ready_up() -> void:
	_send({"type": "ready"})

func send_action(action: Dictionary) -> void:
	_send({"type": "action", "revision": state.get("revision", -1), "action": action})

func _send(message: Dictionary) -> void:
	if is_host:
		_process_message(0, message)
	elif online and _client != null:
		_write(_client, message)
	else: status_changed.emit("连接未就绪，请稍候。")

func retry() -> void:
	if is_host or online: return
	_active = true
	_attempts = 0
	_next_retry = 0
	if _client != null: _client.disconnect_from_host()
	_client = null

func close() -> void:
	_active = false
	_server.stop()
	for peer in _peers: peer.socket.disconnect_from_host()
	_peers.clear()
	if _client != null: _client.disconnect_from_host()
	_client = null
	_slots = [null, null]
	lobby = [null, null]
	game = null
	state = {}
	seat = -1
	online = false
	is_host = false
	_token = ""
	_attempts = 0

func _exit_tree() -> void:
	close()

func _write(socket: StreamPeerTCP, message: Dictionary) -> bool:
	var bytes = (JSON.stringify(message) + "\n").to_utf8_buffer()
	return bytes.size() <= MAX_FRAME and socket.put_data(bytes) == OK

func _process(_delta: float) -> void:
	if not _active: return
	if is_host:
		while _server.is_connection_available():
			var socket = _server.take_connection()
			socket.set_no_delay(true)
			if _peers.size() >= 8: socket.disconnect_from_host()
			else: _peers.append({"socket": socket, "buffer": PackedByteArray(), "seat": -1, "since": Time.get_ticks_msec(), "received": Time.get_ticks_msec()})
		for peer in _peers.duplicate():
			peer.socket.poll()
			if peer.socket.get_status() != StreamPeerTCP.STATUS_CONNECTED or (peer.seat == -1 and Time.get_ticks_msec() - peer.since > 6000) or Time.get_ticks_msec() - peer.received > 15000:
				_drop(peer)
				continue
			_read_peer(peer)
	else:
		if _client == null:
			if Time.get_ticks_msec() >= _next_retry: _connect()
			return
		_client.poll()
		var status = _client.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			if Time.get_ticks_msec() - _last_received > 15000: _disconnected(); return
			if not _hello_sent:
				_client.set_no_delay(true)
				var hello = _hello.duplicate(true)
				if not _token.is_empty(): hello.token = _token
				_write(_client, hello)
				_hello_sent = true
			if Time.get_ticks_msec() - _last_ping > 4000:
				_write(_client, {"type": "ping"})
				_last_ping = Time.get_ticks_msec()
			_read_client()
		elif status != StreamPeerTCP.STATUS_CONNECTING or Time.get_ticks_msec() - _connect_since > 6000: _disconnected()

func _disconnected() -> void:
	online = false
	if _client != null: _client.disconnect_from_host()
	_client = null
	_attempts += 1
	if _token.is_empty() or _attempts > 15:
		_active = false
		status_changed.emit("无法连接房间，请核对IP、端口、口令；可点击重试。")
	else:
		_next_retry = Time.get_ticks_msec() + 1000
		status_changed.emit("连接中断，正在重连（%d/15）…" % _attempts)

func _read_peer(peer: Dictionary) -> void:
	var count = peer.socket.get_available_bytes()
	if count == 0: return
	var result = peer.socket.get_data(mini(count, MAX_FRAME + 1))
	if result[0] != OK: _drop(peer); return
	peer.received = Time.get_ticks_msec()
	peer.buffer.append_array(result[1])
	while true:
		var end = peer.buffer.find(10)
		if end == -1:
			if peer.buffer.size() > MAX_FRAME: _reject(peer, "消息超过限制。")
			return
		if end + 1 > MAX_FRAME: _reject(peer, "消息超过限制。"); return
		var value = JSON.parse_string(peer.buffer.slice(0, end).get_string_from_utf8())
		peer.buffer = peer.buffer.slice(end + 1)
		if not value is Dictionary: _reject(peer, "无效消息。"); return
		if peer.seat == -1: _accept_hello(peer, value)
		else: _process_message(peer.seat, value)
		if not _peers.has(peer): return

func _read_client() -> void:
	var count = _client.get_available_bytes()
	if count == 0: return
	var result = _client.get_data(mini(count, MAX_FRAME + 1))
	if result[0] != OK: _disconnected(); return
	_last_received = Time.get_ticks_msec()
	_buffer.append_array(result[1])
	while true:
		var end = _buffer.find(10)
		if end == -1:
			if _buffer.size() > MAX_FRAME: _disconnected()
			return
		if end + 1 > MAX_FRAME: _disconnected(); return
		var value = JSON.parse_string(_buffer.slice(0, end).get_string_from_utf8())
		_buffer = _buffer.slice(end + 1)
		if not value is Dictionary: _disconnected(); return
		match value.get("type"):
			"welcome":
				seat = int(value.seat)
				_token = value.token
				online = true
				_attempts = 0
				seat_assigned.emit(seat)
				status_changed.emit("已连接房间。")
			"state":
				state = value.state
				lobby = value.lobby
				state_changed.emit(state, lobby)
			"error":
				status_changed.emit(str(value.get("message", "连接失败。")))
				if not online:
					_active = false
					_client.disconnect_from_host()
					_client = null
					return

func _accept_hello(peer: Dictionary, hello: Dictionary) -> void:
	if hello.get("type") != "hello" or hello.get("version") != VERSION: _reject(peer, "双方游戏版本不一致。"); return
	if hello.get("password", "") != _password: _reject(peer, "房间口令错误。"); return
	var token = hello.get("token", "")
	if not token is String: _reject(peer, "重连凭证无效。"); return
	if not token.is_empty():
		if _slots[1] == null or _slots[1].token != token: _reject(peer, "重连凭证无效。"); return
		if _slots[1].online: _reject(peer, "此玩家已在线。"); return
	else:
		if _slots[1] != null: _reject(peer, "房间已满，席位保留给原玩家重连。"); return
		if not hello.get("deck") is Array: _reject(peer, "牌组无效。"); return
		var error = _deck_error(hello.deck)
		if not error.is_empty(): _reject(peer, error); return
		_slots[1] = {"name": str(hello.get("name", "指挥官")).strip_edges().left(18), "deck": hello.deck.duplicate(), "ready": false, "online": false, "token": _new_token()}
	peer.seat = 1
	_slots[1].online = true
	_write(peer.socket, {"type": "welcome", "seat": 1, "token": _slots[1].token})
	_broadcast()

func _reject(peer: Dictionary, error: String) -> void:
	_write(peer.socket, {"type": "error", "message": error})
	_drop(peer)

func _drop(peer: Dictionary) -> void:
	peer.socket.disconnect_from_host()
	_peers.erase(peer)
	if peer.seat == 1 and _slots[1] != null:
		_slots[1].online = false
		_broadcast()

func _error(player: int, message: String) -> void:
	if player == 0: status_changed.emit(message)
	else:
		for peer in _peers:
			if peer.seat == player: _write(peer.socket, {"type": "error", "message": message})

func _process_message(player: int, message: Dictionary) -> void:
	var live_action = false
	match message.get("type"):
		"ping":
			for peer in _peers:
				if peer.seat == player: _write(peer.socket, {"type": "pong"})
			return
		"ready":
			if game != null and game.winner == null: _error(player, "对局已经开始。"); return
			_slots[player].ready = true
			if _slots[1] != null and _slots[0].ready and _slots[1].ready and _slots[1].online:
				game = EngineScript.new([_slots[0].deck, _slots[1].deck], [_slots[0].name, _slots[1].name])
				_slots[0].ready = false
				_slots[1].ready = false
		"action":
			if game == null: _error(player, "请等待双方准备。"); return
			if _slots[1] == null or not _slots[1].online: _error(player, "对方断线，对局暂停等待重连。"); return
			var action = message.get("action")
			if not action is Dictionary: _error(player, "无效操作。"); return
			var opening = game.phase == "mulligan" and action.get("type") == "mulligan"
			if not opening and message.get("revision") != game.revision:
				_broadcast()
				_error(player, "状态已更新，请重新操作。")
				return
			var error = game.act(player, action)
			if not error.is_empty(): _error(player, error); return
			live_action = true
		_: _error(player, "未知房间消息。"); return
	_broadcast(live_action)

func _state_view(player: int, live_action: bool) -> Dictionary:
	if game == null: return {}
	var visible = game.view(player)
	if not live_action:
		visible.events = []
		visible.event_mode = "baseline"
	return visible

func _broadcast(live_action: bool = false) -> void:
	lobby = []
	for slot in _slots:
		lobby.append(null if slot == null else {"name": slot.name, "ready": slot.ready, "online": slot.online})
	state = _state_view(0, live_action)
	state_changed.emit(state, lobby)
	for peer in _peers.duplicate():
		if peer.seat >= 0:
			if not _write(peer.socket, {"type": "state", "lobby": lobby, "state": _state_view(peer.seat, live_action)}):
				_drop(peer)
