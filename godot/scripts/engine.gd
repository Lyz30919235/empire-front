extends RefCounted
## 权威规则。所有可失败的动作都在扣费、移牌或消耗行动之前完成校验。
var cards: Dictionary
var default_deck: Array
var players: Array = []
var phase = "mulligan"
var mulligan_done = [false, false]
var turn = 0
var round = 1
var revision = 0
var match_id = ""
var events: Array = []
var _pending_events: Array = []
var _collecting_events = false
# 公开事件契约：view 仅包含最后成功 act/revision 的 events 批次；失败保留旧批次。
# {match_id,revision,index,kind,owner,card,source,target?,targets?,lane?,skill?,amount?,label?}
# 单位位置 {uid,owner,card,lane,slot}；基地 {base:true,owner}。source 永远存在，
# move.source/death.source 保留动作前位置；不复制 hand/deck/action/token 等私有字段。
# attack/counter/skill/spell 为发起事件，damage/heal/buff/death 为公开结果，按 index 播放。
var winner = null
var log: Array = []
var next_id = 1
var rng = RandomNumberGenerator.new()
const MECHANICAL = ["artillery", "carrier", "plane", "heavy_tank", "medium_tank", "light_tank", "anti_air", "factory", "tower"]

func _init(decks: Array = [], names: Array = [], seed_value: int = -1):
	match_id = Crypto.new().generate_random_bytes(16).hex_encode()
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/cards.json"))
	cards = data.cards
	default_deck = data.default_deck
	if seed_value < 0: rng.randomize()
	else: rng.seed = seed_value
	if decks.size() != 2: decks = [default_deck, default_deck]
	if names.size() != 2: names = ["指挥官", "对手"]
	for i in range(2):
		var deck = decks[i].duplicate() if validate_deck(decks[i]).is_empty() else default_deck.duplicate()
		shuffle(deck)
		players.append({"name":str(names[i]), "hp":30, "deck":deck, "hand":[], "board":[], "max_mana":0, "mana":0, "debt":0, "fatigue":0, "turns":0, "banners":[], "curse":false})
	draw(0, 4)
	draw(1, 4)
	note("开局整备：选择要替换的手牌，双方确认后开始战役。")

func validate_deck(deck) -> String:
	if not deck is Array or deck.size() != 30: return "牌组必须恰好30张。"
	var counts = {}
	for key in deck:
		if not key is String or not cards.has(key): return "牌组包含未知卡牌。"
		counts[key] = counts.get(key, 0) + 1
		if counts[key] > 2: return "同名卡牌最多放入两张。"
	return ""

func shuffle(a: Array):
	for i in range(a.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var value = a[i]
		a[i] = a[j]
		a[j] = value

func integer(value) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value) and abs(value) < 9007199254740992.0)

func valid_lane(value) -> bool:
	return integer(value) and value >= 0 and value < 4

func note(message: String):
	log.append(message)
	if log.size() > 70: log.pop_front()

func position(p: int, u: Dictionary) -> Dictionary:
	return {"uid":u.uid,"owner":p,"card":u.card,"lane":u.lane,"slot":u.slot}

func base_position(p: int) -> Dictionary:
	return {"base":true,"owner":p}

func event(kind: String, p: int, card: String, source: Dictionary, extras: Dictionary = {}):
	if not _collecting_events: return
	var entry = {"match_id":match_id,"revision":revision+1,"index":_pending_events.size(),"kind":kind,"owner":p,"card":card,"source":source.duplicate(true)}
	entry.merge(extras.duplicate(true), true)
	_pending_events.append(entry)

func effect_event(kind: String, target: Dictionary, amount: int, source: Dictionary = {}, skill_name: String = "", label: String = "", effect_card: String = ""):
	var origin = target if source.is_empty() else source
	var extras = {"target":target,"amount":amount}
	if not skill_name.is_empty(): extras.skill = skill_name
	if not label.is_empty(): extras.label = label
	event(kind,int(origin.owner),effect_card if not effect_card.is_empty() else str(origin.get("card","")),origin,extras)

