extends Control
## Passive card artwork. The board owns all input, dragging and animation.

static var _textures: Dictionary = {}
static var _styles: Dictionary = {}
var definition: Dictionary = {}
var data: Dictionary = {}
var card_mode: String = "hand"
var friendly: bool = true
var selected: bool = false
var marked: bool = false
var playable: bool = true
var hovered: bool = false:
	set(value):
		hovered = value
		queue_redraw()
var _font: SystemFont
const INK = Color("29271f")
const PAPER = Color("e4d8b9")
const GOLD = Color("bda064")

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "SimHei"])

func _ready() -> void:
	resized.connect(queue_redraw)
	queue_redraw()

func configure(definition_value: Dictionary, data_value: Dictionary, mode: String = "hand", is_friendly: bool = true) -> void:
	definition = definition_value
	data = data_value
	card_mode = mode
	friendly = is_friendly
	queue_redraw()

func set_visual(selected_value: bool, marked_value: bool = false, playable_value: bool = true) -> void:
	selected = selected_value
	marked = marked_value
	playable = playable_value
	queue_redraw()

func get_card_uid() -> int:
	return int(data.get("uid", -1))

func get_card_key() -> String:
	return str(data.get("key", definition.get("id", "")))

func _panel(rect: Rect2, fill: Color, border: Color, width: int = 1, radius: int = 5) -> void:
	var key = "%d/%d/%d/%d" % [fill.to_rgba32(),border.to_rgba32(),width,radius]
	if not _styles.has(key):
		var style := StyleBoxFlat.new()
		style.bg_color = fill
		style.border_color = border
		style.set_border_width_all(width)
		style.set_corner_radius_all(radius)
		_styles[key] = style
	draw_style_box(_styles[key], rect)

func _label(text: String, rect: Rect2, pixels: int, color: Color = INK, centered: bool = false) -> void:
	var shown := text
	while shown.length() > 1 and _font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x > rect.size.x:
		shown = shown.left(shown.length() - 2) + "…"
	var x := rect.position.x
	if centered:
		x += maxf(0.0, (rect.size.x - _font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x) * 0.5)
	draw_string(_font, Vector2(x, rect.position.y + _font.get_ascent(pixels)), shown, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, pixels, color)

