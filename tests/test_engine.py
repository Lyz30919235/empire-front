import copy
import unittest
from empire_front.cards import CARDS, DEFAULT_DECK, validate_deck
from empire_front.engine import Game, RuleError


class RulesTests(unittest.TestCase):
    def setUp(self):
        self.g = Game(seed=9)
        self.g.act(0,dict(type="mulligan",cards=[]))
        self.g.act(1,dict(type="mulligan",cards=[]))
        for p in self.g.players:
            p["board"] = []
            p["mana"] = 10

    def unit(self, p, key, lane=0):
        u = self.g.summon(p, key, lane)
        u["actions"] = 3
        return u

    def hand(self, key):
        self.g.players[0]["hand"] = [dict(uid=9000, card=key)]
        return 9000

    def test_cards_and_deck(self):
        self.assertEqual(len(CARDS), 26)
        validate_deck(DEFAULT_DECK)
        with self.assertRaises(ValueError):
            validate_deck(["scout"] * 30)

    def test_hidden_information(self):
        view = self.g.view(0)
        self.assertNotIn("hand", view["players"][1])
        self.assertNotIn("deck", view["players"][0])
        self.assertNotIn("deck", view["players"][1])
        view["players"][0]["hp"] = 1
        self.assertEqual(self.g.players[0]["hp"], 30)

    def test_wrong_turn(self):
        before = copy.deepcopy(self.g.view(0))
        with self.assertRaises(RuleError):
            self.g.act(1, dict(type="end"))
        self.assertEqual(before, self.g.view(0))

    def test_invalid_play_does_not_spend(self):
        h = self.hand("fireball")
        u = self.unit(0, "infantry")
        before = copy.deepcopy(self.g.view(0))
        with self.assertRaises(RuleError):
            self.g.act(0, dict(type="play", hand=h, target=u["uid"]))
        self.assertEqual(before, self.g.view(0))

    def test_armor(self):
        u = self.unit(0, "heavy_tank")
        self.assertEqual(self.g.damage(u, 1), 0)
        self.assertEqual(u["hp"], 9)
        self.assertEqual(self.g.damage(u, 5), 3)

    def test_simultaneous_death(self):
        a = self.unit(0, "infantry")
        b = self.unit(1, "infantry")
        a["hp"] = b["hp"] = 3
        self.g.act(0, dict(type="attack", unit=a["uid"], target=b["uid"]))
        self.assertEqual(self.g.players[0]["board"], [])
        self.assertEqual(self.g.players[1]["board"], [])

    def test_ranged_without_counter(self):
        a = self.unit(0, "archer", 0)
        b = self.unit(1, "infantry", 2)
        self.g.act(0, dict(type="attack", unit=a["uid"], target=b["uid"]))
        self.assertEqual(a["hp"], 2)
        self.assertEqual(b["hp"], 3)

    def test_melee_range(self):
        a = self.unit(0, "infantry", 0)
        b = self.unit(1, "infantry", 3)
        with self.assertRaises(RuleError):
            self.g.act(0, dict(type="attack", unit=a["uid"], target=b["uid"]))

    def test_flying_and_base(self):
        a = self.unit(0, "plane")
        b = self.unit(1, "infantry")
        self.g.act(0, dict(type="attack", unit=a["uid"], target="base"))
        self.assertEqual(self.g.players[1]["hp"], 28)
        self.assertIsNotNone(self.g.attack_error(1, b, a["uid"]))
        self.assertIsNotNone(self.g.attack_error(0, a, b["uid"]))

    def test_taunt(self):
        a = self.unit(0, "archer")
        b = self.unit(1, "infantry")
        shield = self.unit(1, "shield")
        self.assertIsNotNone(self.g.attack_error(0, a, b["uid"]))
        self.assertIsNone(self.g.attack_error(0, a, shield["uid"]))

    def test_base_blocked(self):
        a = self.unit(0, "infantry")
        self.unit(1, "infantry", 3)
        with self.assertRaises(RuleError):
            self.g.act(0, dict(type="attack", unit=a["uid"], target="base"))

    def test_movement_and_capacity(self):
        a = self.unit(0, "infantry", 0)
        for _ in range(3):
            self.unit(0, "infantry", 1)
        with self.assertRaises(RuleError):
            self.g.act(0, dict(type="move", unit=a["uid"], lane=1))
        self.assertEqual(a["actions"], 3)
        with self.assertRaises(RuleError):
            self.g.act(0, dict(type="move", unit=a["uid"], lane=2))

    def test_building_no_movement(self):
        a = self.unit(0, "factory")
        with self.assertRaises(RuleError):
            self.g.act(0, dict(type="move", unit=a["uid"], lane=1))

    def test_blitz_and_sleep(self):
        h = self.hand("light_cavalry")
        self.g.act(0, dict(type="play", hand=h, lane=0))
        self.assertEqual(self.g.players[0]["board"][0]["actions"], 3)
        h = self.hand("infantry")
        self.g.act(0, dict(type="play", hand=h, lane=0))
        self.assertEqual(self.g.players[0]["board"][1]["actions"], 0)

    def test_reload_skips_next_turn(self):
        a = self.unit(0, "artillery")
        self.g.act(0, dict(type="attack", unit=a["uid"], target="base"))
        self.assertEqual(a["actions"], 0)
        self.g.start_turn(0)
        self.assertEqual(a["actions"], 0)
        self.assertIsNotNone(self.g.attack_error(0, a, "base", free=True))
        self.g.start_turn(0)
        self.assertEqual(a["actions"], 2)
        self.assertIsNone(self.g.attack_error(0, a, "base"))

    def test_hound_deathrattle_once(self):
        a = self.unit(0, "hound")
        a["hp"] = 0
        self.g.cleanup()
        puppy = self.g.players[0]["board"][0]
        self.assertEqual(puppy["attack"], 2)
        puppy["hp"] = 0
        self.g.cleanup()
        self.assertEqual(self.g.players[0]["board"], [])

    def test_engineer_and_tank_heal(self):
        tank = self.unit(0, "heavy_tank")
        worker = self.unit(0, "engineer")
        worker["hp"] = 0
        self.g.cleanup()
        self.assertEqual((tank["attack"], tank["armor"], tank["max_hp"]), (9, 3, 11))
        tank["hp"] = 7
        self.g.start_turn(0)
        self.assertEqual(tank["hp"], 9)

    def test_suicide_first_hit_and_expiry(self):
        a = self.unit(0, "suicide")
        self.g.act(0, dict(type="attack", unit=a["uid"], target="base"))
        self.g.act(0, dict(type="attack", unit=a["uid"], target="base"))
        self.assertEqual(self.g.players[1]["hp"], 18)
        self.g.start_turn(0)
        self.assertTrue(self.g.players[0]["board"])
        self.g.start_turn(0)
        self.assertFalse(self.g.players[0]["board"])

    def test_loan_and_repayment(self):
        h = self.hand("loan")
        self.g.players[0]["mana"] = 0
        self.g.act(0, dict(type="play", hand=h))
        self.assertEqual(self.g.players[0]["mana"], 2)
        self.g.start_turn(0)
        self.assertEqual(self.g.players[0]["mana"], 0)
        self.assertEqual(self.g.players[0]["debt"], 0)

    def test_banner_three_turns(self):
        a = self.unit(0, "infantry")
        h = self.hand("banner")
        self.g.act(0, dict(type="play", hand=h, lane=0))
        for _ in range(3):
            self.g.start_turn(0)
        self.assertEqual(a["attack"], 9)
        self.g.start_turn(0)
        self.assertEqual(a["attack"], 9)

    def test_carrier_capacity(self):
        h = self.hand("carrier")
        self.g.act(0, dict(type="play", hand=h, lane=0))
        self.assertEqual(sum(u["card"] == "plane" for u in self.g.players[0]["board"]), 3)
        for lane in range(4):
            self.assertLessEqual(sum(u["lane"] == lane for u in self.g.players[0]["board"]), 3)

    def test_factory_once_per_turn(self):
        a = self.unit(0, "factory")
        self.g.act(0, dict(type="skill", unit=a["uid"], lane=0, option="medium_tank"))
        self.assertEqual(self.g.players[0]["mana"], 7)
        with self.assertRaises(RuleError):
            self.g.act(0, dict(type="skill", unit=a["uid"], lane=1))

    def test_skill_cooldown(self):
        a = self.unit(0, "heavy_cavalry")
        b = self.unit(1, "infantry")
        self.g.act(0, dict(type="skill", unit=a["uid"], lane=0))
        self.assertEqual(b["hp"], 3)
        for _ in range(2):
            self.g.start_turn(0)
            with self.assertRaises(RuleError):
                self.g.act(0, dict(type="skill", unit=a["uid"], lane=0))
        self.g.start_turn(0)
        self.g.act(0, dict(type="skill", unit=a["uid"], lane=0))
        self.assertEqual(b["hp"], 1)

    def test_decision_tower(self):
        tower = self.unit(0, "tower")
        ally = self.unit(0, "infantry")
        ally["actions"] = 0
        self.g.act(0, dict(type="skill", unit=tower["uid"], ally=ally["uid"], target="base"))
        self.assertEqual(self.g.players[1]["hp"], 27)
        self.assertEqual(ally["actions"], 0)

    def test_emperor_and_curse(self):
        emperor = self.unit(0, "emperor")
        ally = self.unit(0, "infantry")
        self.g.start_turn(0)
        self.assertEqual(ally["attack"], 5)
        self.assertEqual(ally["actions"], 3)
        emperor["hp"] = 0
        self.g.cleanup()
        self.unit(1, "infantry")
        self.g.start_turn(1)
        self.assertEqual(self.g.players[1]["board"], [])

    def test_fatigue_and_concede(self):
        self.g.players[0]["deck"] = []
        self.g.draw(0, 3)
        self.assertEqual(self.g.players[0]["hp"], 24)
        self.g.act(1, dict(type="concede"))
        self.assertEqual(self.g.winner, 0)

    def test_complete_matches_and_invariants(self):
        # 不只模拟开局：随机牌组覆盖26种卡牌，连续完成80局。
        for seed in range(80):
            import random
            rng = random.Random(seed)
            decks = []
            for _ in range(2):
                pool = list(CARDS) * 2
                rng.shuffle(pool)
                decks.append(pool[:30])
            g = Game(decks=decks, seed=seed)
            for _ in range(1600):
                if g.winner is not None:
                    break
                g.act(g.turn, g.ai_action(g.turn))
                for player in g.players:
                    self.assertGreaterEqual(player["mana"], 0)
                    self.assertLessEqual(len(player["hand"]), 10)
                    for lane in range(4):
                        self.assertLessEqual(sum(u["lane"] == lane for u in player["board"]), 3)
                    for u in player["board"]:
                        self.assertGreater(u["hp"], 0)
                        self.assertLessEqual(u["hp"], u["max_hp"])
                        self.assertGreaterEqual(u["actions"], 0)
            self.assertIsNotNone(g.winner, f"未完成对局 seed={seed}")


if __name__ == "__main__":
    unittest.main()
