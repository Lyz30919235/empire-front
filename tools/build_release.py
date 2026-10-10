"""打包已验证源码和独立Windows EXE。"""
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile
import json

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / "release"


def main():
    RELEASE.mkdir(exist_ok=True)
    subprocess.run([sys.executable,"-m","PyInstaller","--noconfirm","--clean","--onefile","--windowed",
                    "--name","EmpireFront","--distpath",str(RELEASE),"--workpath",str(ROOT/"build"),
                    "--specpath",str(ROOT/"build"),"--add-data",str(ROOT/"assets")+";assets",str(ROOT/"main.py")],cwd=ROOT,check=True)
    report = RELEASE / "exe-self-test.json"
    report.unlink(missing_ok=True)
    subprocess.run([str(RELEASE/"EmpireFront.exe"),"--self-test",str(report)],cwd=ROOT,check=True,timeout=30)
    assert json.loads(report.read_text(encoding="utf-8")) == dict(status="ok",version="1.2.0",cards=26,illustrations=26,mulligan=True,linear_lanes=True,drag=True,tk=True,tcp=True)
    with zipfile.ZipFile(RELEASE/"帝国四线战令-Windows.zip","w",zipfile.ZIP_DEFLATED) as z:
        z.write(RELEASE/"EmpireFront.exe","帝国四线战令/EmpireFront.exe")
        for name in ["README.md","图片文字与规则.md","发布说明.md"]:
            z.write(ROOT/name,f"帝国四线战令/{name}")
        if (RELEASE/"战场预览.png").exists():
            z.write(RELEASE/"战场预览.png","帝国四线战令/战场预览.png")
        if (RELEASE/"开局换牌预览.png").exists():
            z.write(RELEASE/"开局换牌预览.png","帝国四线战令/开局换牌预览.png")
    for name in ["插画一览-1.png","插画一览-2.png"]:
        if (RELEASE/name).exists():
            with zipfile.ZipFile(RELEASE/"帝国四线战令-Windows.zip","a",zipfile.ZIP_DEFLATED) as z:
                z.write(RELEASE/name,"帝国四线战令/"+name)
    files=[ROOT/"main.py",ROOT/"启动游戏.bat",ROOT/"requirements.txt",ROOT/"README.md",ROOT/"图片文字与规则.md",ROOT/"发布说明.md"]
    for folder in ["empire_front","tests","tools"]:
        files.extend((ROOT/folder).glob("*.py"))
    files.extend(f for f in (ROOT/"assets").rglob("*") if f.is_file())
    with zipfile.ZipFile(RELEASE/"帝国四线战令-Python源码.zip","w",zipfile.ZIP_DEFLATED) as z:
        for file in files:
            z.write(file,"帝国四线战令源码/"+file.relative_to(ROOT).as_posix())
    for file in RELEASE.glob("*.zip"):
        print(f"{file.name}: {file.stat().st_size/1024/1024:.1f} MB")


if __name__ == "__main__":
    main()
