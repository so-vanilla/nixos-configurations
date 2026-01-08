{
  username,
  system,
  nixpkgs,
  nixpkgs-stable,
  zen-browser,
  catppuccin,
  my-emacs,
}:
let
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  pkgs-stable = import nixpkgs-stable {
    inherit system;
    config.allowUnfree = true;
  };
  zen-browser-pkg = zen-browser.packages.${system}.default;
  emacs-config = my-emacs.homeManagerModules.default {
    inherit system;
  };
  programs = import ./programs {
    inherit pkgs pkgs-stable;
  };
  services = import ./services {
    inherit pkgs;
  };
  wayland = import ./wayland;
  packages = import ./packages {
    inherit pkgs zen-browser-pkg;
  };
  cursor = import ./cursor {
    inherit pkgs;
  };
  i18n = import ./i18n {
    inherit pkgs;
  };
  dconf = import ./dconf;
in
{
  nixpkgs.config.allowUnfree = true;

  home = {
    username = username;
    homeDirectory = "/home/${username}";
    stateVersion = "23.11";
  };

  imports =
    [
      catppuccin.homeModules.catppuccin
      emacs-config
    ]
    ++ programs
    ++ services
    ++ wayland
    ++ packages
    ++ cursor
    ++ i18n
    ++ dconf;
}
