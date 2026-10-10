# 项目映射

## 运行与修改对象

以下是任务定位关系，不是全目录清单。先选修改对象，再搜索相应符号或卡牌键。

|对象|位置|用途与边界|
|---|---|---|
|当前 Godot 项目|[project.godot](../../godot/project.godot)、[main.tscn](../../godot/main.tscn)|引擎配置与主场景|
|规则与 AI|[engine.gd](../../godot/scripts/engine.gd)|权威游戏状态、合法动作与规则结算|
|双人网络|[network.gd](../../godot/scripts/network.gd)|房主权威 TCP 状态与客户端通信|
|界面与卡面|[main.gd](../../godot/scripts/main.gd)、[card_view.gd](../../godot/scripts/card_view.gd)|菜单、交互、卡牌显示|
|公开结算表现|[battle_fx.gd](../../godot/scripts/battle_fx.gd)|权威事件驱动的主题特效、合成音效、去重与播放队列|
|当前卡牌与默认牌组|[cards.json](../../godot/assets/data/cards.json)|当前 Godot 运行数据；不要仅修改旧 Python 数据|
|当前插画|`godot/assets/cards/`；[插画设计.json](../../godot/docs/插画设计.json)|按卡牌键定位资源和设计条目，不默认全文读取数据|
|规则来源|[图片文字与规则.md](../../图片文字与规则.md)|手稿转录与补全；Godot 目录内同名文件为源码包快照|
|测试|`godot/tests/`；入口见 [RUNBOOK.md](RUNBOOK.md)|规则、网络、UI 及针对性回归|
|导出配置|[export_presets.cfg](../../godot/export_presets.cfg)|现有 Windows Desktop 预设，导出至 `release/EmpireFrontGodot.exe`|
|构建与模板工具|[build_godot_release.py](../../tools/build_godot_release.py)、[download_godot_templates.py](../../tools/download_godot_templates.py)|开发工具；玩家运行 EXE 不需要 Python|
|本地交付物|`release/EmpireFrontGodot.exe`、`release/EmpireFrontGodot-Windows-v2.1.zip`、`release/EmpireFrontGodot-Source-v2.1.zip`|已生成的当前产物；证据与验收状态查NOW，不由文件存在推断全部验证。旧2.0包保留|
|旧 Python 版本|`main.py`、`empire_front/`、`tests/`；[旧版说明](../Python1.2说明.md)|历史版本，不是当前 Godot 修改入口|
|历史资料|[history/README.md](history/README.md)|迁移约定、旧版与历史证据的条件索引|

## 版本与配置关系

2026-10-11定向核验并修改项目与导出配置：项目名“帝国：四线战令”，项目版本`2.1.0`，Windows文件/产品版本`2.1.0.0`，入口`res://main.tscn`；视口`1600 × 1000`，拉伸模式`canvas_items`、比例`keep`，渲染方式`gl_compatibility`。协议版本在`network.gd`，2.1与2.0不兼容；包名由构建脚本读取项目主/次版本生成。

2026-10-11执行本地引擎`--version`返回`4.7.2.stable.official.ed1daf0bf`。开发工具可使用`tools/godot-runtime/`中的本地运行库，但该目录不是游戏源码或玩家必备安装项。

设置存储和旧设置兼容关系沿用 [图鉴、牌组与设置](../../godot/README.md#图鉴牌组与设置)；不保存房间口令。设备具体安装路径及桌面快捷方式目标由运行环境确认，不写入个人绝对路径。

## 部署边界

当前预设为 Windows；Android 方法及缺口见 [RUNBOOK.md](RUNBOOK.md#android)。兼容入口与物理项目目录指向同一份文件，不应当作两套项目维护。远程同步状态仅从 [NOW.md](NOW.md#完成与证据边界) 获取，不能由本地目录或包名推断。
