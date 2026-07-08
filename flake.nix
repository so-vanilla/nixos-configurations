{
  description = "My NixOS configurations";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs?ref=nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager-stable = {
      url = "github:nix-community/home-manager?ref=release-25.11";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix.url = "github:ryantm/agenix";
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    catppuccin.url = "github:catppuccin/nix";

    my-claude = {
      url = "github:so-vanilla/flake-my-claude";
    };
    my-emacs = {
      url = "github:so-vanilla/flake-my-emacs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    my-neovim = {
      url = "github:so-vanilla/flake-my-neovim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      flake = {
        nixosConfigurations = {
          vanilla = import ./hosts/ThinkPadX13 { inherit inputs; };
        };
        darwinConfigurations = {
          chocolate = import ./hosts/MacBook { inherit inputs; };
        };
        homeConfigurations = {
          "work" = import ./home-manager/work.nix { inherit inputs; };
        };
      };
    };
}
