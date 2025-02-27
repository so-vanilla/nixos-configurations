let
  emacs = import ./emacs;
  hyprpaper = import ./hyprpaper;
  remmina = import ./remmina;
  swaync = import ./swaync;
  nm-applet = import ./network-manager-applet;
in
[
  emacs
  hyprpaper
  nm-applet
  remmina
  swaync
]
