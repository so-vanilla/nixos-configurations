{ pkgs-stable }:
let
  ssh = ./ssh;
  gnome = ./gnome;
  logind = ./logind;
  xserver = ./xserver;
  pipewire = ./pipewire;
  displayManager = ./displayManager;
  mullvad-vpn = import ./mullvad-vpn { inherit pkgs-stable; };
in
[
  ssh
  gnome
  logind
  xserver
  pipewire
  displayManager
  mullvad-vpn
]
