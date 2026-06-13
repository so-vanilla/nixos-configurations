{
  pkgs,
}:
let
  gpg-agent = import ./gpg-agent { inherit pkgs; };
  hyprpaper = import ./hyprpaper;
  playerctld = import ./playerctld;
  remmina = import ./remmina;
  swaync = import ./swaync;
  nm-applet = import ./network-manager-applet;
  kdeconnect = import ./kdeconnect;
in
[
  gpg-agent
  hyprpaper
  playerctld
  nm-applet
  remmina
  swaync
  kdeconnect
]