func heal_unit(p: int, u: Dictionary, amount: int, source: Dictionary = {}, skill_name: String = "", label: String = "", effect_card: String = "") -> int:
	var healed = mini(u.max_hp-u.hp,amount)
	u.hp += healed
	effect_event("heal",position(p,u),healed,source,skill_name,label,effect_card)
	return healed

func heal_base(p: int, amount: int, source: Dictionary, card: String):
	var healed = mini(30-players[p].hp,amount)
	players[p].hp += healed
	event("heal",int(source.owner),card,source,{"target":base_position(p),"amount":healed})

func damage_base(p: int, amount: int, source: Dictionary, card: String, label: String = ""):
	players[p].hp -= amount
	event("damage",int(source.owner),card,source,{"target":base_position(p),"amount":amount,"label":label})

func draw(p: int, count: int = 1):
	var player = players[p]
	for _i in range(count):
		if player.deck.is_empty():
			player.fatigue += 1
			damage_base(p,player.fatigue,base_position(p),"","疲劳")
			note("%s受到%d点疲劳伤害。" % [player.name, player.fatigue])
		else:
			var key = player.deck.pop_back()
			if player.hand.size() < 10:
				player.hand.append({"uid":next_id, "card":key})
				next_id += 1
			else: note("%s手牌已满，烧毁%s。" % [player.name, cards[key].name])
	check_win()

func check_win():
	if players[0].hp <= 0 and players[1].hp <= 0: winner = -1
	elif players[0].hp <= 0: winner = 1
	elif players[1].hp <= 0: winner = 0

func unit(uid) -> Variant:
	if not integer(uid): return null
	for p in range(2):
		for u in players[p].board:
			if u.uid == uid: return [p, u]
	return null

func home_lane(p: int) -> int:
	return 3 if p == 0 else 0

func slot_allowed(p: int, lane_value: int, slot) -> bool:
	return p in [0,1] and valid_lane(lane_value) and integer(slot) and ((slot >= 0 and slot < 5) or (lane_value == home_lane(p) and slot >= 5 and slot < 7))

func slot_open(lane_value: int, slot: int) -> bool:
	for player in players:
		for u in player.board:
			if u.lane == lane_value and u.slot == slot: return false
	return true

func available_slots(p: int, lane_value: int) -> Array:
	if p not in [0,1] or not valid_lane(lane_value): return []
	var candidates = [5,6,0,1,2,3,4] if lane_value == home_lane(p) else [0,1,2,3,4]
	return candidates.filter(func(slot): return slot_open(lane_value,slot))

func find_slot(p: int, lane_value: int, requested = null) -> int:
	if requested != null:
		return int(requested) if slot_allowed(p,lane_value,requested) and slot_open(lane_value,int(requested)) else -1
	var slots = available_slots(p,lane_value)
	return -1 if slots.is_empty() else slots[0]

func space(p: int, lane_value: int, slot = null) -> bool:
	return find_slot(p,lane_value,slot) >= 0

func explicit_slot_error(p: int, lane_value: int, action: Dictionary) -> String:
	if not action.has("slot"): return ""
	if not slot_allowed(p,lane_value,action.slot): return "该槽位不存在或是对方专属槽。"
	if not slot_open(lane_value,int(action.slot)): return "指定槽位已被占用。"
	return ""

func deploy_error(p: int, lane_value: int, slot = null) -> String:
	if lane_value != home_lane(p): return "普通单位只能在己方最后方战线部署，再逐线推进。"
	if not space(p, lane_value,slot): return "己方后方没有可用槽位。"
	return ""

func summon(p: int, key: String, lane_value: int, token: bool = false, slot = null, source: Dictionary = {}) -> Variant:
	if not cards.has(key) or not valid_lane(lane_value): return null
	var assigned_slot = find_slot(p,lane_value,slot)
	if assigned_slot < 0: return null
	var c = cards[key]
	var u = {"uid":next_id, "card":key, "lane":lane_value, "slot":assigned_slot, "attack":int(c.attack), "hp":int(c.health), "max_hp":int(c.health), "armor":int(c.get("armor",0)), "tags":c.tags.duplicate(), "actions":(2 if "迅捷" in c.tags else 1) if "突袭" in c.tags else 0, "cooldown":0, "reload":0, "reloading":false, "age":0, "skill_used":false, "first_attack":true, "token":token}
	next_id += 1
	players[p].board.append(u)
	event("deploy",p,key,position(p,u) if source.is_empty() else source,{"target":position(p,u)})
	note("%s在战线%d部署%s。" % [players[p].name, lane_value+1, c.name])
	return u

