local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder()

local US_SHIFTED_META_CHARS = {
	["`"] = "~",
	["1"] = "!",
	["2"] = "@",
	["3"] = "#",
	["4"] = "$",
	["5"] = "%",
	["6"] = "^",
	["7"] = "&",
	["8"] = "*",
	["9"] = "(",
	["0"] = ")",
	["-"] = "_",
	["="] = "+",
	["["] = "{",
	["]"] = "}",
	["\\"] = "|",
	[";"] = ":",
	["'"] = "\"",
	[","] = "<",
	["."] = ">",
	["/"] = "?",
}

for code = string.byte("a"), string.byte("z") do
	local key = string.char(code)
	US_SHIFTED_META_CHARS[key] = string.upper(key)
end

local function cmd_shift_as_meta_action(key)
	local shifted_char = US_SHIFTED_META_CHARS[key]
	if shifted_char then
		return act.SendString("\27" .. shifted_char)
	end

	return act.SendKey { key = key, mods = "ALT|SHIFT" }
end

local function bind_cmd_as_meta(keys, include_shift)
	for _, key in ipairs(keys) do
		table.insert(config.keys, {
			key = key,
			mods = "CMD",
			action = act.SendKey { key = key, mods = "ALT" },
		})
		table.insert(config.keys, {
			key = key,
			mods = "CMD|CTRL",
			action = act.SendKey { key = key, mods = "ALT|CTRL" },
		})
		if include_shift then
			table.insert(config.keys, {
				key = key,
				mods = "CMD|SHIFT",
				action = cmd_shift_as_meta_action(key),
			})
			table.insert(config.keys, {
				key = key,
				mods = "CMD|CTRL|SHIFT",
				action = act.SendKey { key = key, mods = "ALT|CTRL|SHIFT" },
			})
		end
	end
end

config.color_scheme = "Catppuccin Latte"
config.font = wezterm.font("DejaVuSansM Nerd Font Mono")
config.term = "xterm-256color"
config.window_close_confirmation = "NeverPrompt"
config.scrollback_lines = 20000
config.automatically_reload_config = true
config.use_ime = true
config.macos_forward_to_ime_modifier_mask = "SHIFT|CTRL"

config.disable_default_key_bindings = true
config.disable_default_mouse_bindings = true

config.keys = {
	-- Legacy terminal input cannot distinguish Ctrl+; from plain ;.
	-- Send CSI-u for ASCII 59 with the Ctrl modifier.
	{
		key = ";",
		mods = "CTRL",
		action = act.SendString("\x1b[59;5u"),
	},

	-- Legacy terminal input cannot distinguish Ctrl+\ from byte 0x1c.
	-- Send CSI-u for ASCII 92 with the Ctrl modifier.
	{
		key = "\\",
		mods = "CTRL",
		action = act.SendString("\x1b[92;5u"),
	},

	{ key = "v", mods = "CTRL|SHIFT", action = act.PasteFrom("Clipboard") },
}

bind_cmd_as_meta({
	"a",
	"b",
	"c",
	"d",
	"e",
	"f",
	"g",
	"h",
	"i",
	"j",
	"k",
	"l",
	"m",
	"n",
	"o",
	"p",
	"q",
	"r",
	"s",
	"t",
	"u",
	"v",
	"w",
	"x",
	"y",
	"z",
	"Space",
	"Backspace",
	"Enter",
	"Escape",
	"Tab",
	"`",
	"-",
	"=",
	"[",
	"]",
	"\\",
	";",
	"'",
	",",
	".",
	"/",
	"LeftArrow",
	"RightArrow",
	"UpArrow",
	"DownArrow",
	"Home",
	"End",
	"PageUp",
	"PageDown",
	"1",
	"2",
	"3",
	"4",
	"5",
	"6",
	"7",
	"8",
	"9",
	"0",
}, true)

return config
