"""复古军事桌面：地图、纸质军牌、指挥部与手牌。所有素材为原创。"""
import math
import random
from pathlib import Path
import sys
import tkinter as tk
from .cards import CARDS
try:
    from PIL import Image, ImageOps, ImageTk
except ImportError:
    Image = ImageOps = ImageTk = None

PAPER = "#d8cfb8"
INK = "#282b24"
FADED = "#656558"
OLIVE = "#8c9b68"
RUST = "#a94e36"
CREAM = "#e8dfc6"


class TabletopRenderer:
    def backdrop(self):
        c = self.canvas
        w, h = c.winfo_width(), c.winfo_height()
        c.create_rectangle(0,0,w,h,fill="#242820",outline="")
        # 木桌的细纹与铺开的旧作战地图，固定随机种子避免重绘闪动。
        rng = random.Random(17)
        for y in range(0,h,5):
            c.create_line(0,y,w,y+rng.randrange(-2,3),fill=rng.choice(["#292d24","#25291f","#2d3027"]))
        c.create_rectangle(12,43,w-12,h-17,fill="#777c62",outline="#a7a58b",width=2)
        for x in range(30,w-15,75):
            c.create_line(x,45,x,h-18,fill="#82866b")
        for y in range(63,h-15,75):
            c.create_line(14,y,w-15,y,fill="#82866b")
        # 等高线、河流与虚线公路构成纸面地图；与可点击战线不冲突。
        for band in range(18):
            points=[]
            for x in range(14,w-13,28):
                y=70+band*46+28*math.sin(x/180+band*0.57)+14*math.cos(x/83+band)
                if y < h-20:
                    points.extend((x,y))
            if len(points)>5:
                c.create_line(*points,fill="#6c735a",smooth=True,width=1)
        river=[]
        for y in range(45,h-16,16):
            river.extend((w*.39+46*math.sin(y/140)+19*math.sin(y/51),y))
        c.create_line(*river,fill="#697e79",width=13,smooth=True)
        c.create_line(*river,fill="#8c9c89",width=4,smooth=True)
        c.create_line(25,h*.61,w*.57,85,w-20,h*.35,fill="#c0b99d",width=2,dash=(7,5))
        for i in range(30):
            x,y=rng.randint(35,max(36,w-40)),rng.randint(65,max(66,h-45))
            c.create_rectangle(x,y,x+5,y+4,fill="#676d55",outline="")
        # 地图内缘形成纸张压边。
        c.create_rectangle(24,55,w-24,h-29,outline="#93967b",width=1)

    def button(self,x,y,w,h,label,action,accent=False):
        self.rect(x+3,y+3,w,h,"#242b22","#242b22")
        self.rect(x,y,w,h,"#69764b" if accent else "#c9c2aa","#c0c59a" if accent else "#696b58",2)
        self.canvas.create_line(x+3,y+3,x+w-3,y+3,fill="#98a875" if accent else "#e6dfc7")
        self.text(x+w/2,y+h/2,label,11,"#f3eedb" if accent else INK,"center",bold=True)
        self.hit((x,y,x+w,y+h),("button",action))

    def card_art_photo(self,key,w,h):
        if not hasattr(self,"art_images"):
            self.art_images={}
        cachekey=(key,int(w),int(h))
        if cachekey not in self.art_images:
            base=Path(getattr(sys,"_MEIPASS",Path(__file__).resolve().parents[1]))
            file=base/"assets"/"cards"/f"{key}.png"
            try:
                if Image is None:
                    self.art_images[cachekey]=None
                else:
                    with Image.open(file) as original:
                        frame=ImageOps.fit(original.convert("RGB"),(max(1,int(w)),max(1,int(h))),method=Image.Resampling.LANCZOS,centering=(.5,.4))
                        self.art_images[cachekey]=ImageTk.PhotoImage(frame,master=self.root)
            except (OSError,tk.TclError,ValueError):
                self.art_images[cachekey]=None
        return self.art_images[cachekey]

    def illustration(self,x,y,w,h,key):
        c=self.canvas
        category="tank" if key in {"heavy_tank","medium_tank","light_tank","artillery","anti_air"} else "air" if key in {"plane","carrier"} else "industry" if key in {"factory","tower"} else "soldier"
        if CARDS[key]["kind"]=="spell":
            category="industry" if key in {"fireball","arrows"} else "soldier"
        picture=self.card_art_photo(key,w,h)
        if picture:
            # 插画保留完整比例，卡面剩余部分作为照片冲印留边。
            c.create_rectangle(x,y,x+w,y+h,fill="#43493a",outline="")
            c.create_image(x+w/2,y+h/2,image=picture)
            return
        # 无素材时可独立运行的原创纸面剪影。
        c.create_rectangle(x,y,x+w,y+h,fill="#969987",outline="")
        c.create_rectangle(x,y+h*.58,x+w,y+h,fill="#6c7059",outline="")
        c.create_polygon(x,y+h*.6,x+w*.23,y+h*.3,x+w*.51,y+h*.53,x+w*.74,y+h*.25,x+w,y+h*.55,fill="#828773",outline="")
        if category=="tank":
            c.create_polygon(x+w*.12,y+h*.77,x+w*.22,y+h*.5,x+w*.67,y+h*.5,x+w*.87,y+h*.72,x+w*.8,y+h*.85,x+w*.2,y+h*.86,fill="#303b2f",outline="#afb098")
            c.create_rectangle(x+w*.34,y+h*.34,x+w*.64,y+h*.56,fill="#394334",outline="#aaa98c")
            c.create_line(x+w*.51,y+h*.42,x+w*.92,y+h*.34,fill="#2d352b",width=5)
            for i in range(5):
                xx=x+w*(.25+.115*i)
                c.create_oval(xx-5,y+h*.7,xx+5,y+h*.85,fill="#1e2922",outline="#969a7c")
        elif category=="air":
            c.create_polygon(x+w*.11,y+h*.65,x+w*.47,y+h*.39,x+w*.63,y+h*.12,x+w*.68,y+h*.38,x+w*.9,y+h*.63,x+w*.66,y+h*.56,x+w*.54,y+h*.87,x+w*.42,y+h*.82,x+w*.51,y+h*.52,fill="#333e37",outline="#d0cdb3")
        elif category=="industry":
            for i in range(4):
                xx=x+w*(.09+.21*i)
                c.create_rectangle(xx,y+h*(.42-.06*(i%2)),xx+w*.18,y+h*.86,fill="#43493b",outline="#b7b69b")
            c.create_rectangle(x+w*.72,y+h*.16,x+w*.8,y+h*.7,fill="#444b3f",outline="")
        else:
            for i in range(3):
                xx=x+w*(.27+i*.24)
                yy=y+h*(.38+i*.035)
                c.create_oval(xx-7,yy-10,xx+7,yy+6,fill="#30392d",outline="")
                c.create_line(xx-8,yy-5,xx+8,yy-5,fill="#c4c0a0",width=2)
                c.create_polygon(xx-8,yy+5,xx+9,yy+5,xx+15,y+h*.86,xx-13,y+h*.86,fill="#3a4433",outline="")
                c.create_line(xx-10,yy+21,xx+18,yy+14,fill="#242e25",width=3)

    def base_bar(self,x,y,width,player,color,friendly):
        # 指挥部以地图中央的实体纸牌呈现，侧边保留手牌与资源信息。
        c=self.canvas
        px=x+width/2-114
        self.rect(px+3,y+3,228,48,"#414738","#414738")
        self.rect(px,y,228,48,"#c6c0aa","#4b5543",2)
        self.text(px+12,y+7,"己方指挥部" if friendly else "敌方指挥部",9,FADED)
        self.text(px+12,y+23,player["name"],11,INK,bold=True,width=145)
        c.create_oval(px+177,y+5,px+217,y+44,fill="#53694f" if friendly else "#804e3d",outline="#d7c9a6",width=2)
        self.text(px+197,y+25,str(max(0,player["hp"])),17,CREAM,"center",bold=True)
        self.text(x+6,y+10,f"{player['name']}\n手牌 {player['hand_count']} · 牌库 {player['deck_count']}",10,INK,width=190)
        self.text(x+width-8,y+13,f"召唤点 {player['mana']} / {player['max_mana']}",11,CREAM,"ne",bold=True)
        self.hit((px,y,px+228,y+48),("base",friendly))

    def draw_unit(self,x,y,w,h,u,friendly):
        selected=self.selected==("unit",u["uid"])
        c=self.canvas
        border="#e9d27c" if selected else "#4b6141" if friendly else "#85533d"
        self.rect(x+3,y+4,w,h,"#464b3b","#464b3b")
        self.rect(x,y,w,h,PAPER,border,3 if selected else 2)
        artw=w*.45
        self.illustration(x+4,y+4,artw,h-8,u["card"])
        rx=x+artw+12
        self.text(rx,y+6,CARDS[u["card"]]["name"].replace("帝国","",1),9,INK,width=w-artw-18,bold=True)
        by=y+h-31
        for xx,value,fill in [(rx+11,u["attack"],"#8c493a"),(x+w-17,u["hp"],"#526243")]:
            c.create_oval(xx-10,by-10,xx+10,by+10,fill=fill,outline="#e6d7b8")
            self.text(xx,by,str(value),10,CREAM,"center",bold=True)
        self.text((rx+x+w)/2,by,f"盾{u['armor']}" if u["armor"] else "",8,FADED,"center")
        if u["reload"] or u["reloading"]:
            label="装弹"
        elif u["cooldown"]:
            label=f"行动{u['actions']} · 冷却{u['cooldown']}"
        else:
            label=f"行动 {u['actions']}" if u["actions"] else "待命"
        self.text((rx+x+w-8)/2,y+h-12,label,8,INK,"center",width=w-artw-15)
        self.hit((x,y,x+w,y+h),("unit",u["uid"],friendly,u["card"]))

    def draw_hand(self,x,y,w,h,hand,mana,mulligan=False):
        c=self.canvas
        card=CARDS[hand["card"]]
        marked=hand["uid"] in self.mulligan_selected if mulligan else self.selected==("hand",hand["uid"])
        if marked and not mulligan:
            y-=9
        self.rect(x+4,y+5,w,h,"#3b4232","#3b4232")
        self.rect(x,y,w,h,"#e0d7bf","#d8bc65" if marked else "#444d3d",3 if marked else 2)
        self.rect(x+4,y+4,w-8,24,"#575f42","#575f42")
        self.text(x+w/2,y+16,"帝国 · " + ("战术指令" if card["kind"]=="spell" else "作战单位"),8,CREAM,"center")
        art_h=max(48,h*.37)
        self.illustration(x+5,y+32,w-10,art_h,card["id"])
        self.text(x+w/2,y+art_h+48,card["name"].replace("帝国","",1),11 if w>120 else 9,INK,"center",width=w-8,bold=True)
        c.create_oval(x+7,y+29,x+33,y+55,fill="#282b23",outline="#bbae76",width=2)
        self.text(x+20,y+42,str(card["cost"]),13,"#e2cb72" if card["cost"]<=mana or mulligan else "#8d9181","center",bold=True)
        tags=" · ".join(card["tags"]) or ("战术法术" if card["kind"]=="spell" else "帝国陆军")
        self.text(x+w/2,y+h-37,tags,7,FADED,"center",width=w-12)
        if card["kind"]=="unit":
            for xx,value,fill in [(x+19,card["attack"],"#8d4935"),(x+w-19,card["health"],"#546345")]:
                c.create_oval(xx-12,y+h-32,xx+12,y+h-8,fill=fill,outline="#f0e2c6")
                self.text(xx,y+h-20,str(value),12,CREAM,"center",bold=True)
            self.text(x+w/2,y+h-20,"攻击 / 生命",7,FADED,"center")
        else:
            self.text(x+w/2,y+h-20,"命 令",10,INK,"center",bold=True)
        if mulligan and marked:
            self.rect(x+8,y+h/2-19,w-16,38,"#925238","#e5c88d",2)
            self.text(x+w/2,y+h/2,"替  换",13,CREAM,"center",bold=True)
        self.hit((x,y,x+w,y+h),("hand",hand["uid"],card["id"]))

    def draw_mulligan(self,w,h):
        own=self.state["players"][self.you]
        done=self.state["mulligan_done"][self.you]
        other_done=self.state["mulligan_done"][1-self.you]
        px=max(55,(w-950)/2)
        self.rect(px+7,85,w-2*px,h-170,"#3f4636","#3f4636")
        self.rect(px,78,w-2*px,h-170,"#c9c3ac","#515a43",3)
        self.text(w/2,112,"开 局 整 备",27,INK,"center",bold=True)
        self.text(w/2,165,"点击任意初始卡牌标记替换，再确认。也可以保留全部。",12,FADED,"center")
        self.text(w/2,199,"新牌先从原牌堆抽取，旧牌随后放回并洗牌。双方确认后开战。",10,FADED,"center")
        hand=own["hand"]
        cw=min(166,(w-2*px-100)/max(1,len(hand))-16)
        ch=228
        start=w/2-(len(hand)*(cw+16)-16)/2
        for i,card in enumerate(hand):
            self.draw_hand(start+i*(cw+16),245,cw,ch,card,0,mulligan=True)
        self.text(w/2,502,"你已完成整备，等待对方…" if done else f"已选 {len(self.mulligan_selected)} / {len(hand)} 张替换",13,INK,"center",bold=True)
        self.text(w/2,538,"对方已确认" if other_done else "对方正在整备",11,"#486343" if other_done else FADED,"center")
        if not done:
            self.button(w/2-225,h-175,220,46,"确认换牌",self.confirm_mulligan,True)
            self.button(w/2+15,h-175,210,46,"保留全部",lambda:self.confirm_mulligan(True))
        self.button(32,h-66,140,35,"主菜单",self.leave)
        if self.client and not self.network_ok:
            self.button(w-176,h-66,140,35,"重试连接",self.retry)
        self.text(w/2,h-60,self.status,10,CREAM,"center",width=w-380)

    def draw_game(self,w,h):
        if self.state.get("phase")=="mulligan" and self.state["winner"] is None:
            self.draw_mulligan(w,h)
            return
        s,p=self.state,self.you
        own,enemy=s["players"][p],s["players"][1-p]
        sw=268
        bw=w-sw-38
        sx=w-sw-17
        field_bottom=h-230
        top=128
        rowh=(field_bottom-64-top)/4
        self.text(26,14,"EMPIRE  /  帝国 · 四线战令",15,CREAM,bold=True)
        turn="你的回合" if s["turn"]==p else "对手回合"
        if s["winner"] is not None:
            turn="平局" if s["winner"]==-1 else "胜利" if s["winner"]==p else "失利"
        elif not self.network_ok or self.lobby and not all(x and x["online"] for x in self.lobby):
            turn="断线 · 战役暂停"
        self.text(bw-8,17,f"第 {s['round']:02} 轮  |  {turn}",12,"#dfd1a9","ne",bold=True)
        self.base_bar(26,70,bw-22,enemy,RUST,False)
        self.base_bar(26,field_bottom-53,bw-22,own,OLIVE,True)
        self.lane_boxes={}
        order=list(range(4)) if p==0 else list(reversed(range(4)))
        for index,lane in enumerate(order):
            y=top+index*rowh
            units=[(owner,u) for owner in [1-p,p] for u in s["players"][owner]["board"] if u["lane"]==lane]
            controller=units[0][0] if units else None
            shade="#606f50" if controller==p else "#7c6856" if controller==1-p else "#777e65"
            self.rect(26,y,bw-24,rowh-5,shade,"#adb090",1)
            label=["敌方后方","敌方前线","己方前线","己方后方"][index]
            self.text(37,y+12,label,10,CREAM,bold=True)
            self.text(37,y+36,"敌军控制" if controller==1-p else "友军控制" if controller==p else "待占领",8,"#ded8bf")
            box=(26,y,bw+2,y+rowh-5)
            self.lane_boxes[lane]=box
            self.hit(box,("lane",lane))
            cardw=min(218,(bw-150)/3-10)
            start=145+(bw-145-len(units)*(cardw+12)+12)/2
            for j,(owner,u) in enumerate(units):
                self.draw_unit(start+j*(cardw+12),y+8,cardw,rowh-21,u,owner==p)
        # 右侧情报纸张，卡牌详情和操作区遵循同一纸面视觉。
        self.rect(sx+4,64,sw,h-84,"#4a503e","#4a503e")
        self.rect(sx,60,sw,h-84,"#cfc8b0","#555e48",2)
        self.text(sx+15,77,"作战档案",14,INK,bold=True)
        inspected=CARDS.get(self.inspect or "")
        if inspected:
            self.illustration(sx+15,111,sw-30,110,inspected["id"])
            self.text(sx+15,233,inspected["name"],15,INK,bold=True)
            self.text(sx+15,266,f"费用 {inspected['cost']} · 攻击 {inspected['attack']} · 生命 {inspected['health']}" if inspected["kind"]=="unit" else f"战术指令 · 费用 {inspected['cost']}",9,FADED)
            self.text(sx+15,292," · ".join(inspected["tags"]),9,"#4c6545",width=sw-30)
            self.text(sx+15,322,inspected["text"],9 if h<830 else 10,INK,width=sw-30)
        else:
            self.text(sx+15,126,"悬停查看卡牌档案\n\n拖动手牌到己方最后方部署\n拖动友军到相邻空战线移动\n拖动友军到敌军或基地攻击\n\n拖动法术到目标施放\n点击单位后可使用技能按钮\n\n右键 / Esc 取消选择",11,FADED,width=sw-30)
        cy=h-375
        if self.selected and self.selected[0]=="unit":
            self.button(sx+12,cy,76,32,"攻击",lambda:self.set_operation("attack"),self.operation=="attack")
            self.button(sx+96,cy,76,32,"移动",lambda:self.set_operation("move"),self.operation=="move")
            self.button(sx+180,cy,76,32,"技能",lambda:self.set_operation("skill"),self.operation=="skill")
            if self.inspect=="factory":
                self.button(sx+12,cy+42,118,28,"轻坦 · 2 点",lambda:self.choose_factory("light_tank"),self.factory_option=="light_tank")
                self.button(sx+140,cy+42,116,28,"中坦 · 3 点",lambda:self.choose_factory("medium_tank"),self.factory_option=="medium_tank")
        ly=cy+85
        self.canvas.create_line(sx+15,ly-10,sx+sw-15,ly-10,fill="#a29f87")
        self.text(sx+15,ly,"战况记录",10,"#68694c",bold=True)
        for j,line in enumerate(s["log"][-3:]):
            self.text(sx+15,ly+24+j*37,line,9,FADED,width=sw-30)
        self.button(sx+12,h-132,sw-24,43,"结束回合" if s["winner"] is None else "再来一局",self.end_or_restart,True)
        self.button(sx+12,h-77,116,32,"主菜单",self.leave)
        self.button(sx+140,h-77,116,32,"撤退 / 重连",self.concede_or_retry)
        self.rect(20,h-217,bw-1,185,"#4e5841","#889174")
        self.text(29,h-211,f"手牌 {own['hand_count']}/10   ·   牌库 {own['deck_count']}   ·   召唤点 {own['mana']}/{own['max_mana']}",10,CREAM)
        hand=own["hand"]
        cw=min(145,(bw-40)/max(1,len(hand))-6)
        total=len(hand)*(cw+6)-6
        start=26+(bw-22-total)/2
        for i,card in enumerate(hand):
            self.draw_hand(start+i*(cw+6),h-187,cw,156,card,own["mana"])
        self.text(28,h-19,self.status,9,CREAM,width=bw-15)