func damage(u: Dictionary, amount: int, pierce: int = 0, source: Dictionary = {}, skill_name: String = "", effect_card: String = "") -> int:
	var dealt = maxi(0, amount - maxi(0, u.armor - pierce))
	u.hp -= dealt
	var found = unit(u.uid)
	if found != null: effect_event("damage",position(found[0],u),dealt,source,skill_name,"",effect_card)
	return dealt

func cleanup():
	for _i in range(30):
		var dead = []
		for p in range(2):
			for u in players[p].board:
				if u.hp <= 0: dead.append([p,u])
		if dead.is_empty(): break
		for item in dead: players[item[0]].board.erase(item[1])
		for item in dead:
			var p = item[0]
			var u = item[1]
			event("death",p,u.card,position(p,u))
			note("%s阵亡。" % cards[u.card].name)
			if u.card == "hound" and not u.token:
				var puppy = summon(p, "hound", u.lane, true,null,position(p,u))
				if puppy != null:
					puppy.attack = 2
					puppy.hp = 2
					puppy.max_hp = 2
					event("buff",p,u.card,position(p,u),{"target":position(p,puppy),"amount":1,"label":"遗言：2/2猎犬"})
			if u.card == "engineer":
				var candidates = players[p].board.filter(func(x): return x.card in MECHANICAL and x.hp > 0)
				if not candidates.is_empty():
					var x = candidates[rng.randi_range(0,candidates.size()-1)]
					x.attack += 1
					x.armor += 1
					x.hp += 2
					x.max_hp += 2
					event("buff",p,u.card,position(p,u),{"target":position(p,x),"amount":1,"label":"遗言：攻击+1、装甲+1、生命上限+2"})
					effect_event("heal",position(p,x),2,position(p,u),"","工人遗言")
					note("工人遗言强化了一台友方机械。")
			if u.card == "emperor":
				players[1-p].curse = true
				event("buff",p,u.card,position(p,u),{"target":base_position(1-p),"label":"帝皇遗命"})
				note("帝皇遗命生效：敌方每回合将失去一个非帝皇单位。")
	check_win()

func start_turn(p: int, draw_card: bool = true):
	turn = p
	var player = players[p]
	event("turn",p,"",base_position(p),{"label":"回合开始"})
	player.turns += 1
	player.max_mana = mini(10, player.max_mana+1)
	player.mana = maxi(0, player.max_mana-player.debt)
	player.debt = 0
	for u in player.board:
		u.age += 1
		u.reloading = bool(u.reload)
		u.actions = 0 if u.reloading else (2 if "迅捷" in u.tags else 1)
		u.reload = maxi(0,u.reload-1)
		u.cooldown = maxi(0,u.cooldown-1)
		if u.card != "vanguard": u.skill_used = false
		if u.card in ["heavy_tank","factory"]: heal_unit(p,u,2,position(p,u),"","回合恢复")
		if u.card == "suicide" and u.age >= 2:
			effect_event("damage",position(p,u),u.hp,position(p,u),"","敢死队时限")
			u.hp = 0
	cleanup()
	if player.curse:
		var targets = player.board.filter(func(u): return u.card != "emperor")
		if not targets.is_empty():
			var doomed = targets[rng.randi_range(0,targets.size()-1)]
			event("damage",1-p,"emperor",base_position(1-p),{"target":position(p,doomed),"amount":doomed.hp,"label":"帝皇遗命摧毁"})
			doomed.hp = 0
			cleanup()
	var emperors = player.board.filter(func(u): return u.card == "emperor").size()
	for u in player.board:
		if u.card != "emperor":
			u.attack += 2*emperors
			if u.actions: u.actions += emperors
			if emperors > 0:
				var emperor = player.board.filter(func(x): return x.card == "emperor")[0]
				event("buff",p,"emperor",position(p,emperor),{"target":position(p,u),"amount":2*emperors,"label":"帝皇光环"})
	for b in player.banners:
		for u in player.board:
			if u.lane == b.lane:
				u.attack += 2
				if u.actions: u.actions += 1
				event("buff",p,"banner",base_position(p),{"target":position(p,u),"amount":2,"label":"帝国战旗"})
		b.remaining -= 1
	player.banners = player.banners.filter(func(b): return b.remaining > 0)
	if draw_card: draw(p)
	note("第%d轮 · %s的回合。" % [round,player.name])

