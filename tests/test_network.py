import json
import socket
import time
import unittest
from empire_front import VERSION
from empire_front.cards import DEFAULT_DECK
from empire_front.network import Channel, RoomServer, RoomClient, MAX_FRAME
import queue


class NetworkTests(unittest.TestCase):
    def setUp(self):
        self.server = RoomServer(0, "test-room", bind="127.0.0.1")
        self.channels = []

    def tearDown(self):
        for c in self.channels:
            c.close()
        self.server.close()

    def connect(self, host=False, token=None, password="test-room", version=VERSION):
        sock = socket.create_connection(("127.0.0.1", self.server.port), timeout=3)
        sock.settimeout(3)
        c = Channel(sock)
        self.channels.append(c)
        hello = dict(type="hello", version=version, password=password, name="测试房主" if host else "测试访客", deck=DEFAULT_DECK)
        if host:
            hello["host_token"] = self.server.host_token
        if token:
            hello["token"] = token
        c.send(hello)
        return c

    def wait(self, c, kind, predicate=lambda m: True):
        for _ in range(30):
            m = c.receive()
            if m["type"] == kind and predicate(m):
                return m
        self.fail(f"未收到消息 {kind}")

    def started(self, opening=False):
        host = self.connect(host=True)
        hw = self.wait(host, "welcome")
        guest = self.connect()
        gw = self.wait(guest, "welcome")
        host.send(dict(type="ready"))
        guest.send(dict(type="ready"))
        hs = self.wait(host, "state", lambda m: m["state"] is not None)
        gs = self.wait(guest, "state", lambda m: m["state"] is not None)
        if not opening:
            host.send(dict(type="action",revision=0,action=dict(type="mulligan",cards=[])))
            guest.send(dict(type="action",revision=0,action=dict(type="mulligan",cards=[])))
            hs=self.wait(host,"state",lambda m:m["state"]["phase"]=="battle")
            gs=self.wait(guest,"state",lambda m:m["state"]["phase"]=="battle")
        return host, guest, hw, gw, hs, gs

    def test_authentication_and_version(self):
        c = self.connect(password="wrong")
        self.assertIn("口令", self.wait(c, "error")["message"])
        c = self.connect(version="0.0")
        self.assertIn("版本", self.wait(c, "error")["message"])
        self.assertEqual(self.server.slots, [None, None])

    def test_sync_and_hidden_hand(self):
        host, guest, _, _, hs, gs = self.started()
        self.assertNotIn("hand", hs["state"]["players"][1])
        self.assertNotIn("hand", gs["state"]["players"][0])
        host.send(dict(type="action", revision=2, action=dict(type="end")))
        hs = self.wait(host, "state", lambda m: m["state"]["revision"] == 3)
        gs = self.wait(guest, "state", lambda m: m["state"]["revision"] == 3)
        self.assertEqual(hs["state"]["turn"], 1)
        self.assertEqual(gs["state"]["turn"], 1)
        self.assertEqual(hs["state"]["log"], gs["state"]["log"])
        host.send(dict(type="action", revision=3, action=dict(type="end")))
        self.assertIn("回合", self.wait(host, "error")["message"])
        guest.send(dict(type="action", revision=0, action=dict(type="end")))
        self.assertIn("更新", self.wait(guest, "error")["message"])

    def test_room_full(self):
        self.started()
        intruder = self.connect()
        self.assertIn("满", self.wait(intruder, "error")["message"])

    def test_rear_deployment_authority_and_views(self):
        host,guest,_,_,hs,gs=self.started()
        self.assertEqual(hs["state"]["home_lane"],3)
        self.assertEqual(gs["state"]["home_lane"],0)
        game=self.server.game
        game.players[0]["hand"]=[dict(uid=9000,card="light_cavalry")]
        game.players[0]["mana"]=10
        host.send(dict(type="action",revision=2,action=dict(type="play",hand=9000,lane=2)))
        self.assertIn("后方",self.wait(host,"error")["message"])
        self.assertEqual(game.players[0]["mana"],10)
        self.assertEqual(len(game.players[0]["hand"]),1)
        host.send(dict(type="action",revision=2,action=dict(type="play",hand=9000,lane=3)))
        hs=self.wait(host,"state",lambda m:m["state"]["revision"]==3)
        gs=self.wait(guest,"state",lambda m:m["state"]["revision"]==3)
        self.assertEqual(hs["state"]["players"][0]["board"],gs["state"]["players"][0]["board"])
        uid=hs["state"]["players"][0]["board"][0]["uid"]
        host.send(dict(type="action",revision=3,action=dict(type="move",unit=uid,lane=2)))
        gs=self.wait(guest,"state",lambda m:m["state"]["revision"]==4)
        self.assertEqual(gs["state"]["players"][0]["board"][0]["lane"],2)

    def test_disconnect_pause_reconnect(self):
        host, guest, _, gw, _, _ = self.started()
        guest.close()
        self.wait(host, "state", lambda m: not m["lobby"][1]["online"])
        host.send(dict(type="action", revision=2, action=dict(type="end")))
        self.assertIn("断线", self.wait(host, "error")["message"])
        replacement = self.connect(token=gw["token"])
        self.assertEqual(self.wait(replacement, "welcome")["seat"], 1)
        restored = self.wait(replacement, "state", lambda m: m["state"] is not None)
        self.assertEqual(restored["state"]["revision"], 2)
        host.send(dict(type="action", revision=2, action=dict(type="end")))
        restored = self.wait(replacement, "state", lambda m: m["state"]["revision"] == 3)
        self.assertEqual(restored["state"]["turn"], 1)

    def test_rematch(self):
        host, guest, _, _, _, _ = self.started()
        host.send(dict(type="action", revision=2, action=dict(type="concede")))
        self.wait(host, "state", lambda m: m["state"]["winner"] == 1)
        self.wait(guest, "state", lambda m: m["state"]["winner"] == 1)
        host.send(dict(type="ready"))
        guest.send(dict(type="ready"))
        self.wait(host, "state", lambda m: m["state"]["winner"] is None and m["state"]["revision"] == 0)
        self.wait(guest, "state", lambda m: m["state"]["winner"] is None and m["state"]["revision"] == 0)

    def test_simultaneous_opening_confirmations(self):
        host,guest,_,_,hs,gs=self.started(opening=True)
        h_uid=hs["state"]["players"][0]["hand"][0]["uid"]
        g_uid=gs["state"]["players"][1]["hand"][0]["uid"]
        host.send(dict(type="action",revision=0,action=dict(type="mulligan",cards=[h_uid])))
        guest.send(dict(type="action",revision=0,action=dict(type="mulligan",cards=[g_uid])))
        hs=self.wait(host,"state",lambda m:m["state"]["phase"]=="battle")
        gs=self.wait(guest,"state",lambda m:m["state"]["phase"]=="battle")
        self.assertEqual(hs["state"]["revision"],2)
        self.assertEqual(gs["state"]["mulligan_done"],[True,True])
        self.assertNotIn("hand",hs["state"]["players"][1])
        self.assertNotIn(h_uid,[h["uid"] for h in hs["state"]["players"][0]["hand"]])

    def test_opening_disconnect_and_resume(self):
        host,guest,_,gw,hs,_=self.started(opening=True)
        host.send(dict(type="action",revision=0,action=dict(type="mulligan",cards=[])))
        self.wait(host,"state",lambda m:m["state"]["mulligan_done"][0])
        guest.close()
        self.wait(host,"state",lambda m:not m["lobby"][1]["online"])
        guest=self.connect(token=gw["token"])
        self.wait(guest,"welcome")
        restored=self.wait(guest,"state",lambda m:m["state"] is not None)
        self.assertEqual(restored["state"]["phase"],"mulligan")
        self.assertEqual(restored["state"]["mulligan_done"],[True,False])
        guest.send(dict(type="action",revision=1,action=dict(type="mulligan",cards=[])))
        self.wait(guest,"state",lambda m:m["state"]["phase"]=="battle")

    def test_frame_limit_and_invalid_json(self):
        a, b = socket.socketpair()
        self.channels.extend([Channel(a), Channel(b)])
        a.sendall(b"[]\n")
        with self.assertRaises(ValueError):
            self.channels[-1].receive()

    def test_complete_match_over_tcp(self):
        host, guest, _, _, hs, gs = self.started()
        channels = [host, guest]
        for _ in range(1200):
            game = self.server.game
            if game.winner is not None:
                break
            revision = game.revision
            action = game.ai_action(game.turn)
            channels[game.turn].send(dict(type="action", revision=revision, action=action))
            hs = self.wait(host, "state", lambda m: m["state"]["revision"] == revision+1)
            gs = self.wait(guest, "state", lambda m: m["state"]["revision"] == revision+1)
            for key in ["turn","round","winner","revision","log"]:
                self.assertEqual(hs["state"][key], gs["state"][key])
            for p in range(2):
                for key in ["hp","mana","board","deck_count","hand_count"]:
                    self.assertEqual(hs["state"]["players"][p][key],gs["state"]["players"][p][key])
        self.assertIsNotNone(self.server.game.winner)

    def test_client_automatic_reconnect(self):
        client = RoomClient("127.0.0.1", self.server.port, "重连测试", DEFAULT_DECK, "test-room", self.server.host_token)
        def event(kind, predicate=lambda value: True):
            deadline = time.monotonic()+8
            while time.monotonic() < deadline:
                try:
                    value = client.events.get(timeout=0.2)
                except queue.Empty:
                    continue
                if value["type"] == kind and predicate(value):
                    return value
            self.fail(f"客户端未收到 {kind}")
        try:
            first = event("welcome")
            event("state")
            client.channel.close()
            event("connection")
            restored = event("welcome")
            self.assertEqual(first["token"], restored["token"])
            self.assertEqual(restored["seat"], 0)
            self.assertFalse(client.retry(), "运行中的自动重连线程不能重复启动")
        finally:
            client.close()


if __name__ == "__main__":
    unittest.main()
