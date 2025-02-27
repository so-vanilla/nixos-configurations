{
  pkgs,
}:
let
  catppuccin-flavor = "latte";
  alacritty = import ./alacritty { inherit catppuccin-flavor; };
  bat = import ./bat { inherit catppuccin-flavor; };
  btop = import ./btop { inherit catppuccin-flavor; };
  direnv = import ./direnv;
  emacs = import ./emacs { inherit pkgs; };
  eza = import ./eza;
  fish = import ./fish { inherit pkgs catppuccin-flavor; };
  git = import ./git;
  go = import ./go;
  gradle = import ./gradle;
  home-manager = import ./home-manager;
  hyprlock = import ./hyprlock;
  java = import ./java;
  jq = import ./jq;
  pandoc = import ./pandoc;
  ripgrep = import ./ripgrep;
  tofi = import ./tofi { inherit catppuccin-flavor; };
  waybar = import ./waybar;
in
[
  alacritty
  bat
  btop
  direnv
  emacs
  eza
  fish
  git
  go
  gradle
  home-manager
  hyprlock
  java
  jq
  pandoc
  ripgrep
  tofi
  waybar
]