func attack_error(p: int, u: Dictionary, target, free: bool = false, retaliation: bool = false) -> String:
	if "建筑" in u.tags or u.attack <= 0: return "建筑或零攻击单位不能普攻。"
	if u.reload or u.reloading: return "此单位正在装弹。"
	if not free and u.actions < 1: return "此单位没有剩余行动。"
	var enemies = players[1-p].board
	var reach = 3 if "超远程" in u.tags else (2 if "远程" in u.tags else 1)
	if target is String and target == "base":
		for x in enemies:
			if "嘲讽" in x.tags and x.lane == home_lane(1-p): return "敌方后方战线有嘲讽单位保护基地。"
		if "飞行" not in u.tags and abs(u.lane-(-1 if p == 0 else 4)) > reach: return "基地超出射程，请沿战线向敌方推进。"
		return ""
	var found = unit(target)
	if found == null: return "这个单位已不在战场。"
	if found[0] == p: return "请选择敌方单位。"
	var v = found[1]
	if abs(v.lane-u.lane) > reach: return "目标超出攻击范围。"
	if "仅对空" in u.tags and "飞行" not in v.tags: return "此单位只能攻击飞行单位或基地。"
	if "飞行" in v.tags and not ("飞行" in u.tags or "远程" in u.tags or "超远程" in u.tags or "对空" in u.tags): return "地面近战无法攻击飞行单位。"
	if not retaliation and "嘲讽" not in v.tags:
		for x in enemies:
			if "嘲讽" in x.tags and x.lane == v.lane: return "先攻击目标战线的嘲讽单位。"
	return ""

func attack(p: int, u: Dictionary, target, free: bool = false) -> String:
	var error = attack_error(p,u,target,free)
	if not error.is_empty(): return error
	if not free: u.actions -= 1
	var amount = u.attack*(2 if u.card == "suicide" and u.first_attack else 1)
	u.first_attack = false
	var source = position(p,u)
	if target is String and target == "base":
		event("attack",p,u.card,source,{"target":base_position(1-p),"amount":amount})
		damage_base(1-p,amount,source,u.card)
		note("%s攻击敌方基地，造成%d点伤害。" % [cards[u.card].name,amount])
	else:
		var v = unit(target)[1]
		event("attack",p,u.card,source,{"target":position(1-p,v),"amount":amount})
		var dealt = damage(v,amount,2 if u.card == "anti_air" and "飞行" in v.tags else 0,source)
		var back = 0
		if (abs(u.lane-v.lane) <= 1 or "反击" in v.tags) and attack_error(1-p,v,u.uid,true,true).is_empty():
			event("counter",1-p,v.card,position(1-p,v),{"target":source,"amount":v.attack})
			back = damage(u,v.attack,0,position(1-p,v))
		note("%s攻击%s：%d伤害 / %d反击。" % [cards[u.card].name,cards[v.card].name,dealt,back])
	if "装弹" in u.tags:
		u.reload = 1
		u.actions = 0
	cleanup()
	return ""

