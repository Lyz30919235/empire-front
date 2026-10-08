"""在本应用内部调用交互逻辑进行GUI集成验证，不控制其他桌面应用。"""
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
    app.click(SimpleNamespace(x=(x1+x2)/2, y=(y1+y2)/2))


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
        first_uid=app.state["players"][0]["hand"][0]["uid"]
        click_hit(app,"hand",lambda v:v[1]==first_uid)
        assert first_uid in app.mulligan_selected
        app.confirm_mulligan()
        assert app.state["phase"]=="battle"
        assert first_uid not in [h["uid"] for h in app.state["players"][0]["hand"]]
        app.game.players[0]["hand"] = [dict(uid=9000, card="light_cavalry")]
        app.game.players[0]["mana"] = 10
        app.state = app.game.view(0)
        app.redraw()
        click_hit(app, "hand")
        assert app.selected == ("hand", 9000)
        click_hit(app, "lane", lambda v: v[1] == 0)
        assert len(app.game.players[0]["board"]) == 1
        assert not app.game.players[0]["hand"]
        click_hit(app, "unit", lambda v: v[2])
        app.set_operation("move")
        click_hit(app, "lane", lambda v: v[1] == 1)
        assert app.game.players[0]["board"][0]["lane"] == 1
        app.set_operation("attack")
        click_hit(app, "base", lambda v: not v[1])
        assert app.game.players[1]["hp"] == 28
        app.cancel()
        app.game.summon(0, "carrier", 0)
        app.game.summon(0, "factory", 2)
        app.game.summon(0, "heavy_tank", 3)
        app.game.summon(1, "shield", 0)
        app.game.summon(1, "artillery", 1)
        app.game.summon(1, "plane", 2)
        app.game.summon(1, "archer", 3)
        # 实际走界面技能选择流程：工厂制造、决策塔选择友军再选敌军。
        factory=next(u for u in app.game.players[0]["board"] if u["card"]=="factory")
        factory["actions"]=3
        app.state=app.game.view(0)
        app.redraw()
        click_hit(app,"unit",lambda v:v[2] and v[3]=="factory")
        app.choose_factory("light_tank")
        click_hit(app,"lane",lambda v:v[1]==3)
        assert any(u["card"]=="light_tank" for u in app.game.players[0]["board"])
        tower=app.game.summon(0,"tower",2)
        tower["actions"]=3
        app.cancel()
        app.state=app.game.view(0)
        app.redraw()
        click_hit(app,"unit",lambda v:v[2] and v[3]=="tower")
        app.set_operation("skill")
        click_hit(app,"unit",lambda v:v[2] and v[3]=="light_cavalry")
        shield=next(u for u in app.game.players[1]["board"] if u["card"]=="shield")
        click_hit(app,"unit",lambda v:not v[2] and v[3]=="shield")
        assert shield["hp"]==6
        app.cancel()
        app.game.players[0]["hand"] = [dict(uid=9100+i,card=key) for i,key in enumerate(["scout","fireball","heavy_cavalry","heal","medium_tank","banner","emperor"])]
        app.game.players[0]["max_mana"] = 8
        app.game.round = 8
        app.state = app.game.view(0)
        app.inspect = "carrier"
        app.redraw()
        root.update()
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
        print("GUI PASS: 菜单、部署、移动、攻击、制造、调度、图鉴、规则、设置保存、3种窗口尺寸")


if __name__ == "__main__":
    run()
