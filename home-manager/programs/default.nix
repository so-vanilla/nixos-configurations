{
  pkgs,
  pkgs-stable,
}:
let
  catppuccin-flavor = "latte";
  alacritty = import ./alacritty { inherit catppuccin-flavor; };
  awscli = import ./awscli;
  bat = import ./bat { inherit catppuccin-flavor; };
  btop = import ./btop { inherit catppuccin-flavor; };
  direnv = import ./direnv;
  discord = import ./discord;
  eza = import ./eza;
  fish = import ./fish { inherit pkgs catppuccin-flavor; };
  git = import ./git { email = "somura-vanilla@so-icecream.com"; };
  go = import ./go;
  gpg = import ./gpg;
  gradle = import ./gradle;
  home-manager = import ./home-manager;
  hyprlock = import ./hyprlock;
  java = import ./java;
  jq = import ./jq;
  mullvad-vpn = import ./mullvad-vpn { inherit pkgs-stable; };
  neovim = import ./neovim { inherit pkgs; };
  pandoc = import ./pandoc;
  ripgrep = import ./ripgrep;
  tofi = import ./tofi { inherit catppuccin-flavor; };
  vscode = import ./vscode;
  waybar = import ./waybar;
  zed-editor = import ./zed-editor;
in
[
  alacritty
  awscli
  bat
  btop
  direnv
  discord
  eza
  fish
  git
  go
  gpg
  gradle
  home-manager
  hyprlock
  java
  jq
  mullvad-vpn
  neovim
  pandoc
  ripgrep
  tofi
  vscode
  waybar
]
