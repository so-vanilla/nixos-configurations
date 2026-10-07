{
  services.hyprpaper = {
      enable = true;
      settings = {
        ipc = "off";
        preload = [
          "~/repos/github.com/NixOS/nixos-artwork/wallpapers/nix-wallpaper-nineish.png"
        ];
        wallpaper = [
          {
            monitor = "eDP-1";
            path = "/home/somura/repos/github.com/NixOS/nixos-artwork/wallpapers/nix-wallpaper-nineish.png";
          }
          {
            monitor = "DP-1";
            path = "/home/somura/repos/github.com/NixOS/nixos-artwork/wallpapers/nix-wallpaper-nineish.png";
          }
          {
            monitor = "DP-2";
            path = "/home/somura/repos/github.com/NixOS/nixos-artwork/wallpapers/nix-wallpaper-nineish.png";
          }
          {
            monitor = "HDMI-A-1";
            path = "/home/somura/repos/github.com/NixOS/nixos-artwork/wallpapers/nix-wallpaper-nineish.png";
          }
        ];
      };
    };
}
