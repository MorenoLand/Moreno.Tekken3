extends Node
const Options := preload("res://scripts/core/options.gd")
const KEYS := [
	{"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "lp": KEY_U, "rp": KEY_I, "lk": KEY_J, "rk": KEY_K, "start": KEY_ENTER, "select": KEY_BACKSPACE},
	{"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT, "lp": KEY_KP_4, "rp": KEY_KP_5, "lk": KEY_KP_1, "rk": KEY_KP_2, "start": KEY_KP_ENTER, "select": KEY_KP_0},
]
const BUTTONS := {"up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN, "left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT, "lp": JOY_BUTTON_X, "rp": JOY_BUTTON_Y, "lk": JOY_BUTTON_A, "rk": JOY_BUTTON_B, "start": JOY_BUTTON_START, "select": JOY_BUTTON_BACK}
const STICK := {"up": [JOY_AXIS_LEFT_Y, -1.0], "down": [JOY_AXIS_LEFT_Y, 1.0], "left": [JOY_AXIS_LEFT_X, -1.0], "right": [JOY_AXIS_LEFT_X, 1.0]}
func _ready() -> void:
	for p in 2:
		for name in KEYS[p]:
			var action := "p%d_%s" % [p + 1, name]
			InputMap.add_action(action, 0.5)
			var key := InputEventKey.new()
			key.physical_keycode = Options.key_for(p, name, KEYS[p][name])
			InputMap.action_add_event(action, key)
			var button := InputEventJoypadButton.new()
			button.button_index = BUTTONS[name]
			button.device = p
			InputMap.action_add_event(action, button)
			if STICK.has(name):
				var axis := InputEventJoypadMotion.new()
				axis.axis = STICK[name][0]
				axis.axis_value = STICK[name][1]
				axis.device = p
				InputMap.action_add_event(action, axis)
	for name in ["up", "down", "left", "right"]:
		_alias("menu_" + name, "p1_" + name, "p2_" + name)
	_alias("menu_confirm", "p1_lk", "p2_lk")
	_alias("menu_back", "p1_rk", "p2_rk")
	_alias("menu_start", "p1_start", "p2_start")
func _alias(action: String, first: String, second: String) -> void:
	InputMap.add_action(action, 0.5)
	for source in [first, second]:
		for event in InputMap.action_get_events(source):
			InputMap.action_add_event(action, event)
	for extra in [KEY_ENTER, KEY_SPACE]:
		if action == "menu_confirm":
			var key := InputEventKey.new()
			key.physical_keycode = extra
			InputMap.action_add_event(action, key)
	if action == "menu_back":
		var escape := InputEventKey.new()
		escape.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event(action, escape)
func rebind(player: int, name: String, code: int) -> void:
	var action := "p%d_%s" % [player + 1, name]
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var key := InputEventKey.new()
	key.physical_keycode = code
	InputMap.action_add_event(action, key)
	Options.set_key(player, name, code)
	for alias in ["menu_up", "menu_down", "menu_left", "menu_right", "menu_confirm", "menu_back", "menu_start"]:
		InputMap.erase_action(alias)
	for dir in ["up", "down", "left", "right"]:
		_alias("menu_" + dir, "p1_" + dir, "p2_" + dir)
	_alias("menu_confirm", "p1_lk", "p2_lk")
	_alias("menu_back", "p1_rk", "p2_rk")
	_alias("menu_start", "p1_start", "p2_start")
func defaults() -> void:
	Options.reset_keys()
	for p in 2:
		for name in KEYS[p]:
			rebind(p, name, KEYS[p][name])
	Options.reset_keys()
