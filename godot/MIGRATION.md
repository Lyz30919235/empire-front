# Godot 迁移约定

> 历史范围：下文保留迁移阶段的接口与临时分工，不作为当前任务清单；下载状态和限定编辑范围均为当时安排。完整仓库的当前状态见 [NOW.md](../docs/context/NOW.md)，长期规则见 [AGENTS.md](../AGENTS.md)。涉及接口修改时应核对当前实现，不凭旧约定推断现状。

用户授权迁移到Godot，并授权agent team，子代理只允许gpt-6.1-sol或gpt-6.1-luna。当前工具可用gpt-6.1-sol；所有新子代理使用该模型。始终简体中文。

保留Python1.2源代码和历史包，新的完整Godot项目位于godot/，使用GDScript，26张插画已复制到assets/cards/，卡牌与默认牌组见assets/data/cards.json。规则以empire_front/engine.py及现有52项测试为依据，包含修复后的反击绕过主动选目标嘲讽限制。

## 规则接口 scripts/engine.gd

extends RefCounted；构造new(decks:Array=[],names:Array=[],seed_value:int=-1)。公开cards,default_deck,players,phase,mulligan_done,turn,round,revision,winner(null/0/1/-1),log。
act(p:int,action:Dictionary)->String：成功返回空字符串，失败返回中文原因，错误动作不改变任何资源或状态。
view(p:int)->Dictionary：与Python当前视图一致（含you/home_lane/players及自身hand、双方hand_count/deck_count，隐藏对方hand及双方deck）。
ai_action(p:int)->Dictionary，legal_actions(p:int)->Array；summon(p,key,lane,token=false)；unit(uid)；attack_error(p,u,target,free=false,retaliation=false)->String；space(p,lane)->bool；home_lane(p)->int；deploy_error(p,lane)->String。
JSON数字可以是float，接收输入uid/战线等必须安全转换；不能因类型变化接受非法非整数编号。

## 联机接口 scripts/network.gd

extends Node，自身_process轮询。可用const EngineScript=preload("res://scripts/engine.gd")。权威TCP+NDJSON，默认47653，Godot2.0协议可独立于旧Python版。只支持双人熟人LAN/RadminVPN，不修改防火墙。
signal state_changed(state:Dictionary,lobby:Array)；signal status_changed(message:String)；signal seat_assigned(seat:int)。
公开seat:int、online:bool、is_host:bool、port:int、game（主机权威引擎）、lobby:Array。
host(port_value:int,password:String,name:String,deck:Array)->String；join(ip:String,port_value:int,password:String,name:String,deck:Array)->String；ready_up()->void；send_action(action:Dictionary)->void；retry()->void；close()->void。
成功启动/连接返回空字符串，错误为中文字符串。等待阶段state={}、lobby为2个槽位，空位可为null，槽位字段name/ready/online。客户端视图不得泄露隐藏牌。
双方ready后phase=mulligan，双方完成换牌后battle。断线暂停并凭token自动重连，保持席位、当前回合和换牌确认。主动撤退/结束后的再战支持双方ready。限制消息长度、校验房间口令和版本、拒绝旧revision（整备阶段双方同时确认例外）。

## 分工与验证

规则子代理只编辑scripts/engine.gd、tests/test_engine.gd、tests/trace_runner.gd，可增加规则专用测试文件。联机子代理只编辑scripts/network.gd和tests/test_network.gd，可增加联机专用测试脚本。主代理负责项目、场景、UI、卡面动画、设置/图鉴/组牌、导出与桌面快捷方式、文档。
不要编辑其他分工文件，不运行或关闭其他人的GUI。Godot二进制正在下载到tools/godot-runtime/，主代理提供可执行路径后可headless测试；需要主代理整合修改时发送消息。