func _paragraph(text: String, rect: Rect2, pixels: int) -> void:
	var line := ""
	var y := rect.position.y
	var height := float(pixels) * 1.4
	for character in text:
		if _font.get_string_size(line + character, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x > rect.size.x or character == "\n":
			_label(line, Rect2(rect.position.x, y, rect.size.x, height), pixels)
			y += height
			line = ""
			if y + height > rect.end.y:
				return
		if character != "\n":
			line += character
	if not line.is_empty() and y + height <= rect.end.y + 1.0:
		_label(line, Rect2(rect.position.x, y, rect.size.x, height), pixels)

func _art(rect: Rect2) -> void:
	var key := get_card_key()
	# Optional alternate full portrait for the inspection view.
	var path := str(definition.get("hero_art", "")) if card_mode == "detail" else ""
	if path.is_empty():
		path = "res://assets/cards/" + key + ".png"
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	var texture = _textures[path]
	_panel(rect, Color("39423d"), GOLD, 1, 0)
	if texture is Texture2D:
		var dimensions: Vector2 = texture.get_size()
		var ratio := maxf(rect.size.x / dimensions.x, rect.size.y / dimensions.y)
		var crop := rect.size / ratio
		draw_texture_rect_region(texture, rect, Rect2((dimensions - crop) * 0.5, crop))
	else:
		_label("帝 国", rect, 20, PAPER, true)

func _badge(center: Vector2, radius: float, text: String, color: Color, pixels: int) -> void:
	draw_circle(center + Vector2(0, 2), radius + 1, Color(0, 0, 0, 0.45))
	draw_circle(center, radius + 1, GOLD)
	draw_circle(center, radius - 1, color)
	_label(text, Rect2(center.x - radius, center.y - pixels * 0.62, radius * 2, pixels + 3), pixels, Color("fff6de"), true)

func _draw() -> void:
	if size.x < 20 or size.y < 20:
		return
	var edge := Color("5c8f99") if friendly else Color("a75a52")
	if hovered or playable:
		edge = Color("cfb574")
	if selected:
		edge = Color("72d4d3")
	if marked:
		edge = Color("e47765")
	_panel(Rect2(Vector2(3, 5), size), Color(0, 0, 0, 0.38), Color.TRANSPARENT, 0, 8)
	_panel(Rect2(Vector2.ZERO, size), Color("292f2e"), edge, 3 if selected or marked or hovered else 2, 7)
	if card_mode == "unit":
		_draw_unit()
	else:
		_draw_portrait()
	if not playable and card_mode != "detail" and card_mode != "mulligan":
		_panel(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(0.08, 0.1, 0.12, 0.2), Color.TRANSPARENT, 0)
	if marked and card_mode == "mulligan":
		_panel(Rect2(8, size.y * 0.43, size.x - 16, 34), Color("822f32"), GOLD)
		_label("替 换", Rect2(8, size.y * 0.43 + 7, size.x - 16, 24), 17, PAPER, true)

func _draw_portrait() -> void:
	var w := size.x
	var h := size.y
	var detail := card_mode == "detail"
	var title_size := 17 if detail else 14
	var body_size := 13 if detail else 11
	var footer := h - 31.0
	var art_height := h * (0.43 if detail else 0.47)
	_art(Rect2(7, 7, w - 14, art_height))
	_panel(Rect2(7, art_height + 7, w - 14, h - art_height - 14), PAPER, GOLD, 1, 0)
	_label(str(definition.get("name", "未知卡牌")), Rect2(13, art_height + 13, w - 26, 24), title_size, INK, true)
	draw_line(Vector2(16, art_height + 37), Vector2(w - 16, art_height + 37), Color("b4a583"), 1)
	var tags: Array = data.get("tags", definition.get("tags", []))
	var keywords := " · ".join(tags)
	var text_start := art_height + 43
	if not keywords.is_empty():
		_label(keywords, Rect2(13, text_start, w - 26, 18), body_size, Color("7c5730"), true)
		text_start += 19
	_paragraph(str(definition.get("text", "")), Rect2(14, text_start, w - 28, maxf(0, footer - text_start - 5)), body_size)
	_badge(Vector2(21, 22), 16, str(int(definition.get("cost", 0))), Color("355c69"), 19)
	if str(definition.get("kind", "unit")) == "unit":
		_badge(Vector2(23, h - 21), 15, str(int(data.get("attack", definition.get("attack", 0)))), Color("79603a"), 18)
		_badge(Vector2(w - 23, h - 21), 15, str(int(data.get("hp", definition.get("health", 0)))), Color("843f3b"), 18)
		_label("单位", Rect2(44, h - 24, w - 88, 18), 10, Color("766c52"), true)
	else:
		_label("战术命令", Rect2(10, h - 25, w - 20, 18), 11, Color("766c52"), true)

func _draw_unit() -> void:
	var w := size.x
	var h := size.y
	var portrait_width := 43.0
	_art(Rect2(5, 5, portrait_width, 52))
	var left := portrait_width + 10
	var available := w - left - 8
	var unit_name := str(definition.get("name", "单位")).trim_prefix("帝国")
	_label(unit_name, Rect2(left, 8, available, 19), 15, PAPER)
	var tags: Array = data.get("tags", definition.get("tags", []))
	_label("友军" if friendly else "敌军",Rect2(left,29,available,17),13,Color("8ddadd") if friendly else Color("f09b89"))
	_label(" · ".join(tags), Rect2(7, 57, w-14, 14), 10, GOLD)
	var attack := int(data.get("attack", definition.get("attack", 0)))
	var hp := int(data.get("hp", definition.get("health", 0)))
	var armor := int(data.get("armor", definition.get("armor", 0)))
	var actions := int(data.get("actions", 0))
	_label("攻 %d  血 %d" % [attack, hp], Rect2(7, h - 31, w-14, 17), 14, Color("f1dfba"))
	var status := "装弹" if data.get("reloading",false) or int(data.get("reload",0)) > 0 else ("冷%d" % int(data.cooldown) if int(data.get("cooldown",0)) > 0 else "")
	_label("甲%d 行%d%s" % [armor,actions," "+status if not status.is_empty() else ""],Rect2(7,h-15,w-14,15),12,Color("94c8c6") if actions > 0 else Color("9b9d91"))
