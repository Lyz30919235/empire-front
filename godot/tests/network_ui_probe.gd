extends SceneTree

const Main = preload("res://scripts/main.gd")
var host_ui
var guest_ui
var failures = 0
var checks = 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _initialize() -> void:
	call_deferred("run")

func tick(count = 5) -> void:
	for i in range(count): await create_timer(0.002).timeout

func wait_for(predicate: Callable, label: String) -> bool:
	for i in range(500):
		if predicate.call(): return true
		await tick(1)
	push_error("超时：" + label)
	failures += 1
	return false

func wait_fx() -> void:
	await wait_for(func(): return not host_ui.battle_fx.is_busy() and not guest_ui.battle_fx.is_busy(), "双端表现队列完成")

func fx_counts() -> Array:
	return [host_ui.battle_fx.played_events, guest_ui.battle_fx.played_events, host_ui.battle_fx.sound_count, guest_ui.battle_fx.sound_count]

func send_fx(action: Dictionary, label: String) -> void:
	var counts = fx_counts()
	var revision = host_ui.state.revision
	host_ui._send(action)
	await wait_for(func(): return guest_ui.state.revision == revision + 1, label + "状态同步")
	await wait_fx()
	var expected = host_ui.state.events.size()
	check(expected > 0, label + "产生权威事件")
	check(host_ui.battle_fx.played_events == counts[0] + expected and guest_ui.battle_fx.played_events == counts[1] + expected, label + "双方每个事件只播放一次")
	check(host_ui.battle_fx.sound_count > counts[2] and guest_ui.battle_fx.sound_count > counts[3], label + "双方成功动作有音效")
	check(host_ui.battle_fx.played_ids == guest_ui.battle_fx.played_ids, label + "双方播放相同事件顺序")

