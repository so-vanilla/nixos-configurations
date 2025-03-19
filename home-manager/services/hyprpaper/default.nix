{
  services.hyprpaper = {
      enable = true;
      settings = {
        ipc = "off";
        preload = [
          "~/repos/github.com/NixOS/nixos-artwork/wallpapers/nix-wallpaper-nineish.png"
        ];
        wallpaper = [
          # for ThinkPad X13
          # builtin HDMI port
          "HDMI-A-1, /home/somura/repos/github.com/NixOS/nixos-artwork/wallpapers/nix-wallpaper-nineish.png"

          # for ENVYx360-13
          # builtin monitor
          "eDP-1, /home/somura/repos/github.com/NixOS/nixos-artwork/wallpapers/nix-wallpaper-nineish.png"
          # USB Type-C/1 to HDMI adapter
          "DP-1, /home/somura/repos/github.com/NixOS/nixos-artwork/wallpapers/nix-wallpaper-nineish.png"
          # USB Type-C/2 to HDMI adapter
          "DP-2, /home/somura/repos/github.com/NixOS/nixos-artwork/wallpapers/nix-wallpaper-nineish.png"
        ];
      };
    };
}
