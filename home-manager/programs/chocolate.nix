{ pkgs }:
let
  bat = import ./bat;
  btop = import ./btop;
  claude-code = import ./claude-code { inherit pkgs; };
  direnv = import ./direnv;
  eza = import ./eza;
  fish = import ./fish { inherit pkgs; };
  git = import ./git {
    inherit pkgs;
    email = "shuto-vanilla@so-icecream.com";
  };
  gpg = import ./gpg;
  home-manager = import ./home-manager;
  nix-index-database = import ./nix-index-database;
  ripgrep = import ./ripgrep;
  vscode = import ./vscode;
in
[
  bat
  btop
  claude-code
  direnv
  eza
  fish
  git
  gpg
  home-manager
  nix-index-database
  ripgrep
  vscode
]
