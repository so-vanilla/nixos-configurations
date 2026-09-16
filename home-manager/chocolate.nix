{
  username,
  system,
  nixpkgs,
  nix-index-database,
  zen-browser,
  catppuccin,
  my-claude,
}:
let
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  claude-config = my-claude.homeManagerModules.default;
  programs = import ./programs/chocolate.nix { inherit pkgs; };
  packages = import ./packages/chocolate.nix { inherit pkgs zen-browser system; };
in
{
  nixpkgs.config.allowUnfree = true;

  targets.darwin = {
    linkApps.enable = false;
    copyApps.enable = true;
  };

  catppuccin = {
    enable = true;
    autoEnable = true;
    flavor = "latte";
    accent = "pink";
  };

  home = {
    username = username;
    homeDirectory = "/Users/${username}";
    stateVersion = "23.11";
    sessionVariables = {
      EDITOR = nixpkgs.lib.mkForce "zed --wait";
      VISUAL = nixpkgs.lib.mkForce "zed --wait";
    };
  };

  imports = [
    catppuccin.homeModules.catppuccin
    nix-index-database.homeModules.default
    claude-config
  ]
  ++ programs
  ++ packages;
}
