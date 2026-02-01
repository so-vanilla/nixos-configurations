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
  git = import ./git { email = builtins.getEnv "HM_GIT_EMAIL"; };
  gpg = import ./gpg;
  home-manager = import ./home-manager;
  neovim = import ./neovim { inherit pkgs; };
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
  ripgrep
]
