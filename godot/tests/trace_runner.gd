extends SceneTree
## headless --script res://tests/trace_runner.gd -- trace.json
## 输入可含decks、names、seed、players覆盖、actions:[{player,action}]。
## 输出每步双方独立视图，方便Python与Godot对同一确定性战场进行差分。
const Rules = preload("res://scripts/engine.gd")
func _init():
	var args = OS.get_cmdline_user_args()
	if args.is_empty():
		print("用法：-- trace.json；输入actions数组，每项包含player与action。")
		quit(1)
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not data is Dictionary:
		push_error("轨迹必须是JSON对象")
		quit(1)
		return
	var g = Rules.new(data.get("decks",[]),data.get("names",[]),int(data.get("seed",9)))
	if data.has("players"): g.players = data.players.duplicate(true)
	for field in ["phase","mulligan_done","turn","round","revision","winner","log","next_id"]:
		if data.has(field): g.set(field,data[field])
	var results = [{"error":"","views":[g.view(0),g.view(1)]}]
	for step in data.get("actions",[]):
		var error = g.act(int(step.player),step.action)
		results.append({"error":error,"views":[g.view(0),g.view(1)]})
	print(JSON.stringify(results))
	quit()
