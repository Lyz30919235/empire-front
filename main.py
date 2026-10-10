"""直接运行 python main.py 或使用发行版 EXE。"""
import sys
import traceback
from pathlib import Path


def enable_dpi_awareness():
    if sys.platform == "win32":
        import ctypes
        try:
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except (AttributeError, OSError):
            pass


def self_test(report_path):
    """发行版内执行Tk和规则引擎冒烟测试，不接触玩家设置。"""
    import json
    import tempfile
    import tkinter as tk
    import empire_front.app as ui
    from empire_front.cards import CARDS
    from empire_front.network import RoomServer, Channel
    import socket
    from empire_front import VERSION
    with tempfile.TemporaryDirectory() as temp:
        ui.SAVE_DIR = Path(temp)
        root = tk.Tk()
        app = ui.App(root)
        root.update()
        app.solo()
        root.update()
        assert app.state and len(app.hits) > 5
        assert app.state["phase"] == "mulligan"
        app.confirm_mulligan(True)
        assert app.state["phase"] == "battle"
        assert app.state["home_lane"] == 3
        assert sorted(app.lane_boxes,key=lambda lane:app.lane_boxes[lane][1]) == [0,1,2,3]
        app.game.players[0]["hand"] = [dict(uid=9000,card="light_cavalry")]
        app.game.players[0]["mana"] = 10
        app.state = app.game.view(0)
        app.redraw()
        box=next(box for box,value in app.hits if value[0]=="hand")
        x,y=int((box[0]+box[2])/2),int((box[1]+box[3])/2)
        rear=app.lane_boxes[3]
        tx,ty=int(rear[0]+30),int((rear[1]+rear[3])/2)
        app.canvas.event_generate("<ButtonPress-1>",x=x,y=y)
        app.canvas.event_generate("<B1-Motion>",x=tx,y=ty)
        assert app.drag_state["active"]
        app.canvas.event_generate("<ButtonRelease-1>",x=tx,y=ty)
        assert app.game.players[0]["board"][0]["lane"] == 3
        illustrated = sum(app.card_art_photo(key,96,64) is not None for key in CARDS)
        assert illustrated == len(CARDS), f"缺少卡牌插画：{illustrated}/{len(CARDS)}"
        server = RoomServer(0, bind="127.0.0.1")
        channel = Channel(socket.create_connection(("127.0.0.1", server.port), timeout=5))
        channel.send(dict(type="hello",version=VERSION,name="self-test",deck=app.deck,host_token=server.host_token))
        assert channel.receive()["type"] == "welcome"
        channel.close()
        server.close()
        app.close()
        Path(report_path).write_text(json.dumps(dict(status="ok",version=VERSION,cards=len(CARDS),illustrations=illustrated,mulligan=True,linear_lanes=True,drag=True,tk=True,tcp=True)),encoding="utf-8")


def main():
    import tkinter as tk
    from tkinter import messagebox
    from empire_front.app import App
    root = tk.Tk()
    def report(exc, value, tb):
        path = Path.home() / ".empire_front" / "error.log"
        try:
            path.parent.mkdir(exist_ok=True)
            path.write_text("".join(traceback.format_exception(exc, value, tb)), encoding="utf-8")
        except OSError:
            pass
        messagebox.showerror("游戏错误", f"{value}\n错误详情：{path}", parent=root)
    root.report_callback_exception = report
    App(root)
    root.mainloop()


if __name__ == "__main__":
    enable_dpi_awareness()
    if len(sys.argv) == 3 and sys.argv[1] == "--self-test":
        self_test(sys.argv[2])
    else:
        main()
