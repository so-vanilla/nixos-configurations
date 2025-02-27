{
  mainBar = {
    layer = "bottom";
    position = "top";
    height = 32;
    spacing = 0;

    modules-left = [
      "network"
      "wireplumber"
      "backlight"
      "battery"
    ];
    modules-center = [ "hyprland/workspaces" ];
    modules-right = [
      "clock"
      "tray"
      "custom/notification"
    ];

    network = {
      format-wifi = "{essid} ({signalStrength}%) ";
      format-ethernet = "{ipaddr}/{cidr} 󰈀";
      format-disconnected = "Disconnected ⚠";
      format-alt = "{ifname}: {ipaddr}/{cidr}";
    };

    backlight = {
      format = "{percent}% {icon}";
      format-icons = [
        ""
        ""
        ""
        ""
        ""
        ""
        ""
        ""
        ""
      ];
    };

    wireplumber = {
      format = "{volume}% {icon}";
      format-muted = "";
      on-click = "helvum";
      format-icons = [
        ""
        ""
        ""
      ];
    };

    battery = {
      states = {
        warning = 30;
        critical = 15;
      };
      format = "{capacity}% {icon}";
      format-charging = "{capacity}% 󰂄";
      format-plugged = "{capacity}% ";
      format-alt = "{time} {icon}";
      format-icons = [
        ""
        ""
        ""
        ""
        ""
      ];
    };

    "hyprland/workspaces" = {
      format = "{windows}";
      window-rewrite-default = "";
    };

    clock = {
      tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
      format-alt = "{:%Y-%m-%d}";
    };

    tray = {
      spacing = 10;
    };

    "custom/notification" = {
      tooltip = false;
      format = "{icon}";
      format-icons = {
        notification = "<span foreground='red'><sup></sup></span> ";
        none = " ";
        dnd-notification = "<span foreground='red'><sup></sup></span> ";
        dnd-none = " ";
        inhibited-notification = "<span foreground='red'><sup></sup></span> ";
        inhibited-none = " ";
        dnd-inhibited-notification = "<span foreground='red'><sup></sup></span> ";
        dnd-inhibited-none = " ";
      };
      return-type = "json";
      exec-if = "which swaync-client";
      exec = "swaync-client -swb";
      on-click = "swaync-client -t -sw";
      on-click-right = "swaync-client -d -sw";
      escape = true;
    };
  };
}
