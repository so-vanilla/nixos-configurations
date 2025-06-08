let
  emacs = import ./emacs;
  gpg-agent = import ./gpg-agent;
  hyprpaper = import ./hyprpaper;
  playerctld = import ./playerctld;
  remmina = import ./remmina;
  swaync = import ./swaync;
  nm-applet = import ./network-manager-applet;
  kdeconnect = import ./kdeconnect;
in
[
  emacs
  gpg-agent
  hyprpaper
  playerctld
  nm-applet
  remmina
  swaync
  kdeconnect
]
