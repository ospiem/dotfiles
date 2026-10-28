local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Fonts (uncomment one to switch)
config.font = wezterm.font_with_fallback({
  "JetBrainsMono Nerd Font",
  "Symbols Nerd Font Mono",  -- fallback для иконок
})
config.font_size = 15.0

-- Window appearance
config.window_background_opacity = 0.88 -- Make the background slightly transparent
config.colors = {
  background = "#0f0f0f",
}
config.window_decorations = "RESIZE" -- Only show the resize border, no title bar
config.enable_tab_bar = true -- Show the tab bar
config.hide_tab_bar_if_only_one_tab = true -- Hide the tab bar if only one tab is open
--config.color_scheme = "Catppuccin Mocha"
-- Scrollback buffer
config.scrollback_lines = 5000 -- Number of scrollback lines to keep

-- Miscellaneous
config.audible_bell = "Disabled" -- Disable the audible bell

-- Set a custom window frame appearance
config.window_frame = {
	active_titlebar_bg = "#282828", -- Background color of the title bar
	inactive_titlebar_bg = "#1d2021", -- Background color of inactive windows
}

-- Performance settings
config.max_fps = 120
config.prefer_egl = true

config.window_close_confirmation = "NeverPrompt"

-- Layout-independent Alt bindings: при любой раскладке Alt+<физическая клавиша>
-- шлётся как Alt+<латинская буква>, что и ждёт zellij.
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false
config.use_ime = false
config.key_map_preference = "Physical"

local function alt_passthrough(letters)
  local keys = {}
  for letter in letters:gmatch(".") do
    table.insert(keys, {
      key = "phys:" .. letter:upper(),
      mods = "ALT",
      action = wezterm.action.SendKey({ key = letter, mods = "ALT" }),
    })
  end
  return keys
end

config.keys = alt_passthrough("hjklionfp")
for _, extra in ipairs({
  { key = "phys:LeftBracket",  mods = "ALT", action = wezterm.action.SendKey({ key = "[", mods = "ALT" }) },
  { key = "phys:RightBracket", mods = "ALT", action = wezterm.action.SendKey({ key = "]", mods = "ALT" }) },
  { key = "phys:Minus",        mods = "ALT", action = wezterm.action.SendKey({ key = "-", mods = "ALT" }) },
  { key = "phys:Equal",        mods = "ALT", action = wezterm.action.SendKey({ key = "=", mods = "ALT" }) },
  { key = "phys:0",            mods = "ALT", action = wezterm.action.SendKey({ key = "0", mods = "ALT" }) },
}) do
  table.insert(config.keys, extra)
end

return config
