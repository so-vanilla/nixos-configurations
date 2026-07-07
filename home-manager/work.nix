{
  inputs,
}:
let
  inherit (inputs)
    nixpkgs
    home-manager
    catppuccin
    nix-index-database
    my-emacs
    ;
  username = builtins.getEnv "HM_USERNAME";
  system = "x86_64-linux";

  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  programs = import ./programs/work.nix {
    inherit pkgs;
  };
  packages = import ./packages/work.nix {
    inherit pkgs;
  };
in
home-manager.lib.homeManagerConfiguration {
  inherit pkgs;

  modules = [
    {
      home = {
        username = username;
        homeDirectory = "/home/${username}";
        stateVersion = "23.11";
      };

      home.file.".config/nix/nix.conf".text = ''
        extra-experimental-features = nix-command flakes
        extra-substituters = https://nix-community.cachix.org https://catppuccin.cachix.org
        extra-trusted-public-keys = nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs= catppuccin.cachix.org-1:noG/4HkbhJb+lUAdKrph6LaozJvAeEEZj4N732IysmU=
      '';

      catppuccin = {
        enable = true;
        autoEnable = true;
        flavor = "latte";
        accent = "pink";
      };
    }
    catppuccin.homeModules.catppuccin
    nix-index-database.homeModules.default
    my-emacs.homeManagerModules.${system}.default
  ]
  ++ programs
  ++ packages;
}
