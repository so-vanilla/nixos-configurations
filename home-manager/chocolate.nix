{
  username,
  system,
  nixpkgs,
  nix-index-database,
  zen-browser,
  catppuccin,
  my-neovim,
}:
let
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  neovim-config = my-neovim.homeManagerModules.${system}.default;
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
    neovim-config
  ]
  ++ programs
  ++ packages;
}
