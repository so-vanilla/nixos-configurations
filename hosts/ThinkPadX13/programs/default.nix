{ pkgs, ...}:
let
  hyprland = import ./hyprland;
  wireshark = import ./wireshark { inherit pkgs; };
  steam = import ./steam;
in
[
  hyprland
  wireshark
  steam
]
