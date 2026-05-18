{
  inputs,
}:
let
  inherit (inputs)
    nixpkgs
    nix-darwin
    nix-index-database
    catppuccin
    my-emacs
    zen-browser
    ;
  username = "shuto-vanilla";
  system = "aarch64-darwin";
in
nix-darwin.lib.darwinSystem {
  inherit system;
  specialArgs = { inherit username; };
  modules =
    import ./configuration.nix {
      inherit
        nixpkgs
        system
        username
        ;
    }
    ++ [
      ./homebrew
      inputs.home-manager.darwinModules.home-manager
      {
        home-manager.useUserPackages = true;
        home-manager.users."${username}" = import ../../home-manager/chocolate.nix {
          inherit username system;
          inherit (inputs)
            nixpkgs
            nix-index-database
            zen-browser
            catppuccin
            my-emacs
            ;
        };
      }
    ];
}
