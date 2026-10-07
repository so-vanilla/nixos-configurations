local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder()

local WSL_DISTRIBUTION = "FedoraLinux-44"
local WSL_CWD = "~"

local function wsl_default_prog()
	return { "wsl.exe", "--distribution", WSL_DISTRIBUTION, "--cd", WSL_CWD, "--", "bash", "-l" }
end

config.color_scheme = "Catppuccin Latte"
config.font = wezterm.font("DejaVuSansM Nerd Font Mono")
config.term = "xterm-256color"
config.window_close_confirmation = "NeverPrompt"
config.scrollback_lines = 20000
config.automatically_reload_config = true

config.disable_default_key_bindings = true
config.disable_default_mouse_bindings = true

config.default_prog = wsl_default_prog()
config.enable_kitty_keyboard = true
config.allow_win32_input_mode = false
config.enable_csi_u_key_encoding = false
config.treat_left_ctrlalt_as_altgr = false

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

config.mouse_bindings = {
	{
		event = { Down = { streak = 1, button = "Right" } },
		mods = "NONE",
		action = act.PasteFrom("Clipboard"),
	},
}

return config
