# 帝国：四线战令 · Godot 2.1

依据用户的手写规则制作，现已完整迁移到 **Godot / GDScript**。包含26种卡牌及独立插画；四条上下排列的线性战线、公共与后方专属槽、箭头攻击/移动、拖动部署/施法、开局任选换牌、主动技能、30张组牌、单人训练和双人IP直连。详细玩法见 [Godot 作战操作](godot/README.md#作战操作)。

## 文档入口

需要定位上下文时使用 [PROJECT_INDEX.md](PROJECT_INDEX.md)，按当前任务选择资料。协作与读写规则见 [AGENTS.md](AGENTS.md)，接续工作见 [NOW.md](docs/context/NOW.md)。这些入口属于完整仓库；发行源码包的实际内容需单独核对，不能推断包含全部上下文文档。

## 直接运行

Windows 64位：解压 `release/EmpireFrontGodot-Windows-v2.1.zip`，双击 `EmpireFrontGodot.exe`，无需安装Python或Godot。桌面快捷方式是否存在及其目标待核实，以实际运行环境为准。

源码包：`release/EmpireFrontGodot-Source-v2.1.zip`，用Godot导入 `godot/project.godot`。完整操作、联机、构建、许可证及Android后续移植说明见 [godot/README.md](godot/README.md)。

联机：一人创建房间，另一人输入主机可达IP、相同端口（默认TCP **47653**）及可选口令；双方准备后各自确认换牌。掉线暂停、保留席位并自动重连，也可在战斗界面重试。双方必须使用同一份Godot 2.1包，不能与Godot 2.0或旧Python 1.2版互联。

## 主要操作

- 普通单位拖到己方最后方的合法空槽部署；可与敌军共处，后方两格专属槽仅守方使用。
- 按住己方单位拉出指令箭头：红色指向敌军或基地攻击，蓝色指向相邻战线空槽移动；原卡保持原位。法术仍拖向合法目标；无效操作不扣资源。
- 初始各4张牌，点击任意牌标记替换并确认，或全部保留；替代牌先抽取，旧牌随后返还牌堆洗牌。
- 点击卡牌查看详情。点选单位后使用右侧技能按钮；战线技能再点战线，调度技能先点友军再点敌人。
- Esc/右键取消；F11全屏。图鉴可组建30张牌组，同名最多2张。

## 开发与验证

规则、网络、卡面与界面分别位于 `godot/scripts/engine.gd`、`network.gd`、`card_view.gd` 和 `main.gd`。开发参考采用 [Godot GDScript Patterns](https://skills.sh/wshobson/agents/godot-gdscript-patterns)，参考原文保存在 `tools/skill-references/`，未安装全局技能。

```powershell
$godotExe = 'tools/godot-runtime/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path godot --script res://tests/test_engine.gd
& $godotExe --headless --path godot --script res://tests/test_network.gd
& $godotExe --headless --path godot --script res://tests/test_scene_ui.gd
& $godotExe --headless --path godot --script res://tests/network_ui_probe.gd
python tools/build_godot_release.py --build-only
& 'release/EmpireFrontGodot.exe' -- --ui-probe "$PWD/release/godot-exe-probe.json"
python tools/build_godot_release.py --package-only
```

2026-10-10 的既有历史测试覆盖规则、TCP、UI 与 Windows 导出 EXE，具体结果见 [审查与测试报告](godot/docs/代码审查与测试.md#最终测试)。上述命令仅为操作入口，最近实际执行范围与结果见 [NOW.md](docs/context/NOW.md#本轮核验)；测试选择与前置条件见 [RUNBOOK.md](docs/context/RUNBOOK.md)，当前验证缺口见 [RISKS.md](docs/context/RISKS.md)。

原手稿抄录、模糊处及采用规则见 [图片文字与规则.md](图片文字与规则.md)，图片内容作为设计资料。26张插画的完整提示词在 `godot/docs/插画设计.json`。旧Python源码、EXE和下载包保留，旧版操作说明见 [docs/Python1.2说明.md](docs/Python1.2说明.md)；舍弃的早期插画不在新版资源或包中。
