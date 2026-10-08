# 二次元卡牌插画

`cards/` 中每个PNG以卡牌的规则编号命名，与 `empire_front/cards.py` 对应。当前提供5张插画：`scout.png`、`archer.png`、`light_cavalry.png`、`vanguard.png`、`infantry.png`。其余21张尚未提供，程序会显示绘制的剪影。`prompts.json` 当前不存在。

使用统一的二次元角色、奇幻帝国军装、象牙白/橄榄绿/绯红/金色配色，并根据每张卡牌的名称与效果单独设计。没有使用KARDS的卡面、角色或美术资源；KARDS仅作为桌面布局参考。

程序用Pillow保持画面构图并裁切到各个卡面尺寸，在起手换牌、手牌、战场、详情和图鉴中使用同一张对应插画。
