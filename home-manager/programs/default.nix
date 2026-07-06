{ pkgs }:
let
  bat = import ./bat;
  btop = import ./btop;
  claude-code = import ./claude-code { inherit pkgs; };
  direnv = import ./direnv;
  discord = import ./discord;
  eza = import ./eza;
  fish = import ./fish { inherit pkgs; };
  git = import ./git {
    inherit pkgs;
    email = "somura-vanilla@so-icecream.com";
  };
  gpg = import ./gpg;
  home-manager = import ./home-manager;
  hyprlock = import ./hyprlock;
  marksman = import ./marksman;
  nix-index-database = import ./nix-index-database;
  ripgrep = import ./ripgrep;
  tofi = import ./tofi;
  vscode = import ./vscode;
  waybar = import ./waybar;
in
[
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
  marksman
  nix-index-database
  ripgrep
  tofi
  vscode
  waybar
]
