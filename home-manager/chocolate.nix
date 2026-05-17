{
  username,
  system,
  nixpkgs,
  nix-index-database,
  zen-browser,
  catppuccin,
  my-emacs,
}:
let
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  emacs-config = my-emacs.homeManagerModules.${system}.macport;
  programs = import ./programs/chocolate.nix { inherit pkgs; };
  packages = import ./packages/chocolate.nix { inherit pkgs zen-browser system; };
in
{
  nixpkgs.config.allowUnfree = true;

  home = {
    username = username;
    homeDirectory = "/Users/${username}";
    stateVersion = "23.11";
  };

  imports = [
    catppuccin.homeModules.catppuccin
    nix-index-database.homeModules.default
    emacs-config
  ]
  ++ programs
  ++ packages;
}
