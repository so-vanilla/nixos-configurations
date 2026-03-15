{ pkgs }:
let
  catppuccin-flavor = "latte";
  alacritty = import ./alacritty { inherit catppuccin-flavor; };
  bat = import ./bat { inherit catppuccin-flavor; };
  btop = import ./btop { inherit catppuccin-flavor; };
  claude-code = import ./claude-code { inherit pkgs; };
  direnv = import ./direnv;
  discord = import ./discord;
  eza = import ./eza;
  fish = import ./fish { inherit pkgs catppuccin-flavor; };
  git = import ./git {
    inherit pkgs;
    email = "somura-vanilla@so-icecream.com";
  };
  gpg = import ./gpg;
  home-manager = import ./home-manager;
  hyprlock = import ./hyprlock;
  neovim = import ./neovim { inherit pkgs; };
  nix-index-database = import ./nix-index-database;
  ripgrep = import ./ripgrep;
  tofi = import ./tofi { inherit catppuccin-flavor; };
  vscode = import ./vscode;
  waybar = import ./waybar;
in
[
  alacritty
  bat
  btop
  claude-code
  direnv
  discord
  eza
  fish
  git
  gpg
  home-manager
  hyprlock
  neovim
  nix-index-database
  ripgrep
  tofi
  vscode
  waybar
]
