let
  settings = import ./settings.nix;
  extraConfigs = ''
    env = GTK_IM_MODULE,fcitx
    env = QT_IM_MODULE,fcitx
    env = XMODIFIERS,@im=fcitx
    bind = $mod, R, submap, resize
    submap = resize
    binde = , l, resizeactive, 10 0
    binde = , h, resizeactive, -10 0
    binde = , k, resizeactive, 0 -10
    binde = , j, resizeactive, 0 10
    bind = , escape, submap, reset
    submap = reset
  '';
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    systemd = {
      enable = true;
      enableXdgAutostart = true;
    };
    xwayland.enable = true;
    settings = settings;
    extraConfig = extraConfigs;
  };

  catppuccin.hyprland = {
    enable = true;
    flavor = "latte";
    accent = "pink";
  };
  home.file = {
    ".config/hypr/scripts" = {
      source = ./scripts;
      recursive = true;
      executable = true;
    };
  };
}
