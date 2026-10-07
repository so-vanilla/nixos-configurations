{ pkgs, ...}:
let
  hyprland = import ./hyprland;
  wireshark = import ./wireshark { inherit pkgs; };
  steam = import ./steam { inherit pkgs; };
  virt-manager = import ./virt-manager;
in
[
  hyprland
  wireshark
  steam
  virt-manager
]
