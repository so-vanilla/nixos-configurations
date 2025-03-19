{ pkgs, ...}:
let
  hyprland = import ./hyprland;
  wireshark = import ./wireshark { inherit pkgs; };
  steam = import ./steam { inherit pkgs; };
in
[
  hyprland
  wireshark
  steam
]
