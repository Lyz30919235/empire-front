extends Control
## Public authority events drive both seats; no speculative success feedback.
const PROFILES = {
	"scout":["shot",720.0,0.28,Color("a8d1be")],
	"archer":["arrow",980.0,0.08,Color("eac58e")],
	"light_cavalry":["charge",170.0,0.35,Color("edc783")],
	"heavy_cavalry":["charge",115.0,0.48,Color("e8a769")],
	"vanguard":["shot",550.0,0.4,Color("ffbc75")],
	"infantry":["shot",420.0,0.52,Color("eddab0")],
	"hound":["claw",230.0,0.64,Color("cbb58b")],
	"loan":["resource",1200.0,0.05,Color("f6da77")],
	"arrows":["rain",1050.0,0.18,Color("e8c38a")],
	"fireball":["fire",90.0,0.8,Color("ff8b47")],
	"merchant":["resource",890.0,0.1,Color("e3c467")],
	"banner":["rally",660.0,0.06,Color("e4c375")],
	"heal":["heal",850.0,0.02,Color("89edbc")],
	"shield":["shield",260.0,0.25,Color("b9cddb")],
	"artillery":["shell",65.0,0.85,Color("f4a260")],
	"carrier":["air",100.0,0.48,Color("b4d4e1")],
	"plane":["air",190.0,0.4,Color("d0e7eb")],
	"emperor":["rally",510.0,0.08,Color("f2d380")],
	"heavy_tank":["shell",78.0,0.78,Color("dfaa6b")],
	"engineer":["repair",1500.0,0.3,Color("b7dbcd")],
	"suicide":["fire",105.0,0.95,Color("ffad5d")],
	"medium_tank":["shell",100.0,0.66,Color("dfbc83")],
	"light_tank":["shell",145.0,0.56,Color("ebcd9b")],
	"anti_air":["flak",300.0,0.75,Color("d4deea")],
	"factory":["build",370.0,0.46,Color("c5dfc6")],
	"tower":["command",760.0,0.04,Color("99d6e5")]
}
const SKILLS = {"charge":"charge","rally":"rally","airstrike":"air","repair":"repair","manufacture":"build","command":"command"}
var board
var played_events = 0
var sound_count = 0
var visual_count = 0
var event_counts: Dictionary = {}
var played_ids: Array[String] = []
var current_match = ""
var last_revision = -1
var queue: Array = []
var visuals: Array = []
var wait_time = 0.0
var streams: Dictionary = {}
var players: Array[AudioStreamPlayer] = []
var audio_index = 0
var font = SystemFont.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font.font_names = PackedStringArray(["Microsoft YaHei","Noto Sans CJK SC"])
	for i in range(8):
		var player = AudioStreamPlayer.new()
		player.volume_db = -11.0
		add_child(player); players.append(player)

func clear() -> void:
	queue.clear(); visuals.clear(); wait_time = 0.0
	for player in players: player.stop()
	queue_redraw()

func pending_count() -> int:
	return queue.size()

func is_busy() -> bool:
	return not queue.is_empty() or wait_time > 0.0

func consume(snapshot: Dictionary, options: Dictionary) -> void:
	var match_value = str(snapshot.get("match_id","legacy"))
	var revision = int(snapshot.get("revision",0))
	var first = current_match.is_empty()
	var changed = current_match != match_value
	if changed:
		clear(); current_match = match_value; last_revision = -1
	if snapshot.get("event_mode","live") == "baseline" or first:
		clear(); last_revision = revision; return
	if revision <= last_revision: return
	last_revision = revision
	for event in snapshot.get("events",[]):
		var item = event.duplicate(true)
		item["id"] = "%s/%d/%d" % [match_value,int(event.get("revision",revision)),int(event.get("index",0))]
		item["animate"] = bool(options.get("animations",true))
		item["sound"] = bool(options.get("sound",true))
		item["interval"] = minf(0.09,0.5/maxi(1,snapshot.get("events",[]).size()))
		queue.append(item)
	if wait_time <= 0.0: _next()

func _position(descriptor: Dictionary) -> Vector2:
	if descriptor.get("base",false):
		return (board.OWN_BASE if int(descriptor.get("owner",0)) == int(board.state.you) else board.ENEMY_BASE).get_center()
	if descriptor.has("lane"):
		return board._slot_rect(int(descriptor.lane),int(descriptor.get("slot",0))).get_center()
	return board.OWN_BASE.get_center()

func _next() -> void:
	if queue.is_empty(): return
	var event: Dictionary = queue.pop_front()
	played_events += 1
	played_ids.append(event.id)
	if played_ids.size() > 256: played_ids.pop_front()
	var kind = str(event.get("kind",""))
	event_counts[kind] = int(event_counts.get(kind,0))+1
	var profile: Array = PROFILES.get(str(event.get("card","")),["rally",440.0,0.15,Color("d3c18e")])
	var style = str(SKILLS.get(str(event.get("skill","")),profile[0]))
	if kind == "heal": style = "heal"
	elif kind == "buff": style = "rally"
	elif kind == "death": style = "death"
	elif kind == "move": style = "move"
	var source: Dictionary = event.get("source",{})
	var destination: Dictionary = event.get("target",source)
	var targets: Array = event.get("targets",[])
	var lane_only = targets.is_empty() and not event.has("target") and event.has("lane")
	if targets.is_empty(): targets = [destination]
	if bool(event.animate):
		visual_count += 1
		for target in targets:
			var point = _position(target)
			if lane_only:
				point = board.LANES[board._row_for_lane(int(event.lane))].get_center()
			visuals.append({"from":_position(source),"to":point,"kind":kind,"style":style,"color":profile[3],"age":0.0,"life":0.48 if kind in ["attack","counter","spell","skill"] else 0.36,"amount":int(event.get("amount",0)),"label":str(event.get("label",""))})
			if visuals.size() > 64: visuals.pop_front()
	if bool(event.sound):
		sound_count += 1
		var key = "%s/%s/%s" % [event.get("card",""),style,kind]
		if not streams.has(key): streams[key] = _synth(profile,style,kind)
		var player: AudioStreamPlayer = players[audio_index%players.size()]
		audio_index += 1; player.stream = streams[key]; player.play()
	wait_time = minf(float(event.interval),0.09 if kind in ["attack","counter","spell","skill"] else 0.035)
	queue_redraw()

