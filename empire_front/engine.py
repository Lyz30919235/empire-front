"""权威规则引擎，无图形/网络依赖；所有操作先验证再结算。"""
import copy
import random
from .cards import CARDS, DEFAULT_DECK, MECHANICAL, validate_deck


class RuleError(ValueError):
    pass


class Game:
    def __init__(self, decks=None, names=None, seed=None):
        self.rng = random.Random(seed)
        self.next_id = 1
        self.turn = 0
        self.round = 1
        self.revision = 0
        self.winner = None
        self.phase = "mulligan"
        self.mulligan_done = [False, False]
        self.log = []
        self.players = []
        for i, deck in enumerate(decks or [DEFAULT_DECK, DEFAULT_DECK]):
            deck = validate_deck(deck)
            self.rng.shuffle(deck)
            self.players.append(dict(name=(names or ["指挥官", "对手"])[i], hp=30,
                                     deck=deck, hand=[], board=[], max_mana=0, mana=0,
                                     debt=0, fatigue=0, turns=0, banners=[], curse=False))
        self.draw(0, 4)
        self.draw(1, 4)
        self.note("开局整备：选择要替换的手牌，双方确认后开始战役。")

    def mulligan(self, p, selected):
        if self.phase != "mulligan" or self.mulligan_done[p]:
            raise RuleError("开局换牌已经确认，不能再次换牌。")
        if not isinstance(selected, list) or any(type(uid) is not int for uid in selected):
            raise RuleError("换牌列表必须由手牌编号组成。")
        if len(selected) != len(set(selected)):
            raise RuleError("同一张手牌不能重复选择。")
        player = self.players[p]
        hand_ids = {h["uid"] for h in player["hand"]}
        if not set(selected).issubset(hand_ids):
            raise RuleError("只能替换自己的初始手牌。")
        if len(selected) > len(player["deck"]):
            raise RuleError("牌堆没有足够的替换卡牌。")
        # 先从原有牌堆取新牌，再返还旧牌，确保不会抽回刚换掉的实体牌。
        self.rng.shuffle(player["deck"])
        returned = []
        selected_ids = set(selected)
        for i, old in enumerate(player["hand"]):
            if old["uid"] in selected_ids:
                returned.append(old["card"])
                player["hand"][i] = dict(uid=self.next_id, card=player["deck"].pop())
                self.next_id += 1
        player["deck"].extend(returned)
        self.rng.shuffle(player["deck"])
        self.mulligan_done[p] = True
        self.note(f"{player['name']}完成开局整备，替换{len(selected)}张手牌。")
        if all(self.mulligan_done):
            self.phase = "battle"
            self.start_turn(0, draw_card=False)
            self.note("战役开始：摧毁敌方基地取得胜利。")
        else:
            self.turn = next(i for i in range(2) if not self.mulligan_done[i])

    def note(self, message):
        self.log.append(message)
        self.log = self.log[-70:]

    def draw(self, p, count=1):
        player = self.players[p]
        for _ in range(count):
            if not player["deck"]:
                player["fatigue"] += 1
                player["hp"] -= player["fatigue"]
                self.note(f"{player['name']}受到{player['fatigue']}点疲劳伤害。")
            else:
                key = player["deck"].pop()
                if len(player["hand"]) < 10:
                    player["hand"].append(dict(uid=self.next_id, card=key))
                    self.next_id += 1
                else:
                    self.note(f"{player['name']}手牌已满，烧毁{CARDS[key]['name']}。")
        self.check_win()

    def check_win(self):
        dead = [i for i, p in enumerate(self.players) if p["hp"] <= 0]
        if dead:
            self.winner = -1 if len(dead) == 2 else 1 - dead[0]

    def unit(self, uid):
        for i, p in enumerate(self.players):
            for u in p["board"]:
                if u["uid"] == uid:
                    return i, u
        raise RuleError("这个单位已不在战场。")

    def lane(self, lane):
        if type(lane) is not int or not 0 <= lane < 4:
            raise RuleError("战线应为1至4。")
        return lane

    def space(self, p, lane):
        return not any(u["lane"] == lane for u in self.players[1-p]["board"]) and sum(u["lane"] == lane for u in self.players[p]["board"]) < 3

    @staticmethod
    def home_lane(p):
        """四条战线使用共享物理编号；玩家0后方为3，玩家1后方为0。"""
        return 3 if p == 0 else 0

    def deploy_error(self, p, lane):
        if lane != self.home_lane(p):
            return "普通单位只能在己方最后方战线部署，再逐线推进。"
        if not self.space(p,lane):
            return "己方后方战线已满或被敌方占据。"
        return None

    def summon(self, p, key, lane, token=False):
        if not self.space(p, lane):
            return None
        c = CARDS[key]
        u = dict(uid=self.next_id, card=key, lane=lane, attack=c["attack"],
                 hp=c["health"], max_hp=c["health"], armor=c.get("armor", 0),
                 tags=c["tags"][:], actions=(3 if "迅捷" in c["tags"] else 2) if "突袭" in c["tags"] else 0,
                 cooldown=0, reload=0, reloading=False, age=0, skill_used=False, first_attack=True, token=token)
        self.next_id += 1
        self.players[p]["board"].append(u)
        self.note(f"{self.players[p]['name']}在战线{lane + 1}部署{c['name']}。")
        return u

    def damage(self, u, amount, pierce=0):
        amount = max(0, amount - max(0, u["armor"] - pierce))
        u["hp"] -= amount
        return amount

    def cleanup(self):
        # 多轮处理遗言，允许遗言召唤，但不让新召唤单位参与已经结束的伤害。
        for _ in range(30):
            dead = [(p, u) for p in range(2) for u in self.players[p]["board"] if u["hp"] <= 0]
            if not dead:
                break
            for p, u in dead:
                self.players[p]["board"].remove(u)
            for p, u in dead:
                self.note(f"{CARDS[u['card']]['name']}阵亡。")
                if u["card"] == "hound" and not u["token"]:
                    puppy = self.summon(p, "hound", u["lane"], token=True)
                    if puppy:
                        puppy.update(attack=2, hp=2, max_hp=2)
                if u["card"] == "engineer":
                    candidates = [x for x in self.players[p]["board"] if x["card"] in MECHANICAL and x["hp"] > 0]
                    if candidates:
                        x = self.rng.choice(candidates)
                        x["attack"] += 1
                        x["armor"] += 1
                        x["hp"] += 2
                        x["max_hp"] += 2
                        self.note("工人遗言强化了一台友方机械。")
                if u["card"] == "emperor":
                    self.players[1 - p]["curse"] = True
                    self.note("帝皇遗命生效：敌方每回合将失去一个非帝皇单位。")
        self.check_win()

    def start_turn(self, p, draw_card=True):
        self.turn = p
        player = self.players[p]
        player["turns"] += 1
        player["max_mana"] = min(10, player["max_mana"] + 1)
        player["mana"] = max(0, player["max_mana"] - player["debt"])
        player["debt"] = 0
        for u in player["board"]:
            u["age"] += 1
            u["reloading"] = bool(u["reload"])
            u["actions"] = 0 if u["reloading"] else (3 if "迅捷" in u["tags"] else 2)
            u["reload"] = max(0, u["reload"] - 1)
            u["cooldown"] = max(0, u["cooldown"] - 1)
            if u["card"] != "vanguard":
                u["skill_used"] = False
            if u["card"] in {"heavy_tank", "factory"}:
                u["hp"] = min(u["max_hp"], u["hp"] + 2)
            if u["card"] == "suicide" and u["age"] >= 2:
                u["hp"] = 0
        self.cleanup()
        if player["curse"]:
            targets = [u for u in player["board"] if u["card"] != "emperor"]
            if targets:
                self.rng.choice(targets)["hp"] = 0
                self.cleanup()
        emperors = sum(u["card"] == "emperor" for u in player["board"])
        for u in player["board"]:
            if u["card"] != "emperor":
                u["attack"] += 2 * emperors
                if u["actions"]:
                    u["actions"] += emperors
        for b in player["banners"]:
            for u in player["board"]:
                if u["lane"] == b["lane"]:
                    u["attack"] += 2
                    if u["actions"]:
                        u["actions"] += 1
            b["remaining"] -= 1
        player["banners"] = [b for b in player["banners"] if b["remaining"] > 0]
        if draw_card:
            self.draw(p)
        self.note(f"第{self.round}轮 · {player['name']}的回合。")

    def attack_error(self, p, u, target, free=False, retaliation=False):
        if "建筑" in u["tags"] or u["attack"] <= 0:
            return "建筑或零攻击单位不能普攻。"
        if u["reload"] or u["reloading"]:
            return "此单位正在装弹。"
        if not free and u["actions"] < 1:
            return "此单位没有剩余行动。"
        enemies = self.players[1 - p]["board"]
        if target == "base":
            if any("嘲讽" in x["tags"] and x["lane"] == self.home_lane(1-p) for x in enemies):
                return "敌方后方战线有嘲讽单位保护基地。"
            if enemies and "飞行" not in u["tags"]:
                return "先清除敌方全部战场单位，才能攻击基地。"
            reach = 3 if "超远程" in u["tags"] else 2 if "远程" in u["tags"] else 1
            base_position = -1 if p == 0 else 4
            if "飞行" not in u["tags"] and abs(u["lane"]-base_position)>reach:
                return "基地超出射程，请沿战线向敌方推进。"
            return None
        try:
            owner, v = self.unit(target)
        except RuleError as e:
            return str(e)
        if owner == p:
            return "请选择敌方单位。"
        reach = 3 if "超远程" in u["tags"] else 2 if "远程" in u["tags"] else 1
        if abs(v["lane"] - u["lane"]) > reach:
            return "目标超出攻击范围。"
        if "仅对空" in u["tags"] and "飞行" not in v["tags"]:
            return "此单位只能攻击飞行单位或基地。"
        if "飞行" in v["tags"] and not any(t in u["tags"] for t in ["飞行", "远程", "超远程", "对空"]):
            return "地面近战无法攻击飞行单位。"
        if not retaliation and "嘲讽" not in v["tags"] and any("嘲讽" in x["tags"] and x["lane"] == v["lane"] for x in enemies):
            return "先攻击目标战线的嘲讽单位。"
        return None

    def attack(self, p, u, target, free=False):
        error = self.attack_error(p, u, target, free)
        if error:
            raise RuleError(error)
        if not free:
            u["actions"] -= 1
        amount = u["attack"] * (2 if u["card"] == "suicide" and u["first_attack"] else 1)
        u["first_attack"] = False
        if target == "base":
            self.players[1 - p]["hp"] -= amount
            self.note(f"{CARDS[u['card']]['name']}攻击敌方基地，造成{amount}点伤害。")
        else:
            _, v = self.unit(target)
            dealt = self.damage(v, amount, 2 if u["card"] == "anti_air" and "飞行" in v["tags"] else 0)
            # 普通单位近距离互相交战；反击关键字可跨距离还击。
            retaliate = abs(u["lane"] - v["lane"]) <= 1 or "反击" in v["tags"]
            can_hit = self.attack_error(1 - p, v, u["uid"], free=True, retaliation=True) is None
            back = self.damage(u, v["attack"]) if retaliate and can_hit else 0
            self.note(f"{CARDS[u['card']]['name']}攻击{CARDS[v['card']]['name']}：{dealt}伤害 / {back}反击。")
        if "装弹" in u["tags"]:
            u["reload"] = 1
            u["actions"] = 0
        self.cleanup()

    def play(self, p, action):
        player = self.players[p]
        hand = next((x for x in player["hand"] if x["uid"] == action.get("hand")), None)
        if not hand:
            raise RuleError("这张牌不在手中。")
        c = CARDS[hand["card"]]
        if c["cost"] > player["mana"]:
            raise RuleError("召唤点不足。")
        lane = action.get("lane", self.home_lane(p))
        target = action.get("target")
        victim = None
        if c["kind"] == "unit" or c.get("target") == "lane":
            self.lane(lane)
        if c["kind"] == "unit":
            error = self.deploy_error(p,lane)
            if error:
                raise RuleError(error)
        if c.get("target") in {"enemy", "friendly"}:
            if c["id"] == "heal" and target == "base":
                pass
            else:
                owner, victim = self.unit(target)
                expected = 1 - p if c["target"] == "enemy" else p
                if owner != expected:
                    raise RuleError("法术目标阵营错误。")
        player["mana"] -= c["cost"]
        player["hand"].remove(hand)
        if c["kind"] == "unit":
            u = self.summon(p, c["id"], lane)
            if c["id"] == "merchant":
                cheapest = sorted([k for k in player["deck"] if CARDS[k]["kind"] == "unit"], key=lambda k: CARDS[k]["cost"])[:2]
                for key in cheapest:
                    player["deck"].remove(key)
                    if len(player["hand"]) < 10:
                        player["hand"].append(dict(uid=self.next_id, card=key))
                        self.next_id += 1
            if c["id"] == "carrier":
                for _ in range(3):
                    # 空中衍生物可在己方后方或紧邻的友方前线整备，不越过敌人生成。
                    direction = -1 if p == 0 else 1
                    free = next((l for l in [lane,lane+direction] if 0<=l<4 and self.space(p,l)),None)
                    if free is not None:
                        self.summon(p, "plane", free, token=True)
            if c["id"] == "anti_air":
                u["attack"] += 2
        else:
            self.note(f"{player['name']}使用{c['name']}。")
            if c["id"] == "loan":
                player["mana"] += 2
                player["debt"] += 2
            elif c["id"] == "arrows":
                for u in self.players[1 - p]["board"]:
                    self.damage(u, 2)
            elif c["id"] == "fireball":
                self.damage(victim, 6)
            elif c["id"] == "heal":
                if victim:
                    victim["hp"] = min(victim["max_hp"], victim["hp"] + 3)
                else:
                    player["hp"] = min(30, player["hp"] + 3)
            elif c["id"] == "banner":
                player["banners"].append(dict(lane=lane, remaining=3))
        self.cleanup()

    def skill(self, p, u, action):
        key = CARDS[u["card"]].get("skill")
        if not key:
            raise RuleError("这个单位没有主动技能。")
        cost = 2 if key == "airstrike" else 1
        if u["actions"] < cost or u["reload"] or u["reloading"]:
            raise RuleError("技能需要足够行动，且不能处于装弹状态。")
        if u["cooldown"] or (u["skill_used"] and key in {"rally", "manufacture", "command"}):
            raise RuleError("技能处于冷却或已使用。")
        lane = action.get("lane", u["lane"])
        self.lane(lane)
        if key == "manufacture":
            option = action.get("option", "light_tank")
            if option not in {"light_tank", "medium_tank"}:
                raise RuleError("只能制造轻型或中型坦克。")
            mana = 2 if option == "light_tank" else 3
            if lane != self.home_lane(p):
                raise RuleError("制造的坦克必须进入己方最后方战线。")
            if self.players[p]["mana"] < mana or not self.space(p, lane):
                raise RuleError("召唤点不足或战线已满。")
        if key == "command":
            owner, ally = self.unit(action.get("ally"))
            if owner != p or ally is u:
                raise RuleError("请选择另一名友军执行调度。")
            error = self.attack_error(p, ally, action.get("target"), free=True)
            if error:
                raise RuleError(error)
        u["actions"] -= cost
        if key in {"charge", "airstrike"}:
            for enemy in self.players[1 - p]["board"]:
                if enemy["lane"] == lane:
                    self.damage(enemy, 2 if key == "charge" else 8)
            u["cooldown"] = 3  # 接下来两个自己的回合不可使用，第三个恢复。
        elif key == "rally":
            for ally in self.players[p]["board"]:
                if ally is not u and ally["lane"] == u["lane"]:
                    ally["attack"] += 1
                    if "迅捷" not in ally["tags"]:
                        ally["tags"].append("迅捷")
                        if ally["actions"]:
                            ally["actions"] += 1
            u["skill_used"] = True
        elif key == "repair":
            u["hp"] = min(u["max_hp"], u["hp"] + 1)
        elif key == "manufacture":
            self.players[p]["mana"] -= mana
            self.summon(p, option, lane)
            u["skill_used"] = True
        elif key == "command":
            self.attack(p, ally, action.get("target"), free=True)
            u["skill_used"] = True
        self.note(f"{CARDS[u['card']]['name']}发动技能。")
        self.cleanup()

    def act(self, p, action):
        if type(p) is not int or p not in (0, 1):
            raise RuleError("未知玩家。")
        if not isinstance(action, dict):
            raise RuleError("操作格式错误。")
        if self.winner is not None:
            raise RuleError("战役已结束。")
        if action.get("type") == "concede":
            self.winner = 1 - p
            self.note(f"{self.players[p]['name']}撤退。")
            self.revision += 1
            return
        if action.get("type") == "mulligan":
            self.mulligan(p, action.get("cards", []))
            self.revision += 1
            return
        if self.phase == "mulligan":
            raise RuleError("双方完成开局换牌后才能部署、行动或结束回合。")
        if self.turn != p:
            raise RuleError("请等待你的回合。")
        kind = action.get("type")
        if kind == "play":
            self.play(p, action)
        elif kind in {"attack", "move", "skill"}:
            owner, u = self.unit(action.get("unit"))
            if owner != p:
                raise RuleError("不能指挥敌方单位。")
            if kind == "attack":
                self.attack(p, u, action.get("target"))
            elif kind == "skill":
                self.skill(p, u, action)
            else:
                lane = self.lane(action.get("lane"))
                if "建筑" in u["tags"]:
                    raise RuleError("建筑不能移动。")
                if u["actions"] < 1 or u["reload"] or u["reloading"]:
                    raise RuleError("没有可用行动。")
                if abs(lane - u["lane"]) != 1:
                    raise RuleError("每次移动只能到相邻战线。")
                if not self.space(p, lane):
                    raise RuleError("目标战线已满或由敌方控制；先消灭其中的敌军。")
                u["lane"] = lane
                u["actions"] -= 1
                self.note(f"{CARDS[u['card']]['name']}移至战线{lane + 1}。")
        elif kind == "end":
            if p == 1:
                self.round += 1
            self.start_turn(1 - p)
        else:
            raise RuleError("未知操作。")
        self.check_win()
        self.revision += 1

    def view(self, p):
        result = dict(turn=self.turn, round=self.round, revision=self.revision, phase=self.phase,
                      mulligan_done=self.mulligan_done[:],
                      winner=self.winner, log=self.log[:], you=p, home_lane=self.home_lane(p), players=[])
        for i, player in enumerate(self.players):
            visible = {k: copy.deepcopy(v) for k, v in player.items() if k not in {"hand", "deck"}}
            visible["deck_count"] = len(player["deck"])
            visible["hand_count"] = len(player["hand"])
            if i == p:
                visible["hand"] = copy.deepcopy(player["hand"])
            result["players"].append(visible)
        return result

    def legal_actions(self, p):
        """用于练习AI以及回归测试；列出有效动作。"""
        if self.winner is not None:
            return []
        if self.phase == "mulligan":
            return [] if self.mulligan_done[p] else [dict(type="mulligan", cards=[])]
        if self.turn != p:
            return []
        player = self.players[p]
        targets = self.players[1 - p]["board"]
        actions = []
        for h in player["hand"]:
            c = CARDS[h["card"]]
            if c["cost"] > player["mana"]:
                continue
            base = dict(type="play", hand=h["uid"])
            if c["kind"] == "unit":
                home=self.home_lane(p)
                if self.deploy_error(p,home) is None:
                    actions.append(dict(base,lane=home))
            elif c.get("target") == "lane":
                actions.extend(dict(base, lane=l) for l in range(4))
            elif c.get("target") == "enemy":
                actions.extend(dict(base, target=u["uid"]) for u in targets)
            elif c.get("target") == "friendly":
                actions.append(dict(base, target="base"))
                actions.extend(dict(base, target=u["uid"]) for u in player["board"])
            else:
                actions.append(base)
        for u in player["board"]:
            if u["actions"] > 0:
                for target in ["base"] + [v["uid"] for v in targets]:
                    if self.attack_error(p, u, target) is None:
                        actions.append(dict(type="attack", unit=u["uid"], target=target))
                if "建筑" not in u["tags"] and not u["reload"] and not u["reloading"]:
                    for l in range(4):
                        if abs(l - u["lane"]) == 1 and self.space(p, l):
                            actions.append(dict(type="move", unit=u["uid"], lane=l))
                key = CARDS[u["card"]].get("skill")
                if key and not u["cooldown"] and not u["reload"] and not u["reloading"] and not (u["skill_used"] and key in {"rally", "manufacture", "command"}):
                    b = dict(type="skill", unit=u["uid"])
                    if key in {"repair", "rally"}:
                        actions.append(b)
                    elif key in {"charge", "airstrike"} and u["actions"] >= (2 if key == "airstrike" else 1):
                        actions.extend(dict(b, lane=l) for l in range(4) if any(v["lane"] == l for v in targets))
                    elif key == "manufacture":
                        for option, cost in [("light_tank", 2), ("medium_tank", 3)]:
                            if player["mana"] >= cost:
                                home=self.home_lane(p)
                                if self.space(p,home):
                                    actions.append(dict(b,option=option,lane=home))
                    elif key == "command":
                        for ally in player["board"]:
                            if ally is not u:
                                for target in ["base"] + [v["uid"] for v in targets]:
                                    if self.attack_error(p, ally, target, free=True) is None:
                                        actions.append(dict(b, ally=ally["uid"], target=target))
        actions.append(dict(type="end"))
        return actions

    def ai_action(self, p):
        if self.phase == "mulligan" and not self.mulligan_done[p]:
            return dict(type="mulligan", cards=[h["uid"] for h in self.players[p]["hand"] if CARDS[h["card"]]["cost"] >= 4])
        actions = self.legal_actions(p)
        def score(a):
            if a["type"] == "attack":
                _, u = self.unit(a["unit"])
                if a["target"] == "base":
                    return 100 + u["attack"]
                _, v = self.unit(a["target"])
                return 40 + (25 if u["attack"] >= v["hp"] + v["armor"] else 0) - (8 if v["attack"] >= u["hp"] + u["armor"] else 0)
            if a["type"] == "skill":
                return 38
            if a["type"] == "play":
                c = CARDS[next(h["card"] for h in self.players[p]["hand"] if h["uid"] == a["hand"])]
                if c["id"] == "heal":
                    if a["target"] == "base":
                        return 25 if self.players[p]["hp"] < 28 else -1
                    _, v = self.unit(a["target"])
                    return 26 if v["hp"] < v["max_hp"] else -1
                if c["id"] == "arrows" and not self.players[1 - p]["board"]:
                    return -1
                return 30 + c["cost"] + (0.2 * (3 - sum(u["lane"] == a.get("lane") for u in self.players[p]["board"])))
            if a["type"] == "move":
                _, u = self.unit(a["unit"])
                enemy_base=-1 if p==0 else 4
                before = min((abs(u["lane"] - v["lane"]) for v in self.players[1 - p]["board"]), default=abs(u["lane"]-enemy_base))
                after = min((abs(a["lane"] - v["lane"]) for v in self.players[1 - p]["board"]), default=abs(a["lane"]-enemy_base))
                if u["lane"]==self.home_lane(p) and a["lane"]!=u["lane"]:
                    return 13
                return 10 if after < before else -2
            return 0
        return max(actions, key=score) if actions else dict(type="end")
