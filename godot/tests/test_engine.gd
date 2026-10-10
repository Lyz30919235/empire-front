extends SceneTree
const Rules = preload("res://scripts/engine.gd")
var checks = 0
var failures: Array = []
var groups: Array = []

func check(condition: bool, message: String):
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func group(name: String):
	groups.append(name)
	print("[规则] ",name)

func fresh():
	var g = Rules.new([],[],9)
	g.act(0,{"type":"mulligan","cards":[]})
	g.act(1,{"type":"mulligan","cards":[]})
	for p in g.players:
		p.board = []
		p.mana = 10
	return g

func add(g,p,key,l,slot=null):
	var u = g.summon(p,key,l,false,slot)
	check(u != null,"测试布局合法："+key)
	# 人工布局预算用于隔离其他规则；基础行动使用真实召唤和回合测试。
	if u != null: u.actions = 3
	return u

func give(g,key,p=0):
	g.players[p].hand = [{"uid":9000,"card":key}]
	return 9000

func ok(g,p,a):
	check(g.act(p,a).is_empty(),"合法动作成功："+JSON.stringify(a))

func reject(g,p,a):
	var state = [g.players.duplicate(true),g.phase,g.mulligan_done.duplicate(),g.turn,g.round,g.revision,g.winner,g.log.duplicate(),g.next_id,g.rng.state,g.events.duplicate(true),g.match_id]
	check(not g.act(p,a).is_empty(),"非法动作被拒绝："+JSON.stringify(a))
	check(state == [g.players,g.phase,g.mulligan_done,g.turn,g.round,g.revision,g.winner,g.log,g.next_id,g.rng.state,g.events,g.match_id],"非法动作完全不改变状态、事件及随机序列")

func valid_public_position(g,where) -> bool:
	if not where is Dictionary or where.get("owner") not in [0,1]: return false
	if where.get("base",false): return where.size()==2
	return where.size()==5 and g.integer(where.get("uid")) and where.get("card") in g.cards and g.slot_allowed(int(where.owner),int(where.get("lane",-1)),where.get("slot"))

func check_events(g):
	check(g.view(0).events==g.view(1).events,"双方事件公开内容一致")
	for i in range(g.events.size()):
		var e = g.events[i]
		check(e.match_id==g.match_id and e.revision==g.revision and e.index==i,"事件批次标识、版本和顺序")
		check(e.kind in ["deploy","move","attack","counter","skill","spell","damage","heal","buff","death","turn"],"事件种类公开约定")
		check(e.owner in [0,1] and (e.card.is_empty() or e.card in g.cards),"事件来源玩家和公开卡牌")
		check(valid_public_position(g,e.source),"每个事件保留公开来源位置")
		if e.has("target"): check(valid_public_position(g,e.target),"单目标位置有效")
		for target in e.get("targets",[]): check(valid_public_position(g,target),"多目标位置有效")
		if e.has("lane"): check(g.valid_lane(e.lane),"事件保留指定战线")
		for key in e: check(key in ["match_id","revision","index","kind","owner","card","source","target","targets","lane","skill","amount","label"],"事件不泄露私有数据："+key)

func event_kinds(g) -> Array:
	return g.events.map(func(e): return e.kind)

func check_slots(g):
	var occupied = {}
	for p in range(2):
		for u in g.players[p].board:
			check(g.slot_allowed(p,u.lane,u.slot),"单位只占合法公共或己方专属槽")
			var key = "%d:%d" % [u.lane,u.slot]
			check(not occupied.has(key),"双方单位不能重叠占同一槽位")
			occupied[key] = true