func _synth(profile: Array, style: String, kind: String) -> AudioStreamWAV:
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate = 22050
	var samples = PackedByteArray()
	var seed_value = 7919
	var frequency = float(profile[1])
	var noise = float(profile[2])
	var length = 6500 if style in ["shell","fire","air","charge"] else 4100
	if kind in ["damage","death"]: frequency *= 0.6; noise = maxf(noise,0.6)
	for i in range(length):
		var t = float(i)/22050.0
		var progress = float(i)/length
		seed_value = (seed_value*1103515245+12345)&0x7fffffff
		var hiss = float(seed_value%65536)/32768.0-1.0
		var pitch = frequency*(1.0-progress*0.62)
		var tone = sin(TAU*pitch*t)+0.3*sin(TAU*pitch*1.51*t)
		if style in ["heal","resource","command","rally"]: tone = sin(TAU*frequency*t)+0.45*sin(TAU*frequency*1.5*t)
		var pulse = 0.35+0.65*absf(sin(t*90.0)) if style in ["air","flak","build","charge"] else 1.0
		var envelope = minf(1.0,float(i)/120.0)*pow(1.0-progress,2.0)
		var amplitude = int(clampf((tone*(1.0-noise)+hiss*noise)*pulse*envelope*10000.0,-32767,32767))
		samples.append(amplitude&255); samples.append((amplitude>>8)&255)
	stream.data = samples
	return stream

func _process(delta: float) -> void:
	wait_time -= delta
	var serviced = 0
	while wait_time <= 0.0 and not queue.is_empty() and serviced < 16:
		var carried_time = wait_time
		_next()
		wait_time += carried_time
		serviced += 1
	if queue.is_empty(): wait_time = maxf(0.0,wait_time)
	for visual in visuals: visual.age += delta
	visuals = visuals.filter(func(v): return v.age < v.life)
	if not visuals.is_empty(): queue_redraw()
	elif not queue.is_empty() or wait_time > 0.0: queue_redraw()
	else: queue_redraw()

func _draw() -> void:
	for v in visuals:
		var progress = clampf(v.age/v.life,0,1)
		var color: Color = v.color; color.a = 1.0-progress
		var point: Vector2 = v.to
		var style: String = v.style
		if v.kind == "damage":
			draw_rect(Rect2(point-Vector2(73,49),Vector2(146,98)),Color(1.0,0.3,0.18,(1.0-progress)*0.22))
		if v.kind in ["attack","counter","spell","skill","move"]:
			var moving: Vector2 = v.from.lerp(point,minf(1.0,progress*2.0))
			draw_line(v.from,moving,Color(color,color.a*0.6),4.0,true)
			if style in ["arrow","rain"]:
				for i in range(5 if style == "rain" else 1):
					var offset = Vector2((i-2)*14.0,0) if style == "rain" else Vector2.ZERO
					var direction: Vector2 = (point-v.from).normalized()
					draw_line(moving+offset-direction*24,moving+offset,color,3,true)
					draw_colored_polygon(PackedVector2Array([moving+offset,moving+offset-direction.rotated(0.5)*11,moving+offset-direction.rotated(-0.5)*11]),color)
			elif style in ["air","flak"]:
				draw_line(moving-Vector2(18,0),moving+Vector2(18,0),color,4,true)
				draw_line(moving-Vector2(0,24),moving+Vector2(0,15),color,4,true)
			elif style == "claw":
				for i in range(3): draw_line(moving+Vector2(i*9-20,-22),moving+Vector2(i*9,22),color,3,true)
			else: draw_circle(moving,10 if style in ["shell","fire"] else 5,color)
		var radius = 10+progress*42
		if style in ["heal","repair"]:
			draw_line(point-Vector2(12,0),point+Vector2(12,0),color,6,true)
			draw_line(point-Vector2(0,12),point+Vector2(0,12),color,6,true)
		elif style in ["resource","rally","command","build","shield"]:
			draw_rect(Rect2(point-Vector2(radius,radius),Vector2(radius*2,radius*2)),color,false,3)
		else:
			for i in range(8):
				var direction = Vector2.from_angle(i*TAU/8.0)
				draw_line(point+direction*radius*0.45,point+direction*radius,color,3,true)
		draw_arc(point,radius,0,TAU,32,color,2,true)
		if v.kind in ["damage","heal","buff"]:
			var label = ("+" if v.kind != "damage" else "−")+str(v.amount) if int(v.amount) > 0 else v.label
			draw_string(font,point+Vector2(-24,-30-progress*35),label,HORIZONTAL_ALIGNMENT_LEFT,-1,26,color)
	if board != null and board.screen == "battle": board._draw_aim(self)
