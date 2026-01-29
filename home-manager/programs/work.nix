{
  pkgs,
}:
let
  catppuccin-flavor = "latte";
  alacritty = import ./alacritty { inherit catppuccin-flavor; };
  awscli = import ./awscli;
  bat = import ./bat { inherit catppuccin-flavor; };
  btop = import ./btop { inherit catppuccin-flavor; };
  claude-code = import ./claude-code;
  direnv = import ./direnv;
  eza = import ./eza;
  fish = import ./fish { inherit pkgs catppuccin-flavor; };
  git = import ./git { email = builtins.getEnv "HM_GIT_EMAIL"; };
  go = import ./go;
  gpg = import ./gpg;
  gradle = import ./gradle;
  home-manager = import ./home-manager;
  hyprlock = import ./hyprlock;
  java = import ./java;
  jq = import ./jq;
  neovim = import ./neovim { inherit pkgs; };
  ripgrep = import ./ripgrep;
in
[
  alacritty
  awscli
  bat
  btop
  claude-code
  direnv
  eza
  fish
  git
  go
  gpg
  gradle
  home-manager
  java
  jq
  neovim
  ripgrep
]
