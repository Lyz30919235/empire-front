extends SceneTree
const EngineScript = preload("res://scripts/engine.gd")
func _initialize():
	var g = EngineScript.new([], [], 73)
	g.act(0, {"type":"mulligan"})
	g.act(1, {"type":"mulligan"})
	g.players[0].mana = 100
	var weird = [null, true, false, {}, [], {"type": "end"}, [1], "base", "", 0.5, -1, 999999999999]
	var checked = 0
	for kind in ["play", "attack", "move", "skill", "mulligan", "unknown"]:
		for value in weird:
			var a = {"type":kind,"unit":value,"hand":value,"target":value,"ally":value,"option":value,"lane":value,"cards":value}
			var before = JSON.stringify([g.players,g.phase,g.mulligan_done,g.turn,g.round,g.revision,g.winner,g.log,g.next_id,g.rng.state])
			var error = g.act(0,a)
			assert(not error.is_empty(), "unexpected success")
			assert(before == JSON.stringify([g.players,g.phase,g.mulligan_done,g.turn,g.round,g.revision,g.winner,g.log,g.next_id,g.rng.state]), "mutation on reject")
			checked += 1
	print("REVIEW PROBE PASS checks=",checked)
	quit()
