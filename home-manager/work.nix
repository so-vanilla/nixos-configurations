{
  inputs,
}:
let
  inherit (inputs)
    nixpkgs
    nixpkgs-stable
    home-manager-stable
    catppuccin
    nix-index-database
    my-emacs
    ;
  username = builtins.getEnv "HM_USERNAME";
  system = "aarch64-darwin";

  pkgs = import nixpkgs-stable {
    inherit system;
    config.allowUnfree = true;
  };
  pkgs-unstable = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  programs = import ./programs/work.nix {
    inherit pkgs pkgs-unstable;
  };
  packages = import ./packages/work.nix {
    inherit pkgs;
  };
in
home-manager-stable.lib.homeManagerConfiguration {
  pkgs = pkgs;

  modules = [
    {
      home = {
        username = username;
        homeDirectory = "/Users/${username}";
        stateVersion = "23.11";
      };
    }
    catppuccin.homeModules.catppuccin
    nix-index-database.homeModules.default
    my-emacs.homeManagerModules.${system}.stable
  ]
  ++ programs
  ++ packages;
}
