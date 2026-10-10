# 当前状态

## 当前目标与进展

2026-10-11 GitHub同步：已按用户授权提交并上传Godot v2.1源码、资源、文档及必要验证记录，版本标签为 `v2.1.0`；GitHub上的源码提交与标签对应关系已核实，标签指向 `ee65afd`，main继续承载同步状态文档。本轮未修改游戏行为或重新测试、构建，EXE与ZIP仍保留在本地。

此前文档维护已完成按需上下文、写入分工及可靠接续的基础文档完善。现有基础文档职责齐全，沿用原结构；根 AGENTS 已包含完整的七条读取规则和七条写入规则。维护中补充交付要求、明确既有记录的证据边界，并将操作执行状态统一指向本页。

以下游戏进展与测试数字沿用此前开发记录。此前文档维护只定向确认 `godot/project.godot` 中的项目名、版本 `2.1.0` 和入口 `res://main.tscn`；本轮Git同步未复跑游戏测试或构建。

2026-10-11：用户确认的Godot 2.1战线槽位、指令箭头、单线箭雨、基地攻击与统一音画改造已实施，并完成本地Windows构建交付。每线5公共槽，两端各2守方专属槽；手牌仍只部署己方后方，敌军存在不阻止合法进入。已确认选择见[DECISIONS](DECISIONS.md)，采用规则见[根规则](../../图片文字与规则.md#为可玩联机一致性补全的规则)，卡牌需求继续维护在[编辑文档](卡牌描述编辑.md)。

运行对象见[MAP](MAP.md)。双方联机须使用同一份v2.1包，旧2.0握手被拒绝；已有设置和牌组保持原存储入口。此前开发记录注明探针没有持久化修改用户设置或牌组。

## 完成与证据边界

|事项|状态与证据|
|---|---|
|规则与AI|稳定槽位、指定/自动落位、敌我共处、统一容量与衍生召唤；基地取消清敌条件；箭雨选有敌军的一条线，保留4费2伤害与护甲减伤；普通1/迅捷2基础行动保持|
|交互与音画|场上卡牌固定，红色攻击/蓝色移动箭头，手牌拖动及点击选目标保留；26卡与6主动技能有主题映射，成功公开事件驱动双方/AI，死亡位置保留、重复及重连不重播；卡面持续显示行动、装甲与装弹/冷却|
|版本|项目2.1.0、Windows文件/产品2.1.0.0、协议2.1；包名读取项目主/次版本|
|测试通过|规则14组/400775断言、80局AI全完成并打出26种卡；TCP2062检查、场景109检查、双端音画41检查、最终Windows EXE116检查，均0失败。原始证据见下方|
|本地产物|Windows与源码v2.1 ZIP已生成，双包CRC通过；包内EXE与最终探针哈希一致，源码包16个直接相关文件与工作树逐字节一致；权威大小与SHA-256见[包验证记录](../../release/godot-package-verification-v2.1.json)。旧2.0 ZIP保留|
|用户验收与新设备安装|待核实；本机运行与自动检查不等于新设备安装或用户音质验收|
|远程同步与发布|2026-10-11已按用户授权推送至[GitHub仓库](https://github.com/Lyz30919235/empire-front)，默认分支main；[v2.1.0标签](https://github.com/Lyz30919235/empire-front/tree/v2.1.0)对应[源码提交ee65afd](https://github.com/Lyz30919235/empire-front/commit/ee65afd74f2804c82034e13408c3f30f6aa0984b)。生成记录与运行缓存不入库，EXE/ZIP沿用忽略规则保留本地，尚未创建GitHub Release|

## 阻塞与下一步

本轮GitHub同步无阻塞，完成后等待用户下一项任务；后续 AI 按 [索引](../../PROJECT_INDEX.md) 选择资料并核对对应记录的日期与范围。此前开发记录注明本地实施、验证和打包无阻塞。Windows交付入口为[游戏包](../../release/EmpireFrontGodot-Windows-v2.1.zip)，接收者解压运行EmpireFrontGodot.exe；开发入口为[源码包](../../release/EmpireFrontGodot-Source-v2.1.zip)。双方更新到同一份2.1包后联机。

真实跨设备、Android与主观音质仍待验收，见[RISKS](RISKS.md)。重骑冲锋摘要与技能说明的既有冲突保留，本次未变更卡牌需求或游戏规则。源码以后再次变化需重新验证和构建。

## 本轮核验

GitHub同步核验（2026-10-11）：提交前检查暂存文本中的秘密模式和个人设备路径，无命中；暂存改动 `git diff --cached --check` 通过。178个文件已提交，正常推送main与附注标签成功；GitHub接口核实首次推送后的main与 `v2.1.0` 均指向源码提交 `ee65afd`，随后以独立文档提交记录同步结果，保留版本标签。本轮只执行Git与提交整理检查，未复跑游戏测试、新设备安装、跨设备联机或Android验证。

此前文档维护（2026-10-11）：检查范围为九份基础文档的职责、七条读取规则与七条写入规则、当时定点改动及这些文档的直接关联文件和锚点。检查方式为文档链接解析、改动前后对比和限定文件的 `git diff --check`（含未跟踪文件与改前副本的比较）；138 处项目内链接及锚点检查通过，五份文件定点修改、四份文件保持原样，读写规则与既有游戏测试证据条目完整保留。非目标文件保持原样；当时未执行游戏测试、新设备安装、跨设备联机或 Android 验证。

以下为此前游戏开发记录（2026-10-11），对象为最终2.1源码、Windows EXE及两个ZIP；数字与证据入口保留，属于当时任务的直接证据。本轮未复跑，不能将这些数字作为Git同步任务的新测试结果。

- 本地Godot --version：4.7.2.stable.official.ed1daf0bf；构建脚本Python编译检查通过。
- --headless --path godot --script res://tests/test_engine.gd：退出0；14组、400775断言、0失败，80局26/26卡牌覆盖；[规则日志](../../godot/docs/battle-engine-20261011.log)。
- test_network.gd：退出0；2062检查、0失败，62动作完整TCP对战，另验证满24槽与7目标技能消息边界；[网络日志](../../godot/docs/battle-network-20261011.log)。
- test_scene_ui.gd：退出0；109检查、0失败，含精确槽、固定原卡、取消、点击、独立音画开关、新局、80事件短队列及多目标独立落点；[场景日志](../../godot/docs/battle-scene-ui-20261011.log)。
- network_ui_probe.gd：最终FX代码后复跑退出0；41检查、0失败，双方部署/攻击/技能事件同序且各播一次，拒绝、重复、重连不重播，再战清理；[联机UI日志](../../godot/docs/battle-network-ui-20261011.log)。
- python tools/build_godot_release.py --build-only：退出0；离线模板校验、资源导入、Windows导出完成；[构建日志](../../release/godot-build.log)。
- release/EmpireFrontGodot.exe -- --ui-probe <报告路径>：最终EXE退出0；Windows/OpenGL 116检查、0失败，13个公开事件声音与特效各播放13次；[EXE报告](../../release/godot-exe-probe-v2.1.json)、[输出](../../release/godot-exe-probe-v2.1.log)、[攻击箭头](../../release/Godot攻击箭头预览.png)、[移动箭头](../../release/Godot移动箭头预览.png)、[最小窗口七槽](../../release/Godot最小窗口七槽预览.png)。主任务已查看七槽与攻击图，布局不越界、原卡在位。
- python tools/build_godot_release.py --package-only：退出0；双ZIP CRC、EXE SHA-256及源码16文件匹配通过；[包验证记录](../../release/godot-package-verification-v2.1.json)。
- 本次文档及直接关联文件/锚点检查通过，保留旧2.0证据与用户无关手改；[文档检查记录](../../release/battle-document-check-20261011.json)。限定改动的git diff --check通过。

2026-10-10的2.0行动预算、EXE与包证据入口沿用在[历史索引](history/README.md)，仅证明当时对象与范围。跨设备联机、Android、新设备安装和实际音质未由上述检查证明。
