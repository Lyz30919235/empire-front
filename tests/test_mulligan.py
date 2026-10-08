from collections import Counter
import copy
import unittest
from empire_front.engine import Game, RuleError


class MulliganTests(unittest.TestCase):
    def setUp(self):
        self.game=Game(seed=23)

    def test_opening_has_no_resources_and_blocks_play(self):
        g=self.game
        self.assertEqual(g.phase,"mulligan")
        self.assertEqual([len(p["hand"]) for p in g.players],[4,4])
        self.assertEqual(g.players[0]["mana"],0)
        for action in [dict(type="end"),dict(type="play",hand=g.players[0]["hand"][0]["uid"],lane=0)]:
            with self.assertRaises(RuleError):
                g.act(0,action)

    def test_swap_preserves_deck_and_hand_and_unselected_cards(self):
        g=self.game
        player=g.players[0]
        total=Counter(player["deck"]+[h["card"] for h in player["hand"]])
        original=copy.deepcopy(player["hand"])
        g.act(0,dict(type="mulligan",cards=[original[0]["uid"],original[2]["uid"]]))
        self.assertEqual(len(player["hand"]),4)
        self.assertEqual(len(player["deck"]),26)
        self.assertEqual(player["hand"][1],original[1])
        self.assertEqual(player["hand"][3],original[3])
        self.assertNotEqual(player["hand"][0]["uid"],original[0]["uid"])
        self.assertEqual(Counter(player["deck"]+[h["card"] for h in player["hand"]]),total)

    def test_cannot_draw_back_returned_card(self):
        g=self.game
        p=g.players[0]
        p["deck"]=["infantry"]*26
        p["hand"][0]["card"]="emperor"
        uid=p["hand"][0]["uid"]
        g.act(0,dict(type="mulligan",cards=[uid]))
        self.assertEqual(p["hand"][0]["card"],"infantry")
        self.assertIn("emperor",p["deck"])

    def test_keep_all_and_start_after_both_confirm(self):
        g=self.game
        before=copy.deepcopy(g.players[0]["hand"])
        g.act(1,dict(type="mulligan",cards=[]))
        self.assertEqual(g.phase,"mulligan")
        g.act(0,dict(type="mulligan",cards=[]))
        self.assertEqual(g.phase,"battle")
        self.assertEqual(g.turn,0)
        self.assertEqual(g.players[0]["mana"],1)
        self.assertEqual(before,g.players[0]["hand"])
        self.assertEqual(g.players[0]["turns"],1)

    def test_all_cards_replace_and_only_once(self):
        g=self.game
        selected=[h["uid"] for h in g.players[0]["hand"]]
        g.act(0,dict(type="mulligan",cards=selected))
        self.assertTrue(set(selected).isdisjoint(h["uid"] for h in g.players[0]["hand"]))
        with self.assertRaises(RuleError):
            g.act(0,dict(type="mulligan",cards=[]))

    def test_invalid_choices_do_not_mutate(self):
        g=self.game
        own=g.players[0]["hand"][0]["uid"]
        other=g.players[1]["hand"][0]["uid"]
        for selected in [[own,own],[other],[True],"bad",[123456]]:
            before=copy.deepcopy(g.view(0))
            with self.assertRaises(RuleError):
                g.act(0,dict(type="mulligan",cards=selected))
            self.assertEqual(before,g.view(0))

    def test_reject_after_game_start(self):
        g=self.game
        for p in (0,1):
            g.act(p,dict(type="mulligan",cards=[]))
        with self.assertRaises(RuleError):
            g.act(0,dict(type="mulligan",cards=[]))

    def test_private_choices_not_leaked(self):
        g=self.game
        g.act(1,dict(type="mulligan",cards=[h["uid"] for h in g.players[1]["hand"]]))
        view=g.view(0)
        self.assertNotIn("hand",view["players"][1])
        self.assertNotIn("cards",view["players"][1])
        self.assertTrue(view["mulligan_done"][1])