func mulligan(p: int, selected) -> String:
	if phase != "mulligan" or mulligan_done[p]: return "开局换牌已经确认，不能再次换牌。"
	if not selected is Array: return "换牌列表必须由手牌编号组成。"
	var chosen = {}
	for uid in selected:
		if not integer(uid): return "换牌列表必须由手牌编号组成。"
		if chosen.has(int(uid)): return "同一张手牌不能重复选择。"
		chosen[int(uid)] = true
	var player = players[p]
	for uid in chosen:
		if player.hand.filter(func(h): return h.uid == uid).is_empty(): return "只能替换自己的初始手牌。"
	if selected.size() > player.deck.size(): return "牌堆没有足够的替换卡牌。"
	shuffle(player.deck)
	var returned = []
	for i in range(player.hand.size()):
		if chosen.has(player.hand[i].uid):
			returned.append(player.hand[i].card)
			player.hand[i] = {"uid":next_id,"card":player.deck.pop_back()}
			next_id += 1
	player.deck.append_array(returned)
	shuffle(player.deck)
	mulligan_done[p] = true
	event("turn",p,"",base_position(p),{"label":"开局整备完成"})
	note("%s完成开局整备，替换%d张手牌。" % [player.name,selected.size()])
	if mulligan_done[0] and mulligan_done[1]:
		phase = "battle"
		start_turn(0,false)
		note("战役开始：摧毁敌方基地取得胜利。")
	else: turn = 1-p
	return ""

func play(p: int, action: Dictionary) -> String:
	var player = players[p]
	var h = null
	if integer(action.get("hand")):
		for x in player.hand:
			if x.uid == action.hand: h = x
	if h == null: return "这张牌不在手中。"
	var c = cards[h.card]
	if c.cost > player.mana: return "召唤点不足。"
	var lane_value = action.get("lane",home_lane(p))
	var target = action.get("target")
	var victim = null
	if c.id == "arrows" and not action.has("lane"): return "箭雨必须指定一条战线。"
	if c.kind == "unit" or c.get("target") == "lane":
		if not valid_lane(lane_value): return "战线应为1至4。"
		lane_value = int(lane_value)
	if c.kind == "unit":
		var slot_error = explicit_slot_error(p,lane_value,action)
		if not slot_error.is_empty(): return slot_error
		var error = deploy_error(p,lane_value,action.get("slot"))
		if not error.is_empty(): return error
	if c.id == "arrows" and players[1-p].board.filter(func(u): return u.lane == lane_value).is_empty(): return "箭雨目标战线必须有敌方单位。"
	if c.get("target") in ["enemy","friendly"]:
		if not (c.id == "heal" and target is String and target == "base"):
			var found = unit(target)
			if found == null: return "这个单位已不在战场。"
			if found[0] != (1-p if c.target == "enemy" else p): return "法术目标阵营错误。"
			victim = found[1]
	player.mana -= int(c.cost)
	player.hand.erase(h)
	if c.kind == "unit":
		var u = summon(p,c.id,lane_value,false,action.get("slot"))
		if c.id == "merchant":
			var cheapest = player.deck.filter(func(k): return cards[k].kind == "unit")
			cheapest.sort_custom(func(a,b): return cards[a].cost < cards[b].cost)
			for key in cheapest.slice(0,2):
				player.deck.erase(key)
				if player.hand.size() < 10:
					player.hand.append({"uid":next_id,"card":key})
					next_id += 1
		if c.id == "carrier":
			for _i in range(3):
				for l in [lane_value,lane_value+(-1 if p == 0 else 1)]:
					if valid_lane(l) and space(p,l):
						summon(p,"plane",l,true,null,position(p,u))
						break
		if c.id == "anti_air":
			u.attack += 2
			event("buff",p,u.card,position(p,u),{"target":position(p,u),"amount":2,"label":"部署攻击+2"})
	else:
		note("%s使用%s。" % [player.name,c.name])
		var source = base_position(p)
		var spell_targets: Array = []
		if c.id == "arrows":
			for enemy in players[1-p].board:
				if enemy.lane == lane_value: spell_targets.append(position(1-p,enemy))
		elif victim != null: spell_targets.append(position(1-p if c.get("target") == "enemy" else p,victim))
		elif c.id == "heal": spell_targets.append(base_position(p))
		var spell_extras = {"targets":spell_targets,"label":c.name}
		if c.get("target") == "lane": spell_extras.lane = lane_value
		event("spell",p,c.id,source,spell_extras)
		match c.id:
			"loan":
				player.mana += 2
				player.debt += 2
				event("buff",p,c.id,source,{"target":source,"amount":2,"label":"临时召唤点+2"})
			"arrows":
				for u in players[1-p].board:
					if u.lane == lane_value: damage(u,2,0,source,"",c.id)
			"fireball":
				damage(victim,6,0,source,"",c.id)
			"heal":
				if victim != null: heal_unit(p,victim,3,source,"","",c.id)
				else: heal_base(p,3,source,c.id)
			"banner": player.banners.append({"lane":lane_value,"remaining":3})
	cleanup()
	return ""

