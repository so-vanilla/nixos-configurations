{
  inputs,
}:
let
  inherit (inputs)
    nixpkgs
    home-manager
    catppuccin
    nix-index-database
    my-neovim
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
    }
    catppuccin.homeModules.catppuccin
    nix-index-database.homeModules.default
    my-neovim.homeManagerModules.${system}.default
  ]
  ++ programs
  ++ packages;
}
