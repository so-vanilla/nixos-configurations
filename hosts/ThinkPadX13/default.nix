{
  inputs
}:
let
  inherit (inputs)
    nixpkgs
    nixpkgs-stable
    catppuccin
    agenix;
  username = "somura";
  system = "x86_64-linux";
in
nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = { inherit username; };
  modules =
    import ./configuration.nix { inherit nixpkgs nixpkgs-stable system username; }
    ++ [
      ./hardware-configuration.nix
      catppuccin.nixosModules.catppuccin
      agenix.nixosModules.default

      inputs.home-manager.nixosModules.home-manager
      {
        home-manager.useUserPackages = true;
        home-manager.users."${username}" = import ../../home-manager {
          inherit username system;
          inherit (inputs) nixpkgs nixpkgs-stable emacs-overlay zen-browser catppuccin;
        };
      }
    ];
}