func skill(p: int, u: Dictionary, action: Dictionary) -> String:
	var key = cards[u.card].get("skill", "")
	if key.is_empty(): return "这个单位没有主动技能。"
	var cost = 2 if key == "airstrike" else 1
	if u.actions < cost or u.reload or u.reloading: return "技能需要足够行动，且不能处于装弹状态。"
	if u.cooldown or (u.skill_used and key in ["rally","manufacture","command"]): return "技能处于冷却或已使用。"
	var lane_value = action.get("lane",home_lane(p) if key == "manufacture" else u.lane)
	if not valid_lane(lane_value): return "战线应为1至4。"
	lane_value = int(lane_value)
	var option = action.get("option","light_tank")
	var mana = 2 if option == "light_tank" else 3
	var ally = null
	if key == "manufacture":
		if option not in ["light_tank","medium_tank"]: return "只能制造轻型或中型坦克。"
		if lane_value != home_lane(p): return "制造的坦克必须进入己方最后方战线。"
		var slot_error = explicit_slot_error(p,lane_value,action)
		if not slot_error.is_empty(): return slot_error
		if players[p].mana < mana or not space(p,lane_value,action.get("slot")): return "召唤点不足或战线没有可用槽位。"
	if key == "command":
		var found = unit(action.get("ally"))
		if found == null: return "这个单位已不在战场。"
		ally = found[1]
		if found[0] != p or ally.uid == u.uid: return "请选择另一名友军执行调度。"
		var error = attack_error(p,ally,action.get("target"),true)
		if not error.is_empty(): return error
	var source = position(p,u)
	var skill_targets: Array = []
	if key in ["charge","airstrike"]:
		for enemy in players[1-p].board:
			if enemy.lane == lane_value: skill_targets.append(position(1-p,enemy))
	elif key == "rally":
		for other in players[p].board:
			if other.uid != u.uid and other.lane == u.lane: skill_targets.append(position(p,other))
	elif key == "repair": skill_targets.append(source)
	elif key == "command": skill_targets.append(base_position(1-p) if action.get("target") is String else position(1-p,unit(action.target)[1]))
	var skill_extras = {"skill":key,"targets":skill_targets}
	if key in ["charge","airstrike","manufacture"]: skill_extras.lane = lane_value
	event("skill",p,u.card,source,skill_extras)
	u.actions -= cost
	match key:
		"charge", "airstrike":
			for enemy in players[1-p].board:
				if enemy.lane == lane_value: damage(enemy,2 if key == "charge" else 8,0,source,key)
			u.cooldown = 3
		"rally":
			for other in players[p].board:
				if other.uid != u.uid and other.lane == u.lane:
					other.attack += 1
					if "迅捷" not in other.tags:
						other.tags.append("迅捷")
						if other.actions: other.actions += 1
					event("buff",p,u.card,source,{"target":position(p,other),"skill":key,"amount":1,"label":"攻击+1、迅捷"})
			u.skill_used = true
		"repair": heal_unit(p,u,1,source,key)
		"manufacture":
			players[p].mana -= mana
			summon(p,option,lane_value,false,action.get("slot"),source)
			u.skill_used = true
		"command":
			attack(p,ally,action.get("target"),true)
			u.skill_used = true
	note("%s发动技能。" % cards[u.card].name)
	cleanup()
	return ""

