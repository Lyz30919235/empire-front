"""在本应用内部调用交互逻辑进行GUI集成验证，不控制其他桌面应用。"""
import copy
import json
from pathlib import Path
import sys
import tempfile
import time
import tkinter as tk
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import empire_front.app as ui
from main import enable_dpi_awareness


def click_hit(app, kind, predicate=lambda value: True):
    box, value = next((box, value) for box, value in app.hits if value[0] == kind and predicate(value))
    x1, y1, x2, y2 = box
    app.click(SimpleNamespace(x=x1+30 if kind=="lane" else (x1+x2)/2, y=(y1+y2)/2))


def refresh(app):
    app.state=app.game.view(app.you)
    app.redraw()


def screenshot(app,name):
    from PIL import ImageGrab
    root=app.root
    root.attributes("-topmost",True)
    root.lift()
    root.update()
    time.sleep(.2)
    x,y=app.canvas.winfo_rootx(),app.canvas.winfo_rooty()
    output=ROOT/"release"/name
    output.parent.mkdir(exist_ok=True)
    ImageGrab.grab(bbox=(x,y,x+app.canvas.winfo_width(),y+app.canvas.winfo_height())).save(output)
    root.attributes("-topmost",False)


def drag_hit(app,source_kind,source_pred,target_kind,target_pred):
    box,_=next((box,v) for box,v in app.hits if v[0]==source_kind and source_pred(v))
    sx,sy=(box[0]+box[2])/2,(box[1]+box[3])/2
    if target_kind:
        box,_=next((box,v) for box,v in app.hits if v[0]==target_kind and target_pred(v))
        # 战线标签空白处避免中央单位抢占落点。
        tx=box[0]+30 if target_kind=="lane" else (box[0]+box[2])/2
        ty=(box[1]+box[3])/2
    else:
        tx,ty=6,6
    app.canvas.event_generate("<ButtonPress-1>",x=int(sx),y=int(sy))
    app.canvas.event_generate("<B1-Motion>",x=int(tx),y=int(ty))
    assert app.drag_state and app.drag_state["active"]
    assert app.canvas.find_withtag("drag-overlay")
    app.canvas.event_generate("<ButtonRelease-1>",x=int(tx),y=int(ty))
    assert app.drag_state is None