func run() -> void:
	host_ui = Main.new()
	guest_ui = Main.new()
	root.add_child(host_ui)
	root.add_child(guest_ui)
	for ui in [host_ui, guest_ui]:
		ui.settings.animations = true
		ui.settings.sound = true
		ui.multiplayer_game = true
		ui._lobby()
	host_ui.net.host(0, "probe", "房主", host_ui.deck)
	guest_ui.net.join("127.0.0.1", host_ui.net.port, "probe", "访客", guest_ui.deck)
	await wait_for(func(): return guest_ui.net.online, "双端在线")
	host_ui.net.ready_up()
	guest_ui.net.ready_up()
	await wait_for(func(): return guest_ui.screen == "battle" and not guest_ui.state.is_empty(), "整备界面")
	check(host_ui.screen == "battle" and guest_ui.screen == "battle", "双方进入整备界面")
	check(host_ui.state.phase == "mulligan" and guest_ui.state.phase == "mulligan", "双方整备状态")
	check(host_ui.hud.confirm.visible and guest_ui.hud.confirm.visible, "双方换牌确认按钮可见")
	host_ui._confirm_mulligan()
	guest_ui._confirm_mulligan()
	await wait_for(func(): return guest_ui.state.phase == "battle", "双方换牌确认")
	check(guest_ui.state.mulligan_done == [true, true] and host_ui.state.phase == "battle", "双方确认后进入战斗")
	check(not guest_ui.hud.confirm.visible and not host_ui.hud.confirm.visible, "战斗隐藏换牌确认按钮")
	await wait_fx()
	# 用公开测试战场验证双方同一部署、攻击及技能表现，不依赖随机开局手牌。
	host_ui.net.game.players[0].hand = [{"uid":9000,"card":"medium_tank"}]
	host_ui.net.game.players[0].mana = 10
	host_ui.net._broadcast()
	await tick()
	await send_fx({"type":"play","hand":9000,"lane":3,"slot":5}, "部署")
	var tank = host_ui.net.game.players[0].board[0]
	var defender = host_ui.net.game.summon(1,"infantry",3,false,0)
	defender.hp = 30; defender.max_hp = 30
	tank.actions = 2
	tank.hp -= 2
	host_ui.net._broadcast()
	await tick()
	await send_fx({"type":"attack","unit":tank.uid,"target":defender.uid}, "攻击")
	await send_fx({"type":"skill","unit":tank.uid}, "技能")
	var counts_after = fx_counts()
	host_ui._accept_state(host_ui.state.duplicate(true))
	guest_ui._accept_state(guest_ui.state.duplicate(true))
	await tick()
	check(fx_counts() == counts_after, "重复live快照不重播音画")
	host_ui._send({"type":"attack","unit":999999,"target":defender.uid})
	await tick()
	check(fx_counts() == counts_after, "拒绝动作不播放成功音画")
	host_ui._send({"type": "end"})
	await wait_for(func(): return guest_ui.state.turn == 1, "访客回合")
	check(not guest_ui.action_list.is_empty(), "访客自己的行动预览可用")
	await wait_fx()
	check(not guest_ui.state.players[0].has("hand") and not host_ui.state.players[1].has("hand"), "UI视图隐藏对方手牌")
	check(not guest_ui.hud.end.disabled and not guest_ui.hud.retry.visible, "在线访客可结束回合且隐藏重试")
	var old_token = guest_ui.net._token
	var old_revision = guest_ui.state.revision
	var before_disconnect_fx = fx_counts()
	guest_ui.net._active = false
	guest_ui.net._client.disconnect_from_host()
	guest_ui.net._disconnected()
	guest_ui.net._active = false
	await wait_for(func(): return not host_ui.net.lobby[1].online, "断线识别")
	check(host_ui.hud.turn.text.contains("暂停"), "主机断线显示暂停")
	check(guest_ui.hud.turn.text.contains("暂停"), "访客断线显示暂停")
	check(guest_ui.hud.end.disabled and host_ui.hud.end.disabled, "断线双方禁用结束回合")
	check(guest_ui.hud.retry.visible and not guest_ui.hud.retry.disabled, "断线访客显示可用重试按钮")
	check(host_ui.hud.retry.visible and host_ui.hud.retry.disabled, "主机等待重连且禁用重试按钮")
	check(guest_ui.hud.concede.disabled and host_ui.hud.concede.disabled, "暂停双方禁用撤退")
	guest_ui.hud.retry.pressed.emit()
	await wait_for(func(): return guest_ui.net.online and host_ui.net.lobby[1].online, "重连")
	check(guest_ui.net._token == old_token and guest_ui.state.revision == old_revision, "重试保留token和当前revision")
	await tick()
	check(fx_counts() == before_disconnect_fx, "断线与重连基线不重播音画")
	check(not guest_ui.hud.retry.visible and not host_ui.hud.retry.visible, "重连双方隐藏重试按钮")
	check(not guest_ui.hud.end.disabled and not guest_ui.hud.turn.text.contains("暂停"), "访客重连恢复回合HUD")
	check(not guest_ui.hud.concede.disabled, "重连后撤退按钮可用")
	guest_ui.hud.concede.pressed.emit()
	await wait_for(func(): return guest_ui.state.winner != null, "撤退终局")
	check(guest_ui.state.winner == 0 and guest_ui.hud.rematch.visible and host_ui.hud.rematch.visible, "撤退按钮结算并显示双方再战")
	var old_match = host_ui.state.match_id
	host_ui.net.ready_up()
	guest_ui.net.ready_up()
	await wait_for(func(): return guest_ui.state.phase == "mulligan" and guest_ui.state.winner == null, "再战")
	check(host_ui.state.phase == "mulligan" and guest_ui.state.phase == "mulligan", "再战双方恢复整备")
	check(host_ui.state.revision == 0 and guest_ui.state.revision == 0, "再战revision重置")
	check(host_ui.state.match_id != old_match and guest_ui.state.match_id == host_ui.state.match_id, "再战双端新match_id")
	check(host_ui.battle_fx.pending_count() == 0 and guest_ui.battle_fx.pending_count() == 0, "再战基线清空旧局动画队列")
	check(host_ui.state.mulligan_done == [false, false] and guest_ui.state.mulligan_done == [false, false], "再战双方换牌确认重置")
	check(host_ui.hud.confirm.visible and guest_ui.hud.confirm.visible and not host_ui.hud.confirm.disabled and not guest_ui.hud.confirm.disabled, "再战双方换牌按钮可见可用")
	check(not host_ui.hud.rematch.visible and not guest_ui.hud.rematch.visible and not guest_ui.hud.retry.visible, "再战隐藏再战与重试按钮")
	host_ui.net.close()
	guest_ui.net.close()
	print("NETWORK UI PROBE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