func act(p: int, action: Dictionary) -> String:
	_pending_events = []
	_collecting_events = true
	var error = _apply_action(p,action)
	_collecting_events = false
	if error.is_empty():
		events = _pending_events.duplicate(true)
	_pending_events = []
	return error

func _apply_action(p: int, action: Dictionary) -> String:
	if p not in [0,1]: return "未知玩家。"
	if winner != null: return "战役已结束。"
	var kind = action.get("type")
	var error = ""
	if kind == "concede":
		winner = 1-p
		event("turn",p,"",base_position(p),{"label":"撤退"})
		note("%s撤退。" % players[p].name)
	elif kind == "mulligan": error = mulligan(p,action.get("cards",[]))
	else:
		if phase == "mulligan": return "双方完成开局换牌后才能部署、行动或结束回合。"
		if turn != p: return "请等待你的回合。"
		if kind == "play": error = play(p,action)
		elif kind in ["attack","move","skill"]:
			var found = unit(action.get("unit"))
			if found == null: return "这个单位已不在战场。"
			if found[0] != p: return "不能指挥敌方单位。"
			var u = found[1]
			if kind == "attack": error = attack(p,u,action.get("target"))
			elif kind == "skill": error = skill(p,u,action)
			else:
				var l = action.get("lane")
				if not valid_lane(l): return "战线应为1至4。"
				if "建筑" in u.tags: return "建筑不能移动。"
				if u.actions < 1 or u.reload or u.reloading: return "没有可用行动。"
				if abs(l-u.lane) != 1: return "每次移动只能到相邻战线。"
				var slot_error = explicit_slot_error(p,int(l),action)
				if not slot_error.is_empty(): return slot_error
				var assigned_slot = find_slot(p,int(l),action.get("slot"))
				if assigned_slot < 0: return "目标战线没有可用槽位。"
				var before = position(p,u)
				u.lane = int(l)
				u.slot = assigned_slot
				u.actions -= 1
				event("move",p,u.card,before,{"target":position(p,u)})
				note("%s移至战线%d。" % [cards[u.card].name,int(l)+1])
		elif kind == "end":
			if p == 1: round += 1
			start_turn(1-p)
		else: return "未知操作。"
	if not error.is_empty(): return error
	check_win()
	revision += 1
	return ""

func view(p: int) -> Dictionary:
	var result = {"match_id":match_id,"events":events.duplicate(true),"event_mode":"live","turn":turn,"round":round,"revision":revision,"phase":phase,"mulligan_done":mulligan_done.duplicate(),"winner":winner,"log":log.duplicate(),"you":p,"home_lane":home_lane(p),"players":[]}
	for i in range(2):
		var visible = players[i].duplicate(true)
		visible.erase("deck")
		visible.erase("hand")
		visible.deck_count = players[i].deck.size()
		visible.hand_count = players[i].hand.size()
		if i == p: visible.hand = players[i].hand.duplicate(true)
		result.players.append(visible)
	return result

