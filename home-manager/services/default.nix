let
  emacs = import ./emacs;
  hyprpaper = import ./hyprpaper;
  playerctld = import ./playerctld;
  remmina = import ./remmina;
  swaync = import ./swaync;
  nm-applet = import ./network-manager-applet;
in
[
  emacs
  hyprpaper
  playerctld
  nm-applet
  remmina
  swaync
]