def run():
    enable_dpi_awareness()
    with tempfile.TemporaryDirectory() as directory:
        ui.SAVE_DIR = Path(directory)
        root = tk.Tk()
        root.withdraw()
        root.geometry("1440x900+40+40")
        app = ui.App(root)
        errors = []
        root.report_callback_exception = lambda *args: errors.append(str(args))
        root.deiconify()
        root.update()
        assert app.mode == "menu"
        assert len(app.widgets) == 1
        app.solo()
        root.update()
        assert app.state and app.you == 0
        assert app.state["phase"]=="mulligan"
        screenshot(app,"开局换牌预览.png")
        first_uid=app.state["players"][0]["hand"][0]["uid"]
        click_hit(app,"hand",lambda v:v[1]==first_uid)
        assert first_uid in app.mulligan_selected
        app.confirm_mulligan()
        assert app.state["phase"]=="battle"
        assert first_uid not in [h["uid"] for h in app.state["players"][0]["hand"]]
        app.game.players[0]["hand"] = [dict(uid=9000, card="light_cavalry")]
        app.game.players[0]["mana"] = 10
        refresh(app)
        before=copy.deepcopy(app.game.view(0))
        drag_hit(app,"hand",lambda v:True,"lane",lambda v:v[1]==2)
        assert before==app.game.view(0), "错误部署不能消耗资源"
        drag_hit(app,"hand",lambda v:True,"lane",lambda v:v[1]==3)
        cavalry=app.game.players[0]["board"][0]
        assert cavalry["lane"]==3 and not app.game.players[0]["hand"]
        drag_hit(app,"unit",lambda v:v[2],"lane",lambda v:v[1]==2)
        assert cavalry["lane"]==2 and cavalry["actions"]==2
        before=copy.deepcopy(app.game.view(0))
        drag_hit(app,"unit",lambda v:v[2],"lane",lambda v:v[1]==0)
        assert before==app.game.view(0), "跨越战线拖动应当被拒绝"
        drag_hit(app,"unit",lambda v:v[2],"base",lambda v:not v[1])
        assert before==app.game.view(0), "地面单位必须推进到基地射程内"
        # 飞机直接攻击基地，拖出场外取消不消耗行动。
        plane=app.game.summon(0,"plane",3)
        refresh(app)
        drag_hit(app,"unit",lambda v:v[2] and v[3]=="plane","base",lambda v:not v[1])
        assert app.game.players[1]["hp"]==28
        before=copy.deepcopy(app.game.view(0))
        drag_hit(app,"unit",lambda v:v[2] and v[3]=="plane",None,None)
        assert before==app.game.view(0)
        # Esc取消之后松开鼠标不能误触结束回合按钮。
        box,_=next((box,v) for box,v in app.hits if v[0]=="unit" and v[1]==plane["uid"])
        sx,sy=int((box[0]+box[2])/2),int((box[1]+box[3])/2)
        app.canvas.event_generate("<ButtonPress-1>",x=sx,y=sy)
        app.canvas.event_generate("<B1-Motion>",x=sx+20,y=sy+20)
        app.cancel()
        box,_=next((box,v) for box,v in app.hits if v[0]=="button" and v[1]==app.end_or_restart)
        app.canvas.event_generate("<ButtonRelease-1>",x=int((box[0]+box[2])/2),y=int((box[1]+box[3])/2))
        assert before==app.game.view(0)
        # 四线独占：敌方0/1，己方2/3。
        app.game.summon(0,"carrier",2)
        app.game.summon(0,"heavy_tank",2)
        factory=app.game.summon(0,"factory",3)
        factory["actions"]=3
        app.game.summon(1,"artillery",0)
        app.game.summon(1,"archer",0)
        shield=app.game.summon(1,"shield",1)
        victim=app.game.summon(1,"infantry",1)
        app.game.players[0]["hand"]=[dict(uid=9001,card="fireball")]
        refresh(app)
        drag_hit(app,"hand",lambda v:True,"unit",lambda v:v[1]==victim["uid"])
        assert victim not in app.game.players[1]["board"]
        # 拖动己方骑兵攻击敌盾兵，实际结算反击和防御。
        cavalry["actions"]=3
        refresh(app)
        drag_hit(app,"unit",lambda v:v[1]==cavalry["uid"],"unit",lambda v:v[1]==shield["uid"])
        assert shield["hp"]==6 and cavalry["hp"]==3
        app.cancel()
        click_hit(app,"unit",lambda v:v[1]==factory["uid"])
        app.choose_factory("light_tank")
        click_hit(app,"lane",lambda v:v[1]==3)
        assert any(u["card"]=="light_tank" for u in app.game.players[0]["board"])
        # 空出后方一格放决策塔，调度耗尽行动的骑兵。
        app.game.players[0]["board"].remove(plane)
        tower=app.game.summon(0,"tower",3)
        tower["actions"]=3
        cavalry["actions"]=0
        refresh(app)
        click_hit(app,"unit",lambda v:v[1]==tower["uid"])
        app.set_operation("skill")
        click_hit(app,"unit",lambda v:v[1]==cavalry["uid"])
        click_hit(app,"unit",lambda v:v[1]==shield["uid"])
        assert shield["hp"]==5 and cavalry["actions"]==0
        app.cancel()
        app.game.players[0]["hand"] = [dict(uid=9100+i,card=key) for i,key in enumerate(["scout","fireball","heavy_cavalry","heal","medium_tank","banner","emperor"])]
        app.game.players[0]["max_mana"] = 8
        app.game.round = 8
        app.state = app.game.view(0)
        app.inspect = "carrier"
        app.redraw()
        root.update()
        # 两方视角都必须敌方后方在顶部、己方后方在底部。
        for viewer in [0,1]:
            app.you=viewer
            app.state=app.game.view(viewer)
            app.redraw()
            rows=sorted(app.lane_boxes,key=lambda lane:app.lane_boxes[lane][1])
            assert rows==([0,1,2,3] if viewer==0 else [3,2,1,0])
            assert rows[-1]==app.state["home_lane"]
            assert len({(box[0],box[2]) for box in app.lane_boxes.values()})==1
        app.you=0
        refresh(app)
        app.inspect="carrier"
        for width, height in [(1140,760),(1440,900),(1600,1000)]:
            root.geometry(f"{width}x{height}+40+40")
            root.update()
            app.redraw()
            for box, value in app.hits:
                assert 0 <= box[0] < box[2] <= app.canvas.winfo_width()+1, (box,value)
                assert 0 <= box[1] < box[3] <= app.canvas.winfo_height()+1, (box,value)
        root.geometry("1440x900+40+40")
        root.update()
        app.redraw()
        root.update_idletasks()
        # 自己测试窗口的渲染快照，无鼠标/键盘或其他桌面应用自动化。
        try:
            from PIL import ImageGrab
            output=ROOT/"release"/"战场预览.png"
            output.parent.mkdir(exist_ok=True)
            root.attributes("-topmost", True)
            root.lift()
            root.update()
            time.sleep(0.3)
            x,y=app.canvas.winfo_rootx(),app.canvas.winfo_rooty()
            ImageGrab.grab(bbox=(x,y,x+app.canvas.winfo_width(),y+app.canvas.winfo_height())).save(output)
            root.attributes("-topmost", False)
            print(f"PREVIEW {output}")
        except ImportError:
            print("Pillow unavailable; skipped optional screenshot")
        # 打开/关闭图鉴与玩法窗口，校验26张卡牌的界面确实生成。
        app.deck_builder()
        root.update()
        windows=[w for w in root.winfo_children() if isinstance(w,tk.Toplevel)]
        assert windows
        for win in windows:
            win.destroy()
        app.guide()
        root.update()
        for win in [w for w in root.winfo_children() if isinstance(w,tk.Toplevel)]:
            win.destroy()
        app.save_settings()
        assert len(json.loads((ui.SAVE_DIR/"settings.json").read_text(encoding="utf-8"))["deck"])==30
        assert not errors, errors
        app.close()
        print("GUI PASS: 换牌、拖动部署/移动/攻击/法术、非法落点与取消、镜像四线、制造、调度、图鉴、3种窗口尺寸")


if __name__ == "__main__":
    run()
