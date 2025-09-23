{
  "$mod" = "SUPER";
  "$terminal" = "alacritty";
  "$fileManager" = "dolphin";
  "$menu" = "tofi-drun --drun-launch=true";
  "$www_client" = "zen";
  "$www_client_private" = "zen --private-window";
  "$mail_client" = "command -v thunderbird > /dev/null 2>&1 && thunderbird || thunderbird-bin";

  general = {
    gaps_in = 5;
    gaps_out = 8;
    border_size = 2;
    "col.active_border" = "0xfff5c2e7";
    "col.inactive_border" = "0xff313244";
    layout = "dwindle";
    allow_tearing = false;
  };

  decoration = {
    rounding = 8;
    blur = {
      enabled = true;
      size = 3;
      passes = 1;
    };
    shadow = {
      enabled = true;
      range = 4;
      render_power = 3;
      color = "0xff313244";
    };
  };

  animations = {
    enabled = "yes";
    bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";
    animation = [
      "windows, 1, 7, myBezier"
      "windowsOut, 1, 7, default, popin 80%"
      "border, 1, 10, default"
      "borderangle, 1, 8, default"
      "fade, 1, 7, default"
      "workspaces, 1, 6, default"
    ];
  };

  input = {
    kb_layout = "us";
    kb_variant = "";
    kb_model = "";
    kb_options = "ctrl:nocaps";
    kb_rules = "";
    follow_mouse = 3;
    touchpad = {
      natural_scroll = "no";
      disable_while_typing = true;
      scroll_factor = 0.5;
      tap-and-drag = false;
    };
    sensitivity = 0;
  };

  dwindle = {
    pseudotile = "yes";
    preserve_split = "yes";
  };

  # master = {
  # new_is_master = true;
  # };

  # gestures = {
  #   workspace_swipe = false;
  # };

  misc = {
    force_default_wallpaper = -1;
  };

  xwayland = {
    force_zero_scaling = true;
  };

  monitor = [
    "Unknown-1,disable"
  ];

  windowrulev2 = "opacity 0.7 0.7,class:^(org.wezfurlong.wezterm)$";
  windowrule = [
    "workspace 3, class:thunderbird"
    "workspace 4, class:Slack"
    "workspace 5, class:discord"
  ];

  exec-once = [
    "swaync"
    "waybar"
    "hyprpaper"
    "wl-paste --type text --watch cliphist store"
    "wl-paste --type image --watch cliphist store"
  ];

  bind = [
    ",XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"
    ",XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
    ",XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
    ",XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
    ",XF86AudioPlay, exec, playerctl play-pause"
    ",XF86AudioNext, exec, playerctl next"
    ",XF86AudioPrev, exec, playerctl previous"
    ",XF86MonBrightnessUp, exec, brightnessctl set +5%"
    ",XF86MonBrightnessDown, exec, brightnessctl set 5%-"

    "$mod SHIFT, Q, exit, "
    "$mod SHIFT, Delete, exec, hyprlock & systemctl suspend"
    "$mod, C, killactive, "
    "$mod, V, togglefloating, "
    "$mod, T, togglesplit,"
    "$mod, F, fullscreen,"
    "$mod, E, exec, emacsclient -c"
    "$mod, RETURN, exec, $terminal"
    "$mod, B, exec, $www_client"
    "$mod SHIFT, B, exec, $www_client_private"
    "$mod, SPACE, exec, $menu"
    "$mod, S, exec, slack"
    "$mod, M, exec, $mail_client"
    "$mod, A, exec, ~/.config/hypr/scripts/launch_apps.sh"

    "$mod, l, movefocus, r"
    "$mod, h, movefocus, l"
    "$mod, k, movefocus, u"
    "$mod, j, movefocus, d"

    "$mod SHIFT, l, movewindow, r"
    "$mod SHIFT, h, movewindow, l"
    "$mod SHIFT, k, movewindow, u"
    "$mod SHIFT, j, movewindow, d"

    "$mod, 1, workspace, 1"
    "$mod, 2, workspace, 2"
    "$mod, 3, workspace, 3"
    "$mod, 4, workspace, 4"
    "$mod, 5, workspace, 5"
    "$mod, 6, workspace, 6"
    "$mod, 7, workspace, 7"
    "$mod, 8, workspace, 8"
    "$mod, 9, workspace, 9"
    "$mod, 0, workspace, 10"

    "$mod SHIFT, 1, movetoworkspace, 1"
    "$mod SHIFT, 2, movetoworkspace, 2"
    "$mod SHIFT, 3, movetoworkspace, 3"
    "$mod SHIFT, 4, movetoworkspace, 4"
    "$mod SHIFT, 5, movetoworkspace, 5"
    "$mod SHIFT, 6, movetoworkspace, 6"
    "$mod SHIFT, 7, movetoworkspace, 7"
    "$mod SHIFT, 8, movetoworkspace, 8"
    "$mod SHIFT, 9, movetoworkspace, 9"
    "$mod SHIFT, 0, movetoworkspace, 10"

    # scratch pad
    "$mod, O, togglespecialworkspace"
    "$mod SHIFT, O, movetoworkspace, special"
  ];

  bindm = [
    "$mod, mouse:272, movewindow"
    "$mod, mouse:273, resizewindow"
  ];
}
