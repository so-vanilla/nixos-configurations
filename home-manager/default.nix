{
  username,
  system,
  nixpkgs,
  nixpkgs-stable,
  emacs-overlay,
  zen-browser,
  catppuccin,
}:
let
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [
      (import emacs-overlay)
    ];
  };
  pkgs-stable = import nixpkgs-stable {
    inherit system;
    config.allowUnfree = true;
  };
  zen-browser-pkg = zen-browser.packages.${system}.default;
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
    ]
    ++ programs
    ++ services
    ++ wayland
    ++ packages
    ++ cursor
    ++ i18n
    ++ dconf;
}
