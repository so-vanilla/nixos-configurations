{ nixpkgs, system, username, ... }:
let
  hostname = "vanilla";
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };

  services = import ./services;
  programs = import ./programs { inherit pkgs; };
  networking = import ./networkig { inherit pkgs hostname; };
  security = import ./security;
  virtualization = import ./virtualization;
  agenix = import ./agenix;
in
services
++ programs
++ networking
++ security
++ virtualization
++ agenix
++ [
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
        ];
        trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
      };
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 7d";
        persistent = true;
        randomizedDelaySec = "45min";
      };
    };

    boot = {
      loader = {
        systemd-boot.enable = true;
        efi.canTouchEfiVariables = true;
      };
      initrd.luks.devices."luks-6c4149ed-e1a9-4702-bdfc-745f13702367".device = "/dev/disk/by-uuid/6c4149ed-e1a9-4702-bdfc-745f13702367";
    };

    i18n.defaultLocale = "en_US.UTF-8";
    console = {
      font = "Lat2-Terminus16";
      keyMap = "us";
    };

    time.timeZone = "Asia/Tokyo";

    fonts.packages = with pkgs; [
      nerd-fonts.dejavu-sans-mono
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      ipafont
    ];

    users.users."${username}" = {
      isNormalUser = true;
      extraGroups = [ "wheel" "networkmanager" "libvirtd" "wireshark" "docker" ];
      ignoreShellProgramCheck = true;
      shell = pkgs.fish;
    };

    documentation.dev.enable = true;

    system.stateVersion = "24.11"; # Did you read the comment?
  }
]
