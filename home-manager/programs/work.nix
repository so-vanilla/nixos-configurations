{
  pkgs,
}:
let
  catppuccin-flavor = "latte";
  bat = import ./bat { inherit catppuccin-flavor; };
  btop = import ./btop { inherit catppuccin-flavor; };
  claude-code = import ./claude-code { inherit pkgs; };
  direnv = import ./direnv;
  eza = import ./eza;
  fish = import ./fish { inherit pkgs catppuccin-flavor; };
  git = import ./git {
    inherit pkgs;
    email = builtins.getEnv "HM_GIT_EMAIL";
  };
  gpg = import ./gpg;
  home-manager = import ./home-manager;
  nix-index-database = import ./nix-index-database;
  ripgrep = import ./ripgrep;
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
]
