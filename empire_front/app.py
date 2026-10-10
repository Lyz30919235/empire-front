"""四条线性战线的军事卡牌桌面，支持拖动部署、移动与攻击。"""
import json
from pathlib import Path
import queue
import socket
import threading
import tkinter as tk
from tkinter import messagebox
from .cards import CARDS, DEFAULT_DECK, validate_deck
from .engine import Game, RuleError
from .network import RoomClient, RoomServer, DEFAULT_PORT
from .tabletop import TabletopRenderer

BG = "#242820"
PANEL = "#343c2d"
LINE = "#697256"
TEXT = "#eee6cc"
MUTED = "#c0c1a4"
GOLD = "#d7c08b"
TEAL = "#c0ce91"
RED = "#d99b7a"
FONT = "Microsoft YaHei UI"
SAVE_DIR = Path.home() / ".empire_front"


class App(TabletopRenderer):
    def __init__(self, root):
        self.root = root
        root.tk.call("tk", "scaling", 1.25)
        root.title("帝国：四线战令 | EMPIRE FRONT")
        root.geometry("1440x900")
        root.minsize(1140, 760)
        root.configure(bg=BG)
        root.protocol("WM_DELETE_WINDOW", self.close)
        self.canvas = tk.Canvas(root, bg=BG, highlightthickness=0)
        self.canvas.pack(fill="both", expand=True)
        self.canvas.bind("<Configure>", lambda e: self.redraw())
        self.canvas.bind("<ButtonPress-1>", self.press)
        self.canvas.bind("<B1-Motion>", self.drag)
        self.canvas.bind("<ButtonRelease-1>", self.release)
        self.canvas.bind("<Button-3>", lambda e: self.cancel())
        self.canvas.bind("<Motion>", self.hover)
        root.bind("<Escape>", lambda e: self.cancel())
        self.mode = "menu"
        self.client = None
        self.server = None
        self.game = None
        self.state = None
        self.lobby = None
        self.you = 0
        self.selected = None
        self.drag_state = None
        self.mulligan_selected = set()
        self.mulligan_pending = False
        self.operation = "attack"
        self.command_ally = None
        self.factory_option = "light_tank"
        self.inspect = None
        self.hits = []
        self.widgets = []
        self.status = "选择训练，或与朋友建立双人房间。"
        self.network_ok = True
        self.ai_pending = False
        self.name = tk.StringVar(value="指挥官")
        self.ip = tk.StringVar(value="127.0.0.1")
        self.port = tk.StringVar(value=str(DEFAULT_PORT))
        self.password = tk.StringVar()
        self.deck = DEFAULT_DECK[:]
        self.load_settings()
        self.menu()
        root.after(80, self.pump)

    def load_settings(self):
        try:
            saved = json.loads((SAVE_DIR / "settings.json").read_text(encoding="utf-8"))
            self.deck = validate_deck(saved.get("deck", DEFAULT_DECK))
            self.name.set(str(saved.get("name", "指挥官")))
            self.ip.set(str(saved.get("ip", "127.0.0.1")))
            self.port.set(str(saved.get("port", DEFAULT_PORT)))
        except (OSError, ValueError, TypeError):
            pass

    def save_settings(self):
        try:
            SAVE_DIR.mkdir(exist_ok=True)
            (SAVE_DIR / "settings.json").write_text(json.dumps(dict(deck=self.deck, name=self.name.get(), ip=self.ip.get(), port=self.port.get()), ensure_ascii=False, indent=2), encoding="utf-8")
        except OSError:
            self.status = "设置未能保存，当前游戏仍可正常运行。"

    def clear_widgets(self):
        for w in self.widgets:
            w.destroy()
        self.widgets.clear()

    def text(self, x, y, text, size=12, color=TEXT, anchor="nw", width=None, bold=False):
        return self.canvas.create_text(x, y, text=text, fill=color, anchor=anchor,
                                       font=(FONT, size, "bold" if bold else "normal"), width=width)

    def rect(self, x, y, w, h, fill=PANEL, outline=LINE, width=1):
        return self.canvas.create_rectangle(x, y, x + w, y + h, fill=fill, outline=outline, width=width)

    def hit(self, box, value):
        self.hits.append((box, value))



    def menu(self):
        self.mode = "menu"
        self.clear_widgets()
        frame = tk.Frame(self.canvas, bg=PANEL, padx=30, pady=24)
        self.widgets.append(frame)
        tk.Label(frame, text="部署你的战局", font=(FONT, 19, "bold"), bg=PANEL, fg=TEXT).pack(anchor="w", pady=(0, 14))
        for title, var in [("指挥官名称", self.name), ("房主 IP / Radmin VPN IP", self.ip), ("TCP 端口", self.port), ("房间口令（可留空）", self.password)]:
            tk.Label(frame, text=title, font=(FONT, 10), bg=PANEL, fg=MUTED).pack(anchor="w", pady=(7, 3))
            tk.Entry(frame, textvariable=var, bg=BG, fg=TEXT, insertbackground=TEAL,
                     relief="flat", font=(FONT, 12), width=34, show="•" if var is self.password else "").pack(fill="x", ipady=5)
        row = tk.Frame(frame, bg=PANEL)
        row.pack(fill="x", pady=(20, 8))
        for label, command, color in [("创建房间", self.host, TEAL), ("加入房间", self.join, GOLD), ("单机训练", self.solo, TEXT)]:
            tk.Button(row, text=label, command=command, bg=BG, fg=color, relief="flat",
                      activebackground=LINE, activeforeground=TEXT, font=(FONT, 11), padx=12, pady=8).pack(side="left", padx=(0, 8))
        row2 = tk.Frame(frame, bg=PANEL)
        row2.pack(fill="x")
        for label, command in [("卡牌图鉴 / 组牌", self.deck_builder), ("玩法与联机指南", self.guide)]:
            tk.Button(row2, text=label, command=command, bg=PANEL, fg=MUTED, relief="flat", font=(FONT, 10), pady=5).pack(side="left", padx=(0, 15))
        self.menu_frame = frame
        self.redraw()

    def redraw(self):
        c = self.canvas
        c.delete("all")
        self.hits = []
        w, h = c.winfo_width(), c.winfo_height()
        if w < 10:
            return
        self.backdrop()
        if self.mode == "menu":
            self.text(72, 78, "EMPIRE / FRONT", 14, GOLD, bold=True)
            self.text(72, 121, "帝国", 55, TEXT, bold=True)
            self.text(76, 218, "四 线 战 令", 24, TEAL)
            self.text(76, 280, "四条战线。一座基地。\n每次部署，都是新的攻防选择。", 14, MUTED, width=450)
            self.rect(72,402,434,178,"#343c2d",GOLD,2)
            self.illustration(80,410,418,161,"emperor")
            self.text(76, h - 100, "PYTHON · TCP 联机 · 26 种卡牌", 10, MUTED)
            self.text(76, h - 69, self.status, 10, GOLD, width=w - 150)
            c.create_window(w - 300, h / 2 - 15, window=self.menu_frame, anchor="center")
        elif not self.state:
            self.draw_lobby(w, h)
        else:
            self.draw_game(w, h)
            if self.drag_state and self.drag_state.get("active"):
                self.draw_drag_overlay()

    def art(self, x, y, key, color, scale=1):
        c = self.canvas
        def points(items):
            return [v for px, py in items for v in (x + px * scale, y + py * scale)]
        if key == "carrier":
            c.create_polygon(points([(-14,-27),(14,-27),(19,13),(0,28),(-19,13)]),fill="",outline=color,width=2)
            c.create_line(x-5*scale,y-20*scale,x-5*scale,y+15*scale,fill=color,width=2)
            c.create_rectangle(x+4*scale,y-13*scale,x+12*scale,y+4*scale,fill=color,outline=color)
            c.create_line(x-11*scale,y-3*scale,x+2*scale,y-3*scale,fill=color,width=2)
        elif key == "plane":
            c.create_polygon(points([(0,-24),(8,-4),(29,10),(8,9),(8,20),(0,15),(-8,20),(-8,9),(-29,10),(-8,-4)]), fill=color, outline=color)
        elif key in {"heavy_tank", "medium_tank", "light_tank", "artillery", "anti_air"}:
            c.create_rectangle(x-25*scale,y-8*scale,x+25*scale,y+16*scale,outline=color,width=2)
            c.create_rectangle(x-12*scale,y-17*scale,x+13*scale,y-3*scale,fill=color,outline=color)
            c.create_line(x,y-10*scale,x+34*scale,y-10*scale,fill=color,width=3)
            for dx in [-16,0,16]:
                c.create_oval(x+(dx-5)*scale,y+4*scale,x+(dx+5)*scale,y+14*scale,outline=color)
        elif key in {"factory", "tower"}:
            c.create_polygon(points([(-24,20),(-24,-5),(-8,2),(-8,-9),(8,-2),(8,-24),(20,-24),(20,20)]),outline=color,fill="",width=2)
            c.create_line(x-28*scale,y+23*scale,x+28*scale,y+23*scale,fill=color,width=2)
        elif CARDS[key]["kind"] == "spell":
            c.create_polygon(points([(0,-25),(22,0),(0,25),(-22,0)]),fill="",outline=color,width=2)
            c.create_line(x-11*scale,y+11*scale,x+11*scale,y-11*scale,fill=color,width=3)
        else:
            c.create_polygon(points([(-20,-20),(20,-20),(17,7),(0,25),(-17,7)]),fill="",outline=color,width=2)
            c.create_line(x,y-12*scale,x,y+11*scale,fill=color,width=2)
            c.create_line(x-8*scale,y-1*scale,x+8*scale,y-1*scale,fill=color,width=2)

    def draw_lobby(self, w, h):
        self.text(80, 65, "双人作战室", 28, TEXT, bold=True)
        self.text(82, 125, "双方点击准备后开战。房主先手，对手后手。", 13, MUTED)
        for i, slot in enumerate(self.lobby or [None, None]):
            x = w / 2 - 350 + i * 370
            self.rect(x, 210, 330, 210)
            self.text(x + 24, 237, "01 / 房主" if i == 0 else "02 / 访客", 11, GOLD)
            self.text(x + 24, 285, slot["name"] if slot else "等待指挥官加入…", 20, TEXT)
            self.text(x + 24, 345, ("已准备" if slot["ready"] else "尚未准备") if slot else "空席", 12, TEAL if slot and slot["ready"] else MUTED)
            if slot and not slot["online"]:
                self.text(x + 24, 380, "离线 · 等待重连", 11, RED)
        self.text(80, 460, f"端口 {self.server.port if self.server else self.port.get()}  ·  牌组 {len(self.deck)}/30", 12, MUTED)
        if self.server:
            self.text(80, 502, "把房主的 Radmin VPN IP 和端口告诉朋友。\n同机测试：另开游戏，加入 127.0.0.1。", 12, TEXT)
        self.button(w / 2 - 100, h - 205, 200, 48, "准备开战", self.ready, True)
        self.button(80, h - 120, 180, 40, "返回主菜单", self.leave)
        self.button(280, h - 120, 180, 40, "重试连接", self.retry)
        self.text(80, h - 57, self.status, 11, GOLD, width=w - 150)





    def hit_at(self,x,y):
        return next(((box,value) for box,value in reversed(self.hits) if box[0]<=x<=box[2] and box[1]<=y<=box[3]),None)

    def press(self,e):
        found=self.hit_at(e.x,e.y)
        if not found:
            self.drag_state=None
            return
        box,value=found
        draggable=self.state and self.state.get("phase")=="battle" and self.state["winner"] is None and (value[0]=="hand" or value[0]=="unit" and value[2])
        self.drag_state=dict(source=value,start=(e.x,e.y),point=(e.x,e.y),active=False,draggable=bool(draggable))

    def drag(self,e):
        gesture=self.drag_state
        if not gesture or not gesture["draggable"]:
            return
        gesture["point"]=(e.x,e.y)
        sx,sy=gesture["start"]
        if not gesture["active"] and (e.x-sx)**2+(e.y-sy)**2<49:
            return
        if not gesture["active"]:
            gesture["active"]=True
            source=gesture["source"]
            self.selected=(source[0],source[1])
            self.inspect=source[-1]
            self.status="松开鼠标执行；拖回手牌或拖到场外取消。"
            self.redraw()
        else:
            self.draw_drag_overlay()

    def drag_action(self,source,target):
        if not target:
            return None
        kind=target[0]
        if source[0]=="hand":
            card=CARDS[source[-1]]
            action=dict(type="play",hand=source[1])
            if card["kind"]=="unit" or card.get("target")=="lane":
                if kind=="lane":
                    action["lane"]=target[1]
                elif kind=="unit" and self.lookup(target[1]):
                    action["lane"]=self.lookup(target[1])["lane"]
                else:
                    return None
            elif card.get("target"):
                if kind=="unit":
                    action["target"]=target[1]
                elif kind=="base" and target[1] and card.get("target")=="friendly":
                    action["target"]="base"
                else:
                    return None
            elif kind not in {"lane","unit","base"}:
                return None
            return action
        if source[0]=="unit":
            uid=source[1]
            if kind=="unit" and not target[2]:
                return dict(type="attack",unit=uid,target=target[1])
            if kind=="base" and not target[1]:
                return dict(type="attack",unit=uid,target="base")
            if kind=="lane":
                return dict(type="move",unit=uid,lane=target[1])
            if kind=="unit" and target[2] and self.lookup(target[1]):
                return dict(type="move",unit=uid,lane=self.lookup(target[1])["lane"])
        return None

    def drop_error(self,action):
        if not action:
            return "未选择合法放置位置，已取消拖动。"
        s=self.state
        if s["winner"] is not None or s.get("phase")!="battle":
            return "当前阶段不能执行战斗操作。"
        if s["turn"]!=self.you:
            return "请等待你的回合。"
        if self.client and (not self.network_ok or not all(x and x["online"] for x in self.lobby or [])):
            return "连接中断，等待双方恢复连接。"
        preview=Game.__new__(Game)
        preview.players=s["players"]
        own=s["players"][self.you]
        if action["type"]=="play":
            hand=next((h for h in own["hand"] if h["uid"]==action["hand"]),None)
            if not hand:
                return "这张牌已不在手中。"
            card=CARDS[hand["card"]]
            if own["mana"]<card["cost"]:
                return "召唤点不足。"
            if card["kind"]=="unit":
                return preview.deploy_error(self.you,action["lane"])
            if card.get("target") in {"friendly","enemy"}:
                if action.get("target")=="base":
                    return None if card["id"]=="heal" else "该法术不能作用于基地。"
                try:
                    owner,_=preview.unit(action.get("target"))
                except RuleError as error:
                    return str(error)
                expected=self.you if card["target"]=="friendly" else 1-self.you
                if owner!=expected:
                    return "法术目标阵营错误。"
            return None
        try:
            owner,u=preview.unit(action["unit"])
        except RuleError as error:
            return str(error)
        if owner!=self.you:
            return "不能指挥敌方单位。"
        if action["type"]=="attack":
            return preview.attack_error(self.you,u,action["target"])
        if "建筑" in u["tags"]:
            return "建筑不能移动。"
        if not u["actions"] or u["reload"] or u["reloading"]:
            return "这个单位没有可用行动。"
        if abs(u["lane"]-action["lane"])!=1:
            return "每次移动只能到相邻战线。"
        if not preview.space(self.you,action["lane"]):
            return "目标战线已满或被敌方占据。"
        return None

    def draw_drag_overlay(self):
        self.canvas.delete("drag-overlay")
        gesture=self.drag_state
        if not gesture or not gesture["active"]:
            return
        before=set(self.canvas.find_all())
        source=gesture["source"]
        for box,value in list(self.hits):
            action=self.drag_action(source,value)
            if action and self.drop_error(action) is None:
                x1,y1,x2,y2=box
                self.canvas.create_rectangle(x1+1,y1+1,x2-1,y2-1,outline="#ede39a",width=2,dash=(5,3))
        x,y=gesture["point"]
        found=self.hit_at(x,y)
        target=found[1] if found else None
        action=self.drag_action(source,target)
        color="#e6dd84" if self.drop_error(action) is None else "#db9277"
        if source[0]=="unit":
            sx,sy=gesture["start"]
            self.canvas.create_line(sx,sy,x,y,fill=color,width=4,arrow="last",arrowshape=(14,18,6))
        else:
            hit_count=len(self.hits)
            self.draw_hand(x-62,y-76,124,148,dict(uid=source[1],card=source[-1]),self.state["players"][self.you]["mana"])
            del self.hits[hit_count:]
            self.canvas.create_rectangle(x-64,y-85,x+64,y+78,outline=color,width=3)
        for item in set(self.canvas.find_all())-before:
            self.canvas.addtag_withtag("drag-overlay",item)

    def release(self,e):
        gesture=self.drag_state
        self.drag_state=None
        self.canvas.delete("drag-overlay")
        if not gesture:
            return
        if not gesture.get("active"):
            self.click(e)
            return
        found=self.hit_at(e.x,e.y)
        action=self.drag_action(gesture["source"],found[1] if found else None)
        error=self.drop_error(action)
        if error:
            self.status=error
            self.redraw()
        else:
            self.submit(action,keep=gesture["source"][0]=="unit")

    def click(self,e):
        value=next((v for (x1,y1,x2,y2),v in reversed(self.hits) if x1<=e.x<=x2 and y1<=e.y<=y2),None)
        if not value:
            return
        if value[0]=="button":
            value[1]()
            return
        if not self.state or self.state["winner"] is not None:
            return
        if self.state.get("phase") == "mulligan":
            if value[0] == "hand" and not self.state["mulligan_done"][self.you] and not self.mulligan_pending:
                uid = value[1]
                if uid in self.mulligan_selected:
                    self.mulligan_selected.remove(uid)
                else:
                    self.mulligan_selected.add(uid)
                self.inspect = value[2]
                self.status = f"已选择{len(self.mulligan_selected)}张替换；点击确认换牌或保留全部。"
                self.redraw()
            return
        if value[0]=="hand":
            self.selected=("hand",value[1])
            self.inspect=value[2]
            self.command_ally=None
            card=CARDS[value[2]]
            if card["kind"]=="spell" and not card.get("target"):
                self.submit(dict(type="play",hand=value[1]))
            else:
                self.status="拖动到己方后方战线部署。" if card["kind"]=="unit" else "选择目标战线。" if card.get("target")=="lane" else "拖动或点击一个合法目标。"
        elif self.selected and self.selected[0]=="hand":
            card=CARDS[self.inspect]
            a=dict(type="play",hand=self.selected[1])
            if value[0]=="lane":
                a["lane"]=value[1]
            elif value[0]=="unit":
                if card["kind"]=="unit" or card.get("target")=="lane":
                    a["lane"]=self.lookup(value[1])["lane"]
                else:
                    a["target"]=value[1]
            elif value[0]=="base" and value[1]:
                a["target"]="base"
            else:
                return
            if card["kind"]=="unit" or card.get("target")=="lane":
                if "lane" not in a:
                    self.status="请选择战线。"
                    self.redraw()
                    return
            self.submit(a)
        elif value[0]=="unit" and value[2]:
            if self.operation=="skill" and self.selected and self.inspect=="tower":
                self.command_ally=value[1]
                self.status="已选择执行友军，再点击敌军或敌方基地。"
            else:
                self.selected=("unit",value[1])
                self.inspect=value[3]
                self.operation="attack"
                self.command_ally=None
                self.status="拖动到敌军攻击、相邻空战线移动；主动技能使用右侧按钮。"
        elif self.selected and self.selected[0]=="unit":
            uid=self.selected[1]
            if self.operation=="move":
                if value[0]=="lane":
                    self.submit(dict(type="move",unit=uid,lane=value[1]),keep=True)
            elif self.operation=="skill":
                skill=CARDS[self.inspect].get("skill")
                if skill=="command" and self.command_ally and (value[0]=="unit" or value[0]=="base" and not value[1]):
                    self.submit(dict(type="skill",unit=uid,ally=self.command_ally,target=value[1] if value[0]=="unit" else "base"),keep=True)
                elif value[0] in {"lane","unit"} and skill in {"charge","airstrike","manufacture"}:
                    lane=value[1] if value[0]=="lane" else self.lookup(value[1])["lane"]
                    self.submit(dict(type="skill",unit=uid,lane=lane,option=self.factory_option),keep=True)
            elif value[0]=="unit" and not value[2]:
                self.submit(dict(type="attack",unit=uid,target=value[1]),keep=True)
            elif value[0]=="base" and not value[1]:
                self.submit(dict(type="attack",unit=uid,target="base"),keep=True)
        self.redraw()

    def lookup(self,uid):
        return next((u for p in self.state["players"] for u in p["board"] if u["uid"]==uid),None)

    def hover(self,e):
        if self.drag_state:
            return
        value=next((v for (x1,y1,x2,y2),v in reversed(self.hits) if x1<=e.x<=x2 and y1<=e.y<=y2),None)
        key=value[-1] if value and value[0] in {"hand","unit"} else None
        # 选择中的卡牌保持其详情，避免悬停敌军改变待执行法术。
        if key and not self.selected and key != self.inspect:
            self.inspect=key
            self.redraw()

    def set_operation(self,operation):
        self.operation=operation
        self.command_ally=None
        if operation=="skill" and self.selected:
            key=CARDS[self.inspect].get("skill")
            if key in {"repair","rally"}:
                self.submit(dict(type="skill",unit=self.selected[1]),keep=True)
            elif key=="command":
                self.status="先点击一个友军，再点击它要攻击的敌方目标。"
            elif key:
                self.status="点击目标战线发动技能。"
            else:
                self.status="该单位没有主动技能。"
        else:
            self.status="点击相邻空战线移动。" if operation=="move" else "点击敌军或敌方基地攻击。"
        self.redraw()

    def choose_factory(self,key):
        self.factory_option=key
        self.operation="skill"
        self.status="点击己方最后方战线制造坦克。"
        self.redraw()

    def cancel(self):
        self.drag_state=None
        if self.state and self.state.get("phase") == "mulligan" and not self.mulligan_pending:
            self.mulligan_selected.clear()
        self.selected=None
        self.command_ally=None
        self.operation="attack"
        self.status="已取消选择。"
        self.redraw()

    def submit(self,action,keep=False):
        try:
            if self.client:
                self.client.send(dict(type="action",revision=self.state["revision"],action=action))
                self.status="操作已发送。"
            else:
                self.game.act(self.you,action)
                self.state=self.game.view(self.you)
                self.status="操作完成。"
            if not keep:
                self.selected=None
            if self.selected and self.selected[0]=="unit" and not self.lookup(self.selected[1]):
                self.selected=None
        except (RuleError,OSError,ConnectionError) as error:
            self.status=str(error)
        self.redraw()
        self.schedule_ai()

    def confirm_mulligan(self, keep_all=False):
        if not self.state or self.state.get("phase") != "mulligan" or self.state["mulligan_done"][self.you] or self.mulligan_pending:
            return
        if keep_all:
            self.mulligan_selected.clear()
        cards = sorted(self.mulligan_selected)
        self.mulligan_pending = bool(self.client)
        self.submit(dict(type="mulligan", cards=cards))
        if not self.client or not self.network_ok:
            self.mulligan_pending = False
        self.redraw()

    def schedule_ai(self):
        if self.game and not self.client and self.game.turn==1 and self.game.winner is None and not self.ai_pending:
            self.ai_pending=True
            self.root.after(430,self.ai_step)

    def ai_step(self):
        self.ai_pending=False
        if self.mode!="game" or not self.game or self.client or self.game.turn!=1 or self.game.winner is not None:
            return
        try:
            self.game.act(1,self.game.ai_action(1))
            self.state=self.game.view(0)
            self.status="训练对手正在行动…" if self.game.turn==1 else "轮到你行动。"
        except RuleError as error:
            self.status=f"训练对手跳过操作：{error}"
            self.game.act(1,dict(type="end"))
            self.state=self.game.view(0)
        self.redraw()
        self.schedule_ai()

    def solo(self):
        self.save_settings()
        self.clear_widgets()
        self.mode="game"
        self.game=Game([self.deck,DEFAULT_DECK],[self.name.get() or "指挥官","训练指挥官"])
        self.game.act(1,self.game.ai_action(1))
        self.you=0
        self.state=self.game.view(0)
        self.lobby=None
        self.selected=None
        self.mulligan_selected.clear()
        self.mulligan_pending=False
        self.status="点击要替换的初始卡牌，再确认换牌。"
        self.redraw()

    def network_start(self,host):
        try:
            port=int(self.port.get())
            if not 1024<=port<=65535:
                raise ValueError("端口应在1024至65535之间。")
            if not host and not self.ip.get().strip():
                raise ValueError("请输入房主IP。")
            self.save_settings()
            if host:
                self.server=RoomServer(port,self.password.get())
            self.client=RoomClient("127.0.0.1" if host else self.ip.get().strip(),port,
                                   self.name.get(),self.deck,self.password.get(),self.server.host_token if host else None)
            self.clear_widgets()
            self.mode="game"
            self.state=None
            self.lobby=None
            self.selected=None
            self.mulligan_selected.clear()
            self.mulligan_pending=False
            self.network_ok=False
            self.status="正在连接房间…"
            self.redraw()
        except (ValueError,OSError) as error:
            if self.server:
                self.server.close()
                self.server=None
            messagebox.showerror("无法建立连接",str(error),parent=self.root)

    def host(self):
        self.network_start(True)

    def join(self):
        self.network_start(False)

    def ready(self):
        try:
            self.client.send(dict(type="ready"))
        except (OSError,ConnectionError) as error:
            self.status=str(error)
            self.redraw()

    def retry(self):
        if self.client and self.client.token:
            if self.client.channel:
                self.status="连接已经恢复。"
            else:
                if self.client.retry():
                    self.status="重新尝试连接原房间…"
                else:
                    self.status="正在自动重连，请稍候。"
        else:
            self.status="首次连接失败时，请返回主菜单核对IP与口令。"
        self.redraw()

    def pump(self):
        if self.client:
            for _ in range(30):
                try:
                    event=self.client.events.get_nowait()
                except queue.Empty:
                    break
                kind=event["type"]
                if kind=="welcome":
                    self.you=event["seat"]
                    self.network_ok=True
                    self.status="已连接房间。"
                elif kind=="state":
                    self.network_ok=True
                    previous_phase=self.state.get("phase") if self.state else None
                    self.state=event["state"]
                    self.lobby=event["lobby"]
                    if self.state and self.state.get("phase")=="mulligan":
                        if previous_phase!="mulligan":
                            self.mulligan_selected.clear()
                            self.mulligan_pending=False
                        if self.state["mulligan_done"][self.you]:
                            self.mulligan_selected.clear()
                            self.mulligan_pending=False
                            self.status="已完成开局整备，等待对方确认。"
                    elif self.state and previous_phase=="mulligan":
                        self.mulligan_pending=False
                        self.selected=None
                        self.status="双方整备完成，战役开始。"
                    if self.selected and self.selected[0]=="unit" and self.state and not self.lookup(self.selected[1]):
                        self.selected=None
                    self.redraw()
                elif kind in {"error","failed","connection"}:
                    self.mulligan_pending=False
                    self.status=event.get("message","")
                    if kind in {"failed","connection"}:
                        self.network_ok=False
                    self.redraw()
        self.root.after(80,self.pump)

    def end_or_restart(self):
        if self.state.get("phase")=="mulligan" and self.state["winner"] is None:
            self.confirm_mulligan()
        elif self.state["winner"] is None:
            self.submit(dict(type="end"))
        elif self.client:
            self.ready()
            self.status="已准备再来一局，等待对方准备。"
            self.redraw()
        else:
            self.solo()

    def concede_or_retry(self):
        if self.client and not self.network_ok:
            self.retry()
        elif self.state and self.state["winner"] is None:
            if messagebox.askyesno("撤退","是否结束本局并认输？",parent=self.root):
                self.submit(dict(type="concede"))

    def leave(self):
        if self.mode=="game" and self.state and self.state["winner"] is None:
            if not messagebox.askyesno("返回主菜单","将退出当前对局。房主退出会关闭房间，是否继续？",parent=self.root):
                return
        self.disconnect()
        self.status="选择训练，或与朋友建立双人房间。"
        self.menu()

    def disconnect(self):
        self.drag_state=None
        if self.client:
            self.client.close()
        if self.server:
            self.server.close()
        self.client=self.server=self.game=self.state=None
        self.lobby=None
        self.selected=None
        self.mulligan_selected.clear()
        self.mulligan_pending=False
        self.ai_pending=False
        self.network_ok=True

    def guide(self):
        window=tk.Toplevel(self.root)
        window.title("玩法与联机指南")
        window.geometry("820x680")
        window.configure(bg=BG)
        box=tk.Text(window,bg=BG,fg=TEXT,wrap="word",font=(FONT,12),padx=24,pady=20,relief="flat")
        box.pack(fill="both",expand=True)
        box.insert("end",GUIDE)
        box.configure(state="disabled")

    def deck_builder(self):
        window=tk.Toplevel(self.root)
        window.title("卡牌图鉴与组牌")
        window.geometry("1220x800")
        window.configure(bg=BG)
        from collections import Counter
        counts=Counter(self.deck)
        info=tk.StringVar()
        tk.Label(window,textvariable=info,bg=BG,fg=GOLD,font=(FONT,14)).pack(pady=15)
        area=tk.Frame(window,bg=BG)
        area.pack(fill="both",expand=True,padx=16)
        canvas=tk.Canvas(area,bg=BG,highlightthickness=0)
        scrollbar=tk.Scrollbar(area,orient="vertical",command=canvas.yview)
        canvas.configure(yscrollcommand=scrollbar.set)
        scrollbar.pack(side="right",fill="y")
        canvas.pack(side="left",fill="both",expand=True)
        rows=tk.Frame(canvas,bg=BG)
        canvas.create_window(0,0,window=rows,anchor="nw")
        labels={}
        def update():
            info.set(f"你的牌组  {sum(counts.values())} / 30  ·  同名最多2张")
            for key,label in labels.items():
                label.configure(text=f"{counts[key]} 张")
        def change(key,delta):
            if 0<=counts[key]+delta<=2 and (delta<0 or sum(counts.values())<30):
                counts[key]+=delta
                update()
        for i,card in enumerate(sorted(CARDS.values(),key=lambda c:(c["cost"],c["id"]))):
            row=tk.Frame(rows,bg=PANEL,padx=12,pady=8)
            row.grid(row=i,column=0,sticky="ew",pady=3)
            photo=self.card_art_photo(card["id"],140,86)
            if photo:
                tk.Label(row,image=photo,bg=PANEL).pack(side="left",padx=(0,12))
            tk.Label(row,text=f"{card['cost']:>2}  {card['name']}\n{card['attack']}/{card['health']}" if card["kind"]=="unit" else f"{card['cost']:>2}  {card['name']}\n法术",bg=PANEL,fg=GOLD,font=(FONT,11),width=20,anchor="w").pack(side="left")
            tk.Label(row,text=(" · ".join(card["tags"])+"\n" if card["tags"] else "")+card["text"],bg=PANEL,fg=TEXT,font=(FONT,10),wraplength=520,justify="left",width=62,anchor="w").pack(side="left",padx=10)
            tk.Button(row,text="−",command=lambda key=card["id"]:change(key,-1),bg=BG,fg=TEXT,relief="flat",font=(FONT,12)).pack(side="left")
            label=tk.Label(row,bg=PANEL,fg=TEAL,font=(FONT,11),width=5)
            label.pack(side="left")
            labels[card["id"]]=label
            tk.Button(row,text="+",command=lambda key=card["id"]:change(key,1),bg=BG,fg=TEXT,relief="flat",font=(FONT,12)).pack(side="left")
        rows.bind("<Configure>",lambda e:canvas.configure(scrollregion=canvas.bbox("all")))
        def wheel(e):
            if window.winfo_exists():
                canvas.yview_scroll(-int(e.delta/120),"units")
        window.bind("<MouseWheel>",wheel)
        def save():
            deck=[key for key,n in counts.items() for _ in range(n)]
            try:
                validate_deck(deck)
            except ValueError as error:
                messagebox.showerror("牌组未完成",str(error),parent=window)
                return
            self.deck=deck
            self.save_settings()
            window.destroy()
            self.status="30张牌组已保存。"
            self.redraw()
        def reset():
            counts.clear()
            counts.update(DEFAULT_DECK)
            update()
        footer=tk.Frame(window,bg=BG)
        footer.pack(pady=14)
        for text,fn in [("保存牌组",save),("恢复推荐牌组",reset),("关闭",window.destroy)]:
            tk.Button(footer,text=text,command=fn,bg=PANEL,fg=TEAL,font=(FONT,11),relief="flat",padx=22,pady=9).pack(side="left",padx=8)
        update()

    def close(self):
        self.save_settings()
        self.disconnect()
        self.root.destroy()


