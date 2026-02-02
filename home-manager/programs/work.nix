{
  pkgs,
}:
let
  catppuccin-flavor = "latte";
  alacritty = import ./alacritty { inherit catppuccin-flavor; };
  bat = import ./bat { inherit catppuccin-flavor; };
  btop = import ./btop { inherit catppuccin-flavor; };
  claude-code = import ./claude-code;
  direnv = import ./direnv;
  eza = import ./eza;
  fish = import ./fish { inherit pkgs catppuccin-flavor; };
  git = import ./git {
    inherit pkgs;
    email = builtins.getEnv "HM_GIT_EMAIL";
  };
  gpg = import ./gpg;
  home-manager = import ./home-manager;
  neovim = import ./neovim { inherit pkgs; };
  nix-index-database = import ./nix-index-database;
  ripgrep = import ./ripgrep;
in
[
  alacritty
  bat
  btop
  claude-code
  direnv
  eza
  fish
  git
  gpg
  home-manager
  neovim
  nix-index-database
  ripgrep
]
