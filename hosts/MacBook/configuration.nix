{
  nixpkgs,
  system,
  username,
}:
let
  hostname = "chocolate";
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
in
[
  {
    nix = {
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        substituters = [
          "https://nix-community.cachix.org"
          "https://cache.nixos.org/"
          "https://devenv.cachix.org"
        ];
        trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        ];
      };
      gc = {
        automatic = true;
        interval = {
          Weekday = 0;
          Hour = 2;
          Minute = 0;
        };
        options = "--delete-older-than 7d";
      };
    };

    networking.hostName = hostname;

    fonts.packages = with pkgs; [
      nerd-fonts.dejavu-sans-mono
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      ipafont
    ];

    users.users."${username}" = {
      home = "/Users/${username}";
      shell = pkgs.fish;
    };

    programs.fish.enable = true;

    services.nix-daemon.enable = true;

    system.stateVersion = 5;
  }
]