GUIDE = """帝国：四线战令 · 1.1

胜利目标：将敌方基地从30点生命降到0。
牌组30张，同名最多2张。双方各获得4张初始手牌，点击任意数量的牌标记替换，点击确认换牌，或点击保留全部。每人只能确认一次。新牌从当前牌堆随机抽取，再将旧牌放回并洗牌；不会立即抽回刚替换的实体牌，但可能抽到另一张同名牌。双方确认后开战，先手首回合不额外抽牌，此后每个自己的回合开始抽1张。手牌上限10，牌库耗尽后受到逐渐增加的疲劳伤害。
召唤点从1开始，每个自己的回合上限+1，最高10，并补满。借贷获得临时召唤点，下回合偿还。
四条战线从敌方后方到己方后方上下排列；同一条战线只能由一方控制，最多3个单位。普通单位只能在己方最后方部署，然后逐线移动推进；不能移动到有敌军的战线。通常部署当回合不能行动，下一回合获得2次行动。
拖动手牌到己方后方部署；拖动友军到相邻空战线移动，拖到敌军或敌方基地攻击；拖动法术到合法目标施放。黄色虚线表示合法落点，拖出战场或右键/Esc取消。仍可点击选择并使用技能按钮。

攻击与移动
普通攻击与相邻移动分别花费1次行动。近战可攻击同线或相邻线，远程相距2线，超远程相距3线。
地面单位必须清空敌军且基地处于射程内才能攻击：基地在敌方后方战线外一格，近战必须推进到敌方后方。飞行可直接攻击基地，但敌方后方的嘲讽必须先处理。
同线与相邻线交战会反击，带反击关键词的单位也可远程反击；建筑不能反击。伤害同时结算。防御对每次伤害独立减免。
飞行免疫普通地面近战；远程、超远程、对空或飞行单位可以攻击飞行。战机“仅对空”不能攻击地面单位。
突袭：部署即可行动。迅捷：每回合3行动。装弹：攻击后结束行动，下个自己的回合也无法行动，再下个回合恢复。
技能会显示冷却；坦克工厂选择轻/中坦后点击己方最后方战线。航空母舰的衍生战机先填己方后方，再填紧邻前线；满员或敌占时不生成。决策塔先选择技能，再选友军，再点其攻击目标。

Radmin VPN 双人联机
1. 两人启动Radmin VPN，进入同一个VPN网络。
2. 房主在游戏中填写名称、端口（默认47653）与可选口令，点击创建房间。
3. 另一人填写房主在Radmin VPN中显示的IPv4地址、相同端口及口令，点击加入房间。
4. 双方点击准备开战。允许该游戏程序通过Windows防火墙，房主需要允许TCP入站连接。
5. 断线时暂停对局；程序自动重连，失败后点重试连接。房主必须保持游戏和VPN运行。
6. 同一台电脑测试：开两个游戏窗口，第一个建房，第二个加入127.0.0.1。
不需要Radmin Server或远程控制软件。口令只用于熟人VPN房间的准入，不是传输加密。

手稿说明
本作保留手稿核心规则，界面采用KARDS式复古地图桌面布局，26张卡牌分别配有贴合卡名和效果的德系服装与机械、日系二次元绘画插画。照片涂改处已按可玩规则补全；完整抄录与采用值见项目中的“图片文字与规则.md”。卡牌原型有26种，手稿末段序号有重号。
"""
