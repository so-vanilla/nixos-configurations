{
  inputs,
}:
let
  inherit (inputs)
    nixpkgs
    home-manager
    catppuccin
    my-emacs;
  username = builtins.getEnv "HM_USERNAME";
  system = "aarch64-darwin";

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
  pkgs = pkgs;
  
  modules =
    [
      {
        home = {
          username = username;
          homeDirectory = "/Users/${username}";
          stateVersion = "23.11";
        };
      }
      catppuccin.homeModules.catppuccin
      my-emacs.homeManagerModules.${system}.macport
    ]
    ++ programs
    ++ packages;
}
