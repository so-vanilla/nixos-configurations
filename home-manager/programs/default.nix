{
  pkgs,
  pkgs-stable,
}:
let
  catppuccin-flavor = "latte";
  alacritty = import ./alacritty { inherit catppuccin-flavor; };
  bat = import ./bat { inherit catppuccin-flavor; };
  btop = import ./btop { inherit catppuccin-flavor; };
  claude-code = import ./claude-code;
  direnv = import ./direnv;
  discord = import ./discord;
  eza = import ./eza;
  fish = import ./fish { inherit pkgs catppuccin-flavor; };
  git = import ./git { email = "somura-vanilla@so-icecream.com"; };
  gpg = import ./gpg;
  home-manager = import ./home-manager;
  hyprlock = import ./hyprlock;
  mullvad-vpn = import ./mullvad-vpn { inherit pkgs-stable; };
  neovim = import ./neovim { inherit pkgs; };
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
  mullvad-vpn
  neovim
  ripgrep
  tofi
  vscode
  waybar
]
