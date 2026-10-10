extends SceneTree
## Regression checks for canceled pointer gestures and JSON snapshot action caches.
const Rules = preload("res://scripts/engine.gd")
var ui
var checks = 0
var failures = []
func _initialize(): call_deferred("run")
func check(ok, message):
 checks += 1
 if not ok:
  failures.append(message)
  push_error("REVIEW_CLIENT: " + message)
func mouse(pos, down, button = MOUSE_BUTTON_LEFT):
 var event = InputEventMouseButton.new()
 event.button_index = button; event.position = pos; event.pressed = down
 ui._input(event)
func escape():
 var event = InputEventKey.new(); event.keycode = KEY_ESCAPE; event.pressed = true
 ui._input(event)
func center(uid): return ui.card_nodes[uid].get_global_transform() * (ui.card_nodes[uid].size / 2)
func click(pos): mouse(pos,true); mouse(pos,false)
func lane(value): return Vector2(110,ui.LANES[ui._row_for_lane(value)].get_center().y)
func snapshot(json_roundtrip = false):
 var view = ui.rules.view(0)
 ui._accept_state(JSON.parse_string(JSON.stringify(view)) if json_roundtrip else view)
func reset():
 escape()
 ui.rules = Rules.new([],[],731)
 ui.rules.phase = "battle"; ui.rules.mulligan_done = [true,true]; ui.rules.turn = 0
 for player in ui.rules.players:
  player.hand.clear(); player.board.clear(); player.mana = 10; player.max_mana = 10
 snapshot()
func cancel(kind,pos):
 if kind == "escape": escape()
 elif kind == "right": mouse(pos,true,MOUSE_BUTTON_RIGHT)
 else: snapshot()
func run():
 ui = load("res://main.tscn").instantiate(); root.add_child(ui)
 await process_frame
 ui.settings.animations = false; ui.settings.sound = false; ui.set_process(false)
 ui.deck = ui.rules.default_deck.duplicate(); ui._solo(); ui.set_process(false)
 var uid = int(ui.state.players[0].hand[0].uid)
 for kind in ["escape","right","snapshot"]:
  var pos = center(uid)
  ui.marked.clear(); mouse(pos,true); cancel(kind,pos); mouse(pos,false)
  check(ui.marked.is_empty(),"mulligan cancel " + kind + " ignores release")
  check(not ui.press_active and ui.press.is_empty(),"mulligan gesture cleared " + kind)
 ui._confirm_mulligan()
 reset()
 var unit = ui.rules.summon(0,"infantry",3); unit.actions = 2; snapshot()
 uid = int(unit.uid)
 for kind in ["escape","right","snapshot"]:
  escape()
  var pos = center(uid)
  mouse(pos,true); cancel(kind,pos); mouse(pos,false)
  check(ui.selected.is_empty(),"battle cancel " + kind + " ignores release")
  check(not ui.press_active and ui.ghost == null,"battle gesture cleared " + kind)
 for kind in ["escape","right","snapshot"]:
  escape()
  mouse(center(uid),true)
  var motion = InputEventMouseMotion.new(); motion.position = lane(2); motion.button_mask = MOUSE_BUTTON_MASK_LEFT
  ui._input(motion)
  check(ui.dragging and ui.ghost != null,"drag starts before cancel " + kind)
  cancel(kind,lane(2)); mouse(lane(2),false)
  check(unit.lane == 3 and unit.actions == 2 and ui.ghost == null and not ui.press_active,"drag cancel prevents move on release " + kind)
 click(center(uid)); click(lane(2))
 check(unit.lane == 2 and unit.actions == 1,"click selected unit then empty lane moves")
 reset()
 unit = ui.rules.summon(0,"infantry",0); unit.actions = 2; snapshot()
 click(center(int(unit.uid))); click(ui.ENEMY_BASE.get_center())
 check(ui.rules.players[1].hp == 27 and unit.actions == 1,"click selected unit then enemy base attacks")
 # Client snapshots have JSON floating point IDs; cached signatures must match
 # pointer-generated integer IDs for both deployments and targeted attacks.
 reset()
 ui.rules.players[0].hand = [{"uid":1000,"card":"infantry"}]
 snapshot(true)
 check(ui.card_nodes[1000].playable,"JSON snapshot deployment card has legal highlight")
 check(ui._legal({"type":"play","hand":1000,"lane":3}),"JSON snapshot integer deployment matches action cache")
 click(center(1000)); click(lane(3))
 check(ui.rules.players[0].hand.is_empty() and ui.rules.players[0].board.size() == 1,"JSON snapshot click deployment executes")
 reset()
 unit = ui.rules.summon(0,"infantry",2); unit.actions = 2
 var enemy = ui.rules.summon(1,"heavy_cavalry",1)
 snapshot(true)
 check(ui.card_nodes[int(unit.uid)].playable,"JSON snapshot attacking unit has legal highlight")
 var attack = {"type":"attack","unit":int(unit.uid),"target":int(enemy.uid)}
 check(ui._legal(attack),"JSON snapshot integer target matches attack cache")
 check(ui._legal({"target":int(enemy.uid),"unit":int(unit.uid),"type":"attack"}),"action signature ignores dictionary insertion order")
 click(center(int(unit.uid))); click(center(int(enemy.uid)))
 check(enemy.hp == 4 and unit.actions == 1,"JSON snapshot target click attacks")
 unit.actions = 0; snapshot(true)
 check(not ui._legal(attack) and not ui.card_nodes[int(unit.uid)].playable,"new snapshot expires old cached legal attack and highlight")
 ui.net.close(); ui.queue_free(); await process_frame
 print("REVIEW_CLIENT_TEST: %d checks; %d failures" % [checks,failures.size()])
 quit(0 if failures.is_empty() else 1)
