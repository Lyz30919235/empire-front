"""从手稿整理的卡牌。此表是所有卡牌数值的唯一来源。"""
from collections import Counter


def card(key, name, cost, attack=0, health=0, tags=(), text="", **extra):
    return dict(id=key, name=name, cost=cost, attack=attack, health=health,
                tags=list(tags), text=text, kind="unit" if health else "spell", **extra)


CARDS = {c["id"]: c for c in [
    card("scout", "帝国侦察兵", 1, 1, 2, ("防御1",), "受到伤害时减少1点伤害。", armor=1),
    card("archer", "帝国弓箭手", 2, 2, 2, ("远程", "反击"), "可攻击相距2条战线内的目标；受到单位攻击时反击。"),
    card("light_cavalry", "帝国轻骑兵", 2, 2, 4, ("突袭", "迅捷"), "部署即可行动，每回合3次行动。"),
    card("heavy_cavalry", "帝国重骑兵", 4, 4, 7, ("突袭",), "技能·冲锋：对一条敌方战线全部单位造成2点伤害。消耗1行动，冷却2回合。", skill="charge"),
    card("vanguard", "帝国冲锋手", 3, 2, 3, (), "技能·号令：同线其他友军攻击+1，获得迅捷。本单位每局限一次，消耗1行动。", skill="rally"),
    card("infantry", "帝国重步兵", 2, 3, 5, (), "可靠的主力步兵。"),
    card("hound", "帝国猎犬", 1, 1, 2, (), "遗言：召唤一只2/2帝国猎犬（无遗言）。"),
    card("loan", "借贷", 0, text="本回合获得2点临时召唤点；下个自己的回合扣除2点可用召唤点。"),
    card("arrows", "箭雨", 4, text="对所有敌方场上单位造成2点伤害。"),
    card("fireball", "火球术", 4, text="对一个敌方单位造成6点伤害。", target="enemy"),
    card("merchant", "帝国商人", 3, 1, 3, (), "战吼：从牌库抽取至多两张费用最低的随从。"),
    card("banner", "帝国战旗", 3, text="指定一条战线：连续3个自己的回合开始时，该线友军攻击+2、行动+1。", target="lane"),
    card("heal", "急救", 2, text="恢复一个友方单位或自己基地3点生命。", target="friendly"),
    card("shield", "帝国重盾兵", 4, 1, 7, ("防御1", "远程", "嘲讽"), "同线有此单位时，敌人必须优先攻击它。", armor=1),
    card("artillery", "帝国榴弹炮", 5, 5, 5, ("装弹", "超远程", "反击"), "攻击覆盖全部战线；攻击后下个自己的回合无法行动。"),
    card("carrier", "帝国航空母舰", 7, 4, 10, ("迅捷",), "战吼：在己方后方及紧邻前线召唤至多3个帝国战机。技能·空袭：对一条敌方战线造成8点伤害，消耗2行动，冷却2回合。", skill="airstrike"),
    card("plane", "帝国战机", 2, 2, 4, ("飞行", "仅对空", "迅捷", "突袭"), "可攻击飞行单位或敌方基地；地面近战无法攻击它。"),
    card("emperor", "帝国帝皇", 10, 1, 1, (), "回合开始：其余帝国单位攻击+2、行动+1。遗言：敌方每回合开始随机摧毁其一个非帝皇单位。"),
    card("heavy_tank", "帝国重型坦克", 8, 8, 9, ("防御2",), "回合开始恢复2点生命，不超过生命上限。", armor=2),
    card("engineer", "帝国工人", 2, 1, 3, (), "遗言：随机一个友方机械单位攻击+1、防御+1、生命上限及生命+2。"),
    card("suicide", "帝国敢死队", 3, 4, 1, ("突袭", "迅捷"), "首次攻击伤害翻倍；部署后的第二个自己的回合开始时阵亡。"),
    card("medium_tank", "帝国中型坦克", 6, 5, 8, ("防御1",), "技能·自修：恢复1点生命。消耗1行动。", armor=1, skill="repair"),
    card("light_tank", "帝国轻型坦克", 5, 4, 7, ("迅捷", "防御1"), "每回合3次行动；每次受到伤害减少1点。", armor=1),
    card("anti_air", "帝国高射炮", 7, 6, 6, ("对空", "超远程", "装弹"), "战吼：攻击+2。攻击飞行单位时额外忽略2点防御。"),
    card("factory", "帝国坦克工厂", 8, 0, 10, ("建筑",), "回合开始恢复2点生命。技能·制造：支付2点召唤点制造轻型坦克，或3点制造中型坦克。坦克进入己方最后方战线，每回合一次。", skill="manufacture"),
    card("tower", "帝国决策塔", 7, 0, 8, ("建筑", "远程"), "技能·调度：使一个友军立刻进行一次不消耗行动的合法攻击。每回合一次。", skill="command"),
]}

MECHANICAL = {"artillery", "carrier", "plane", "heavy_tank", "medium_tank", "light_tank", "anti_air", "factory", "tower"}
DEFAULT_DECK = ["scout", "archer", "light_cavalry", "infantry", "hound", "loan", "arrows", "fireball", "heal", "engineer"] * 2 + ["heavy_cavalry", "vanguard", "merchant", "banner", "shield", "artillery", "carrier", "medium_tank", "heavy_tank", "factory"]


def validate_deck(deck):
    if not isinstance(deck, list) or len(deck) != 30:
        raise ValueError("牌组必须恰好30张。")
    if any(not isinstance(k, str) or k not in CARDS for k in deck):
        raise ValueError("牌组包含未知卡牌。")
    if max(Counter(deck).values()) > 2:
        raise ValueError("同名卡牌最多放入两张。")
    return list(deck)