func legal_actions(p: int) -> Array:
	if p not in [0,1] or winner != null: return []
	if phase == "mulligan": return [] if mulligan_done[p] else [{"type":"mulligan","cards":[]}]
	if turn != p: return []
	var player = players[p]
	var enemies = players[1-p].board
	var targets: Array = ["base"]
	for v in enemies: targets.append(v.uid)
	var actions = []
	for h in player.hand:
		var c = cards[h.card]
		if c.cost > player.mana: continue
		var b = {"type":"play","hand":h.uid}
		if c.kind == "unit":
			if deploy_error(p,home_lane(p)).is_empty(): append_slot_actions(actions,b,p,home_lane(p))
		elif c.get("target") == "lane":
			for l in range(4):
				if c.id != "arrows" or not enemies.filter(func(u): return u.lane == l).is_empty(): actions.append(dict_with(b,{"lane":l}))
		elif c.get("target") == "enemy":
			for v in enemies: actions.append(dict_with(b,{"target":v.uid}))
		elif c.get("target") == "friendly":
			actions.append(dict_with(b,{"target":"base"}))
			for u in player.board: actions.append(dict_with(b,{"target":u.uid}))
		else: actions.append(b)
	for u in player.board:
		if u.actions <= 0: continue
		for target in targets:
			if attack_error(p,u,target).is_empty(): actions.append({"type":"attack","unit":u.uid,"target":target})
		if "建筑" not in u.tags and not u.reload and not u.reloading:
			for l in range(4):
				if abs(l-u.lane) == 1 and space(p,l): append_slot_actions(actions,{"type":"move","unit":u.uid},p,l)
		var key = cards[u.card].get("skill","")
		if key.is_empty() or u.cooldown or u.reload or u.reloading or (u.skill_used and key in ["rally","manufacture","command"]): continue
		var b = {"type":"skill","unit":u.uid}
		if key in ["repair","rally"]: actions.append(b)
		elif key in ["charge","airstrike"] and u.actions >= (2 if key == "airstrike" else 1):
			for l in range(4):
				if not enemies.filter(func(v): return v.lane == l).is_empty(): actions.append(dict_with(b,{"lane":l}))
		elif key == "manufacture":
			for option in ["light_tank","medium_tank"]:
				if player.mana >= (2 if option == "light_tank" else 3) and space(p,home_lane(p)): append_slot_actions(actions,dict_with(b,{"option":option}),p,home_lane(p))
		elif key == "command":
			for ally in player.board:
				if ally.uid == u.uid: continue
				for target in targets:
					if attack_error(p,ally,target,true).is_empty(): actions.append(dict_with(b,{"ally":ally.uid,"target":target}))
	actions.append({"type":"end"})
	return actions

func append_slot_actions(actions: Array, action: Dictionary, p: int, lane_value: int):
	actions.append(dict_with(action,{"lane":lane_value}))
	for slot in available_slots(p,lane_value): actions.append(dict_with(action,{"lane":lane_value,"slot":slot}))

func dict_with(base: Dictionary, extras: Dictionary) -> Dictionary:
	var result = base.duplicate()
	result.merge(extras,true)
	return result

func ai_action(p: int) -> Dictionary:
	if phase == "mulligan" and not mulligan_done[p]:
		var selected = []
		for h in players[p].hand:
			if cards[h.card].cost >= 4: selected.append(h.uid)
		return {"type":"mulligan","cards":selected}
	var actions = legal_actions(p)
	var best = {"type":"end"}
	var score = -INF
	for a in actions:
		var value = ai_score(p,a)
		if value > score:
			score = value
			best = a
	return best

func ai_score(p: int, a: Dictionary) -> float:
	if a.type == "attack":
		var u = unit(a.unit)[1]
		if a.target is String and a.target == "base": return 100+u.attack
		var v = unit(a.target)[1]
		return 40+(25 if u.attack >= v.hp+v.armor else 0)-(8 if v.attack >= u.hp+u.armor else 0)
	if a.type == "skill": return 38
	if a.type == "play":
		var c = {}
		for h in players[p].hand:
			if h.uid == a.hand: c = cards[h.card]
		if c.id == "heal":
			if a.target is String and a.target == "base": return 25 if players[p].hp < 28 else -1
			var v = unit(a.target)[1]
			return 26 if v.hp < v.max_hp else -1
		if c.id == "arrows":
			var score = 20.0
			for enemy in players[1-p].board:
				if enemy.lane == a.lane:
					var dealt = maxi(0,2-enemy.armor)
					score += dealt*5 + (15 if dealt >= enemy.hp else 0)
			return score
		var remaining = available_slots(p,int(a.get("lane",home_lane(p)))).size()
		return 30+c.cost+0.2*remaining
	if a.type == "move":
		var u = unit(a.unit)[1]
		var base = -1 if p == 0 else 4
		var before = abs(u.lane-base)
		var after = abs(a.lane-base)
		if not players[1-p].board.is_empty():
			before = 10
			after = 10
			for v in players[1-p].board:
				before = mini(before,abs(u.lane-v.lane))
				after = mini(after,abs(a.lane-v.lane))
		if u.lane == home_lane(p): return 13
		return 10 if after < before else -2
	return 0
