{ pkgs, ...}:
let
  hyprland = ./hyprland;
  wireshark = import ./wireshark { inherit pkgs; };
in
[
  hyprland
  wireshark
]
