{
  catppuccin.zed.enable = false;

  programs.zed-editor = {
    enable = true;
    package = null;
    mutableUserSettings = false;
    mutableUserKeymaps = false;
    userSettings = builtins.fromJSON (builtins.readFile ./macos/settings.json);
    userKeymaps = builtins.fromJSON (builtins.readFile ./macos/keymap.json);
  };

  xdg.configFile = {
    "zed/settings.json".force = true;
    "zed/keymap.json".force = true;
  };
}