func _init():
	group("开局换牌、实体守恒与双人确认")
	var g = Rules.new([],[],23)
	check(g.cards.size()==26 and g.default_deck.size()==30,"26种卡与30张默认牌组")
	check(not g.validate_deck(["scout"]).is_empty(),"非法牌组拒绝")
	check(g.phase=="mulligan" and g.players[0].mana==0 and g.players[0].hand.size()==4,"开局无资源")
	reject(g,0,{"type":"end"})
	var old = g.players[0].hand.duplicate(true)
	for selection in [[old[0].uid,old[0].uid],[true],[1.25],"bad",[g.players[1].hand[0].uid]]:
		reject(g,0,{"type":"mulligan","cards":selection})
	g.players[0].deck = []
	for _i in range(26): g.players[0].deck.append("infantry")
	g.players[0].hand[0].card = "emperor"
	ok(g,0,{"type":"mulligan","cards":[float(old[0].uid)]})
	check(g.players[0].hand[0].card=="infantry" and "emperor" in g.players[0].deck,"先抽新牌后返还，不抽回刚换的实体")
	check(g.players[0].hand[1]==old[1] and g.players[0].hand.size()==4 and g.players[0].deck.size()==26,"未选手牌与总量守恒")
	reject(g,0,{"type":"mulligan","cards":[]})
	ok(g,1,{"type":"mulligan","cards":[]})
	check(g.turn==0 and g.phase=="battle" and g.players[0].mana==1 and g.players[0].hand.size()==4,"双方确认先手开始且不额外抽牌")
	group("隐藏信息与错误动作原子性")
	g = fresh()
	var visible = g.view(0)
	check(not visible.players[1].has("hand") and not visible.players[0].has("deck") and not visible.players[1].has("deck"),"双方牌堆与敌方手牌不泄露")
	visible.players[0].hp = 1
	check(g.players[0].hp==30,"视图深拷贝隔离")
	reject(g,1,{"type":"end"})
	reject(g,0,{"type":"bogus"})
	var ally = add(g,0,"infantry",3)
	give(g,"fireball")
	reject(g,0,{"type":"play","hand":9000,"target":ally.uid})
	for malformed in [true,"9000",9000.5,null]: reject(g,0,{"type":"play","hand":malformed,"target":ally.uid})
	group("基础行动：普通1、迅捷2，部署休眠与耗尽限制")
	for p in range(2):
		for scenario in [{"card":"infantry","budget":1,"assault":false},{"card":"heavy_cavalry","budget":1,"assault":true},{"card":"light_tank","budget":2,"assault":false},{"card":"light_cavalry","budget":2,"assault":true}]:
			g = fresh()
			g.turn = p
			var moving = g.summon(p,scenario.card,g.home_lane(p))
			var direction = -1 if p==0 else 1
			check(moving.actions==(scenario.budget if scenario.assault else 0),"部署行动预算："+scenario.card)
			if not scenario.assault:
				reject(g,p,{"type":"move","unit":moving.uid,"lane":moving.lane+direction})
			g.start_turn(p,false)
			check(moving.actions==scenario.budget,"回合基础行动："+scenario.card)
			for _i in range(scenario.budget):
				ok(g,p,{"type":"move","unit":moving.uid,"lane":moving.lane+direction})
			check(moving.actions==0,"移动耗尽基础行动："+scenario.card)
			reject(g,p,{"type":"move","unit":moving.uid,"lane":moving.lane-direction})
			g.start_turn(p,false)
			check(moving.actions==scenario.budget,"下一回合重新获得基础行动："+scenario.card)
	group("共享四线、后方部署、敌我共处与基地射程")
	for p in range(2):
		g = fresh()
		g.turn = p
		give(g,"light_cavalry",p)
		for l in range(4):
			if l != g.home_lane(p): reject(g,p,{"type":"play","hand":9000,"lane":l})
		reject(g,p,{"type":"play","hand":9000,"lane":1.5})
		ok(g,p,{"type":"play","hand":9000,"lane":float(g.home_lane(p))})
		var u = g.players[p].board[0]
		check(u.actions==2,"突袭迅捷部署两行动")
		check(not g.attack_error(p,u,"base").is_empty(),"近战必须推进才可攻击基地")
		var direction = -1 if p==0 else 1
		for _i in range(2): ok(g,p,{"type":"move","unit":float(u.uid),"lane":float(u.lane+direction)})
		reject(g,p,{"type":"move","unit":float(u.uid),"lane":float(u.lane+direction)})
		g.start_turn(p,false)
		ok(g,p,{"type":"move","unit":float(u.uid),"lane":float(u.lane+direction)})
		u.actions = 1
		check(g.attack_error(p,u,"base").is_empty(),"前线近战基地在射程内")
	g = fresh()
	ally = add(g,0,"light_cavalry",3)
	add(g,1,"scout",1)
	ok(g,0,{"type":"move","unit":ally.uid,"lane":2})
	ok(g,0,{"type":"move","unit":ally.uid,"lane":1})
	check(g.players[1].board[0].lane==ally.lane and g.players[1].board[0].slot!=ally.slot,"进入敌军战线并分别占槽")
	reject(g,0,{"type":"move","unit":ally.uid,"lane":3})
	ok(g,0,{"type":"move","unit":ally.uid,"lane":0})
	ally.actions = 1
	check(g.attack_error(0,ally,"base").is_empty(),"其他战线敌军不再保护基地")
	group("公共五槽、后方专属双槽、精确落位与失败原子性")
	for p in range(2):
		g = fresh()
		g.turn = p
		var rear = g.home_lane(p)
		var defender = add(g,p,"scout",rear)
		check(defender.slot==5,"后方自动优先首个专属槽")
		var intruder = add(g,1-p,"scout",rear)
		check(intruder.slot==0,"敌军只能使用后方公共槽")
		give(g,"scout",p)
		for bad_slot in [null,-1,7,1.25,"0",true,0]:
			reject(g,p,{"type":"play","hand":9000,"lane":rear,"slot":bad_slot})
		ok(g,p,{"type":"play","hand":9000,"lane":rear,"slot":6.0})
		check(g.players[p].board[-1].slot==6,"显式JSON整数浮点槽落位")
		for s in range(1,5): add(g,1-p,"scout",rear,s)
		check(g.available_slots(p,rear).is_empty(),"五公共槽加两本方专属槽共七槽")
		give(g,"scout",p)
		reject(g,p,{"type":"play","hand":9000,"lane":rear})
		check(g.summon(1-p,"scout",rear)==null,"敌军不能借用对方专属槽")
		check_slots(g)
		g = fresh()
		g.turn = p
		defender = add(g,p,"scout",rear,2)
		check(defender.slot==2 and g.find_slot(p,rear)==5,"允许先选公共槽，自动仍优先专属")
		check(g.summon(1-p,"scout",rear,false,5)==null,"衍生入口拒绝对方专属槽")
		var center = 2 if p==0 else 1
		var moving = add(g,p,"light_cavalry",rear)
		for bad_slot in [null,-1,5,6,7,0.5]: reject(g,p,{"type":"move","unit":moving.uid,"lane":center,"slot":bad_slot})
		ok(g,p,{"type":"move","unit":moving.uid,"lane":center,"slot":4})
		check(moving.slot==4,"移动服从显式公共槽")
		for s in range(4): add(g,1-p,"scout",center,s)
		check(g.available_slots(p,center).is_empty() and g.available_slots(1-p,center).is_empty(),"中间公共五槽由双方共享")
		moving = add(g,p,"light_cavalry",rear)
		reject(g,p,{"type":"move","unit":moving.uid,"lane":center})
		check(g.summon(p,"scout",center)==null,"中间第六单位召唤失败")
		check_slots(g)
	group("战斗、装甲、同时死亡、射程、飞行与嘲讽反击修复")
	g = fresh()
	ally = add(g,0,"heavy_tank",0)
	check(g.damage(ally,1)==0 and g.damage(ally,5)==3,"装甲逐次减伤")
	g = fresh()
	ally = add(g,0,"infantry",0)
	var enemy = add(g,1,"infantry",1)
	ally.hp = 3
	enemy.hp = 3
	ok(g,0,{"type":"attack","unit":ally.uid,"target":enemy.uid})
	check(g.players[0].board.is_empty() and g.players[1].board.is_empty(),"致死攻击仍同时反击")
	g = fresh()
	ally = add(g,0,"archer",0)
	enemy = add(g,1,"infantry",2)
	ok(g,0,{"type":"attack","unit":ally.uid,"target":enemy.uid})
	check(ally.hp==2 and enemy.hp==3,"远程打近战无跨距离反击")
	g = fresh()
	ally = add(g,0,"infantry",2)
	var shield = add(g,0,"shield",2)
	enemy = add(g,1,"infantry",1)
	check(not g.attack_error(1,enemy,ally.uid,true).is_empty(),"主动调度仍遵守嘲讽")
	ok(g,0,{"type":"attack","unit":ally.uid,"target":enemy.uid})
	check(ally.hp==2 and enemy.hp==2 and shield.hp==7,"反击不被攻击方同线嘲讽阻止")
	g = fresh()
	ally = add(g,0,"plane",3)
	enemy = add(g,1,"infantry",2)
	ok(g,0,{"type":"attack","unit":ally.uid,"target":"base"})
	check(g.players[1].hp==28,"飞机跨战场攻击基地")
	check(not g.attack_error(1,enemy,ally.uid).is_empty() and not g.attack_error(0,ally,enemy.uid).is_empty(),"近战不能对空、战机仅对空")
	add(g,1,"shield",0)
	reject(g,0,{"type":"attack","unit":ally.uid,"target":"base"})
	g = fresh()
	ally = add(g,0,"artillery",0)
	ok(g,0,{"type":"attack","unit":ally.uid,"target":"base"})
	g.start_turn(0,false)
	check(ally.actions==0 and not g.attack_error(0,ally,"base",true).is_empty(),"装弹跳过下个己方回合，塔不能绕过")
	g.start_turn(0,false)
	check(ally.actions==1 and g.attack_error(0,ally,"base").is_empty(),"再下回合恢复一行动")
	group("遗言、坦克恢复、帝皇光环与敢死队时限")
	g = fresh()
	ally = add(g,0,"hound",0)
	ally.hp = 0
	g.cleanup()
	var puppy = g.players[0].board[0]
	check(puppy.token and puppy.hp==2 and puppy.attack==2,"猎犬遗言产生2/2")
	puppy.hp = 0
	g.cleanup()
	check(g.players[0].board.is_empty(),"衍生猎犬不重复遗言")
	g = fresh()
	ally = add(g,0,"heavy_tank",0)
	enemy = add(g,0,"engineer",0)
	enemy.hp = 0
	g.cleanup()
	check(ally.attack==9 and ally.armor==3 and ally.max_hp==11,"工人强化机械攻击装甲上限")
	ally.hp = 7
	g.start_turn(0,false)
	check(ally.hp==9,"重型坦克恢复2")
	g = fresh()
	ally = add(g,0,"suicide",0)
	ok(g,0,{"type":"attack","unit":ally.uid,"target":"base"})
	ok(g,0,{"type":"attack","unit":ally.uid,"target":"base"})
	check(g.players[1].hp==18,"敢死队首击8后续4")
	g.start_turn(0,false)
	check(g.players[0].board.size()==1,"敢死队第一回合存活")
	g.start_turn(0,false)
	check(g.players[0].board.is_empty(),"敢死队第二己方回合阵亡")
	g = fresh()
	ally = add(g,0,"emperor",0)
	var infantry = add(g,0,"infantry",0)
	g.start_turn(0,false)
	check(infantry.attack==5 and infantry.actions==2,"帝皇光环在基础一行动上额外提升")
	ally.hp = 0
	g.cleanup()
	add(g,1,"infantry",1)
	g.start_turn(1,false)
	check(g.players[1].board.is_empty(),"帝皇遗命摧毁敌方单位")
	group("五种法术、商人战吼、航空母舰与高射炮")
	g = fresh()
	give(g,"loan")
	g.players[0].mana = 0
	ok(g,0,{"type":"play","hand":9000})
	check(g.players[0].mana==2 and g.players[0].debt==2,"借贷临时点数")
	g.start_turn(0,false)
	check(g.players[0].mana==0 and g.players[0].debt==0,"下回合还债")
	g = fresh()
	ally = add(g,0,"infantry",0)
	give(g,"banner")
	ok(g,0,{"type":"play","hand":9000,"lane":0})
	for _i in range(4): g.start_turn(0,false)
	check(ally.attack==9 and g.players[0].banners.is_empty(),"战旗恰好累积三次")
	g = fresh()
	enemy = add(g,1,"heavy_tank",1)
	give(g,"arrows")
	ok(g,0,{"type":"play","hand":9000,"lane":1})
	check(enemy.hp==9,"箭雨受装甲影响")
	give(g,"fireball")
	ok(g,0,{"type":"play","hand":9000,"target":enemy.uid})
	check(enemy.hp==5,"火球伤害6减装甲2")
	give(g,"heal")
	g.players[0].hp = 29
	ok(g,0,{"type":"play","hand":9000,"target":"base"})
	check(g.players[0].hp==30,"急救基地不超上限")
	g = fresh()
	g.players[0].deck = ["fireball","heavy_tank","scout","hound","loan"]
	give(g,"merchant")
	ok(g,0,{"type":"play","hand":9000})
	check(g.players[0].hand.size()==2 and g.players[0].hand[0].card=="scout" and g.players[0].hand[1].card=="hound","商人只抽费用最低随从、稳定同费顺序")
	g = fresh()
	give(g,"carrier")
	ok(g,0,{"type":"play","hand":9000})
	check(g.players[0].board.size()==4 and g.players[0].board.filter(func(u): return u.lane==3).size()==4,"母舰与三战机留在有足够槽的后方")
	g = fresh()
	give(g,"anti_air")
	ok(g,0,{"type":"play","hand":9000})
	ally = g.players[0].board[0]
	ally.actions = 2
	enemy = add(g,1,"plane",0)
	enemy.armor = 2
	enemy.hp = 10
	enemy.max_hp = 10
	ok(g,0,{"type":"attack","unit":ally.uid,"target":enemy.uid})
	check(ally.attack==8 and enemy.hp==2,"高射炮战吼攻击8及对空穿甲2")
	group("六种主动技能与冷却、一次性限制")
	g = fresh()
	ally = add(g,0,"heavy_cavalry",0)
	enemy = add(g,1,"infantry",1)
	ok(g,0,{"type":"skill","unit":ally.uid,"lane":1})
	check(enemy.hp==3,"冲锋全线伤害")
	for _i in range(2):
		g.start_turn(0,false)
		reject(g,0,{"type":"skill","unit":ally.uid,"lane":1})
	g.start_turn(0,false)
	ok(g,0,{"type":"skill","unit":ally.uid,"lane":1})
	check(enemy.hp==1,"第三个己方回合恢复技能")
	g = fresh()
	ally = add(g,0,"vanguard",3)
	infantry = add(g,0,"infantry",3)
	g.start_turn(0,false)
	ok(g,0,{"type":"skill","unit":ally.uid})
	check(infantry.attack==4 and infantry.actions==2 and "迅捷" in infantry.tags,"号令将同线普通单位由一行动提升到迅捷两行动")
	g.start_turn(0,false)
	reject(g,0,{"type":"skill","unit":ally.uid})
	g = fresh()
	ally = add(g,0,"medium_tank",3)
	ally.hp = 6
	g.start_turn(0,false)
	ok(g,0,{"type":"skill","unit":ally.uid})
	check(ally.hp==7 and ally.actions==0,"自修恢复1并耗尽基础一行动")
	g = fresh()
	ally = add(g,0,"factory",3)
	reject(g,0,{"type":"move","unit":ally.uid,"lane":2})
	reject(g,0,{"type":"skill","unit":ally.uid,"lane":2})
	reject(g,0,{"type":"skill","unit":ally.uid,"option":"plane"})
	ok(g,0,{"type":"skill","unit":ally.uid,"lane":3,"option":"medium_tank"})
	check(g.players[0].mana==7 and g.players[0].board[1].card=="medium_tank","工厂制造后方中坦扣3点")
	reject(g,0,{"type":"skill","unit":ally.uid,"lane":3})
	g = fresh()
	ally = add(g,0,"tower",0)
	infantry = add(g,0,"infantry",0)
	infantry.actions = 0
	ok(g,0,{"type":"skill","unit":ally.uid,"ally":infantry.uid,"target":"base"})
	check(g.players[1].hp==27 and infantry.actions==0,"决策塔不消耗被调度者行动")
	g = fresh()
	ally = add(g,0,"carrier",3)
	enemy = add(g,1,"heavy_tank",1)
	g.start_turn(0,false)
	ok(g,0,{"type":"skill","unit":ally.uid,"lane":1})
	check(enemy.hp==3 and ally.actions==0 and ally.cooldown==3,"空袭8伤害耗尽迅捷两行动")
	group("疲劳、手牌上限、撤退与终局")
	g = fresh()
	g.players[0].deck = []
	g.draw(0,3)
	check(g.players[0].hp==24,"递增疲劳1+2+3")
	ok(g,1,{"type":"concede"})
	check(g.winner==0,"非当前玩家可以撤退")
	reject(g,0,{"type":"end"})
	g = fresh()
	g.draw(0,20)
	check(g.players[0].hand.size()==10 and g.players[0].deck.size()==6,"满手烧牌仍消耗牌堆")
	test_arrow_events()
	test_spawn_slots()
	test_public_events()
	group("80局完整AI对战、全部卡牌覆盖与每步不变量")
	var wins = [0,0,0]
	var max_steps = 0
	var played = {}
	for seed_value in range(80):
		var builder = Rules.new([],[],seed_value)
		var decks = []
		for p in range(2):
			var pool = builder.cards.keys()
			pool.append_array(builder.cards.keys())
			builder.shuffle(pool)
			decks.append(pool.slice(0,30))
		g = Rules.new(decks,[],seed_value)
		var steps = 0
		while g.winner == null and steps < 1600:
			var action = g.ai_action(g.turn)
			if action.type=="play":
				for h in g.players[g.turn].hand:
					if h.uid==action.hand: played[h.card] = true
			var error = g.act(g.turn,JSON.parse_string(JSON.stringify(action)))
			check(error.is_empty(),"AI合法及JSON浮点输入 seed=%d step=%d error=%s" % [seed_value,steps,error])
			if not error.is_empty(): break
			for player in g.players:
				check(player.mana>=0 and player.hand.size()<=10,"资源及手牌不变量")
				for u in player.board: check(u.hp>0 and u.hp<=u.max_hp and u.actions>=0,"存活生命及行动不变量")
			check_slots(g)
			check_events(g)
			steps += 1
		check(g.winner!=null,"完成完整战役 seed=%d steps=%d" % [seed_value,steps])
		max_steps = maxi(max_steps,steps)
		if g.winner != null: wins[2 if g.winner==-1 else g.winner] += 1
	check(played.size()==26,"80局实际打出全部26种卡：%d" % played.size())
	print("[AI报告] 完成80局；先手胜=%d，后手胜=%d，平局=%d；最长=%d动作；实际打出=%d/26种卡" % [wins[0],wins[1],wins[2],max_steps,played.size()])
	print("[规则报告] 分组=%d；断言=%d；失败=%d" % [groups.size(),checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_arrow_events():
	group("箭雨明确选线、敌我混合、装甲与公开死亡事件")
	for p in range(2):
		var g = fresh()
		g.turn = p
		var ally = add(g,p,"infantry",1,0)
		var victim = add(g,1-p,"infantry",1,1)
		victim.hp = 2
		var armored = add(g,1-p,"heavy_tank",1,2)
		var outside = add(g,1-p,"scout",2,0)
		give(g,"arrows",p)
		reject(g,p,{"type":"play","hand":9000})
		for lane_value in [null,-1,4,1.5,"1",true,0,3]: reject(g,p,{"type":"play","hand":9000,"lane":lane_value})
		var actions = g.legal_actions(p).filter(func(a): return a.type=="play")
		check(actions.size()==2 and actions.all(func(a): return a.lane in [1,2]),"箭雨合法动作仅覆盖有敌军的线")
		check(g.ai_score(p,{"type":"play","hand":9000,"lane":1})>g.ai_score(p,{"type":"play","hand":9000,"lane":2}),"箭雨AI按目标线收益评分")
		var before = g.position(1-p,victim)
		ok(g,p,{"type":"play","hand":9000,"lane":1.0})
		check(g.players[p].mana==6 and g.players[p].hand.is_empty(),"箭雨保持费用4并移除手牌")
		check(ally.hp==ally.max_hp and outside.hp==outside.max_hp and armored.hp==armored.max_hp,"箭雨保护友军、其他线及足够装甲")
		check(g.unit(victim.uid)==null,"箭雨仅杀死所选线低血敌军")
		check(event_kinds(g)==["spell","damage","damage","death"],"箭雨发起、伤害、死亡批次顺序")
		check(g.events[0].card=="arrows" and g.events[0].targets.size()==2,"箭雨公开准确多目标")
		check(g.events[-1].source==before,"死亡单位仍有原槽位可供动画")
		check(g.events[1].card=="arrows" and g.events[1].amount==2 and g.events[2].amount==0,"伤害事件保留箭雨来源与装甲结果")
		check_events(g)

func test_spawn_slots():
	group("敌我共处时母舰衍生、工厂制造与猎犬遗言落位")
	for p in range(2):
		var g = fresh()
		g.turn = p
		var rear = g.home_lane(p)
		var front = rear+(-1 if p==0 else 1)
		for s in range(5): add(g,1-p,"scout",rear,s)
		add(g,1-p,"scout",front,0)
		give(g,"carrier",p)
		ok(g,p,{"type":"play","hand":9000,"lane":rear,"slot":5})
		check(g.players[p].board.filter(func(u): return u.lane==rear).size()==2 and g.players[p].board.filter(func(u): return u.lane==front).size()==2,"母舰优先后方空专属，随后衍生到敌我共处前线")
		check(g.players[p].board.filter(func(u): return u.card=="plane").size()==3,"公共及专属空位可召唤全部三战机")
		check_slots(g)
		check_events(g)
		g = fresh()
		g.turn = p
		for s in range(5): add(g,1-p,"scout",rear,s)
		for s in range(5): add(g,1-p,"scout",front,s)
		add(g,p,"scout",rear,6)
		give(g,"carrier",p)
		ok(g,p,{"type":"play","hand":9000,"lane":rear,"slot":5})
		check(g.players[p].board.size()==2 and not g.players[p].board.any(func(u): return u.card=="plane"),"两条线都满时母舰成功但不产生战机")
		g = fresh()
		g.turn = p
		var factory = add(g,p,"factory",rear)
		for s in range(5): add(g,1-p,"scout",rear,s)
		reject(g,p,{"type":"skill","unit":factory.uid,"lane":rear,"slot":0})
		reject(g,p,{"type":"skill","unit":factory.uid,"lane":rear,"slot":null})
		ok(g,p,{"type":"skill","unit":factory.uid,"lane":rear,"slot":6,"option":"medium_tank"})
		check(g.players[p].board[-1].slot==6 and g.players[p].mana==7,"敌军占公共槽不阻止指定空专属槽制造")
		check(event_kinds(g)==["skill","deploy"] and g.events[1].source.uid==factory.uid,"制造公开技能来源与坦克落位")
		g = fresh()
		g.turn = p
		factory = add(g,p,"factory",front)
		ok(g,p,{"type":"skill","unit":factory.uid})
		check(g.players[p].board[-1].lane==rear and g.events[0].lane==rear,"任意位置工厂省略战线时仍制造到己方后方")
		g = fresh()
		g.turn = p
		factory = add(g,p,"factory",rear)
		add(g,p,"scout",rear)
		for s in range(5): add(g,1-p,"scout",rear,s)
		reject(g,p,{"type":"skill","unit":factory.uid,"lane":rear})
		g = fresh()
		g.turn = 1-p
		var first = add(g,p,"hound",1,0)
		var second = add(g,p,"hound",1,1)
		add(g,p,"heavy_tank",1,2)
		add(g,1-p,"infantry",1,3)
		add(g,1-p,"infantry",1,4)
		give(g,"arrows",1-p)
		ok(g,1-p,{"type":"play","hand":9000,"lane":1})
		var puppies = g.players[p].board.filter(func(u): return u.card=="hound")
		check(puppies.size()==2 and puppies.all(func(u): return u.token and u.hp==2 and u.attack==2),"满混合战线同时死亡后遗言释放并重占两个公共槽")
		check(g.unit(first.uid)==null and g.unit(second.uid)==null and puppies[0].slot==0 and puppies[1].slot==1,"遗言不会与幸存敌军或另一个猎犬重叠")
		check(g.events.filter(func(e): return e.kind=="death").size()==2 and g.events.filter(func(e): return e.kind=="deploy").size()==2,"两只猎犬死亡及衍生均有公开事件")
		check_slots(g)
		check_events(g)

func test_public_events():
	group("新局标识、公开事件批次、快照隔离与被动效果")
	var g = Rules.new([],[],44)
	var another = Rules.new([],[],44)
	check(g.match_id!=another.match_id and g.match_id.length()==32,"每个新局有独立唯一标识")
	check(g.rng.state==another.rng.state,"新局标识不干扰规则随机序列")
	check(g.view(0).event_mode=="live" and g.events.is_empty(),"初始视图无尚未提交事件")
	ok(g,0,{"type":"mulligan","cards":[]})
	check(g.events.size()==1 and g.events[0].kind=="turn","整备指令也形成公开批次")
	reject(g,0,{"type":"mulligan","cards":[]})
	ok(g,1,{"type":"mulligan","cards":[]})
	check(g.events.all(func(e): return e.revision==g.revision),"成功指令替换批次而非追加历史")
	g = fresh()
	var moving = add(g,0,"light_cavalry",3,6)
	var before = g.position(0,moving)
	ok(g,0,{"type":"move","unit":moving.uid,"lane":2,"slot":4})
	check(g.events.size()==1 and g.events[0].source==before and g.events[0].target==g.position(0,moving),"移动事件同时保留起点和终点")
	var visible = g.view(1)
	visible.events[0].source.slot = 0
	check(g.events[0].source.slot==6,"视图深拷贝隔离事件位置")
	reject(g,0,{"type":"move","unit":moving.uid,"lane":2,"slot":1})
	ok(g,0,{"type":"move","unit":moving.uid,"lane":1})
	check(g.events.size()==1 and g.events[0].source.lane==2,"连续移动仅保留最后成功版本批次")
	g = fresh()
	var ally = add(g,0,"infantry",1,0)
	var enemy = add(g,1,"infantry",1,1)
	ally.hp = 3
	enemy.hp = 3
	var ally_before = g.position(0,ally)
	var enemy_before = g.position(1,enemy)
	ok(g,0,{"type":"attack","unit":ally.uid,"target":enemy.uid})
	check(event_kinds(g)==["attack","damage","counter","damage","death","death"],"同线致死攻击仍反击并按顺序记录双方死亡")
	check(g.events[0].source==ally_before and g.events[2].source==enemy_before,"攻击和反击保留各自公开来源")
	check(g.events[4].source==ally_before and g.events[5].source==enemy_before,"同时死亡保留两方槽位")
	check_events(g)
	g = fresh()
	give(g,"banner")
	ok(g,0,{"type":"play","hand":9000,"lane":1})
	check(g.events[0].lane==1 and g.events[0].targets.is_empty(),"空线战旗事件保留明确战线")
	var cavalry = add(g,0,"heavy_cavalry",3)
	ok(g,0,{"type":"skill","unit":cavalry.uid,"lane":0})
	check(g.events[0].lane==0 and g.events[0].targets.is_empty(),"空线冲锋仍合法且事件指向指定战线")
	g = fresh()
	ally = add(g,0,"infantry",0)
	add(g,1,"scout",0)
	add(g,1,"scout",2)
	ok(g,0,{"type":"attack","unit":ally.uid,"target":"base"})
	check(g.players[1].hp==27 and event_kinds(g)==["attack","damage"] and g.events[1].target==g.base_position(1),"同线及其他线非嘲讽敌军不阻挡射程内基地伤害")
	add(g,1,"shield",0)
	reject(g,0,{"type":"attack","unit":ally.uid,"target":"base"})
	g = fresh()
	ally = add(g,1,"heavy_tank",1)
	ally.hp = 3
	var factory = add(g,1,"factory",0)
	factory.hp = 4
	var expired = add(g,1,"suicide",2)
	expired.age = 1
	add(g,1,"emperor",0)
	g.players[1].banners = [{"lane":1,"remaining":3}]
	g.players[1].deck = []
	ok(g,0,{"type":"end"})
	check(g.events.any(func(e): return e.kind=="heal" and e.target.get("uid")==ally.uid and e.amount==2),"重坦回合恢复产生治疗事件")
	check(g.events.any(func(e): return e.kind=="heal" and e.target.get("uid")==factory.uid and e.amount==2),"工厂回合恢复产生治疗事件")
	check(g.events.any(func(e): return e.kind=="death" and e.source.uid==expired.uid),"敢死队时限产生死亡事件")
	check(g.events.any(func(e): return e.kind=="buff" and e.card=="emperor") and g.events.any(func(e): return e.kind=="buff" and e.card=="banner"),"帝皇和战旗被动产生强化事件")
	check(g.events.any(func(e): return e.kind=="damage" and e.target.get("base",false) and e.amount==1),"疲劳产生基地伤害事件")
	check_events(g)
	g = fresh()
	ally = add(g,0,"infantry",1)
	ally.hp = 2
	give(g,"heal")
	ok(g,0,{"type":"play","hand":9000,"target":ally.uid})
	check(event_kinds(g)==["spell","heal"] and g.events[1].amount==3 and g.events[1].card=="heal","单位法术治疗记录实际恢复及来源")
	g.players[0].hp = 29
	give(g,"heal")
	ok(g,0,{"type":"play","hand":9000,"target":"base"})
	check(g.events[1].amount==1 and g.events[1].target==g.base_position(0),"基地治疗按真实上限记录")
	g = fresh()
	ally = add(g,0,"medium_tank",1)
	ally.hp = 4
	ok(g,0,{"type":"skill","unit":ally.uid})
	check(event_kinds(g)==["skill","heal"] and g.events[1].skill=="repair","自修技能与治疗拥有相同公开技能名")
	check_events(g)
