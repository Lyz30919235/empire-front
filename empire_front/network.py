"""TCP/JSON 双人房间；房主结算规则，只发送各自可见的手牌。"""
import json
import queue
import secrets
import socket
import threading
import time
from . import VERSION
from .cards import DEFAULT_DECK, validate_deck
from .engine import Game, RuleError

MAX_FRAME = 65536
DEFAULT_PORT = 47653


def encode(message):
    data = json.dumps(message, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n"
    if len(data) > MAX_FRAME:
        raise ValueError("消息过大。")
    return data


class Channel:
    def __init__(self, sock):
        self.sock = sock
        self.lock = threading.Lock()
        self.buffer = b""

    def send(self, message):
        with self.lock:
            self.sock.sendall(encode(message))

    def receive(self):
        while b"\n" not in self.buffer:
            block = self.sock.recv(8192)
            if not block:
                raise ConnectionError("连接已关闭。")
            self.buffer += block
            if len(self.buffer) > MAX_FRAME:
                raise ValueError("消息超过限制。")
        line, self.buffer = self.buffer.split(b"\n", 1)
        value = json.loads(line)
        if not isinstance(value, dict):
            raise ValueError("无效消息。")
        return value

    def close(self):
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.sock.close()


class RoomServer:
    def __init__(self, port=DEFAULT_PORT, password="", bind="0.0.0.0"):
        self.lock = threading.RLock()
        self.password = password
        self.host_token = secrets.token_hex(24)
        self.running = True
        self.game = None
        self.slots = [None, None]
        self.peers = set()
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            self.listener.bind((bind, port))
            self.listener.listen(8)
        except OSError:
            self.listener.close()
            raise
        self.port = self.listener.getsockname()[1]
        self.listener.settimeout(1)
        threading.Thread(target=self.accept, daemon=True).start()

    def accept(self):
        while self.running:
            try:
                sock, _ = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            sock.settimeout(15)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            channel = Channel(sock)
            with self.lock:
                if len(self.peers) >= 8:
                    channel.close()
                    continue
                self.peers.add(channel)
            threading.Thread(target=self.handle, args=(channel,), daemon=True).start()

    def handle(self, channel):
        seat = None
        try:
            hello = channel.receive()
            if hello.get("type") != "hello" or hello.get("version") != VERSION:
                raise ValueError("双方游戏版本不一致。请使用同一份游戏。")
            if hello.get("password", "") != self.password:
                raise ValueError("房间口令错误。")
            deck = validate_deck(hello.get("deck", DEFAULT_DECK))
            name = str(hello.get("name", "指挥官"))[:18].strip() or "指挥官"
            with self.lock:
                token = hello.get("token")
                if token:
                    seat = next((i for i, s in enumerate(self.slots) if s and secrets.compare_digest(s["token"], str(token))), None)
                    if seat is None:
                        raise ValueError("重连凭证无效，房间可能已重建。")
                    if self.slots[seat]["channel"] is not None:
                        raise ValueError("此玩家已在线。")
                else:
                    seat = 0 if hello.get("host_token") == self.host_token else 1
                    if self.slots[seat] is not None:
                        raise ValueError("房间已满，或该席位正在等待原玩家重连。")
                    self.slots[seat] = dict(name=name, deck=deck, ready=False,
                                            token=secrets.token_hex(24), channel=None)
                self.slots[seat]["channel"] = channel
                channel.send(dict(type="welcome", seat=seat, token=self.slots[seat]["token"]))
                self.broadcast()
            while self.running:
                message = channel.receive()
                with self.lock:
                    try:
                        self.process(seat, message)
                    except (ValueError, TypeError, KeyError) as error:
                        channel.send(dict(type="error", message=str(error)))
        except (OSError, ConnectionError, ValueError, TypeError, KeyError) as error:
            try:
                channel.send(dict(type="error", message=str(error)))
            except OSError:
                pass
        finally:
            channel.close()
            with self.lock:
                self.peers.discard(channel)
                if seat is not None and self.slots[seat] and self.slots[seat]["channel"] is channel:
                    self.slots[seat]["channel"] = None
                    self.broadcast()

    def process(self, seat, message):
        kind = message.get("type")
        if kind == "ping":
            self.slots[seat]["channel"].send(dict(type="pong"))
            return
        if kind == "ready":
            if self.game and self.game.winner is None:
                raise RuleError("对局已经开始。")
            self.slots[seat]["ready"] = True
            if all(s and s["ready"] and s["channel"] for s in self.slots):
                self.game = Game([s["deck"] for s in self.slots], [s["name"] for s in self.slots])
                for s in self.slots:
                    s["ready"] = False
        elif kind == "action":
            if not self.game:
                raise RuleError("请等待双方准备。")
            if not all(s and s["channel"] for s in self.slots):
                raise RuleError("对方断线，对局暂停等待重连。")
            simultaneous_opening = self.game.phase == "mulligan" and isinstance(message.get("action"), dict) and message["action"].get("type") == "mulligan"
            if not simultaneous_opening and message.get("revision") != self.game.revision:
                self.broadcast()
                raise RuleError("状态已更新，请重新操作。")
            self.game.act(seat, message.get("action"))
        else:
            raise RuleError("未知房间消息。")
        self.broadcast()

    def broadcast(self):
        lobby = [dict(name=s["name"], ready=s["ready"], online=s["channel"] is not None) if s else None for s in self.slots]
        for i, slot in enumerate(self.slots):
            if slot and slot["channel"]:
                try:
                    slot["channel"].send(dict(type="state", lobby=lobby, state=self.game.view(i) if self.game else None))
                except OSError:
                    pass

    def close(self):
        self.running = False
        self.listener.close()
        with self.lock:
            for peer in list(self.peers):
                peer.close()


class RoomClient:
    def __init__(self, ip, port, name, deck, password="", host_token=None):
        self.ip, self.port = ip, port
        self.hello = dict(type="hello", version=VERSION, name=name, deck=deck,
                          password=password, host_token=host_token)
        self.events = queue.Queue()
        self.channel = None
        self.running = True
        self.token = None
        self.seat = None
        self.worker = threading.Thread(target=self.run, daemon=True)
        self.worker.start()

    def run(self):
        retries = 0
        while self.running:
            try:
                sock = socket.create_connection((self.ip, self.port), timeout=6)
                sock.settimeout(15)
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                channel = Channel(sock)
                self.channel = channel
                channel.send(dict(self.hello, **({"token": self.token} if self.token else {})))
                while self.running:
                    event = channel.receive()
                    if event["type"] == "welcome":
                        self.token, self.seat = event["token"], event["seat"]
                        retries = 0
                        threading.Thread(target=self.heartbeat, args=(channel,), daemon=True).start()
                    self.events.put(event)
            except (OSError, ConnectionError, ValueError, KeyError) as error:
                if self.running:
                    self.events.put(dict(type="connection", message=str(error)))
            finally:
                if self.channel:
                    self.channel.close()
                    self.channel = None
            if not self.running:
                break
            if not self.token:
                self.events.put(dict(type="failed", message="无法连接房间。请核对IP、端口、口令和防火墙。"))
                break
            retries += 1
            if retries > 15:
                self.events.put(dict(type="failed", message="重连超时。请点击重试连接，保留原房间与席位。"))
                break
            self.events.put(dict(type="connection", message=f"连接中断，正在重连（{retries}/15）…"))
            time.sleep(2)

    def retry(self):
        if self.worker.is_alive():
            return False
        self.running = True
        self.worker = threading.Thread(target=self.run, daemon=True)
        self.worker.start()
        return True

    def heartbeat(self, channel):
        while self.running and self.channel is channel:
            try:
                channel.send(dict(type="ping"))
            except OSError:
                return
            time.sleep(4)

    def send(self, message):
        if not self.channel:
            raise ConnectionError("连接未就绪，请稍候。")
        self.channel.send(message)

    def close(self):
        self.running = False
        if self.channel:
            self.channel.close()
