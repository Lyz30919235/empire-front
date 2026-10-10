"""排版插画缩略图用于人工核查；不修改游戏插画源文件。"""
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from empire_front.cards import CARDS


def main():
    font=ImageFont.truetype("C:/Windows/Fonts/msyh.ttc",22)
    small=ImageFont.truetype("C:/Windows/Fonts/msyh.ttc",16)
    entries=list(CARDS.values())
    for page in range(2):
        cards=entries[page*13:(page+1)*13]
        sheet=Image.new("RGB",(1560,1200),"#252a22")
        draw=ImageDraw.Draw(sheet)
        for index,card in enumerate(cards):
            x,y=(index%4)*390,(index//4)*300
            with Image.open(ROOT/"assets"/"cards"/f"{card['id']}.png") as source:
                thumb=ImageOps.fit(source.convert("RGB"),(378,245))
                sheet.paste(thumb,(x+6,y+6))
            draw.text((x+9,y+253),card["name"],font=font,fill="#e9dfc5")
            label=f"费用 {card['cost']}  ·  "+(" / ".join(map(str,[card['attack'],card['health']])) if card["kind"]=="unit" else "法术")
            draw.text((x+9,y+280),label,font=small,fill="#abb99a")
        path=ROOT/"release"/f"插画一览-{page+1}.png"
        sheet.save(path)
        print(path)


if __name__=="__main__":
    main()
